import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../text/app_strings.dart';
import '../widgets/app_window.dart';

/// The one "type a short string" window: rename a layer, a cut, a frame, a
/// brush, a media asset; name a new folder or a preset.
///
/// Before this existed each of those spelled its own [AlertDialog] out, and
/// they had drifted apart in BEHAVIOUR, not just looks — some trimmed the
/// result and some did not, some rejected an empty name and some accepted
/// it, and Enter submitted in two of them. Deciding all three here is the
/// point of the widget; the shared chrome is a bonus.
///
/// Pops the entered text (trimmed), or nothing on cancel.
class AppPromptDialog extends StatefulWidget {
  const AppPromptDialog({
    super.key,
    required this.title,
    required this.fieldLabel,
    required this.initialValue,
    required this.confirmLabel,
    this.titleIcon,
    this.emptyError,
    this.multiline = false,
    this.numeric = false,
    this.windowKey,
    this.fieldKey,
    this.cancelKey,
    this.confirmKey,
  });

  final String title;
  final IconData? titleIcon;
  final String fieldLabel;
  final String initialValue;

  /// Verb, not 'OK' — 'Rename', 'Save', 'Create'.
  final String confirmLabel;

  /// The message shown when the field is empty, or null to allow empty
  /// (a cut note may legitimately be cleared).
  final String? emptyError;

  /// Multi-line entry (notes, dialogue). Enter then inserts a newline
  /// instead of submitting.
  final bool multiline;

  /// Digits only, with the numeric keyboard. The caller still parses the
  /// popped string — the window's job is to stop non-digits arriving.
  final bool numeric;

  final Key? windowKey;
  final Key? fieldKey;
  final Key? cancelKey;
  final Key? confirmKey;

  @override
  State<AppPromptDialog> createState() => _AppPromptDialogState();
}

class _AppPromptDialogState extends State<AppPromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  )..selection = TextSelection(
    // Preselected, so typing REPLACES the old name — renaming is nearly
    // always a replacement, and reaching for ctrl+A first was friction.
    baseOffset: 0,
    extentOffset: widget.initialValue.length,
  );
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    final emptyError = widget.emptyError;
    if (value.isEmpty && emptyError != null) {
      setState(() => _errorText = emptyError);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AppWindow(
      windowKey: widget.windowKey,
      title: widget.title,
      titleIcon: widget.titleIcon,
      onClose: () => Navigator.of(context).pop(),
      width: widget.multiline ? 420 : 300,
      body: AppWindowField(
        label: widget.fieldLabel,
        emphasized: true,
        child: TextField(
          key: widget.fieldKey,
          controller: _controller,
          autofocus: true,
          minLines: widget.multiline ? 8 : 1,
          maxLines: widget.multiline ? 12 : 1,
          keyboardType: widget.multiline
              ? TextInputType.multiline
              : widget.numeric
              ? TextInputType.number
              : null,
          inputFormatters: widget.numeric
              ? [FilteringTextInputFormatter.digitsOnly]
              : null,
          decoration: InputDecoration(errorText: _errorText),
          onChanged: (_) {
            if (_errorText != null) {
              setState(() => _errorText = null);
            }
          },
          onSubmitted: widget.multiline ? null : (_) => _submit(),
        ),
      ),
      actions: [
        AppWindowAction(
          label: AppText.strings.commonCancel,
          actionKey: widget.cancelKey,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppWindowAction(
          label: widget.confirmLabel,
          actionKey: widget.confirmKey,
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: _submit,
        ),
      ],
    );
  }
}
