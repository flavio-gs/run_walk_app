import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../enums/territory_mode.dart';



class TerritoryModeToggle extends StatelessWidget {
  final MapTerritoryMode mode;
  final ValueChanged<MapTerritoryMode> onChange;

  const TerritoryModeToggle({
    super.key,
    required this.mode,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _chip("TERRITORIOS", MapTerritoryMode.global),
          const SizedBox(width: 6),
          _chip("LIVRE", MapTerritoryMode.livre),
        ],
      ),
    );
  }

  Widget _chip(String label, MapTerritoryMode value) {
    final selected = mode == value;

    return GestureDetector(
      onTap: () => onChange(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black12),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            color: selected ? const Color(0xFFFF6D00) : Colors.black87,
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}
