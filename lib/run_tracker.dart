import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'historico_page.dart'; 
import 'package:flutter/services.dart' show rootBundle;
import 'dart:ui' as ui;
import 'profile_page.dart';
import 'widgets/main_scaffold.dart';


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
            key: ValueKey(time), // troca suave a cada segundo
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF00E5FF), // ciano
                Color(0xFFFF00FF), // magenta
              ],
            ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
            blendMode: BlendMode.srcIn,
            child: Text(
              time,
              textAlign: TextAlign.center,
              style: TextStyle( // troque por TextStyle(...) se não usar google_fonts
                fontSize: widget.fontSize,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                // glow animado
                shadows: [
                  Shadow(
                    blurRadius: 20 + 10 * glow,
                    color: const Color(0xFF00E5FF).withOpacity(0.6 * glow),
                  ),
                  Shadow(
                    blurRadius: 30 + 15 * glow,
                    color: const Color(0xFFFF00FF).withOpacity(0.5 * glow),
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
  bool loading = false;

  GoogleMapController? _googleMapController;

  Timer? _timer;
  int _seconds = 0;
  bool _isRunning = false;
  DateTime? _startTime;
  final Stopwatch _stopwatch = Stopwatch();

  final List<LatLng> _positions = [];
  double _totalDistance = 0;
  // NOVO: Calorias e Ritmo Médio
  double _caloriesBurned = 0;
  double _averagePace = 0; // min/km

  StreamSubscription<Position>? _positionStream;
  LatLng _currentPosition =
      const LatLng(-23.5505, -46.6333); // fallback (São Paulo)
  bool _loadingLocation = true;
  LocationPermission?
      _locationPermission; // NOVO: Para exibir status da permissão

  late AnimationController _animationController;
  LatLng? _previousPosition;
  LatLng? _animatedPosition;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  // NOVO: Índice da aba selecionada para BottomNavigationBar
  int _selectedIndex = 2; // Atividade selecionada
  String? _mapStyle;

  @override
  void initState() {
    super.initState();

    // Carregar estilo do mapa
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
                (_animatedPosition!.latitude - _previousPosition!.latitude) * t,
            _previousPosition!.longitude +
                (_animatedPosition!.longitude - _previousPosition!.longitude) * t,
          );
          _updateMarker();
        });
      }
    });

    _checkLocationPermissionAndSetInitialLocation();
  }

  // NOVO: Checa permissão de localização antes de tentar obter a posição
  Future<void> _checkLocationPermissionAndSetInitialLocation() async {
    _locationPermission = await Geolocator.checkPermission();
    if (_locationPermission == LocationPermission.denied) {
      _locationPermission = await Geolocator.requestPermission();
    }
    if (_locationPermission == LocationPermission.deniedForever) {
      // Handle denied forever
      setState(() {
        _loadingLocation = false;
      });
      return;
    }
    _setInitialLocation();
  }

  Future<void> _updateMarker() async {
    final customIcon = await _createUserCircleIcon(
      size: 100,
      borderColor: Colors.white.withOpacity(0.9),
      fillColor: Colors.pinkAccent,
    );

    setState(() {
      _markers.clear();
      _markers.add(
        Marker(
          markerId: const MarkerId('currentLocation'),
          position: _currentPosition,
          icon: customIcon,
          anchor: const Offset(0.5, 0.5), // centraliza o círculo
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
        _updateMarker();
      });

      _googleMapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _currentPosition, zoom: 17),
        ),
      );
    } catch (e) {
      setState(() => _loadingLocation = false);
      // Opcional: mostrar um SnackBar ou diálogo de erro para o usuário
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

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _seconds++;
        _calculatePaceAndCalories(); // NOVO: Recalcula a cada segundo
      });
    });

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5, // Notifica a cada 5m para mais precisão
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

        // Adiciona a distância apenas se houve movimento significativo
        if (distance > 0.5) {
          // Evitar pequenas flutuações de GPS
          _totalDistance += distance;
          _positions.add(latLngPos);
          _updatePolyline();
          _calculatePaceAndCalories(); // Recalcula quando a posição muda
        }
      } else {
        _positions.add(latLngPos);
      }

      _previousPosition = _currentPosition;
      _animatedPosition = latLngPos;
      _animationController.forward(from: 0.0);
      _startPulseEffect();
      _googleMapController?.animateCamera(
          CameraUpdate.newLatLng(latLngPos)); // Centraliza no usuário
    });
  }

  DateTime? _lastPointTime;

  void _updatePolyline() {
    if (_positions.length < 2) return;

    final i = _positions.length - 2;
    final start = _positions[i];
    final end = _positions[i + 1];

    // Tempo decorrido entre pontos
    final now = DateTime.now();
    double elapsed = 1.0;
    if (_lastPointTime != null) {
      elapsed = now.difference(_lastPointTime!).inMilliseconds / 1000;
    }
    _lastPointTime = now;

    // Distância e velocidade real
    final distance = Geolocator.distanceBetween(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );
    if (distance < 0.5) return;

    final speed = (distance / elapsed).clamp(0.2, 6.0); // m/s

    // Gradiente: azul → ciano → rosa → vermelho
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
    _pulseTimer?.cancel();
    if (_positions.length < 2) return;

    final pulseIcon = await _createUserCircleIcon(
      size: 80,
      borderColor: Colors.pinkAccent.withOpacity(0.8),
      fillColor: Colors.cyanAccent.withOpacity(0.8),
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

      final lat = start.latitude + (end.latitude - start.latitude) * (_pulseT * (_positions.length - 1) - index);
      final lng = start.longitude + (end.longitude - start.longitude) * (_pulseT * (_positions.length - 1) - index);
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


// Função auxiliar: retorna cor conforme velocidade
  Color _getSpeedColor(double speed) {
    // Mapeia velocidade (m/s) em um gradiente de cores suaves e modernas
    if (speed < 1.0) {
      return const Color(0xFF3FA9F5); // Azul - caminhada leve
    } else if (speed < 2.0) {
      return const Color(0xFF00FFFF); // Ciano - ritmo leve
    } else if (speed < 3.5) {
      return const Color(0xFFFF80FF); // Rosa - corrida média
    } else {
      return const Color(0xFFFF3D00); // Vermelho - corrida intensa
    }
  }



  void _stopRun() {
    _timer?.cancel();
    _positionStream?.cancel();
    _stopwatch.stop();
    _stopPulseEffect();
    setState(() => _isRunning = false);
    _saveRun();
  }

  // NOVO: Função para calcular calorias e ritmo
  void _calculatePaceAndCalories() {
    if (_seconds > 0 && _totalDistance > 0) {
      // Ritmo médio: tempo total (min) / distância total (km)
      _averagePace = (_seconds / 60) / (_totalDistance / 1000); // min/km

      // Cálculo de calorias (simplificado, pode ser mais complexo)
      // Ex: 0.05 calorias por metro percorrido (aproximado)
      _caloriesBurned = (_totalDistance * 0.05); // Exemplo simplificado
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

  // NOVO: Formata o ritmo para "min/km"
  String _formatPace(double pace) {
    if (pace.isInfinite || pace.isNaN || pace <= 0) return '00:00';
    int minutes = pace.floor();
    int seconds = ((pace - minutes) * 60).round();
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionStream?.cancel();
    _animationController.dispose();
    _googleMapController?.dispose();
    super.dispose();
  }

  // NOVO: Método para navegar entre as abas (se precisar em outras telas)
  void _onItemTapped(int index) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => MainScaffold(initialIndex: index)),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "Empire of the Run",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            letterSpacing: 1.2,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // === MAPA ===
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: CameraPosition(
              target: _currentPosition,
              zoom: 16,
            ),
            onMapCreated: (GoogleMapController controller) {
              _googleMapController = controller;
              if (_mapStyle != null) {
                _googleMapController?.setMapStyle(_mapStyle);
              }
              _updateMarker();
            },
            polylines: _polylines,
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),

          // === CAMADA DE INFORMAÇÕES ===
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.black87, Colors.transparent],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
            ),
          ),

          // === CRONÔMETRO DIGITAL ===
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            left: 0,
            right: 0,
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

          // === BOTÃO FLUTUANTE INICIAR/PARAR ===
          Positioned(
            bottom: 120,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _isRunning ? _stopRun : _startRun,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 90,
                  width: 90,
                  decoration: BoxDecoration(
                    color: _isRunning ? Colors.redAccent : Colors.pinkAccent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _isRunning
                            ? Colors.redAccent.withOpacity(0.6)
                            : Colors.pinkAccent.withOpacity(0.6),
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
            ),
          ),
        ],
      ),
    );
  }

// Novo helper para métricas em card circular
  Widget _buildMetricCard(IconData icon, String value, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
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


  // NOVO: Widget auxiliar para exibir as métricas (distância, calorias, ritmo)
  Widget _buildMetricColumn({required String value, required String unit}) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28, // Tamanho da fonte para os valores
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          unit,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // NOVO: Widget auxiliar para os botões de modo de atividade
  Widget _buildActivityModeButton(
      IconData icon, String label, bool isSelected) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.grey[800]
                : Colors.transparent, // Fundo cinza se selecionado
            borderRadius: BorderRadius.circular(8),
            border:
                isSelected ? Border.all(color: Colors.white, width: 0.5) : null,
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey, fontSize: 12),
        ),
      ],
    );
  }

  // --- FUNÇÃO PARA SALVAR A CORRIDA ---
  Future<void> _saveRun() async {
    _stopRun(); // Garante que a corrida está parada antes de salvar


    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  "Usuário não autenticado. Login necessário para salvar.")),
        );
      }
      return;
    }

    if (_totalDistance < 10) {
      // Não salva corridas muito curtas (ex: menos de 10 metros)
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Corrida muito curta para ser salva.")),
        );
      }
      return;
    }

    final runData = {
      'userId': user.uid,
      'startTime': _startTime?.toIso8601String(),
      'endTime': DateTime.now().toIso8601String(),
      'duration': _stopwatch.elapsed.inSeconds,
      'distance': _totalDistance,
      'calories': _caloriesBurned, // Salva as calorias
      'pace': _averagePace, // Salva o ritmo médio
      'path': _positions
          .map((point) => {'lat': point.latitude, 'lng': point.longitude})
          .toList(),
      'createdAt': FieldValue.serverTimestamp(),
    };

    try {
      await FirebaseFirestore.instance.collection('corridas').add(runData);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Corrida salva com sucesso!')),
        );
        // Opcional: Navegar para HistoricoPage após salvar, como no seu código original
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainScaffold(initialIndex: 3)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro ao salvar corrida: $e")),
        );
      }
    } finally {
      // Opcional: Resetar a tela para um estado "pronto para nova corrida"
      setState(() {
        _seconds = 0;
        _totalDistance = 0;
        _caloriesBurned = 0;
        _averagePace = 0;
        _positions.clear();
        _polylines.clear();
        _markers.clear();
        _setInitialLocation(); // Volta para a localização inicial
      });
    }
  }
}

Future<BitmapDescriptor> _createUserCircleIcon({
  double size = 80,
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

  final img = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
}


