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

// Páginas e widgets do seu app
import 'historico_page.dart';
import 'profile_page.dart';
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
                Color(0xFF00C853), // Verde vibrante
                Color(0xFFFF6D00), // Laranja energético
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
                    color: const Color(0xFF00C853).withOpacity(0.6 * glow),
                  ),
                  Shadow(
                    blurRadius: 30 + 15 * glow,
                    color: const Color(0xFFFF6D00).withOpacity(0.5 * glow),
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

  bool _isNightMode = false;


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
  DateTime? _startTime;
  final Stopwatch _stopwatch = Stopwatch();

  final List<LatLng> _positions = [];
  double _totalDistance = 0;
  double _caloriesBurned = 0;
  double _averagePace = 0; // min/km

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

      if (!isWearOS) {
        _googleMapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: _currentPosition, zoom: 17),
          ),
        );
      }
    } catch (e) {
      setState(() => _loadingLocation = false);
    }
  }

  Future<void> _toggleMapStyle() async {
    _isNightMode = !_isNightMode;

    final stylePath = _isNightMode
        ? 'assets/map_style_day.json'
        : 'assets/map_style.json';

    try {
      _mapStyle = await rootBundle.loadString(stylePath);
      await _googleMapController?.setMapStyle(_mapStyle);

      // 🔸 Feedback visual e tátil
      HapticFeedback.selectionClick();
    } catch (e) {
      debugPrint("Erro ao alternar estilo do mapa: $e");
    }

    setState(() {}); // Atualiza o ícone do botão
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

      setState(() {});
    } catch (e) {
      debugPrint("Erro ao carregar corridas: $e");
    }

    // 🔹 Ajuste automático do zoom
    if (_markers.isNotEmpty && _googleMapController != null) {
      await Future.delayed(const Duration(milliseconds: 800));
      _googleMapController?.animateCamera(
        CameraUpdate.newLatLngBounds(
          _calculateBounds(_markers.map((m) => m.position).toList()),
          80,
        ),
      );
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

      if (!isWearOS) {
        _googleMapController?.animateCamera(
          CameraUpdate.newLatLng(latLngPos),
        );
      }

      if (!isWearOS) {
        _startPulseEffect();
      }
    });
  }

  DateTime? _lastPointTime;

  void _updatePolyline() {
    if (isWearOS) return; // economiza no Wear
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
      const Color(0xFF3FA9F5), // Azul
      const Color(0xFFFF3D00), // Vermelho
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

    setState(() {});
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
    _stopPulseEffect();
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

        if (!isWearOS) {
          _googleMapController?.animateCamera(
            CameraUpdate.newLatLng(_currentPosition),
          );
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
                      Color.fromARGB(100, 0, 200, 83),
                      Color.fromARGB(40, 255, 109, 0),
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
                              ? Colors.redAccent
                              : const Color(0xFF00C853))
                              .withOpacity(0.6),
                          blurRadius: 20,
                          spreadRadius: 4,
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
              colors: [Color(0xFF00C853), Color(0xFFFF6D00)],
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

              // 🌗 Alterna automaticamente entre dia e noite
              final hour = DateTime.now().hour;
              final isNight = hour >= 18 || hour < 6;

              final stylePath = isNight
                  ? 'assets/map_style.json'
                  : 'assets/map_style_day.json';

              try {
                _mapStyle = await rootBundle.loadString(stylePath);
                await _googleMapController?.setMapStyle(_mapStyle);
              } catch (e) {
                debugPrint("Erro ao aplicar estilo do mapa: $e");
              }

              // 🔹 Atualiza o marcador atual
              _updateMarker();
            },


            polylines: _polylines,
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

          IgnorePointer(
            ignoring: true,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color.fromARGB(90, 0, 200, 83),
                    Color.fromARGB(40, 255, 109, 0),
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

// 🌞🌙 Botão de alternância de modo do mapa
          Positioned(
            bottom: 20,
            left: 20,
            child: GestureDetector(
              onTap: _toggleMapStyle,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: _isNightMode
                        ? [const Color(0xFF00C853), const Color(0xFFFF6D00)] // noite
                        : [const Color(0xFFFFD740), const Color(0xFFFF6D00)], // dia
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(2, 3),
                    ),
                  ],
                ),
                child: Icon(
                  _isNightMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  color: Colors.white,
                  size: 28,
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
                    colors: [Color(0xFF00C853), Color(0xFFFF6D00)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(2, 3),
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
                              color: const Color(0xFF00C853)
                                  .withOpacity(0.6 * pulse),
                              blurRadius: 25 + 20 * pulse,
                              spreadRadius: 6 + 2 * pulse,
                            ),
                            BoxShadow(
                              color: const Color(0xFFFF6D00)
                                  .withOpacity(0.5 * pulse),
                              blurRadius: 30 + 10 * pulse,
                              spreadRadius: 3,
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
                              colors: [Colors.redAccent, Color(0xFFFF6D00)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                                : const LinearGradient(
                              colors: [
                                Color(0xFF00C853),
                                Color(0xFFFF6D00)
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (_isRunning
                                    ? Colors.redAccent
                                    : const Color(0xFF00C853))
                                    .withOpacity(0.6),
                                blurRadius: 20,
                                spreadRadius: 5,
                              )
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
              colors: [Color(0xFF00C853), Color(0xFFFF6D00)],
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
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (context) => const MainScaffold(initialIndex: 3)),
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
        if (!isWearOS) {
          _polylines.clear();
          _markers.clear();
        }
      });
      await _setInitialLocation();
    }
  }

  Future<void> _addRunMarker({
    required LatLng position,
    required String userName,
    String? photoUrl,
    required Map<String, dynamic> runData,
  }) async {
    if (isWearOS) return; // sem marcador no relógio

    try {
      const double width = 180;
      const double height = 90;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..isAntiAlias = true;

      // Fundo do card com leve gradiente diagonal
      final gradient = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(width, height),
        [
          const Color(0xFF00C853).withOpacity(0.9),
          const Color(0xFFFF6D00).withOpacity(0.9),
        ],
      );
      paint.shader = gradient;
      final rrect = RRect.fromLTRBR(0, 0, width, height, const Radius.circular(18));
      canvas.drawRRect(rrect, paint);

      // Camada de sombra interna estilo Pokémon Go
      paint.shader = null;
      paint.color = Colors.black.withOpacity(0.25);
      canvas.drawRRect(
        RRect.fromLTRBR(2, 2, width - 2, height - 2, const Radius.circular(16)),
        paint,
      );

      // Foto circular do jogador
      const double avatarSize = 70;
      final avatarOffset = const Offset(15, 10);
      final avatarRect = Rect.fromCircle(center: avatarOffset.translate(avatarSize / 2, avatarSize / 2), radius: avatarSize / 2);

      if (photoUrl != null && photoUrl.isNotEmpty) {
        try {
          final bytes =
          (await NetworkAssetBundle(Uri.parse(photoUrl)).load(photoUrl))
              .buffer
              .asUint8List();
          final codec = await ui.instantiateImageCodec(bytes,
              targetWidth: avatarSize.toInt(), targetHeight: avatarSize.toInt());
          final frame = await codec.getNextFrame();
          final image = frame.image;

          paint.isAntiAlias = true;
          final clipPath = Path()..addOval(avatarRect);
          canvas.save();
          canvas.clipPath(clipPath);
          paintImage(canvas: canvas, rect: avatarRect, image: image, fit: BoxFit.cover);
          canvas.restore();

          // borda branca fina ao redor do avatar
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white.withOpacity(0.9);
          canvas.drawCircle(
              avatarOffset.translate(avatarSize / 2, avatarSize / 2),
              avatarSize / 2,
              paint);
        } catch (_) {
          _drawDefaultAvatar(canvas, avatarOffset, avatarSize);
        }
      } else {
        _drawDefaultAvatar(canvas, avatarOffset, avatarSize);
      }

      // Nome do jogador
      final textPainter = TextPainter(
        text: TextSpan(
          text: userName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 18,
            shadows: [
              Shadow(color: Colors.black54, blurRadius: 4),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      );
      textPainter.layout(maxWidth: width - avatarSize - 40);
      textPainter.paint(canvas, Offset(avatarSize + 30, height / 2 - 10));

      // Subtexto com data ou distância (extra Pokémon Go vibe)
      final distanceKm = (runData['distance'] / 1000).toStringAsFixed(2);
      final subText = TextPainter(
        text: TextSpan(
          text: '$distanceKm km',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      subText.layout(maxWidth: width - avatarSize - 40);
      subText.paint(canvas, Offset(avatarSize + 30, height / 2 + 12));

      // Finaliza imagem
      final img = await recorder.endRecording().toImage(width.toInt(), height.toInt());
      final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();

      final marker = Marker(
        markerId: MarkerId("run_marker_${position.latitude}_${position.longitude}"),
        position: position,
        icon: BitmapDescriptor.fromBytes(bytes),
        anchor: const Offset(0.5, 1.1),
        zIndex: 9999,
        onTap: () => _showRunDetailsPopup(runData),
      );

      setState(() => _markers.add(marker));
    } catch (e) {
      debugPrint("❌ Erro ao criar marcador estilizado: $e");
    }
  }

  void _drawDefaultAvatar(Canvas canvas, Offset offset, double size) {
    final paint = Paint()
      ..color = const Color(0xFF00C853)
      ..isAntiAlias = true;
    canvas.drawCircle(offset.translate(size / 2, size / 2), size / 2, paint);
    final iconPainter = TextPainter(
      text: const TextSpan(
        text: "🏃‍♀️",
        style: TextStyle(fontSize: 32),
      ),
      textDirection: TextDirection.ltr,
    );
    iconPainter.layout();
    iconPainter.paint(canvas, offset.translate(size / 2 - 16, size / 2 - 16));
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
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00C853), Color(0xFFFF6D00)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.85),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "🏁 Corrida registrada",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}",
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildPopupInfo(Icons.route, "$distanceKm km"),
                    _buildPopupInfo(Icons.timer, timeFormatted),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildPopupInfo(Icons.local_fire_department, "$calories kcal"),
                    _buildPopupInfo(
                        Icons.speed, "${pace.toStringAsFixed(2)} min/km"),
                  ],
                ),
                const SizedBox(height: 15),
                ElevatedButton.icon(
                  icon: const Icon(Icons.close, color: Colors.white),
                  label: const Text(
                    "Fechar",
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6D00),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
          ),
        ),
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
