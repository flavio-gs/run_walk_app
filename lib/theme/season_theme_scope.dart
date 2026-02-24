import 'package:flutter/material.dart';

class SeasonTheme {
  final Color accent;
  final Color accentForeground;
  final Color background;
  final Color border;
  final Color card;
  final Color cardForeground;
  final Color destructive;
  final Color destructiveForeground;
  final Color foreground;
  final Color input;
  final Color muted;
  final Color mutedForeground;
  final Color popover;
  final Color popoverForeground;
  final Color primary;
  final Color primaryForeground;
  final Color ring;
  final Color secondary;
  final Color secondaryForeground;

  const SeasonTheme({
    required this.accent,
    required this.accentForeground,
    required this.background,
    required this.border,
    required this.card,
    required this.cardForeground,
    required this.destructive,
    required this.destructiveForeground,
    required this.foreground,
    required this.input,
    required this.muted,
    required this.mutedForeground,
    required this.popover,
    required this.popoverForeground,
    required this.primary,
    required this.primaryForeground,
    required this.ring,
    required this.secondary,
    required this.secondaryForeground,
  });
}

class SeasonThemeScope extends InheritedWidget {
  final SeasonTheme theme;

  const SeasonThemeScope({
    super.key,
    required this.theme,
    required super.child,
  });

  static SeasonTheme of(BuildContext context) {
    final scope =
    context.dependOnInheritedWidgetOfExactType<SeasonThemeScope>();

    if (scope == null) {
      throw Exception('SeasonThemeScope não encontrado no widget tree');
    }
    return scope.theme;
  }

  @override
  bool updateShouldNotify(covariant SeasonThemeScope oldWidget) {
    return oldWidget.theme != theme;
  }
}
