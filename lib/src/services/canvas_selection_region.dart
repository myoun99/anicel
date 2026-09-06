import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/app_language.dart';
import '../models/canvas_point.dart';
import 'canvas_selection_shape.dart';

/// How a freshly drawn marquee/lasso combines with the region already
/// selected (R26 #16 — CSP's four selection modes; 유저 원문
/// "갱신/추가/삭제/선택중", 기본값 = 추가).
///
/// [replace] 갱신 · [add] 추가 · [subtract] 삭제 · [intersect] 선택중
/// (the intersection — "선택 중에서 다시 고른다").
enum SelectionCombineMode {
  replace,
  add,
  subtract,
  intersect;

  /// The default the user asked for: a new drag ADDS to what is already
  /// selected instead of throwing it away.
  static const SelectionCombineMode defaultMode = SelectionCombineMode.add;

  String get label => switch (this) {
    replace => 'Replace',
    add => 'Add',
    subtract => 'Subtract',
    intersect => 'Intersect',
  };

  /// The label in the program language. ja follows the PS/CSP Japanese
  /// terms and ko the user's own words (the same rule the brush blend
  /// labels follow); other languages keep the shared English vocabulary.
  String labelFor(AppLanguage language) => switch (language) {
    AppLanguage.ja => switch (this) {
      replace => '新規選択',
      add => '追加選択',
      subtract => '部分解除',
      intersect => '選択中',
    },
    AppLanguage.ko => switch (this) {
      replace => '갱신',
      add => '추가',
      subtract => '삭제',
      intersect => '선택중',
    },
    _ => label,
  };

  String toJson() => name;

  static SelectionCombineMode fromJson(Object? value) =>
      SelectionCombineMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => SelectionCombineMode.defaultMode,
      );
}

/// One (polygon, operation) step of a composite selection.
///
/// Usually ONE polygon. A symmetry guide makes a single drag draw several,
/// and those copies are one step rather than several: they are one act, so
/// the mode applies to them TOGETHER (their union), undo takes them back
/// together, and every reader folds them as a unit.
///
/// 🚨That union is the whole reason the field is a list. Folding the copies
/// as separate steps gives the right answer for replace/add/subtract and the
/// WRONG one for intersect — narrowing to copy A and then to copy B leaves
/// their overlap, which for a plain left/right mirror is nothing at all. The
/// step list is linear and cannot nest, so "∩ (A ∪ B)" has nowhere else to
/// live.
class CanvasSelectionStep {
  CanvasSelectionStep(CanvasSelectionShape shape, this.mode)
    : shapes = List<CanvasSelectionShape>.unmodifiable([shape]);

  /// The copies one guided act drew, folded as their union.
  CanvasSelectionStep.copies(List<CanvasSelectionShape> shapes, this.mode)
    : shapes = List<CanvasSelectionShape>.unmodifiable(shapes),
      assert(shapes.isNotEmpty, 'a step needs at least one polygon');

  final List<CanvasSelectionShape> shapes;
  final SelectionCombineMode mode;

  CanvasSelectionStep mapped(CanvasPoint Function(CanvasPoint) map) =>
      CanvasSelectionStep.copies([
        for (final shape in shapes)
          CanvasSelectionShape([for (final point in shape.points) map(point)]),
      ], mode);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! CanvasSelectionStep ||
        other.mode != mode ||
        other.shapes.length != shapes.length) {
      return false;
    }
    for (var i = 0; i < shapes.length; i += 1) {
      if (other.shapes[i] != shapes[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(shapes), mode);
}

/// A composite selection region: an ordered list of (polygon, operation)
/// STEPS folded left to right (R26 #16).
///
/// The single polygon of the P9 model is the one-step case, so every old
/// behaviour survives untouched; the four modes simply append a step.
/// Membership is the fold — `add` unions, `subtract` cuts, `intersect`
/// keeps only the overlap — and every consumer (hit test, lift mask,
/// marching ants, transforms) reads the SAME fold, so what the ants draw
/// is exactly what lifts.
///
/// Empty regions do not exist: a combination that selects nothing returns
/// null from [combinedWith], which is the app's "no selection" state.
class CanvasSelectionRegion {
  CanvasSelectionRegion(List<CanvasSelectionStep> steps)
    : steps = List<CanvasSelectionStep>.unmodifiable(steps),
      assert(steps.isNotEmpty, 'a region needs at least one step'),
      assert(
        steps.first.mode == SelectionCombineMode.replace,
        'the first step always REPLACES (nothing precedes it)',
      );

  /// The plain single-polygon region (the P9 shape model).
  factory CanvasSelectionRegion.shape(CanvasSelectionShape shape) =>
      CanvasSelectionRegion([
        CanvasSelectionStep(shape, SelectionCombineMode.replace),
      ]);

  final List<CanvasSelectionStep> steps;

  /// The single polygon when this region IS one (the transform/lift paths
  /// that predate the composite model still read it); null otherwise.
  CanvasSelectionShape? get singleShape =>
      steps.length == 1 && steps.first.shapes.length == 1
      ? steps.first.shapes.first
      : null;

  /// Folds [shape] into the region under [mode]. Null result = nothing is
  /// selected any more (subtract/intersect can empty a region, and
  /// subtract/intersect from NOTHING stays nothing).
  static CanvasSelectionRegion? combine(
    CanvasSelectionRegion? region,
    CanvasSelectionShape? shape,
    SelectionCombineMode mode,
  ) => combineCopies(
    region,
    shape == null ? const <CanvasSelectionShape>[] : [shape],
    mode,
  );

  /// [combine] for an outline a guide copied — the copies fold as ONE step.
  ///
  /// One path, not two: the plain drag is the one-copy case, so a mode can
  /// never behave differently depending on whether a guide was on.
  static CanvasSelectionRegion? combineCopies(
    CanvasSelectionRegion? region,
    List<CanvasSelectionShape> shapes,
    SelectionCombineMode mode,
  ) {
    if (shapes.isEmpty) {
      // A degenerate drag (a click): REPLACE deselects — Photoshop's
      // click-away — while the other modes leave the region alone.
      return mode == SelectionCombineMode.replace ? null : region;
    }
    switch (mode) {
      case SelectionCombineMode.replace:
        return CanvasSelectionRegion([
          CanvasSelectionStep.copies(shapes, SelectionCombineMode.replace),
        ]);
      case SelectionCombineMode.add:
        if (region == null) {
          return CanvasSelectionRegion([
            CanvasSelectionStep.copies(shapes, SelectionCombineMode.replace),
          ]);
        }
        return CanvasSelectionRegion([
          ...region.steps,
          CanvasSelectionStep.copies(shapes, SelectionCombineMode.add),
        ]);
      case SelectionCombineMode.subtract:
      case SelectionCombineMode.intersect:
        if (region == null) {
          return null;
        }
        return CanvasSelectionRegion([
          ...region.steps,
          CanvasSelectionStep.copies(shapes, mode),
        ]);
    }
  }

  CanvasSelectionRegion? combinedWith(
    CanvasSelectionShape? shape,
    SelectionCombineMode mode,
  ) => combine(this, shape, mode);

  /// Even-odd membership through the fold.
  bool containsPoint(CanvasPoint point) {
    var inside = false;
    for (final step in steps) {
      // The copies of one act are a UNION, so any of them is a hit.
      var hit = false;
      for (final shape in step.shapes) {
        if (shape.containsPoint(point)) {
          hit = true;
          break;
        }
      }
      inside = switch (step.mode) {
        SelectionCombineMode.replace => hit,
        SelectionCombineMode.add => inside || hit,
        SelectionCombineMode.subtract => inside && !hit,
        SelectionCombineMode.intersect => inside && hit,
      };
    }
    return inside;
  }

  /// The bounding box of every step that can ADD coverage (replace/add) —
  /// a correct superset, since subtract and intersect only shrink.
  ///
  /// This answers "what must I COVER": a lift mask, a stroke clip and a
  /// piece rasterizer each allocate for every pixel a step could have
  /// added, so a subtraction must not shrink the box they work over (the
  /// fold then zeroes what is outside). What the user SEES asks the other
  /// question — [selectedBounds].
  ({double left, double top, double right, double bottom}) get coverageBounds {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final step in steps) {
      if (step.mode == SelectionCombineMode.subtract ||
          step.mode == SelectionCombineMode.intersect) {
        continue;
      }
      for (final shape in step.shapes) {
        for (final point in shape.points) {
          minX = math.min(minX, point.x);
          minY = math.min(minY, point.y);
          maxX = math.max(maxX, point.x);
          maxY = math.max(maxY, point.y);
        }
      }
    }
    // An intersect-only tail cannot happen (the first step replaces), so
    // the loop always saw at least one polygon.
    return (left: minX, top: minY, right: maxX, bottom: maxY);
  }

  ({double left, double top, double right, double bottom})? _selectedBounds;

  /// The tight box around what is ACTUALLY selected — the fold, with
  /// subtract and intersect applied.
  ///
  /// This answers "where IS the selection", which is the question every
  /// piece of chrome asks: the always-on transform box, the pivot it
  /// scales and rotates around, the confirm anchor. They must frame what
  /// the marching ants trace, and the ants trace [pathIn]'s fold — so the
  /// box is measured off that same path rather than off a second opinion.
  ///
  /// 유저 실기 ㉝ was exactly the two answers drifting apart: subtracting
  /// the right half shrank the ants but left the move box on the
  /// pre-subtraction rect, because chrome read the coverage superset.
  ///
  /// A fold that selects nothing has no box to draw at all, so it keeps
  /// [coverageBounds] rather than collapsing the chrome onto the origin.
  ({double left, double top, double right, double bottom}) get selectedBounds =>
      _selectedBounds ??= _computeSelectedBounds();

  ({double left, double top, double right, double bottom})
  _computeSelectedBounds() {
    final coverage = coverageBounds;
    // Nothing here ever removes coverage ⇒ the superset IS tight, and the
    // path booleans below would only spend time agreeing with it. This is
    // the overwhelming case (one replace step).
    final shrinks = steps.any(
      (step) =>
          step.mode == SelectionCombineMode.subtract ||
          step.mode == SelectionCombineMode.intersect,
    );
    if (!shrinks) {
      return coverage;
    }
    final folded = pathIn((point) => ui.Offset(point.x, point.y)).getBounds();
    if (folded.isEmpty) {
      return coverage;
    }
    return (
      left: folded.left,
      top: folded.top,
      right: folded.right,
      bottom: folded.bottom,
    );
  }

  CanvasSelectionRegion mapped(CanvasPoint Function(CanvasPoint) map) =>
      CanvasSelectionRegion([for (final step in steps) step.mapped(map)]);

  CanvasSelectionRegion translated({required double dx, required double dy}) =>
      mapped((point) => CanvasPoint(x: point.x + dx, y: point.y + dy));

  /// The region as ONE path in an arbitrary (usually viewport) space, for
  /// the marching ants and for display clips. Path booleans are exact for
  /// rendering; the MODEL still folds polygons, so the ants and the lift
  /// mask never disagree about membership.
  ui.Path pathIn(ui.Offset Function(CanvasPoint) map) {
    var combined = ui.Path();
    for (final step in steps) {
      var polygon = ui.Path()
        ..fillType = ui.PathFillType.evenOdd
        ..addPolygon([
          for (final point in step.shapes.first.points) map(point),
        ], true);
      // Copies UNION into the step's own outline before the mode applies —
      // one `addPolygon` per copy would even-odd them and punch a hole
      // wherever two copies overlap.
      for (final shape in step.shapes.skip(1)) {
        polygon = ui.Path.combine(
          ui.PathOperation.union,
          polygon,
          ui.Path()
            ..fillType = ui.PathFillType.evenOdd
            ..addPolygon([for (final point in shape.points) map(point)], true),
        );
      }
      combined = switch (step.mode) {
        SelectionCombineMode.replace => polygon,
        SelectionCombineMode.add => ui.Path.combine(
          ui.PathOperation.union,
          combined,
          polygon,
        ),
        SelectionCombineMode.subtract => ui.Path.combine(
          ui.PathOperation.difference,
          combined,
          polygon,
        ),
        SelectionCombineMode.intersect => ui.Path.combine(
          ui.PathOperation.intersect,
          combined,
          polygon,
        ),
      };
    }
    return combined;
  }

  /// 🚨★★★THE COMMITTED OUTLINE, ON THE PIXEL GRID (F-65).
  ///
  /// 유저: 「라이브로 선택중일땐 선이 픽셀에 안착안된 벡터로 보여도 상관없는데,
  /// **선택 커밋될떈 픽셀에 제대로 안착한 상태로**. 지금은 **변형되는 픽셀
  /// 범위와 개미행렬 위치가 다르다**」.
  ///
  /// ⛔[pathIn] traces the POLYGON — where the drag went. Membership is by
  /// pixel CENTRE ([maskFor] scans `y + 0.5`). The two agree about which
  /// pixels are in and disagree about where the line is, and past 1:1 that
  /// gap is the whole complaint. This walks the boundary of the pixels
  /// themselves, so the ants sit on the edges of what will actually move.
  ///
  /// ★It reads [maskFor] rather than re-deriving the fold: 「어느 픽셀이
  /// 들어오나」 already has an answer, and a second one written next to it
  /// would be a rule that can drift. ⚠️That costs one byte per pixel of the
  /// selected box for the length of this call — the same allocation a lift
  /// makes — so callers cache the result rather than asking per frame.
  ///
  /// The contours are CLOSED and walk consistently, so a dash phase runs
  /// around a whole component (and around a hole) exactly as it did around
  /// [pathIn]'s contours.
  ui.Path pixelOutlineIn(ui.Offset Function(CanvasPoint) map) {
    final path = ui.Path();
    for (final contour in _pixelContours) {
      path.addPolygon([for (final point in contour) map(point)], true);
    }
    return path;
  }

  List<List<CanvasPoint>>? _pixelContoursCache;

  /// The closed contours of [pixelOutlineIn], in CANVAS space.
  ///
  /// ⚠️Memoised, and that is not an optimisation but the condition of
  /// calling it from a painter at all: the walk allocates a mask over the
  /// selected box and reads every byte of it, while the ants repaint on
  /// every animation tick. A region is immutable, so this can never go
  /// stale — the same reasoning `layerContentBoundsAt` states for its own
  /// memo, one field over.
  ///
  /// ⛔On the REGION rather than in the painter: the painter is rebuilt per
  /// tick and there is more than one of them on screen (the selection layer
  /// and the panel's idle outline), so a cache living there would either
  /// vanish every frame or be a global two painters take turns evicting.
  List<List<CanvasPoint>> get _pixelContours =>
      _pixelContoursCache ??= _walkPixelContours();

  /// The contours [pixelOutlineIn] draws, for the test that pins how many
  /// POINTS they hold — the straight-run merge is invisible in the shape
  /// and only shows up in the count, so nothing else can measure it.
  @visibleForTesting
  List<List<CanvasPoint>> get pixelOutlineContours => _pixelContours;

  List<List<CanvasPoint>> _walkPixelContours() {
    final contours = <List<CanvasPoint>>[];
    final bounds = selectedBounds;
    // The pixel box: every pixel whose CENTRE can be inside. A box smaller
    // than that would clip the outline; a bigger one only costs bytes.
    final left = (bounds.left - 0.5).floor();
    final top = (bounds.top - 0.5).floor();
    final width = (bounds.right + 0.5).ceil() - left;
    final height = (bounds.bottom + 0.5).ceil() - top;
    if (width <= 0 || height <= 0) {
      return contours;
    }
    final mask = maskFor(left: left, top: top, width: width, height: height);
    bool inside(int x, int y) =>
        x >= 0 && y >= 0 && x < width && y < height && mask[y * width + x] != 0;

    // Every boundary edge, wound so that the selected side is on the same
    // hand throughout: a component runs one way and a hole the other, which
    // is what makes the even-odd fill below carve rather than cover.
    final edges = <int, List<int>>{};
    int vertex(int x, int y) => y * (width + 1) + x;
    void edge(int x0, int y0, int x1, int y1) {
      edges.putIfAbsent(vertex(x0, y0), () => <int>[]).add(vertex(x1, y1));
    }

    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        if (!inside(x, y)) {
          continue;
        }
        if (!inside(x, y - 1)) edge(x, y, x + 1, y);
        if (!inside(x + 1, y)) edge(x + 1, y, x + 1, y + 1);
        if (!inside(x, y + 1)) edge(x + 1, y + 1, x, y + 1);
        if (!inside(x - 1, y)) edge(x, y + 1, x, y);
      }
    }

    CanvasPoint at(int v) => CanvasPoint(
      x: (left + v % (width + 1)).toDouble(),
      y: (top + v ~/ (width + 1)).toDouble(),
    );

    while (edges.isNotEmpty) {
      final start = edges.keys.first;
      var current = start;
      final contour = <CanvasPoint>[at(start)];
      // ⚠️STRAIGHT RUNS COLLAPSE. The walk emits one vertex per pixel edge,
      // so a plain rectangle would arrive as four thousand-point sides and
      // be rebuilt into a `Path` on every animation tick. Merging while
      // walking makes an axis-aligned outline four points again; a true
      // staircase (a rotated or lassoed edge) keeps its steps, because
      // those steps ARE the answer.
      var lastDx = 0;
      var lastDy = 0;
      // ⚠️Bounded by the edge count rather than trusted to close: a
      // malformed walk must end, not hang the paint thread.
      var guard = edges.length * 4 + 8;
      while (guard-- > 0) {
        final outgoing = edges[current];
        if (outgoing == null || outgoing.isEmpty) {
          break;
        }
        final next = outgoing.removeLast();
        if (outgoing.isEmpty) {
          edges.remove(current);
        }
        if (next == start) {
          break;
        }
        final dx = next % (width + 1) - current % (width + 1);
        final dy = next ~/ (width + 1) - current ~/ (width + 1);
        if (dx == lastDx && dy == lastDy && contour.length > 1) {
          contour[contour.length - 1] = at(next);
        } else {
          contour.add(at(next));
        }
        lastDx = dx;
        lastDy = dy;
        current = next;
      }
      // ⚠️And once more AROUND the join. The walk starts wherever the edge
      // map happened to hand it a vertex, which is usually the middle of a
      // straight run, and the segment that closes the contour is implied
      // rather than stepped — so the first and last points can each sit in
      // the middle of a line the merge above never saw the two halves of.
      // 🧪Without this a rectangle came back with five corners.
      while (contour.length > 3 &&
          _isStraight(
            contour[contour.length - 2],
            contour.last,
            contour.first,
          )) {
        contour.removeLast();
      }
      while (contour.length > 3 &&
          _isStraight(contour.last, contour.first, contour[1])) {
        contour.removeAt(0);
      }
      contours.add(contour);
    }
    return contours;
  }

  /// The hard coverage mask over the pixel box `[left, left+width) ×
  /// [top, top+height)`: 255 inside, 0 outside, by PIXEL CENTRE — the
  /// same even-odd rule as [containsPoint], so a lift never disagrees
  /// with a hit test.
  ///
  /// Per row the crossings of each step polygon become spans, and the
  /// step's operation is applied to the row: `add` fills, `subtract`
  /// clears, `intersect` clears everything OUTSIDE the spans. Single-step
  /// regions (the overwhelming case) take the plain span-fill path.
  Uint8List maskFor({
    required int left,
    required int top,
    required int width,
    required int height,
  }) {
    final mask = Uint8List(width * height);
    final crossings = <double>[];
    final scratch = <double>[];
    for (var row = 0; row < height; row += 1) {
      final scanY = top + row + 0.5;
      final rowOffset = row * width;
      for (final step in steps) {
        _scanSpans(step.shapes, scanY, crossings, scratch);
        switch (step.mode) {
          case SelectionCombineMode.replace:
            mask.fillRange(rowOffset, rowOffset + width, 0);
            _fillSpans(mask, rowOffset, left, width, crossings, 255);
          case SelectionCombineMode.add:
            _fillSpans(mask, rowOffset, left, width, crossings, 255);
          case SelectionCombineMode.subtract:
            _fillSpans(mask, rowOffset, left, width, crossings, 0);
          case SelectionCombineMode.intersect:
            _clearOutsideSpans(mask, rowOffset, left, width, crossings);
        }
      }
    }
    return mask;
  }

  /// Whether [b] sits on the straight line from [a] to [c] — the test the
  /// contour merge asks at a join. Axis-aligned steps only, which is all a
  /// pixel boundary ever has.
  static bool _isStraight(CanvasPoint a, CanvasPoint b, CanvasPoint c) =>
      (b.x - a.x) * (c.y - b.y) == (b.y - a.y) * (c.x - b.x);

  /// The row's inside spans for one step: the union of its copies, as a flat
  /// sorted `[start, end, …]` list with overlaps merged.
  ///
  /// 🚨Merging SPANS, not crossings. Concatenating two polygons' crossings
  /// and pairing them off is the even-odd rule, which cancels where the
  /// copies overlap — the lift would then punch a hole exactly where
  /// [containsPoint] says the point is in. One copy (nearly every region)
  /// returns the crossings untouched.
  static void _scanSpans(
    List<CanvasSelectionShape> shapes,
    double scanY,
    List<double> out,
    List<double> scratch,
  ) {
    _scanCrossings(shapes.first, scanY, out);
    for (final shape in shapes.skip(1)) {
      _scanCrossings(shape, scanY, scratch);
      _mergeSpans(out, scratch);
    }
  }

  /// `into ∪ extra`, both flat sorted span lists, left merged in [into].
  static void _mergeSpans(List<double> into, List<double> extra) {
    if (extra.isEmpty) {
      return;
    }
    if (into.isEmpty) {
      into.addAll(extra);
      return;
    }
    final merged = <double>[];
    var a = 0;
    var b = 0;
    while (a < into.length || b < extra.length) {
      final takeA =
          b >= extra.length || (a < into.length && into[a] <= extra[b]);
      final start = takeA ? into[a] : extra[b];
      final end = takeA ? into[a + 1] : extra[b + 1];
      if (takeA) {
        a += 2;
      } else {
        b += 2;
      }
      if (merged.isNotEmpty && start <= merged[merged.length - 1]) {
        if (end > merged[merged.length - 1]) {
          merged[merged.length - 1] = end;
        }
        continue;
      }
      merged
        ..add(start)
        ..add(end);
    }
    into
      ..clear()
      ..addAll(merged);
  }

  /// Sorted x crossings of [shape]'s edges at the scanline [scanY].
  static void _scanCrossings(
    CanvasSelectionShape shape,
    double scanY,
    List<double> out,
  ) {
    out.clear();
    final points = shape.points;
    for (var i = 0, j = points.length - 1; i < points.length; j = i, i += 1) {
      final a = points[i];
      final b = points[j];
      if (CanvasSelectionShape.edgeStraddles(a, b, scanY)) {
        out.add(CanvasSelectionShape.edgeCrossingX(a, b, scanY));
      }
    }
    out.sort();
  }

  /// Pixel centres strictly inside `[start, end)` — `x + 0.5 > crossing`,
  /// the same strictness as `containsPoint`'s `point.x < intersection`.
  static void _fillSpans(
    Uint8List mask,
    int rowOffset,
    int left,
    int width,
    List<double> crossings,
    int value,
  ) {
    for (var c = 0; c + 1 < crossings.length; c += 2) {
      final start = math.max((crossings[c] - 0.5).ceil() - left, 0);
      final end = math.min((crossings[c + 1] - 0.5).ceil() - left, width);
      for (var x = start; x < end; x += 1) {
        mask[rowOffset + x] = value;
      }
    }
  }

  /// 🚨Both ends clamp into `[0, width]`, not one end each. A span that lies
  /// entirely to the RIGHT of the window gives `start > width`, and the
  /// fill below then runs off the end of the row — [_fillSpans] survives
  /// that (its loop simply does not run) but this one calls `fillRange`.
  /// The 1×1 probe a mask/hit-test parity check uses is exactly the window
  /// small enough to reach it.
  static void _clearOutsideSpans(
    Uint8List mask,
    int rowOffset,
    int left,
    int width,
    List<double> crossings,
  ) {
    var cursor = 0;
    for (var c = 0; c + 1 < crossings.length; c += 2) {
      final start = math.min(
        math.max((crossings[c] - 0.5).ceil() - left, 0),
        width,
      );
      final end = math.min(
        math.max((crossings[c + 1] - 0.5).ceil() - left, 0),
        width,
      );
      if (start > cursor) {
        mask.fillRange(rowOffset + cursor, rowOffset + start, 0);
      }
      cursor = math.max(cursor, end);
    }
    if (cursor < width) {
      mask.fillRange(rowOffset + cursor, rowOffset + width, 0);
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! CanvasSelectionRegion || other.steps.length != steps.length) {
      return false;
    }
    for (var i = 0; i < steps.length; i += 1) {
      if (other.steps[i] != steps[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(steps);

  @override
  String toString() =>
      'CanvasSelectionRegion(${steps.map((step) => '${step.mode.name}:'
          '${step.shapes.map((shape) => '${shape.points.length}pts')
          .join('+')}').join(' → ')})';
}
