import 'package:flutter/material.dart';

import '../../models/layer_kind.dart';
import 'layer_label_controls.dart';

/// The rail row's COLUMN SKELETON — the one declaration of slot ORDER and
/// slot WIDTH, shared by every surface that draws a horizontal rail row.
///
/// R9 #22 is what this file exists to prevent. Four surfaces hand-listed
/// the same columns — the timeline rows, the rail legend header, and the
/// storyboard's V and S rows — and they had drifted apart:
///
/// * the storyboard's V row omitted the sheet and mark slots and drew an
///   18px icon where the canonical type button is 22, so its name and
///   everything measured from it sat **44px** left of every other row's;
/// * the legend header's kind cell was 18 where the rows' is 22, a 4px
///   drift under the LAYER heading;
/// * the storyboard's S row put its kind icon INSIDE the name area, so the
///   name started 6px early.
///
/// The lesson R9 keeps re-learning: what gets shared must be the RAW value
/// (here the slot widths and their order), not each surface's derived
/// arrangement of it. Passing null RESERVES a slot — an empty box of the
/// same width — because every row reserves every slot (the Excel-grid
/// rule) so the legend's column icons sit over their columns.

/// The gap between the reserved section band and the first control slot.
/// Folder rows add their indent here, so the indent moves the WHOLE row's
/// leading cluster and never desynchronises one slot from the rest.
const double layerRailSectionGap = 8;

/// The TYPE BUTTON's slot (UI-R24 #7) — the row's KIND icon, on every row
/// kind including attach rows (R10 R3 moved their placement arrow to the
/// sheet slot). A fixed column of its own, so attach rows align with every
/// other row instead of indenting.
const double layerTypeSlotWidth = 22;

/// Where a rail row's NAME begins, measured from the row's left edge at
/// zero indent. Every rail surface must agree on this number; the parity
/// test asserts it against the real rendered geometry, not against this
/// constant, so a drift cannot be papered over by editing it.
const double layerRailLeadingWidth =
    layerSectionLabelSlotWidth +
    layerRailSectionGap +
    layerLaneToggleSlotWidth +
    layerTimesheetSlotWidth +
    layerControlChipGap +
    layerMarkSlotWidth +
    layerControlChipGap +
    layerTypeSlotWidth +
    layerControlChipGap;

/// ONE slot, measured along the rail's OWN axis.
///
/// R10 R6: the horizontal rail spends a slot's extent as width, the x-sheet's
/// stood-up column header spends it as height. Both read the same numbers
/// from the same list — an axis parameter, not a second skeleton, because a
/// second skeleton is exactly what R9 #22 was.
Widget layerRailSlot(Axis axis, double extent, [Widget? child]) {
  return axis == Axis.horizontal
      ? SizedBox(width: extent, child: child)
      : SizedBox(height: extent, child: child);
}

/// The cells BEFORE a rail row's name, in order. Null cells reserve their
/// slot.
///
/// [indent] is the folder-nesting inset; it widens the section gap so the
/// row's whole leading cluster shifts as one.
///
/// [axis] is the rail's own direction: horizontal for the timeline's rows
/// and the storyboard's, vertical for the x-sheet's column headers, where
/// the identical list runs top-to-bottom instead of left-to-right.
/// A slot a host can DECLINE to carry.
///
/// R10 R6: the stood-up x-sheet header stacks the rail single-file down a
/// 28px column, so in a short panel it cannot afford every control and has
/// to shed some. Shedding is the skeleton's own answer — the slot and its
/// gap leave together, so what remains stays in its place and the legend
/// above stays over it. Naming them means the ladder is a list, not seven
/// booleans that can disagree.
enum LayerRailSlot {
  laneToggle,
  timesheet,
  mark,
  fillReference,
  fx,
  mute,
  opacity,
}

double _shedSlotExtent(LayerRailSlot slot) => switch (slot) {
  // Slots that own a following chip gap take it with them.
  LayerRailSlot.laneToggle => layerLaneToggleSlotWidth,
  LayerRailSlot.timesheet => layerTimesheetSlotWidth + layerControlChipGap,
  LayerRailSlot.mark => layerMarkSlotWidth + layerControlChipGap,
  LayerRailSlot.fillReference => layerFillReferenceSlotWidth,
  LayerRailSlot.fx => layerFxSlotWidth,
  LayerRailSlot.mute => layerMuteSlotWidth,
  LayerRailSlot.opacity => layerOpacitySlotWidth,
};

/// The TWIRL glyph, for every rail surface in either orientation.
///
/// R10 R6 shipped two of them disagreeing: the layer's lane toggle drew
/// `▾ = open` while the lane GROUP header beside it drew `▸ = open`, so the
/// identical state read as opposite arrows two columns apart. `▾ open, ▸
/// shut` is what every other twirl in the app says, and pointing the glyph
/// at where the lanes physically open would have made the sheet disagree
/// with the timeline instead — one convention beats two geometries.
IconData layerRailTwirlIcon({required bool expanded}) =>
    expanded ? Icons.arrow_drop_down : Icons.arrow_right;

/// What a set of shed slots costs a rail row end to end.
double layerRailShedExtent(Set<LayerRailSlot> shed) {
  var total = 0.0;
  for (final slot in shed) {
    total += _shedSlotExtent(slot);
  }
  return total;
}

List<Widget> layerRailLeadingCells({
  double indent = 0,
  Axis axis = Axis.horizontal,
  bool includeSectionSlot = true,
  Set<LayerRailSlot> shed = const {},
  Widget? sectionBand,
  Widget? laneToggle,
  Widget? timesheet,
  Widget? mark,
  Widget? typeButton,
}) {
  return [
    // The reserved section slot (UI-R7 #2): the section ZONE — tint,
    // upright label, flyout tap — overlays the whole run from the grid
    // (SectionBandZone), old-gutter style. The legend header is the one
    // surface that puts something IN the slot (its sections flyout).
    //
    // [includeSectionSlot] false is the x-sheet's column header (R10 R6):
    // its section band is a strip of its OWN above the headers, spanning
    // each run's columns, so reserving the slot again inside every header
    // would count the band twice.
    if (includeSectionSlot)
      sectionBand == null
          ? LayerSectionBandCell(axis: axis)
          : layerRailSlot(axis, layerSectionLabelSlotWidth, sectionBand),
    layerRailSlot(axis, layerRailSectionGap + indent),
    if (!shed.contains(LayerRailSlot.laneToggle))
      layerRailSlot(axis, layerLaneToggleSlotWidth, laneToggle),
    if (!shed.contains(LayerRailSlot.timesheet)) ...[
      layerRailSlot(axis, layerTimesheetSlotWidth, timesheet),
      layerRailSlot(axis, layerControlChipGap),
    ],
    if (!shed.contains(LayerRailSlot.mark)) ...[
      layerRailSlot(axis, layerMarkSlotWidth, mark),
      layerRailSlot(axis, layerControlChipGap),
    ],
    // The KIND icon and the NAME are what a column heading IS; neither is
    // ever shed.
    layerRailSlot(axis, layerTypeSlotWidth, typeButton),
    layerRailSlot(axis, layerControlChipGap),
  ];
}

/// The cells AFTER a rail row's name, in order. Null cells reserve
/// their slot; [hasOnionColumn]/[hasBlendColumn] false drops the column
/// outright, which is the HOST's answer (the storyboard rail has neither),
/// as distinct from a row that merely has nothing to put there.
List<Widget> layerRailTrailingCells({
  Axis axis = Axis.horizontal,
  Set<LayerRailSlot> shed = const {},
  Widget? fillReference,
  Widget? fx,
  bool hasOnionColumn = false,
  Widget? onion,
  Widget? visibility,
  Widget? mute,
  Widget? opacity,
  bool hasBlendColumn = false,
  Widget? blend,
}) {
  return [
    if (!shed.contains(LayerRailSlot.fillReference))
      layerRailSlot(axis, layerFillReferenceSlotWidth, fillReference),
    if (!shed.contains(LayerRailSlot.fx))
      layerRailSlot(axis, layerFxSlotWidth, fx),
    if (hasOnionColumn) layerRailSlot(axis, layerOnionSlotWidth, onion),
    // The EYE is never shed: hiding a layer is the one control a timesheet
    // reader reaches for.
    layerRailSlot(axis, layerVisibilitySlotWidth, visibility),
    if (!shed.contains(LayerRailSlot.mute))
      layerRailSlot(axis, layerMuteSlotWidth, mute),
    if (!shed.contains(LayerRailSlot.opacity))
      layerRailSlot(axis, layerOpacitySlotWidth, opacity),
    if (hasBlendColumn) layerRailSlot(axis, layerBlendSlotWidth, blend),
  ];
}

/// The trailing run's slots, in the order [layerRailTrailingCells] emits
/// them. Naming them lets a host LOCATE a column instead of re-adding the
/// widths in a comment — see [layerRailTrailingWidth].
enum LayerRailTrailingSlot {
  fillReference,
  fx,
  onion,
  visibility,
  mute,
  opacity,
  blend,
}

double _trailingSlotWidth(LayerRailTrailingSlot slot) => switch (slot) {
  LayerRailTrailingSlot.fillReference => layerFillReferenceSlotWidth,
  LayerRailTrailingSlot.fx => layerFxSlotWidth,
  LayerRailTrailingSlot.onion => layerOnionSlotWidth,
  LayerRailTrailingSlot.visibility => layerVisibilitySlotWidth,
  LayerRailTrailingSlot.mute => layerMuteSlotWidth,
  LayerRailTrailingSlot.opacity => layerOpacitySlotWidth,
  LayerRailTrailingSlot.blend => layerBlendSlotWidth,
};

/// What the trailing cells cost, counting only from [from] onward.
///
/// The default counts the whole run. Starting part-way through answers
/// "how much sits to the right of this column" — which is how the
/// eye-swipe band finds the eye without restating the control order, and
/// therefore without going stale the next time a column is added.
double layerRailTrailingWidth({
  LayerRailTrailingSlot from = LayerRailTrailingSlot.fillReference,
  Set<LayerRailSlot> shed = const {},
  bool hasOnionColumn = false,
  bool hasBlendColumn = false,
}) {
  var total = 0.0;
  for (final slot in LayerRailTrailingSlot.values) {
    if (slot.index < from.index) {
      continue;
    }
    final carried = switch (slot) {
      LayerRailTrailingSlot.fillReference => !shed.contains(
        LayerRailSlot.fillReference,
      ),
      LayerRailTrailingSlot.fx => !shed.contains(LayerRailSlot.fx),
      LayerRailTrailingSlot.mute => !shed.contains(LayerRailSlot.mute),
      LayerRailTrailingSlot.opacity => !shed.contains(LayerRailSlot.opacity),
      LayerRailTrailingSlot.onion => hasOnionColumn,
      LayerRailTrailingSlot.blend => hasBlendColumn,
      LayerRailTrailingSlot.visibility => true,
    };
    if (!carried) {
      continue;
    }
    total += _trailingSlotWidth(slot);
  }
  return total;
}

/// The row's TYPE BUTTON (UI-R24 #7): the kind icon, in the rail's fixed
/// type slot. Always the kind — an attach row's placement arrow rides the
/// sheet slot ([LayerAttachArrowCell], R10 R3).
///
/// R9: ONE widget, so every surface that states a row's identity states it
/// the same way. The x-sheet's column headers had no type slot at all (no
/// kind icon anywhere, and no way to see that a column is an attach row),
/// and the storyboard's two rail rows hand-rolled their own icons outside
/// the slot.
class LayerTypeButton extends StatelessWidget {
  const LayerTypeButton({
    super.key,
    required this.keyPrefix,
    required this.idValue,
    this.kind,
    this.folderCollapsed = false,
    this.icon,
    this.semanticLabel,
    this.onTap,
    this.height = 24,
  });

  /// Addresses the surface: 'timeline' | 'xsheet' | 'storyboard'.
  final String keyPrefix;

  /// The subject's stable id for the keys — a [LayerId]'s string, or a
  /// track's on the storyboard's V row.
  final String idValue;

  /// Null only on the rows that are not layers (the storyboard's V row is
  /// a TRACK); those pass [icon] instead.
  final LayerKind? kind;

  /// A folder's glyph reads its own fold.
  final bool folderCollapsed;

  /// Overrides the glyph for rows that are not layers (the V row's film
  /// strip).
  final IconData? icon;

  final String? semanticLabel;

  final VoidCallback? onTap;

  /// Rows shorter than the default (the storyboard's floor-height V row)
  /// pass their own so the button never overflows.
  final double height;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final Widget glyph;
    final String label;
    // R10 R3: the type cell is ALWAYS the kind. The attach arrow used to
    // take this slot on attach rows, which cost them the one column that
    // says what kind of row they are — and the sheet slot beside it was
    // reserved and empty on exactly those rows. The arrow lives there now
    // ([LayerAttachArrowCell]).
    if (kind != null && layerKindGroupsLayers(kind!)) {
      label = semanticLabel ?? layerTypeSemanticLabel(kind!);
      glyph = Icon(
        folderCollapsed ? Icons.folder : Icons.folder_open,
        key: ValueKey<String>('$keyPrefix-folder-icon-$idValue'),
        size: 16,
        color: colorScheme.onSurfaceVariant,
      );
    } else {
      label =
          semanticLabel ??
          (kind == null ? 'Row' : layerTypeSemanticLabel(kind!));
      glyph = Icon(
        icon ?? layerKindIcon(kind!),
        key: ValueKey<String>('$keyPrefix-layer-kind-icon-$idValue'),
        size: 18,
      );
    }

    return InkWell(
      key: ValueKey<String>('$keyPrefix-layer-type-button-$idValue'),
      onTap: onTap,
      customBorder: const CircleBorder(), // R26 #28
      child: SizedBox(
        width: layerTypeSlotWidth,
        height: height,
        child: Center(
          child: Semantics(
            label: label,
            container: true,
            child: ExcludeSemantics(child: glyph),
          ),
        ),
      ),
    );
  }
}

String layerTypeSemanticLabel(LayerKind kind) {
  return switch (kind) {
    LayerKind.animation => 'Animation layer',
    LayerKind.storyboard => 'Storyboard layer',
    LayerKind.image => 'Image layer',
    LayerKind.text => 'Text layer',
    LayerKind.se => 'SE layer',
    LayerKind.instruction => 'Instruction layer',
    LayerKind.camera => 'Camera layer',
    LayerKind.folder => 'Folder',
    LayerKind.adjustment => 'Adjustment layer',
  };
}
