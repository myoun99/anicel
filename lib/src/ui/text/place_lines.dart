import 'package:collection/collection.dart' show IterableExtension;

import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../../models/layer_link_registry.dart';
import '../../models/project.dart';
import '../../services/media/media_asset_uses.dart';
import '../../services/persistence/cel_places.dart';
import '../../services/project_lookup.dart';
import 'app_strings.dart';

/// A ROW as one line: what holds it — its cut, or its track — and its name.
///
/// Three lists name a row — a frame's place (its first two parts), a media
/// pool file's row uses and a link badge's partners — so a row reads the
/// same wherever it is listed.
String rowPlaceLine({required String ownerName, required String layerName}) =>
    '$ownerName · $layerName';

/// A place in a project as one line of a list: the names it is found by,
/// joined the way the canvas title joins a cut, a layer and a frame.
///
/// Two lists speak in these lines — the pictures a save could not carry
/// (C-save-percent) and the uses of a media pool file (F-118) — so a frame
/// on a row reads the same in both.
String celPlaceLine(CelPlace place) {
  final strings = AppText.strings;
  return switch (place) {
    // An image row's unnamed cel writes no name: the layer's name is the
    // picture's ([LayerKind.unnamedCelIsTheLayer]).
    DrawingCelPlace(:final ownerName, :final layerName, :final celName) => [
      rowPlaceLine(ownerName: ownerName, layerName: layerName),
      if (celName.isNotEmpty) celName,
    ].join(' · '),
    ContePageInkPlace(:final pageNumber) =>
      '${strings.panelConte} · p$pageNumber',
    ConteRowInkPlace(:final cutName, :final celName) =>
      '${strings.panelConte} · $cutName · $celName',
    EnvelopeInkPlace(:final cutName) => '${strings.panelEnvelope} · $cutName',
    GoneCelPlace() => strings.saveCelsLostGone,
  };
}

/// One use of a media pool file as a line of the list the pool shows: a row
/// by its cut and its name, a frame as [celPlaceLine] names it.
String mediaAssetUseLine(MediaAssetUse use) => switch (use) {
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
