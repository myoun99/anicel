import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A window that FLOATS over the workspace: the canvas under it keeps taking
/// strokes while it is open, its title bar moves it, and it opens where it
/// was left (I-141-Q3, 유저 2026-10-29: 「떠 있는 창(클튜처럼)」 — the brush
/// detail window, tried against the canvas while it stays open).
///
/// 🚨IT IS NOT A ROUTE: a route's barrier eats input aimed at everything
/// under it even when it is transparent, so a window that has to survive a
/// canvas stroke cannot be one. It rides an [OverlayPortal], as the colour
/// window's pinned popup did (gone with I-131; its reason is kept in
/// `anchored_popup.dart`), which buys three things a raw overlay entry
/// would each need code for:
///
///  * the window rebuilds when its anchor ([child]) rebuilds, so what it
///    shows is the anchor's values as they stand;
///  * `Theme`, `MediaQuery` and the rest flow in from the anchor's place in
///    the tree;
///  * the anchor going away takes the window with it, so nothing is left
///    floating with no one to close it.
///
/// Only the window's own box takes hits: there is no fill and no barrier
/// between it and the canvas. What opens and closes it is its host's —
/// [controller] — and the window's own close button.
class FloatingAppWindow extends StatelessWidget {
  const FloatingAppWindow({
    super.key,
    required this.controller,
    required this.at,
    required this.size,
    required this.window,
    required this.child,
  });

  final OverlayPortalController controller;

  /// Where the window's top-left stands in the overlay — null until it has
  /// been moved, which centres it. Held by the host, so it can outlive the
  /// window.
  final ValueNotifier<Offset?> at;

  /// The window's size, kept inside the screen.
  final Size size;

  /// The window at [Size], handed what its title bar moves it by
  /// (`AppWindow.onTitleDrag`).
  final Widget Function(
    BuildContext context,
    Size size,
    GestureDragUpdateCallback onTitleDrag,
  )
  window;

  /// The anchor: what the window lives and dies with.
  final Widget child;

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: controller,
    // The overlay's own size, not the media's: it is what the window stands
    // in. Measured as it is laid out, so the window follows a screen that
    // changes shape — kept inside it as a layout clamp, not a stored one:
    // the screen growing back puts the window back where it was left.
    // ⚠️The Stack takes no press of its own: only the window's box does.
    overlayChildBuilder: (overlayContext) => LayoutBuilder(
      builder: (context, room) {
        final screen = room.biggest;
        final box = Size(
          math.min(size.width, screen.width),
          math.min(size.height, screen.height),
        );
        return ValueListenableBuilder<Offset?>(
          valueListenable: at,
          builder: (context, stood, _) {
            final place = _inside(
              stood ?? screen.center(Offset.zero) - box.center(Offset.zero),
              screen,
              box,
            );
            return Stack(
              children: [
                Positioned(
                  left: place.dx,
                  top: place.dy,
                  width: box.width,
                  height: box.height,
                  child: window(
                    context,
                    box,
                    (drag) =>
                        at.value = _inside(place + drag.delta, screen, box),
                  ),
                ),
              ],
            );
          },
        );
      },
    ),
    child: child,
  );

  /// [place] moved as little as it takes for a [box] there to stand inside
  /// [screen].
  static Offset _inside(Offset place, Size screen, Size box) => Offset(
    place.dx.clamp(0, screen.width - box.width).toDouble(),
    place.dy.clamp(0, screen.height - box.height).toDouble(),
  );
}
