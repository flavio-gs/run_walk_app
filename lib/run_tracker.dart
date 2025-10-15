import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'historico_page.dart'; 
import 'package:flutter/services.dart' show rootBundle;
import 'dart:ui' as ui;
import 'feed_page.dart';
import 'create_post_page.dart'; // Importa a nova tela

// ... (código do FuturisticChrono State inalterado) ...

class RunTrackingPage extends StatefulWidget {
  const RunTrackingPage({super.key});

  @override
  State<RunTrackingPage> createState() => _RunTrackingPageState();
}

class _RunTrackingPageState extends State<RunTrackingPage>
    with SingleTickerProviderStateMixin {
  
  // ... (variáveis de estado da corrida inalteradas) ...
  GoogleMapController? _googleMapController;
  Timer? _timer;
  int _seconds = 0;
  bool _isRunning = false;
  final List<LatLng> _positions = [];
  double _totalDistance = 0;
  double _caloriesBurned = 0;
  double _averagePace = 0;
  StreamSubscription<Position>? _positionStream;
  LatLng _currentPosition = const LatLng(-23.5505, -46.6333);
  bool _loadingLocation = true;
  String? _mapStyle;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  // --- CONTROLE DE NAVEGAÇÃO ---
  int _selectedIndex = 0; // Começa no Feed

  // Lista de widgets para cada aba
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _setupRunPage();

    // Define as páginas que serão usadas na navegação
    _pages = [
      const FeedPage(),
      const Center(child: Text('Comunidade (em breve)', style: TextStyle(color: Colors.white))),
      _buildActivityPage(), // Página de atividade com mapa
      const HistoricoPage(),
      const Center(child: Text('Perfil (em breve)', style: TextStyle(color: Colors.white))),
    ];
  }

  // ... (código de setup e da corrida inalterado) ...
  void _setupRunPage() { /* ... */ }
  Future<void> _checkLocationPermissionAndSetInitialLocation() async { /* ... */ }
  Future<void> _setInitialLocation() async { /* ... */ }
  Future<void> _updateMarker() async { /* ... */ }
  void _updatePolyline() { /* ... */ }
  Color _getSpeedColor(double speed) { return Colors.red; }
  void _startRun() { /* ... */ }
  void _stopRun() { /* ... */ }
  void _calculatePaceAndCalories() { /* ... */ }

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionStream?.cancel();
    _googleMapController?.dispose();
    super.dispose();
  }

  AppBar _buildAppBar() {
    final titles = [
      'Feed de Atividades',
      'Comunidade',
      'Sua Atividade',
      'Histórico de Corridas',
      'Seu Perfil'
    ];
    String title = titles[_selectedIndex];

    if (_selectedIndex == 0) {
      return AppBar(
        title: Text(title),
        backgroundColor: Colors.grey[900],
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            tooltip: 'Encontrar pessoas',
            onPressed: () { /* ... */ },
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.white),
            tooltip: 'Adicionar publicação',
            onPressed: () {
              // Navega para a tela de criação de post
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CreatePostPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.white),
            tooltip: 'Notificações',
            onPressed: () { /* ... */ },
          ),
        ],
      );
    }

    // ... (outros AppBars inalterados) ...
    if (_selectedIndex == 2) { /* ... */ }
    return AppBar(title: Text(title), backgroundColor: Colors.grey[900], centerTitle: true,);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: _selectedIndex == 2,
      backgroundColor: Colors.black,
      appBar: _buildAppBar(),
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.black.withOpacity(0.9),
        selectedItemColor: Colors.pinkAccent,
        unselectedItemColor: Colors.white70,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "Feed"),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: "Comunidade"),
          BottomNavigationBarItem(icon: Icon(Icons.bolt), label: "Atividade"),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: "Progresso"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Perfil"),
        ],
      ),
    );
  }
  
  // ... (Restante do código inalterado) ...
  Widget _buildActivityPage() { return Stack(); }
  String _formatPace(double pace) { return '00:00'; }
  Widget _buildMetricCard(IconData i, String v, String u) { return Container(); }
  Future<BitmapDescriptor> _createUserCircleIcon({required double size, Color borderColor = Colors.white, Color fillColor = Colors.blue,}) async { throw UnimplementedError(); }
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