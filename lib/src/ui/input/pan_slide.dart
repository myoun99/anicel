import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'hit_path.dart';

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

/// Where a press lands on [slide]: everywhere in its box, over whatever it
/// holds — it takes nothing from the hit test.
class PanSlideRegion extends SingleChildRenderObjectWidget {
  const PanSlideRegion({super.key, required this.slide, super.child});

  final PanSlide slide;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderPanSlideRegion(slide);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderPanSlideRegion renderObject,
  ) {
    renderObject.slide = slide;
  }
}

/// [PanSlideRegion]'s box: on every hit test that lands in it, and nothing
/// more.
class RenderPanSlideRegion extends RenderProxyBoxWithHitTestBehavior {
  RenderPanSlideRegion(this.slide)
    : super(behavior: HitTestBehavior.translucent);

  PanSlide slide;
}
