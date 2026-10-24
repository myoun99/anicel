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
/// A row may keep its [lead] too, pinned to its start: the frame panels'
/// bar keeps the transport there (유저 2026-10-08, F-111-Q1 「버튼행 맨
/// 왼쪽에 고정 — 알약 칸 밖」). Both ends are what the fold keeps, so where
/// the row cannot hold them both, both are shown whole and smaller BY ONE
/// FACTOR — neither gives way for the other.
///
/// The head keeps [headKeeps] for itself — the place of what ITS OWN fold
/// keeps: a tab strip's list button, the one way to the tabs it folded. The
/// kept ends give way before that place does; below it, nothing is
/// promised.
///
/// ↩️Each of these rows was a `Row`, which lays a child that does not flex
/// out with all the width there is: a tail wider than the row was laid out
/// wider, and ran off it (the timeline's bar in a 360px window, a panel's
/// tab strip at 340, the top strip at 320 — measured 2026-10-14 · 15).
///
/// ⚠️Laid out by a render object, not a [LayoutBuilder], for the transport's
/// play row's reason (`_PlayRowLayout`): the row is sized while it is laid
/// out, so nothing is built again to learn a width. ↩️A layout delegate did
/// it while there was one end to keep; two ends shown by one factor need
/// both their widths before either is placed, and a delegate lays a child
/// out once.
class KeptTailRow extends StatelessWidget {
  const KeptTailRow({
    super.key,
    this.lead,
    this.head,
    required this.tail,
    this.gap = 0,
    this.headKeeps = 0,
  });

  /// Kept at the row's start as the [tail] is at its end. Null leaves the
  /// head the row's start.
  final Widget? lead;

  /// What takes the room the kept ends leave — exactly that room. Null
  /// leaves the row's middle empty and still pins the tail to its end.
  final Widget? head;

  final Widget tail;

  /// Between each piece and the next.
  final double gap;

  /// The least the [head] is left, where there is a head.
  final double headKeeps;

  @override
  Widget build(BuildContext context) => _KeptEnds(
    lead: lead,
    head: head,
    tail: tail,
    gap: gap,
    headKeeps: headKeeps,
  );
}

enum _Part { lead, head, tail }

class _KeptEnds extends SlottedMultiChildRenderObjectWidget<_Part, RenderBox> {
  const _KeptEnds({
    required this.lead,
    required this.head,
    required this.tail,
    required this.gap,
    required this.headKeeps,
  });

  final Widget? lead;
  final Widget? head;
  final Widget tail;
  final double gap;
  final double headKeeps;

  @override
  Iterable<_Part> get slots => _Part.values;

  @override
  Widget? childForSlot(_Part slot) => switch (slot) {
    _Part.lead => lead,
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

class _RenderKeptEnds extends RenderBox
    with SlottedContainerRenderObjectMixin<_Part, RenderBox> {
  _RenderKeptEnds({required double gap, required double headKeeps})
    : _gap = gap,
      _headKeeps = headKeeps;

  double _gap;
  double get gap => _gap;
  set gap(double value) {
    if (value != _gap) {
      _gap = value;
      markNeedsLayout();
    }
  }

  double _headKeeps;
  double get headKeeps => _headKeeps;
  set headKeeps(double value) {
    if (value != _headKeeps) {
      _headKeeps = value;
      markNeedsLayout();
    }
  }

  /// What each kept end is shown at — 1 where the row holds it.
  final Map<_Part, double> _scales = {};

  final Map<_Part, LayerHandle<TransformLayer>> _layers = {
    _Part.lead: LayerHandle<TransformLayer>(),
    _Part.tail: LayerHandle<TransformLayer>(),
  };

  RenderBox? get _lead => childForSlot(_Part.lead);
  RenderBox? get _head => childForSlot(_Part.head);
  RenderBox get _tail => childForSlot(_Part.tail)!;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.biggest;

  @override
  void performLayout() {
    size = constraints.biggest;
    final lead = _lead;
    final head = _head;
    final tail = _tail;
    // A kept end is laid out at its own size, as a scaling box lays its
    // child, and shown smaller where the row cannot hold it.
    lead?.layout(const BoxConstraints(), parentUsesSize: true);
    tail.layout(const BoxConstraints(), parentUsesSize: true);
    final pieces = [lead, head, tail].nonNulls.length;
    final gaps = _gap * (pieces - 1);
    final room = math.max(
      0.0,
      size.width - gaps - (head == null ? 0 : _headKeeps),
    );
    final kept = (lead?.size.width ?? 0) + tail.size.width;
    final byWidth = kept > room ? room / kept : 1.0;
    var shownLead = 0.0;
    if (lead != null) {
      shownLead = _place(_Part.lead, lead, byWidth, atStart: true);
    }
    final shownTail = _place(_Part.tail, tail, byWidth, atStart: false);
    if (head == null) {
      return;
    }
    final before = lead == null ? 0.0 : shownLead + _gap;
    final width = math.max(0.0, size.width - before - shownTail - _gap);
    head.layout(
      BoxConstraints(minWidth: width, maxWidth: width, maxHeight: size.height),
      parentUsesSize: true,
    );
    _offsetOf(head).offset = Offset(
      before,
      (size.height - head.size.height) / 2,
    );
  }

  /// Puts a kept end at its edge of the row, shown at [byWidth] or less —
  /// what the row's height lets it be — and answers the width it is shown.
  double _place(
    _Part part,
    RenderBox child,
    double byWidth, {
    required bool atStart,
  }) {
    final own = child.size;
    final byHeight = own.height > size.height ? size.height / own.height : 1.0;
    final scale = math.min(byWidth, byHeight);
    _scales[part] = scale;
    final shown = own * scale;
    _offsetOf(child).offset = Offset(
      atStart ? 0 : size.width - shown.width,
      (size.height - shown.height) / 2,
    );
    return shown.width;
  }

  BoxParentData _offsetOf(RenderBox child) =>
      child.parentData! as BoxParentData;

  /// Where [child] is painted from — its offset, and its scale if it is a
  /// kept end shown smaller.
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
      final layer = _layers[part];
      if (scale == 1 || layer == null) {
        layer?.layer = null;
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
