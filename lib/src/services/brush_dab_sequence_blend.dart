import '../models/brush_dab.dart';
import '../models/brush_dab_sequence.dart';
import '../models/brush_pixel_blend_operation.dart';
import '../models/brush_pixel_coverage.dart';
import '../models/rgba_color.dart';
import '../models/stroke_pixel.dart';
import 'brush_dab_coverage.dart';
import 'brush_pixel_blend.dart';
import 'brush_stroke_blend.dart';

typedef DestinationPixelReader = RgbaColor Function(int x, int y);

List<BrushPixelBlendOperation> brushPixelBlendOperationsForDabSequence({
  required BrushDabSequence sequence,
  required DestinationPixelReader destinationAt,
}) {
  final pile = _Pile(destinationAt);
  for (final dab in sequence.dabs) {
    pile.lay(dab);
  }
  return List<BrushPixelBlendOperation>.unmodifiable(pile.operations);
}

/// What the sequence's dabs have piled up so far, pixel by pixel, and the
/// changes of bytes they made on the way ([operations]).
class _Pile {
  _Pile(this._destinationAt);

  final DestinationPixelReader _destinationAt;
  final operations = <BrushPixelBlendOperation>[];

  // Each pixel as the sequence piles it up — on its 16-bit plane, widened
  // from the destination's bytes the first time a dab reaches it, the way
  // the commit scratch widens a tile ([StrokePixel], ABI 40).
  final _first = <_PixelKey, StrokePixel>{};

  // A stroke with a second tip piles that tip's dabs on a plane of their
  // own and shows the two through its view (ABI 60, `qa_dual_view_rows`):
  // each pixel's second level, and the bytes it shows.
  final _second = <_PixelKey, StrokePixel>{};
  final _shown = <_PixelKey, RgbaColor>{};

  void lay(BrushDab dab) {
    final dual = dab.dual;
    // A second tip's dab piles over, never erases (`qa_dab_blend_tile`).
    final piler = dab.second && dab.erase ? dab.copyWith(erase: false) : dab;
    final touched = <_PixelKey>[];
    // The VISITOR, not the list: this walk folds each pixel as it arrives, so
    // the list the other form builds — and the `unmodifiable` copy of it —
    // would be built only to be thrown away one dab later. (The coverage
    // OBJECT still gets made, because that is what `blendBrushDabStrokePixel`
    // takes; it is the container around them that goes.)
    forEachBrushPixelCoverage(dab, (x, y, value, ceiling) {
      final coverage = BrushPixelCoverage(
        x: x,
        y: y,
        coverage: value,
        ceiling: ceiling,
      );
      final key = _PixelKey(coverage.x, coverage.y);
      final moved = dab.second
          ? _pileSecond(piler, coverage, key)
          : _pileFirst(dab, coverage, key, viewed: dual != null);
      if (moved) {
        touched.add(key);
      }
    });
    if (dual != null) {
      _show(touched, dual);
    }
  }

  /// Piles [dab] at [key] on the first plane — whether the plane moved. The
  /// bytes of a [viewed] stroke are its view's ([_show]); any other stroke's
  /// change of bytes is an operation here.
  bool _pileFirst(
    BrushDab dab,
    BrushPixelCoverage coverage,
    _PixelKey key, {
    required bool viewed,
  }) {
    final before =
        _first[key] ?? StrokePixel.widened(_destinationAt(key.x, key.y));
    final after = blendBrushDabStrokePixel(
      dab: dab,
      coverage: coverage,
      destination: before,
    );
    if (after == before) {
      return false;
    }
    _first[key] = after;
    // An operation is a change of BYTES — the plane can move under a
    // view that stays put.
    if (!viewed && after.bytes != before.bytes) {
      operations.add(
        BrushPixelBlendOperation(
          x: key.x,
          y: key.y,
          before: before.bytes,
          after: after.bytes,
        ),
      );
    }
    return true;
  }

  /// Piles a second tip's [dab] at [key] on the second plane — whether the
  /// plane moved.
  bool _pileSecond(BrushDab dab, BrushPixelCoverage coverage, _PixelKey key) {
    final under = _second[key] ?? StrokePixel.level(0);
    final piled = blendBrushDabStrokePixel(
      dab: dab,
      coverage: coverage,
      destination: under,
    );
    if (piled.a == under.a) {
      return false;
    }
    _second[key] = StrokePixel.level(piled.a);
    return true;
  }

  /// The view of the pixels the dab moved a plane under, once it has
  /// landed.
  void _show(List<_PixelKey> touched, BrushDualView dual) {
    for (final key in touched) {
      final first =
          _first[key] ?? StrokePixel.widened(_destinationAt(key.x, key.y));
      final before = _shown[key] ?? _destinationAt(key.x, key.y);
      final after = _dualView(first, _second[key]?.a ?? 0, dual);
      if (after == before) {
        continue;
      }
      _shown[key] = after;
      operations.add(
        BrushPixelBlendOperation(
          x: key.x,
          y: key.y,
          before: before,
          after: after,
        ),
      );
    }
  }
}

/// What [first] and a second level of [second] show through [dual] — the
/// kernels' view, pixel for pixel ([dualViewAlpha]).
RgbaColor _dualView(StrokePixel first, int second, BrushDualView dual) {
  final alpha = dualViewAlpha(first.a, second, dual);
  if (alpha == 0) {
    return RgbaColor(r: 0, g: 0, b: 0, a: 0);
  }
  return RgbaColor(
    r: (first.r / 257.0).round(),
    g: (first.g / 257.0).round(),
    b: (first.b / 257.0).round(),
    a: alpha,
  );
}

class _PixelKey {
  const _PixelKey(this.x, this.y);

  final int x;
  final int y;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _PixelKey && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}
