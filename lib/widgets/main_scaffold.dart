import 'dart:math';
import 'package:flutter/material.dart';
import 'package:run_walk_app/feed_page.dart';
import 'package:run_walk_app/run_tracker.dart';
import 'package:run_walk_app/historico_page.dart';
import 'package:run_walk_app/profile_page.dart';
import 'package:run_walk_app/activity_page.dart';
import 'package:run_walk_app/feedback_page.dart';
import 'package:run_walk_app/community_page.dart';
import 'package:audioplayers/audioplayers.dart';

// ✅ Controlador global para esconder/mostrar o Scaffold
class ScaffoldVisibilityController {
  static final ValueNotifier<bool> isVisible = ValueNotifier(true);
  static void hide() => isVisible.value = false;
  static void show() => isVisible.value = true;
}

class MainScaffold extends StatefulWidget {
  final int initialIndex;

  const MainScaffold({super.key, this.initialIndex = 2});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _transitioning = false;
  int? _nextIndex;
  late Offset _transitionCenter;

  late int _selectedIndex;
  late AnimationController _pulseController;
  late PageController _pageController;

  bool get isWearOS {
    final size = MediaQueryData.fromWindow(WidgetsBinding.instance.window).size;
    return size.shortestSide < 300;
  }

  final List<Widget> _pages = const [
    FeedPage(),
    CommunityPage(),
    RunTrackingPage(),
    ProfilePage(),
    FeedbackPage(),
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _selectedIndex);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
      lowerBound: 0.8,
      upperBound: 1.1,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) async {
    if (index == _selectedIndex || _transitioning) return;

    if (index == 2) {
      Future.delayed(const Duration(milliseconds: 300), () {
        _audioPlayer.play(AssetSource('sounds/1.mp3'));
      });
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final itemWidth = screenWidth / 7;
    final center =
    Offset(itemWidth * (index + 0.5), MediaQuery.of(context).size.height - 40);

    setState(() {
      _transitioning = true;
      _nextIndex = index;
      _transitionCenter = center;
    });
  }

  void _onPageChanged(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return isWearOS ? _buildWearOSView() : _buildMobileView();
  }

  // 📱 -------- MOBILE VIEW --------
  Widget _buildMobileView() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned.fill(child: _pages[_selectedIndex]),

          if (_transitioning)
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 600),
                tween: Tween(begin: 0.0, end: 1.0),
                onEnd: () {
                  setState(() {
                    _transitioning = false;
                    _selectedIndex = _nextIndex!;
                    _nextIndex = null;
                  });
                },
                builder: (context, value, child) {
                  return ClipPath(
                    clipper: _CircularRevealClipper(
                      fraction: value,
                      center: _transitionCenter,
                    ),
                    child: _pages[_nextIndex!],
                  );
                },
              ),
            ),
        ],
      ),

      // ⚫ Bottom Navigation Bar minimalista preta
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: ScaffoldVisibilityController.isVisible,
        builder: (context, visible, _) {
          if (!visible) return const SizedBox.shrink();

          return AnimatedOpacity(
            opacity: visible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 400),
            child: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.white,
              selectedItemColor: Colors.black,
              unselectedItemColor: Colors.grey.shade400,
              currentIndex: _selectedIndex,
              onTap: _onItemTapped,
              showUnselectedLabels: false,
              items: [
                _navItem(Icons.dashboard_outlined, 0),
                _navItem(Icons.people_outline, 1),
                _activityItem(Icons.bolt, 2),
                _navItem(Icons.person_outline, 3),
                _navItem(Icons.chat_bubble_outline, 4),
              ],
            ),
          );
        },
      ),
    );
  }

  BottomNavigationBarItem _navItem(IconData icon, int index) {
    final isSelected = _selectedIndex == index;
    return BottomNavigationBarItem(
      icon: AnimatedScale(
        duration: const Duration(milliseconds: 200),
        scale: isSelected ? 1.2 : 1.0,
        child: Icon(icon,
            color: isSelected ? Colors.black : Colors.grey.shade400, size: 26),
      ),
      label: "",
    );
  }

  BottomNavigationBarItem _activityItem(IconData icon, int index) {
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
                color: isSelected ? Colors.black : Colors.black12,
                boxShadow: isSelected
                    ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(glowOpacity * 0.3),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ]
                    : [],
              ),
              child: Icon(icon,
                  size: isSelected ? 34 : 28,
                  color: isSelected ? Colors.white : Colors.black),
            ),
          );
        },
      ),
      label: "",
    );
  }

  Widget _buildWearOSView() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: PageView.builder(
          controller: _pageController,
          onPageChanged: _onPageChanged,
          scrollDirection: Axis.vertical,
          itemCount: _pages.length,
          itemBuilder: (context, index) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _pages[index],
          ),
        ),
      ),
    );
  }
}

// 💥 Transição de raio circular personalizada
class _CircularRevealClipper extends CustomClipper<Path> {
  final double fraction;
  final Offset center;

  _CircularRevealClipper({required this.fraction, required this.center});

  @override
  Path getClip(Size size) {
    final radius = fraction * (size.longestSide * 1.2);
    return Path()..addOval(Rect.fromCircle(center: center, radius: radius));
  }

  @override
  bool shouldReclip(_CircularRevealClipper oldClipper) =>
      oldClipper.fraction != fraction || oldClipper.center != center;
}
