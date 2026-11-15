import '../core/frozen_collections.dart';
import 'layer.dart';
import 'layer_folder.dart';
import 'layer_kind.dart';

/// Timesheet-style timeline sections, in raw (model) order: drawing cels
/// first, sound effects, camera last.
///
/// The horizontal timeline reverses raw order, so on screen the sections
/// stack bottom-up as 그림 → SE → 카메라 (camera rows on top); the X-sheet
/// keeps raw order and reads left-to-right like a paper timesheet (ACTION
/// cel columns, then CAMERA on the right).
///
/// ★IT IS THE PICTURE'S ORDER TOO: a cut's rows stand in it ([Cut]), and
/// every route that paints them walks them bottom-up as they stand — so a
/// row the timeline shows over another is painted over it: the direction
/// row over every ACTION row's picture, as the timeline shows it (F-596).
/// 🗣️F-596-Q1 (유저 2026-11-16): 「디렉션이 항상 위여야한다는건 아니고
/// 다른 레이어 위치 로직이랑 동일하게 하란거엿음. 위에있으면 위에
/// 보이게 … 보이는대로 위치관계만 지키면됨」 — ⛔no rule of the direction
/// row's own.
///
enum TimelineSection { drawing, se, camera }

TimelineSection timelineSectionForLayerKind(LayerKind kind) {
  return switch (kind) {
    // Folders group drawing rows, so their header sits in the drawing
    // section with them. An ADJUSTMENT belongs there for the same reason
    // and a stronger one: its scope IS its position in the drawing stack
    // (§6-z, "액션란이 맞다"), so it has to sit among the rows it filters.
    LayerKind.animation ||
    LayerKind.storyboard ||
    LayerKind.image ||
    LayerKind.folder ||
    LayerKind.adjustment => TimelineSection.drawing,
    LayerKind.se => TimelineSection.se,
    // The TRANSITION row is a camera-section row like the direction row it
    // is made of — it just belongs to the track instead of the cut.
    LayerKind.instruction ||
    LayerKind.transition ||
    LayerKind.camera => TimelineSection.camera,
  };
}

/// 🚨A5-4 (유저 2026-08-22) — **THE CAMERA SECTION HAS AN ORDER, AND IT IS A
/// RULE.**
///
/// > 「위에서부터 **카메라/트랜지션/디렉션** 고정. 지금 **디렉션을 카메라 위로
/// > 옮길 수 있고 되돌릴 수 없다.** 카메라·트랜지션 = **드래그 불가**,
/// > 디렉션 = **디렉션끼리만**」
///
/// ⛔It was never written down anywhere. All three kinds share ONE section,
/// so the cross-section refusal never fired between them, and the order on
/// screen fell out of two unrelated insertion sites — `withEnsuredSection
/// Layers` putting a Direction row before the camera, and the layer
/// controller splicing the transition clone at the camera's index. Neither
/// repairs a list that has already been disturbed.
///
/// Raw order, so LOW sorts to the bottom of the screen: direction, then
/// transition, then camera on top.
int timelineCameraSectionRank(LayerKind kind) => switch (kind) {
  LayerKind.camera => _cameraSectionTopRank,
  LayerKind.transition => 1,
  // Direction rows — and every kind outside this section, where a rank
  // means nothing because it is only ever compared within one section.
  _ => 0,
};

const int _cameraSectionTopRank = 2;

/// Stable-sorts layers into section order (raw orientation), preserving the
/// relative order within each section — except inside the CAMERA section,
/// where [timelineCameraSectionRank] IS the order and the incoming list has
/// no say (A5-4).
///
/// ⚠️That exception is what repairs a project already saved with a Direction
/// row above the camera. Refusing the drag stops it happening again; a cut
/// built from such a file stands its rows back in this order ([Cut]).
///
/// 🚨A ROW IN A FOLDER STANDS WHERE ITS OUTERMOST FOLDER STANDS — a
/// folder's rows are one run with the folder row right above them
/// (`folderStructureProblem`), and the picture is built on that: one pass
/// bottom-up gathers a folder's rows by the time it meets the folder row
/// (`resolveCutFrameCompositeTree`), so a member standing past it would be
/// painted by no one. A direction or camera row put in a drawing folder
/// therefore stands in it, with the folder, and is painted where it is
/// seen — 🗣️F-596-Q1 (유저 2026-11-16): 「폴더 안에 두면 폴더 자리에서
/// 그린다」.
List<Layer> sectionedLayerOrder(List<Layer> layers) {
  final placeOf = _placeOfIn(layers);
  final places = [for (final layer in layers) placeOf(layer)];
  // A partition by place, which is stable by construction: rows of one
  // place keep the order they arrived in, and that is what lets several
  // Direction rows be re-ordered among themselves.
  return frozenList<Layer>([
    for (var place = 0; place <= _lastPlace; place += 1)
      for (var i = 0; i < layers.length; i += 1)
        if (places[i] == place) layers[i],
  ]);
}

/// Whether [layers] already stand in section order ([sectionedLayerOrder]):
/// no row's place below the place of the row before it.
bool isInSectionOrder(List<Layer> layers) {
  final placeOf = _placeOfIn(layers);
  var last = 0;
  for (final layer in layers) {
    final place = placeOf(layer);
    if (place < last) {
      return false;
    }
    last = place;
  }
  return true;
}

/// Each of [layers]' rows' place in section order: its outermost folder's
/// ([sectionedLayerOrder] has why), or its own outside every folder.
int Function(Layer) _placeOfIn(List<Layer> layers) {
  final folders = LayerFolderIndex(layers);
  return (layer) {
    final ancestry = folders.ancestryOf(layer.folderId);
    return _placeOf(ancestry.isEmpty ? layer.kind : ancestry.last.kind);
  };
}

/// [kind]'s place: its section, and inside the camera section its rank.
int _placeOf(LayerKind kind) {
  final section = timelineSectionForLayerKind(kind);
  return section.index * (_cameraSectionTopRank + 1) +
      (section == TimelineSection.camera ? timelineCameraSectionRank(kind) : 0);
}

final int _lastPlace =
    TimelineSection.values.length * (_cameraSectionTopRank + 1) - 1;
