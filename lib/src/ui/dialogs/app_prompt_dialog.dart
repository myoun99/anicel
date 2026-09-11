import 'package:flutter/material.dart';
import '../text/full_width_numerals.dart';

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
    this.extra,
    this.fieldTrailing,
  });

  /// The same window with its four keys derived from ONE name:
  /// `<keyPrefix>-dialog`, `-text-field`, `-cancel-button`, `-ok-button`.
  ///
  /// 🚨THE FOUR KEYS ARE ONE NAME — the prompt family's half of the rule
  /// `confirmDialogKeys` owns for confirms (round 8's clone scan). Four
  /// windows spelled the four out by hand, or wrapped this one in a
  /// data-only widget whose whole job was the derivation, and a window
  /// renamed without its buttons leaves a test that finds the window and
  /// not its confirm — which reads as "the button is missing" rather than
  /// "the key drifted".
  ///
  /// ⚠️The prompt family accepts through `-ok-button`, where a confirm
  /// accepts through `-confirm-button`. A window off EITHER convention
  /// (the cut rename accepts through `-confirm-button`; the cut note names
  /// its buttons after the verb) passes its keys to the default
  /// constructor instead — which is what keeps a test key from moving
  /// because a window joined a family.
  AppPromptDialog.keyed({
    super.key,
    required String keyPrefix,
    required this.title,
    required this.fieldLabel,
    required this.initialValue,
    required this.confirmLabel,
    this.titleIcon,
    this.emptyError,
    this.multiline = false,
    this.numeric = false,
    this.extra,
    this.fieldTrailing,
  }) : windowKey = ValueKey<String>('$keyPrefix-dialog'),
       fieldKey = ValueKey<String>('$keyPrefix-text-field'),
       cancelKey = ValueKey<String>('$keyPrefix-cancel-button'),
       confirmKey = ValueKey<String>('$keyPrefix-ok-button');

  /// Optional content below the field — a picker that belongs to the same
  /// edit as the name, so the two are confirmed together rather than
  /// through two dialogs in a row.
  final Widget? extra;

  /// Optional content BESIDE the field, on its right — the key window's
  /// TYPE (F-17: 「이름변경이랑 오른쪽에 유니언 타입 변경」). Confirmed with
  /// the name like [extra]; it takes its own width and the field the rest.
  final Widget? fieldTrailing;

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

  /// [field] with [AppPromptDialog.fieldTrailing] on its right, when there
  /// is one.
  Widget _besideTrailing(Widget field) {
    final trailing = widget.fieldTrailing;
    if (trailing == null) {
      return field;
    }
    return Row(
      children: [
        Expanded(child: field),
        const SizedBox(width: 8),
        IntrinsicWidth(child: trailing),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppWindow(
      windowKey: widget.windowKey,
      title: widget.title,
      titleIcon: widget.titleIcon,
      onClose: () => Navigator.of(context).pop(),
      width: widget.multiline
          ? 420
          : widget.fieldTrailing == null
          ? 300
          : 400,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppWindowField(
            label: widget.fieldLabel,
            emphasized: true,
            child: _besideTrailing(
              TextField(
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
          inputFormatters: widget.numeric ? halfWidthDigitsOnly : null,
          decoration: InputDecoration(errorText: _errorText),
          onChanged: (_) {
            if (_errorText != null) {
              setState(() => _errorText = null);
            }
          },
              onSubmitted: widget.multiline ? null : (_) => _submit(),
            ),
            ),
          ),
          if (widget.extra != null) ...[
            const SizedBox(height: 10),
            widget.extra!,
          ],
        ],
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
