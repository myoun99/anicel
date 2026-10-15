import 'dart:async';

import '../../models/brush_frame_key.dart';
import '../../models/cut.dart';
import '../../models/playback_quality.dart';
import '../../models/rgba_image_bytes.dart';
import '../../services/playback/frame_demand.dart';
import '../canvas/canvas_layer_stack_view.dart' show CanvasLayerImageRequest;
import '../quiet_turns.dart';
import 'layer_frame_image_cache.dart';
import 'playback_pictures.dart';

/// A frame as the editing canvas draws it: each row an image of its cel at
/// the level the canvas draws that frame at ([LayerFrameImageCache]) — the
/// level of the view it is seen through, the camera's included while a run
/// plays through it ([CanvasLook]) — the images the
/// canvas holds, so a frame made here is one the canvas shows without making
/// anything, and nothing of it is made twice
/// (playback-plays-the-screen-material; 유저 F-296-Q6 「중복소재 안만들고
/// 싶은것」).
///
/// A frame is there when every row of it is. A row whose cel holds nothing to
/// draw is there by definition — as the ruler's bar has always counted a
/// frame that composes to nothing.
class CanvasPictures implements PlaybackPictures {
  CanvasPictures({
    required this.layerImages,
    required this.rowsOf,
    required this.qualityAt,
    QuietTurns? quietTurns,
  }) : quietTurns = quietTurns ?? QuietTurns.instance;

  final LayerFrameImageCache layerImages;

  /// Where a row takes its turn to put its picture on the GPU ([make]).
  final QuietTurns quietTurns;

  /// How long a row has taken from its turn to its landing, at the most of
  /// late.
  final QuietSpan _rowSpan = QuietSpan();

  /// The rows [cut]'s frame [frameIndex] draws as images while a run plays
  /// it — the canvas's own tree with no row standing live.
  final List<CanvasLayerImageRequest> Function(Cut cut, int frameIndex)
  rowsOf;

  /// The level the canvas draws a cut's frame's rows at
  /// ([CanvasLook.qualityAt]) — one frame's own, as a camera zooming through
  /// a cut draws its frames at more than one.
  final PlaybackQuality Function(Cut cut, int frameIndex) qualityAt;

  /// Rows whose image could not be made, and the store generation and cel
  /// revision they failed at — the canvas's own `_failedRevisions`, kept by
  /// the maker: one unreachable cel is not opened again on every walk, and a
  /// run is not held for a row that will not come. The next change of the
  /// cel's content, or a project opened again, is looked at afresh.
  final Map<BrushFrameKey, (int, int?)> _failed = {};

  (int, int?) _failureKeyOf(BrushFrameKey key) => (
    layerImages.frameStore.celContentRevision.value,
    layerImages.frameStore.frameOrNull(key)?.sourceRevision,
  );

  /// Whether [row]'s image could not be made at the content it has now — a
  /// frame showing it waits for nothing more of it.
  bool gaveUpOn(CanvasLayerImageRequest row) {
    final failed = _failed[row.frameKey];
    return failed != null && failed == _failureKeyOf(row.frameKey);
  }

  LayerFrameImage? _held(
    CanvasLayerImageRequest row,
    Cut cut,
    PlaybackQuality level,
  ) => layerImages.peek(
    row.frameKey,
    level,
    canvasSize: cut.canvasSize,
    sourceEffects: row.sourceEffects,
    inkSuffices: row.inkSuffices,
  );

  bool _rowIsThere(CanvasLayerImageRequest row, Cut cut, PlaybackQuality level) =>
      _held(row, cut, level) != null ||
      !layerImages.frameStore.celHasRenderableContent(row.frameKey);

  @override
  bool has(DemandedPicture picture) {
    final level = qualityAt(picture.cut, picture.frameIndex);
    return rowsOf(
      picture.cut,
      picture.frameIndex,
    ).every((row) => _rowIsThere(row, picture.cut, level));
  }

  /// Each row [make] would make, as the cache slot its image lands in — a
  /// cel two frames show is one part.
  @override
  Set<Object> partsToMake(DemandedPicture picture) {
    final level = qualityAt(picture.cut, picture.frameIndex);
    return {
      for (final row in rowsOf(picture.cut, picture.frameIndex))
        if (!_rowIsThere(row, picture.cut, level) && !gaveUpOn(row))
          (row.frameKey, level),
    };
  }

  /// Nothing of the frame is still to come: every row not there is one that
  /// could not be made.
  @override
  bool failed(DemandedPicture picture) {
    final level = qualityAt(picture.cut, picture.frameIndex);
    return rowsOf(picture.cut, picture.frameIndex).every(
      (row) => _rowIsThere(row, picture.cut, level) || gaveUpOn(row),
    );
  }

  /// Every row of [picture] still to come is given up on. A row that threw
  /// in [make] is recorded there, and its siblings made past it — so what
  /// this records is a frame whose making stopped before its rows: the
  /// movie its cels show could not be read.
  @override
  void noteFailure(DemandedPicture picture) {
    final level = qualityAt(picture.cut, picture.frameIndex);
    for (final row in rowsOf(picture.cut, picture.frameIndex)) {
      if (!_rowIsThere(row, picture.cut, level)) {
        _failed[row.frameKey] = _failureKeyOf(row.frameKey);
      }
    }
  }

  /// The rows not there, each the canvas at the level — an estimate, made
  /// before a pixel is read: an image covers its cel's TILES, so a canvas
  /// that is no whole number of tiles, or a row inked out on the pasteboard,
  /// makes a bigger one, and a row inked in a corner a smaller one. The trim
  /// after each landing measures what was made.
  @override
  int bytesToMake(DemandedPicture picture) {
    final level = qualityAt(picture.cut, picture.frameIndex);
    final size = scaledCanvasSize(picture.cut.canvasSize, level);
    var bytes = 0;
    for (final row in rowsOf(picture.cut, picture.frameIndex)) {
      if (!_rowIsThere(row, picture.cut, level)) {
        bytes += estimatedImageBytes(size.width, size.height);
      }
    }
    return bytes;
  }

  /// A held cel is one part however many frames show it.
  @override
  int weighNew(DemandedPicture picture, Set<Object> seen) {
    final level = qualityAt(picture.cut, picture.frameIndex);
    var bytes = 0;
    for (final row in rowsOf(picture.cut, picture.frameIndex)) {
      final held = _held(row, picture.cut, level);
      if (held != null && seen.add((row.frameKey, level))) {
        bytes += estimatedImageBytes(held.image.width, held.image.height);
      }
    }
    return bytes;
  }

  /// 🚨ONE ROW'S FAILURE IS ONE ROW'S: a row that throws is recorded and
  /// its siblings are made past it, and the throw is handed on once they
  /// are — the frame's other rows are no reason for a cel that cannot be
  /// read to be read again, nor its failure a reason for them to be missing.
  ///
  /// ⛔ONE ROW AFTER ANOTHER, on purpose: a row's making holds its cel's
  /// tile pictures until its raster lands, and asked for at once a frame of
  /// thirteen rows held thirteen cels' worth — for no gain (measured
  /// 10-10, camera view, profile: the whole cut made +0.3–15% LATER). What
  /// a walk gains from is asking for the NEXT frames before it waits
  /// ([PlaybackPrerenderScheduler]'s ask ahead).
  ///
  /// 🚨BUT EVERY ROW'S CEL IS THAWED AT ONCE (card
  /// cel-thaw-holds-the-ui-thread): a thaw holds no picture, only the
  /// cel's own tiles, and runs on a worker ([BrushFrameStore.thawAhead] —
  /// as many at once as the machine has workers for). Asked row by row, as
  /// each row's making waits for its own, the workers would thaw a frame's
  /// cels one after another.
  ///
  /// 🚨EACH ROW TAKES ITS TURN IN THE QUIET BETWEEN A RUN'S HELD FRAMES
  /// ([QuietTurns]) once its cel is read, before its picture goes on the
  /// GPU — a row at a time is what one turn fits.
  @override
  Future<bool> make(
    DemandedPicture picture, {
    required bool Function() shouldAbort,
    bool Function() due = notDue,
  }) async {
    final level = qualityAt(picture.cut, picture.frameIndex);
    final cut = picture.cut;
    final rows = rowsOf(cut, picture.frameIndex);
    if (!shouldAbort()) {
      for (final row in rows) {
        if (!_rowIsThere(row, cut, level) && !gaveUpOn(row)) {
          unawaited(
            layerImages.frameStore.thawAhead(
              row.frameKey,
              canvasSize: cut.canvasSize,
            ),
          );
        }
      }
    }
    (Object, StackTrace)? thrown;
    for (final row in rows) {
      if (_rowIsThere(row, cut, level) || gaveUpOn(row)) {
        continue;
      }
      final LayerFrameImage? image;
      try {
        image = await layerImages.prepare(
          key: row.frameKey,
          canvasSize: cut.canvasSize,
          quality: level,
          sourceEffects: row.sourceEffects,
          shouldAbort: shouldAbort,
          inkSuffices: row.inkSuffices,
          turn: () => quietTurns.inAQuiet(
            _rowSpan,
            gone: shouldAbort,
            due: due,
          ),
        );
      } on Object catch (error, stack) {
        _failed[row.frameKey] = _failureKeyOf(row.frameKey);
        thrown ??= (error, stack);
        continue;
      }
      if (image == null) {
        if (shouldAbort()) {
          return false;
        }
        // A cel with pixels that cannot be drawn at this canvas size — the
        // canvas's own miss of the same name, which it leaves to the next
        // pass. A maker that left it would make it again on every walk.
        _failed[row.frameKey] = _failureKeyOf(row.frameKey);
      }
    }
    if (thrown case (final error, final stack)) {
      Error.throwWithStackTrace(error, stack);
    }
    return true;
  }

  /// How many steps on each of the canvas's images is next shown under
  /// [demand] — what the budget lets go of LATEST first. Walked once, the
  /// first time it is asked: a budget with room asks nothing.
  LayerImageWantedAt wantedAt(
    FrameDemand? demand,
  ) {
    Map<(BrushFrameKey, PlaybackQuality), int>? soonest;
    return (slot) {
      if (demand == null) {
        return null;
      }
      soonest ??= _soonestSteps(demand);
      return soonest![slot];
    };
  }

  Map<(BrushFrameKey, PlaybackQuality), int> _soonestSteps(
    FrameDemand demand,
  ) {
    final soonest = <(BrushFrameKey, PlaybackQuality), int>{};
    for (var step = 0; step < demand.length; step += 1) {
      for (final picture
          in demand.picturesAt(step) ?? const <DemandedPicture>[]) {
        final level = qualityAt(picture.cut, picture.frameIndex);
        for (final row in rowsOf(picture.cut, picture.frameIndex)) {
          soonest.putIfAbsent((row.frameKey, level), () => step);
        }
      }
    }
    return soonest;
  }
}
