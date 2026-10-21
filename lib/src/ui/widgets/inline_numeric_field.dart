import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../text/full_width_numerals.dart';
import 'selected_text_controller.dart';

/// The ONE inline numeric field (R10 R5).
///
/// Every place in this app where a readout turns into something you type
/// into wants the identical field: it takes focus the moment it appears
/// with its text selected, Escape abandons the edit, Enter or a tap
/// anywhere else commits it, and a Japanese IME sitting in 全角 has its
/// numerals made half-width — once it commits them, and in what is
/// submitted — so no host's parser ever sees them (R9 #15 · F-355). Three
/// copies of that had drifted apart — the canvas readouts', the slider's,
/// and the colour window's about to be a fourth.
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
    this.inputFormatters,
  });

  /// Seeds the field, and is selected whole so the first keystroke
  /// replaces it — the readout you tapped IS the thing you are replacing.
  final String initialText;

  /// The text on commit, its numerals half-width; the host parses and
  /// clamps, because only the host knows the units.
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

  /// Overrides what a keystroke may put in the field. Null converts the
  /// full-width numerals and leaves the rest to the host's parser; a host
  /// that takes whole numbers alone passes [halfWidthDigitsOnly], so a
  /// letter never lands (I-18's start number: 「숫자만 입력가능」).
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<InlineNumericField> createState() => _InlineNumericFieldState();
}

class _InlineNumericFieldState extends State<InlineNumericField> {
  late final TextEditingController _controller = selectedTextController(
    widget.initialText,
  );

  /// Commit exactly once. `onSubmitted` and `onTapOutside` can both land
  /// for one edit (Enter, then the focus loss it causes), and a host that
  /// treats a commit as an undo step must not get two.
  bool _done = false;

  final FocusNode _focus = FocusNode(debugLabel: 'inline-numeric-field');

  /// 🚨F-353 (유저 2026-10-14: 「텍스트 편집중인 상황에서 크기쪽 연필누르면
  /// 텍스트 선택되지 않은 상태. 추가로 자간같은거 연필누르면 여러 박스가
  /// 강조색 되있는상태」): THE FIELD TAKES THE KEYBOARD FROM WHOEVER HOLDS IT.
  /// ↩️It was `autofocus`, which takes the keyboard from NOBODY only: with
  /// a text being typed on the canvas the field opened without it — its
  /// number shown unselected, and no tap away ever closed it, so a second
  /// bar's opened beside it.
  ///
  /// ⛔Nothing here hands the keyboard BACK when the field closes: Flutter
  /// does, as a focused node leaves the tree — to the node its scope had
  /// focused before it (`FocusAttachment.detach`,
  /// `UnfocusDisposition.previouslyFocusedChild`) — so the field holds it
  /// until it goes, on Enter too ([build]). ↩️A give-back of the field's
  /// own was written first (2026-10-14): a second answer to that question.
  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    if (_done) {
      return;
    }
    _done = true;
    // Read half-width (F-355): a tap away commits a draft the IME still
    // holds as it is, which no formatter has seen.
    widget.onSubmit(toHalfWidthNumerals(_controller.text).trim());
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
        focusNode: _focus,
        textAlign: widget.textAlign,
        keyboardType:
            widget.keyboardType ??
            TextInputType.numberWithOptions(
              decimal: true,
              signed: widget.signed,
            ),
        inputFormatters: widget.inputFormatters ?? halfWidthNumerals,
        style: widget.textStyle ?? const TextStyle(fontSize: 12),
        // BARE: the field replaces a readout in place, so it takes nothing
        // of the app-wide boxed field — no fill, no frame in any state, no
        // padding. 🐛It opted out of the fill and the resting border alone,
        // and the theme's FOCUSED frame and its 9px came in with the focus
        // the field always has: a box typed in drew a second, smaller box
        // inside itself (유저 2026-10-11: 「직접입력눌렀을때 텍스트편집박스가
        // 너무 작아. 오른쪽에도 이상한 패딩있고」).
        decoration: const InputDecoration(
          filled: false,
          isDense: true,
          isCollapsed: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
        ),
        // ⛔Enter does not let go of the keyboard. A stock field lets go of
        // it to its SCOPE, which forgets who held it before — the text on
        // the canvas then had it back only if the number changed something
        // (F-353). Kept, the keyboard leaves with the field ([initState]),
        // as it does on Escape and on a tap away.
        onEditingComplete: () {},
        onSubmitted: (_) => _submit(),
        onTapOutside: (_) => _submitFromOutside(),
      ),
    );
  }
}
