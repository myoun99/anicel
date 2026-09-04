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
/// One step of every walk below: [items] with the single element whose id
/// is [id] replaced by [update], and [onFound] called when it was there.
///
/// ⛔SEVEN PLACES WROTE THIS OUT — a track, a cut, two layer lists, the
/// transition row and frames in two places — and each carried its own
/// `found = true`. A step that forgets to flag returns a REBUILT project
/// that reports "nothing matched", so the caller throws over an edit that
/// actually landed. The flag and the replacement are one step here, which
/// is the only way they cannot come apart.
List<T> _replacingOne<T, I>(
  Iterable<T> items,
  ({I id, I Function(T item) of}) picks,
  T Function(T item) update,
  void Function() onFound,
) {
  final out = <T>[];
  for (final item in items) {
    if (picks.of(item) != picks.id) {
      out.add(item);
      continue;
    }
    onFound();
    out.add(update(item));
  }
  return out;
}

/// Replaces the track with [trackId] via [update]. Returns `null` if no track
/// matched.
Project? updateTrackById(
  Project project,
  TrackId trackId,
  Track Function(Track track) update,
) {
  var found = false;
  final tracks = _replacingOne(
    project.tracks,
    (id: trackId, of: (Track track) => track.id),
    update,
    () => found = true,
  );
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
  final tracks = [
    for (final track in project.tracks)
      track.copyWith(
        cuts: _replacingOne(
          track.cuts,
          (id: cutId, of: (cut) => cut.id),
          update,
          () => found = true,
        ),
      ),
  ];
  return found ? project.copyWith(tracks: tracks) : null;
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
  void mark() => found = true;
  List<Layer> replaced(Iterable<Layer> layers) => _replacingOne(
    layers,
    (id: layerId, of: (layer) => layer.id),
    update,
    mark,
  );
  final tracks = [
    for (final track in project.tracks)
      track.copyWith(
        cuts: [
          for (final cut in track.cuts)
            cut.copyWith(layers: replaced(cut.layers)),
        ],
        seLayers: replaced(track.seLayers),
        // The TRANSITION row lives on the track beside the SE rows and
        // reaches a cut's row list as a display clone, so a flag command
        // (eye, mark, timesheet) sweeping the visible rows can name it.
        transitionLayer: replaced([track.transitionLayer]).single,
      ),
  ];
  return found ? project.copyWith(tracks: tracks) : null;
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
  Layer updateFrames(Layer layer) => layer.copyWith(
    frames: _replacingOne(
      layer.frames,
      (id: frameId, of: (frame) => frame.id),
      update,
      () => found = true,
    ),
  );
  final tracks = [
    for (final track in project.tracks)
      track.copyWith(
        cuts: [
          for (final cut in track.cuts)
            cut.copyWith(layers: cut.layers.map(updateFrames).toList()),
        ],
        seLayers: track.seLayers.map(updateFrames).toList(),
      ),
  ];
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
  final layers = _replacingOne(
    cut.layers,
    (id: layerId, of: (Layer layer) => layer.id),
    update,
    () => found = true,
  );
  return found ? cut.copyWith(layers: layers) : null;
}
