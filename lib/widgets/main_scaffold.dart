import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ haptic
import 'package:run_walk_app/feed_page.dart';
import 'package:run_walk_app/run_tracker.dart';
import 'package:run_walk_app/profile_page.dart';
import 'package:run_walk_app/feedback_page.dart';
import 'package:run_walk_app/community_page.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:run_walk_app/service/service/gamification_service.dart';

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

  // 🎨 Paleta (mesma das páginas)
  static const Color kOrange = Color(0xFFFF7A00);
  static const Color kBg = Color(0xFF0B0B0F);
  static const Color kCard = Color(0xFF12121A);

  // BottomNav layout (para “pixel perfect”)
  static const double _navHeight = 62;
  static const double _navOuterPaddingH = 14;
  static const double _navOuterPaddingB = 12;

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
      lowerBound: 0.88,
      upperBound: 1.08,
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await GamificationService().registrarBonusDiario(context: context);
      } catch (e) {
        debugPrint("Erro ao registrar bônus diário: $e");
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// 🎯 Centro exato do item na bottom bar flutuante (considera padding + safe area)
  Offset _navItemCenter(int index) {
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final screenH = mq.size.height;

    final navW = screenW - (_navOuterPaddingH * 2);
    final itemW = navW / 5;

    final cx = _navOuterPaddingH + itemW * (index + 0.5);

    // Centro vertical do container da bottom bar flutuante
    final cy = screenH - mq.padding.bottom - _navOuterPaddingB - (_navHeight / 2);

    return Offset(cx, cy);
  }

  void _onItemTapped(int index) async {
    if (index == _selectedIndex || _transitioning) return;

    // ✅ haptics diferentes
    if (index == 2) {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 220), () {
        _audioPlayer.play(AssetSource('sounds/1.mp3'));
      });
    } else {
      HapticFeedback.selectionClick();
    }

    setState(() {
      _transitioning = true;
      _nextIndex = index;
      _transitionCenter = _navItemCenter(index); // ✅ pixel perfect
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
      backgroundColor: kBg,
      extendBody: true, // ✅ evita overflow com bottom bar flutuante
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

      // 🟠 Bottom Navigation (dark + laranja, flutuante)
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: ScaffoldVisibilityController.isVisible,
        builder: (context, visible, _) {
          if (!visible) return const SizedBox.shrink();

          final bottomInset = MediaQuery.of(context).padding.bottom; // ✅ safe area real do device

          return AnimatedSlide(
            offset: visible ? Offset.zero : const Offset(0, 1),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              opacity: visible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 260),
              child: Padding(
                // ✅ aqui fica o “flutuante” + margem externa
                padding: EdgeInsets.fromLTRB(
                  _navOuterPaddingH,
                  0,
                  _navOuterPaddingH,
                  _navOuterPaddingB + bottomInset, // ✅ inclui safe area sem duplicar
                ),
                child: SizedBox(
                  // ✅ altura fixa, não soma com SafeArea
                  height: _navHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      color: kCard.withOpacity(0.96),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white10),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                          color: Colors.black.withOpacity(0.45),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: BottomNavigationBar(
                        type: BottomNavigationBarType.fixed,
                        backgroundColor: Colors.transparent,
                        elevation: 0,
                        selectedItemColor: kOrange,
                        unselectedItemColor: Colors.white54,
                        currentIndex: _selectedIndex,
                        onTap: _onItemTapped,
                        showSelectedLabels: false,
                        showUnselectedLabels: false,
                        items: [
                          _navItem(Icons.dashboard_outlined, 0),
                          _navItem(Icons.people_outline, 1),
                          _activityItem(Icons.bolt_rounded, 2),
                          _navItem(Icons.person_outline, 3),
                          _navItem(Icons.chat_bubble_outline, 4),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }


  /// ✅ ícone normal + pontinho laranja quando selecionado
  BottomNavigationBarItem _navItem(IconData icon, int index) {
    final isSelected = _selectedIndex == index;

    return BottomNavigationBarItem(
      icon: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        scale: isSelected ? 1.10 : 1.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 26,
              color: isSelected ? kOrange : Colors.white54,
            ),
            const SizedBox(height: 5),
            AnimatedOpacity(
              opacity: isSelected ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 180),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: kOrange,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: kOrange.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      label: "",
    );
  }

  /// ✅ botão central com pulse + pontinho + glow
  BottomNavigationBarItem _activityItem(IconData icon, int index) {
    final isSelected = _selectedIndex == index;

    return BottomNavigationBarItem(
      icon: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final scale = isSelected ? _pulseController.value : 1.0;
          final glowOpacity = isSelected
              ? (sin(_pulseController.value * pi).abs()) * 0.55
              : 0.0;

          return Transform.translate(
            offset: const Offset(0, -12), // 🔼 sobe o botão (use -4, -6 ou -8)
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: scale,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? kOrange : Colors.white10,
                      border: Border.all(
                        color: isSelected
                            ? kOrange.withOpacity(0.75)
                            : Colors.white10,
                        width: 1.2,
                      ),
                      boxShadow: isSelected
                          ? [
                        BoxShadow(
                          color: kOrange.withOpacity(glowOpacity * 0.35),
                          blurRadius: 22,
                          spreadRadius: 1.5,
                        ),
                      ]
                          : [],
                    ),
                    child: Icon(
                      icon,
                      size: isSelected ? 34 : 28,
                      color: isSelected ? Colors.black : Colors.white70,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                AnimatedOpacity(
                  opacity: isSelected ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: kOrange,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: kOrange.withOpacity(0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );

        },
      ),
      label: "",
    );
  }

  // ⌚ WearOS mantém simples (dark também)
  Widget _buildWearOSView() {
    return Scaffold(
      backgroundColor: kBg,
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
