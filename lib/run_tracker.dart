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
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
      lowerBound: 0.2,
      upperBound: 0.9,
    )..repeat(reverse: true);
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
  bool _mapReady = false;
  bool _followUser = true; // 🔓 controla se o mapa deve seguir automaticamente
  bool _isProgrammaticCameraMove = false; // 👈 controla se o movimento é automático
  bool _userIsMovingMap = false;

  OverlayEntry? _radialMenuOverlay;
  Timer? _longPressTimer;
  bool _isHoldingMarker = false;
  Offset? _markerScreenPosition;

  String _areaCapturedFormatted = "0 m²";

  final Set<Polygon> _territoryPolygons = {}; // 🟩 Territórios salvos

  // 🟩 NOVO: Área conquistada
  final Set<Polygon> _polygons = {};
  double _areaCaptured = 0;

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

    // Localização sempre (Wear e Mobile)
    _initLocationFlow();

    // Carregamento do histórico — desativado no Wear para poupar recursos
    if (!isWearOS) {
      _loadSavedRuns();
    }
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
    await _finalizarCorrida();
  }

  Future<void> _updateMarker() async {
    if (isWearOS) return; // sem marcador/Mapa no Wear
    final customIcon = await _createUserCircleIcon(
      size: 60,
      borderColor: const Color(0xFFFF6D00).withOpacity(0.9),
      fillColor: const Color(0xFF00C853),
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
        _seconds++;
        _calculatePaceAndCalories();
      });
    });

    // Stream para corrida (mantido; no Wear não desenhamos polylines/mapa)
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((position) {
      final latLngPos = LatLng(position.latitude, position.longitude);

      if (_positions.isNotEmpty) {
        final distance = Geolocator.distanceBetween(
          _positions.last.latitude,
          _positions.last.longitude,
          latLngPos.latitude,
          latLngPos.longitude,
        );

        if (distance > 0.5) {
          _totalDistance += distance;
          _positions.add(latLngPos);

          if (!isWearOS) {
            _updatePolyline();
          }
          _calculatePaceAndCalories();
        }
      } else {
        _positions.add(latLngPos);
      }

      _previousPosition = _currentPosition;
      _animatedPosition = latLngPos;
      _animationController.forward(from: 0.0);

      if (!isWearOS && _followUser) {
        _googleMapController?.animateCamera(
          CameraUpdate.newLatLng(latLngPos),
        );
      }

      if (!isWearOS && _followUser) {
        _isProgrammaticCameraMove = true;
        _googleMapController?.animateCamera(
          CameraUpdate.newLatLng(latLngPos),
        );
        Future.delayed(const Duration(milliseconds: 300), () {
          _isProgrammaticCameraMove = false;
        });
      }
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


    // 🟩 NOVO: cria área conquistada
    if (_positions.length >= 3) {
      _areaCapturedFormatted = _calculateAreaFormatted(_positions);
      _polygons.clear();
      _polygons.add(
        Polygon(
          polygonId: const PolygonId('territorio'),
          points: List.from(_positions),
          strokeColor: color,
          strokeWidth: 2,
          fillColor: color.withOpacity(0.3),
        ),
      );
    }

    _elapsedSeconds = 0;

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _elapsedSeconds++;
      });
    });

    setState(() {
      _isRunning = true;
      _runEnded = false;
      _elapsedSeconds = 0;
      _totalDistance = 0;
    });

    // inicia o cronômetro
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _elapsedSeconds++);
    });
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

    // 🔹 Formata automaticamente
    if (area >= 1_000_000) {
      return "${(area / 1_000_000).toStringAsFixed(2)} km²";
    } else {
      return "${area.toStringAsFixed(0)} m²";
    }
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
      borderColor: const Color(0xFFFF6D00).withOpacity(0.8),
      fillColor: const Color(0xFF00C853).withOpacity(0.8),
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

  void _stopRun() async {
    _timer?.cancel();
    _stopwatch.stop();
    // _stopPulseEffect();
    setState(() => _isRunning = false);
    await _playStop(); // som apenas no Wear
  }

  void _calculatePaceAndCalories() {
    if (_seconds > 0 && _totalDistance > 0) {
      _averagePace = (_seconds / 60) / (_totalDistance / 1000); // min/km
      _caloriesBurned = (_totalDistance * 0.05);
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

  @override
  void dispose() {
    _timer?.cancel();
    _positionStream?.cancel();
    _animationController.dispose();
    _googleMapController?.dispose();
    _audio.dispose();
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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFF4A90E2), Color(0xFF007AFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
            child: Text(
              "Império da Corrida",
                style: GoogleFonts.russoOne(
                  textStyle: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 1.8,
                    shadows: [
                      Shadow(
                        blurRadius: 12,
                        color: Colors.black45,
                        offset: Offset(2, 2),
                      ),
                    ],
                  ),
                ),
            ),
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: CameraPosition(
              target: _currentPosition,
              zoom: 16,
            ),
            onMapCreated: (GoogleMapController controller) async {
              _googleMapController = controller;
              _mapReady = true; // 👈 marca o mapa como pronto

              try {
                _mapStyle = await rootBundle.loadString('assets/map_style.json');
                await _googleMapController?.setMapStyle(_mapStyle);
              } catch (e) {
                debugPrint("Erro ao aplicar estilo do mapa: $e");
              }

              // 🔹 Espera o mapa estar pronto e a localização carregada antes de centralizar
              if (!_loadingLocation && _currentPosition != const LatLng(-23.5505, -46.6333)) {
                await Future.delayed(const Duration(milliseconds: 300));
                _googleMapController?.animateCamera(
                  CameraUpdate.newLatLngZoom(_currentPosition, 17),
                );
              }

              await _updateMarker();
            },


            onCameraMoveStarted: () {
              // Ignora movimentos de câmera causados por código
              if (_isProgrammaticCameraMove) return;

              _userIsMovingMap = true;
              setState(() => _followUser = false);
            },



            // 🟩 NOVO: adiciona polygons

            polylines: _polylines,
            polygons: {..._polygons, ..._territoryPolygons}, // 🟩 Mostra dominados + atuais
            markers: _markers,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            scrollGesturesEnabled: true,
            zoomGesturesEnabled: true,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            gestureRecognizers: {},
          ),

          // 🟩 NOVO: exibe painel com área conquistada
          Positioned(
            top: MediaQuery.of(context).padding.top + 200,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedOpacity(
                opacity: _areaCaptured > 0 ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.greenAccent.withOpacity(0.5), width: 1),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _areaCapturedFormatted,
                        style: GoogleFonts.orbitron(
                          textStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _isRunning
                            ? "Captura em Progresso"
                            : "Area Capturada",
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          IgnorePointer(
            ignoring: true,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color.fromARGB(80, 0, 122, 255),   // azul iOS translúcido
                    Color.fromARGB(40, 10, 60, 120),   // azul mais escuro sutil
                    Colors.transparent,
                  ],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
            ),
          ),


          IgnorePointer(
            ignoring: true,
            child: Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 40,
                  bottom: 10,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withOpacity(0.4),
                      Colors.transparent,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  children: [
                    FuturisticChrono(seconds: _seconds, fontSize: 70),
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
            ),
          ),

// 🧭 Botão de recentralizar
          Positioned(
            bottom: 20,
            right: 20,
            child: GestureDetector(
              onTap: _recenterMap,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4A90E2), Color(0xFF007AFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4A90E2).withOpacity(0.6),
                      blurRadius: 25,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.my_location_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
          // 🧭 Botão de seguir ou liberar mapa
          Positioned(
            bottom: 90,
            right: 20,
            child: GestureDetector(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _followUser
                          ? "🗺️ Mapa liberado — explore as corridas!"
                          : "📍 Mapa travado na sua posição",
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
                setState(() => _followUser = !_followUser);
                HapticFeedback.lightImpact();
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: _followUser
                        ? [const Color(0xFF00C853), const Color(0xFF4CAF50)] // Verde: seguindo
                        : [const Color(0xFF4A90E2), const Color(0xFF007AFF)], // Azul: livre
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  _followUser ? Icons.lock : Icons.lock_open,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _isRunning
                    ? () async {
                  _stopRun();
                  await _saveRun();
                }
                    : _startRun,
                child: AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    final pulse = (ui.lerpDouble(
                        0,
                        1,
                        (0.5 - (0.5 - _animationController.value).abs()) *
                            2)!);
                    final scale = 1 + (pulse) * 0.1;
                    return Transform.scale(
                      scale: _isRunning ? 1.0 : scale,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF4A90E2).withOpacity(0.6),
                              blurRadius: 25,
                              spreadRadius: 4,
                            ),
                            BoxShadow(
                              color: const Color(0xFF4A90E2).withOpacity(0.6),
                              blurRadius: 25,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          height: 90,
                          width: 90,
                          decoration: BoxDecoration(
                            gradient: _isRunning
                                ? const LinearGradient(
                              colors: [Color(0xFFFF3B30), Color(0xFFE53935)], // 🔴 Vermelho Apple para Stop
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                                : const LinearGradient(
                              colors: [Color(0xFF4A90E2), Color(0xFF007AFF)], // 💙 Azul iOS para Play
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),

                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF4A90E2).withOpacity(0.6),
                                blurRadius: 25,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Icon(
                            _isRunning ? Icons.stop : Icons.play_arrow,
                            color: Colors.white,
                            size: 45,
                          ),
                        ),
                      ),
                    );
                  },
                ),
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

  // ===== Helpers de UI (mobile) =====
  Widget _buildMetricCard(IconData icon, String value, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4A90E2), Color(0xFF007AFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 6,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
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
              content: Text(
                  "Usuário não autenticado. Login necessário para salvar.")),
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

    final runData = {
      'userId': user.uid,
      'startTime': _startTime?.toIso8601String(),
      'endTime': DateTime.now().toIso8601String(),
      'duration': _stopwatch.elapsed.inSeconds,
      'distance': _totalDistance,
      'calories': _caloriesBurned,
      'pace': _averagePace,
      'path': _positions
          .map((point) => {'lat': point.latitude, 'lng': point.longitude})
          .toList(),
      'createdAt': FieldValue.serverTimestamp(),
    };

    try {
      await FirebaseFirestore.instance.collection('corridas').add(runData);

      if (context.mounted && !wearMode) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Corrida salva com sucesso!')),
        );
      }
    } catch (e) {
      if (context.mounted && !wearMode) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro ao salvar corrida: $e")),
        );
      }
    } finally {
      setState(() => loading = false);
      // Reset para próxima corrida
      setState(() {
        _seconds = 0;
        _totalDistance = 0;
        _caloriesBurned = 0;
        _averagePace = 0;
        _positions.clear();

        // 🟩 Mantém polígonos e adiciona os territórios conquistados
        if (!isWearOS) {
          _polylines.clear();
          _markers.clear();
          // não limpar _polygons aqui!
        }
      });

      await _setInitialLocation();
    }
    // 🟩 Salva também o território conquistado
    if (_positions.length >= 3 && _areaCaptured > 0) {
      final territoryData = {
        'userId': user.uid,
        'points': _positions
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
        'area': _areaCaptured,
        'createdAt': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance.collection('territorios').add(territoryData);
      await _loadTerritories();
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
    // ⛔ só pode finalizar se realmente estava em uma corrida ativa
    if (!_isRunning) {
      debugPrint("Ignorado: tentativa de finalizar sem corrida ativa");
      return;
    }
    _timer?.cancel(); // para o cronômetro

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final distance = _totalDistance; // km

    // Evita salvar corridas muito curtas
    if (distance < 0.1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Distância muito curta para registrar corrida."),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // Tempo total em segundos
    final duration = _elapsedSeconds;

    // Pontos: 1 a cada 100m + 5 de bônus
    int earnedPoints = (distance * 10).floor() + 5;

    // Salvar corrida
    await FirebaseFirestore.instance.collection('corridas').add({
      'userId': user.uid,
      'distance': distance,
      'duration': duration,
      'pace': _averagePace,
      'calories': _caloriesBurned,
      'data': DateTime.now(),
    });

    // Adiciona pontos
    await GamificationService().addPoints(earnedPoints, context: context);

    // Atualiza estatísticas e conquistas
    await _updateUserRunStats();
    await AchievementService().checkAchievements(
      runData: {
        'distance': distance,
        'pace': _averagePace,
        'weeklyRuns': weeklyRunsCount,
        'streak': streakDays,
      },
      context: context,
    );

    // Feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("🏁 Corrida salva! +$earnedPoints XP."),
        backgroundColor: Colors.green[700],
      ),
    );

    setState(() {
      _isRunning = false;
      _runEnded = true;
    });
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
          const Color(0xFF4A90E2),
          const Color(0xFF007AFF),
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

          final (name, photo, data) = _markerGestures[position]!;
          final userId = data['userId'];

          // 🧩 Mostra o card com XP e conquistas
          _showPlayerCard(context, userId, runData: data);
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
                              backgroundColor: const Color(0xFF4A90E2),
                              child: (photoUrl == null || photoUrl.isEmpty)
                                  ? const Icon(Icons.person,
                                  color: Colors.white, size: 40)
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
                                      color: Colors.white,
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
                                          color: Colors.white70,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        "$followingCount seguindo",
                                        style: const TextStyle(
                                          color: Colors.white70,
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
                          style: GoogleFonts.orbitron(
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
                    style: GoogleFonts.orbitron(
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
            color: Colors.blueAccent.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 26),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
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
    final stats = await _getPlayerStats(userId);
    if (stats.isEmpty) return;

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
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(25),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.88,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blueAccent.withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // topo: avatar, nome, xp/nível
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 35,
                              backgroundImage: stats['photoURL'] != null
                                  ? NetworkImage(stats['photoURL'])
                                  : null,
                              backgroundColor: Colors.white10,
                              child: stats['photoURL'] == null
                                  ? const Icon(Icons.person, color: Colors.white70)
                                  : null,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    stats['displayName'],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 19,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(Icons.star, color: Colors.amber, size: 20),
                                      const SizedBox(width: 6),
                                      Text(
                                        "${stats['xp']} XP • Nível ${stats['level']}",
                                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // seguidores / seguindo + botão seguir
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.people, color: Colors.white70, size: 18),
                                const SizedBox(width: 6),
                                Text(
                                  "$followersCount seguidores • $followingCount seguindo",
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                              ],
                            ),
                            if (userId != currentUser.uid)
                              ElevatedButton.icon(
                                icon: Icon(isFollowing ? Icons.check : Icons.person_add_alt_1, size: 18),
                                label: Text(isFollowing ? "Seguindo" : "Seguir"),
                                style: ElevatedButton.styleFrom(
                                  elevation: 0,
                                  backgroundColor: (isFollowing
                                      ? Colors.green
                                      : const Color(0xFF4A90E2))
                                      .withOpacity(0.85),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () => toggleFollow(setStateDialog),
                              ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // conquistas recentes (emojis)
                        if ((stats['achievements'] as List).isNotEmpty)
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 10,
                            children: (stats['achievements'] as List)
                                .map<Widget>((icon) => AnimatedScale(
                              scale: 1.08,
                              duration: const Duration(milliseconds: 400),
                              child: Text(icon, style: const TextStyle(fontSize: 28)),
                            ))
                                .toList(),
                          )
                        else
                          const Text(
                            "Nenhuma insígnia conquistada ainda",
                            style: TextStyle(color: Colors.white54, fontSize: 14),
                          ),

                        const SizedBox(height: 16),

                        // métricas da corrida selecionada
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildGlassMetric(Icons.route, "$distanceKm km"),
                            _buildGlassMetric(Icons.timer, _fmtDuration(durationSec)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildGlassMetric(Icons.local_fire_department, "$calories kcal"),
                            _buildGlassMetric(Icons.speed, "${_fmtPace(pace)} min/km"),
                          ],
                        ),

                        const SizedBox(height: 12),
                        Text(
                          "${_fmt2(when.day)}/${_fmt2(when.month)}/${when.year}",
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),

                        const SizedBox(height: 18),

                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            "Fechar",
                            style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w500),
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
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            child: child,
          ),
        );
      },
    );
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
