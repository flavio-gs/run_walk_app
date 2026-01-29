import 'package:flutter/material.dart';

class ScaffoldVisibilityController {
  static final ValueNotifier<bool> isVisible = ValueNotifier(true);

  static void hide() => isVisible.value = false;
  static void show() => isVisible.value = true;
}
