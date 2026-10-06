import 'package:flutter/material.dart';

/// Asks the admin for a written reason (reject a deposit / withdrawal).
/// Returns the trimmed text, or null when cancelled.
///
/// The dialog owns its TextEditingController, so it is disposed only after
/// the closing animation (which still renders the field) has finished.
Future<String?> showReasonDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String hint,
  required String confirmLabel,
  Color confirmColor = const Color(0xFFFF4757),
  Color? background,
  Color? textPrimary,
  Color? textSecondary,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ReasonDialog(
      title: title,
      message: message,
      hint: hint,
      confirmLabel: confirmLabel,
      confirmColor: confirmColor,
      background: background,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
    ),
  );
}

class _ReasonDialog extends StatefulWidget {
  final String title;
  final String message;
  final String hint;
  final String confirmLabel;
  final Color confirmColor;
  final Color? background;
  final Color? textPrimary;
  final Color? textSecondary;

  const _ReasonDialog({
    required this.title,
    required this.message,
    required this.hint,
    required this.confirmLabel,
    required this.confirmColor,
    this.background,
    this.textPrimary,
    this.textSecondary,
  });

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: widget.background,
      title: Text(widget.title, style: TextStyle(color: widget.textPrimary, fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message, style: TextStyle(color: widget.textSecondary, fontSize: 12)),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 2,
            style: TextStyle(color: widget.textPrimary),
            decoration: InputDecoration(hintText: widget.hint),
          ),
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: widget.confirmColor,
            foregroundColor: Colors.white,
            minimumSize: const Size(120, 44),
          ),
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
