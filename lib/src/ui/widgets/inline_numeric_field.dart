import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../text/full_width_numerals.dart';

/// The ONE inline numeric field (R10 R5).
///
/// Every place in this app where a readout turns into something you type
/// into wants the identical field: it takes focus the moment it appears
/// with its text selected, Escape abandons the edit, Enter or a tap
/// anywhere else commits it, and a Japanese IME sitting in 全角 has its
/// numerals converted as they arrive so no downstream parser ever sees
/// them (R9 #15). Three copies of that had drifted apart — the canvas
/// readouts', the slider's, and the colour window's about to be a fourth.
///
/// What is deliberately NOT here is the ENTRY GESTURE. The host decides
/// what turns into this field and when, because that is the only part
/// that legitimately differs: a value label swaps itself out in place, a
/// colour field sits in a status bar. The app's rule about which gesture
/// that may be — a single tap, never a double — is a rule about hosts.
class InlineNumericField extends StatefulWidget {
  const InlineNumericField({
    super.key,
    required this.initialText,
    required this.onSubmit,
    required this.onCancel,
    this.fieldKey,
    this.textStyle,
    this.textAlign = TextAlign.center,
    this.signed = true,
    this.keyboardType,
  });

  /// Seeds the field, and is selected whole so the first keystroke
  /// replaces it — the readout you tapped IS the thing you are replacing.
  final String initialText;

  /// The raw text on commit; the host parses and clamps, because only the
  /// host knows the units.
  final ValueChanged<String> onSubmit;

  /// Escape, and any other abandonment. The host restores its readout.
  final VoidCallback onCancel;

  final Key? fieldKey;
  final TextStyle? textStyle;
  final TextAlign textAlign;

  /// A signed offset takes a minus; a channel value does not.
  final bool signed;

  /// Overrides the soft keyboard. HEX is the reason this exists: it wants
  /// the field's focus/escape/commit behaviour but its digits run A–F, so
  /// a numeric pad would leave a phone unable to type half of them.
  final TextInputType? keyboardType;

  @override
  State<InlineNumericField> createState() => _InlineNumericFieldState();
}

class _InlineNumericFieldState extends State<InlineNumericField> {
  late final TextEditingController _controller =
      TextEditingController.fromValue(
        TextEditingValue(
          text: widget.initialText,
          selection: TextSelection(
            baseOffset: 0,
            extentOffset: widget.initialText.length,
          ),
        ),
      );

  /// Commit exactly once. `onSubmitted` and `onTapOutside` can both land
  /// for one edit (Enter, then the focus loss it causes), and a host that
  /// treats a commit as an undo step must not get two.
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_done) {
      return;
    }
    _done = true;
    widget.onSubmit(_controller.text.trim());
  }

  /// Tapping AWAY commits what you typed — but if you typed nothing, it
  /// must not commit anything at all.
  ///
  /// The seed goes stale the instant the host's value moves under an open
  /// field, and the pointer-down that closes the field is usually the one
  /// that moved it: open the hex field, then pick on the wheel, and a
  /// commit would write the OLD hex back over the colour you just chose.
  /// An untouched field abandons instead.
  void _submitFromOutside() {
    if (_controller.text == widget.initialText) {
      _cancel();
      return;
    }
    _submit();
  }

  void _cancel() {
    if (_done) {
      return;
    }
    _done = true;
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        key: widget.fieldKey,
        controller: _controller,
        autofocus: true,
        textAlign: widget.textAlign,
        keyboardType:
            widget.keyboardType ??
            TextInputType.numberWithOptions(
              decimal: true,
              signed: widget.signed,
            ),
        inputFormatters: halfWidthNumerals,
        style: widget.textStyle ?? const TextStyle(fontSize: 12),
        decoration: const InputDecoration(
          // Bare: the field replaces a readout in place, so it opts out of
          // the app-wide filled box.
          filled: false,
          isDense: true,
          isCollapsed: true,
          border: InputBorder.none,
        ),
        onSubmitted: (_) => _submit(),
        onTapOutside: (_) => _submitFromOutside(),
      ),
    );
  }
}
