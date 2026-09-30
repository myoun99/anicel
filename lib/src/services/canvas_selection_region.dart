import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core/point_bounds.dart';
import '../models/canvas_point.dart';
import '../models/dirty_region.dart';
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

  /// The English label.
  ///
  /// ja followed the PS/CSP Japanese terms and ko the user's own words (the
  /// same rule the brush blend labels follow); other languages keep the
  /// shared English vocabulary. ↩️Every language has its own words now
  /// (유저 2026-09-15, blend-mode-names-language-Q1: 「블렌드 모드도 모든
  /// 언어로 번역」), keyed by `name` in the string tables — the ko rows are
  /// still the user's words — through `SelectionCombineModeWords` in
  /// `ui/text/model_vocabulary.dart`, which a service cannot import.
  String get label => switch (this) {
    replace => 'Replace',
    add => 'Add',
    subtract => 'Subtract',
    intersect => 'Intersect',
  };

  String toJson() => name;

  static SelectionCombineMode fromJson(Object? value) =>
      SelectionCombineMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => SelectionCombineMode.defaultMode,
      );

  /// Whether a step under this mode can only take coverage AWAY — 삭제
  /// cuts and 선택중 narrows. 갱신 and 추가 are the two that can add.
  bool get _onlyRemoves => this == subtract || this == intersect;

  /// Membership through one step: [inside] is the fold so far, [hit] the
  /// operand's own answer.
  ///
  /// ⛔THE ONE TABLE. The point test folds by it and so does the row sweep
  /// the mask and the ants read ([_combineSpans]), so a mode cannot mean one
  /// thing to the hit test and another to the lift.
  bool _fold(bool inside, bool hit) => switch (this) {
    replace => hit,
    add => inside || hit,
    subtract => inside && !hit,
    intersect => inside && hit,
  };
}

/// One step of a composite selection: an OPERAND folded in under a [mode].
///
/// The operand is usually ONE polygon ([CanvasSelectionCopies]). A symmetry
/// guide makes a single drag draw several, and those copies are one step
/// rather than several: they are one act, so the mode applies to them
/// TOGETHER (their union), undo takes them back together, and every reader
/// folds them as a unit.
///
/// 🚨That union is the whole reason a step can hold a list. Folding the
/// copies as separate steps gives the right answer for replace/add/subtract
/// and the WRONG one for intersect — narrowing to copy A and then to copy B
/// leaves their overlap, which for a plain left/right mirror is nothing at
/// all. "∩ (A ∪ B)" has to be one step or it cannot be said.
///
/// ↩️The step list could not nest when that was written, so the union had
/// nowhere else to live. It can now: an operand may be a whole selection
/// ([CanvasSelectionNested], I-23's inverse). The copies stay a list all the
/// same — they are one act, which a nested selection is not.
///
/// ⛔Every reader asks the OPERAND, never its kind: the hit, the row's spans,
/// the path and the coverage are each subtype's to answer, and the fold over
/// them is written once, in [CanvasSelectionRegion].
sealed class CanvasSelectionStep {
  /// One polygon.
  factory CanvasSelectionStep(
    CanvasSelectionShape shape,
    SelectionCombineMode mode,
  ) => CanvasSelectionCopies([shape], mode);

  CanvasSelectionStep._(this.mode);

  /// The copies one guided act drew, folded as their union.
  factory CanvasSelectionStep.copies(
    List<CanvasSelectionShape> shapes,
    SelectionCombineMode mode,
  ) = CanvasSelectionCopies;

  /// A whole selection folded in as ONE operand.
  factory CanvasSelectionStep.region(
    CanvasSelectionRegion region,
    SelectionCombineMode mode,
  ) = CanvasSelectionNested;

  final SelectionCombineMode mode;

  /// Whether [point] is inside the operand — before [mode] applies.
  bool hits(CanvasPoint point);

  /// The operand's inside spans on the scanline at [scanY]: a flat sorted
  /// `[start, end, …]` list whose spans may touch or be empty, the shape
  /// [_combineSpans] reads.
  List<double> _spansOn(double scanY);

  /// The operand as ONE path in [map]'s space.
  ui.Path _pathIn(ui.Offset Function(CanvasPoint) map);

  /// Points whose box holds everything the operand can select.
  Iterable<ui.Offset> get _coverage;

  /// Whether folding this step can leave less than the coverage box says:
  /// a mode that takes coverage away, or an operand whose own box is only a
  /// superset of what it selects.
  bool get _shrinksFold;

  /// The operand when it IS one polygon; null otherwise.
  CanvasSelectionShape? get _loneShape;

  CanvasSelectionStep mapped(CanvasPoint Function(CanvasPoint) map);

  /// The operand cut at [wall], as a step under [mode] — null when nothing
  /// of it is left inside ([CanvasSelectionRegion.clippedTo] reads that as
  /// the empty set).
  CanvasSelectionStep? _clippedTo(ui.Rect wall, SelectionCombineMode mode);
}

/// The polygons ONE act drew — usually one, several under a symmetry guide
/// (see [CanvasSelectionStep] for why they are one step) — folded as their
/// union.
final class CanvasSelectionCopies extends CanvasSelectionStep {
  CanvasSelectionCopies(List<CanvasSelectionShape> shapes, super.mode)
    : shapes = List<CanvasSelectionShape>.unmodifiable(shapes),
      assert(shapes.isNotEmpty, 'a step needs at least one polygon'),
      super._();

  final List<CanvasSelectionShape> shapes;

  /// The copies of one act are a UNION, so any of them is a hit.
  @override
  bool hits(CanvasPoint point) =>
      shapes.any((shape) => shape.containsPoint(point));

  /// 🚨Merging SPANS, not crossings. Concatenating two polygons' crossings
  /// and pairing them off is the even-odd rule, which cancels where the
  /// copies overlap — the lift would then punch a hole exactly where [hits]
  /// says the point is in. One copy (nearly every region) hands back its
  /// crossings untouched.
  @override
  List<double> _spansOn(double scanY) {
    var union = _crossingsOn(shapes.first, scanY);
    for (final shape in shapes.skip(1)) {
      union = _combineSpans(
        union,
        _crossingsOn(shape, scanY),
        SelectionCombineMode.add,
      );
    }
    return union;
  }

  /// Copies UNION into one outline before the mode applies — one
  /// `addPolygon` per copy would even-odd them and punch a hole wherever
  /// two copies overlap.
  @override
  ui.Path _pathIn(ui.Offset Function(CanvasPoint) map) {
    var union = _polygonPath(shapes.first, map);
    for (final shape in shapes.skip(1)) {
      union = ui.Path.combine(
        ui.PathOperation.union,
        union,
        _polygonPath(shape, map),
      );
    }
    return union;
  }

  @override
  Iterable<ui.Offset> get _coverage => [
    for (final shape in shapes)
      for (final point in shape.points) ui.Offset(point.x, point.y),
  ];

  @override
  bool get _shrinksFold => mode._onlyRemoves;

  @override
  CanvasSelectionShape? get _loneShape =>
      shapes.length == 1 ? shapes.first : null;

  @override
  CanvasSelectionStep mapped(CanvasPoint Function(CanvasPoint) map) =>
      CanvasSelectionCopies([
        for (final shape in shapes)
          CanvasSelectionShape([for (final point in shape.points) map(point)]),
      ], mode);

  /// A copy with nothing inside drops out, and the rest stay one act.
  @override
  CanvasSelectionStep? _clippedTo(ui.Rect wall, SelectionCombineMode mode) {
    final kept = [for (final shape in shapes) ?shape.clippedTo(wall)];
    return kept.isEmpty ? null : CanvasSelectionCopies(kept, mode);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! CanvasSelectionCopies ||
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

  @override
  String toString() =>
      '${mode.name}:'
      '${shapes.map((shape) => '${shape.points.length}pts').join('+')}';
}

/// A WHOLE selection as one operand (I-23 「선택반전」).
///
/// The inverse of a selection is 「the wall, minus that selection」, and
/// "minus a selection" can only be said as ONE step: a selection with a
/// 선택중 in it cannot be subtracted step by step, because A ∖ (B ∩ C) is not
/// A ∖ B ∖ C. So the region itself is the operand, and every reader asks it
/// exactly what that reader would ask it at the top.
final class CanvasSelectionNested extends CanvasSelectionStep {
  CanvasSelectionNested(this.region, super.mode) : super._();

  final CanvasSelectionRegion region;

  @override
  bool hits(CanvasPoint point) => region.containsPoint(point);

  @override
  List<double> _spansOn(double scanY) => region._spansOn(scanY);

  @override
  ui.Path _pathIn(ui.Offset Function(CanvasPoint) map) => region.pathIn(map);

  /// Its own coverage box — a superset, which is all coverage promises.
  @override
  Iterable<ui.Offset> get _coverage {
    final box = region.coverageBounds;
    return [ui.Offset(box.left, box.top), ui.Offset(box.right, box.bottom)];
  }

  /// A nested selection that shrinks ITSELF covers less than its box, even
  /// under a mode that only adds.
  @override
  bool get _shrinksFold => mode._onlyRemoves || region._shrinks;

  /// A selection inside a step is not a polygon, even when it holds one.
  @override
  CanvasSelectionShape? get _loneShape => null;

  @override
  CanvasSelectionStep mapped(CanvasPoint Function(CanvasPoint) map) =>
      CanvasSelectionNested(region.mapped(map), mode);

  /// Through the same door as the top: a nested selection that selects
  /// nothing once cut is as good as no operand.
  @override
  CanvasSelectionStep? _clippedTo(ui.Rect wall, SelectionCombineMode mode) {
    final kept = region.clippedTo(wall);
    return kept == null ? null : CanvasSelectionNested(kept, mode);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CanvasSelectionNested &&
          other.mode == mode &&
          other.region == region;

  @override
  int get hashCode => Object.hash(region, mode);

  @override
  String toString() => '${mode.name}:($region)';
}

/// A composite selection region: an ordered list of (operand, operation)
/// STEPS folded left to right (R26 #16). An operand is a polygon — or the
/// copies of one, or a whole selection of its own ([CanvasSelectionStep]).
///
/// The single polygon of the P9 model is the one-step case, so every old
/// behaviour survives untouched; the four modes simply append a step.
/// Membership is the fold — `add` unions, `subtract` cuts, `intersect`
/// keeps only the overlap — and every consumer (hit test, lift mask,
/// marching ants, transforms) reads the SAME fold, so what the ants draw
/// is exactly what lifts.
///
/// A fold that selects nothing does not LAND: the stage door ([clippedTo])
/// hands back null for it, the app's "no selection" state (I-23-empty-Q1,
/// pending — see [_noSelectionWhenEmpty]). ↩️This paragraph said
/// [combinedWith] returned null for one, which it never did: 삭제 of
/// everything folds to a region there, and [combine] keeps doing so for the
/// callers that are not selections.
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

  /// The one polygon when this region IS one — a single step holding a
  /// single copy — and null otherwise, a nested operand included.
  ///
  /// For a caller that built a one-polygon region and wants its polygon
  /// back: an outline taken onto a posed row, the move tool's implicit box.
  CanvasSelectionShape? get singleShape =>
      steps.length == 1 ? steps.first._loneShape : null;

  /// Folds [shape] into the region under [mode]. Null result = nothing is
  /// selected any more: a click in 갱신, or 삭제/선택중 from NOTHING (which
  /// stays nothing). A fold that 삭제/선택중 EMPTIED is still a region here —
  /// what turns it into none is the stage door ([clippedTo]).
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

  /// 선택 반전 (I-23, 유저 2026-09-12: 「선택반전기능. 내용은 선택되지 않은
  /// 부분을 선택함」): what [region] does NOT select, out to [wall] — the
  /// pasteboard's edge (I-23-Q1: 「페이스트보드 벽까지」).
  ///
  /// Nothing selected ⇒ the whole wall. Otherwise the wall with [region]
  /// taken away as ONE operand ([CanvasSelectionNested]) — exact whatever
  /// the selection is made of, a 선택중 or an earlier inverse included, and
  /// made at once: nothing is rasterised or traced to build it.
  ///
  /// Through the stage door like any landing ([clippedTo]), so the inverse
  /// of everything — which selects nothing — is no selection, and two
  /// presses come back to where they began.
  static CanvasSelectionRegion? invertedWithin(
    CanvasSelectionRegion? region,
    ui.Rect wall,
  ) => CanvasSelectionRegion([
    CanvasSelectionStep(
      CanvasSelectionShape.rect(
        left: wall.left,
        top: wall.top,
        right: wall.right,
        bottom: wall.bottom,
      ),
      SelectionCombineMode.replace,
    ),
    if (region != null)
      CanvasSelectionStep.region(region, SelectionCombineMode.subtract),
  ]).clippedTo(wall);

  /// Even-odd membership through the fold.
  bool containsPoint(CanvasPoint point) {
    var inside = false;
    for (final step in steps) {
      inside = step.mode._fold(inside, step.hits(point));
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
  ({double left, double top, double right, double bottom}) get coverageBounds =>
      _coverageBounds ??= _computeCoverageBounds();

  ({double left, double top, double right, double bottom})? _coverageBounds;

  ({double left, double top, double right, double bottom})
  _computeCoverageBounds() {
    final bounds = pointsBounds([
      for (final step in steps)
        if (!step.mode._onlyRemoves) ...step._coverage,
    ]);
    // An intersect-only tail cannot happen (the first step replaces), so
    // the walk always saw at least one operand.
    return (
      left: bounds.left,
      top: bounds.top,
      right: bounds.right,
      bottom: bounds.bottom,
    );
  }

  /// Whether any of [pixels] can be selected — false only when they lie
  /// wholly outside [coverageBounds], so what answers false may be skipped
  /// without changing one byte the mask lets through.
  ///
  /// A pixel is selected by its CENTRE ([maskFor] scans at +0.5); the
  /// half-pixel slack on every side keeps this a superset at the box's
  /// edges.
  bool mayCover(DirtyRegion pixels) {
    final box = coverageBounds;
    return pixels.rightExclusive > box.left - 0.5 &&
        pixels.left < box.right + 0.5 &&
        pixels.bottomExclusive > box.top - 0.5 &&
        pixels.top < box.bottom + 0.5;
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
    if (!_shrinks) {
      return coverage;
    }
    final folded = _foldedPathBounds;
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

  /// Whether the fold can select less than [coverageBounds] says — some
  /// step takes coverage away, or folds in a selection that does.
  bool get _shrinks => steps.any((step) => step._shrinksFold);

  /// The box of [pathIn]'s fold, measured once: [selectedBounds] reads it,
  /// and so does the question of whether the fold selects anything at all.
  ui.Rect get _foldedPathBounds => _foldedPathBoundsCache ??= pathIn(
    (point) => ui.Offset(point.x, point.y),
  ).getBounds();

  ui.Rect? _foldedPathBoundsCache;

  CanvasSelectionRegion mapped(CanvasPoint Function(CanvasPoint) map) =>
      CanvasSelectionRegion([for (final step in steps) step.mapped(map)]);

  CanvasSelectionRegion translated({required double dx, required double dy}) =>
      mapped((point) => CanvasPoint(x: point.x + dx, y: point.y + dy));

  /// 🚨THE STAGE DOOR (I-23): this selection as it may LAND — cut at
  /// [wall], the pasteboard's edge.
  ///
  /// 유저 2026-09-30: 「선택도구로 사용할수있는 모든부분까지임. 근데 지금
  /// 보니까 페이스트보드 밖도 선택가능하네? 해당부분 안으로만 가능하게
  /// 구조적으로 변경하면서 작업」. So a selection past the wall is not refused
  /// or warned about — it cannot be MADE: every door a selection lands
  /// through (a drawn outline's fold, a transform's landing, the inverse)
  /// asks this.
  ///
  /// Every operand is cut ([CanvasSelectionShape.clippedTo], a nested one
  /// through this), which is exact because cutting commutes with the fold:
  /// (A ∘ B) ∩ W is (A ∩ W) ∘ (B ∩ W) for all four modes. An operand with
  /// nothing left is the empty set, folded by the one table like any other.
  ///
  /// ⚠️This region ITSELF when its coverage already lies inside the wall —
  /// the overwhelming case costs one box test. ⛔Asked at the doors only:
  /// a selection that is merely KEPT, across a walk to a smaller cut, is
  /// not cut (「뭘 하든 안사라지도록」, F-86), and [combine] never asks it,
  /// because it also folds for a caller that is not a selection (a sheet
  /// window's ink region).
  ///
  /// Null when nothing is left — or when what is left selects nothing
  /// ([_noSelectionWhenEmpty]).
  CanvasSelectionRegion? clippedTo(ui.Rect wall) {
    final kept = _keptInside(wall);
    return kept == null ? null : _noSelectionWhenEmpty(kept);
  }

  CanvasSelectionRegion? _keptInside(ui.Rect wall) {
    final box = coverageBounds;
    if (box.left >= wall.left &&
        box.top >= wall.top &&
        box.right <= wall.right &&
        box.bottom <= wall.bottom) {
      return this;
    }
    final kept = <CanvasSelectionStep>[];
    for (final step in steps) {
      // An empty fold only grows under a mode that can add, and whatever
      // starts it again REPLACES — nothing precedes it any more.
      final foldIsEmpty = kept.isEmpty;
      if (foldIsEmpty && !step.mode._fold(false, true)) {
        continue;
      }
      final cut = step._clippedTo(
        wall,
        foldIsEmpty ? SelectionCombineMode.replace : step.mode,
      );
      if (cut != null) {
        kept.add(cut);
      } else if (!step.mode._fold(true, false)) {
        // Folding in nothing emptied it (갱신, 선택중).
        kept.clear();
      }
    }
    return kept.isEmpty ? null : CanvasSelectionRegion(kept);
  }

  /// 🚨I-23-empty-Q1: A FOLD THAT SELECTS NOTHING IS NO SELECTION.
  ///
  /// ⏳PENDING — the user has not answered yet. This applies the
  /// RECOMMENDED answer (A, 「어디서든 선택 없음으로」, the PS/CSP rule), so
  /// 삭제 of everything, a 선택중 that misses and the inverse of everything
  /// all land as no selection — which is also what brings two presses of
  /// the inverse back where they started. Until now such a fold stayed a
  /// live selection with no ants, and the brush's clip to it drew nothing.
  ///
  /// ⚠️ONE place on purpose. If the answer is B (「반전에서만」) this call
  /// moves from [clippedTo] into [invertedWithin]; if it is C (「그대로
  /// 둔다」) it goes. Nothing else changes either way.
  static CanvasSelectionRegion? _noSelectionWhenEmpty(
    CanvasSelectionRegion region,
  ) => region._selectsNothing ? null : region;

  /// Whether the fold selects nothing at all: its folded path is empty —
  /// or, when nothing can shrink it, its operands enclose no box.
  bool get _selectsNothing {
    if (!_shrinks) {
      final box = coverageBounds;
      return box.right <= box.left || box.bottom <= box.top;
    }
    return _foldedPathBounds.isEmpty;
  }

  /// The region as ONE path in an arbitrary (usually viewport) space, for
  /// the marching ants and for display clips. Path booleans are exact for
  /// rendering; the MODEL still folds polygons, so the ants and the lift
  /// mask never disagree about membership.
  ui.Path pathIn(ui.Offset Function(CanvasPoint) map) {
    var combined = ui.Path();
    for (final step in steps) {
      final operand = step._pathIn(map);
      combined = switch (step.mode) {
        SelectionCombineMode.replace => operand,
        SelectionCombineMode.add => ui.Path.combine(
          ui.PathOperation.union,
          combined,
          operand,
        ),
        SelectionCombineMode.subtract => ui.Path.combine(
          ui.PathOperation.difference,
          combined,
          operand,
        ),
        SelectionCombineMode.intersect => ui.Path.combine(
          ui.PathOperation.intersect,
          combined,
          operand,
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
  /// ★It reads the row runs [maskFor] fills ([_pixelRuns]) rather than
  /// re-deriving the fold: 「어느 픽셀이 들어오나」 already has an answer, and
  /// a second one written next to it would be a rule that can drift.
  /// ↩️It read [maskFor] itself — one byte per pixel of the selected box —
  /// until an inverse made that box the whole pasteboard wall (I-23); the
  /// runs are the same answer without the bytes. ⚠️It still folds every row
  /// of the selected box, so callers cache the result rather than asking
  /// per frame.
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

  /// What holding THIS region costs, for the history stack's byte budget.
  ///
  /// The steps are a handful of shapes; the weight is the memo above,
  /// which a canvas-sized lasso fills with hundreds of thousands of
  /// points. An undo entry keeps its region alive, so the memo lives as
  /// long as the entry does — measured as RSS the budget could not see,
  /// because the selection command reported nothing at all.
  ///
  /// ⚠️Zero until something asks for the contours: a region nobody drew
  /// ants around holds only its steps.
  int get estimatedRetainedBytes {
    final contours = _pixelContoursCache;
    if (contours == null) {
      return 0;
    }
    var points = 0;
    for (final contour in contours) {
      points += contour.length;
    }
    return points * _bytesPerContourPoint;
  }

  /// Two doubles and the object header a [CanvasPoint] costs on the Dart
  /// heap. An estimate by construction — the budget needs the ORDER of
  /// the number, and zero was the wrong order.
  static const int _bytesPerContourPoint = 32;

  /// The closed contours of [pixelOutlineIn], in CANVAS space.
  ///
  /// ⚠️Memoised, and that is not an optimisation but the condition of
  /// calling it from a painter at all: the walk folds every row of the
  /// selected box, while the ants repaint on every animation tick. A region
  /// is immutable, so this can never go stale — the same reasoning
  /// `layerContentBoundsAt` states for its own memo, one field over.
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
    final bounds = selectedBounds;
    // The pixel box: every pixel whose CENTRE can be inside. A box smaller
    // than that would clip the outline; a bigger one only costs rows.
    final left = (bounds.left - 0.5).floor();
    final top = (bounds.top - 0.5).floor();
    final width = (bounds.right + 0.5).ceil() - left;
    final height = (bounds.bottom + 0.5).ceil() - top;
    if (width <= 0 || height <= 0) {
      return <List<CanvasPoint>>[];
    }
    final edges = _boundaryEdges([
      for (var row = 0; row < height; row += 1)
        _pixelRuns(top + row + 0.5, left, width),
    ], width);
    CanvasPoint at(int v) => CanvasPoint(
      x: (left + v % (width + 1)).toDouble(),
      y: (top + v ~/ (width + 1)).toDouble(),
    );
    final contours = <List<CanvasPoint>>[];
    while (edges.isNotEmpty) {
      final contour = _walkContour(edges, edges.keys.first, width + 1, at);
      // ⚠️And once more AROUND the join. The walk starts wherever the edge
      // map happened to hand it a vertex, which is usually the middle of a
      // straight run, and the segment that closes the contour is implied
      // rather than stepped — so the first and last points can each sit in
      // the middle of a line the merge in the walk never saw the two halves
      // of. 🧪Without this a rectangle came back with five corners.
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

  /// Every boundary edge of the pixels [rows] hold (each row's runs, from
  /// [_pixelRuns]) as vertex → vertex, keyed by the vertex it starts at, in
  /// a box [width] pixels wide. Wound so that the selected side is on the
  /// same hand throughout: a component runs one way and a hole the other,
  /// which is what makes the outline's fill carve rather than cover.
  ///
  /// 🚨ROW BY ROW, NEVER A MASK (I-23). An inverse's box is the whole
  /// pasteboard wall — about 35MB at a byte a pixel for a 2340×1654 canvas,
  /// allocated and read on the paint thread before one ant was drawn. Only
  /// a pixel with an edge is visited: a run's two ends, and where the row
  /// above or below leaves it uncovered.
  ///
  /// ⛔In exactly the order the pixel-by-pixel scan this replaced emitted
  /// them — row-major, then top, right, bottom, left within a pixel — so
  /// every contour starts where it always did and the dashes stay put.
  static Map<int, List<int>> _boundaryEdges(List<List<int>> rows, int width) {
    final edges = <int, List<int>>{};
    void edge(int x0, int y0, int x1, int y1) {
      edges
          .putIfAbsent(y0 * (width + 1) + x0, () => <int>[])
          .add(y1 * (width + 1) + x1);
    }

    for (var y = 0; y < rows.length; y += 1) {
      final above = _RunCursor(y > 0 ? rows[y - 1] : const []);
      final below = _RunCursor(y + 1 < rows.length ? rows[y + 1] : const []);
      final runs = rows[y];
      for (var r = 0; r + 1 < runs.length; r += 2) {
        final start = runs[r];
        final end = runs[r + 1];
        var x = start;
        while (x < end) {
          final up = above.covers(x);
          final down = below.covers(x);
          if (!up) edge(x, y, x + 1, y);
          if (x == end - 1) edge(x + 1, y, x + 1, y + 1);
          if (!down) edge(x + 1, y + 1, x, y + 1);
          if (x == start) edge(x, y + 1, x, y);
          if (up && down) {
            // Covered above and below, nothing has an edge until one of
            // the three runs ends.
            final next = math.min(math.min(above.end, below.end), end - 1);
            x = math.max(x + 1, next);
          } else {
            x += 1;
          }
        }
      }
    }
    return edges;
  }

  /// One closed contour of [edges], walked from [start] and consumed as it
  /// goes — [stride] is a row of vertices, [at] a vertex's canvas point.
  static List<CanvasPoint> _walkContour(
    Map<int, List<int>> edges,
    int start,
    int stride,
    CanvasPoint Function(int vertex) at,
  ) {
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
      final dx = next % stride - current % stride;
      final dy = next ~/ stride - current ~/ stride;
      if (dx == lastDx && dy == lastDy && contour.length > 1) {
        contour[contour.length - 1] = at(next);
      } else {
        contour.add(at(next));
      }
      lastDx = dx;
      lastDy = dy;
      current = next;
    }
    return contour;
  }

  /// The hard coverage mask over the pixel box `[left, left+width) ×
  /// [top, top+height)`: 255 inside, 0 outside, by PIXEL CENTRE — the
  /// same even-odd rule as [containsPoint], so a lift never disagrees
  /// with a hit test.
  ///
  /// Per row the WHOLE fold is taken as spans first ([_spansOn]: each
  /// operand's spans combined under its mode) and sampled into pixels once
  /// ([_pixelRuns]). Sampling commutes with the set operations, so this is
  /// the answer folding every step's own pixels gave — and a nested
  /// selection folds in as spans of its own, which a per-step pixel fold
  /// had no row to hold.
  Uint8List maskFor({
    required int left,
    required int top,
    required int width,
    required int height,
  }) {
    final mask = Uint8List(width * height);
    for (var row = 0; row < height; row += 1) {
      final runs = _pixelRuns(top + row + 0.5, left, width);
      final rowOffset = row * width;
      for (var r = 0; r + 1 < runs.length; r += 2) {
        mask.fillRange(rowOffset + runs[r], rowOffset + runs[r + 1], 255);
      }
    }
    return mask;
  }

  /// What the fold selects on the scanline at [scanY]: every operand's
  /// spans combined under its step's mode, left to right — [containsPoint]
  /// for a whole row, by the same table ([SelectionCombineMode._fold]).
  List<double> _spansOn(double scanY) {
    var fold = const <double>[];
    for (final step in steps) {
      fold = _combineSpans(fold, step._spansOn(scanY), step.mode);
    }
    return fold;
  }

  /// The pixels [maskFor] fills on the row at [scanY], as `[start, end, …]`
  /// columns counted from [left] and clamped into `[0, width)`.
  ///
  /// A pixel is in when its CENTRE is: `start ≤ x + 0.5 < end`, the same
  /// strictness as [containsPoint]'s `point.x < intersection`.
  ///
  /// ⚠️A span wholly to the RIGHT of the window samples to a start past
  /// `width`, and the `start >= end` skip is what keeps the fill from
  /// running off the row — the 1×1 probe a mask/hit-test parity check uses
  /// is exactly the window small enough to reach it.
  ///
  /// ⚠️Runs that TOUCH once sampled are one run. Two spans kept apart by a
  /// gap with no pixel centre in it sample to neighbouring columns, and a
  /// reader of run ends (the outline walk) would draw a wall between two
  /// pixels that are both selected.
  List<int> _pixelRuns(double scanY, int left, int width) {
    final spans = _spansOn(scanY);
    final runs = <int>[];
    for (var c = 0; c + 1 < spans.length; c += 2) {
      final start = math.max((spans[c] - 0.5).ceil() - left, 0);
      final end = math.min((spans[c + 1] - 0.5).ceil() - left, width);
      if (start >= end) {
        continue;
      }
      if (runs.isNotEmpty && runs[runs.length - 1] == start) {
        runs[runs.length - 1] = end;
      } else {
        runs
          ..add(start)
          ..add(end);
      }
    }
    return runs;
  }

  /// Whether [b] sits on the straight line from [a] to [c] — the test the
  /// contour merge asks at a join. Axis-aligned steps only, which is all a
  /// pixel boundary ever has.
  static bool _isStraight(CanvasPoint a, CanvasPoint b, CanvasPoint c) =>
      (b.x - a.x) * (c.y - b.y) == (b.y - a.y) * (c.x - b.x);

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
  String toString() => 'CanvasSelectionRegion(${steps.join(' → ')})';
}

/// Sorted x crossings of [shape]'s edges on the scanline at [scanY] — its
/// inside spans by the even-odd rule, paired off left to right.
List<double> _crossingsOn(CanvasSelectionShape shape, double scanY) {
  final crossings = <double>[];
  final points = shape.points;
  for (var i = 0, j = points.length - 1; i < points.length; j = i, i += 1) {
    final a = points[i];
    final b = points[j];
    if (CanvasSelectionShape.edgeStraddles(a, b, scanY)) {
      crossings.add(CanvasSelectionShape.edgeCrossingX(a, b, scanY));
    }
  }
  return crossings..sort();
}

/// Two rows of spans combined under [mode] — each a flat sorted
/// `[start, end, …]` list whose spans may touch or be empty, which is
/// exactly what a polygon's raw crossings are.
///
/// ⛔ONE sweep for every mode, the union of a guide's copies included (that
/// is `add`): walk both rows' endpoints in order, and between two of them
/// ask [SelectionCombineMode._fold] — the table the point test folds by.
/// A row's membership there is the PARITY of its endpoints passed so far,
/// which is the even-odd rule, so raw crossings need no pairing first.
///
/// Exact, not approximate: it only ever hands back endpoints it was given,
/// so sampling the answer at a pixel centre says what folding the two
/// rows' own samples says. That is why the mask can fold spans first and
/// sample once.
List<double> _combineSpans(
  List<double> a,
  List<double> b,
  SelectionCombineMode mode,
) {
  final combined = <double>[];
  var inside = false;
  var ia = 0;
  var ib = 0;
  while (ia < a.length || ib < b.length) {
    final x = ib >= b.length || (ia < a.length && a[ia] <= b[ib])
        ? a[ia]
        : b[ib];
    while (ia < a.length && a[ia] == x) {
      ia += 1;
    }
    while (ib < b.length && b[ib] == x) {
      ib += 1;
    }
    final next = mode._fold(ia.isOdd, ib.isOdd);
    if (next != inside) {
      combined.add(x);
      inside = next;
    }
  }
  return combined;
}

/// [shape] as one closed even-odd path in [map]'s space.
ui.Path _polygonPath(
  CanvasSelectionShape shape,
  ui.Offset Function(CanvasPoint) map,
) => ui.Path()
  ..fillType = ui.PathFillType.evenOdd
  ..addPolygon([for (final point in shape.points) map(point)], true);

/// One row's pixel runs, read left to right: asked about columns that never
/// go back, it answers in a single pass over the row.
final class _RunCursor {
  _RunCursor(this._runs);

  final List<int> _runs;
  int _at = 0;

  /// Whether a run covers column [x].
  bool covers(int x) {
    while (_at + 1 < _runs.length && _runs[_at + 1] <= x) {
      _at += 2;
    }
    return _at + 1 < _runs.length && _runs[_at] <= x;
  }

  /// Where the run [covers] last found ends — asked only after a yes.
  int get end => _runs[_at + 1];
}
