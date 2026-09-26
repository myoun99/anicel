import '../../core/collection_equality.dart' show listsMatch;
import '../../models/layer.dart';
import '../../models/media_asset.dart' show normalizedMediaPath;
import '../../models/project.dart';
import '../../models/timesheet_info.dart';
import '../../models/track.dart';

/// [project] with every reference to a moved media file following it —
/// [moved] maps a file's old path to its new one: its pool entry, the clips
/// that play it, the rows that show it (`Layer.mediaReference`) and the
/// pictures the sheets print from it ([WorkPicture]).
///
/// 🚨ONE walk for every way a file's path changes: a relink (the file was
/// found somewhere else — `RelinkMediaAssetCommand`) and a load (the folder
/// travelled, or a bookmark found the file). They were two walks, and the
/// load's missed the rows' media references: the project opened with its
/// pool at the file's new place and its rows at the old one — the failure
/// a relink's own pin names (「a walk that missed one leaves a layer
/// pointing at a file that is not there」).
///
/// ⚠️Untouched tracks, cuts and layers keep their IDENTITY: downstream
/// caches key off it, and rebuilding what did not change is how a relink of
/// one clip re-decodes a film.
Project projectWithMediaMoved(Project project, Map<String, String> moved) {
  if (moved.isEmpty) {
    return project;
  }
  // In the pool's one spelling, which every reference keeps: a load's moves
  // arrive as its manifest spelled them, backslashes and all
  // (`MediaFingerprints.moved` meets the same keys).
  final moves = {
    for (final MapEntry(:key, :value) in moved.entries)
      normalizedMediaPath(key): normalizedMediaPath(value),
  };
  final tracks = [
    for (final track in project.tracks) _trackMoved(track, moves),
  ];
  var info = project.timesheetInfo;
  for (final picture in WorkPicture.values) {
    final path = picture.pathIn(info);
    final to = path == null ? null : moves[normalizedMediaPath(path)];
    if (to != null) {
      info = picture.withPath(info, to);
    }
  }
  return project.copyWith(
    mediaAssets: _eachMoved(
      project.mediaAssets,
      moves,
      pathOf: (asset) => asset.path,
      // 🚨copyWith keeps what it is NOT given, so a move takes the path and
      // leaves whatever source tracking the asset already had. ⛔It writes
      // none: a move says 「the same file is over here now」, and where a
      // copy came from is the copy's business — see `MediaAsset.sourcePath`.
      movedTo: (asset, to) => asset.copyWith(path: to),
    ),
    tracks: listsMatch(tracks, project.tracks, identical)
        ? project.tracks
        : tracks,
    timesheetInfo: info,
  );
}

Track _trackMoved(Track track, Map<String, String> moves) {
  final seLayers = _layersMoved(track.seLayers, moves);
  final cuts = [
    for (final cut in track.cuts)
      switch (_layersMoved(cut.layers, moves)) {
        final layers when identical(layers, cut.layers) => cut,
        final layers => cut.copyWith(layers: layers),
      },
  ];
  if (identical(seLayers, track.seLayers) &&
      listsMatch(cuts, track.cuts, identical)) {
    return track;
  }
  return track.copyWith(seLayers: seLayers, cuts: cuts);
}

/// [layers] following [moves] — [layers] itself when none of them plays or
/// shows a moved file.
List<Layer> _layersMoved(List<Layer> layers, Map<String, String> moves) {
  final moved = [for (final layer in layers) _layerMoved(layer, moves)];
  return listsMatch(moved, layers, identical) ? layers : moved;
}

Layer _layerMoved(Layer layer, Map<String, String> moves) {
  final reference = layer.mediaReference;
  final referenceTo = reference == null ? null : moves[reference.assetPath];
  if (referenceTo == null &&
      !layer.audioClips.any((clip) => moves.containsKey(clip.filePath))) {
    return layer;
  }
  return layer.copyWith(
    audioClips: _eachMoved(
      layer.audioClips,
      moves,
      pathOf: (clip) => clip.filePath,
      movedTo: (clip, to) => clip.copyWith(filePath: to),
    ),
    mediaReference: referenceTo == null
        ? reference
        : reference!.copyWith(assetPath: referenceTo),
  );
}

/// [items], each one whose file [moves] names following it.
List<T> _eachMoved<T>(
  List<T> items,
  Map<String, String> moves, {
  required String Function(T item) pathOf,
  required T Function(T item, String to) movedTo,
}) => [
  for (final item in items)
    if (moves[pathOf(item)] case final to?) movedTo(item, to) else item,
];
