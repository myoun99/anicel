import '../../models/layer.dart';
import '../../models/layer_kind.dart';

/// Timesheet-style timeline sections, in raw (model) order: drawing cels
/// first, sound effects, camera last.
///
/// The horizontal timeline reverses raw order, so on screen the sections
/// stack bottom-up as 그림 → SE → 카메라 (camera rows on top); the X-sheet
/// keeps raw order and reads left-to-right like a paper timesheet (ACTION
/// cel columns, then CAMERA on the right).
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
    LayerKind.text ||
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
/// row above the camera. Refusing the drag stops it happening again; this
/// puts the rows back for someone who already has one.
List<Layer> sectionedLayerOrder(List<Layer> layers) {
  final buckets = <TimelineSection, List<Layer>>{
    for (final section in TimelineSection.values) section: <Layer>[],
  };
  for (final layer in layers) {
    buckets[timelineSectionForLayerKind(layer.kind)]!.add(layer);
  }
  // A partition by rank, which is stable by construction: same-rank rows
  // keep the order they arrived in, and that is what lets several Direction
  // rows be re-ordered among themselves.
  final camera = buckets[TimelineSection.camera]!;
  final ranked = <Layer>[
    for (var rank = 0; rank <= _cameraSectionTopRank; rank += 1)
      for (final layer in camera)
        if (timelineCameraSectionRank(layer.kind) == rank) layer,
  ];
  return List<Layer>.unmodifiable([
    for (final section in TimelineSection.values)
      ...(section == TimelineSection.camera ? ranked : buckets[section]!),
  ]);
}

/// Whether the layer at [index] opens a new section relative to the layer
/// before it in DISPLAY order. The first row/column never draws a divider.
bool timelineSectionStartsAt(List<Layer> displayLayers, int index) {
  if (index <= 0 || index >= displayLayers.length) {
    return false;
  }
  return timelineSectionForLayerKind(displayLayers[index].kind) !=
      timelineSectionForLayerKind(displayLayers[index - 1].kind);
}

/// The gutter label — the paper timesheet's column-group headings laid on
/// their side (액션 / SE / CAM as the sheet prints them; CAM matches the
/// printed sheet's group header, user rule).
String timelineSectionLabel(TimelineSection section) {
  return switch (section) {
    TimelineSection.drawing => 'ACTION',
    TimelineSection.se => 'SE',
    TimelineSection.camera => 'CAM',
  };
}

/// SE and camera sections can be hidden from the grids (the toolbar's
/// visibility toggles); the drawing section is the work surface and always
/// stays visible.
bool timelineSectionHideable(TimelineSection section) {
  return section != TimelineSection.drawing;
}
