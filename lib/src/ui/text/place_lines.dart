import 'package:collection/collection.dart' show IterableExtension;

import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_link_registry.dart';
import '../../models/project.dart';
import '../../models/project_timeline.dart';
import '../../models/track.dart';
import '../../services/media/media_asset_uses.dart';
import '../../services/persistence/cel_places.dart';
import '../../services/project_lookup.dart';
import 'app_strings.dart';

/// What a timeline is called: its name, or the one its number gives.
String timelineNameOf(ProjectTimeline timeline) =>
    timeline.name ?? AppText.strings.timelineNumbered(timeline.number);

/// A cut's [name] as a place that names the cut stood in writes it — 🗣️
/// F-491 (유저 2026-10-27): 「컷 이름 앞에 c 붙이도록. 즉 컷이름 500이면
/// c500 되도록」 — and nothing for a gap's empty one.
String cutNameWritten(String name) => name.isEmpty ? '' : 'c$name';

/// What holds a place as one line: its name, after its timeline's where
/// that is not the open one ([PlaceOwner]).
String ownerLine(PlaceOwner owner) => switch (owner.away) {
  null => owner.name,
  final timeline => '${timelineNameOf(timeline)} · ${owner.name}',
};

/// A ROW as one line: what holds it — its cut, or its track — and its name.
///
/// Four lists name a row — a frame's place (its first two parts), a media
/// pool file's row uses, a link badge's partners and a lane key's link
/// notice — so a row reads the same wherever it is listed.
String rowPlaceLine({required PlaceOwner owner, required String layerName}) =>
    '${ownerLine(owner)} · $layerName';

/// A place in a project as one line of a list: the names it is found by,
/// joined the way the canvas title joins a cut, a layer and a frame.
///
/// The lists that speak in these lines — the pictures a save could not
/// carry (C-save-percent), the uses of a media pool file (F-118) and the
/// frames a link takes (I-18, [drawingPlaceLines]) — so a frame on a row
/// reads the same in all of them.
///
/// 🗣️F-284 (유저 2026-10-04): 「링크된 오디오 링크버튼눌러서 쓰는곳
/// 확인할때, 인덱스도 표시. 예를들어 se는 지금 S1 등 트랙이름까지만
/// 표시되는데, S1의 15 … 프레임 링크된거 보여줄때도 동일하게 해서 링크된거
/// 보여주는 창 다 법 통일해서 적용」 — a drawing's line ends with WHERE its
/// blocks start, each as [framePlace] writes a frame's place
/// ([FramePlaceLabel]). ↩️It ended with the name, and a sound has none.
String celPlaceLine(CelPlace place, {required FramePlaceLabel framePlace}) {
  final strings = AppText.strings;
  return switch (place) {
    // An unnamed drawing writes no name on every kind but animation's
    // ([LayerKind.unnamedDrawingIsInbetween], 유저 2026-09-26: 「애니메이션
    // 이외 레이어는 이름없으면 진짜 이름없도록」), so its row names it alone.
    // ↩️The image row's alone until then — the layer's name is the picture's.
    DrawingCelPlace(
      :final owner,
      :final layerName,
      :final celName,
      :final blockStarts,
    ) =>
      [
        rowPlaceLine(owner: owner, layerName: layerName),
        if (celName.isNotEmpty) celName,
        if (blockStarts.isNotEmpty) blockStarts.map(framePlace).join(', '),
      ].join(' · '),
    ConteRowInkPlace(:final owner, :final celName) =>
      '${strings.panelConte} · ${ownerLine(owner)} · $celName',
    EnvelopeInkPlace(:final owner) =>
      '${strings.panelEnvelope} · ${ownerLine(owner)}',
    TimesheetInkPlace(:final owner) =>
      '${strings.panelTimesheet} · ${ownerLine(owner)}',
    ViewerInkPlace(:final fileName) =>
      '${strings.panelMediaViewer} · $fileName',
    GoneCelPlace() => strings.saveCelsLostGone,
  };
}

/// How a list writes a frame's place on its row — the app's one notation,
/// which follows the seconds display: the session's
/// (`ProjectAccess.framePlaceLabel`).
typedef FramePlaceLabel = String Function(int frameIndex);

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
  Iterable<FrameId> frameIds, {
  required FramePlaceLabel framePlace,
}) {
  final owned = _rowOf(project, layerId);
  if (owned == null) {
    return const [];
  }
  final row = RowDrawingPlaces(
    owner: placeOwnerOf(project, track: owned.track, cut: owned.cut),
    layer: owned.layer,
  );
  return [
    for (final frameId in frameIds)
      if (owned.layer.frameById(frameId) case final frame?)
        celPlaceLine(row.of(frame), framePlace: framePlace),
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
      owner: placeOwnerOf(project, track: owned.track, cut: owned.cut),
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
String mediaAssetUseLine(
  MediaAssetUse use, {
  required FramePlaceLabel framePlace,
}) => switch (use) {
  WorkPictureMediaUse(:final picture) =>
    '${AppText.strings.workSettingsTitle} · '
        '${AppText.strings.workPictureName(picture)}',
  RowMediaUse(:final owner, :final layerName) => rowPlaceLine(
    owner: owner,
    layerName: layerName,
  ),
  FrameMediaUse(:final place) => celPlaceLine(place, framePlace: framePlace),
  SheetPhotoMediaUse(:final place) => celPlaceLine(
    place,
    framePlace: framePlace,
  ),
};

/// The rows that [layerId] in [cutId] shares its pictures with — every
/// OTHER member of its link group, in the group's order — each as
/// [rowPlaceLine] names it. Empty when the row is not linked.
///
/// 🗣️유저 2026-09-25: 「링크버튼통해서 어디랑 링크되고있는지만 제대로
/// 표시하게」 — the badge said only THAT the pictures are shared, never with
/// whom; a link is made by duplicating now, never by a name, so the name
/// cannot tell you either.
///
/// I-150-Q3 (유저 2026-11-03): 「배지에도 겸용이란 이름이아니라 동기컷? 뭐
/// 그런식으로 따로 표시」 — the row itself in its 동기컷's other cuts is no
/// partner here ([LayerLinkRegistry.linkedBeyondItsSync]); those cuts are
/// listed apart ([syncPartnerLines]).
List<String> linkPartnerLines(
  Project project, {
  required CutId cutId,
  required LayerId layerId,
}) {
  return [
    for (final member in project.linkRegistry.linkedBeyondItsSync(
      cutId: cutId,
      layerId: layerId,
    ))
      ?_memberLine(project, member),
  ];
}

/// The other cuts of [cutId]'s 동기컷 (`CutSync`) — the one cut, standing in
/// other timelines — each as [cutPlaceLine] names it, its timeline first.
/// Empty for a cut of its own.
List<String> syncPartnerLines(Project project, {required CutId cutId}) => [
  for (final other in project.linkRegistry.syncOf(cutId)?.cuts ?? const [])
    if (other != cutId) ?cutPlaceLine(project, other),
];

/// A CUT as one line: what holds it, as [ownerLine] writes it — its timeline
/// first where that is not the open one. Null for a cut no track holds.
String? cutPlaceLine(Project project, CutId cutId) =>
    switch (cutPositionOf(project, cutId)) {
      null => null,
      final position => ownerLine(
        placeOwnerOf(project, track: position.track, cut: position.cut),
      ),
    };

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
    owner: placeOwnerOf(project, track: position.track, cut: position.cut),
    layerName: layer.name,
  );
}
