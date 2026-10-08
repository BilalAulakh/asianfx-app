import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Root screens (no route underneath) close the app on the system back button.
/// This asks for a second press within 2 seconds first, and lets [onBack]
/// handle the press when it returns true (e.g. switch back to the previous tab).
class DoubleBackToExit extends StatefulWidget {
  final Widget child;

  /// Handles a back press in-app; returns true when it did something.
  final bool Function()? onBack;

  const DoubleBackToExit({super.key, required this.child, this.onBack});

  @override
  State<DoubleBackToExit> createState() => _DoubleBackToExitState();
}

class _DoubleBackToExitState extends State<DoubleBackToExit> {
  DateTime? _lastPress;

  void _handleBack() {
    if (widget.onBack?.call() ?? false) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    final now = DateTime.now();
    if (_lastPress != null && now.difference(_lastPress!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastPress = now;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: widget.child,
    );
  }
}
