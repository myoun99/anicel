import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A ROW THAT KEEPS ITS TAIL: the [tail] at its own width, pinned to the
/// row's end — and where the row is narrower than that, ALL of it,
/// smaller; the [head] takes what is left, each in the middle of the row's
/// height.
///
/// 🗣️THE PAGE TURNER'S LAW, as the canvas pill keeps it
/// (`canvas-bottom-bar-overflows-at-437`): a panel too narrow for what the
/// fold kept shows all of it, smaller — never a row that runs off, never a
/// control cut away. The head is the fold, and the tail is what it keeps.
/// ⚠️Where it fits, nothing is scaled.
///
/// The head keeps [headKeeps] for itself — the place of what ITS OWN fold
/// keeps: a tab strip's list button, the one way to the tabs it folded. The
/// kept end gives way before that place does; below it, nothing is
/// promised. ([FloorFoldRow] is the row whose head's place is shown smaller
/// with the rest.)
///
/// ↩️Each of these rows was a `Row`, which lays a child that does not flex
/// out with all the width there is: a tail wider than the row was laid out
/// wider, and ran off it (the timeline's bar in a 360px window, a panel's
/// tab strip at 340, the top strip at 320 — measured 2026-10-14 · 15).
/// ↩️It kept a LEAD too, at the row's start — the frame panels' transport
/// (F-111-Q1), until the transport joined the zoom at the bar's end (F-463,
/// [FloorFoldRow]).
///
/// ⚠️Laid out by a render object, not a [LayoutBuilder], for the transport's
/// play row's reason (`_PlayRowLayout`): the row is sized while it is laid
/// out, so nothing is built again to learn a width.
class KeptTailRow extends StatelessWidget {
  const KeptTailRow({
    super.key,
    this.head,
    required this.tail,
    this.gap = 0,
    this.headKeeps = 0,
  });

  /// What takes the room the kept end leaves — exactly that room. Null
  /// leaves the row's start empty and still pins the tail to its end.
  final Widget? head;

  final Widget tail;

  /// Between the head and the tail.
  final double gap;

  /// The least the [head] is left, where there is a head.
  final double headKeeps;

  @override
  Widget build(BuildContext context) =>
      _KeptEnds(head: head, tail: tail, gap: gap, headKeeps: headKeeps);
}

/// A ROW OF TWO GROUPS THAT GIVE WAY IN TURN, EACH DOWN TO A FLOOR — and
/// below their floors, BOTH, smaller by one factor: the frame panels'
/// command bar.
///
/// 🗣️F-463 ⑥ (유저 2026-10-25 16:46): 「각 묶음마다 최소길이가 있어서 그
/// 길이만큼까지만 줄고, 그 이상으로 줄때 전체적으로 작아짐. 우선 컷쪽은
/// 컷알약까지 최소폭 … 먼저 컷/레이어/프레임쪽 줄어들고」. The [head] takes
/// the room the [tail] leaves, down to its floor — from its start to the
/// end of the [FoldFloor] inside it, and [headPadding] after that. The
/// [tail] stands at its own width at the row's end; once the head stands at
/// its floor the tail gives way too, down to its floor — from the start of
/// the [FoldFloor] inside it to its end (a tail with none keeps its own
/// width). Where the row cannot hold both floors, both are shown smaller
/// by ONE factor. The tail is laid out at the width it is left: what does
/// not stand in it is its own to scroll.
///
/// 🗣️F-491 (유저 2026-10-27 23:15): 「재생쪽은 역시 왼쪽 묶음의 제일
/// 왼쪽으로 옮기도록 … 오른쪽묶음엔 컷이름/줌/fit 이순서로 남도록. 그리고
/// 공간 좁아서 오른쪽 묶음 줄기시작할때, 지금 스크롤의 제일 왼쪽이 마지막에
/// 남을텐데, 그게아니라 오른쪽이 마지막에 남도록 … 왼쪽묶음은 … 줄어들때도
/// 같은룰대로 제일 왼쪽것이 마지막으로 남는구조」 — the head is the
/// transport and the pills, kept by its start; the tail is the cut's name,
/// the zoom and its fit, kept by its end. ↩️F-463 ⑥ (17:15: 「왼쪽묶음에
/// 전처럼 컷/레이어/프레임/fx 등을 한 묶음, 재생버튼쪽은 오른쪽에 줌쪽
/// 버튼이랑 같은묶음」) and F-463-Q1 (20:2x: 「오른쪽묶음은 오른쪽묶음에서
/// 제일 왼쪽이 남는구조」) put the transport before the zoom in the tail,
/// kept by its first button; (15:23) 「묶음 안에서 재생 · 줌이 따로」 kept
/// each by a button of its own, as a middle group here; and before that
/// the two were one tail that did not give way, only shown smaller.
///
/// ↩️The bar was a [KeptTailRow] with the transport kept at its start: the
/// pills took whatever the two ends left, down to nothing (F-111-Q2, 유저
/// 2026-10-25 「그대로 — 알약은 남는 만큼」), and only the ends were shown
/// smaller.
class FloorFoldRow extends StatefulWidget {
  const FloorFoldRow({
    super.key,
    this.head,
    required this.tail,
    this.gap = 0,
    this.headPadding = 0,
  });

  /// The group that gives way first, down to its [FoldFloor]. Null leaves
  /// the whole row the tail's: no gap is kept before it, and no floor.
  final Widget? head;

  /// The group at the row's end, which gives way after the head.
  final Widget tail;

  /// Between the head and the tail.
  final double gap;

  /// What the head holds past its floor's end — the padding its scroller
  /// stands in on that side.
  final double headPadding;

  @override
  State<FloorFoldRow> createState() => _FloorFoldRowState();
}

class _FloorFoldRowState extends State<FloorFoldRow> {
  /// What each group's [FoldFloor] measured when it was last laid out.
  final Map<_Part, _FloorReading> _readings = {
    for (final part in _Part.values) part: _FloorReading(),
  };

  Widget? _floored(_Part part, Widget? group) => switch (group) {
    final group? => _FloorScope(reading: _readings[part]!, child: group),
    null => null,
  };

  @override
  Widget build(BuildContext context) => _FloorEnds(
    readings: _readings,
    head: _floored(_Part.head, widget.head),
    tail: _floored(_Part.tail, widget.tail)!,
    gap: widget.gap,
    headPadding: widget.headPadding,
  );
}

/// What a [FloorFoldRow]'s group keeps when it gives way: the least of it
/// that is shown — reckoned from the end its group keeps, so what stands
/// between that end and the floor is kept with it. The head keeps its
/// start, down to its floor's end: the transport and the cut pill of the
/// frame panels' left group (「컷알약까지 최소폭」 · F-491: the transport at
/// its start). The tail keeps its end, down to its floor's start: the zoom
/// fit and what stands after it (F-491: 「오른쪽이 마지막에 남도록. 즉
/// 지금으로 치면 fit버튼」). Outside a [FloorFoldRow] it is its child alone.
///
/// ↩️The floor was its own width alone, at its group's start, until F-491
/// put the transport before the cut pill.
class FoldFloor extends SingleChildRenderObjectWidget {
  const FoldFloor({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFoldFloor(_FloorScope.readingOf(context));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderFoldFloor).keepIn(_FloorScope.readingOf(context));
}

/// Where a group's [FoldFloor]s stand, for the row round it to read once it
/// has laid the group out — none where its group holds none.
class _FloorReading {
  /// Each floor the group holds, at the width it was laid out at — its own
  /// to say: the row may read the size of its group, not of what the group
  /// holds.
  final Map<_RenderFoldFloor, double> _widths = {};

  /// How much of its group its floors keep, from the start ([fromTheEnd]
  /// false) to the farthest floor's end, or from the farthest floor's start
  /// to the end — in the group as it is laid out, unscrolled: a scroller
  /// lays what it holds at its own origin and moves it only where it paints
  /// it.
  double? reach({required bool fromTheEnd}) {
    double? farthest;
    for (final MapEntry(key: floor, value: width) in _widths.entries) {
      // Off the tree for now — moved, or folded away — it keeps nothing.
      if (!floor.attached) {
        continue;
      }
      RenderBox group = floor;
      var start = 0.0;
      for (
        var parent = group.parent;
        parent is RenderBox && parent is! _RenderFloorEnds;
        parent = group.parent
      ) {
        if (group.parentData case final BoxParentData data) {
          start += data.offset.dx;
        }
        group = parent;
      }
      final reach = fromTheEnd ? group.size.width - start : start + width;
      farthest = math.max(farthest ?? reach, reach);
    }
    return farthest;
  }
}

class _FloorScope extends InheritedWidget {
  const _FloorScope({required this.reading, required super.child});

  final _FloorReading reading;

  static _FloorReading? readingOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<_FloorScope>()
      ?.reading;

  @override
  bool updateShouldNotify(_FloorScope oldWidget) =>
      !identical(oldWidget.reading, reading);
}

class _RenderFoldFloor extends RenderProxyBox {
  _RenderFoldFloor(this._reading);

  _FloorReading? _reading;

  /// Where the floor says what it keeps — its group's reading.
  void keepIn(_FloorReading? value) {
    if (!identical(value, _reading)) {
      _reading?._widths.remove(this);
      _reading = value;
      markNeedsLayout();
    }
  }

  @override
  void performLayout() {
    super.performLayout();
    _reading?._widths[this] = size.width;
  }

  @override
  void dispose() {
    _reading?._widths.remove(this);
    super.dispose();
  }
}

enum _Part { head, tail }

class _KeptEnds extends SlottedMultiChildRenderObjectWidget<_Part, RenderBox> {
  const _KeptEnds({
    required this.head,
    required this.tail,
    required this.gap,
    required this.headKeeps,
  });

  final Widget? head;
  final Widget tail;
  final double gap;
  final double headKeeps;

  @override
  Iterable<_Part> get slots => _Part.values;

  @override
  Widget? childForSlot(_Part slot) => switch (slot) {
    _Part.head => head,
    _Part.tail => tail,
  };

  @override
  _RenderKeptEnds createRenderObject(BuildContext context) =>
      _RenderKeptEnds(gap: gap, headKeeps: headKeeps);

  @override
  void updateRenderObject(BuildContext context, _RenderKeptEnds row) => row
    ..gap = gap
    ..headKeeps = headKeeps;
}

class _FloorEnds extends SlottedMultiChildRenderObjectWidget<_Part, RenderBox> {
  const _FloorEnds({
    required this.readings,
    required this.head,
    required this.tail,
    required this.gap,
    required this.headPadding,
  });

  final Map<_Part, _FloorReading> readings;
  final Widget? head;
  final Widget tail;
  final double gap;
  final double headPadding;

  @override
  Iterable<_Part> get slots => _Part.values;

  @override
  Widget? childForSlot(_Part slot) => switch (slot) {
    _Part.head => head,
    _Part.tail => tail,
  };

  @override
  _RenderFloorEnds createRenderObject(BuildContext context) =>
      _RenderFloorEnds(readings, gap: gap, headPadding: headPadding);

  @override
  void updateRenderObject(BuildContext context, _RenderFloorEnds row) => row
    ..gap = gap
    ..headPadding = headPadding;
}

/// A row of parts, each painted and hit at its offset and, shown smaller,
/// at its scale — what both rows here share.
abstract class _RenderScaledParts extends RenderBox
    with SlottedContainerRenderObjectMixin<_Part, RenderBox> {
  _RenderScaledParts({required double gap}) : _gap = gap;

  double _gap;
  double get gap => _gap;
  set gap(double value) {
    if (value != _gap) {
      _gap = value;
      markNeedsLayout();
    }
  }

  /// What each part is shown at — 1 where the row holds it.
  final Map<_Part, double> _scales = {};

  final Map<_Part, LayerHandle<TransformLayer>> _layers = {
    for (final part in _Part.values) part: LayerHandle<TransformLayer>(),
  };

  RenderBox? get _head => childForSlot(_Part.head);
  RenderBox get _tail => childForSlot(_Part.tail)!;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.biggest;

  /// Puts [child] at [dx], in the middle of the row's height, shown at
  /// [scale].
  void _put(_Part part, RenderBox child, double dx, double scale) {
    _scales[part] = scale;
    _offsetOf(child).offset = Offset(
      dx,
      (size.height - child.size.height * scale) / 2,
    );
  }

  BoxParentData _offsetOf(RenderBox child) =>
      child.parentData! as BoxParentData;

  /// Where [child] is painted from — its offset, and its scale if it is
  /// shown smaller.
  Matrix4 _transformOf(_Part part, RenderBox child) {
    final at = _offsetOf(child).offset;
    final scale = _scales[part] ?? 1;
    return Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(at.dx, at.dy, 0);
  }

  Iterable<(_Part, RenderBox)> get _parts sync* {
    for (final part in _Part.values) {
      if (childForSlot(part) case final child?) {
        yield (part, child);
      }
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final (part, child) in _parts) {
      final at = offset + _offsetOf(child).offset;
      final scale = _scales[part] ?? 1;
      final layer = _layers[part]!;
      if (scale == 1) {
        layer.layer = null;
        context.paintChild(child, at);
        continue;
      }
      layer.layer = context.pushTransform(
        needsCompositing,
        at,
        Matrix4.diagonal3Values(scale, scale, 1),
        (context, offset) => context.paintChild(child, offset),
        oldLayer: layer.layer,
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final (part, child) in _parts.toList().reversed) {
      final hit = result.addWithPaintTransform(
        transform: _transformOf(part, child),
        position: position,
        hitTest: (result, position) =>
            child.hitTest(result, position: position),
      );
      if (hit) {
        return true;
      }
    }
    return false;
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final part = _parts.firstWhere((entry) => identical(entry.$2, child)).$1;
    transform.multiply(_transformOf(part, child));
  }

  @override
  void dispose() {
    for (final layer in _layers.values) {
      layer.layer = null;
    }
    super.dispose();
  }
}

class _RenderKeptEnds extends _RenderScaledParts {
  _RenderKeptEnds({required super.gap, required double headKeeps})
    : _headKeeps = headKeeps;

  double _headKeeps;
  double get headKeeps => _headKeeps;
  set headKeeps(double value) {
    if (value != _headKeeps) {
      _headKeeps = value;
      markNeedsLayout();
    }
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    final head = _head;
    final tail = _tail;
    // The kept end is laid out at its own size, as a scaling box lays its
    // child, and shown smaller where the row cannot hold it.
    tail.layout(const BoxConstraints(), parentUsesSize: true);
    final room = math.max(
      0.0,
      size.width - (head == null ? 0 : _gap + _headKeeps),
    );
    final own = tail.size;
    final byWidth = own.width > room ? room / own.width : 1.0;
    final byHeight = own.height > size.height ? size.height / own.height : 1.0;
    final scale = math.min(byWidth, byHeight);
    final shownTail = own.width * scale;
    _put(_Part.tail, tail, size.width - shownTail, scale);
    if (head == null) {
      return;
    }
    final width = math.max(0.0, size.width - shownTail - _gap);
    head.layout(
      BoxConstraints(minWidth: width, maxWidth: width, maxHeight: size.height),
      parentUsesSize: true,
    );
    _put(_Part.head, head, 0, 1);
  }
}

/// A [FloorFoldRow]'s tail as it stands at its own size: shown [fit] of
/// itself where it is taller than the row, as a scaling box shows it,
/// [own] wide so — and the least of it the row may show, [floor].
typedef _TailAtItsOwn = ({double fit, double own, double floor});

class _RenderFloorEnds extends _RenderScaledParts {
  _RenderFloorEnds(
    this._readings, {
    required super.gap,
    required double headPadding,
  }) : _headPadding = headPadding;

  final Map<_Part, _FloorReading> _readings;

  double _headPadding;
  double get headPadding => _headPadding;
  set headPadding(double value) {
    if (value != _headPadding) {
      _headPadding = value;
      markNeedsLayout();
    }
  }

  void _layAt(RenderBox group, double width, double height) => group.layout(
    BoxConstraints(minWidth: width, maxWidth: width, maxHeight: height),
    parentUsesSize: true,
  );

  /// The least [head] is shown at: laid out first where the tail leaves it
  /// ([room]), which is where its [FoldFloor] is measured.
  double _floorOf(RenderBox head, double room) {
    _layAt(head, math.max(0, room), size.height);
    return (_readings[_Part.head]!.reach(fromTheEnd: false) ?? 0) +
        _headPadding;
  }

  /// [tail] laid out at its own size — where its [FoldFloor] is measured;
  /// all of it is its floor where it holds none.
  _TailAtItsOwn _atItsOwn(RenderBox tail) {
    tail.layout(const BoxConstraints(), parentUsesSize: true);
    final own = tail.size;
    final fit = own.height > size.height ? size.height / own.height : 1.0;
    return (
      fit: fit,
      own: own.width * fit,
      floor:
          (_readings[_Part.tail]!.reach(fromTheEnd: true) ?? own.width) * fit,
    );
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    final head = _head;
    final tail = _tail;
    final atItsOwn = _atItsOwn(tail);
    final gap = head == null ? 0.0 : _gap;
    final room = size.width - gap - atItsOwn.own;
    final floor = head == null ? 0.0 : _floorOf(head, room);
    // Past the head's floor, the tail gives way, down to its own.
    final over = math.max(0.0, floor - room);
    final gives = math.min(
      over,
      math.max(0.0, atItsOwn.own - atItsOwn.floor),
    );
    final shownTail = atItsOwn.own - gives;
    // Below both floors, both of them at their floors, smaller by one factor.
    final under = over - gives;
    final scale = under > 0 ? size.width / (size.width + under) : 1.0;
    if (head != null) {
      final width = scale < 1 ? floor : size.width - gap - shownTail;
      _layAt(head, width, size.height / scale);
      _put(_Part.head, head, 0, scale);
    }
    if (gives > 0) {
      _layAt(tail, shownTail / atItsOwn.fit, double.infinity);
    }
    _put(
      _Part.tail,
      tail,
      size.width - shownTail * scale,
      atItsOwn.fit * scale,
    );
  }
}
