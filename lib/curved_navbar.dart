import 'dart:ui';
import 'package:flutter/material.dart';

class CurvedNavBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemTapped;

  const CurvedNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemTapped,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return SafeArea(
      top: false,
      child: SizedBox(
        height: 80 + bottomPadding,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 🎨 Fundo curvado
            Positioned(
              bottom: 0,
              child: CustomPaint(
                size: Size(MediaQuery.of(context).size.width, 80 + bottomPadding),
                painter: _NavBarPainter(),
              ),
            ),

            // 🔘 Botão central elevado
            Positioned(
              bottom: 30 + bottomPadding,
              left: MediaQuery.of(context).size.width / 2 - 30,
              child: GestureDetector(
                onTap: () => onItemTapped(3),
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4A90E2), Color(0xFF007AFF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.directions_run, color: Colors.white, size: 30),
                ),
              ),
            ),

            // 🧭 Ícones laterais
            Positioned.fill(
              bottom: bottomPadding,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildIcon(Icons.dashboard, 0),
                  _buildIcon(Icons.people, 1),
                  const SizedBox(width: 60), // espaço pro botão central
                  _buildIcon(Icons.bar_chart, 4),
                  _buildIcon(Icons.person, 5),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(IconData icon, int index) {
    final isSelected = selectedIndex == index;
    return GestureDetector(
      onTap: () => onItemTapped(index),
      child: Icon(
        icon,
        size: 28,
        color: isSelected ? const Color(0xFF007AFF) : Colors.grey[400],
      ),
    );
  }
}

class _NavBarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);

    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(size.width * 0.20, 0, size.width * 0.35, 0)
      ..quadraticBezierTo(size.width * 0.40, 0, size.width * 0.42, 20)
      ..arcToPoint(
        Offset(size.width * 0.58, 20),
        radius: const Radius.circular(28),
        clockwise: false,
      )
      ..quadraticBezierTo(size.width * 0.60, 0, size.width * 0.65, 0)
      ..quadraticBezierTo(size.width * 0.80, 0, size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawShadow(path, Colors.black.withOpacity(0.2), 5, true);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
