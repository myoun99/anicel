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
  static TextStyle get title => TextStyle(
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
  static TextStyle get caption => TextStyle(
    fontSize: 10,
    color: AppColors.textDim,
  );

  /// The window's ONE margin. Content that fills its own width — a swatch
  /// grid, a colour wheel — lines its padding up with this rather than
  /// picking a smaller number of its own.
  static const double bodyPaddingValue = 10;
  static const EdgeInsets bodyPadding = EdgeInsets.all(bodyPaddingValue);

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

/// The ONE anchored sub-window (R28 #9).
///
/// The brush panel's pressure-curve editor established this shape and the
/// user asked for it to become the shared one: "창 자체는 브러시의 필압설정
/// 하는 열었을때랑 같은거. 그런식으로 서브 창 여는 로직 통일해서 사용. ui
/// 느낌 바꾸면 다른곳에도 적용되게." Everything about how the window
/// behaves — where it lands, how it dismisses, that it appears in one
/// frame — lives here, so restyling it restyles every caller.
///
/// Anything you touch outside it closes it: right for a pick-one-and-go
/// list. It lands right-aligned under the anchor, flipped above when there
/// is no room below, clamped into the overlay either way
/// ([_placeAnchoredPopup]).
///
/// 🪦A second, PINNED kind stood here (`PinnedAnchoredPopup`), for the
/// colour window: it stayed while you worked the canvas underneath, so a
/// colour could be nudged and the stroke tried without the window blinking
/// out (유저 확정: "색만 안 사라지게"). ⚠️It could not be a route — a
/// barrier eats the canvas stroke even when it is transparent — and rode an
/// `OverlayPortal` instead. The colour window became the colour panels
/// (`67893911e`, 2026-08-07) and nothing opened it again; it went with
/// I-131 (2026-10-28). A window that stays over the canvas came back the
/// next day as `FloatingAppWindow` (I-141-Q3) — not anchored, moved by its
/// title bar, on the same portal for the same reason.
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
  final open = anchorContext
      .getInheritedWidgetOfExactType<AnchoredPopupsOpenFrom>()
      ?.open;
  final popup = Object();
  open?.add(popup);
  return showGeneralDialog<T>(
    context: anchorContext,
    barrierLabel: label,
    // ↩️`false` from R27 #5 (2026-07-22) to F-450 (2026-10-23), and Escape
    // went with it: Flutter hands a route's Escape to this flag
    // (`_DismissModalAction`), and R27 #5 meant only the barrier's TAP. That
    // tap cannot come — the field below takes every press first — so the
    // flag now says only the window's other ways out, Escape and a screen
    // reader's dismiss, as every other window has them (`showDialogVerb`).
    // 유저 2026-10-23 (F-450), the pressure window up: 「키보드도 안먹힘」.
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    // Flyout rule (R4 #2): the popup appears in one frame.
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) {
      return Stack(
        children: [
          // Dismissal is on pointer DOWN outside, NOT the barrier's tap
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
  ).whenComplete(() => open?.remove(popup));
}

/// THE POPUPS OPEN FROM INSIDE A SURFACE: each [showAnchoredPopup] whose
/// anchor stands under it is in [open] while it is up.
///
/// A popup is a route over everything, so neither a press on it nor the
/// keyboard's focus in it lies inside the surface it was opened from. A
/// surface that must know an edit begun on it is still in flight — the
/// rows a grid builds in berths (`RowBerths`) — asks here.
class AnchoredPopupsOpenFrom extends InheritedWidget {
  const AnchoredPopupsOpenFrom({
    super.key,
    required this.open,
    required super.child,
  });

  /// The surface's own set: one token for each popup up now.
  final Set<Object> open;

  /// Asked once, at a popup's opening, and by nothing that depends on it.
  @override
  bool updateShouldNotify(AnchoredPopupsOpenFrom oldWidget) => false;
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
