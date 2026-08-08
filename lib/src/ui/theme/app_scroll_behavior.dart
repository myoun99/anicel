import 'package:flutter/material.dart';

import '../panels/panel_scrollbar.dart';

/// The app's scroll behaviour: ONE scrollbar vocabulary, everywhere.
///
/// The app had two species living side by side and nobody had counted
/// them. `MaterialScrollBehavior.buildScrollbar` puts a framework
/// `Scrollbar` on every vertical scrollable on a desktop platform, so some
/// thirty surfaces — panel bodies, dialog bodies, the media list, the
/// preset grid, popup menus — wore Flutter's bar while the timeline rails,
/// the canvas panbars and the three [PanelScrollbar] callers wore ours.
/// They diverged in the one way a hand notices: our thumb is 4px in every
/// state and the framework's grew to 6 under the pointer (유저, R4:
/// 호버중에 크기가 커지는데? 안커지도록 — and that came from our own
/// `ScrollbarThemeData`, not from Flutter's defaults).
///
/// What every scrollable gets here is [PanelScrollbar], which is the shape
/// the user asked for by name (「띠 패널 스크롤바처럼」):
///
///  * **It exists only while it can scroll.** Presence is the signal.
///    ⛔This is not the framework's fade — the bar follows the CONTENT and
///    never the clock, so an overflowing surface shows its bar for as long
///    as it overflows.
///  * **Constant thickness.** Nothing about it moves when you touch it.
///  * **Colour is the whole state machine**, and it lights accent on
///    pointer-DOWN rather than waiting for a drag to start.
///  * **It costs no layout.** The lane lies over the content's end edge, so
///    a surface that fits pays nothing for a bar it does not have.
///
/// ★It bars BOTH axes, which Flutter never has
/// (`MaterialScrollBehavior.buildScrollbar` returns the child unchanged for
/// `Axis.horizontal`), so the sideways scroll a narrow rail puts the conte
/// and the timesheet into finally says so. 유저 확정: 내용에만 — the four
/// places where a horizontal scroller is a COMPRESSED TOOL STRIP rather
/// than content opt out by hand, because a 12px lane laid across a 30px
/// toolbar takes the bottom third of every button in it.
///
/// ⚠️Two surfaces it provably cannot reach: `DropdownButton`'s menu and
/// `MenuAnchor`'s panel both wrap themselves in `copyWith(scrollbars:
/// false)` and build their own `Scrollbar`. `ScrollbarThemeData` in
/// [buildAppTheme] is their only styling, and it is kept in step with this
/// on purpose rather than left as dead prose.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final controller = details.controller;
    if (controller == null) {
      // Not reachable from a real `Scrollable` — it always passes its
      // effective controller, falling back to one it owns — but a hand-made
      // `ScrollableDetails` may not, and a bar with nothing to read is
      // worse than no bar.
      return child;
    }
    // ⛔NEVER inside a text field. `EditableText` scrolls itself when it is
    // multiline and DELEGATES the scrollbar decision to us
    // (`copyWith(scrollbars: _isMultiline)`), so without this the conte's
    // action field, the timesheet memo and every multiline prompt would
    // grow a lane down their right edge — and the lane hit-tests opaque, so
    // it would swallow the taps that put the caret at the end of a line.
    // A text field says "there is more" with its own caret and text; it
    // does not need a bar to.
    if (context.findAncestorWidgetOfExactType<EditableText>() != null) {
      return child;
    }
    return PanelScrollbar(
      controller: controller,
      axis: axisDirectionToAxis(details.direction),
      child: child,
    );
  }
}

/// Declares a scrollable to be CHROME rather than content, so the app's
/// scrollbar stays off it.
///
/// The four users are compressed tool strips — a panel header's trailing
/// controls, a dialog's tab row, the timeline toolbar, the storyboard
/// toolbar. They scroll as an escape valve when the window squeezes them,
/// and a bar there is not information: it is a 12px lane lying across a
/// 30px row of buttons, eating the bottom third of each one's target.
///
/// 유저 확정 (R4): 가로 스크롤은 내용에만. Content that overflows sideways —
/// a sheet laid out at its own minimum width inside a narrow rail — keeps
/// its bar, because there the bar is the only thing that says the rest of
/// the page is out there.
class UnbarredScrollable extends StatelessWidget {
  const UnbarredScrollable({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
    child: child,
  );
}
