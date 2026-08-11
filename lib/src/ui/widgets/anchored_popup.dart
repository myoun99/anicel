import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Builds an anchored popup's content. [close] is how the content dismisses
/// itself — a picker that closes on pick, a Done button. Both kinds of
/// popup hand the SAME callback shape, so content does not know (or care)
/// which kind is carrying it: the dismissing kind pops its route, the
/// pinned kind hides its overlay child.
typedef AnchoredPopupBuilder =
    Widget Function(BuildContext context, VoidCallback close);

/// THE WINDOW ITSELF — the surface, the corner, the lift off the canvas.
///
/// It lives here because the file already promised it did: "everything about
/// how the window behaves ... lives here, so restyling it restyles every
/// caller". Everything except what it LOOKS like, which each caller drew for
/// itself — and drew differently (elevation 6 in two of them, 8 in a third)
/// until one of them simply forgot.
///
/// 🐛유저, R4 #8: 브러시 팁 고르는 창이 듣도보도못한 투명한 창이 열린다.
/// `BrushTipPickerRow` opened through this function correctly and returned a
/// bare `Column`, so the picker rendered with NO BACKGROUND AT ALL — a grid
/// of tip swatches floating over whatever was behind it. Nothing was wrong
/// with the popup it asked for; the popup just never had a body of its own
/// to give it. A caller cannot forget this now.
class _AnchoredPopupSurface extends StatelessWidget {
  const _AnchoredPopupSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      // Colour, corner, outline and shadow all come from [AppPopupSurface]
      // — the same four values the menus read, so a popover and a flyout
      // opened side by side are one window with two contents (R6 #4). The
      // outline in particular is new here: this surface used to draw none
      // while every menu drew a hairline.
      color: AppPopupSurface.color,
      // CLIPPED, not merely painted: a shape that only fills leaves its
      // corners square to the pointer and to any child that paints to the
      // edge (the colour picker's saturation field does exactly that).
      clipBehavior: Clip.antiAlias,
      shape: AppPopupSurface.shape,
      elevation: AppPopupSurface.elevation,
      surfaceTintColor: AppPopupSurface.surfaceTint,
      child: child,
    );
  }
}

/// What an anchored window SAYS, as opposed to what it is made of.
///
/// 🐛유저, R6 #4: 「앵커팝오버등이 규격들이 다 제각각임. **텍스트사이즈도 다
/// 다르고** 이상함. 공통로직사용해서 통일화」.
///
/// The shell owned the window and not one word inside it, so the four
/// callers each invented a title: `TextStyle(fontSize: 11)`, `fontSize: 12
/// + w600`, `labelSmall` (11/w500) and `labelMedium` (12/w500) — four
/// treatments for the same line of text, over margins of 10, 10, 10 and
/// `fromLTRB(8, 6, 4, 4)`. Restyling the shell restyled every window's
/// FRAME and left its contents exactly as mismatched as before.
abstract final class AnchoredPopupText {
  /// The window's own name, once, at the top. Heavier than the flyout's
  /// 12pt rows on purpose: a menu is a list of peers, a window has a title.
  static const TextStyle title = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.text,
  );

  /// A line that explains rather than acts — an axis label, a caveat.
  ///
  /// ⚠️[AppColors.textDim] and NOT `hairline`: the SE mixer's pan caveat
  /// was drawn in the BORDER colour (0xFF37393C) on this surface
  /// (0xFF303336), which is a sentence you cannot read. A token borrowed
  /// from the wrong family stops being a colour choice and becomes a bug.
  static const TextStyle caption = TextStyle(
    fontSize: 10,
    color: AppColors.textDim,
  );

  /// The window's ONE margin. Content that fills its own width — a swatch
  /// grid, a colour wheel — lines its padding up with this rather than
  /// picking a smaller number of its own.
  static const EdgeInsets bodyPadding = EdgeInsets.all(10);

  /// Between the title row and the first control under it.
  static const double titleGap = 8;
}

/// The window's name, once, at the top — with the single control that
/// belongs beside it (a switch, an import button, a live swatch).
///
/// It ellipsises. Every one of these windows is 216–236px wide and at
/// least one title is built from a caller's string, so "it fits today" was
/// never a property anyone had checked.
class AnchoredPopupHeader extends StatelessWidget {
  const AnchoredPopupHeader({super.key, required this.title, this.trailing});

  final String title;

  /// The one control that reads as part of the title — not a toolbar.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AnchoredPopupText.title,
          ),
        ),
        ?trailing,
      ],
    );
  }
}

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
              builder: (context) => _AnchoredPopupSurface(
                child: builder(context, () => Navigator.of(context).maybePop()),
              ),
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
          // The same surface as the dismissing kind: they differ in what
          // makes them go away and in nothing else.
          child: _AnchoredPopupSurface(
            child: widget.builder(overlayContext, widget.controller.hide),
          ),
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
