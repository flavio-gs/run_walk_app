import 'dart:math';
import 'package:flutter/material.dart';
import 'package:run_walk_app/feed_page.dart';
import 'package:run_walk_app/run_tracker.dart';
import 'package:run_walk_app/historico_page.dart';
import 'package:run_walk_app/profile_page.dart';

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
  late PageController _pageController;

  bool get isWearOS {
    final size = MediaQueryData.fromWindow(WidgetsBinding.instance.window).size;
    return size.shortestSide < 300;
  }

  final List<Widget> _pages = const [
    FeedPage(),
    Center(child: Text("Comunidade", style: TextStyle(color: Colors.white))),
    RunTrackingPage(),
    HistoricoPage(),
    ProfilePage(),
  ];

  final List<String> _titles = const [
    "Feed",
    "Comunidade",
    "Atividade",
    "Progresso",
    "Perfil",
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _selectedIndex);

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
    _pageController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
    _pageController.jumpToPage(index);
  }

  void _onPageChanged(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return isWearOS ? _buildWearOSView() : _buildMobileView();
  }

  // 📱 -------- MOBILE VIEW (com BottomNavigationBar) --------
  Widget _buildMobileView() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _pages[_selectedIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF00C853), Color(0xFFFF6D00)],
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
            _activityItem(Icons.bolt, "Atividade", 2),
            _navItem(Icons.bar_chart, "Progresso", 3),
            _navItem(Icons.person, "Perfil", 4),
          ],
        ),
      ),
    );
  }

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

  BottomNavigationBarItem _activityItem(IconData icon, String label, int index) {
    final isSelected = _selectedIndex == index;
    return BottomNavigationBarItem(
      icon: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final scale = isSelected ? _pulseController.value : 1.0;
          final glowOpacity =
          isSelected ? (sin(_pulseController.value * pi).abs()) * 0.6 : 0.0;

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


  // ⌚ -------- WEAR OS VIEW (com PageView vertical + gutters) --------
  Widget _buildWearOSView() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // PageView vertical
            PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              scrollDirection: Axis.vertical,
              pageSnapping: true,
              itemCount: _pages.length,
              itemBuilder: (context, index) {
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _pages[index],
                );
              },
            ),

            // 🔹 Indicador de páginas na lateral direita
            Positioned(
              right: 6,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (index) {
                  final isActive = _selectedIndex == index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    width: isActive ? 10 : 6,
                    height: isActive ? 10 : 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: isActive
                          ? const LinearGradient(
                        colors: [Color(0xFF00C853), Color(0xFFFF6D00)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                          : null,
                      color: isActive ? null : Colors.white24,
                    ),
                  );
                }),
              ),
            ),

            // 🔹 Título no topo
            Positioned(
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24, width: 0.6),
                ),
                child: Text(
                  _titles[_selectedIndex],
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ),

            // ✅ GUTTERS: zonas de gesto para trocar de página
            //    Arrastar nessas faixas aciona o PageView e não a ListView interna.
            Positioned.fill(
              child: Column(
                children: const [
                  // topo
                  _WearPageGutter(height: 22),
                  Spacer(),
                  // rodapé
                  _WearPageGutter(height: 22),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }



}

class _WearPageGutter extends StatelessWidget {
  final double height;
  const _WearPageGutter({required this.height});

  @override
  Widget build(BuildContext context) {
    // AbsorbPointer TRUE: bloqueia a lista por baixo
    // HitTest translucent garante que deslize “pegue” em qualquer parte da faixa
    return AbsorbPointer(
      absorbing: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: ColoredBox(color: Colors.transparent),
      ),
    );
  }
}

