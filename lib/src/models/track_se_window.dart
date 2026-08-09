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

  /// The cut-local display clone. The transform track and effect chain are
  /// REBASED onto the local axis (R5 #8) rather than stripped: their keys
  /// are global, so showing them raw would draw diamonds at wrong local
  /// frames — but dropping them left the row with lanes nothing could
  /// key, which is the bug the user reported.
  ///
  /// The trip back out is [globalTransformTrack] / [globalEffects]: an
  /// edit arrives against THIS clone and must be converted before it
  /// touches the track-owned original, or a cut-local frame lands on the
  /// global axis.
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
      transformTrack: _rebasedTrack(globalLayer.transformTrack, toLocal: true),
      effects: _rebasedEffects(globalLayer.effects, toLocal: true),
      seNameTag: globalLayer.seNameTag?.track == null
          ? globalLayer.seNameTag
          : globalLayer.seNameTag!.copyWith(
              track: _rebasedNameTag(
                globalLayer.seNameTag!.track!,
                toLocal: true,
              ),
            ),
    );
  }

  /// [localTrack] — edited against [displayLayer] — put back on the global
  /// axis, ready to commit onto the track-owned layer (R5 #8).
  TransformTrack globalTransformTrack(TransformTrack localTrack) =>
      _rebasedTrack(localTrack, toLocal: false);

  /// The effect-chain twin of [globalTransformTrack].
  List<LayerEffect> globalEffects(List<LayerEffect> localEffects) =>
      _rebasedEffects(localEffects, toLocal: false);

  /// Every key of [track] shifted by one cut start, in either direction.
  ///
  /// Keys landing BEFORE local 0 are dropped on the way in: they belong to
  /// an earlier cut and have no row here to sit on. Nothing is dropped on
  /// the way out — the caller only ever hands back what it was shown, so a
  /// negative would mean the local axis itself was wrong.
  /// ONE lane's keys shifted by a cut start, in either direction — the
  /// primitive every rebase below is made of.
  PropertyTrack<T> _shift<T>(PropertyTrack<T> lane, {required bool toLocal}) {
    final moved = <int, PropertyKey<T>>{};
    for (final entry in lane.keys.entries) {
      final frame = toLocal
          ? toLocalFrame(entry.key)
          : toGlobalFrame(entry.key);
      if (toLocal && frame < 0) {
        continue;
      }
      moved[frame] = entry.value;
    }
    return PropertyTrack<T>(keys: moved);
  }

  /// The NAME TAG twin of [globalTransformTrack] (R5 #7): its members key
  /// on the same global axis and its lanes are read off the same cut-local
  /// clone, so it takes the same trip.
  SeNameTagTrack globalSeNameTagTrack(SeNameTagTrack localTrack) =>
      _rebasedNameTag(localTrack, toLocal: false);

  SeNameTagTrack _rebasedNameTag(
    SeNameTagTrack track, {
    required bool toLocal,
  }) {
    if (cutStartFrame == 0) {
      return track;
    }
    return SeNameTagTrack(
      fontSize: _shift(track.fontSize, toLocal: toLocal),
      letterSpacing: _shift(track.letterSpacing, toLocal: toLocal),
      bold: _shift(track.bold, toLocal: toLocal),
      nameInk: _shift(track.nameInk, toLocal: toLocal),
      boxColor: _shift(track.boxColor, toLocal: toLocal),
      lineInk: _shift(track.lineInk, toLocal: toLocal),
      showLine: _shift(track.showLine, toLocal: toLocal),
    );
  }

  TransformTrack _rebasedTrack(TransformTrack track, {required bool toLocal}) {
    if (cutStartFrame == 0) {
      return track;
    }
    PropertyTrack<T> shift<T>(PropertyTrack<T> lane) =>
        _shift(lane, toLocal: toLocal);

    return track.copyWith(
      anchorPoint: shift(track.anchorPoint),
      position: shift(track.position),
      scale: shift(track.scale),
      rotation: shift(track.rotation),
      opacity: shift(track.opacity),
    );
  }

  List<LayerEffect> _rebasedEffects(
    List<LayerEffect> effects, {
    required bool toLocal,
  }) {
    if (cutStartFrame == 0 || effects.isEmpty) {
      return effects;
    }
    return [
      for (final effect in effects)
        effect.copyWith(
          parameters: {
            for (final entry in effect.parameters.entries)
              entry.key: entry.value.copyWith(
                track: () {
                  final moved = <int, PropertyKey<double>>{};
                  for (final key in entry.value.track.keys.entries) {
                    final frame = toLocal
                        ? toLocalFrame(key.key)
                        : toGlobalFrame(key.key);
                    if (toLocal && frame < 0) {
                      continue;
                    }
                    moved[frame] = key.value;
                  }
                  return PropertyTrack<double>(keys: moved);
                }(),
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
