import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Where a scrollable is asked to stand, and which asking it is
/// ([ScrollStoodInLayout]).
typedef ScrollStand = ({int asking, double pixels});

/// The content of a scrollable which, asked, stands that scrollable at an
/// offset IN THE LAYOUT THAT LAYS THE CONTENT OUT — so what a build just
/// added to the content is in the window in the first frame it is drawn in.
///
/// 🚨WHY IN LAYOUT (card the-media-button-lights-but-no-media-panel-shows,
/// 2026-11-15). How far a scrollable can go is its content's extent, and
/// that is known once the content is laid out. A jump asked before the
/// frame lands in the old extent; one asked after it (a post-frame
/// callback, `Scrollable.ensureVisible`) leaves a frame drawn with the new
/// content where the old offset puts it, and moves it in the next —
/// 「한프레임 보이는건 무조건걸리고 싫어」 (유저 2026-08-12). A single-child
/// viewport lays its content out, pulls its position into the new range,
/// and paints, in that order; this stands the position between the first
/// two, so the pull keeps it in range and the paint is the first there is.
///
/// ⚠️`correctPixels` tells no listener — it is the writer a layout is
/// given. The viewport above paints after its own layout either way; what
/// reads the position from outside it looks again once the frame is laid
/// out (`AppControllerScrollbar`) or reads it as it paints
/// (`DeviceGridScrollBody`).
class ScrollStoodInLayout extends SingleChildRenderObjectWidget {
  const ScrollStoodInLayout({
    super.key,
    required this.controller,
    required this.stand,
    required Widget super.child,
  });

  /// The controller of the scrollable this is the content of — its one.
  final ScrollController controller;

  /// Where the scrollable is asked to stand: it is stood there once for
  /// each asking, in the layout after it comes. Null asks nothing.
  final ScrollStand? stand;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScrollStoodInLayout(controller)..ask(stand);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderScrollStoodInLayout)
      ..controller = controller
      ..ask(stand);
  }
}

class _RenderScrollStoodInLayout extends RenderProxyBox {
  _RenderScrollStoodInLayout(this.controller);

  ScrollController controller;

  /// The last asking heard, and where it stands the scrollable — until the
  /// layout that answers it has run.
  int? _asking;
  double? _waiting;

  /// An asking not heard before waits for the next layout, and asks for
  /// one: content that did not change would not be laid out, nor its
  /// viewport painted.
  void ask(ScrollStand? stand) {
    if (stand == null || stand.asking == _asking) {
      return;
    }
    _asking = stand.asking;
    _waiting = stand.pixels;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    super.performLayout();
    final pixels = _waiting;
    if (pixels != null) {
      _waiting = null;
      controller.position.correctPixels(pixels);
    }
  }
}
