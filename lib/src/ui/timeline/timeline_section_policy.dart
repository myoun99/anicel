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
    LayerKind.instruction || LayerKind.camera => TimelineSection.camera,
  };
}

/// Stable-sorts layers into section order (raw orientation), preserving the
/// relative order within each section. Defensive: the model usually already
/// keeps camera last, but display must not depend on that.
List<Layer> sectionedLayerOrder(List<Layer> layers) {
  final buckets = <TimelineSection, List<Layer>>{
    for (final section in TimelineSection.values) section: <Layer>[],
  };
  for (final layer in layers) {
    buckets[timelineSectionForLayerKind(layer.kind)]!.add(layer);
  }
  return List<Layer>.unmodifiable([
    for (final section in TimelineSection.values) ...buckets[section]!,
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
