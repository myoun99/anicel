import '../../models/brush_frame_key.dart';
import '../../models/cel_bank_lanes.dart' show laneBlockStarts;
import '../../models/conte/conte_ink_keys.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/envelope/cut_envelope_ink_keys.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/project.dart';
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

/// What holds a row, by the name a person finds it by: its [cut], or the
/// [track] for a row the track owns (an SE row).
///
/// ONE naming for every list that sends a person to a row — the pictures a
/// save could not carry, and the uses of a media pool file (F-118).
String rowOwnerName({required Track track, required Cut? cut}) =>
    cut?.name ?? track.name;

/// A drawing on a row: named by what holds the row — its cut, or the track
/// for a row the track owns (an SE row) — the row, and [celName].
final class DrawingCelPlace extends CelPlace {
  const DrawingCelPlace({
    required this.ownerName,
    required this.layerName,
    required this.celName,
    required this.blockStarts,
  });

  final String ownerName;
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
/// held by [cut] — or by [track] when the track owns the row.
///
/// A row's object and not a function of a row and a drawing, because where
/// a drawing's blocks start is ONE walk of the row's lane however many of
/// its drawings are asked for — a save that could not carry a row's
/// thousand pictures asks a thousand times.
final class RowDrawingPlaces {
  RowDrawingPlaces({
    required Track track,
    required Cut? cut,
    required Layer layer,
  }) : _ownerName = rowOwnerName(track: track, cut: cut),
       _layer = layer;

  final String _ownerName;
  final Layer _layer;
  late final _blockStarts = laneBlockStarts(_layer.timeline);

  DrawingCelPlace of(Frame frame) => DrawingCelPlace(
    ownerName: _ownerName,
    layerName: _layer.name,
    celName: celNumberOrMark(frame.name, kind: _layer.kind),
    blockStarts: _blockStarts[frame.id] ?? const [],
  );
}

/// Conte handwriting of one storyboard block: its cut, and the drawing the
/// block shows.
final class ConteRowInkPlace extends CelPlace {
  const ConteRowInkPlace({required this.cutName, required this.celName});

  final String cutName;
  final String celName;
}

/// Ink in a box of one cut's envelope.
final class EnvelopeInkPlace extends CelPlace {
  const EnvelopeInkPlace(this.cutName);

  final String cutName;
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
/// ([projectLayersWithOwners]), then the ink over storyboard drawings and
/// in envelopes by cut — and last, what holds no place.
List<CelPlace> celPlacesOf(Project project, Iterable<BrushFrameKey> keys) {
  final index = _CelPlaceIndex(project);
  final found = [for (final key in keys) index.placeOf(key)]
    ..sort((a, b) {
      final byPlane = a.plane.index.compareTo(b.plane.index);
      return byPlane != 0 ? byPlane : a.position.compareTo(b.position);
    });
  return [for (final entry in found) entry.place];
}

enum _Plane { drawing, conteRow, envelope, gone }

typedef _Found = ({_Plane plane, int position, CelPlace place});

/// Every place [celPlacesOf] can answer with, found by the ids a key
/// carries — one walk of the project.
class _CelPlaceIndex {
  _CelPlaceIndex(Project project) {
    for (final owned in projectLayersWithOwners(project)) {
      final cut = owned.cut;
      if (cut != null) {
        _envelopes[cut.id] ??= (
          plane: _Plane.envelope,
          position: _envelopes.length,
          place: EnvelopeInkPlace(cut.name),
        );
      }
      final drawings = <FrameId, DrawingCelPlace>{};
      final row = RowDrawingPlaces(
        track: owned.track,
        cut: cut,
        layer: owned.layer,
      );
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
          place: ConteRowInkPlace(cutName: cut.name, celName: drawing.celName),
        );
      }
    }
  }

  final _drawings = <(LayerId, FrameId), _Found>{};
  final _rows = <(CutId, String), _Found>{};
  final _envelopes = <CutId, _Found>{};

  _Found placeOf(BrushFrameKey key) {
    final found = isConteInkRowKey(key)
        ? _rows[(key.cutId, conteInkRowIdOf(key)!)]
        : isEnvelopeInkKey(key)
        ? _envelopes[key.cutId]
        : _drawings[(key.layerId, key.frameId)];
    return found ??
        (plane: _Plane.gone, position: 0, place: const GoneCelPlace());
  }
}
