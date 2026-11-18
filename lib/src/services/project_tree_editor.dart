import '../core/mapped_or_same.dart';
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
///
/// [items] ITSELF when the step changed nothing ([mappedOrSame]), so every
/// walk below hands back the very parent it was given where nothing under
/// it changed. 🔬Card conte-one-eye-repaints-every-track (11-08): one S
/// row's eye made every track and every cut of the project anew — and the
/// conte's rows, kept while their cuts are the same objects, all built
/// again.
List<T> _replacingOne<T, I>(
  List<T> items,
  ({I id, I Function(T item) of}) picks,
  T Function(T item) update,
  void Function() onFound,
) => mappedOrSame(items, (item) {
  if (picks.of(item) != picks.id) {
    return item;
  }
  onFound();
  return update(item);
});

/// [items] without the one [picks] names, and the element that left.
///
/// ⛔REMOVING IS NOT REPLACING, which is why this is not [_replacingOne]:
/// a remover has to hand the element BACK — the caller undoes with it, and
/// the two removers in `ProjectRepository` each wrote the find, the
/// capture and the removal out again to get it.
({List<T> items, T? removed}) _withoutOne<T, I>(
  Iterable<T> items,
  ({I id, I Function(T item) of}) picks,
) {
  final out = <T>[];
  T? removed;
  for (final item in items) {
    if (removed == null && picks.of(item) == picks.id) {
      removed = item;
      continue;
    }
    out.add(item);
  }
  return (items: out, removed: removed);
}

/// Replaces the track with [trackId] via [update]. Returns `null` if no track
/// matched.
Project? updateTrackById(
  Project project,
  TrackId trackId,
  Track Function(Track track) update,
) {
  var found = false;
  final next = project.withTracksOfEveryTimeline(
    (tracks) => _replacingOne(
      tracks,
      (id: trackId, of: (Track track) => track.id),
      update,
      () => found = true,
    ),
  );
  return found ? next : null;
}

/// Replaces the first cut matching [cutId] (searching every track) via [update].
/// Returns `null` if no cut matched.
///
/// ⛔THE WALK IS THE WHOLE PROJECT, ON PURPOSE. A cut is addressed by id,
/// not by track — a caller that knew the track would have to keep knowing
/// it through every undo, and a linked cut's counterpart lives in another
/// one. Two link commands wrote this out identically, which is two places
/// to forget that a cut can be anywhere.
Project? updateCutAnywhere(
  Project project,
  CutId cutId,
  Cut Function(Cut cut) update,
) {
  var found = false;
  final next = project.withTracksOfEveryTimeline(
    (tracks) => mappedOrSame(tracks, (track) {
      final cuts = _replacingOne(
        track.cuts,
        (id: cutId, of: (Cut cut) => cut.id),
        update,
        () => found = true,
      );
      return identical(cuts, track.cuts) ? track : track.copyWith(cuts: cuts);
    }),
  );
  return found ? next : null;
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
  List<Layer> replaced(List<Layer> layers) => _replacingOne(
    layers,
    (id: layerId, of: (layer) => layer.id),
    update,
    mark,
  );
  final next = _withEveryRowList(project, replaced);
  return found ? next : null;
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
    final frames = _replacingOne(
      layer.frames,
      (id: frameId, of: (Frame frame) => frame.id),
      update,
      () => found = true,
    );
    return identical(frames, layer.frames)
        ? layer
        : layer.copyWith(frames: frames);
  }

  final next = _withEveryRowList(
    project,
    (rows) => mappedOrSame(rows, updateFrames),
  );
  return found ? next : null;
}

/// [project] with every list of rows it holds rebuilt by [rebuild]: each
/// cut's, each track's SE rows and its transition row — every timeline's.
///
/// ⛔The rows `projectLayersAnywhere` walks, which is the law of 「every
/// layer in the project」 (F-131). The TRANSITION row lives on the track
/// beside the SE rows and reaches a cut's row list as a display clone, so a
/// flag command (eye, mark, timesheet) sweeping the visible rows can name
/// it. ↩️The frames' walk wrote this out again without it.
///
/// A track and a cut whose rows [rebuild] hands back as they were stand as
/// they were ([mappedOrSame]).
Project _withEveryRowList(
  Project project,
  List<Layer> Function(List<Layer> rows) rebuild,
) => project.withTracksOfEveryTimeline(
  (tracks) => mappedOrSame(tracks, (track) {
    final cuts = mappedOrSame(track.cuts, (cut) {
      final layers = rebuild(cut.layers);
      return identical(layers, cut.layers) ? cut : cut.copyWith(layers: layers);
    });
    final seLayers = rebuild(track.seLayers);
    final transitionLayer = rebuild([track.transitionLayer]).single;
    return identical(cuts, track.cuts) &&
            identical(seLayers, track.seLayers) &&
            identical(transitionLayer, track.transitionLayer)
        ? track
        : track.copyWith(
            cuts: cuts,
            seLayers: seLayers,
            transitionLayer: transitionLayer,
          );
  }),
);

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
  if (!found) {
    return null;
  }
  return identical(layers, cut.layers) ? cut : cut.copyWith(layers: layers);
}

/// Removes the cut matching [cutId] from whichever track holds it, and
/// hands it back. `removed` is null when no track held it.
({Project project, Cut? removed}) removeCutAnywhere(
  Project project,
  CutId cutId,
) {
  Cut? removed;
  final next = project.withTracksOfEveryTimeline(
    (tracks) => mappedOrSame(tracks, (track) {
      if (removed != null) {
        return track;
      }
      final without = _withoutOne(track.cuts, (
        id: cutId,
        of: (Cut cut) => cut.id,
      ));
      removed = without.removed;
      return removed == null ? track : track.copyWith(cuts: without.items);
    }),
  );
  return (project: next, removed: removed);
}

/// Removes the layer matching [layerId] from [cut] and hands it back.
/// `removed` is null when the cut had no such layer.
({Cut cut, Layer? removed}) removeLayerFromCut(Cut cut, LayerId layerId) {
  final without = _withoutOne(cut.layers, (
    id: layerId,
    of: (Layer layer) => layer.id,
  ));
  return (
    cut: without.removed == null ? cut : cut.copyWith(layers: without.items),
    removed: without.removed,
  );
}
