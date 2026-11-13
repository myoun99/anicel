import 'dart:math' as math;
import 'dart:typed_data';

import 'package:gpu_engine/gpu_engine.dart' show GpuMask;

import '../models/dirty_region.dart';
import '../models/pasteboard_bounds.dart';
import '../native/engine_selection_masks.dart';
import 'canvas_selection.dart';
import 'canvas_selection_region.dart';

/// 🚨★★★WHAT IS DRAWN IN A SELECTION IS CUT BY ONE EDGE, whichever tool drew
/// it (brush-fidelity-Q11 · Q12, 유저 2026-10-18: 「도형 · 채우기도 같은 문으로
/// 자른다」 · 「브러시 · 지우개도 같은 문으로 자른다」).
///
/// A held picture took the selection at its 확장 · 페더 · AA and everything
/// else at the centre-sampled outline, so one marquee had two edges. Every
/// road that cuts a drawing holds one of these now: the live stroke's
/// rasterizer, the commit funnel, a fill, a shape, the door a held picture
/// lands through.
///
/// ⛔A region is not a clip, so a road cannot be handed the bare outline by
/// forgetting. [SelectionClip.outline] says so out loud, and only for what
/// never had a softness: the edge of a sheet window's paper.
sealed class SelectionClip {
  const SelectionClip();

  /// [region] as a selection reads, at its [options], inside the pasteboard
  /// [wall].
  factory SelectionClip.of(
    CanvasSelectionRegion region, {
    required PasteboardWall wall,
    required SelectionMaskOptions options,
  }) => options.isHard
      ? _OutlineClip(region)
      : _SoftClip(region, wall: wall, options: options);

  /// [region]'s own outline, every pixel in or out by its centre.
  const factory SelectionClip.outline(CanvasSelectionRegion region) =
      _OutlineClip;

  /// Whether any of [pixels] can be selected — false only when none can, so
  /// what answers false may be skipped without changing one byte the mask
  /// lets through.
  bool mayCover(DirtyRegion pixels);

  /// How much of each pixel of the box `[left, left+width) × [top, top+height)`
  /// the selection takes, a byte each, row by row.
  Uint8List maskFor({
    required int left,
    required int top,
    required int width,
    required int height,
  });

  /// The bytes [maskFor] reads, over every pixel this clip can select, made
  /// on the engine the first time what reads a selection there asks — the
  /// live stroke (`BrushLiveStrokeRasterizer`), a stamp's landing
  /// (`materializeBrushDabSequenceOnBitmapSurface`) — and kept as long as
  /// this clip ([EngineSelectionMasks.keptFor]). Nothing frees it.
  ///
  /// ⚠️Only for a clip that [mayCover] some pixel: one that can select none
  /// has no box to make it over.
  GpuMask maskOnEngine() => EngineSelectionMasks.keptFor(this, _madeOnEngine);

  GpuMask _madeOnEngine();
}

final class _OutlineClip extends SelectionClip {
  const _OutlineClip(this._region);

  final CanvasSelectionRegion _region;

  @override
  bool mayCover(DirtyRegion pixels) => _region.mayCover(pixels);

  @override
  GpuMask _madeOnEngine() => EngineSelectionMasks.of(
    _region.spelled,
    box: _region.pixelBoxWithin(null)!,
    grow: 0,
    feather: 0,
    antiAlias: false,
  );

  @override
  Uint8List maskFor({
    required int left,
    required int top,
    required int width,
    required int height,
  }) => _region.maskFor(left: left, top: top, width: width, height: height);
}

/// The bytes [selectionMaskOnPasteboard] reads over the selection's whole
/// box, window for window, by reading only around the window: the passes
/// look [SelectionMaskOptions.neighbourReach] away and no further, and the
/// box's own edges are the same edges to a window that reaches them.
///
/// ⚠️brush-fidelity-Q12 costed this as the whole selection's mask, made once
/// and kept. That is a first stroke that waits on the selection's size and a
/// mask held for as long as the selection stands; this one pays for the
/// tiles a stroke touches, once each ([BrushLiveStrokeRasterizer] keeps them
/// for the stroke), and holds nothing.
final class _SoftClip extends SelectionClip {
  _SoftClip(
    this._region, {
    required PasteboardWall wall,
    required SelectionMaskOptions options,
  }) : _options = options,
       _box = _region.pixelBoxWithin(wall.region, pad: options.bboxPad);

  final CanvasSelectionRegion _region;
  final SelectionMaskOptions _options;

  /// The box of the whole reading — null when the selection and the wall do
  /// not meet.
  final ({int left, int top, int width, int height})? _box;

  @override
  bool mayCover(DirtyRegion pixels) {
    final box = _box;
    return box != null &&
        pixels.rightExclusive > box.left &&
        pixels.left < box.left + box.width &&
        pixels.bottomExclusive > box.top &&
        pixels.top < box.top + box.height;
  }

  /// Over the whole reading's box: the windows [maskFor] reads are cut
  /// from it. ⚠️The whole box, which the class's note turns down for the
  /// CPU's bytes: on the engine it is passes the UI thread does not wait
  /// for, made once for the clip and let go of with it (2026-11-13 · 14) —
  /// where the CPU made a window's bytes and handed them up at every move.
  @override
  GpuMask _madeOnEngine() {
    final box = _box;
    if (box == null) {
      throw StateError('a selection that meets no pixel of its wall');
    }
    return EngineSelectionMasks.of(
      _region.spelled,
      box: box,
      grow: _options.growPx,
      feather: _options.featherPx,
      antiAlias: _options.antiAlias,
    );
  }

  @override
  Uint8List maskFor({
    required int left,
    required int top,
    required int width,
    required int height,
  }) {
    final mask = Uint8List(width * height);
    final box = _box;
    if (box == null) {
      return mask;
    }
    final boxRight = box.left + box.width;
    final boxBottom = box.top + box.height;
    final fromX = math.max(left, box.left);
    final toX = math.min(left + width, boxRight);
    final fromY = math.max(top, box.top);
    final toY = math.min(top + height, boxBottom);
    if (toX <= fromX || toY <= fromY) {
      return mask;
    }
    final reach = _options.neighbourReach;
    final readLeft = math.max(fromX - reach, box.left);
    final readTop = math.max(fromY - reach, box.top);
    final readWidth = math.min(toX + reach, boxRight) - readLeft;
    final readHeight = math.min(toY + reach, boxBottom) - readTop;
    final read = buildSelectionMask(
      region: _region,
      options: _options,
      left: readLeft,
      top: readTop,
      width: readWidth,
      height: readHeight,
    );
    for (var y = fromY; y < toY; y += 1) {
      final row = (y - top) * width;
      mask.setRange(
        row + fromX - left,
        row + toX - left,
        read,
        (y - readTop) * readWidth + fromX - readLeft,
      );
    }
    return mask;
  }
}
