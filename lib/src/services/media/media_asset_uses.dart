import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
import '../../models/project.dart';
import '../../models/track_id.dart';
import '../persistence/cel_places.dart' show DrawingCelPlace, rowOwnerName;
import '../project_lookup.dart' show projectLayersWithOwners;

/// Where a project uses a file of its media pool, by the names a person
/// finds it by there (F-118).
///
/// 유저 2026-09-12: 「미디어풀의 타임라인에서 쓰는중 버튼, 정확히 어디서
/// 쓰는건지 모르겠음. 해당 버튼 누르면 공용창 띄워서 어디서 쓰는지 리스트로
/// 표시하도록. 그리고 풀에서 그냥 제거버튼 누르면 사용중인데 제거하겠습니까?
/// 배치한 레이어/프레임이 삭제됩니다. 라고 표시해서 강제삭제할수있게」.
///
/// 🚨ONE answer for all three: the pool row's in-use mark is this list not
/// being empty, the window the mark opens shows it, and removing the file
/// asks about it and takes exactly it away.
sealed class MediaAssetUse {
  const MediaAssetUse();
}

/// A row placed from the file — a movie, a still or a sequence kept as a
/// reference — which points at it (`Layer.mediaReference`).
final class RowMediaUse extends MediaAssetUse {
  const RowMediaUse({
    required this.cutId,
    required this.layerId,
    required this.ownerName,
    required this.layerName,
  });

  final CutId cutId;
  final LayerId layerId;
  final String ownerName;
  final String layerName;
}

/// A frame that carries the file as its sound (an `AudioClip` linked to
/// it).
final class FrameMediaUse extends MediaAssetUse {
  const FrameMediaUse({
    required this.trackId,
    required this.cutId,
    required this.layerId,
    required this.frameId,
    required this.place,
  });

  /// The track the row belongs to: its owner for a row the track owns, the
  /// track of its cut otherwise.
  final TrackId trackId;

  /// The cut holding the row; null for a row the track owns (an SE row).
  final CutId? cutId;
  final LayerId layerId;
  final FrameId frameId;
  final DrawingCelPlace place;
}

/// Every use [project] has of the file at [path], in the order the project
/// holds its rows — lazily, so asking whether there is one stops at the
/// first.
///
/// A sound counts on a frame its row still holds (REC1-A): a link to a frame
/// that is gone plays nothing anywhere, so it must not hold the pool
/// hostage. A frame linking the file twice is one use.
///
/// ⚠️A row counts in a CUT. A track's own rows are its SE rows and its
/// transition row, made by the track: no verb puts a reference on one (the
/// placement planners, the layer paste and the cut duplicate all write a
/// cut's rows), so there is no row of the track a person could be sent to,
/// or that a removal could delete.
Iterable<MediaAssetUse> mediaAssetUsesOf(Project project, String path) sync* {
  for (final owned in projectLayersWithOwners(project)) {
    final layer = owned.layer;
    final cut = owned.cut;
    if (cut != null && layer.mediaReference?.assetPath == path) {
      yield RowMediaUse(
        cutId: cut.id,
        layerId: layer.id,
        ownerName: rowOwnerName(track: owned.track, cut: cut),
        layerName: layer.name,
      );
    }
    final linked = {
      for (final clip in layer.audioClips)
        if (clip.filePath == path) clip.frameId,
    };
    if (linked.isEmpty) {
      continue;
    }
    for (final frame in layer.frames) {
      if (linked.contains(frame.id)) {
        yield FrameMediaUse(
          trackId: owned.track.id,
          cutId: cut?.id,
          layerId: layer.id,
          frameId: frame.id,
          place: DrawingCelPlace.at(
            track: owned.track,
            cut: cut,
            layer: layer,
            frame: frame,
          ),
        );
      }
    }
  }
}
