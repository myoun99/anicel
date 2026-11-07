import 'package:collection/collection.dart' show IterableExtension;

import '../../models/brush_frame_key.dart';
import '../../models/cel_bank_lanes.dart' show laneBlockStarts;
import '../../models/conte/conte_ink_keys.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/envelope/cut_envelope_ink_keys.dart';
import '../../models/timesheet_ink_keys.dart';
import '../../models/viewer_ink_keys.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/media_asset.dart' show mediaFileShownName;
import '../../models/project.dart';
import '../../models/project_timeline.dart';
import '../../models/track.dart';
import '../project_lookup.dart' show projectLayersWithOwners;

/// Where a picture the brush stores keep sits in a project, by the names a
/// person finds it by there.
///
/// 🚨★★★**A SAVE THAT COULD NOT CARRY PICTURES SAYS WHICH** (C-save-percent).
/// 유저 2026-09-11, on an iPad: 「저장시 그림 1장 사라졌다고뜸 … 다시 앱
/// 재실행해서 프로젝트 여니 그림 사라졋다하는데 뭐가 사라진지 모르겠음 …
/// 사라진 그림이 뭔지 이름 리스트로 표시하는게 필요해보임」. A count alone
/// sent them looking through a project that looked whole.
sealed class CelPlace {
  const CelPlace();
}

/// What holds a row, by the name a person finds it by: its cut, or the
/// track for a row the track owns (an SE row) — and the timeline it is in,
/// where that is not the open one.
///
/// ONE naming for every list that sends a person to a row — the pictures a
/// save could not carry, the uses of a media pool file (F-118) and the
/// places a link reaches (I-25).
///
/// 🗣️I-150 (유저 2026-11-03): 「컷의 링크버튼 누르거나 뭐 아무튼 그런
/// 소재위치 표시할때 트랙위치도 표시」. It names the timeline only away from
/// the open one — board I-150-Q3's recommended answer, asked and not yet
/// answered: one rule for the screen and the print.
final class PlaceOwner {
  const PlaceOwner(this.name, {this.away});

  final String name;

  /// The timeline holding it, when that is not the open one.
  final ProjectTimeline? away;
}

/// What holds a row in [project]: its [cut], or the [track] for a row the
/// track owns — in whichever timeline holds the track.
PlaceOwner placeOwnerOf(
  Project project, {
  required Track track,
  required Cut? cut,
}) {
  bool holds(ProjectTimeline timeline) =>
      timeline.tracks.any((held) => held.id == track.id);
  return PlaceOwner(
    cut?.name ?? track.name,
    away: holds(project.currentTimeline)
        ? null
        : project.timelines.firstWhereOrNull(holds),
  );
}

/// A drawing on a row: named by what holds the row — its cut, or the track
/// for a row the track owns (an SE row) — the row, and [celName].
final class DrawingCelPlace extends CelPlace {
  const DrawingCelPlace({
    required this.owner,
    required this.layerName,
    required this.celName,
    required this.blockStarts,
  });

  final PlaceOwner owner;
  final String layerName;

  /// What the timeline prints where the drawing's block starts
  /// ([celNumberOrMark]).
  final String celName;

  /// The frames its blocks start on, on its row's own axis, in order
  /// ([laneBlockStarts]) — a cut's frames, or the track's for a row the
  /// track owns: the frames the ruler over that row counts. Where a person
  /// finds it on the row (F-284): an SE block has no name to be found by,
  /// and a name shown on several blocks does not say which. Empty for a
  /// drawing no block shows.
  final List<int> blockStarts;
}

/// The drawings of ONE row, each as [DrawingCelPlace] names it: [layer],
/// held by [owner].
///
/// A row's object and not a function of a row and a drawing, because where
/// a drawing's blocks start is ONE walk of the row's lane however many of
/// its drawings are asked for — a save that could not carry a row's
/// thousand pictures asks a thousand times.
final class RowDrawingPlaces {
  RowDrawingPlaces({required PlaceOwner owner, required Layer layer})
    : _owner = owner,
      _layer = layer;

  final PlaceOwner _owner;
  final Layer _layer;
  late final _blockStarts = laneBlockStarts(_layer.timeline);

  DrawingCelPlace of(Frame frame) => DrawingCelPlace(
    owner: _owner,
    layerName: _layer.name,
    celName: celNumberOrMark(frame.name, kind: _layer.kind),
    blockStarts: _blockStarts[frame.id] ?? const [],
  );
}

/// Conte handwriting of one storyboard block: its cut, and the drawing the
/// block shows.
final class ConteRowInkPlace extends CelPlace {
  const ConteRowInkPlace({required this.owner, required this.celName});

  /// Its cut.
  final PlaceOwner owner;
  final String celName;
}

/// Ink in a box of one cut's envelope.
final class EnvelopeInkPlace extends CelPlace {
  const EnvelopeInkPlace(this.owner);

  /// Its cut.
  final PlaceOwner owner;
}

/// Ink on a page of one cut's timesheet — the third sheet, said as the
/// envelope's is (I-97: a photo on a page is a use of its pool file).
final class TimesheetInkPlace extends CelPlace {
  const TimesheetInkPlace(this.owner);

  /// Its cut.
  final PlaceOwner owner;
}

/// Ink on a page of a file the project carries, written in a viewer
/// (I-114) — named by the file, as the pool names it.
final class ViewerInkPlace extends CelPlace {
  const ViewerInkPlace(this.fileName);

  final String fileName;
}

/// A picture the project holds no place for any more: its drawing, its row
/// or its cut is gone.
final class GoneCelPlace extends CelPlace {
  const GoneCelPlace();
}

/// Where each of [keys] sits in [project] — ONE place per key, so the list
/// is exactly as long as the count a notice gives.
///
/// In the order a person meets them: drawings as the project holds its rows
/// ([projectLayersWithOwners]), then the ink over storyboard drawings, in
/// envelopes and on timesheets by cut, on the files the viewers wrote on —
/// and last, what holds no place.
List<CelPlace> celPlacesOf(Project project, Iterable<BrushFrameKey> keys) => [
  for (final (_, place) in celPlacesByKey(project, keys)) place,
];

/// [celPlacesOf], each place beside the key it was asked for.
List<(BrushFrameKey, CelPlace)> celPlacesByKey(
  Project project,
  Iterable<BrushFrameKey> keys,
) {
  final index = _CelPlaceIndex(project);
  final found = [for (final key in keys) (key, index.placeOf(key))]
    ..sort((a, b) {
      final byPlane = a.$2.plane.index.compareTo(b.$2.plane.index);
      return byPlane != 0 ? byPlane : a.$2.position.compareTo(b.$2.position);
    });
  return [for (final (key, entry) in found) (key, entry.place)];
}

enum _Plane { drawing, conteRow, envelope, timesheet, viewer, gone }

typedef _Found = ({_Plane plane, int position, CelPlace place});

/// Every place [celPlacesOf] can answer with, found by the ids a key
/// carries — one walk of the project.
class _CelPlaceIndex {
  _CelPlaceIndex(Project project) {
    for (final asset in project.mediaAssets) {
      if (asset.carriedAs case final carry?) {
        _viewers[carry] = (
          plane: _Plane.viewer,
          position: _viewers.length,
          place: ViewerInkPlace(mediaFileShownName(asset, asset.path)),
        );
      }
    }
    for (final owned in projectLayersWithOwners(project)) {
      final cut = owned.cut;
      final owner = placeOwnerOf(project, track: owned.track, cut: cut);
      if (cut != null) {
        _envelopes[cut.id] ??= (
          plane: _Plane.envelope,
          position: _envelopes.length,
          place: EnvelopeInkPlace(owner),
        );
        _timesheets[cut.id] ??= (
          plane: _Plane.timesheet,
          position: _timesheets.length,
          place: TimesheetInkPlace(owner),
        );
      }
      final drawings = <FrameId, DrawingCelPlace>{};
      final row = RowDrawingPlaces(owner: owner, layer: owned.layer);
      for (final frame in owned.layer.frames) {
        final drawing = row.of(frame);
        _drawings[(owned.layer.id, frame.id)] = (
          plane: _Plane.drawing,
          position: _drawings.length,
          place: drawing,
        );
        drawings[frame.id] = drawing;
      }
      // A block's handwriting, over the drawing the block shows.
      for (final exposure in owned.layer.timeline.values) {
        final inkId = exposure.memo?.inkId ?? '';
        final drawing = drawings[exposure.frameId];
        if (cut == null || inkId.isEmpty || drawing == null) {
          continue;
        }
        _rows[(cut.id, inkId)] = (
          plane: _Plane.conteRow,
          position: _rows.length,
          place: ConteRowInkPlace(owner: owner, celName: drawing.celName),
        );
      }
    }
  }

  final _drawings = <(LayerId, FrameId), _Found>{};
  final _rows = <(CutId, String), _Found>{};
  final _envelopes = <CutId, _Found>{};
  final _timesheets = <CutId, _Found>{};
  final _viewers = <String, _Found>{};

  _Found placeOf(BrushFrameKey key) {
    final found = isConteInkRowKey(key)
        ? _rows[(key.cutId, conteInkRowIdOf(key)!)]
        : isEnvelopeInkKey(key)
        ? _envelopes[key.cutId]
        : isTimesheetInkKey(key)
        ? _timesheets[key.cutId]
        : isViewerInkKey(key)
        ? _viewers[viewerInkCarryOf(key)]
        : _drawings[key.cel];
    return found ??
        (plane: _Plane.gone, position: 0, place: const GoneCelPlace());
  }
}
