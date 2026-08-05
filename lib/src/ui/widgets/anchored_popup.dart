import 'package:flutter/material.dart';

/// Builds an anchored popup's content. [close] is how the content dismisses
/// itself — a picker that closes on pick, a Done button. Both kinds of
/// popup hand the SAME callback shape, so content does not know (or care)
/// which kind is carrying it: the dismissing kind pops its route, the
/// pinned kind hides its overlay child.
typedef AnchoredPopupBuilder =
    Widget Function(BuildContext context, VoidCallback close);

/// The ONE anchored sub-window (R28 #9), in two kinds.
///
/// The brush panel's pressure-curve editor established this shape and the
/// user asked for it to become the shared one: "창 자체는 브러시의 필압설정
/// 하는 열었을때랑 같은거. 그런식으로 서브 창 여는 로직 통일해서 사용. ui
/// 느낌 바꾸면 다른곳에도 적용되게." Everything about how the window
/// behaves — where it lands, how it dismisses, that it appears in one
/// frame — lives here, so restyling it restyles every caller.
///
/// The two kinds differ ONLY in what makes them go away:
///
///  * [showAnchoredPopup] — the DISMISSING kind. Anything you touch
///    outside it closes it. Right for a pick-one-and-go list.
///  * [PinnedAnchoredPopup] — the PINNED kind. It stays while you work the
///    canvas underneath, and closes when its anchor is tapped again. Right
///    for the colour window, where the whole point is to nudge a colour and
///    test the stroke without the window blinking out (유저 확정: "색만 안
///    사라지게").
///
/// They share [_placeAnchoredPopup] — right-aligned under the anchor,
/// flipped above when there is no room below, clamped into the overlay
/// either way. That shared placement is what keeps them one window with two
/// lifetimes rather than two windows that merely look alike.
Future<T?> showAnchoredPopup<T>(
  BuildContext anchorContext, {
  required String label,
  required double width,
  required double height,
  required AnchoredPopupBuilder builder,
}) {
  final placement = _placeAnchoredPopup(
    anchor: anchorContext.findRenderObject()! as RenderBox,
    overlay:
        Navigator.of(anchorContext).overlay!.context.findRenderObject()!
            as RenderBox,
    width: width,
    height: height,
  )!;
  return showGeneralDialog<T>(
    context: anchorContext,
    barrierLabel: label,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    // Flyout rule (R4 #2): the popup appears in one frame.
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) {
      return Stack(
        children: [
          // Dismissal is on pointer DOWN outside, NOT `barrierDismissible`
          // (R27 #5): Flutter's modal barrier closes on a completed TAP, so
          // a drag started outside — a slider grab, a canvas stroke — left
          // the popup hanging. "드래그든 뭐든 다른곳 조작하면 사라지도록".
          Positioned.fill(
            key: ValueKey<String>('$label-dismiss-field'),
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => Navigator.of(context).maybePop(),
            ),
          ),
          Positioned(
            left: placement.left,
            top: placement.top,
            width: width,
            child: Builder(
              builder: (context) =>
                  builder(context, () => Navigator.of(context).maybePop()),
            ),
          ),
        ],
      );
    },
  );
}

/// The PINNED kind: wrap the anchor in it, drive it with [controller].
///
/// 🚨 It is NOT a route, and that is the whole reason it exists.
/// [showGeneralDialog] installs a [ModalBarrier], and a barrier eats input
/// aimed at everything under it even at `barrierColor: transparent` — so a
/// window that has to survive a canvas stroke cannot be a route at all. No
/// amount of barrier tuning gets there.
///
/// It rides [OverlayPortal] rather than a hand-rolled [OverlayEntry],
/// which buys three things a raw entry would each need code for:
///
///  * the popup rebuilds when the ANCHOR rebuilds, so content built from
///    the host's current values is never stale — an eyedropper landing on
///    the canvas reaches the open colour window, which is only possible
///    now that the window no longer closes when the canvas is touched;
///  * `Theme`, `MediaQuery` and the app's other inherited widgets flow in
///    from the anchor's position in the tree, not the overlay's;
///  * unmounting the anchor takes the popup with it, so a panel torn off or
///    a project switched cannot leave a window floating over the canvas
///    with nothing left to dismiss it.
///
/// Because it is not a route there is no [Navigator.pop] to lean on, so the
/// close triggers are explicit, and there are exactly three: the anchor
/// again (the host toggles [controller]), the content itself (through the
/// `close` callback it is built with), and the anchor going away.
///
/// Only the popup's own box takes hits: there is no fill and no barrier
/// between it and the canvas.
class PinnedAnchoredPopup extends StatefulWidget {
  const PinnedAnchoredPopup({
    super.key,
    required this.controller,
    required this.label,
    required this.width,
    required this.height,
    required this.builder,
    required this.child,
  });

  final OverlayPortalController controller;

  /// Names the popup's box for tests, the way the dismissing kind's
  /// barrier label does.
  final String label;

  final double width;

  /// Only decides above-or-below; the content states its own height (the
  /// popup constrains WIDTH alone).
  final double height;

  final AnchoredPopupBuilder builder;

  /// The anchor. Its box is what the popup is placed against.
  final Widget child;

  @override
  State<PinnedAnchoredPopup> createState() => _PinnedAnchoredPopupState();
}

class _PinnedAnchoredPopupState extends State<PinnedAnchoredPopup> {
  /// The last placement that measured cleanly. Kept so a frame where the
  /// anchor is mid-relayout reuses the previous answer instead of dropping
  /// the window to a corner.
  _AnchoredPopupPlacement? _placement;

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: widget.controller,
      overlayChildBuilder: (overlayContext) {
        // Reading the media size SUBSCRIBES the popup to resizes, so the
        // window follows its button when the app window changes shape
        // instead of sitting at its opening coordinates. The dependency is
        // registered on the anchor's MediaQuery — that is what the portal
        // gives us over a raw overlay entry.
        MediaQuery.sizeOf(overlayContext);
        // `context` here is the ANCHOR's: the portal's own render object is
        // a proxy sized and positioned exactly like the child it wraps.
        final anchor = context.findRenderObject();
        final overlay = Overlay.of(context).context.findRenderObject();
        if (anchor is RenderBox && overlay is RenderBox) {
          _placement =
              _placeAnchoredPopup(
                anchor: anchor,
                overlay: overlay,
                width: widget.width,
                height: widget.height,
              ) ??
              _placement;
        }
        final placement = _placement;
        if (placement == null) {
          return const SizedBox.shrink();
        }
        return Positioned(
          key: ValueKey<String>('${widget.label}-pinned'),
          left: placement.left,
          top: placement.top,
          width: widget.width,
          child: widget.builder(overlayContext, widget.controller.hide),
        );
      },
      child: widget.child,
    );
  }
}

/// Where an anchored popup's box lands in overlay coordinates.
@immutable
class _AnchoredPopupPlacement {
  const _AnchoredPopupPlacement(this.left, this.top);

  final double left;
  final double top;
}

/// Null when the two boxes cannot be related yet — an anchor that has not
/// laid out has no coordinates to be right-aligned under.
_AnchoredPopupPlacement? _placeAnchoredPopup({
  required RenderBox anchor,
  required RenderBox overlay,
  required double width,
  required double height,
}) {
  if (!anchor.attached ||
      !anchor.hasSize ||
      !overlay.attached ||
      !overlay.hasSize) {
    return null;
  }
  final anchorBottomRight = anchor.localToGlobal(
    anchor.size.bottomRight(Offset.zero),
    ancestor: overlay,
  );
  final anchorTopRight = anchor.localToGlobal(
    Offset(anchor.size.width, 0),
    ancestor: overlay,
  );
  final left = (anchorBottomRight.dx - width).clamp(
    4.0,
    // A popup wider than the overlay would invert the clamp range.
    (overlay.size.width - width - 4.0).clamp(4.0, double.infinity),
  );
  final below = anchorBottomRight.dy + height <= overlay.size.height - 4;
  final top = below
      ? anchorBottomRight.dy + 2
      : (anchorTopRight.dy - height - 2).clamp(
          4.0,
          (overlay.size.height - height - 4.0).clamp(4.0, double.infinity),
        );
  return _AnchoredPopupPlacement(left, top);
}
