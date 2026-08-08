import 'package:flutter/material.dart';

import '../../models/app_language.dart' show AppLanguage;
import '../../models/attached_placement.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';
import '../theme/app_theme.dart';
import '../widgets/panel_flyout.dart';
import '../text/app_strings.dart';
import '../text/vertical_writing_text.dart';

/// Layer-label chip controls shared by both timeline orientations
/// (horizontal rows and XSheet column headers): the timesheet-output toggle
/// and the TVPaint-style color mark. Keys take an orientation prefix
/// ('timeline' | 'xsheet') so tests address each surface.

/// Slot widths — non-eligible rows reserve the same space so kind icons and
/// names stay column-aligned across rows, and the rail's legend header
/// (R-toolbar round) lines its column icons up over these exact slots.
/// EVERY kind reserves EVERY slot (Excel-grid rule): slimmed from the old
/// 24/26/86 so the full set still fits the 312 rail.
/// Leading slot every rail row reserves for the INLINE section tag
/// (ACTION/SE/CAM on the section's first row — UI-R5, the bracket gutter
/// retired); the legend header's sections cell sits over the same slot,
/// and the x-sheet spends the same number as the HEIGHT of its section
/// strip.
///
/// 36 → 16 (user, 2026-08-08: 'compact, just the letters plus a hair').
/// MEASURED, not chosen: standing the letters up ([VerticalLatinForm]) puts
/// the glyph column at one em — 9px at the band's 9pt — and the widest
/// thing that ever sits here otherwise is the legend's 13px sections icon.
/// 16 clears both and leaves 3.5px of air; 36 left thirteen.
///
/// Every rail row's name starts this much earlier as a result: the slot is
/// the first term of [layerRailLeadingWidth], which is the whole point of
/// the number living here rather than in each surface.
const double layerSectionLabelSlotWidth = 16;

/// The wash a rail row wears while it is THE row the frame-axis verbs act
/// on — the active layer's row, and (R10 #19's other half) the fx header
/// or property lane you are standing on.
///
/// ONE value, because they are one statement: "this is what the verbs act
/// on". Two rows can wear it at once and that is the AE picture — the
/// layer is selected AND a property inside it is — so the more specific
/// lit row is the subject. Colour only, never weight (user rule): the
/// text must not reflow when a row is picked.
Color railSelectedRowColor(ColorScheme colorScheme) =>
    colorScheme.secondaryContainer.withValues(alpha: 0.55);

/// The rows' reserved leading SECTION slot (UI-R7 #2): a transparent
/// spacer — the section ZONE (tint, hairlines, upright label, tap) is
/// painted by [SectionBandZone] overlaying the whole section run, so
/// S1·S2-style neighbours read as ONE vertical sub-zone exactly like the
/// old gutter bracket, just inside the rows.
class LayerSectionBandCell extends StatelessWidget {
  const LayerSectionBandCell({super.key, this.axis = Axis.horizontal});

  /// The rail's own direction — the slot's extent is measured along it, and
  /// the cell fills the other way (R10 R6).
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    return axis == Axis.horizontal
        ? const SizedBox(
            width: layerSectionLabelSlotWidth,
            height: double.infinity,
          )
        : const SizedBox(
            height: layerSectionLabelSlotWidth,
            width: double.infinity,
          );
  }
}

/// One section's vertical zone over the rows' reserved band slots — the
/// pre-R5 gutter bracket verbatim (UI-R7 #2, user: '저번이랑 똑같이'),
/// now INSIDE the rows: tinted fill, bottom hairline landing on the run's
/// last row boundary, right hairline as the band/rail divider, the paper
/// sheet's upright glyph label centered across the run.
///
/// DISPLAY-ONLY on every surface. It used to open a flyout (fold / add
/// layer here / solo / section-wide eye) on the timeline alone, which the
/// user retired outright: the legend's sections cell already shows and
/// hides SE and CAM, and nothing else in that menu was wanted. The x-sheet
/// band never had the flyout, so deleting it is also what finally makes
/// the two surfaces agree.
class SectionBandZone extends StatelessWidget {
  const SectionBandZone({super.key, required this.label, this.extent});

  final String label;

  /// Fixed layer-axis extent; null expands to the parent (the storyboard's
  /// per-group Positioned.fill mounting).
  final double? extent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: layerSectionLabelSlotWidth,
      height: extent,
      decoration: BoxDecoration(
        // The band is a PLATE grouping a run of rows, not a chrome
        // surface — one chrome fill would have left it reading by its two
        // hairlines alone.
        color: AppColors.washDown,
        // One shared table (R3 #5/#6): the bottom hairline sits on the
        // run's last row boundary, the right hairline is the band/rail
        // divider — no enclosing box.
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
          right: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      // The band names its own region. It used to get a node for free from
      // the flyout's InkWell — an ACTION is a tap target, so the tree gave
      // it a boundary — and taking the tap away took the heading's
      // semantics with it. A label is a label whether or not you can press
      // it, so the boundary is stated here now.
      child: Semantics(
        container: true,
        label: label,
        child: ExcludeSemantics(
          child: Center(
            child: ClipRect(
              child: VerticalWritingText(
                text: label,
                // ACTION / SE / CAM stand UP (user, 2026-08-08). Lying down
                // is the Japanese standard and it is what the printed sheet
                // keeps, but this band is a three-letter tag you glance at,
                // and glancing at it meant tilting your head.
                latinForm: VerticalLatinForm.upright,
                style: TextStyle(
                  fontSize: 9,
                  // Dropped with the turn: letter spacing is a HORIZONTAL
                  // notion and the renderer zeroes it anyway (the leading
                  // comes from the cell extent), so carrying it here only
                  // said something untrue about the label.
                  fontWeight: FontWeight.bold,
                  height: 1.15,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const double layerTimesheetSlotWidth = 20;
const double layerMarkSlotWidth = 14;
const double layerLaneToggleSlotWidth = 16;
const double layerFillReferenceSlotWidth = 22;
const double layerFxSlotWidth = 22;
const double layerVisibilitySlotWidth = 22;
const double layerMuteSlotWidth = 18;
// 64 → 42 (UI-R18 #4): the opacity bar reads fine at two-thirds width
// across all three panels' rails.
const double layerOpacitySlotWidth = 42;

/// R27 #6: the BLEND column — the layer's compositing mode, moved out of
/// the timeline toolbar and into the label itself (PS/CSP reading: the
/// mode belongs to the row, not to a far-away command bar). Rightmost
/// slot, immediately right of the opacity bar, per the user's placement.
const double layerBlendSlotWidth = 58;

/// The per-layer onion-skin toggle column (UI-R17 #5, TVPaint style).
const double layerOnionSlotWidth = 22;
const double layerControlChipGap = 4;

/// Whether [kind] carries a blend mode at all. Only the ACTION-section
/// kinds composite artwork — plus FOLDERS, which blend their whole group
/// (R27 #29); SE/CAM/instruction rows reserve the slot so the control
/// columns and the legend header stay aligned.
bool layerKindShowsBlendControl(LayerKind kind) =>
    layerKindIsDrawingCel(kind) || layerKindGroupsLayers(kind);

/// R27 #6 / R28 #2: the row's blend-mode BUTTON. Reads the current mode's
/// name; accent while non-normal (selection style: color only, no check
/// glyph in the row itself).
///
/// R28 #2: this is the tool-settings blend control — the shared
/// [PanelFlyoutButton] — with the caret dropped, per the user's rule that
/// everything touching blend modes speaks one UI. It used to be a bare
/// left-aligned InkWell label, which read as text rather than a button and
/// sat flush against the opacity bar instead of centered under the
/// legend's BLND header.
class LayerBlendModeChip extends StatelessWidget {
  const LayerBlendModeChip({
    super.key,
    required this.keyValue,
    required this.optionKeyPrefix,
    required this.blendMode,
    required this.language,
    required this.onBlendModeSelected,
    this.subject = 'Layer',
    this.isGroup = false,
    this.axis = Axis.horizontal,
  });

  /// The RAIL's direction. Vertical is the x-sheet's stood-up column: the
  /// slot spends its 58 as HEIGHT and the mode name reads down the button.
  /// This was the one control in the shared skeleton that hardcoded its
  /// axis, so on the sheet it drew a 58-wide chip inside a 28px column.
  final Axis axis;

  /// The full widget key string ('timeline-layer-blend-a').
  final String keyValue;

  /// Prefix for the flyout option keys
  /// ('timeline-layer-blend-option-' + mode name).
  final String optionKeyPrefix;

  final LayerBlendMode blendMode;
  final AppLanguage language;
  final ValueChanged<LayerBlendMode> onBlendModeSelected;

  /// Names the row kind in the tooltip ('Layer', 'Folder').
  final String subject;

  /// GROUP rows get [LayerBlendMode.passThrough] in the list; a drawing
  /// layer has no members to pass through, so it never sees the option.
  final bool isGroup;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final nonNormal = blendMode != LayerBlendMode.normal;
    final vertical = axis == Axis.vertical;
    return SizedBox(
      width: vertical ? 20 : layerBlendSlotWidth,
      height: vertical ? layerBlendSlotWidth : 20,
      // Centered in the slot so the button lines up under the legend's
      // BLND column header (R28 #2).
      child: Center(
        child: PanelFlyoutButton(
          key: ValueKey<String>(keyValue),
          axis: axis,
          label: blendMode.labelFor(language),
          tooltip: '$subject blend mode',
          showCaret: false,
          expand: true,
          fontSize: 9.5,
          fontWeight: nonNormal ? FontWeight.w700 : FontWeight.w400,
          labelColor: nonNormal
              ? AppColors.accent
              : colorScheme.onSurfaceVariant,
          padding: vertical
              ? const EdgeInsets.symmetric(horizontal: 2, vertical: 3)
              : const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          entriesBuilder: () => [
            for (final mode in LayerBlendMode.optionsFor(isGroup: isGroup))
              PanelFlyoutItem(
                keyValue: '$optionKeyPrefix${mode.name}',
                label: mode.labelFor(language),
                checked: mode == blendMode,
                onSelected: () => onBlendModeSelected(mode),
              ),
          ],
        ),
      ),
    );
  }
}

/// Every layer kind that PRINTS carries the timesheet-output toggle — one
/// entrance for every row (unified layer controls, user rule): cel/image/SE
/// gate their sheet columns and the CAMERA layer gates the printed CAM
/// column. A folder prints nothing of its own, so its slot stays reserved
/// but empty.
bool layerKindEligibleForTimesheetToggle(LayerKind kind) =>
    !layerKindGroupsLayers(kind);

/// Every layer kind shows the opacity slider (unified layer controls —
/// "레이어는 싹 다 공통화"): compositing cels use it directly, the CAMERA
/// row's slider drives the camera-view DIM opacity, and instruction rows
/// carry the same control for entrance parity.
bool layerKindShowsOpacityControl(LayerKind kind) => true;

/// Every layer kind shows the fx switch (unified layer controls): drawing
/// cels and SE rows bypass their composite-time transform/opacity (SE fx
/// move the canvas dialogue), the CAMERA row bypasses the camera work on
/// the render routes (playback/export/thumbnails — authoring overlays
/// keep the real pose), and instruction rows carry the switch as authored
/// state for entrance parity.
bool layerKindShowsFxToggle(LayerKind kind) => true;

/// The `fx` GLYPH — italic, bold, accent when the FX apply and dim when
/// bypassed. Defined ONCE (R28 follow-up).
///
/// Four copies of this styling existed: the layer switch, the folder
/// switch, the storyboard's cut switch and the legend's column header.
/// Restyling fx meant finding all four, which is exactly the failure the
/// user keeps calling out — change it in one place, it changes
/// everywhere.
Widget fxGlyph({
  required BuildContext context,
  required bool active,
  double fontSize = 13,
  bool mixed = false,
}) {
  final onSurface = Theme.of(context).colorScheme.onSurface;
  return Text(
    'fx',
    style: TextStyle(
      fontSize: fontSize,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w700,
      // MIXED (R8): the row's master says "some of my groups are off" — the
      // accent held back to half, so it reads as neither fully on nor off.
      color: mixed
          ? AppColors.accent.withValues(alpha: 0.5)
          : active
          ? AppColors.accent
          : onSurface.withValues(alpha: 0.35),
      // …plus a mark the colour-blind eye can still read.
      decoration: mixed ? TextDecoration.underline : TextDecoration.none,
      decorationColor: AppColors.accent.withValues(alpha: 0.5),
    ),
  );
}

/// The ONE eye: whether this row shows.
///
/// It was written inline in three rails (timeline, x-sheet, storyboard)
/// and had already drifted — the glyph was 18px in one and 16px in the
/// other two. Same lesson as the fx switch: a control that exists three
/// times is a control nobody can restyle.
class LayerVisibilityToggleButton extends StatelessWidget {
  const LayerVisibilityToggleButton({
    super.key,
    required this.keyValue,
    required this.isVisible,
    required this.onToggle,
    this.subject = 'layer',
    this.size = layerVisibilitySlotWidth,
    this.iconSize = 18,
  });

  /// Names the row kind in the tooltip ('layer', 'folder').
  final String subject;

  /// The full widget key string ('timeline-layer-visibility-a').
  final String keyValue;

  final bool isVisible;
  final VoidCallback onToggle;
  final double size;

  /// The x-sheet's column header runs a hair smaller than the rails.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: 26,
      child: IconButton(
        key: ValueKey<String>(keyValue),
        tooltip: isVisible ? 'Hide $subject' : 'Show $subject',
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: size, height: 26),
        icon: Icon(
          isVisible ? Icons.visibility : Icons.visibility_off,
          size: iconSize,
        ),
        onPressed: onToggle,
      ),
    );
  }
}

/// The ONE mute speaker (SE rows).
///
/// Also written inline three times, also drifted — 14px glyph in the
/// storyboard, 16px in the two timeline rails, and the storyboard's copy
/// had silently lost the SOLO accent the other two carry.
///
/// R10 R3: the speaker is a DOOR, not a toggle. Pressing it opens the SE
/// mixer (mute, solo, fader, pan) anchored under the button; the two
/// timeline rails used to hang a context menu off it for the other three
/// and the storyboard rail had no way to reach them at all. It still
/// SHOWS mute and solo, because a door has to say what is behind it.
class LayerMuteToggleButton extends StatelessWidget {
  const LayerMuteToggleButton({
    super.key,
    required this.keyValue,
    required this.muted,
    required this.onOpenMixer,
    this.soloed = false,
    this.width = layerMuteSlotWidth,
    this.height = 26,
  });

  /// The full widget key string ('timeline-layer-mute-a').
  final String keyValue;

  final bool muted;

  /// Opens the mixer. It takes THIS button's context so the popup anchors
  /// to the speaker rather than to whatever row mounted it.
  final ValueChanged<BuildContext> onOpenMixer;

  /// Soloed rows tint accent (selection style: color only, no checkmarks).
  final bool soloed;

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: ValueKey<String>(keyValue),
      // One meaning on all three rails, so the label is the control's, not
      // the host's. It also carries the button's semantics name — the
      // hardcoded English 'Mute layer'/'Unmute layer' went out with the
      // toggle, and a door needs to say where it goes.
      tooltip: AppText.strings.layerAudioTitle,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: width, height: height),
      icon: Icon(
        muted ? Icons.volume_off : Icons.volume_up,
        size: 16,
        color: soloed ? Theme.of(context).colorScheme.primary : null,
      ),
      onPressed: () => onOpenMixer(context),
    );
  }
}

/// The ONE fx SWITCH: whether this row's FX apply or are bypassed.
///
/// Every row kind that has FX mounts this and binds its own identity —
/// layers, folders and storyboard cuts. It is deliberately id-agnostic:
/// a per-type wrapper is how the copies started.
///
/// Tight SizedBox: the M3 IconButton otherwise inflates its layout box to
/// the 48px minimum tap target and overflows the row (same gotcha as the
/// timesheet toggle).
class FxToggleButton extends StatelessWidget {
  const FxToggleButton({
    super.key,
    required this.keyValue,
    required this.state,
    required this.onToggle,
    this.subject = 'layer',
    this.size = layerFxSlotWidth,
  });

  /// The full widget key string — callers spell their own identity in
  /// ('timeline-layer-fx-a', 'storyboard-cut-fx-3').
  final String keyValue;

  /// R8: the row's FX as ONE value, so "on/off" and "mixed" cannot drift
  /// apart on their way here. A layer row is a MASTER over its per-group
  /// switches and can be [LayerFxState.mixed]; the cut-level switch has no
  /// groups under it and only ever passes on/off.
  final LayerFxState state;

  final VoidCallback onToggle;

  /// Names the row kind in the tooltip ('layer', 'folder', 'cut').
  final String subject;

  final double size;

  @override
  Widget build(BuildContext context) {
    final mixed = state == LayerFxState.mixed;
    return SizedBox(
      width: size,
      height: 26,
      child: IconButton(
        key: ValueKey<String>(keyValue),
        tooltip: switch (state) {
          LayerFxState.mixed => 'Bypass all $subject FX (some are off)',
          LayerFxState.on => 'Bypass $subject FX',
          LayerFxState.off => 'Apply $subject FX',
        },
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: size, height: 26),
        icon: fxGlyph(
          context: context,
          active: state != LayerFxState.off,
          mixed: mixed,
        ),
        onPressed: onToggle,
      ),
    );
  }
}

/// The row kind icon (shared by the rail rows and the legend's kind-solo
/// flyout, R4 #8).
IconData layerKindIcon(LayerKind kind) {
  return switch (kind) {
    LayerKind.animation => Icons.brush_outlined,
    LayerKind.storyboard => Icons.auto_stories_outlined,
    LayerKind.image => Icons.image_outlined,
    LayerKind.text => Icons.title_outlined,
    LayerKind.se => Icons.music_note_outlined,
    LayerKind.instruction => Icons.theaters_outlined,
    LayerKind.camera => Icons.videocam_outlined,
    LayerKind.folder => Icons.folder_outlined,
    // The sliders glyph: an adjustment row IS its parameters.
    LayerKind.adjustment => Icons.tune,
  };
}

/// The kind's display name for the legend's kind-solo flyout.
String layerKindDisplayName(LayerKind kind) {
  return switch (kind) {
    LayerKind.animation => 'Animation',
    LayerKind.storyboard => 'Storyboard',
    LayerKind.image => 'Image',
    LayerKind.text => 'Text',
    LayerKind.se => 'SE',
    LayerKind.instruction => 'Instruction',
    LayerKind.camera => 'Camera',
    LayerKind.folder => 'Folder',
    LayerKind.adjustment => 'Adjustment',
  };
}

/// Chip color of [mark]; null for [LayerMark.none].
Color? layerMarkColor(LayerMark mark) {
  return switch (mark) {
    LayerMark.none => null,
    LayerMark.red => const Color(0xFFE05A4E),
    LayerMark.orange => const Color(0xFFE08D3C),
    LayerMark.yellow => const Color(0xFFE3C64B),
    LayerMark.green => const Color(0xFF7CB65B),
    LayerMark.teal => const Color(0xFF3FBFC9),
    LayerMark.blue => const Color(0xFF5B8DD9),
    LayerMark.purple => const Color(0xFF9B6BD3),
    LayerMark.pink => const Color(0xFFD972A8),
  };
}

String layerMarkDisplayName(LayerMark mark) {
  final name = mark.jsonValue;
  return name[0].toUpperCase() + name.substring(1);
}

class LayerTimesheetToggleButton extends StatelessWidget {
  const LayerTimesheetToggleButton({
    super.key,
    required this.keyPrefix,
    required this.layerId,
    required this.onTimesheet,
    required this.onToggle,
  });

  final String keyPrefix;
  final LayerId layerId;
  final bool onTimesheet;
  final ValueChanged<LayerId> onToggle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Tight SizedBox: the M3 IconButton otherwise inflates its layout box to
    // the 48px minimum tap target, overflowing the XSheet header column.
    return SizedBox(
      width: layerTimesheetSlotWidth,
      height: layerTimesheetSlotWidth,
      child: IconButton(
        key: ValueKey<String>('$keyPrefix-layer-timesheet-$layerId'),
        tooltip: onTimesheet ? 'Remove from timesheet' : 'Add to timesheet',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(
          width: layerTimesheetSlotWidth,
          height: layerTimesheetSlotWidth,
        ),
        icon: Icon(
          onTimesheet ? Icons.table_chart : Icons.table_chart_outlined,
          size: 16,
          color: onTimesheet
              ? AppColors.accent
              : colorScheme.onSurface.withValues(alpha: 0.35),
        ),
        onPressed: () => onToggle(layerId),
      ),
    );
  }
}

/// The attach ARROW, in the TIMESHEET slot (R10 R3).
///
/// It used to sit in the type cell, where it displaced the kind icon — so
/// an attach row was the one row that could not say what kind of row it
/// was. The sheet slot next door was reserved and EMPTY on exactly those
/// rows (an attach row is a display accessory of its base, never a sheet
/// column; a folder prints nothing), so the arrow moved into a hole that
/// was already the right shape.
///
/// [Icons.subdirectory_arrow_right] points DOWN-right natively; the
/// above-placement arrow is that glyph mirrored vertically.
class LayerAttachArrowCell extends StatelessWidget {
  const LayerAttachArrowCell({
    super.key,
    required this.keyPrefix,
    required this.idValue,
    required this.placement,
  });

  final String keyPrefix;
  final String idValue;
  final AttachedPlacement placement;

  @override
  Widget build(BuildContext context) {
    final above = placement == AttachedPlacement.above;
    return SizedBox(
      width: layerTimesheetSlotWidth,
      height: layerTimesheetSlotWidth,
      child: Center(
        child: Semantics(
          label: above ? 'Attach layer (above)' : 'Attach layer (below)',
          container: true,
          child: ExcludeSemantics(
            child: Transform.flip(
              flipY: above,
              child: Icon(
                Icons.subdirectory_arrow_right,
                key: ValueKey<String>('$keyPrefix-layer-attach-arrow-$idValue'),
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LayerMarkChip extends StatelessWidget {
  const LayerMarkChip({
    super.key,
    required this.keyPrefix,
    required this.layerId,
    required this.mark,
    required this.onMarkSelected,
  });

  final String keyPrefix;
  final LayerId layerId;
  final LayerMark mark;
  final void Function(LayerId layerId, LayerMark mark) onMarkSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<LayerMark>(
      key: ValueKey<String>('$keyPrefix-layer-mark-$layerId'),
      tooltip: AppText.strings.tlLayerMark,
      popUpAnimationStyle: instantMenuAnimation,
      padding: EdgeInsets.zero,
      onSelected: (selected) => onMarkSelected(layerId, selected),
      itemBuilder: (context) => [
        for (final option in LayerMark.values)
          PopupMenuItem<LayerMark>(
            key: ValueKey<String>('layer-mark-option-${option.jsonValue}'),
            value: option,
            height: 36,
            child: Row(
              children: [
                _MarkSwatch(mark: option),
                const SizedBox(width: 10),
                Text(layerMarkDisplayName(option)),
              ],
            ),
          ),
      ],
      child: Semantics(
        label: AppText.strings.tlLayerMark,
        button: true,
        child: _MarkSwatch(mark: mark),
      ),
    );
  }
}

class _MarkSwatch extends StatelessWidget {
  const _MarkSwatch({required this.mark});

  final LayerMark mark;

  @override
  Widget build(BuildContext context) {
    final color = layerMarkColor(mark);
    return Container(
      width: layerMarkSlotWidth,
      height: layerMarkSlotWidth,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: color == null
            ? Border.all(color: AppColors.hairlineStrong)
            : null,
      ),
    );
  }
}
