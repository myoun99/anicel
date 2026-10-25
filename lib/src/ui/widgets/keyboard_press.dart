import 'package:flutter/widgets.dart';

import 'icon_button_box.dart' show IconButtonFocus;

/// The part of a light button the keyboard reaches: its FOCUS — the Tab
/// key's stop and the focus layer its face shows ([keyboardFocus]) — and
/// the Enter/Space it answers, which press it as the pointer does.
///
/// The face under it is everything a pointer and a screen reader meet
/// ([PressFace]); this is the two widgets a focus cannot do without, and
/// nothing else. A button's [State] wears it and wraps its face in
/// [keyboardReaches].
///
/// 🗣️유저 2026-10-23 (board `F-450-Q1`): 「통일 — 아이콘 버튼도 Enter ·
/// Space 로 눌린다」 — one callback for every way a button is pressed.
///
/// ↩️It was the icon button's own until 2026-10-25 (card frame-panels-
/// build-in-one-frame): the toolbar's word buttons and name cells were
/// Material buttons with an `InkWell` each, whose focus came with ~25
/// elements more, and they wear a face now as the icon button does.
mixin KeyboardPress<T extends StatefulWidget> on State<T> {
  /// What Enter or Space does — the button's one press. Null is a button
  /// the keyboard passes over.
  VoidCallback? get keyboardPress;

  bool _hasFocus = false;

  /// Where the focus is, as the face shows it — M3's focus layer is for
  /// KEYBOARD focus only, the same gate `InkResponse.updateFocusHighlights`
  /// applies.
  IconButtonFocus get keyboardFocus => !_hasFocus
      ? IconButtonFocus.away
      : keyboardPress != null &&
            FocusManager.instance.highlightMode ==
                FocusHighlightMode.traditional
      ? IconButtonFocus.shown
      : IconButtonFocus.held;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_highlightModeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_highlightModeChanged);
    super.dispose();
  }

  void _highlightModeChanged(FocusHighlightMode mode) {
    if (_hasFocus) {
      setState(() {});
    }
  }

  void _setHasFocus(bool value) {
    if (_hasFocus != value) {
      setState(() => _hasFocus = value);
    }
  }

  /// [face] where the keyboard can reach it.
  Widget keyboardReaches(Widget face) => Actions(
    actions: <Type, Action<Intent>>{
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          keyboardPress?.call();
          return null;
        },
      ),
    },
    child: Focus(
      canRequestFocus: keyboardPress != null,
      // The face's ONE node says the focus ([PressFace]).
      includeSemantics: false,
      onFocusChange: _setHasFocus,
      child: face,
    ),
  );
}
