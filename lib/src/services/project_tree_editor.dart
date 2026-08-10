import '../models/cut.dart';
import '../models/cut_id.dart';
import '../models/frame.dart';
import '../models/frame_id.dart';
import '../models/layer.dart';
import '../models/layer_id.dart';
import '../models/project.dart';
import '../models/track.dart';
import '../models/track_id.dart';

/// Focused immutable-tree edit helpers for the `Project` -> `Track` -> `Cut` ->
/// `Layer` -> `Frame` hierarchy.
///
/// Each helper rebuilds only the spine down to the targeted entity and returns
/// the new parent, or `null` when nothing matched — letting the caller decide
/// which not-found error to raise (and, because the caller throws before any
/// reassignment, leaving the source unchanged on failure). This replaces the
/// hand-inlined nested `.map()` chains that were duplicated across every
/// mutation in `ProjectRepository`. It is deliberately not a general optics /
/// lens library — just the handful of traversals this project needs.

/// Replaces the track with [trackId] via [update]. Returns `null` if no track
/// matched.
Project? updateTrackById(
  Project project,
  TrackId trackId,
  Track Function(Track track) update,
) {
  var found = false;
  final tracks = project.tracks
      .map((track) {
        if (track.id != trackId) {
          return track;
        }
        found = true;
        return update(track);
      })
      .toList(growable: false);
  return found ? project.copyWith(tracks: tracks) : null;
}

/// Replaces the first cut matching [cutId] (searching every track) via [update].
/// Returns `null` if no cut matched.
Project? updateCutAnywhere(
  Project project,
  CutId cutId,
  Cut Function(Cut cut) update,
) {
  var found = false;
  final tracks = project.tracks
      .map((track) {
        final cuts = track.cuts
            .map((cut) {
              if (cut.id != cutId) {
                return cut;
              }
              found = true;
              return update(cut);
            })
            .toList(growable: false);
        return track.copyWith(cuts: cuts);
      })
      .toList(growable: false);
  return found ? project.copyWith(tracks: tracks) : null;
}

/// Replaces the layer matching [layerId] within [cut] via [update]. Returns
/// `null` if the cut has no such layer.
Cut? updateLayerInCut(
  Cut cut,
  LayerId layerId,
  Layer Function(Layer layer) update,
) {
  var found = false;
  final layers = cut.layers
      .map((layer) {
        if (layer.id != layerId) {
          return layer;
        }
        found = true;
        return update(layer);
      })
      .toList(growable: false);
  return found ? cut.copyWith(layers: layers) : null;
}

/// Replaces the first layer matching [layerId] — searching every cut AND
/// every track's SE rows — via [update]. Returns `null` if no layer
/// matched. Track-owned SE layers resolve through this same seam, so
/// every layer command (timeline edits, flags, audio clips, renames)
/// reaches them without knowing where the layer lives.
Project? updateLayerAnywhere(
  Project project,
  LayerId layerId,
  Layer Function(Layer layer) update,
) {
  var found = false;
  final tracks = project.tracks
      .map((track) {
        final cuts = track.cuts
            .map((cut) {
              final layers = cut.layers
                  .map((layer) {
                    if (layer.id != layerId) {
                      return layer;
                    }
                    found = true;
                    return update(layer);
                  })
                  .toList(growable: false);
              return cut.copyWith(layers: layers);
            })
            .toList(growable: false);
        final seLayers = track.seLayers
            .map((layer) {
              if (layer.id != layerId) {
                return layer;
              }
              found = true;
              return update(layer);
            })
            .toList(growable: false);
        // The TRANSITION row lives on the track beside the SE rows and
        // reaches a cut's row list as a display clone, so a flag command
        // (eye, mark, timesheet) sweeping the visible rows can name it.
        final transition = track.transitionLayer.id == layerId
            ? (() {
                found = true;
                return update(track.transitionLayer);
              })()
            : track.transitionLayer;
        return track.copyWith(
          cuts: cuts,
          seLayers: seLayers,
          transitionLayer: transition,
        );
      })
      .toList(growable: false);
  return found ? project.copyWith(tracks: tracks) : null;
}

/// Replaces the frame matching [frameId] within [layer] via [update]. Returns
/// `null` if the layer has no such frame.
Layer? updateFrameInLayer(
  Layer layer,
  FrameId frameId,
  Frame Function(Frame frame) update,
) {
  var found = false;
  final frames = layer.frames
      .map((frame) {
        if (frame.id != frameId) {
          return frame;
        }
        found = true;
        return update(frame);
      })
      .toList(growable: false);
  return found ? layer.copyWith(frames: frames) : null;
}

/// Replaces the first frame matching [frameId] — searching every layer,
/// the tracks' SE rows included — via [update]. Returns `null` if no
/// frame matched.
Project? updateFrameAnywhere(
  Project project,
  FrameId frameId,
  Frame Function(Frame frame) update,
) {
  var found = false;
  Layer updateFrames(Layer layer) {
    final frames = layer.frames
        .map((frame) {
          if (frame.id != frameId) {
            return frame;
          }
          found = true;
          return update(frame);
        })
        .toList(growable: false);
    return layer.copyWith(frames: frames);
  }

  final tracks = project.tracks
      .map((track) {
        final cuts = track.cuts
            .map((cut) {
              final layers = cut.layers
                  .map(updateFrames)
                  .toList(growable: false);
              return cut.copyWith(layers: layers);
            })
            .toList(growable: false);
        final seLayers = track.seLayers
            .map(updateFrames)
            .toList(growable: false);
        return track.copyWith(cuts: cuts, seLayers: seLayers);
      })
      .toList(growable: false);
  return found ? project.copyWith(tracks: tracks) : null;
}
