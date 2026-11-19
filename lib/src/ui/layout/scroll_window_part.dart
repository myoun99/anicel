import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'device_grid.dart';
import 'device_grid_scroll_controller.dart';

/// Where a [ScrollWindowPart] lays what it holds: [top] down from its own
/// top, [extent] tall.
typedef ShownPart = ({double top, double extent});

/// What a box [slotTop] down a scrolled column and [slotExtent] tall lays
/// its child as, with the scroll's window over `windowTop..windowBottom` of
/// that column: the whole box, or — when the window shows only some of its
/// body — a child whose body is the part the window shows.
///
/// The child's first [head] is its own chrome, not its body (a panel's tab
/// strip): it keeps its place above the body, in the window or out of it,
/// and is never what gets cut. The child is never laid shorter than
/// [floor] — the least it lays out in at all; past it, it keeps the floor
/// and the window cuts the rest.
ShownPart shownPartOf({
  required double slotTop,
  required double slotExtent,
  required double head,
  required double floor,
  required double windowTop,
  required double windowBottom,
}) {
  final whole = (top: 0.0, extent: slotExtent);
  final bodyTop = math.max(slotTop + head, windowTop);
  final bodyBottom = math.min(slotTop + slotExtent, windowBottom);
  if (bodyBottom <= bodyTop) {
    return whole;
  }
  final extent = math.max(head + bodyBottom - bodyTop, floor);
  if (extent >= slotExtent) {
    return whole;
  }
  return (
    top: math.min(bodyTop - head - slotTop, slotExtent - extent),
    extent: extent,
  );
}

/// The CONTENT of a vertical scrollable driven by [controller] alone, in a
/// window [viewport] tall — and what lays the [ScrollWindowPart]s inside it
/// to that window. It goes between the viewport and the content, outside
/// a [ScrollStoodInLayout].
///
/// 🚨WHERE THE WINDOW IS READ. A single-child viewport lays its content out
/// FIRST and pulls its position into the new range after; a stand
/// ([ScrollStoodInLayout]) moves it between the two. A part laid out with
/// the content reads the position before both — a group closing under a
/// rail scrolled to its end, or the rail stood to show a group just
/// opened, left the others laid to a window that was no longer there. So
/// this reads the window once its content is laid out and stood, takes the
/// pull the viewport is about to make — into `0..content − viewport`, the
/// one range a single-child viewport has — and lays again, in the same
/// frame, every part the window has moved.
///
/// ↩️It stood OUTSIDE the viewport first, to read the position after the
/// pull itself. A viewport between tight constraints is a relayout
/// boundary: content that changed laid the viewport out and nothing above
/// it, and the closing group's neighbour kept the old window (🧪caught by
/// the test of that frame).
///
/// A scroll moves the position without a layout: that is heard
/// ([ScrollController.addListener]) and the parts it moves are marked
/// there, through the same reading.
class ScrollWindowSettle extends SingleChildRenderObjectWidget {
  const ScrollWindowSettle({
    super.key,
    required this.controller,
    required this.viewport,
    required Widget super.child,
  });

  final ScrollController controller;

  /// How tall the scrollable's window is.
  final double viewport;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScrollWindowSettle(controller, DeviceGrid.of(context), viewport);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderScrollWindowSettle).configure(
        controller,
        DeviceGrid.of(context),
        viewport,
      );
}

/// A box inside a [ScrollWindowSettle]'s content, [top] down it, that lays
/// what it holds to the part of it the window shows ([shownPartOf]) — so a
/// scrollable inside it scrolls within what can be seen, and its bar is all
/// in view.
///
/// It keeps its own size: the column it stands in, and everything that
/// reads where its edges are, are unchanged.
class ScrollWindowPart extends SingleChildRenderObjectWidget {
  const ScrollWindowPart({
    super.key,
    required this.controller,
    required this.top,
    required this.head,
    required this.floor,
    required Widget super.child,
  });

  /// The controller of the scrollable this stands in.
  final ScrollController controller;

  /// Where this box's top is in the scrolled content.
  final double top;

  /// See [shownPartOf].
  final double head;
  final double floor;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScrollWindowPart(controller)
        ..configure(controller, top, head, floor);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderScrollWindowPart).configure(
        controller,
        top,
        head,
        floor,
      );
}

/// What a settle and its parts share: the window, as the settle last read
/// it, and the parts laid to it. Found by the CONTROLLER both are given —
/// the one fact that says which scrollable a part stands in.
class _Book {
  final Set<_RenderScrollWindowPart> parts = {};
  ({double top, double bottom})? window;
}

final Expando<_Book> _books = Expando<_Book>('scroll window parts');

_Book _bookOf(ScrollController controller) =>
    _books[controller] ??= _Book();

class _RenderScrollWindowSettle extends RenderProxyBox {
  _RenderScrollWindowSettle(this._controller, this._grid, this._viewport);

  ScrollController _controller;
  DeviceGrid _grid;
  double _viewport;

  void configure(
    ScrollController controller,
    DeviceGrid grid,
    double viewport,
  ) {
    if (identical(controller, _controller) &&
        grid.ratio == _grid.ratio &&
        viewport == _viewport) {
      return;
    }
    if (attached) {
      _controller.removeListener(_scrolled);
      controller.addListener(_scrolled);
    }
    _controller = controller;
    _grid = grid;
    _viewport = viewport;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(_scrolled);
  }

  @override
  void detach() {
    _controller.removeListener(_scrolled);
    super.detach();
  }

  void _scrolled() {
    for (final part in _staleAt(singleScrollPixelsOf(_controller))) {
      part.markNeedsLayout();
    }
  }

  @override
  void performLayout() {
    super.performLayout();
    final pixels = singleScrollPixelsOf(_controller);
    final pulled = pixels == null
        ? null
        : clampDouble(pixels, 0, math.max(0, size.height - _viewport));
    final stale = _staleAt(pulled);
    if (stale.isEmpty) {
      return;
    }
    invokeLayoutCallback<BoxConstraints>((_) {
      for (final part in stale) {
        part.markNeedsLayout();
      }
    });
  }

  /// The parts the window at [pixels] has moved, the window now that.
  ///
  /// Its top is where the content is PAINTED from, landed on the grid as
  /// [DeviceGridScrollBody] lands it — so a part's bar ends on the device
  /// pixel the window does.
  List<_RenderScrollWindowPart> _staleAt(double? pixels) {
    final book = _bookOf(_controller);
    final top = pixels == null
        ? null
        : pixels - deviceGridScrollCorrection(pixels, _grid);
    book.window = top == null ? null : (top: top, bottom: top + _viewport);
    return [
      for (final part in book.parts)
        if (part.isStale) part,
    ];
  }
}

class _RenderScrollWindowPart extends RenderShiftedBox {
  _RenderScrollWindowPart(this._controller) : super(null);

  ScrollController _controller;
  double _top = 0;
  double _head = 0;
  double _floor = 0;

  void configure(
    ScrollController controller,
    double top,
    double head,
    double floor,
  ) {
    if (identical(controller, _controller) &&
        top == _top &&
        head == _head &&
        floor == _floor) {
      return;
    }
    if (attached) {
      _bookOf(_controller).parts.remove(this);
      _bookOf(controller).parts.add(this);
    }
    _controller = controller;
    _top = top;
    _head = head;
    _floor = floor;
    markNeedsLayout();
  }

  /// What the child was last laid as, in a box how tall — null until it
  /// is. The settle reads it, and a box's size is its parent's to read.
  ({ShownPart part, double extent})? _laid;

  ShownPart _shownIn(double extent) {
    final window = _bookOf(_controller).window;
    if (window == null) {
      return (top: 0.0, extent: extent);
    }
    return shownPartOf(
      slotTop: _top,
      slotExtent: extent,
      head: _head,
      floor: _floor,
      windowTop: window.top,
      windowBottom: window.bottom,
    );
  }

  /// Whether the window has moved this box's shown part since its child
  /// was laid — a box it shows all or none of stays as it was.
  bool get isStale {
    final laid = _laid;
    return laid != null && laid.part != _shownIn(laid.extent);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _bookOf(_controller).parts.add(this);
  }

  @override
  void detach() {
    _bookOf(_controller).parts.remove(this);
    super.detach();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    final shown = _shownIn(size.height);
    _laid = (part: shown, extent: size.height);
    child!.layout(
      BoxConstraints.tightFor(width: size.width, height: shown.extent),
    );
    (child!.parentData! as BoxParentData).offset = Offset(0, shown.top);
  }
}
