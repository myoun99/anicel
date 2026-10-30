import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../timeline/axis_turn.dart' show offsetAlong, partAlong;
import 'hit_path.dart';
import 'wheel_law.dart';

/// 🚨★★A PAN MOVES WHAT IT STARTED ON — over a sheet's layer area, the
/// layer area: its layers, and its own window along the rail. The frames
/// beside it stay where they are.
///
/// 🗣️F-351 (유저 2026-10-16): 「레이어 영역을 잡아도 프레임쪽이 팬
/// 작동되는데 레이어쪽을 잡으면 레이어영역이 팬 작동하도록」 — a sheet's one
/// drag ([TwoAxisDrag]) and the canvas's pan ([PanelPanDriver]) both moved
/// the frames wherever the hand landed.
///
/// A part of a sheet that slides along one of the sheet's axes by itself —
/// a layer rail's window (`LayerRailWindow`) — stands in a [PanSlideRegion],
/// and a pan that STARTS over it moves that [PanSlide] in place of the
/// sheet's scrollers along the slide's axis ([panMoves]). The other axis is
/// the sheet's, as it was. Both pans ask the same two questions, here.
abstract interface class PanSlide {
  /// The axis it slides along.
  Axis get axis;

  /// Whether it has anywhere to slide — as a scroller that cannot scroll
  /// takes no drag.
  bool get canSlide;

  /// Slides it by the part of [delta] along [axis], with the hand: what it
  /// shows goes the way the hand does.
  void slideWithHand(Offset delta);
}

/// The [PanSlide] [event] landed on — the deepest under it — or null.
///
/// Asked of the screen where the press lands, so a pan above the slide
/// knows what it landed on whatever its place in the tree — or of [within]
/// alone, for a pan that holds what is under it out of the hit test while
/// it pans ([PanelPanDriver]'s gate).
PanSlide? panSlideUnder(PointerEvent event, {RenderBox? within}) {
  final path = within == null
      ? hitPathInView(event.position, event.viewId)
      : hitPathWithin(within, event.position);
  return path.whereType<RenderPanSlideRegion>().firstOrNull?.slide;
}

/// Whether a pan that landed on [slide] moves [position]: every scroller of
/// the sheet but those along the slide's axis — the slide moves that way.
bool panMoves(ScrollPosition position, PanSlide? slide) =>
    position.axis != slide?.axis;

/// Moves [position] by the part of [delta] along its axis, with the hand:
/// the content goes with it — dragging down shows what was above — as far
/// as it can scroll. What a pan that drives no drag of the scroller's own
/// moves it by: the canvas's pan on a panel ([PanelPanDriver]) and a
/// sheet's pinch ([TwoAxisDrag]).
void scrollWithHand(ScrollPosition position, Offset delta) {
  final to = (position.pixels - partAlong(position.axis, delta)).clamp(
    position.minScrollExtent,
    position.maxScrollExtent,
  );
  if (to != position.pixels) {
    position.jumpTo(to);
  }
}

/// Where a press lands on [slide]: everywhere in its box, over whatever it
/// holds — it takes nothing from the hit test.
///
/// 🚨A WHEEL OVER IT MOVES IT TOO, the same way: the notch a scroller along
/// the slide's axis would take there ([wheelDeltaAlong]) slides it as its
/// scrollbar pushes it, and every other notch is the sheet's scrollers', as
/// a pan leaves them the other axis ([panMoves]). Where it has nowhere to
/// slide the notch is still its own, and does nothing — as a pan there.
/// 🗣️F-447-Q1 (유저 2026-10-23): 「그 영역 자신을 — 팬(F-351)과 같은 법」:
/// over the x-sheet's header the wheel pushes the header's window and,
/// Shift held, the layers; over a timeline's rail it scrolls the rows and,
/// Shift held, pushes the rail's window.
class PanSlideRegion extends SingleChildRenderObjectWidget {
  const PanSlideRegion({super.key, required this.slide, super.child});

  final PanSlide slide;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderPanSlideRegion(slide, flipKeys: _flipKeysAt(context));

  @override
  void updateRenderObject(
    BuildContext context,
    RenderPanSlideRegion renderObject,
  ) {
    renderObject
      ..slide = slide
      ..flipKeys = _flipKeysAt(context);
  }

  /// The keys that turn a notch the other way here — the scrollers'.
  static Set<LogicalKeyboardKey> _flipKeysAt(BuildContext context) =>
      ScrollConfiguration.of(context).pointerAxisModifiers;
}

/// [PanSlideRegion]'s box: on every hit test that lands in it, and nothing
/// more — and the notches along its slide's axis.
class RenderPanSlideRegion extends RenderProxyBoxWithHitTestBehavior {
  RenderPanSlideRegion(this.slide, {required this.flipKeys})
    : super(behavior: HitTestBehavior.translucent);

  PanSlide slide;

  /// [PanSlideRegion._flipKeysAt].
  Set<LogicalKeyboardKey> flipKeys;

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final axis = slide.axis;
    final push = wheelDeltaAlong(axis, event, flipKeys: flipKeys);
    if (push == 0) {
      return;
    }
    handleWheelExclusively(
      event,
      (_) => slide.slideWithHand(
        offsetAlong(axis, along: -push, across: 0),
      ),
    );
  }
}
