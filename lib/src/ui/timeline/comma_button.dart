import 'package:flutter/material.dart';

import '../shortcuts/editor_shortcut_scope.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/command_pill.dart';
import '../widgets/keyboard_press.dart';

/// One of the frame pill's comma buttons — 1 · 2 · 3 · 4 · N: a word on the
/// light face ([IconButtonPressFace]), where it was a Material [TextButton].
///
/// 🪶WHY (card frame-panels-build-in-one-frame, 2026-10-25): a TextButton
/// is ~40 elements — a semantics node, an input padding, a box, a Material
/// with its physical shape, its ink features and a theme, an `InkWell` with
/// its focus, actions, mouse region and gesture detector — and the pill
/// wears five, built again whenever a tab is shown. The face is one render
/// object: the box, the state layer, the cursor, the tooltip, the node and
/// the claim; [KeyboardPress] is the focus and the Enter/Space.
///
/// ⛔AT REST NOTHING ON THE SCREEN CHANGES. Each part is read where the
/// TextButton read it: the ink and the corner from the app's
/// `TextButtonTheme` before M3's defaults ([IconButtonInk.textButton]), the
/// box from the button's own sizes under its density ([boxIn]), the word in
/// the theme's text style in the foreground colour —
/// `a_comma_button_is_one_face_test` holds it against the TextButton it
/// replaced, in every state a hand can put it in.
///
/// 🔧THE BAR'S BUTTONS POINT AND PRESS ALIKE. As TextButtons the comma set
/// was the bar's odd one out twice: it showed the arrow — M3's
/// `adaptiveClickable`, which is the arrow on a desktop — where every icon
/// button and name cell beside it shows the hand (the icon button's since
/// 2026-09-10, `a57e2566f`); and held down, its `InkWell` laid the press's
/// layer over the hover's, where an icon button shows the press's alone.
/// The face does what its neighbours do. The rim of a state layer is
/// anti-aliased a hair differently too (the shape filled as itself, not
/// traced as a path) — at most 5 of 255, measured.
///
/// ⛔The word's colour is read for the states a build knows — disabled, and
/// the keyboard's focus. The hover and the press live in the face and are
/// not asked: no step of the foreground answers them (`styleFrom` builds it
/// from `ButtonStyleButton.defaultColor`, enabled or disabled) — pinned by
/// the same test.
class CommaButton extends StatefulWidget {
  const CommaButton({
    super.key,
    required this.label,
    required this.tooltip,
    required this.shortcuts,
    required this.onPressed,
  });

  /// What the button says — the comma it sets, or `N`.
  final String label;

  /// What its tooltip says, before the live keys of [shortcuts] (I-19).
  final String tooltip;
  final List<String> shortcuts;

  /// The ONE callback for every way it is pressed — the pointer's (the
  /// face's claim), a key's and a screen reader's. Null is a dead button.
  final VoidCallback? onPressed;

  /// The box a comma button hugs its word in where it is shown: sized to
  /// sit INSIDE a pill (its outer height, 2px of breath each side) rather
  /// than to stand on its own in the bar — 21 to 24 wide at that height,
  /// under the compact density, which lets it shrink 8 each way to its
  /// word, as `ButtonStyleButton` lets it. The padding is none, and stays
  /// none: the density only ever takes padding away.
  static BoxConstraints boxIn(BuildContext context) {
    final height = CommandPill.heightIn(context) - 4;
    return VisualDensity.compact.effectiveConstraints(
      BoxConstraints(
        minWidth: 21,
        minHeight: height,
        maxWidth: 24,
        maxHeight: height,
      ),
    );
  }

  @override
  State<CommaButton> createState() => _CommaButtonState();
}

class _CommaButtonState extends State<CommaButton> with KeyboardPress {
  @override
  VoidCallback? get keyboardPress => widget.onPressed;

  @override
  Widget build(BuildContext context) {
    final focus = keyboardFocus;
    final states = <WidgetState>{
      if (widget.onPressed == null) WidgetState.disabled,
      if (focus == IconButtonFocus.shown) WidgetState.focused,
    };
    final ink = IconButtonInk.textButton(context);
    final theme = TextButtonTheme.of(context).style;
    final box = CommaButton.boxIn(context);
    return keyboardReaches(
      IconButtonPressFace(
        // Read in THIS build: the toolbars cache their groups, and a string
        // composed in a cached builder would keep the key it was built with
        // ([ShortcutTooltip]).
        tooltip: shortcutTooltip(context, widget.tooltip, widget.shortcuts),
        onPressed: widget.onPressed,
        isSelected: false,
        focus: focus,
        ink: ink,
        shape: theme?.shape?.resolve(states) ?? const StadiumBorder(),
        minWidth: box.minWidth,
        maxWidth: box.maxWidth,
        minHeight: box.minHeight,
        maxHeight: box.maxHeight,
        // The button's Material SETS the text style rather than merging
        // it — the theme's, or M3's `labelLarge` — in the foreground.
        child: DefaultTextStyle(
          style: (theme?.textStyle?.resolve(states) ??
                  Theme.of(context).textTheme.labelLarge!)
              .copyWith(color: ink.foreground(states)),
          child: Text(
            widget.label,
            style: const TextStyle(fontSize: CommandPill.verbFontSize),
          ),
        ),
      ),
    );
  }
}
