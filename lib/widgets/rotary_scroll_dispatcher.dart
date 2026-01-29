import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum RotaryDirection { clockwise, counterClockwise }

class RotaryEvent {
  final RotaryDirection direction;
  const RotaryEvent(this.direction);
}

class RotaryScrollDispatcher extends StatelessWidget {
  final Widget child;
  final void Function(RotaryEvent) onRotaryEvent;

  const RotaryScrollDispatcher({
    super.key,
    required this.child,
    required this.onRotaryEvent,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
              event.logicalKey == LogicalKeyboardKey.pageDown) {
            onRotaryEvent(const RotaryEvent(RotaryDirection.clockwise));
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
              event.logicalKey == LogicalKeyboardKey.pageUp) {
            onRotaryEvent(const RotaryEvent(RotaryDirection.counterClockwise));
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Listener(
        onPointerSignal: (signal) {
          if (signal is PointerScrollEvent) {
            // dy > 0 → pra baixo (clockwise)
            // dy < 0 → pra cima (counterClockwise)
            if (signal.scrollDelta.dy > 0) {
              onRotaryEvent(const RotaryEvent(RotaryDirection.clockwise));
            } else if (signal.scrollDelta.dy < 0) {
              onRotaryEvent(const RotaryEvent(RotaryDirection.counterClockwise));
            }
          }
        },
        child: child,
      ),
    );
  }
}
