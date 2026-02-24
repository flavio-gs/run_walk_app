import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../enums/territory_mode.dart';
import '../theme/season_theme_scope.dart';



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
    final theme = SeasonThemeScope.of(context);

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: theme.border,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.primary.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _chip(context, "TERRITÓRIOS", MapTerritoryMode.global),
          const SizedBox(width: 6),
          _chip(context, "LIVRE", MapTerritoryMode.livre),
        ],
      ),
    );
  }

  Widget _chip(
      BuildContext context, String label, MapTerritoryMode value) {
    final theme = SeasonThemeScope.of(context);
    final selected = mode == value;

    return GestureDetector(
      onTap: () => onChange(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
            colors: [
              theme.primary,
              theme.secondary,
            ],
          )
              : null,
          color: selected ? null : theme.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? theme.ring
                : theme.border,
          ),
          boxShadow: selected
              ? [
            BoxShadow(
              color: theme.primary.withOpacity(0.35),
              blurRadius: 8,
            )
          ]
              : [],
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            color: selected
                ? theme.primaryForeground
                : theme.foreground,
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}
