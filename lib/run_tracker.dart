import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // HapticFeedback + rootBundle
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'package:run_walk_app/service/service/gamification_service.dart';
import 'package:run_walk_app/service/achievement_service.dart';

import 'widgets/main_scaffold.dart';

// Som (apenas Wear OS usará)
import 'package:audioplayers/audioplayers.dart';

class Character3D extends StatelessWidget {
  final double bearing;

  const Character3D({super.key, required this.bearing});

  @override
  Widget build(BuildContext context) {
    return ModelViewer(
      src: 'assets/models/runner.glb',
      backgroundColor: Colors.transparent,
      disableZoom: true,
      cameraControls: false,
      autoPlay: true,
      animationName: "Run",
      autoRotate: false,

      // 📸 Ajustes finos:
      // - 180° pra virar o personagem “de frente pra frente do mapa”
      // - 3m de distância pra mostrar o corpo todo
      // - alvo da câmera levemente mais alto (1.7m)
      cameraOrbit: "${(bearing + 180).toStringAsFixed(0)}deg 65deg 3m",
      cameraTarget: "0m 1.7m 0m",
      fieldOfView: "28deg",
      exposure: 1.2,
      disableTap: true,
    );
  }
}

class FuturisticChrono extends StatefulWidget {
  final int seconds;
  final double fontSize;
  const FuturisticChrono({
    super.key,
    required this.seconds,
    this.fontSize = 68,
  });

  @override
  State<FuturisticChrono> createState() => _FuturisticChronoState();
}

class _FuturisticChronoState extends State<FuturisticChrono>
    with SingleTickerProviderStateMixin {



  late final AnimationController _glowCtrl;

  @override
  void initState() {
    super.initState();
    _checkAchievementsOnLoad();

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
      lowerBound: 0.2,
      upperBound: 0.9,
    )..repeat(reverse: true);
  }

  Future<void> _checkAchievementsOnLoad() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Checa se o usuário tem corridas registradas
    final query = await FirebaseFirestore.instance
        .collection('corridas')
        .where('userId', isEqualTo: user.uid)
        .get();

    if (query.docs.isNotEmpty) {
      // Garante que a “Primeira Corrida” seja desbloqueada mesmo se o app foi fechado antes
      await AchievementService().checkAchievements(
        runData: {
          'distance': query.docs.last['distance'],
          'pace': query.docs.last['pace'],
        },
      );
    }
  }



  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  String _format(int totalSeconds) {
    final h = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final time = _format(widget.seconds);

    return AnimatedBuilder(
      animation: _glowCtrl,
      builder: (context, _) {
        final glow = _glowCtrl.value;

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position:
              Tween<Offset>(begin: const Offset(0, .15), end: Offset.zero)
                  .animate(anim),
              child: child,
            ),
          ),
          child: ShaderMask(
            key: ValueKey(time),
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF4A90E2),
                Color(0xFF007AFF),
              ],
            ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
            blendMode: BlendMode.srcIn,
            child: Text(
              time,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: widget.fontSize,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                shadows: [
                  Shadow(
                    blurRadius: 20 + 10 * glow,
                    color: const Color(0xFF4A90E2).withOpacity(0.5 * glow),
                  ),
                  Shadow(
                    blurRadius: 30 + 15 * glow,
                    color: const Color(0xFF007AFF).withOpacity(0.4 * glow),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class RunTrackingPage extends StatefulWidget {
  const RunTrackingPage({super.key});


  @override
  State<RunTrackingPage> createState() => _RunTrackingPageState();
}

class _RunTrackingPageState extends State<RunTrackingPage>
    with SingleTickerProviderStateMixin {
  double _slideDragValue = 0.0;

  bool _isOnline = true;
  StreamSubscription<Position>? _onlinePositionStream;
  LatLng? _lastSavedPositionOnline;
  bool _isChallengePanelVisible = true;

  bool _mapReady = false;
  bool _followUser = true; // 🔓 controla se o mapa deve seguir automaticamente
  bool _isProgrammaticCameraMove = false; // 👈 controla se o movimento é automático
  bool _userIsMovingMap = false;

  Map<String, dynamic>? _activeChallenge;
  String? _activeChallengeId;

  OverlayEntry? _radialMenuOverlay;
  Timer? _longPressTimer;
  bool _isHoldingMarker = false;
  Offset? _markerScreenPosition;

  String _areaCapturedFormatted = "0 m²";

  final Set<Polygon> _territoryPolygons = {}; // 🟩 Territórios salvos

  // 🟩 NOVO: Área conquistada
  final Set<Polygon> _polygons = {};
  double _areaCaptured = 0;

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _challengeStream;
  Map<String, dynamic>? _activeChallengeData;

  Future<bool> _userHasActiveChallenge() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final now = DateTime.now();
      final qs = await FirebaseFirestore.instance
          .collection('challenges')
          .where('participantsIds', arrayContains: user.uid)
          .where('deadline', isGreaterThan: Timestamp.fromDate(now))
          .limit(1)
          .get();

      if (qs.docs.isEmpty) return false;

      // (Opcional) checar status do participante
      final doc = qs.docs.first;
      final partRef = doc.reference.collection('participants').doc(user.uid);
      final partSnap = await partRef.get();
      if (!partSnap.exists) return true;

      final status = (partSnap.data()?['status'] ?? 'active') as String;
      return status == 'active';
    } catch (e) {
      debugPrint('Erro ao verificar desafio ativo: $e');
      return false;
    }
  }


  Future<void> _setOfflineOnExit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'isOnline': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      debugPrint("📴 Usuário marcado como offline ao encerrar o app");
    } catch (e) {
      debugPrint("Erro ao marcar offline ao sair: $e");
    }
  }


  Future<void> _listenToActiveChallenge() async {
    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;

      final query = await FirebaseFirestore.instance
          .collection('posts')
          .where('type', isEqualTo: 'challenge')
          .get();

      DocumentSnapshot<Map<String, dynamic>>? foundDoc;

      for (var doc in query.docs) {
        final data = doc.data();
        final participants = (data['participants'] ?? []) as List<dynamic>;
        final quitters = (data['quitters'] ?? []) as List<dynamic>? ?? [];

        // 🔹 O jogador participa e não desistiu
        if (participants.contains(userId) && !quitters.contains(userId)) {
          foundDoc = doc;
          break;
        }
      }

      if (foundDoc != null) {
        setState(() {
          _activeChallengeId = foundDoc!.id;
          _challengeStream = FirebaseFirestore.instance
              .collection('posts')
              .doc(foundDoc.id)
              .snapshots();
        });
      }
    } catch (e) {
      debugPrint("❌ Erro ao escutar desafio ativo: $e");
    }
  }





  Future<void> _recenterMap() async {
    if (_googleMapController == null) return;

    // Se estiver em execução, centraliza na posição atual em movimento;
    // senão, centraliza na última posição conhecida.
    final target = _currentPosition;

    await _googleMapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: 17),
      ),
    );

    // Pequeno feedback tátil
    HapticFeedback.lightImpact();
  }

  // ===== Wear OS detection =====
  bool get isWearOS {
    final size = MediaQueryData.fromWindow(WidgetsBinding.instance.window).size;
    return size.shortestSide < 300; // heurística prática p/ relógios
  }

  bool loading = false;

  GoogleMapController? _googleMapController;

  Timer? _timer;
  int _seconds = 0;
  bool _isRunning = false;
  bool _runEnded = false;
  DateTime? _startTime;
  final Stopwatch _stopwatch = Stopwatch();

  final List<LatLng> _positions = [];
  double _totalDistance = 0;
  double _caloriesBurned = 0;
  int weeklyRunsCount = 0;
  int streakDays = 0;
  double _averagePace = 0; // min/km
  int _elapsedSeconds = 0;

  // 🎮 Controle de XP em tempo real
  int _sessionXP = 0;            // XP acumulado durante esta corrida
  int _nextXPThreshold = 100;    // Meta para vibração (ex: a cada 100 XP)
  double _distanceSinceLastXP = 0; // distância acumulada até o próximo ponto

  StreamSubscription<Position>? _positionStream;
  LatLng _currentPosition =
  const LatLng(-23.5505, -46.6333); // fallback (São Paulo)
  bool _loadingLocation = true;
  LocationPermission? _locationPermission;

  late AnimationController _animationController;
  LatLng? _previousPosition;
  LatLng? _animatedPosition;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};


  int _selectedIndex = 2;
  String? _mapStyle;

  // ===== Áudio (som digital suave) — apenas Wear OS =====
  final AudioPlayer _audio = AudioPlayer();
  Future<void> _playStart() async {
    if (!isWearOS) return;
    try {
      await HapticFeedback.lightImpact();
      await _audio.play(AssetSource('sounds/start.wav'));
    } catch (e) {
      debugPrint('Erro som start: $e');
    }
  }

  Future<void> _playStop() async {
    if (!isWearOS) return;
    try {
      await HapticFeedback.lightImpact();
      await _audio.play(AssetSource('sounds/stop.wav'));
    } catch (e) {
      debugPrint('Erro som stop: $e');
    }
  }

  @override
  void initState() {
    _initLocationFlow();

    super.initState();

    // Carrega estilo do mapa (mobile)
    rootBundle.loadString('assets/map_style.json').then((style) {
      _mapStyle = style;
    });

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addListener(() {
      if (_previousPosition != null && _animatedPosition != null) {
        setState(() {
          final t = _animationController.value;
          _currentPosition = LatLng(
            _previousPosition!.latitude +
                (_animatedPosition!.latitude - _previousPosition!.latitude) *
                    t,
            _previousPosition!.longitude +
                (_animatedPosition!.longitude -
                    _previousPosition!.longitude) *
                    t,
          );
          _updateMarker();
        });
      }
    });

    // Carregamento do histórico — desativado no Wear para poupar recursos
    if (!isWearOS) {
      _loadSavedRuns();
    }
    _listenToActiveChallenge();
    _setOnlineInitially();
  }

  Future<void> _initLocationFlow() async {
    await _checkLocationPermissionAndSetInitialLocation();
    await _startLocationTracking(); // atualiza posição mesmo sem iniciar corrida
  }

  Future<void> _checkLocationPermissionAndSetInitialLocation() async {
    _locationPermission = await Geolocator.checkPermission();
    if (_locationPermission == LocationPermission.denied) {
      _locationPermission = await Geolocator.requestPermission();
    }
    if (_locationPermission == LocationPermission.deniedForever) {
      setState(() {
        _loadingLocation = false;
      });
      return;
    }
    await _setInitialLocation();
  }

  Future<void> _updateMarker() async {
    if (isWearOS) return; // sem marcador/Mapa no Wear
    final customIcon = await _createUserCircleIcon(
      size: 60,
      fillColor: const Color(0xFFFF7600),
    );

    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'currentLocation');
      _markers.add(
        Marker(
          markerId: const MarkerId('currentLocation'),
          position: _currentPosition,
          icon: customIcon,
          anchor: const Offset(0.5, 0.5),
          zIndex: 10000,
        ),
      );
    });
  }

  Future<void> _setInitialLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _loadingLocation = false;
      });

      await _updateMarker();

      if (!isWearOS && _followUser && _mapReady) {
        _isProgrammaticCameraMove = true;
        await _googleMapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: _currentPosition, zoom: 17),
          ),
        );
        Future.delayed(const Duration(milliseconds: 300), () {
          _isProgrammaticCameraMove = false;
        });
      }

    } catch (e) {
      setState(() => _loadingLocation = false);
    }
  }



  Future<void> _loadSavedRuns() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final runs = await FirebaseFirestore.instance
          .collection('corridas')
          .orderBy('createdAt', descending: true)
          .get();

      final colorPalette = [
        Colors.orangeAccent,
        Colors.cyanAccent,
        Colors.purpleAccent,
        Colors.amberAccent,
        Colors.pinkAccent,
        Colors.lightGreenAccent,
        Colors.blueAccent,
      ];

      final userColors = <String, Color>{};
      int colorIndex = 0;

      for (var doc in runs.docs) {
        final data = doc.data();
        final userId = data['userId'];

        if (data['path'] == null || (data['path'] as List).isEmpty) continue;

        // 🔹 Define uma cor para cada usuário (a sua sempre verde)
        userColors.putIfAbsent(
          userId,
              () => colorPalette[colorIndex++ % colorPalette.length],
        );

        final color = userId == user.uid
            ? const Color(0xFF00C853) // 💚 você
            : userColors[userId]!;     // 🎨 outros

        // 🔹 Caminho
        final path = (data['path'] as List)
            .map((p) => LatLng(p['lat'], p['lng']))
            .toList();

        // 🔹 Linha colorida
        final polyline = Polyline(
          polylineId: PolylineId('run_${doc.id}'),
          points: path,
          color: color.withOpacity(0.85),
          width: 6,
          jointType: JointType.round,
        );
        _polylines.add(polyline);

        // 🔹 Pega nome e foto do jogador
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();

        final userName =
            userDoc.data()?['displayName'] ?? 'Jogador'; // <-- usa displayName
        final photoUrl = userDoc.data()?['photoURL'];   // <-- foto do perfil

        await _addRunMarker(
          position: path.first,
          userName: userId == user.uid ? 'Você' : userName,
          photoUrl: photoUrl,
          runData: data,
        );
      }

      await _loadTerritories(); // 🟩 Carrega territórios conquistados


      setState(() {});
    } catch (e) {
      debugPrint("Erro ao carregar corridas: $e");
    }

    // 🔹 Ajuste automático do zoom
    if (_markers.isNotEmpty && _googleMapController != null && _followUser) {
      await Future.delayed(const Duration(milliseconds: 800));
      _googleMapController?.animateCamera(
        CameraUpdate.newLatLngBounds(
          _calculateBounds(_markers.map((m) => m.position).toList()),
          80,
        ),
      );
    }
  }

  Future<void> _loadTerritories() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('territorios')
          .get();

      final colorPalette = [
        Colors.deepPurpleAccent.withOpacity(0.4),
        Colors.orangeAccent.withOpacity(0.4),
        Colors.cyanAccent.withOpacity(0.4),
        Colors.pinkAccent.withOpacity(0.4),
        Colors.lightGreenAccent.withOpacity(0.4),
        Colors.blueAccent.withOpacity(0.4),
      ];

      int colorIndex = 0;

      _territoryPolygons.clear();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final userId = data['userId'] ?? '';
        final points = (data['points'] as List)
            .map((p) => LatLng(p['lat'], p['lng']))
            .toList();

        final color = userId == user.uid
            ? const Color(0xFF00C853).withOpacity(0.4) // 💚 Seu território
            : colorPalette[colorIndex++ % colorPalette.length];

        _territoryPolygons.add(
          Polygon(
            polygonId: PolygonId("territorio_${doc.id}"),
            points: points,
            fillColor: color,
            strokeColor: color.withOpacity(0.7),
            strokeWidth: 2,
          ),
        );
      }

      setState(() {});
    } catch (e) {
      debugPrint("Erro ao carregar territórios: $e");
    }
  }



  void _startRun() async {
    ScaffoldVisibilityController.hide();

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return;
      }
    }

    _positions.clear();
    _polylines.clear();
    _totalDistance = 0;
    _seconds = 0;
    _caloriesBurned = 0;
    _averagePace = 0;

    _stopwatch.reset();
    _stopwatch.start();
    _startTime = DateTime.now();

    setState(() => _isRunning = true);

    await _playStart(); // som apenas no Wear

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _seconds = _stopwatch.elapsed.inSeconds;
        _calculatePaceAndCalories();
      });
    });

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((position) {
      final latLngPos = LatLng(position.latitude, position.longitude);

      setState(() {
        if (_positions.isNotEmpty) {
          final d = Geolocator.distanceBetween(
            _positions.last.latitude, _positions.last.longitude,
            latLngPos.latitude, latLngPos.longitude,
          );

          if (d > 0.5) {
            _totalDistance += d;         // ⬅️ soma em METROS
            _positions.add(latLngPos);
            // 🎯 Sistema de XP em tempo real
            _distanceSinceLastXP += d;
            if (_distanceSinceLastXP >= 100) { // a cada 100 metros = +1 XP
              _distanceSinceLastXP -= 100;
              _sessionXP += 1;
              _showXPGainEffect("+1 XP");

              // Vibra e mostra se atingiu múltiplos de 100 XP
              if (_sessionXP >= _nextXPThreshold) {
                _nextXPThreshold += 100;
                HapticFeedback.mediumImpact();
                _showXPLevelUp();
              }
            }
            if (!isWearOS) _updatePolyline();
          }
        } else {
          _positions.add(latLngPos);
        }

        _previousPosition = _currentPosition;
        _animatedPosition = latLngPos;
      });

      _animationController.forward(from: 0.0);

      if (!isWearOS && _followUser) {
        _googleMapController?.animateCamera(CameraUpdate.newLatLng(latLngPos));
      }

      // não marcar _isProgrammaticCameraMove duas vezes aqui; uma animação basta
    });
  }

  DateTime? _lastPointTime;

  void _updatePolyline() {
    if (isWearOS) return;
    if (_positions.length < 2) return;

    final i = _positions.length - 2;
    final start = _positions[i];
    final end = _positions[i + 1];

    final now = DateTime.now();
    double elapsed = 1.0;
    if (_lastPointTime != null) {
      elapsed = now.difference(_lastPointTime!).inMilliseconds / 1000;
    }
    _lastPointTime = now;

    final distance = Geolocator.distanceBetween(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );
    if (distance < 0.5) return;

    final speed = (distance / elapsed).clamp(0.2, 6.0); // m/s

    final color = Color.lerp(
      const Color(0xFF3FA9F5),
      const Color(0xFFFF3D00),
      (speed / 6).clamp(0, 1),
    )!;

    final width = (4 + speed * 1.2).clamp(4, 12).toInt();

    _polylines.add(
      Polyline(
        polylineId: PolylineId('segment_$i'),
        points: [start, end],
        color: color.withOpacity(0.9),
        width: width,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    );


    // 🟩 Atualiza área/plot do território SEM mexer em timers/estados da corrida
    if (_positions.length >= 3) {
      _areaCapturedFormatted = _calculateAreaFormatted(_positions);
      _polygons
        ..clear()
        ..add(Polygon(
          polygonId: const PolygonId('territorio'),
          points: List.from(_positions),
          strokeColor: color,
          strokeWidth: 2,
          fillColor: color.withOpacity(0.3),
        ));
    }
  }

  // 🟩 NOVO: cálculo de área (m² ou km², com formatação automática)
  String _calculateAreaFormatted(List<LatLng> points) {
    if (points.length < 3) return "0 m²";

    const double earthRadius = 6378137.0;
    final refLat = points.first.latitude * math.pi / 180;
    final refLng = points.first.longitude * math.pi / 180;

    final projected = points.map((p) {
      final latRad = p.latitude * math.pi / 180;
      final lngRad = p.longitude * math.pi / 180;
      final x = (lngRad - refLng) * earthRadius * math.cos(refLat);
      final y = (latRad - refLat) * earthRadius;
      return Offset(x, y);
    }).toList();

    // Shoelace formula
    double area = 0;
    for (int i = 0; i < projected.length; i++) {
      final j = (i + 1) % projected.length;
      area += projected[i].dx * projected[j].dy - projected[j].dx * projected[i].dy;
    }

    area = area.abs() / 2.0;

    _areaCaptured = area; // ⬅️ agora o painel consegue saber se mostra (opacity)

    return (area >= 1_000_000)
        ? "${(area / 1_000_000).toStringAsFixed(2)} km²"
        : "${area.toStringAsFixed(0)} m²";

  }





  Marker? _pulseMarker;
  double _pulseT = 0.0;
  Timer? _pulseTimer;

  Future<void> _startPulseEffect() async {
    if (isWearOS) return;
    _pulseTimer?.cancel();
    if (_positions.length < 2) return;

    final pulseIcon = await _createUserCircleIcon(
      size: 60,
      fillColor: const Color(0xFFFF7600),
    );

    _pulseT = 0.0;
    _pulseTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (_positions.length < 2) return;

      _pulseT += 0.01;
      if (_pulseT >= 1.0) _pulseT = 0.0;

      final index = (_pulseT * (_positions.length - 1)).floor();
      if (index >= _positions.length - 1) return;

      final start = _positions[index];
      final end = _positions[index + 1];

      final t = (_pulseT * (_positions.length - 1) - index);
      final lat = start.latitude + (end.latitude - start.latitude) * t;
      final lng = start.longitude + (end.longitude - start.longitude) * t;
      final pulsePos = LatLng(lat, lng);

      _pulseMarker = Marker(
        markerId: const MarkerId('pulse'),
        position: pulsePos,
        icon: pulseIcon,
        anchor: const Offset(0.5, 0.5),
      );

      setState(() {
        _markers.removeWhere((m) => m.markerId.value == 'pulse');
        _markers.add(_pulseMarker!);
      });
    });
  }

  void _stopPulseEffect() {
    _pulseTimer?.cancel();
    _pulseMarker = null;
  }

  Future<void> _stopRun() async {
    _timer?.cancel();
    _stopwatch.stop();
    // _stopPulseEffect();
    setState(() => _isRunning = false);
    await _playStop(); // som apenas no Wear
    ScaffoldVisibilityController.show();
  }

  void _calculatePaceAndCalories() {
    final dMeters = _totalDistance;
    final secs = _seconds;

    if (secs > 0 && dMeters > 1) {
      _averagePace = (secs / 60) / (dMeters / 1000.0); // min/km
      _caloriesBurned = dMeters * 0.05; // ~50 kcal por km
    } else {
      _averagePace = 0;
      _caloriesBurned = 0;
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  String _formatPace(double pace) {
    if (pace.isInfinite || pace.isNaN || pace <= 0) return '00:00';
    int minutes = pace.floor();
    int seconds = ((pace - minutes) * 60).round();
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  LatLngBounds _calculateBounds(List<LatLng> positions) {
    double minLat = positions.first.latitude;
    double maxLat = positions.first.latitude;
    double minLng = positions.first.longitude;
    double maxLng = positions.first.longitude;

    for (final LatLng pos in positions) {
      if (pos.latitude < minLat) minLat = pos.latitude;
      if (pos.latitude > maxLat) maxLat = pos.latitude;
      if (pos.longitude < minLng) minLng = pos.longitude;
      if (pos.longitude > maxLng) maxLng = pos.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  Future<void> _startLocationTracking() async {
    try {
      await _positionStream?.cancel();
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
        ),
      ).listen((position) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
        });
        _updateMarker();

        if (!isWearOS && _followUser) {
          _isProgrammaticCameraMove = true;
          _googleMapController?.animateCamera(
            CameraUpdate.newLatLng(_currentPosition),
          );
          Future.delayed(const Duration(milliseconds: 300), () {
            _isProgrammaticCameraMove = false;
          });
        }

      });
    } catch (e) {
      debugPrint("Erro ao iniciar rastreamento contínuo: $e");
    }
  }

  Future<void> _setOnlineInitially() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _lastSavedPositionOnline = LatLng(pos.latitude, pos.longitude);

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'isOnline': true,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _startOnlineTracking();
      debugPrint("✅ Usuário inicializado como online em ${pos.latitude}, ${pos.longitude}");
    } catch (e) {
      debugPrint("❌ Erro ao inicializar online: $e");
    }
  }

  void _startOnlineTracking() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _onlinePositionStream?.cancel();
    _onlinePositionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 100, // evita atualizações muito próximas
      ),
    ).listen((pos) async {
      if (_lastSavedPositionOnline == null) {
        _lastSavedPositionOnline = LatLng(pos.latitude, pos.longitude);
        return;
      }

      final dist = Geolocator.distanceBetween(
        _lastSavedPositionOnline!.latitude,
        _lastSavedPositionOnline!.longitude,
        pos.latitude,
        pos.longitude,
      );

      if (dist >= 500) {
        _lastSavedPositionOnline = LatLng(pos.latitude, pos.longitude);
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        debugPrint("📍 Localização atualizada após mover ${dist.toStringAsFixed(0)}m");
      }
    });
  }

  Future<void> _toggleOnlineStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isOnline = !_isOnline);

    if (_isOnline) {
      await _setOnlineInitially();
    } else {
      _onlinePositionStream?.cancel();
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'isOnline': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint("🛑 Usuário ficou offline");
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isOnline ? "🟢 Você está online!" : "🔴 Você ficou offline"),
        duration: const Duration(seconds: 2),
      ));
    }
  }



  @override
  void dispose() {
    _timer?.cancel();
    _positionStream?.cancel();
    _animationController.dispose();
    _googleMapController?.dispose();
    _audio.dispose();
    _onlinePositionStream?.cancel();
    // ✅ Marca como offline ao encerrar o app
    _setOfflineOnExit();
    super.dispose();
  }

  void _onItemTapped(int index) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => MainScaffold(initialIndex: index)),
    );
  }

  // ===== UI =====

  // Wear OS: UI leve, sem Google Map
  // 🕶️ -------- WEAR OS BODY (cronômetro + botão central + métricas) --------
  Widget _buildWearBody() {
    final size = MediaQuery.of(context).size;
    final shortest = size.shortestSide;
    final scale = (shortest / 390).clamp(0.7, 1.0); // escala adaptável p/ relógios menores

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(

          alignment: Alignment.center,
          children: [
            // Fundo animado sutil
            IgnorePointer(
              ignoring: true,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color.fromARGB(100, 0, 143, 200),
                      Color.fromARGB(40, 14, 60, 112),
                      Colors.transparent,
                    ],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
              ),
            ),


            // Conteúdo principal
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ⏱️ Cronômetro centralizado
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Transform.scale(
                    scale: scale * 0.95,
                    child: FuturisticChrono(
                      seconds: _seconds,
                      fontSize: 48 * scale,
                    ),
                  ),
                ),


                // 📊 Métricas
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildMetricWear(Icons.route,
                        (_totalDistance / 1000).toStringAsFixed(2), "Km"),
                    _buildMetricWear(
                        Icons.timer, _formatPace(_averagePace), "Ritmo"),
                  ],
                ),
                SizedBox(height: 14 * scale),

                if (_challengeStream != null)
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _challengeStream,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox();

                      final data = snapshot.data!.data();
                      if (data == null) return const SizedBox();

                      final participants = (data['participants'] ?? []) as List;
                      final userId = FirebaseAuth.instance.currentUser!.uid;
                      final isAuthor = data['authorId'] == userId;

                      // Se não for participante nem autor, oculta
                      if (!participants.contains(userId) && !isAuthor) return const SizedBox();

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 25, top: 15),
                        child: _buildActiveChallengePanel(data, snapshot.data!.id),
                      );
                    },
                  ),




                // ▶️ Botão principal

                GestureDetector(
                  onTap: _isRunning
                      ? () async {
                    _stopRun();
                    await _saveRun(wearMode: true);
                  }
                      : _startRun,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 90 * scale,
                    width: 90 * scale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: _isRunning
                            ? [Colors.redAccent, const Color(0xFFFF6D00)]
                            : [const Color(0xFF00C853), const Color(0xFFFF6D00)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_isRunning
                              ? const Color(0xFFFF3B30)
                              : const Color(0xFF007AFF))
                              .withOpacity(0.55),
                          blurRadius: 25,
                          spreadRadius: 6,
                        ),
                      ],
                    ),
                    child: Icon(
                      _isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 40 * scale,
                    ),
                  ),
                ),

                // 🔴 Estado da corrida
                const SizedBox(height: 10),
                Text(
                  _isRunning ? "Correndo..." : "Toque para começar",
                  style: TextStyle(
                    color: _isRunning
                        ? Colors.redAccent.withOpacity(0.9)
                        : Colors.white70,
                    fontSize: 12 * scale,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveChallengePanel(Map<String, dynamic> challenge, String challengeId) {
    final title = challenge['title'] ?? 'Desafio sem nome';
    final distance = (challenge['distance'] ?? 0).toDouble();
    final deadline = (challenge['deadline'] as Timestamp?)?.toDate();
    final now = DateTime.now();

    final timeLeft = deadline != null ? deadline.difference(now) : Duration.zero;
    final daysLeft = timeLeft.inDays >= 0 ? timeLeft.inDays : 0;

    final userId = FirebaseAuth.instance.currentUser!.uid;
    final userProgress =
    (challenge['progress']?[userId]?['distance'] ?? 0).toDouble();

    final progress = distance > 0 ? (userProgress / distance).clamp(0.0, 1.0) : 0.0;
    final progressPercent = (progress * 100).toStringAsFixed(0);

    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(left: 16, top: 12),
        padding: const EdgeInsets.all(14),
        width: 150,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.blueAccent.withOpacity(0.3),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔽 Cabeçalho com botão de recolher
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "🏁 $title",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _isChallengePanelVisible
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Colors.white70,
                  ),
                  onPressed: () {
                    setState(() => _isChallengePanelVisible = !_isChallengePanelVisible);
                  },
                ),
              ],
            ),

            // 🔹 Conteúdo recolhível
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 250),
              crossFadeState: _isChallengePanelVisible
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Text("Meta: ${distance.toStringAsFixed(1)} km",
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  if (daysLeft > 0)
                    Text("Prazo: $daysLeft dias restantes",
                        style: const TextStyle(color: Colors.white70, fontSize: 13))
                  else
                    const Text("⏰ Desafio encerrando hoje!",
                        style: TextStyle(color: Colors.redAccent, fontSize: 13)),

                  const SizedBox(height: 10),

                  Stack(
                    children: [
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.redAccent.withOpacity(0.3),
                        ),
                      ),
                      Container(
                        height: 8,
                        width: (250 * progress).toDouble(),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF007AFF), Color(0xFF4A90E2)],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text("$progressPercent% concluído",
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),

                  const SizedBox(height: 10),
                  _buildCancelButton(challengeId),
                ],
              ),
              secondChild: const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildCancelButton(String challengeId) {
    return TextButton.icon(
      onPressed: () => _confirmCancelChallenge(challengeId),
      icon: const Icon(Icons.cancel, color: Colors.redAccent),
      label: const Text(
        "Cancelar inscrição",
        style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _confirmCancelChallenge(String challengeId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black87,
        title: const Text("Tem certeza?",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          "😢 Se você desistir, seu nome vai brilhar no mural dos desistentes!\nTem certeza mesmo?",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Voltar", style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Desistir 😭",
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final userId = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance.collection('posts').doc(challengeId).update({
        'quitters': FieldValue.arrayUnion([userId]),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Você desistiu do desafio 😅"),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }




  Widget _buildMetricWear(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10))
      ],
    );
  }

  // Mobile: UI completa com Google Map e tudo
  Widget _buildMobileBody() {
    return Scaffold(
      backgroundColor: Colors.white,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "RUNNER",
          style: GoogleFonts.poppins(
            color: Colors.black,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // 🗺️ Mapa branco e cinza
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: CameraPosition(
              target: _currentPosition,
              zoom: 16,
            ),
            onMapCreated: (controller) async {
              _googleMapController = controller;
              _mapReady = true;
              await _updateMarker();
              final style = await rootBundle.loadString('assets/map_style/white_map.json');
              _googleMapController?.setMapStyle(style);
            },
            polylines: _polylines,
            polygons: {..._polygons, ..._territoryPolygons},
            markers: _markers,
            myLocationEnabled: false,
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
          ),

          // 🌫️ Vinheta branca suave — estilo névoa real
          IgnorePointer(
            ignoring: true,
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.0,
                  colors: [
                    Colors.white.withOpacity(0.0),   // centro transparente
                    Colors.white.withOpacity(0.8),   // camada média
                    Colors.white.withOpacity(1.0),   // bordas levemente brancas
                    Colors.white,                    // extremidades totalmente brancas
                  ],
                  stops: const [0.4, 0.7, 0.9, 1.0],
                ),
              ),
            ),
          ),


          // 🕒 Cronômetro e métricas superiores
          Positioned(
            top: MediaQuery.of(context).padding.top + 30,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  _formatDuration(Duration(seconds: _seconds)),
                  style: GoogleFonts.poppins(
                    fontSize: 50,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildMetricCard(Icons.route, (_totalDistance / 1000).toStringAsFixed(2), "Km"),
                    _buildMetricCard(Icons.local_fire_department, _caloriesBurned.round().toString(), "Kcal"),
                    _buildMetricCard(Icons.timer, _formatPace(_averagePace), "Ritmo"),
                  ],
                ),
              ],
            ),
          ),

          // ⚫ Botão central — preto com ícone play laranja
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: _isRunning ? _buildSlideToStopButton() : _buildStartButton(),
            ),
          ),

          // 🔘 Botão recenter
          Positioned(
            bottom: 110,
            right: 20,
            child: GestureDetector(
              onTap: _recenterMap,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      spreadRadius: 1,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.my_location_rounded, color: Colors.black, size: 26),
              ),
            ),
          ),

          // 🌐 Online/Offline — minimalista
          Positioned(
            top: MediaQuery.of(context).padding.top + 230,
            right: 20,
            child: GestureDetector(
              onTap: _toggleOnlineStatus,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                      color: Colors.black,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isOnline ? "Online" : "Offline",
                      style: GoogleFonts.poppins(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ▶️ Botão de início da corrida
  Widget _buildStartButton() {
    return GestureDetector(
      onTap: _startRun,
      child: Container(
        height: 90,
        width: 90,
        decoration: BoxDecoration(
          color: Colors.black,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(
          Icons.play_arrow_rounded,
          color: Color(0xFFFF6D00),
          size: 48,
        ),
      ),
    );
  }

  // ⏹️ Botão de deslize para parar
  Widget _buildSlideToStopButton() {
    final double progress = (_slideDragValue / 180).clamp(0.0, 1.0);

    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _slideDragValue += details.primaryDelta ?? 0;
          _slideDragValue = _slideDragValue.clamp(0.0, 180.0);
        });
      },
      onHorizontalDragEnd: (details) async {
        if (_slideDragValue > 120) {
          HapticFeedback.mediumImpact();
          await _stopRun();
          await _saveRun();
          setState(() {
            _slideDragValue = 0.0;
            _isRunning = false;
          });
        } else {
          HapticFeedback.lightImpact();
          setState(() => _slideDragValue = 0.0);
        }
      },
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Container(
            height: 65,
            width: 240,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(40),
              color: Colors.black,
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
          ),

          AnimatedContainer(
            duration: const Duration(milliseconds: 50),
            height: 65,
            width: (240 * progress).clamp(0, 240),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.horizontal(
                left: const Radius.circular(40),
                right: Radius.circular(progress > 0.98 ? 40 : 10),
              ),
              color: Colors.grey[300],
            ),
          ),

          SizedBox(
            height: 65,
            width: 240,
            child: Center(
              child: Text(
                progress > 0.9 ? "Solte para parar 🏁" : "⬅️ Deslize para parar",
                style: GoogleFonts.poppins(
                  color: Colors.white.withOpacity(progress > 0.9 ? 1 : 0.9),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  fontSize: 14,
                ),
              ),
            ),
          ),

          Positioned(
            left: _slideDragValue.clamp(0, 175),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              height: 65,
              width: 65,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.stop_rounded,
                color: Colors.black,
                size: 30,
              ),
            ),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return isWearOS ? _buildWearBody() : _buildMobileBody();
  }

  // 🔲 Cards de métricas — branco com texto preto e fonte Adidas
  Widget _buildMetricCard(IconData icon, String value, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 6,
                spreadRadius: 1,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.black, size: 26),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: GoogleFonts.poppins(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(
            color: Colors.black54,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ===== Persistência =====
  Future<void> _saveRun({bool wearMode = false}) async {
    if (loading) return;
    setState(() => loading = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (context.mounted && !wearMode) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Usuário não autenticado. Login necessário para salvar.")),
        );
      }
      setState(() => loading = false);
      return;
    }

    if (_totalDistance < 10) {
      if (context.mounted && !wearMode) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Corrida muito curta para ser salva.")),
        );
      }
      setState(() => loading = false);
      return;
    }

    // ✅ Define a distância antes de qualquer reset
    final distanceMeters = _totalDistance;
    final distanceKm = distanceMeters / 1000.0;

    final runData = {
      'userId': user.uid,
      'startTime': _startTime?.toIso8601String(),
      'endTime': DateTime.now().toIso8601String(),
      'duration': _stopwatch.elapsed.inSeconds,
      'distance': distanceMeters,
      'calories': _caloriesBurned,
      'pace': _averagePace,
      'path': _positions
          .map((point) => {'lat': point.latitude, 'lng': point.longitude})
          .toList(),
      'createdAt': FieldValue.serverTimestamp(),
    };

    final pathSnapshot = List<LatLng>.from(_positions);

    try {
      // ✅ Salva corrida
      await FirebaseFirestore.instance.collection('corridas').add(runData);

// 🏆 Checa conquistas (Primeira Corrida, 5K etc.)
      try {
        // dá um pequeno tempo pra garantir sincronização
        await Future.delayed(const Duration(milliseconds: 600));

        await AchievementService().checkAchievements(
          runData: runData,
          context: context,
        );
      } catch (e) {
        debugPrint('Erro ao verificar conquistas: $e');
      }

// 🏅 XP automático no salvamento
      try {
        int baseXP = (distanceKm * 10).floor() + 5;
        double xpMultiplier = 1.0;

        final isPro = (user.email ?? '').contains('pro');
        if (isPro) xpMultiplier *= 2.0;

        final inActiveChallenge = await _userHasActiveChallenge();
        if (inActiveChallenge) xpMultiplier *= 1.5;

        final totalXP = (baseXP * xpMultiplier).round();

        await GamificationService().addPoints(totalXP, context: context);
        _showXPAnimation("+$totalXP XP");
        await _updateLeaderboard();
      } catch (e) {
        debugPrint('Erro ao conceder XP no _saveRun: $e');
      }


      if (context.mounted && !wearMode) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🏁 Corrida salva com sucesso!')),
        );
        await _applyRunDistanceToActiveChallenges(distanceMeters: distanceMeters);
      }
    } catch (e) {
      if (context.mounted && !wearMode) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro ao salvar corrida: $e")),
        );
      }
    } finally {
      setState(() => loading = false);

      // 🔹 Reseta UI e variáveis
      setState(() {
        _seconds = 0;
        _totalDistance = 0;
        _caloriesBurned = 0;
        _averagePace = 0;
        _positions.clear();

        if (!isWearOS) {
          _polylines.clear();
          _markers.clear();
        }
      });

      await _setInitialLocation();
    }

    // 🗺️ Salva território conquistado
    if (pathSnapshot.length >= 3 && _areaCaptured > 0) {
      await FirebaseFirestore.instance.collection('territorios').add({
        'userId': user.uid,
        'points':
        pathSnapshot.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
        'area': _areaCaptured,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _loadTerritories();
    }
  }


  Future<void> _updateLeaderboard() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // 🔹 Busca XP e nome do usuário
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final xp = (userDoc.data()?['xp'] ?? 0) as int;
      final username = userDoc.data()?['displayName'] ?? user.email ?? 'Runner';

      // 🔹 Soma todas as distâncias válidas das corridas
      final query = await FirebaseFirestore.instance
          .collection('corridas')
          .where('userId', isEqualTo: user.uid)
          .get();

      double totalKm = 0.0;
      for (var doc in query.docs) {
        final data = doc.data();
        final rawDist = data['distance'];

        // ✅ Garante que é número antes de somar
        if (rawDist != null && rawDist is num) {
          totalKm += rawDist.toDouble() / 1000.0;
        }
      }

      // 🔹 Atualiza Leaderboard Global
      await FirebaseFirestore.instance
          .collection('leaderboard_global')
          .doc(user.uid)
          .set({
        'userId': user.uid,
        'displayName': username,
        'xp': xp,
        'km': double.parse(totalKm.toStringAsFixed(2)),
        'lastRunAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 🔹 Atualiza Leaderboard Semanal
      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final weekId =
          "${weekStart.year}_${weekStart.month.toString().padLeft(2, '0')}_${weekStart.day.toString().padLeft(2, '0')}";

      await FirebaseFirestore.instance
          .collection('leaderboard_weekly')
          .doc("${weekId}-${user.uid}")
          .set({
        'userId': user.uid,
        'displayName': username,
        'xp': xp,
        'km': double.parse(totalKm.toStringAsFixed(2)),
        'weekStart': weekStart,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint("✅ Leaderboard atualizado: ${totalKm.toStringAsFixed(2)} km | $xp XP");
    } catch (e) {
      debugPrint('❌ Erro ao atualizar leaderboard: $e');
    }
  }






  Future<void> _updateUserRunStats() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startOfDay = DateTime(now.year, now.month, now.day);

    final runsQuery = await FirebaseFirestore.instance
        .collection('corridas')
        .where('userId', isEqualTo: user.uid)
        .get();

    final runs = runsQuery.docs.map((doc) {
      final data = doc.data();
      final date = (data['data'] as Timestamp).toDate();
      return date;
    }).toList();

    // Contagem da semana atual
    weeklyRunsCount = runs.where((d) => d.isAfter(startOfWeek)).length;

    // Calcula sequência de dias consecutivos (streak)
    runs.sort((a, b) => b.compareTo(a));
    streakDays = 1;

    for (int i = 1; i < runs.length; i++) {
      final diff = runs[i - 1].difference(runs[i]).inDays;
      if (diff == 1) {
        streakDays++;
      } else if (diff > 1) {
        break;
      }
    }
  }


  Future<void> _finalizarCorrida() async {

    // só finalize se realmente estiver correndo
    if (!_isRunning) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _timer?.cancel();
    _stopwatch.stop();

    final distanceMeters = _totalDistance;          // metros
    final distanceKm = distanceMeters / 1000.0;     // km
    final duration = _stopwatch.elapsed.inSeconds;

    // Evita corridas muito curtas
    if (distanceMeters < 10) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Distância muito curta para registrar corrida."),
          backgroundColor: Colors.redAccent,
        ));
      }
      return;
    }

    // 🎯 XP base: 10 xp por km + 5 de bônus
    final baseXP = (distanceKm * 10).floor() + 5;

    // 🎛️ Multiplicadores
    double xpMultiplier = 1.0;

    // Exemplo de "Pro Runner" — adapte sua flag real
    final isPro = (user.email ?? '').contains('pro');
    if (isPro) xpMultiplier *= 2.0;

    // Desafio ativo
    final inActiveChallenge = await _userHasActiveChallenge();
    if (inActiveChallenge) xpMultiplier *= 1.5;

    final totalXP = (baseXP * xpMultiplier).round();

    // 🎈 Feedback de XP
    _showXPAnimation("+$totalXP XP");

    // 🏅 Salva corrida
    final runData = {
      'userId': user.uid,
      'distance': distanceMeters,         // guardei em METROS p/ consistência com o resto do app
      'duration': duration,
      'pace': _averagePace,
      'calories': _caloriesBurned,
      'xpEarned': totalXP,
      'createdAt': FieldValue.serverTimestamp(),
    };
    await FirebaseFirestore.instance.collection('corridas').add(runData);

    // ➕ adiciona XP ao perfil
    await GamificationService().addPoints(totalXP, context: context);

    // 🏆 Conquistas/estatísticas
    await _updateUserRunStats();
    await AchievementService().checkAchievements(
      runData: {
        'distance': distanceMeters,
        'pace': _averagePace,
        'weeklyRuns': weeklyRunsCount,
        'streak': streakDays,
      },
      context: context,
    );

    // 🥇 Leaderboard
    await _updateLeaderboard();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("🏁 Corrida salva! +$totalXP XP."), backgroundColor: Colors.green[700]),
      );
    }

    // reset UI
    setState(() {
      _isRunning = false;
      _runEnded = true;
      _positions.clear();
      _polylines.clear();
      _markers.clear();
      _totalDistance = 0;
      _seconds = 0;
      _averagePace = 0;
      _caloriesBurned = 0;
      _slideDragValue = 0.0;
    });
    ScaffoldVisibilityController.show();
  }

  void _showXPAnimation(String text) {
    OverlayEntry? overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: MediaQuery.of(context).padding.top + 20,
          left: 0, right: 0,
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 1200),
              builder: (context, t, _) {
                return Opacity(
                  opacity: 1 - t,
                  child: Transform.translate(
                    offset: Offset(0, -40 * t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blueAccent.withOpacity(0.4),
                            blurRadius: 16, spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Text(
                        text,
                        style: const TextStyle(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(overlayEntry!);
    Future.delayed(const Duration(milliseconds: 1250), () {
      overlayEntry?.remove();
    });
  }

  void _showXPGainEffect(String text) {
    OverlayEntry? overlay;
    overlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: MediaQuery.of(context).padding.top + 40,
          left: 0, right: 0,
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 800),
              builder: (context, t, _) {
                return Opacity(
                  opacity: 1 - t,
                  child: Transform.translate(
                    offset: Offset(0, -40 * t),
                    child: Text(
                      text,
                      style: const TextStyle(
                        color: Color(0xFF4A90E2),
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(blurRadius: 10, color: Colors.blueAccent),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(overlay!);
    Future.delayed(const Duration(milliseconds: 850), () => overlay?.remove());
  }

  void _showXPLevelUp() {
    OverlayEntry? overlay;
    overlay = OverlayEntry(
      builder: (context) {
        return Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                builder: (context, t, _) {
                  final opacity = (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
                  return Opacity(
                    opacity: opacity,
                    child: Transform.scale(
                      scale: 1 + 0.3 * (1 - opacity),
                      child: Text(
                        "⭐ LEVEL UP!",
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: Colors.yellowAccent.withOpacity(opacity),
                          shadows: const [
                            Shadow(blurRadius: 30, color: Colors.orangeAccent),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(overlay!);
    Future.delayed(const Duration(milliseconds: 1000), () => overlay?.remove());
  }






  Future<void> _addRunMarker({
    required LatLng position,
    required String userName,
    String? photoUrl,
    required Map<String, dynamic> runData,
  }) async {
    if (isWearOS) return;

    try {
      const double size = 60;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..isAntiAlias = true;

      // 🔹 Bolinha com gradiente azul
      final gradient = ui.Gradient.radial(
        Offset(size / 2, size / 2),
        size / 2,
        [
          const Color(0xFF000000),
          const Color(0xFFE66E0F),
        ],
      );
      paint.shader = gradient;
      canvas.drawCircle(Offset(size / 2, size / 2), size / 2, paint);

      // 🔹 Borda branca translúcida
      paint
        ..shader = null
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withOpacity(0.8);
      canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 1.5, paint);

      final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
      final bytes =
      (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();

      final marker = Marker(
        markerId: MarkerId("runner_${position.latitude}_${position.longitude}"),
        position: position,
        icon: BitmapDescriptor.fromBytes(bytes),
        anchor: const Offset(0.5, 0.5),
        zIndex: 9999,
        onTap: () async {
          HapticFeedback.lightImpact();
          _showLoadingOverlay(context);

          await Future.delayed(const Duration(milliseconds: 700));
          if (!context.mounted) return;
          Navigator.pop(context);

          final userId = runData['userId'] ?? '';
          if (userId.isEmpty) {
            debugPrint("⚠️ userId vazio — card não pode abrir");
            return;
          }

          // ✅ Reabre o card no contexto atualizado
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              _showPlayerCard(context, userId, runData: runData);
            }
          });
        },



        onDragStart: (_) {
          _longPressTimer?.cancel();
        },
        onDragEnd: (_) {},
        consumeTapEvents: false,
      );

      setState(() => _markers.add(marker));

      // Armazena dados do marcador para gesto
      _markerGestures[position] = (userName, photoUrl, runData);
    } catch (e) {
      debugPrint("❌ Erro ao criar marcador com gesto: $e");
    }
  }

// 🔹 Armazena dados dos marcadores
  final Map<LatLng, (String, String?, Map<String, dynamic>)> _markerGestures = {};

  /// Chamado a partir do mapa, interceptando gestos sobre marcadores
  Timer? _markerHoldTimer;
  OverlayEntry? _activeMarkerOverlay;

  void _showRadialMenu(
      LatLng markerPos,
      String userName,
      String? photoUrl,
      Map<String, dynamic> runData,
      ) async {
    if (_googleMapController == null) return;

    final screenCoordinate =
    await _googleMapController!.getScreenCoordinate(markerPos);

    final renderBox = context.findRenderObject() as RenderBox;
    final screenSize = renderBox.size;
    final safeTop = MediaQuery.of(context).padding.top;

    double dx = screenCoordinate.x.toDouble();
    double dy = screenCoordinate.y.toDouble();

    // Ajuste de posição: centraliza acima da bolinha
    dy = dy - 80 - safeTop;

    dx = dx.clamp(80.0, screenSize.width - 80.0);
    dy = dy.clamp(150.0, screenSize.height - 150.0);
    final center = Offset(dx, dy);

    // Feedback tátil
    HapticFeedback.mediumImpact();

    _radialMenuOverlay?.remove();

    // Reutiliza o controlador de animação existente
    _animationController.reset();
    _animationController.duration = const Duration(milliseconds: 400);
    _animationController.forward();

    _radialMenuOverlay = OverlayEntry(
      builder: (context) {
        return AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            final progress = Curves.easeOut.transform(_animationController.value);
            final waveRadius = 10 + (progress * 300);

            return Positioned.fill(
              child: GestureDetector(
                onTap: _removeRadialMenu,
                child: Stack(
                  children: [
                    // Fundo escurecido
                    AnimatedOpacity(
                      opacity: 0.5,
                      duration: const Duration(milliseconds: 150),
                      child: Container(color: Colors.black54),
                    ),

                    // 💫 Efeito de expansão circular
                    Positioned(
                      left: center.dx - waveRadius / 2,
                      top: center.dy - waveRadius / 2,
                      child: Container(
                        width: waveRadius,
                        height: waveRadius,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              const Color(0xFF4A90E2).withOpacity(0.4 * (1 - progress)),
                              const Color(0xFF007AFF).withOpacity(0.3 * (1 - progress)),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),

                    // 🧭 Menu circular principal sem texto
                    Positioned(
                      left: center.dx - 75,
                      top: center.dy - 75,
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutBack,
                        scale: _animationController.value,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Fundo translúcido
                            Container(
                              width: 150,
                              height: 150,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withOpacity(0.65),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.3),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blueAccent.withOpacity(0.4),
                                    blurRadius: 25,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                            ),

                            // 🧍 Ícone "Info do jogador"
                            Positioned(
                              top: 10,
                              child: GestureDetector(
                                onTap: () {
                                  _removeRadialMenu();
                                  _showPlayerInfo(userName, photoUrl, userId: runData['userId']);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [Color(0xFF4A90E2), Color(0xFF007AFF)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: const Icon(Icons.person, color: Colors.white, size: 30),
                                ),
                              ),
                            ),

                            // 🏁 Ícone "Detalhes da corrida"
                            Positioned(
                              bottom: 10,
                              child: GestureDetector(
                                onTap: () {
                                  _removeRadialMenu();
                                  _showRunDetailsPopup(runData);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [Color(0xFFFF6D00), Color(0xFFE53935)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: const Icon(Icons.flag_rounded, color: Colors.white, size: 30),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    Overlay.of(context).insert(_radialMenuOverlay!);
  }






  void _removeRadialMenu() {
    _isHoldingMarker = false;
    _radialMenuOverlay?.remove();
    _radialMenuOverlay = null;
  }


  Widget _buildRadialButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF4A90E2), Color(0xFF007AFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showLoadingOverlay(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) {
        return Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                height: 110,
                width: 110,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blueAccent.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Center(
                  child: SizedBox(
                    height: 50,
                    width: 50,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      valueColor:
                      AlwaysStoppedAnimation<Color>(Color(0xFF4A90E2)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }


  void _showPlayerInfo(String name, String? photoUrl, {String? userId}) {
    final currentUser = FirebaseAuth.instance.currentUser!;
    final followsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('following');

    bool isFollowing = false;
    int followersCount = 0;
    int followingCount = 0;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6), // fundo levemente escurecido
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // 🔹 Carrega status de follow e contadores
            if (userId != null) {
              followsRef.doc(userId).get().then((doc) {
                if (doc.exists && !isFollowing) {
                  setState(() => isFollowing = true);
                }
              });

              FirebaseFirestore.instance
                  .collection('users')
                  .doc(userId)
                  .collection('followers')
                  .get()
                  .then((snapshot) {
                setState(() => followersCount = snapshot.size);
              });

              FirebaseFirestore.instance
                  .collection('users')
                  .doc(userId)
                  .collection('following')
                  .get()
                  .then((snapshot) {
                setState(() => followingCount = snapshot.size);
              });
            }

            Future<void> toggleFollow() async {
              if (userId == null || userId == currentUser.uid) return;

              final targetUserRef =
              FirebaseFirestore.instance.collection('users').doc(userId);
              final currentUserRef =
              FirebaseFirestore.instance.collection('users').doc(currentUser.uid);

              if (isFollowing) {
                await followsRef.doc(userId).delete();
                await targetUserRef.collection('followers').doc(currentUser.uid).delete();
                setState(() {
                  isFollowing = false;
                  followersCount = (followersCount > 0) ? followersCount - 1 : 0;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Deixou de seguir o jogador')),
                );
              } else {
                await followsRef.doc(userId).set({'followedAt': Timestamp.now()});
                await targetUserRef.collection('followers').doc(currentUser.uid).set({
                  'followedAt': Timestamp.now(),
                });
                setState(() {
                  isFollowing = true;
                  followersCount += 1;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Agora você segue este jogador')),
                );
              }
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
              shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(25),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(25),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.12),
                          Colors.white.withOpacity(0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 1.4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blueAccent.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 🔹 Avatar + nome + stats
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 40,
                              backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                                  ? NetworkImage(photoUrl)
                                  : null,
                              backgroundColor: Colors.white,
                              child: (photoUrl == null || photoUrl.isEmpty)
                                  ? const Icon(Icons.person,
                                  color: Colors.black, size: 40)
                                  : null,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Text(
                                        "$followersCount seguidores",
                                        style: const TextStyle(
                                          color: Colors.black12,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        "$followingCount seguindo",
                                        style: const TextStyle(
                                          color: Colors.black12,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 25),

                        // 🔹 Botão de seguir / seguindo
                        if (userId != null && userId != currentUser.uid)
                          ElevatedButton.icon(
                            icon: Icon(
                              isFollowing
                                  ? Icons.check_rounded
                                  : Icons.person_add_alt_1_rounded,
                              color: Colors.white,
                            ),
                            label: Text(
                              isFollowing ? "Seguindo" : "Seguir",
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: isFollowing
                                  ? Colors.green.withOpacity(0.8)
                                  : const Color(0xFF4A90E2).withOpacity(0.8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 25, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: toggleFollow,
                          ),

                        const SizedBox(height: 20),

                        // 🔹 Botão de fechar
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            "Fechar",
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }





  /// Detecta long press e arrasto no mapa
  void _handleMapGesture(LatLng markerPos, String userName, String? photoUrl, Map<String, dynamic> runData) {
    _activeMarkerOverlay?.remove();

    _activeMarkerOverlay = OverlayEntry(
      builder: (context) => Positioned(
        left: MediaQuery.of(context).size.width / 2 - 100,
        bottom: 150,
        child: GestureDetector(
          onHorizontalDragUpdate: (details) async {
            if (details.primaryDelta != null && details.primaryDelta! > 25) {
              _activeMarkerOverlay?.remove();
              _activeMarkerOverlay = null;
              HapticFeedback.mediumImpact();
              await Future.delayed(const Duration(milliseconds: 120));
              _showRunDetailsPopup(runData);
            }
          },
          onTapUp: (_) => _activeMarkerOverlay?.remove(),
          child: AnimatedOpacity(
            opacity: 1,
            duration: const Duration(milliseconds: 150),
            child: Container(
              width: 200,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF4A90E2), Color(0xFF007AFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF007AFF).withOpacity(0.4),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                        ? NetworkImage(photoUrl)
                        : null,
                    backgroundColor: const Color(0xFF4A90E2),
                    child: (photoUrl == null || photoUrl.isEmpty)
                        ? const Icon(Icons.person, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          style: GoogleFonts.poppins(
                            textStyle: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          "${(runData['distance'] / 1000).toStringAsFixed(2)} km",
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_activeMarkerOverlay!);
    HapticFeedback.lightImpact();
  }

  /// Associa o gesto “press and hold” a cada marcador
  void _enableMarkerGestures() {
    for (final markerPos in _markerGestures.keys) {
      final (name, photo, data) = _markerGestures[markerPos]!;

      // Simula gesto de pressionar sobre o marcador
      _markers.add(
        Marker(
          markerId: MarkerId("runner_${markerPos.latitude}_${markerPos.longitude}"),
          position: markerPos,
          icon: _markers
              .firstWhere((m) => m.position == markerPos)
              .icon, // usa mesmo ícone existente
          onTap: () {
            // Nada em tap curto
          },
          onDragStart: (_) {},
          consumeTapEvents: false,
          onDragEnd: (_) {},
          infoWindow: InfoWindow(
            title: name,
            onTap: () {}, // evita abrir info padrão
          ),
        ),
      );
    }
  }

  /// Encontra o marcador mais próximo da posição do toque
  LatLng? _findNearestMarker(Offset position) {
    if (_googleMapController == null || _markerGestures.isEmpty) return null;
    for (final marker in _markerGestures.keys) {
      // Poderia usar hitbox mais refinada com coordenadas de tela
      // mas aqui simplificamos.
      return marker;
    }
    return null;
  }




  void _showRunDetailsPopup(Map<String, dynamic> runData) {
    if (isWearOS) return; // dialog é desconfortável no relógio

    final distanceKm = (runData['distance'] / 1000).toStringAsFixed(2);
    final duration = Duration(seconds: runData['duration'] ?? 0);
    final timeFormatted =
        "${duration.inHours.toString().padLeft(2, '0')}:${(duration.inMinutes % 60).toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}";
    final calories = runData['calories']?.round() ?? 0;
    final pace = runData['pace'] ?? 0.0;
    final date = DateTime.tryParse(runData['endTime'] ?? '') ?? DateTime.now();

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 25, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(25),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.12),
                    Colors.white.withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1.3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blueAccent.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 🏁 Título
                  Text(
                    "🏁 Corrida registrada",
                    style: GoogleFonts.poppins(
                      textStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}",
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 25),

                  // 📊 Métricas principais
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildGlassMetric(Icons.route, "$distanceKm km"),
                      _buildGlassMetric(Icons.timer, timeFormatted),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildGlassMetric(Icons.local_fire_department, "$calories kcal"),
                      _buildGlassMetric(Icons.speed,
                          "${pace.toStringAsFixed(2)} min/km"),
                    ],
                  ),

                  const SizedBox(height: 30),

                  // 🔹 Botão fechar
                  ElevatedButton.icon(
                    icon: const Icon(Icons.close, color: Colors.white),
                    label: const Text(
                      "Fechar",
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: const Color(0xFFFF6D00).withOpacity(0.9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 30, vertical: 12),
                    ),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassMetric(IconData icon, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.10),
            Colors.white.withOpacity(0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.25), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.deepOrangeAccent, size: 26),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.deepOrangeAccent,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildPopupInfo(IconData icon, String text) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 28),
        const SizedBox(height: 5),
        Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ],
    );
  }
  Future<Map<String, dynamic>> _getPlayerStats(String userId) async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final userData = userDoc.data() ?? {};

      // Pega até 3 conquistas recentes
      final achievementsQuery = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('achievements')
          .orderBy('timestamp', descending: true)
          .limit(3)
          .get();

      final achievements = achievementsQuery.docs
          .map((a) => a.data()['icon'] ?? '🏅')
          .toList();

      return {
        'displayName': userData['displayName'] ?? 'Jogador',
        'photoURL': userData['photoURL'],
        'xp': userData['xp'] ?? 0,
        'level': userData['level'] ?? 1,
        'achievements': achievements,
      };
    } catch (e) {
      debugPrint("Erro ao carregar estatísticas do jogador: $e");
      return {};
    }
  }

  void _showPlayerCard(BuildContext context, String userId, {required Map<String, dynamic> runData}) async {
    debugPrint("📊 Abrindo card para $userId com dados: ${runData.keys}");
    final stats = await _getPlayerStats(userId);
    if (stats.isEmpty) {
      debugPrint("⚠️ Nenhum dado retornado — card abortado");
      return;
    }
    if (stats.isEmpty) {
      debugPrint("⚠️ Stats vazias, mas exibindo card básico mesmo assim.");
    }

    // --- prepara métricas da corrida selecionada ---
    final distanceKm = ((runData['distance'] ?? 0) / 1000).toStringAsFixed(2);
    final durationSec = (runData['duration'] ?? 0) as int;
    final pace = (runData['pace'] ?? 0.0) as double;
    final calories = (runData['calories'] ?? 0).round();
    final when = DateTime.tryParse(runData['endTime'] ?? '') ?? DateTime.now();
    String _fmt2(int n) => n.toString().padLeft(2, '0');
    String _fmtDuration(int s) => "${_fmt2(s ~/ 3600)}:${_fmt2((s % 3600) ~/ 60)}:${_fmt2(s % 60)}";
    String _fmtPace(double p) {
      if (p.isNaN || p.isInfinite || p <= 0) return "00:00";
      final m = p.floor();
      final s = ((p - m) * 60).round();
      return "${_fmt2(m)}:${_fmt2(s)}";
    }

    // --- follow state (para botão seguir + contadores) ---
    final currentUser = FirebaseAuth.instance.currentUser!;
    final followsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('following');

    bool isFollowing = false;
    int followersCount = 0;
    int followingCount = 0;

    // pré-carrega status/contadores
    try {
      final doc = await followsRef.doc(userId).get();
      isFollowing = doc.exists;

      final followersSnap = await FirebaseFirestore.instance
          .collection('users').doc(userId).collection('followers').get();
      followersCount = followersSnap.size;

      final followingSnap = await FirebaseFirestore.instance
          .collection('users').doc(userId).collection('following').get();
      followingCount = followingSnap.size;
    } catch (_) {}

    Future<void> toggleFollow(StateSetter setStateDialog) async {
      if (userId == currentUser.uid) return; // não segue a si mesmo
      final targetRef = FirebaseFirestore.instance.collection('users').doc(userId);

      if (isFollowing) {
        await followsRef.doc(userId).delete();
        await targetRef.collection('followers').doc(currentUser.uid).delete();
        setStateDialog(() {
          isFollowing = false;
          followersCount = followersCount > 0 ? followersCount - 1 : 0;
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Deixou de seguir o jogador')),
          );
        }
      } else {
        await followsRef.doc(userId).set({'followedAt': Timestamp.now()});
        await targetRef.collection('followers').doc(currentUser.uid).set({
          'followedAt': Timestamp.now(),
        });
        setStateDialog(() {
          isFollowing = true;
          followersCount += 1;
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Agora você segue este jogador')),
          );
        }
      }
    }

    // --- dialog central com efeito glass ---
    await showGeneralDialog(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: true,
      barrierLabel: 'Fechar card do jogador',
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final screenHeight = MediaQuery.of(context).size.height;
            final screenWidth = MediaQuery.of(context).size.width;

            return Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    width: screenWidth * 0.9,
                    constraints: BoxConstraints(
                      maxHeight: screenHeight * 0.6, // ⛔ impede que ultrapasse a tela
                    ),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.5),
                      border: Border.all(color: Colors.white),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 🔹 Cabeçalho com botão Fechar no canto superior direito
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const SizedBox(width: 40), // mantém alinhamento do avatar
                              Text(
                                "Perfil do Jogador",
                                style: GoogleFonts.poppins(
                                  color: Colors.black87,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close_rounded, color: Colors.black87),
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          // 🔹 Avatar + nome + XP/Nível
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 35,
                                backgroundImage: stats['photoURL'] != null
                                    ? NetworkImage(stats['photoURL'])
                                    : null,
                                backgroundColor: Colors.black12,
                                child: stats['photoURL'] == null
                                    ? const Icon(Icons.person, color: Colors.black, size: 35)
                                    : null,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      stats['displayName'],
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                      style: GoogleFonts.poppins(
                                        color: Colors.black,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const Icon(Icons.star, color: Colors.amber, size: 20),
                                        const SizedBox(width: 6),
                                        Text(
                                          "${stats['xp']} XP • Nível ${stats['level']}",
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.poppins(
                                            color: Colors.black87,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // 👥 Seguidores / seguindo + botão seguir
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "$followersCount seguidores • $followingCount seguindo",
                                style: GoogleFonts.poppins(
                                  color: Colors.black87,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (userId != currentUser.uid)
                                ElevatedButton.icon(
                                  icon: Icon(
                                    isFollowing ? Icons.check : Icons.person_add_alt_1,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                  label: Text(
                                    isFollowing ? "Seguindo" : "Seguir",
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    elevation: 0,
                                    backgroundColor: isFollowing
                                        ? const Color(0xFFFF6D00)
                                        : Colors.black,
                                    padding:
                                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () => toggleFollow(setStateDialog),
                                ),
                            ],
                          ),

                          const SizedBox(height: 24),

                          // 🏅 Conquistas recentes
                          if ((stats['achievements'] as List).isNotEmpty)
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 10,
                              runSpacing: 8,
                              children: (stats['achievements'] as List)
                                  .map<Widget>((icon) => AnimatedScale(
                                scale: 1.08,
                                duration: const Duration(milliseconds: 400),
                                child: Text(icon, style: const TextStyle(fontSize: 28)),
                              ))
                                  .toList(),
                            )
                          else
                            Text(
                              "Nenhuma insígnia conquistada ainda",
                              style: GoogleFonts.poppins(
                                color: Colors.black87,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),

                          const SizedBox(height: 5),

                          // 📊 NOVA SEÇÃO DE MÉTRICAS — organizada em GRID simétrica
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),

                            child: GridView.count(
                              crossAxisCount: 2,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              children: [
                                _buildMetricCard(Icons.route, "$distanceKm km", "Distância"),
                                _buildMetricCard(Icons.timer, _fmtDuration(durationSec), "Tempo"),
                                _buildMetricCard(
                                    Icons.local_fire_department, "$calories kcal", "Calorias"),
                                _buildMetricCard(Icons.speed, "${_fmtPace(pace)} min/km", "Ritmo"),
                              ],
                            ),
                          ),

                          const SizedBox(height: 10),

                          Text(
                            "${_fmt2(when.day)}/${_fmt2(when.month)}/${when.year}",
                            style: GoogleFonts.poppins(
                              color: Colors.black87,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),

                          const SizedBox(height: 5),
                        ],
                      ),
                    ),

                  ),
                ),
              ),
            );
          },
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: CurvedAnimation(
              parent: anim1,
              curve: Curves.easeOutBack,
            ),
            child: child,
          ),
        );
      },
    );

  }

  Future<void> _applyRunDistanceToActiveChallenges({required double distanceMeters}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DateTime.now();

    // Desafios ativos em que o usuário está inscrito
    final qs = await FirebaseFirestore.instance
        .collection('challenges')
        .where('participantsIds', arrayContains: user.uid)
        .where('deadline', isGreaterThan: Timestamp.fromDate(now))
        .get();

    for (final doc in qs.docs) {
      final challenge = doc.data();
      final targetKm = (challenge['targetKm'] ?? 0).toDouble();
      if (targetKm <= 0) continue;

      final partRef = doc.reference.collection('participants').doc(user.uid);
      final partSnap = await partRef.get();

      if (!partSnap.exists) continue;
      final status = partSnap['status'] ?? 'active';
      if (status != 'active') continue;

      final current = (partSnap['progressMeters'] ?? 0.0).toDouble();
      double next = current + distanceMeters;
      final targetMeters = targetKm * 1000.0;

      // atingiu meta?
      final completed = next >= targetMeters;

      await partRef.update({
        'progressMeters': next,
        'status': completed ? 'completed' : 'active',
        if (completed) 'finishedAt': FieldValue.serverTimestamp(),
        'lastUpdate': FieldValue.serverTimestamp(),
      });
    }
  }



  DateTime _getCurrentWeekStart() {
    final now = DateTime.now();
    return now.subtract(Duration(days: now.weekday - 1)); // segunda-feira da semana atual
  }


}

Future<BitmapDescriptor> _createUserCircleIcon({
  double size = 60,
  Color borderColor = Colors.white,
  Color fillColor = Colors.blueAccent,
}) async {
  final pictureRecorder = ui.PictureRecorder();
  final canvas = Canvas(pictureRecorder);
  final paint = Paint()..isAntiAlias = true;

  // Fundo transparente
  canvas.drawColor(Colors.transparent, BlendMode.clear);

  // Círculo externo (borda)
  paint.color = borderColor;
  canvas.drawCircle(Offset(size / 2, size / 2), size / 2, paint);

  // Círculo interno (preenchimento)
  paint.color = fillColor;
  canvas.drawCircle(Offset(size / 2, size / 2), size / 2.8, paint);

  final img =
  await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
}
