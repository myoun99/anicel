import 'audio_clip.dart';
import 'cut.dart';
import 'frame.dart';
import 'frame_id.dart';
import 'layer.dart';
import 'layer_kind.dart';
import 'layer_mark.dart';
import 'layer_section_defaults.dart';
import 'timeline_exposure.dart';
import 'track_id.dart';

/// The result of lifting a legacy track's per-cut SE layers onto the
/// track: the cuts with their SE layers removed, and the merged
/// track-global SE layers (timeline keys on the track's GLOBAL frame
/// axis).
typedef TrackSeLift = ({List<Cut> cuts, List<Layer> seLayers});

/// Migrates the legacy per-cut SE model (pre-`Track.seLayers` files) onto
/// the track's global frame axis.
///
/// Slot-merged: track SE layer *k* is the union of every cut's *k*-th SE
/// layer (the per-cut layer-list order — exactly the positional slots the
/// storyboard used to render). Timeline entries offset by the cut's
/// cumulative global start and CLAMP to the cut's window: legacy playback,
/// export and the storyboard all cut a block off at the cut end, so the
/// clamp reproduces what the file actually played — no audible/visible
/// content is lost, and merged slots can never overlap.
///
/// Deliberate drops, documented for the release notes:
/// - Per-cut SE layer NAMES converge on the track name (`S1`, `S2`, …);
///   a cut with custom-renamed SE rows loses the per-cut label.
/// - Per-cut SE flags (visibility/mute/opacity/mark) take the FIRST cut's
///   values per slot (deterministic; per-cut divergence cannot map onto
///   one global row).
/// - Legacy per-cut SE transform tracks are dropped: their lane keys are
///   cut-local and cannot merge onto the global axis without per-lane key
///   surgery, and the SE transform lanes shipped days before this
///   migration.
TrackSeLift liftCutSeLayersToTrack(TrackId trackId, List<Cut> cuts) {
  final perCutSe = [
    for (final cut in cuts)
      [
        for (final layer in cut.layers)
          if (layer.kind == LayerKind.se) layer,
      ],
  ];
  final starts = <int>[];
  var nextStart = 0;
  for (final cut in cuts) {
    starts.add(nextStart);
    nextStart += cut.duration;
  }
  var slotCount = 0;
  for (final layers in perCutSe) {
    if (layers.length > slotCount) {
      slotCount = layers.length;
    }
  }

  final seLayers = <Layer>[];
  for (var slot = 0; slot < slotCount; slot += 1) {
    final timeline = <int, TimelineExposure>{};
    final frames = <Frame>[];
    final frameIds = <FrameId>{};
    final audioClips = <AudioClip>[];
    Layer? flagSource;

    for (var cutIndex = 0; cutIndex < cuts.length; cutIndex += 1) {
      if (slot >= perCutSe[cutIndex].length) {
        continue;
      }
      final source = perCutSe[cutIndex][slot];
      flagSource ??= source;
      final start = starts[cutIndex];
      final duration = cuts[cutIndex].duration;

      source.timeline.forEach((key, exposure) {
        if (key < 0 || key >= duration) {
          // Entries beyond the cut's played window never showed anywhere.
          return;
        }
        timeline[start + key] = exposure.isDrawing
            ? TimelineExposure.drawing(
                exposure.frameId!,
                length: exposure.length!.clamp(1, duration - key),
              )
            : exposure;
      });
      for (final frame in source.frames) {
        if (frameIds.add(frame.id)) {
          frames.add(frame);
        }
      }
      audioClips.addAll(source.audioClips);
    }

    seLayers.add(
      Layer(
        id: seLayerIdForTrack(trackId, slot + 1),
        name: 'S${slot + 1}',
        frames: frames,
        timeline: timeline,
        audioClips: audioClips,
        kind: LayerKind.se,
        isVisible: flagSource?.isVisible ?? true,
        muted: flagSource?.muted ?? false,
        opacity: flagSource?.opacity ?? 1.0,
        onTimesheet: flagSource?.onTimesheet ?? true,
        mark: flagSource?.mark ?? LayerMark.none,
      ),
    );
  }

  final cutsWithoutSe = [
    for (final cut in cuts)
      if (cut.layers.any((layer) => layer.kind == LayerKind.se))
        cut.copyWith(
          layers: [
            for (final layer in cut.layers)
              if (layer.kind != LayerKind.se) layer,
          ],
        )
      else
        cut,
  ];

  return (
    cuts: cutsWithoutSe,
    seLayers: withEnsuredTrackSeLayers(trackId, seLayers),
  );
}
