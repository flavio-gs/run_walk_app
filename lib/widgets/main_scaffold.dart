import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';

import 'package:run_walk_app/feed_page.dart';
import 'package:run_walk_app/run_tracker.dart';
import 'package:run_walk_app/profile_page.dart';
import 'package:run_walk_app/feedback_page.dart';
import 'package:run_walk_app/community_page.dart';
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

  // Layout bottom nav
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

  static bool _dailyBonusTriggeredThisSession = false;

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

    _triggerDailyBonus();
  }

  void _triggerDailyBonus() {
    if (_dailyBonusTriggeredThisSession) return;
    _dailyBonusTriggeredThisSession = true;

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

  Offset _navItemCenter(int index) {
    final mq = MediaQuery.of(context);
    final navW = mq.size.width - (_navOuterPaddingH * 2);
    final itemW = navW / 5;

    final cx = _navOuterPaddingH + itemW * (index + 0.5);
    final cy = mq.size.height -
        mq.padding.bottom -
        _navOuterPaddingB -
        (_navHeight / 2);

    return Offset(cx, cy);
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex || _transitioning) return;

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
      _transitionCenter = _navItemCenter(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return isWearOS ? _buildWearOSView() : _buildMobileView();
  }

  // 📱 MOBILE
  Widget _buildMobileView() {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final onPrimary = theme.colorScheme.onPrimary;
    final bg = theme.scaffoldBackgroundColor;
    final card = theme.cardColor;
    final fg = theme.colorScheme.onSurface;

    final unselected = fg.withOpacity(0.55);
    final border = fg.withOpacity(0.12);

    return Scaffold(
      backgroundColor: bg,
      extendBody: true,
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
                builder: (context, value, _) {
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
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: ScaffoldVisibilityController.isVisible,
        builder: (context, visible, _) {
          if (!visible) return const SizedBox.shrink();

          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                _navOuterPaddingH,
                0,
                _navOuterPaddingH,
                _navOuterPaddingB,
              ),
              child: SizedBox(
                height: _navHeight,
                child: Container(
                  decoration: BoxDecoration(
                    color: card.withOpacity(0.96),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: border),
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
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      type: BottomNavigationBarType.fixed,
                      currentIndex: _selectedIndex,
                      onTap: _onItemTapped,
                      showSelectedLabels: false,
                      showUnselectedLabels: false,
                      selectedItemColor: primary,
                      unselectedItemColor: unselected,
                      items: [
                        _navItem(Icons.dashboard_outlined, 0, primary, unselected),
                        _navItem(Icons.people_outline, 1, primary, unselected),
                        _activityItem(Icons.bolt_rounded, 2, primary, onPrimary, unselected),
                        _navItem(Icons.person_outline, 3, primary, unselected),
                        _navItem(Icons.chat_bubble_outline, 4, primary, unselected),
                      ],
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

  BottomNavigationBarItem _navItem(
      IconData icon,
      int index,
      Color primary,
      Color unselected,
      ) {
    final isSelected = _selectedIndex == index;

    return BottomNavigationBarItem(
      icon: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        scale: isSelected ? 1.10 : 1.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26, color: isSelected ? primary : unselected),
            const SizedBox(height: 5),
            AnimatedOpacity(
              opacity: isSelected ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 180),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: primary.withOpacity(0.35),
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
      label: '',
    );
  }

  BottomNavigationBarItem _activityItem(
      IconData icon,
      int index,
      Color primary,
      Color onPrimary,
      Color unselected,
      ) {
    final isSelected = _selectedIndex == index;

    return BottomNavigationBarItem(
      icon: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, _) {
          final scale = isSelected ? _pulseController.value : 1.0;
          final glow = isSelected
              ? (sin(_pulseController.value * pi).abs()) * 0.55
              : 0.0;

          return Transform.translate(
            offset: const Offset(0, -12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: scale,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? primary : unselected.withOpacity(0.15),
                      border: Border.all(
                        color: isSelected
                            ? primary.withOpacity(0.75)
                            : unselected.withOpacity(0.15),
                        width: 1.2,
                      ),
                      boxShadow: isSelected
                          ? [
                        BoxShadow(
                          color: primary.withOpacity(glow * 0.35),
                          blurRadius: 22,
                          spreadRadius: 1.5,
                        ),
                      ]
                          : [],
                    ),
                    child: Icon(
                      icon,
                      size: isSelected ? 34 : 28,
                      color: isSelected ? onPrimary : unselected,
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
                      color: primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: primary.withOpacity(0.35),
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
      label: '',
    );
  }

  // ⌚ WearOS
  Widget _buildWearOSView() {
    final bg = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          itemCount: _pages.length,
          itemBuilder: (_, i) => _pages[i],
        ),
      ),
    );
  }
}

// 💥 Reveal circular
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
  bool shouldReclip(_CircularRevealClipper old) =>
      old.fraction != fraction || old.center != center;
}
