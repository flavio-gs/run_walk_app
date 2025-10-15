import 'dart:math';
import 'package:flutter/material.dart';
import 'package:run_walk_app/run_tracker.dart';
import 'package:run_walk_app/historico_page.dart';
import 'package:run_walk_app/profile_page.dart';
import 'package:run_walk_app/feed_page.dart';

class MainScaffold extends StatefulWidget {
  final int initialIndex;

  const MainScaffold({super.key, this.initialIndex = 2});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold>
    with SingleTickerProviderStateMixin {
  late int _selectedIndex;
  late AnimationController _pulseController;

  final List<Widget> _pages = const [
    FeedPage(),
    Center(child: Text("Comunidade", style: TextStyle(color: Colors.white))),
    RunTrackingPage(),
    HistoricoPage(),
    ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;

    // Controlador do efeito de pulso
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
      lowerBound: 0.7,
      upperBound: 1.1,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _pages[_selectedIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF00C853), // Verde
              Color(0xFFFF6D00), // Laranja
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.black.withOpacity(0.85),
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white70,
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          showUnselectedLabels: true,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
          items: [
            _navItem(Icons.dashboard, "Feed", 0),
            _navItem(Icons.people, "Comunidade", 1),
            _activityItem(Icons.bolt, "Atividade", 2), // Ícone com pulso
            _navItem(Icons.bar_chart, "Progresso", 3),
            _navItem(Icons.person, "Perfil", 4),
          ],
        ),
      ),
    );
  }

  // --- Ítens padrão da barra ---
  BottomNavigationBarItem _navItem(IconData icon, String label, int index) {
    final isSelected = _selectedIndex == index;
    return BottomNavigationBarItem(
      icon: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: isSelected
              ? const LinearGradient(
            colors: [Color(0xFF00C853), Color(0xFFFF6D00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
              : null,
        ),
        child: Icon(
          icon,
          color: isSelected ? Colors.white : Colors.white70,
        ),
      ),
      label: label,
    );
  }

  // --- Ícone central com efeito de pulso ---
  BottomNavigationBarItem _activityItem(IconData icon, String label, int index) {
    final isSelected = _selectedIndex == index;

    return BottomNavigationBarItem(
      icon: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final scale = isSelected ? _pulseController.value : 1.0;
          final glowOpacity = isSelected ? (sin(_pulseController.value * pi).abs()) * 0.6 : 0.0;


          return Transform.scale(
            scale: scale,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isSelected
                    ? const LinearGradient(
                  colors: [Color(0xFF00C853), Color(0xFFFF6D00)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
                    : null,
                boxShadow: isSelected
                    ? [
                  BoxShadow(
                    color: const Color(0xFF00C853)
                        .withOpacity(0.5 * glowOpacity),
                    blurRadius: 15 + 10 * glowOpacity,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: const Color(0xFFFF6D00)
                        .withOpacity(0.5 * glowOpacity),
                    blurRadius: 20 + 10 * glowOpacity,
                    spreadRadius: 4,
                  ),
                ]
                    : [],
              ),
              child: Icon(
                icon,
                size: isSelected ? 32 : 26,
                color: Colors.white,
              ),
            ),
          );
        },
      ),
      label: label,
    );
  }
}
