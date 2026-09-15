import '../../models/brush_frame_key.dart';
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
  });

  /// [frame] on [layer], held by [cut] — or by [track] when the track owns
  /// the row.
  DrawingCelPlace.at({
    required Track track,
    required Cut? cut,
    required Layer layer,
    required Frame frame,
  }) : ownerName = rowOwnerName(track: track, cut: cut),
       layerName = layer.name,
       celName = celNumberOrMark(frame.name);

  final String ownerName;
  final String layerName;

  /// What the timeline prints where the drawing's block starts
  /// ([celNumberOrMark]).
  final String celName;
}

/// Conte ink on the paper of a page, by the number the page prints.
final class ContePageInkPlace extends CelPlace {
  const ContePageInkPlace(this.pageNumber);

  final int pageNumber;
}

/// Conte ink over one storyboard drawing's row.
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
/// ([projectLayersWithOwners]), the conte's paper ink by page, then the ink
/// over storyboard drawings and in envelopes by cut — and last, what holds
/// no place.
List<CelPlace> celPlacesOf(Project project, Iterable<BrushFrameKey> keys) {
  final index = _CelPlaceIndex(project);
  final found = [for (final key in keys) index.placeOf(key)]
    ..sort((a, b) {
      final byPlane = a.plane.index.compareTo(b.plane.index);
      return byPlane != 0 ? byPlane : a.position.compareTo(b.position);
    });
  return [for (final entry in found) entry.place];
}

enum _Plane { drawing, contePage, conteRow, envelope, gone }

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
      for (final frame in owned.layer.frames) {
        final drawing = DrawingCelPlace.at(
          track: owned.track,
          cut: cut,
          layer: owned.layer,
          frame: frame,
        );
        _drawings[(owned.layer.id, frame.id)] = (
          plane: _Plane.drawing,
          position: _drawings.length,
          place: drawing,
        );
        if (cut != null) {
          _rows[(cut.id, frame.id)] = (
            plane: _Plane.conteRow,
            position: _rows.length,
            place: ConteRowInkPlace(
              cutName: cut.name,
              celName: drawing.celName,
            ),
          );
        }
      }
    }
  }

  final _drawings = <(LayerId, FrameId), _Found>{};
  final _rows = <(CutId, FrameId), _Found>{};
  final _envelopes = <CutId, _Found>{};

  _Found placeOf(BrushFrameKey key) {
    final pageIndex = conteInkPageIndexOf(key);
    if (pageIndex != null) {
      return (
        plane: _Plane.contePage,
        position: pageIndex,
        place: ContePageInkPlace(pageIndex + 1),
      );
    }
    final found = isConteInkRowKey(key)
        ? _rows[(key.cutId, key.frameId)]
        : isEnvelopeInkKey(key)
        ? _envelopes[key.cutId]
        : _drawings[(key.layerId, key.frameId)];
    return found ??
        (plane: _Plane.gone, position: 0, place: const GoneCelPlace());
  }
}
