import 'package:flutter/widgets.dart';

import '../brush/brush_tool_state.dart' show CanvasTool;
import '../widgets/panel_flyout.dart';

/// What one panel binds for keys to press (I-40): its buttons, each under
/// the action it names — the very callback the button holds, null while the
/// button is dead — and the rows its menu would open now.
typedef PanelPresses = ({
  Map<String, VoidCallback?> buttons,
  List<PanelFlyoutEntry> Function()? menu,
});

/// The panels' own buttons and menus as a KEY presses them (I-40) — each
/// panel binds what it shows while it is mounted ([PanelKeysBinding]), and
/// the shell presses the one an action names.
///
/// 🗣️I-40 (유저 2026-09-18): 「버튼 전수감사해서 숏컷리스트에 등록 … 뭐든
/// 모든 버튼」. ★A KEY AND ITS BUTTON ARE ONE PRESS: what is bound is the
/// button's own callback, so a dead button is dead by key too, and a panel
/// that is not mounted has nothing here to press.
///
/// WHICH PANEL: a panel of a TOOL — its library, its settings — binds as
/// that tool's, and a key presses the panels of the tool in hand: two paint
/// tools keep their libraries mounted side by side, and the eraser's is not
/// the one on screen while the brush is in hand. A panel of no tool is the
/// only one of its kind, and a key presses it whatever is in hand.
///
/// ↩️The brush library had a binding of its own (`BrushLibraryKeys`, the
/// eighth round of I-40); the guide list, the text tool's settings, the
/// media pool and the timesheet were the next four, so the binding is one
/// for every panel now.
class PanelKeys {
  final Map<Object, ({CanvasTool? tool, PanelPresses presses})> _bound = {};

  /// [owner]'s presses from now on, as [tool]'s panel or as no tool's —
  /// whatever it bound before, replaced.
  void bind(Object owner, PanelPresses presses, {CanvasTool? tool}) {
    _bound[owner] = (tool: tool, presses: presses);
  }

  /// [owner]'s presses are gone — and no one else's: a panel mounted in its
  /// place has bound under its own name.
  void unbind(Object owner) => _bound.remove(owner);

  Iterable<PanelPresses> _reaching(CanvasTool inHand) => [
    for (final bound in _bound.values)
      if (bound.tool == null || bound.tool == inHand) bound.presses,
  ];

  /// Every row the menus a key reaches would open right now, with [inHand]
  /// in hand.
  Iterable<PanelFlyoutItem> menuRows(CanvasTool inHand) => [
    for (final presses in _reaching(inHand))
      if (presses.menu case final menu?) ...flyoutRowsOf(menu()),
  ];

  /// One press of the button that names [actionId] on a panel a key
  /// reaches with [inHand] in hand — nothing where none shows one, or where
  /// it is dead.
  void press(String actionId, CanvasTool inHand) {
    for (final presses in _reaching(inHand)) {
      if (presses.buttons.containsKey(actionId)) {
        presses.buttons[actionId]?.call();
        return;
      }
    }
  }
}

/// Where every panel below finds the [PanelKeys] to bind to — none where a
/// panel is pumped on its own, and then it binds nothing.
class PanelKeysScope extends InheritedWidget {
  const PanelKeysScope({super.key, required this.keys, required super.child});

  final PanelKeys keys;

  static PanelKeys? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PanelKeysScope>()?.keys;

  @override
  bool updateShouldNotify(PanelKeysScope oldWidget) =>
      !identical(keys, oldWidget.keys);
}

/// Binds the buttons and the menu of the panel around [child] for keys while
/// it is mounted — as [tool]'s panel, or as no tool's ([PanelKeys]).
///
/// [buttons] are handed again on every build, so a key presses what the
/// buttons hold NOW.
///
/// ⚠️It wraps the PANEL — a tool's settings section, a library, a pool —
/// never the row a button stands on: a settings list builds its rows only
/// near the screen, and a binding on a row far down would not be there to
/// press until the list was scrolled to it (the tool settings' round of
/// I-40, 2026-10-11).
class PanelKeysBinding extends StatefulWidget {
  const PanelKeysBinding({
    super.key,
    this.tool,
    this.buttons = const {},
    this.menu,
    required this.child,
  });

  final CanvasTool? tool;
  final Map<String, VoidCallback?> buttons;
  final List<PanelFlyoutEntry> Function()? menu;
  final Widget child;

  @override
  State<PanelKeysBinding> createState() => _PanelKeysBindingState();
}

class _PanelKeysBindingState extends State<PanelKeysBinding> {
  PanelKeys? _keys;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final keys = PanelKeysScope.maybeOf(context);
    if (!identical(keys, _keys)) {
      _keys?.unbind(this);
      _keys = keys;
    }
    _bind();
  }

  @override
  void didUpdateWidget(PanelKeysBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bind();
  }

  void _bind() => _keys?.bind(this, (
    buttons: widget.buttons,
    menu: widget.menu,
  ), tool: widget.tool);

  @override
  void dispose() {
    _keys?.unbind(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
