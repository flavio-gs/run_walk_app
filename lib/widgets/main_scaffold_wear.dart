import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wearable_rotary/wearable_rotary.dart';
import 'package:run_walk_app/run_tracker_wear.dart';
import '../historico_wear_page.dart';
import '../profile_wear_page.dart';
import '../feedback_wear_page.dart';
import 'rotary_scroll_dispatcher.dart' hide RotaryEvent, RotaryDirection;

class MainScaffoldWear extends StatefulWidget {
  const MainScaffoldWear({super.key});

  @override
  State<MainScaffoldWear> createState() => _MainScaffoldWearState();
}

class _MainScaffoldWearState extends State<MainScaffoldWear> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  StreamSubscription<RotaryEvent>? _rotarySub;

  final List<Widget> _pages = const [
    RunTrackerWearPage(),
    //HistoricoWearPage(),
    ProfileWearPage(),
    FeedbackWearPage(),
  ];

  @override
  void initState() {
    super.initState();

    // 🔹 Escuta rotação física real da coroa (Wear OS)
    _rotarySub = rotaryEvents.listen((event) {
      if (event.direction == RotaryDirection.clockwise) {
        _nextPage();
      } else if (event.direction == RotaryDirection.counterClockwise) {
        _previousPage();
      } else {
        debugPrint("⚠️ Direção de rotação desconhecida: ${event.direction}");
      }
    });
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _currentPage++;
      _pageController.animateToPage(
        _currentPage,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
      HapticFeedback.selectionClick();
      setState(() {});
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _currentPage--;
      _pageController.animateToPage(
        _currentPage,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
      HapticFeedback.selectionClick();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _rotarySub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) => setState(() => _currentPage = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: RotaryScrollDispatcher(
          onRotaryEvent: (e) {
            // 🔁 Compatibilidade: scrollDelta.dy > 0 = descer (próxima página)
            if (e.direction == RotaryDirection.clockwise) {
              _nextPage();
            } else if (e.direction == RotaryDirection.counterClockwise) {
              _previousPage();
            }
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                onPageChanged: _onPageChanged,
                itemCount: _pages.length,
                itemBuilder: (context, index) => AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _pages[index],
                ),
              ),
              // 🔹 Indicadores de página
              Positioned(
                right: 8,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    _pages.length,
                        (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      width: 8,
                      height: _currentPage == i ? 18 : 8,
                      decoration: BoxDecoration(
                        color: _currentPage == i
                            ? Colors.orangeAccent
                            : Colors.white24,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
