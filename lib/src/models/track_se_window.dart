import 'layer.dart';
import 'timeline_coverage.dart';
import 'timeline_exposure.dart';
import 'layer_effect.dart';
import 'property_track.dart';
import 'se_name_tag.dart';
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

  /// How far into the spill-in block — and the sound it carries — the
  /// window's first frame already is, or null when nothing spills in.
  ///
  /// 🚨F-113 (2026-09-15): the display clone restarts that block at local 0,
  /// so nothing read off the clone alone can know this — its waveform was
  /// drawn from the file's first frame while the storyboard and playback,
  /// which read the track's own row, placed the sound right.
  int? spillInLeadFrames(Layer globalLayer) {
    final spill = spillInBlock(globalLayer);
    return spill == null ? null : cutStartFrame - spill.startIndex;
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

  /// The cut-local display clone. The transform track, the effect chain and
  /// the name tag's keys are REBASED onto the local axis (R5 #8) rather than
  /// stripped: their keys are global, so showing them raw would draw
  /// diamonds at wrong local frames — but dropping them left the row with
  /// lanes nothing could key, which is the bug the user reported.
  ///
  /// 🚨★★★The clone is what the cut's RAIL shows — the keys INSIDE the cut —
  /// and nothing more (F-102, 2026-09-15). A key an earlier cut made has no
  /// frame here (a key index is never negative: `nonNegativeIndexedCopy`),
  /// yet it still holds the value into this cut. So a VALUE is never read
  /// off this clone: it is read off the track's row at the global frame
  /// (`LaneVerbs.laneValueSourceAt`). Reading it here is why cut 2 showed
  /// S1's position at its default — 유저 「컷1에서 se의 트랜스폼으로 포지션
  /// 조정했는데, 그게 다른 컷2에서 값이 안바뀌어 있고 초기값인 상태로 보임」.
  ///
  /// ⛔THE TRIP BACK OUT IS GONE (F-102). `globalTransformTrack`,
  /// `globalEffects` and `globalSeNameTagTrack` put an edit made against this
  /// clone back through the window, and the keys the clone had dropped never
  /// came back: keying S1 in cut 2 erased the key cut 1 made. Every edit
  /// writes the row the project holds, at the frame on its own axis
  /// (`LaneVerbs.laneVerbLayerFor`) — the clone is never written back, which
  /// is what this class always said.
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
      transformTrack: _rebasedTrack(globalLayer.transformTrack),
      effects: _rebasedEffects(globalLayer.effects),
      seNameTag: globalLayer.seNameTag?.track == null
          ? globalLayer.seNameTag
          : globalLayer.seNameTag!.copyWith(
              track: _rebasedNameTag(globalLayer.seNameTag!.track!),
            ),
    );
  }

  /// ONE lane's keys moved onto the local axis — the primitive every rebase
  /// below is made of.
  ///
  /// Keys landing BEFORE local 0 are dropped: they belong to an earlier cut
  /// and have no frame on this rail. The value such a key holds into the cut
  /// is read off the track's row, never off this clone — see [displayLayer].
  PropertyTrack<T> _shift<T>(PropertyTrack<T> lane) => PropertyTrack<T>(
    keys: {
      for (final entry in lane.keys.entries)
        if (entry.key >= cutStartFrame) toLocalFrame(entry.key): entry.value,
    },
  );

  SeNameTagTrack _rebasedNameTag(SeNameTagTrack track) {
    if (cutStartFrame == 0) {
      return track;
    }
    return SeNameTagTrack(
      fontSize: _shift(track.fontSize),
      letterSpacing: _shift(track.letterSpacing),
      bold: _shift(track.bold),
      nameInk: _shift(track.nameInk),
      boxColor: _shift(track.boxColor),
      lineInk: _shift(track.lineInk),
      showLine: _shift(track.showLine),
    );
  }

  TransformTrack _rebasedTrack(TransformTrack track) {
    if (cutStartFrame == 0) {
      return track;
    }
    return track.copyWith(
      anchorPoint: _shift(track.anchorPoint),
      position: _shift(track.position),
      scale: _shift(track.scale),
      rotation: _shift(track.rotation),
      opacity: _shift(track.opacity),
    );
  }

  List<LayerEffect> _rebasedEffects(List<LayerEffect> effects) {
    if (cutStartFrame == 0 || effects.isEmpty) {
      return effects;
    }
    return [
      for (final effect in effects)
        effect.copyWith(
          parameters: {
            for (final entry in effect.parameters.entries)
              entry.key: entry.value.copyWith(
                track: _shift(entry.value.track),
              ),
          },
        ),
    ];
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
