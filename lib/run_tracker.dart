import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'historico_page.dart'; // Certifique-se de que este caminho está correto

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

  @override
  void initState() {
    super.initState();
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

    _checkLocationPermissionAndSetInitialLocation(); // NOVO: Checa permissão primeiro
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

  void _updateMarker() {
    _markers.clear();
    _markers.add(
      Marker(
        markerId: const MarkerId('currentLocation'),
        position: _currentPosition,
        icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueBlue), // Mudado para azul como na imagem
      ),
    );
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
      _googleMapController?.animateCamera(
          CameraUpdate.newLatLng(latLngPos)); // Centraliza no usuário
    });
  }

  void _updatePolyline() {
    _polylines.clear();
    _polylines.add(
      Polyline(
        polylineId: const PolylineId('runPath'),
        points: _positions,
        color: Colors.pinkAccent, // Cor da trilha inspirada no Adidas
        width: 6,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    );
    // setState(() {}); // setState não é necessário aqui pois já é chamado por _animationController.addListener
  }

  void _stopRun() {
    _timer?.cancel();
    _positionStream?.cancel();
    _stopwatch.stop();
    setState(() => _isRunning = false);
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
    setState(() {
      _selectedIndex = index;
    });
    // Aqui você pode adicionar a lógica para navegar para outras páginas
    // switch (index) {
    //   case 0:
    //     Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => FeedPage()));
    //     break;
    //   case 1:
    //     // Comunidade
    //     break;
    //   case 2:
    //     // Atividade (já estamos aqui)
    //     break;
    //   case 3:
    //     Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => HistoricoPage())); // Exemplo
    //     break;
    //   case 4:
    //     // Perfil
    //     break;
    // }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, // Para o conteúdo ir por baixo da AppBar
      appBar: AppBar(
        backgroundColor: Colors.transparent, // AppBar transparente
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.star_outline, color: Colors.white, size: 28),
          onPressed: () {
            // Ação do botão estrela
          },
        ),
        title: const Icon(Icons.fitness_center,
            color: Colors.white,
            size: 30), // Ícone Adidas (substituir por Asset real)
        centerTitle: true,
        actions: [
          Row(
            children: [
              // NOVO: Ícone GPS com status (exemplo)
              const Icon(Icons.gps_fixed, color: Colors.green, size: 18),
              const SizedBox(width: 4),
              Text(
                _locationPermission == LocationPermission.always ||
                        _locationPermission == LocationPermission.whileInUse
                    ? 'GPS'
                    : 'Sem GPS',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(width: 10),
            ],
          ),
        ],
      ),
      body: _loadingLocation
          ? const Center(
              child: CircularProgressIndicator(color: Colors.pinkAccent))
          : Stack(
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
                    _updateMarker();
                  },
                  polylines: _polylines,
                  markers: _markers,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  // NOVO: Estilo de mapa escuro, semelhante ao da imagem
                  // Para usar, você precisaria carregar um JSON de estilo.
                  // Exemplo:
                  // style: MapStyle.dark, // se você tiver uma classe MapStyle com um JSON de estilo escuro
                ),

                // === OVERLAY PRINCIPAL COM DADOS (Top Card) ===
                Positioned(
                  top: AppBar().preferredSize.height +
                      MediaQuery.of(context).padding.top +
                      10,
                  left: 0,
                  right: 0,
                  child: Container(
                    // color: Colors.black.withOpacity(0.7), // Fundo translúcido
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 20),
                    child: Column(
                      children: [
                        Text(
                          _formatDuration(Duration(seconds: _seconds)),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 70, // Tamanho grande como na imagem
                            fontWeight: FontWeight.w900,
                            fontFamily:
                                'RobotoMono', // Fonte que remete a display digital
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildMetricColumn(
                              value: (_totalDistance / 1000).toStringAsFixed(2),
                              unit: 'Distância [km]',
                            ),
                            _buildMetricColumn(
                              value: _caloriesBurned.round().toString(),
                              unit: 'Calorias [kcal]',
                            ),
                            _buildMetricColumn(
                              value: _formatPace(_averagePace),
                              unit: 'Ritmo médio [min/km]',
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // NOVO: Desafio Semanal (Placeholder)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 15, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.emoji_events,
                                  color: Colors.white70, size: 20),
                              const SizedBox(width: 10),
                              const Text('Esta semana',
                                  style: TextStyle(color: Colors.white70)),
                              const Spacer(),
                              Text('0/${(30).toStringAsFixed(0)} km',
                                  style: const TextStyle(color: Colors.white)),
                              const SizedBox(width: 5),
                              Container(
                                width: 50,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: Colors.grey[700],
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor: (0 / 30)
                                        .clamp(0.0, 1.0), // Progresso 0/30km
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.pinkAccent,
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // === CONTROLES INFERIORES E BOTÃO INICIAR ===
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      // Botões de modo de atividade (Corrida, Caminhada, etc.)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildActivityModeButton(
                                Icons.directions_run, 'Corrida', true),
                            _buildActivityModeButton(
                                Icons.directions_walk, 'Caminhada', false),
                            _buildActivityModeButton(
                                Icons.directions_bike, 'Ciclismo', false),
                            _buildActivityModeButton(
                                Icons.more_horiz, 'Mais', false),
                          ],
                        ),
                      ),
                      const SizedBox(height: 15),

                      // Botão INICIAR AO VIVO
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Botão de Música (Placeholder)
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.grey[800],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.music_note,
                                    color: Colors.white),
                                onPressed: () {/* Ação de música */},
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: loading
                                    ? null
                                    : _isRunning
                                        ? _stopRun
                                        : _startRun, // Alterna entre iniciar e parar
                                child: Container(
                                  height: 60,
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.black, // Fundo preto
                                    borderRadius: BorderRadius.circular(8),
                                    border: _isRunning
                                        ? Border.all(
                                            color: Colors.red, width: 2)
                                        : null, // Borda vermelha quando correndo
                                  ),
                                  child: Center(
                                    child: loading
                                        ? const CircularProgressIndicator(
                                            color: Colors.pinkAccent)
                                        : Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                  _isRunning
                                                      ? Icons.pause
                                                      : Icons.play_arrow,
                                                  color: _isRunning
                                                      ? Colors.red
                                                      : Colors.white),
                                              const SizedBox(width: 8),
                                              Text(
                                                _isRunning
                                                    ? 'PAUSAR CORRIDA'
                                                    : 'INICIAR AO VIVO',
                                                style: TextStyle(
                                                    color: _isRunning
                                                        ? Colors.red
                                                        : Colors.white,
                                                    fontSize: 18,
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                              const SizedBox(width: 8),
                                              Icon(
                                                  _isRunning
                                                      ? Icons.stop
                                                      : Icons.arrow_forward,
                                                  color: _isRunning
                                                      ? Colors.red
                                                      : Colors.white),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                            ),
                            // Botão de Configurações (Placeholder)
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.grey[800],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.settings,
                                    color: Colors.white),
                                onPressed: () {/* Ação de configurações */},
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 15),

                      // === BOTTOM NAVIGATION BAR ===
                      BottomNavigationBar(
                        type: BottomNavigationBarType
                            .fixed, // Garante que todos os itens são exibidos
                        backgroundColor: Colors.black, // Cor de fundo da barra
                        selectedItemColor:
                            Colors.white, // Cor do ícone/texto selecionado
                        unselectedItemColor:
                            Colors.grey, // Cor dos itens não selecionados
                        currentIndex: _selectedIndex,
                        onTap: _onItemTapped,
                        items: const <BottomNavigationBarItem>[
                          BottomNavigationBarItem(
                            icon: Icon(Icons.menu), // Icone "Feed" na imagem
                            label: 'Feed',
                          ),
                          BottomNavigationBarItem(
                            icon: Icon(
                                Icons.people), // Icone "Comunidade" na imagem
                            label: 'Comunidade',
                          ),
                          BottomNavigationBarItem(
                            icon:
                                Icon(Icons.bolt), // Icone "Atividade" na imagem
                            label: 'Atividade',
                          ),
                          BottomNavigationBarItem(
                            icon: Icon(
                                Icons.bar_chart), // Icone "Progresso" na imagem
                            label: 'Progresso',
                          ),
                          BottomNavigationBarItem(
                            icon:
                                Icon(Icons.person), // Icone "Perfil" na imagem
                            label: 'Perfil',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const HistoricoPage()),
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
