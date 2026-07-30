import 'layer.dart';
import 'timeline_coverage.dart';
import 'timeline_exposure.dart';
import 'transform_track.dart';

/// A cut-local DISPLAY window over a track-global SE layer.
///
/// Track SE timelines live on the track's global frame axis (sounds may
/// cross cut boundaries); the timeline panel renders one cut. The window
/// produces a read-only display clone whose timeline is rebased to the
/// cut's local frames:
///
/// - The window is OPEN-ENDED on the right (SE globalization): every
///   entry at or after the cut start rides, rebased — scroll the ruler
///   past the cut end and the NEXT cuts' sounds are simply there, on the
///   endless runway, editable like any other block. The `~` continuation
///   mark keeps saying exactly "this block crosses the current cut's
///   end" — pure display, not a clip.
/// - Entries keep their TRUE length — a block may extend past the cut
///   end (the cut-cross case).
/// - The LEFT side stays a wall: the cut-local axis cannot go below 0,
///   so entries starting before the cut appear only as the synthesized
///   spill-in entry at local 0 carrying the remaining length. It is
///   display-only: edits must convert through [toGlobalFrame] and
///   operate on the GLOBAL layer (the clone is never written back), and
///   a start-edge grab on the spill entry is rejected — its real start
///   lives in an earlier cut.
///
/// All local↔global conversion lives HERE; nothing else adds cut starts.
class TrackSeWindow {
  const TrackSeWindow({
    required this.cutStartFrame,
    required this.cutDurationFrames,
  });

  final int cutStartFrame;
  final int cutDurationFrames;

  int get cutEndFrameExclusive => cutStartFrame + cutDurationFrames;

  int toGlobalFrame(int localFrame) => localFrame + cutStartFrame;

  int toLocalFrame(int globalFrame) => globalFrame - cutStartFrame;

  /// The global block covering the window's first frame from BEFORE it
  /// (a sound spilling in from an earlier cut), or null.
  TimelineDrawingBlock? spillInBlock(Layer globalLayer) {
    final covering = coveringDrawingBlockAt(
      globalLayer.timeline,
      cutStartFrame,
    );
    if (covering == null || covering.startIndex >= cutStartFrame) {
      return null;
    }
    return covering;
  }

  /// Whether the display block starting at [localBlockStart] is the
  /// synthesized spill-in entry (whose start edge is not editable here).
  bool isSpillInStart(Layer globalLayer, int localBlockStart) =>
      localBlockStart == 0 && spillInBlock(globalLayer) != null;

  /// The global block a display block at [localBlockStart] represents:
  /// the spill-in entry maps to the covering block from the earlier cut,
  /// everything else to the entry at the converted global frame.
  int globalBlockStartFor(Layer globalLayer, int localBlockStart) {
    final spill = spillInBlock(globalLayer);
    if (localBlockStart == 0 && spill != null) {
      return spill.startIndex;
    }
    return toGlobalFrame(localBlockStart);
  }

  /// The read-only cut-local display clone. The transform track is
  /// stripped: its keys are global and would render at wrong local
  /// positions; SE transform lanes stand down for track SE layers until
  /// the lane editing converts through the window too.
  ///
  /// Open-ended on the right (SE globalization): keys at or beyond the
  /// cut end ride too, so the runway shows the neighbours' sounds. The
  /// degenerate no-cut window (duration 0) shows nothing — without a cut
  /// there is no local axis to rebase onto.
  Layer displayLayer(Layer globalLayer) {
    final local = <int, TimelineExposure>{};
    if (cutDurationFrames > 0) {
      globalLayer.timeline.forEach((key, exposure) {
        if (key >= cutStartFrame) {
          local[toLocalFrame(key)] = exposure;
        }
      });
      final spill = spillInBlock(globalLayer);
      if (spill != null) {
        local[0] = TimelineExposure.drawing(
          spill.frameId,
          length: spill.endIndexExclusive - cutStartFrame,
        );
      }
    }
    return globalLayer.copyWith(
      timeline: local,
      // The display clone carries NO FX: this row's lanes live on the
      // track-owned original, and the lane-edit path refuses the clone —
      // FX left on it would composite with diamonds nothing could edit.
      transformTrack: TransformTrack.empty(),
      effects: const [],
    );
  }
}

/// [layer] with every exposure STARTING at or past [endFrameExclusive]
/// dropped — the cut-scoped exports' clip on an open-ended display window
/// (a printed page is no runway). Blocks that start inside and RUN PAST
/// the end keep their true length: the sheet's `~` and the XDTS hold both
/// want the crossing shown, not cut off.
Layer clipLayerStartsBefore(Layer layer, int endFrameExclusive) =>
    layer.copyWith(
      timeline: {
        for (final entry in layer.timeline.entries)
          if (entry.key < endFrameExclusive) entry.key: entry.value,
      },
    );
