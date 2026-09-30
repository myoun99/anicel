import 'package:collection/collection.dart' show IterableExtension;

import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_link_registry.dart';
import '../../models/project.dart';
import '../../models/track.dart';
import '../../services/media/media_asset_uses.dart';
import '../../services/persistence/cel_places.dart';
import '../../services/project_lookup.dart';
import 'app_strings.dart';

/// A ROW as one line: what holds it — its cut, or its track — and its name.
///
/// Four lists name a row — a frame's place (its first two parts), a media
/// pool file's row uses, a link badge's partners and a lane key's link
/// notice — so a row reads the same wherever it is listed.
String rowPlaceLine({required String ownerName, required String layerName}) =>
    '$ownerName · $layerName';

/// A place in a project as one line of a list: the names it is found by,
/// joined the way the canvas title joins a cut, a layer and a frame.
///
/// The lists that speak in these lines — the pictures a save could not
/// carry (C-save-percent), the uses of a media pool file (F-118) and the
/// frames a link takes (I-18, [drawingPlaceLines]) — so a frame on a row
/// reads the same in all of them.
String celPlaceLine(CelPlace place) {
  final strings = AppText.strings;
  return switch (place) {
    // An unnamed drawing writes no name on every kind but animation's
    // ([LayerKind.unnamedDrawingIsInbetween], 유저 2026-09-26: 「애니메이션
    // 이외 레이어는 이름없으면 진짜 이름없도록」), so its row names it alone.
    // ↩️The image row's alone until then — the layer's name is the picture's.
    DrawingCelPlace(:final ownerName, :final layerName, :final celName) => [
      rowPlaceLine(ownerName: ownerName, layerName: layerName),
      if (celName.isNotEmpty) celName,
    ].join(' · '),
    ConteRowInkPlace(:final cutName, :final celName) =>
      '${strings.panelConte} · $cutName · $celName',
    EnvelopeInkPlace(:final cutName) => '${strings.panelEnvelope} · $cutName',
    GoneCelPlace() => strings.saveCelsLostGone,
  };
}

/// [layerId]'s drawings [frameIds], each as [celPlaceLine] names it, in the
/// order given — none for a row [project] does not hold, or for a drawing
/// its bank does not.
///
/// What a LINK notice lists (I-18): 「대상의 프레임을 리스트로서」 — the
/// drawings a join by name discards, and those a 겸용 conversion replaces,
/// one line each, however many there are.
List<String> drawingPlaceLines(
  Project project,
  LayerId layerId,
  Iterable<FrameId> frameIds,
) {
  final owned = _rowOf(project, layerId);
  if (owned == null) {
    return const [];
  }
  return [
    for (final frameId in frameIds)
      if (owned.layer.frameById(frameId) case final frame?)
        celPlaceLine(
          DrawingCelPlace.at(
            track: owned.track,
            cut: owned.cut,
            layer: owned.layer,
            frame: frame,
          ),
        ),
  ];
}

/// [layerId]'s row as [rowPlaceLine] names it — none for a row [project]
/// does not hold.
///
/// What a lane KEY's link notice lists: the keys a join re-values sit on
/// that row's lanes, and a key has no drawing of its own to name.
List<String> rowPlaceLines(Project project, LayerId layerId) => [
  if (_rowOf(project, layerId) case final owned?)
    rowPlaceLine(
      ownerName: rowOwnerName(track: owned.track, cut: owned.cut),
      layerName: owned.layer.name,
    ),
];

/// [layerId]'s row in [project] with what holds it, wherever it lives.
({Track track, Cut? cut, Layer layer})? _rowOf(
  Project project,
  LayerId layerId,
) => projectLayersWithOwners(
  project,
).firstWhereOrNull((owned) => owned.layer.id == layerId);

/// One use of a media pool file as a line of the list the pool shows: a
/// picture of the work where it is set, a row by its cut and its name, a
/// frame as [celPlaceLine] names it.
String mediaAssetUseLine(MediaAssetUse use) => switch (use) {
  WorkPictureMediaUse(:final picture) =>
    '${AppText.strings.workSettingsTitle} · '
        '${AppText.strings.workPictureName(picture)}',
  RowMediaUse(:final ownerName, :final layerName) => rowPlaceLine(
    ownerName: ownerName,
    layerName: layerName,
  ),
  FrameMediaUse(:final place) => celPlaceLine(place),
};

/// The rows that [layerId] in [cutId] shares its pictures with — every
/// OTHER member of its link group, in the group's order — each as
/// [rowPlaceLine] names it. Empty when the row is not linked.
///
/// 🗣️유저 2026-09-25: 「링크버튼통해서 어디랑 링크되고있는지만 제대로
/// 표시하게」 — the badge said only THAT the pictures are shared, never with
/// whom; a link is made by duplicating now, never by a name, so the name
/// cannot tell you either.
List<String> linkPartnerLines(
  Project project, {
  required CutId cutId,
  required LayerId layerId,
}) {
  final group = project.linkRegistry.groupOf(cutId: cutId, layerId: layerId);
  if (group == null) {
    return const [];
  }
  return [
    for (final member in group.members)
      if (member.cutId != cutId || member.layerId != layerId)
        ?_memberLine(project, member),
  ];
}

/// [member] as [rowPlaceLine] names it; null for a member whose row is gone.
String? _memberLine(Project project, LayerLinkMember member) {
  final position = cutPositionOf(project, member.cutId);
  final layer = position?.cut.layers.firstWhereOrNull(
    (layer) => layer.id == member.layerId,
  );
  if (position == null || layer == null) {
    return null;
  }
  return rowPlaceLine(
    ownerName: rowOwnerName(track: position.track, cut: position.cut),
    layerName: layer.name,
  );
}
