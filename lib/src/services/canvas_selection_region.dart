import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/app_language.dart';
import '../models/canvas_point.dart';
import 'canvas_selection.dart';

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
class CanvasSelectionStep {
  const CanvasSelectionStep(this.shape, this.mode);

  final CanvasSelectionShape shape;
  final SelectionCombineMode mode;

  CanvasSelectionStep mapped(CanvasPoint Function(CanvasPoint) map) =>
      CanvasSelectionStep(
        CanvasSelectionShape([for (final point in shape.points) map(point)]),
        mode,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CanvasSelectionStep && other.shape == shape && other.mode == mode;

  @override
  int get hashCode => Object.hash(shape, mode);
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
      steps.length == 1 ? steps.first.shape : null;

  /// Folds [shape] into the region under [mode]. Null result = nothing is
  /// selected any more (subtract/intersect can empty a region, and
  /// subtract/intersect from NOTHING stays nothing).
  static CanvasSelectionRegion? combine(
    CanvasSelectionRegion? region,
    CanvasSelectionShape? shape,
    SelectionCombineMode mode,
  ) {
    if (shape == null) {
      // A degenerate drag (a click): REPLACE deselects — Photoshop's
      // click-away — while the other modes leave the region alone.
      return mode == SelectionCombineMode.replace ? null : region;
    }
    switch (mode) {
      case SelectionCombineMode.replace:
        return CanvasSelectionRegion.shape(shape);
      case SelectionCombineMode.add:
        if (region == null) {
          return CanvasSelectionRegion.shape(shape);
        }
        return CanvasSelectionRegion([
          ...region.steps,
          CanvasSelectionStep(shape, SelectionCombineMode.add),
        ]);
      case SelectionCombineMode.subtract:
      case SelectionCombineMode.intersect:
        if (region == null) {
          return null;
        }
        return CanvasSelectionRegion([
          ...region.steps,
          CanvasSelectionStep(shape, mode),
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
      final hit = step.shape.containsPoint(point);
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
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final step in steps) {
      if (step.mode == SelectionCombineMode.subtract ||
          step.mode == SelectionCombineMode.intersect) {
        continue;
      }
      for (final point in step.shape.points) {
        minX = math.min(minX, point.x);
        minY = math.min(minY, point.y);
        maxX = math.max(maxX, point.x);
        maxY = math.max(maxY, point.y);
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
      final polygon = ui.Path()
        ..fillType = ui.PathFillType.evenOdd
        ..addPolygon([for (final point in step.shape.points) map(point)], true);
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
    for (var row = 0; row < height; row += 1) {
      final scanY = top + row + 0.5;
      final rowOffset = row * width;
      for (final step in steps) {
        _scanCrossings(step.shape, scanY, crossings);
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
      if ((a.y > scanY) != (b.y > scanY)) {
        out.add((b.x - a.x) * (scanY - a.y) / (b.y - a.y) + a.x);
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

  static void _clearOutsideSpans(
    Uint8List mask,
    int rowOffset,
    int left,
    int width,
    List<double> crossings,
  ) {
    var cursor = 0;
    for (var c = 0; c + 1 < crossings.length; c += 2) {
      final start = math.max((crossings[c] - 0.5).ceil() - left, 0);
      final end = math.min((crossings[c + 1] - 0.5).ceil() - left, width);
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
          '${step.shape.points.length}pts').join(' → ')})';
}
