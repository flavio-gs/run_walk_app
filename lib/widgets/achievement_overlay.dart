import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'dart:math';

class AchievementOverlay extends StatefulWidget {
  final String title;
  final String icon; // emoji mesmo, ex: "🌙"
  const AchievementOverlay({super.key, required this.title, required this.icon});

  @override
  State<AchievementOverlay> createState() => _AchievementOverlayState();
}

class _AchievementOverlayState extends State<AchievementOverlay> {
  late ConfettiController _confetti;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 2));
    WidgetsBinding.instance.addPostFrameCallback((_) => _confetti.play());
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // fundo escurecido
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(color: Colors.black54),
        ),
        // card
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.8, end: 1.0),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutBack,
          builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.8,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(blurRadius: 16, color: Colors.black26)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.icon, style: const TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                const Text("Conquista desbloqueada!",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 6),
                Text(widget.title, textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Fechar"),
                )
              ],
            ),
          ),
        ),
        // confete
        Positioned(
          top: MediaQuery.of(context).size.height * 0.3,
          child: ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            emissionFrequency: 0.08,
            numberOfParticles: 30,
            minBlastForce: 5,
            maxBlastForce: 20,
            gravity: 0.4,
            colors: const [Colors.amber, Colors.orange, Colors.pink, Colors.blue],
            shouldLoop: false,
            createParticlePath: (size) {
              final path = Path();
              path.addPolygon([
                Offset(size.width * 0.5, 0),
                Offset(size.width, size.height),
                Offset(0, size.height),
              ], true);
              return path;
            },
          ),
        ),
      ],
    );
  }
}

Future<void> showAchievementPopup(BuildContext context, {required String title, required String icon}) async {
  await showDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black54,
    builder: (_) => AchievementOverlay(title: title, icon: icon),
  );
}
