import 'package:flutter/material.dart';

import '../../models/app_language.dart' show AppLanguage;
import '../input/value_control_pointers.dart';
import '../../models/attached_placement.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';
import '../../models/layer_process.dart';
import '../theme/app_theme.dart';
import '../theme/layer_mark_palette.dart';
import '../widgets/panel_flyout.dart';
import '../text/app_strings.dart';
// The fit math the band shares with the renderer (㉑): the cells a label
// costs and the cells a span holds.
import '../text/vertical_writing.dart'
    show verticalTextCapacityCells, verticalTextCells, verticalTextSpanCount;
import '../text/vertical_writing_text.dart';
// The default paper: [LayerMark.none] IS it (⑲/⑳).
import 'timeline_cell_style.dart'
    show timelineDrawingHeldColor, timelineTextOnColor;

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

  /// The tag's type. Named because the FIT math and the painter have to read
  /// the same two numbers — [sectionBandLabelWithin] decides whether the
  /// whole word fits, and a band that decided with a different font size
  /// than it draws with would abbreviate the wrong labels.
  static const double fontSize = 9;
  static const double lineHeight = 1.15;

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
      //
      // It announces the WHOLE word even when the band is too short to draw
      // it (㉑): shortening is a drawing decision, and a reader that said
      // 'C' would be reading the geometry instead of the section.
      child: Semantics(
        container: true,
        label: label,
        child: ExcludeSemantics(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // The scaled size, because that is what the column is set in:
              // an accessibility scaler makes CAM need MORE room, and a fit
              // computed at 9pt would keep promising a word that no longer
              // fits.
              final scaled = MediaQuery.textScalerOf(context).scale(fontSize);
              final shown = sectionBandLabelWithin(
                label,
                extent: constraints.maxHeight,
                cellExtent: scaled * lineHeight,
              );
              return Center(
                child: ClipRect(
                  child: VerticalWritingText(
                    text: shown,
                    // ACTION / SE / CAM stand UP (user, 2026-08-08). Lying
                    // down is the Japanese standard and it is what the
                    // printed sheet keeps, but this band is a three-letter
                    // tag you glance at, and glancing at it meant tilting
                    // your head.
                    latinForm: VerticalLatinForm.upright,
                    lineHeight: lineHeight,
                    style: TextStyle(
                      fontSize: fontSize,
                      // Dropped with the turn: letter spacing is a
                      // HORIZONTAL notion and the renderer zeroes it anyway
                      // (the leading comes from the cell extent), so
                      // carrying it here only said something untrue about
                      // the label.
                      fontWeight: FontWeight.bold,
                      height: lineHeight,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The tag a band [extent] tall can actually show: the whole word, or — when
/// it does not fit — the word's INITIAL.
///
/// ㉑ (user, 2026-08-12): the storyboard's transition section is one 30px row
/// tall, and `CAM` set in that column came out as a `C` over a rotated
/// ellipsis — 「`CI`처럼 잘려 보인다」. The label was not the bug and the panel
/// was not either: three glyph cells at 9pt/1.15 need 31px and the band has
/// 29, so it ellipsised exactly as [VerticalTextOverflow.ellipsis] promises.
///
/// ★An ellipsis earns its place when it stands for text you could go and
/// READ — a layer name, a blend mode. Standing for the rest of a three-letter
/// tag it stands for nothing: there is no wider band to see `CAM` in, and the
/// `⋮` it draws is a letter-shaped smudge. An abbreviation that will not fit
/// abbreviates further, and one letter is where that ends.
///
/// Deliberately NOT the general text rule (`Background` still wants `Backg…`,
/// not `B`): this is the rule for a fixed tag out of a closed set, where the
/// first letter still tells the sections apart. It fires ONLY where the label
/// is being cut today, so no band that reads correctly now can change.
String sectionBandLabelWithin(
  String label, {
  required double extent,
  required double cellExtent,
}) {
  if (label.isEmpty || !extent.isFinite || cellExtent <= 0) {
    return label;
  }
  final cells = verticalTextCells(
    label,
    latinForm: VerticalLatinForm.upright,
  );
  final needed = verticalTextSpanCount(cells);
  final capacity = verticalTextCapacityCells(
    mainExtent: extent,
    naturalCellExtent: cellExtent,
  );
  if (capacity >= needed) {
    return label;
  }
  // Grapheme clusters, not code units: the tag is Latin today but the rule
  // has to survive being translated, and half of a combining pair is not an
  // initial.
  return label.characters.first;
}

const double layerTimesheetSlotWidth = 20;

/// A6 (2026-08-17): the colour label's slot is HALF the canonical row
/// height by law (「가로폭 = 세로의 절반」) — 28/2 = 14. Written as a
/// number rather than `timelineLayerRowHeight / 2` only to keep this file
/// free of the metrics import; the ratio is pinned by the A6 geometry
/// test. Storyboard rows are 30px tall and share the slot unchanged — the
/// cross-surface column parity this skeleton exists for outranks an exact
/// half on a non-canonical row height.
const double layerMarkSlotWidth = 14;

/// 테이크 라벨의 슬롯 — 색 라벨과 **같은 폭, 바로 오른쪽**(I-5, 유저
/// 2026-08-27: 「위치는 색 라벨 바로 오른쪽에 색 라벨이랑 **같은 디자인**」).
const double layerTakeSlotWidth = layerMarkSlotWidth;

/// 두 라벨이 함께 차지하는 자리. ⚠️레일이 예약하는 것은 이 폭이고,
/// **테이크가 없는 행도 똑같이 예약한다** — ⛔없다가 생기는 UI 금지.
const double layerLabelSlotWidth = layerMarkSlotWidth + layerTakeSlotWidth;
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

/// A property lane's VALUE readout — a real column, like every other slot
/// on this rail (R5 #20).
///
/// It used to be an `Expanded` beside a `Flexible` label, which is not a
/// column at all: two flex children of weight 1 split the leftover in half,
/// so the value's right edge sat at the middle of whatever the label did
/// not use — and what the label uses is its NAME. `Anchor Point` and
/// `Position` therefore parked their numbers at different x on adjacent
/// rows. The alignment was never the problem; there was nothing to align
/// to.
const double layerLaneValueSlotWidth = 80;

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
        child: RailControlPointer(child: PanelFlyoutButton(
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
        )),
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

/// Almost every layer kind shows the opacity slider (unified layer controls
/// — "레이어는 싹 다 공통화"): compositing cels use it directly, the CAMERA
/// row's slider drives the camera-view DIM opacity, and instruction rows
/// carry the same control for entrance parity.
///
/// ⛔The TRANSITION row does not. It is the one row that carries no picture
/// of its own — it says WHEN two cuts cross-dissolve — so there is nothing
/// for a slider to fade, and [layerKindHasPictureOpacity] has answered false
/// for it all along. 유저 2026-08-12: 「타임라인에서 fx랑 불투명도 뺌」.
///
/// 🚨★These two predicates took a `kind` and returned a bare `true`, which
/// is how the timeline came to draw controls the storyboard's own transition
/// row never had: one panel asked a question that could not say no, the
/// other simply did not build the cells. A predicate that ignores its
/// argument is a constant wearing a predicate's clothes — and it hides
/// exactly this class of drift.
bool layerKindShowsOpacityControl(LayerKind kind) =>
    kind != LayerKind.transition;

/// Almost every layer kind shows the fx switch (unified layer controls):
/// drawing cels and SE rows bypass their composite-time transform/opacity
/// (SE fx move the canvas dialogue), the CAMERA row bypasses the camera work
/// on the render routes (playback/export/thumbnails — authoring overlays
/// keep the real pose), and instruction rows carry the switch as authored
/// state for entrance parity.
///
/// ⛔The TRANSITION row does not — see [layerKindShowsOpacityControl]. It
/// composites nothing, so it has no fx chain to bypass; what it does own is
/// a VISIBILITY toggle, which is a different verb (apply this O.L / F.O on
/// playback or do not).
bool layerKindShowsFxToggle(LayerKind kind) => kind != LayerKind.transition;

/// The ONE style a row's NAME is written in — the timeline rail's row, the
/// x-sheet's column, and the storyboard's V and S rows.
///
/// 🚨F-26 (유저 2026-08-24): 「레이어명의 폰트가 다른거같음. 가로모드는
/// 볼드체에 글자크기도 큰거같은데 x시트는 글자 얇고 작은거같음. **가로모드에
/// 맞춰서 통일**하고, 스토리보드패널도 겸사겸사 싹 다 폰트 통일. 지금 우선
/// V1라는 글자만 볼드체인거 **굉장히 통일감면에서 이상함**」.
///
/// ★The horizontal rail is the reference the user named, and what it does is
/// nothing: it never set a style, so its name takes the surface's body text.
/// So this IS that — named, so the other two have somewhere to point instead
/// of each typing a number of their own. The x-sheet's `fontSize: 11` and
/// the storyboard's `FontWeight.bold` are what "each typing its own" looked
/// like, and they are gone.
///
/// ⛔Not a colour. A row's name is coloured by what the row IS (disabled,
/// posed, a section's), which is the caller's business — this answers the
/// one question they were all answering differently.
TextStyle layerRowNameStyle(BuildContext context) =>
    DefaultTextStyle.of(context).style;

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
      child: RailControlPointer(child: IconButton(
        key: ValueKey<String>(keyValue),
        tooltip: isVisible ? 'Hide $subject' : 'Show $subject',
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: size, height: 26),
        icon: Icon(
          isVisible ? Icons.visibility : Icons.visibility_off,
          size: iconSize,
        ),
        onPressed: onToggle,
      )),
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
    return RailControlPointer(child: IconButton(
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
    ));
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
      child: RailControlPointer(child: IconButton(
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
      )),
    );
  }
}

/// The row kind icon (shared by the rail rows and the legend's kind-solo
/// flyout, R4 #8).
IconData layerKindIcon(LayerKind kind) {
  return switch (kind) {
    // The framed-picture glyph: a CEL. 유저 2026-08-12 — the brush was the
    // odd one out, and not because of how it looked: every other kind here
    // names WHAT THE ROW IS (a book, a photo, a note, a camera) while this
    // one named the TOOL you draw it with. A row is a noun.
    //
    // 🚨F-6, decided 2026-08-26 — and it came out the other way round from
    // how the round was framed. The plan was "the animation row takes the
    // picture glyph, the image row gets something new"; the user looked at
    // the candidates and swapped which row moved:
    //
    // > 「이미지는 지금의 액자 그림을 그냥 다시 이미지레이어 아이콘으로 하고,
    // > **겹친 장을 애니메이션레이어 아이콘으로** 하자」
    //
    // ★And that reads better, which is why it is worth recording rather
    // than just applying: an ANIMATION row is several drawings — the
    // stacked sheets say exactly that — while the IMAGE row is one picture,
    // which the single framed picture already said. The row that needed a
    // new noun was the one holding many, not the one holding one.
    LayerKind.animation => Icons.filter_outlined,
    LayerKind.storyboard => Icons.auto_stories_outlined,
    LayerKind.image => Icons.image_outlined,
    LayerKind.text => Icons.title_outlined,
    LayerKind.se => Icons.music_note_outlined,
    LayerKind.instruction => Icons.theaters_outlined,
    // The cross-fade glyph: a transition span is two pictures overlapping.
    LayerKind.transition => Icons.compare_arrows_outlined,
    LayerKind.camera => Icons.videocam_outlined,
    LayerKind.folder => Icons.folder_outlined,
    // The sliders glyph: an adjustment row IS its parameters.
    LayerKind.adjustment => Icons.tune,
  };
}

/// The kind's display name for the legend's kind-solo flyout.
/// A row kind's name, in the program's language.
///
/// It used to be ten hardcoded English literals living beside a `tlKind*`
/// table that had eight of the same names translated, so the SAME row read
/// 「디렉션」 in the toolbar and `Direction` in the kind flyout. The table
/// was not missing a translator — it was missing two KINDS (`transition`,
/// `camera`), and this switch was where they had quietly gone instead.
///
/// ⚠️Trade terms stay in their own script or in English (user 2026-08-12:
/// 「현장용어만 원어/영어로 두기로 하자」): SE, Transition, Direction. That
/// is a decision about the WORDS and it lives in the tables, not here.
String layerKindDisplayName(LayerKind kind) {
  final strings = AppText.strings;
  return switch (kind) {
    LayerKind.animation => strings.tlKindAnimation,
    LayerKind.storyboard => strings.tlKindStoryboard,
    LayerKind.image => strings.tlKindImage,
    LayerKind.text => strings.tlKindText,
    LayerKind.se => strings.tlKindSe,
    LayerKind.instruction => strings.tlKindInstruction,
    LayerKind.transition => strings.tlKindTransition,
    LayerKind.camera => strings.tlKindCamera,
    LayerKind.folder => strings.tlKindFolder,
    LayerKind.adjustment => strings.tlKindAdjustment,
  };
}

/// Chip colour of [mark] — and, since ⑲, the colour of that layer's frame
/// BLOCKS as well.
///
/// ⑳ (user, 2026-08-12): 「레이어 색라벨 기본 = 흰색(지금은 프로그램
/// 바탕색)」. It used to be null, drawn as a hole with a hairline round it,
/// which is what made ⑲ read as a change at all: an unlabelled layer's
/// blocks are [timelineDrawingHeldColor] and always have been, so saying
/// 「none IS the paper」 makes the default label WHITE and leaves every
/// unlabelled row painted by exactly the number it was painted by before.
///
/// The two items are one statement, and this is where it is written: a
/// layer's mark is the colour of its paper. Nothing is lost by dropping the
/// null — 「is there a mark」 is `mark == LayerMark.none`, which is what the
/// question was always really asking.
/// 🚨THE EIGHT LITERAL COLOURS ARE GONE, and that is the point of the round:
/// a mark names a 공정/수정 and the colour is looked up from that name, so a
/// hue fix edits one row and every block in the project moves with it —
/// without touching a layer.
///
/// 🪦고를 수 있는 톤이 넷이었고(I-4), 크림으로 확정된 뒤 나머지와 고르는
/// 장치를 걷었다. 이력은 [resolveLayerMarkColor] 의 문서에 있다.
///
/// ⚠️`none` still resolves to [timelineDrawingHeldColor] for the reason
/// written just above — 「none IS the paper」 — so an unlabelled row is
/// painted by exactly the number it was painted by before.
Color layerMarkColor(LayerMark mark) => resolveLayerMarkColor(
  mark,
  noneColor: timelineDrawingHeldColor,
);

/// The unabbreviated reading — 「축약어 쓰지 않을때는 축약하지마」. The chip
/// writes the abbreviations through [layerMarkChipText] instead.
///
/// 🚨Through [layerMarkLabel], so the reading follows the program language
/// (유저 2026-08-28). `mark.displayName` would be the English row.
String layerMarkDisplayName(LayerMark mark) =>
    mark.isNone ? AppText.strings.tlLayerMarkNone : layerMarkLabel(mark);

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
      child: RailControlPointer(child: IconButton(
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
      )),
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
              child: layerAttachmentArrowIcon(
                context,
                key: ValueKey<String>('$keyPrefix-layer-attach-arrow-$idValue'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


// 🪦THE FOLDER-NESTING ARROW LIVED HERE (R5 #18).
//
// A row inside a folder drew a ↳ in the last of its indent cells, saying it
// hung off the folder above. 🚨F-30 (유저 2026-08-24) had already made it
// share the attach arrow's DRAWING rather than just its codepoint — 「폴더
// 화살표는 어태치 것과 생김새·색이 달라 같은 것을 재사용할 것」, after one
// was 14px at 55% alpha and the other 16px at full strength.
//
// 2026-08-29 removed the indent cells themselves: depth moved into the NAME
// column so the buttons keep one x at every depth. With no cell to draw in,
// the arrow went too — and with it the rule that a row carrying an ATTACH
// arrow had to keep the cell and give up this glyph, because two arrows a
// column apart answered one question twice. There is one arrow again.

/// THE arrow that says "this row hangs off the one above it" — one size, one
/// colour, whether the thing above is a folder or an attach base.
Widget layerAttachmentArrowIcon(BuildContext context, {Key? key}) => Icon(
  Icons.subdirectory_arrow_right,
  key: key,
  size: 16,
  color: Theme.of(context).colorScheme.onSurfaceVariant,
);

class LayerMarkChip extends StatelessWidget {
  const LayerMarkChip({
    super.key,
    required this.keyPrefix,
    required this.layerId,
    required this.mark,
    required this.onMarkSelected,
    this.axis = Axis.horizontal,
  });

  final String keyPrefix;
  final LayerId layerId;
  final LayerMark mark;
  final void Function(LayerId layerId, LayerMark mark) onMarkSelected;

  /// The rail's own direction — the x-sheet's stood-up column header passes
  /// vertical, where the slot is 14px TALL and the plate wears no text.
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    // 🚨★★★TWO PLATES, ONE UNIT. 유저 2026-08-27: 「위치는 색 라벨 **바로
    // 오른쪽**에 색 라벨이랑 **같은 디자인**으로」. They share this widget
    // rather than getting one each because they also share the callback —
    // a take is part of the mark, so setting one is `mark.withTake(n)` and
    // no second channel had to be opened for it.
    //
    // ⚠️ALONG THE RAIL'S OWN AXIS. The x-sheet stands the rail up, so its
    // column header runs DOWN — laying the pair out sideways there put both
    // plates outside the header's width and took a hundred x-sheet tests
    // with it. The slot ([layerLabelSlotWidth]) is measured along the same
    // axis, so the two have to agree.
    final horizontal = axis == Axis.horizontal;
    final plates = [
      SizedBox(
        width: horizontal ? layerMarkSlotWidth : null,
        height: horizontal ? null : layerMarkSlotWidth,
        child: _markTrigger(context),
      ),
      SizedBox(
        width: horizontal ? layerTakeSlotWidth : null,
        height: horizontal ? null : layerTakeSlotWidth,
        child: _takeTrigger(context),
      ),
    ];
    // 🚨STRETCH ON THE CROSS AXIS. The plate is `SizedBox.expand` — it fills
    // the slot edge to edge (⑳, 「패딩 절대 금지」) — so it needs a BOUNDED
    // extent both ways. Putting a plain Row between it and the slot left the
    // cross axis unbounded and the plate could not lay out at all: measured,
    // 「RenderBox was not laid out」 across a hundred tests that never mention
    // a label.
    return horizontal
        ? Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: plates,
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: plates,
          );
  }

  /// 테이크 라벨 — 1–9, 기본은 없음.
  ///
  /// ⚠️The plate is painted whether or not a take is set, so the name beside
  /// it never slides when one appears (⛔없다가 생기는 UI 금지). Its fill is
  /// the paper colour, which is also the 「색은 흰색 하나」 the user asked for:
  /// a take is an ORDER, not a kind, and nine colours would fight the
  /// stage's.
  Widget _takeTrigger(BuildContext context) {
    return RailControlPointer(
      child: PanelFlyoutTrigger(
        key: ValueKey<String>('$keyPrefix-layer-take-$layerId'),
        tooltip: AppText.strings.tlLayerTake,
        padding: EdgeInsets.zero,
        // ⛔No 「없음」. 유저 2026-08-27: 「테이크도 … 라벨없음 삭제해. 테이크는
        // **기본값 T1**」 — a drawing is always some pass, so the first one is
        // 1 rather than an absence. (색 라벨 keeps its 없음: 「색라벨은
        // 라벨없음 그대로 두자」.)
        entriesBuilder: () => [
          for (final take in LayerMark.takeChoices)
            PanelFlyoutItem(
              keyValue: 'layer-take-option-$take',
              label: AppText.strings.tlLayerTakeNumber(take),
              selected: take == mark.take,
              onSelected: () => onMarkSelected(layerId, mark.withTake(take)),
            ),
        ],
        child: Semantics(
          label: AppText.strings.tlLayerTake,
          button: true,
          child: _TakeText(mark: mark, axis: axis),
        ),
      ),
    );
  }

  Widget _markTrigger(BuildContext context) {
    // R6 #4, the last of the five raw `PopupMenuButton`s: this one held out
    // because its rows name COLOURS, and the shared list had no way to show
    // one — see [PanelFlyoutItem.swatch]. Its own row height was 36, a sixth
    // number in a menu system that was supposed to have one.
    return RailControlPointer(child: PanelFlyoutTrigger(
      key: ValueKey<String>('$keyPrefix-layer-mark-$layerId'),
      tooltip: AppText.strings.tlLayerMark,
      // ZERO, not the trigger's usual 8: the mark sits in a fixed
      // `layerMarkSlotWidth` rail column, so padding here would not grow a
      // hit area — it would push every slot after it out of the rail.
      padding: EdgeInsets.zero,
      // 🚨★★★TWO AXES, TWO LEVELS. 유저 설계(I-4): 「위에서부터 콘티,레이아웃,
      // 러프원화,원화,동화,시아게 가 있고, 거기 **호버하면 추가로 앵커팝오버로
      // 수정라벨이 뜨도록**. 즉 축으로서 2가지가 존재하도록」.
      //
      // ⛔I built this flat once and wrote 「TWO AXES, ONE LIST」 in the
      // comment. 유저: 「니가 아티팩트로 제시한거랑 이거랑 똑같다고
      // 생각하냐? … **대체 왜 정한대로 안만드는거야?**」 — the second axis
      // exists precisely so it is not all on screen at once, and flattening
      // it turned eight stages into forty-odd rows.
      //
      // ⛔The revise list is not copied per process either: [revisesFor]
      // answers from the ONE [LayerRevise] set, so renaming a revise renames
      // it everywhere and 원화 can drop 동화검사 without the others noticing.
      entriesBuilder: () => [
        PanelFlyoutItem(
          keyValue: 'layer-mark-option-none',
          label: AppText.strings.tlLayerMarkNone,
          swatch: layerMarkColor(LayerMark.none),
          onSelected: () => onMarkSelected(layerId, LayerMark.none),
        ),
        for (final process in LayerProcess.values)
          PanelFlyoutItem(
            // 🚨THE KEY SAYS WHAT THE ROW DOES. A stage that opens a child
            // is `…-stage-…`; a row that PICKS is `…-option-…`. They used
            // to share a key and the submenu's 소재 collided with the parent
            // it hung off — two widgets, one key, and every finder that
            // touched either one broke.
            keyValue: revisesFor(process).isEmpty
                ? 'layer-mark-option-${process.jsonValue}'
                : 'layer-mark-stage-${process.jsonValue}',
            label: layerProcessLabel(process),
            swatch: layerMarkColor(LayerMark(process: process)),
            // 용지 carries no corrections, so it is a plain choice — no
            // chevron, no second level, and picking it labels the row.
            onSelected: revisesFor(process).isEmpty
                ? () => onMarkSelected(layerId, LayerMark(process: process))
                : null,
            submenuBuilder: revisesFor(process).isEmpty
                ? null
                : () => [
                    // 소재(上がり) first — 그 공정의 작업본이다. 이것이
                    // 「수정 없음」 자리를 대신한다.
                    for (final option in [
                      LayerMark(process: process),
                      for (final revise in revisesFor(process))
                        LayerMark(process: process, revise: revise),
                    ])
                      PanelFlyoutItem(
                        keyValue: 'layer-mark-option-${option.keySlug}',
                        label: option.revise == null
                            ? AppText.strings.tlLayerMarkSource
                            : layerReviseLabel(option.revise!),
                        swatch: layerMarkColor(option),
                        onSelected: () => onMarkSelected(layerId, option),
                      ),
                  ],
          ),
      ],
      child: Semantics(
        label: AppText.strings.tlLayerMark,
        button: true,
        // 🚨★★★THE STAGE COMES FIRST — left on the rail, top on the sheet.
        //
        // 유저 2026-08-27 corrected an earlier call of theirs: 「LO작감시 왼쪽에
        // 작감 오른쪽에 LO 오는데, 그게아니라 **평범하게 왼쪽에 LO 오른쪽에
        // 작감** 오도록. 이유는 지금 **레이어영역 자체가 왼쪽부터 오른쪽으로
        // 읽는걸 기준으로** 설계하고있어」.
        //
        // ⚠️The first reading (stage on the right, from Japanese vertical
        // writing) was right about the writing and wrong about the SURFACE:
        // the rail is a left-to-right column of names, and one label
        // reading the other way would be the exception.
        //
        // ⛔Not stacked as two rows on the rail: 「띠가 지금 가로로 얇은거를
        // 살리고싶어서」 — two columns keep the plate as short as one. The
        // sheet stacks instead, because there the plate is wide and short.
        child: _LabelPlate(
          fill: layerMarkColor(mark),
          columns: [
            layerMarkChipText(mark).process,
            layerMarkChipText(mark).revise,
          ],
          axis: axis,
        ),
      ),
    ));
  }
}

/// A6 (2026-08-17): the circle became the label PLATE — the full slot,
/// edge to edge (「패딩 절대 금지」), square corners, with the colour NAME
/// standing upright inside it (「가로쓰기 세로표시」). The click logic above
/// is untouched; only this face changed.
/// 🚨★★★ONE PLATE, TWO LABELS. The colour label and the take label are the
/// same face — 유저 2026-08-27: 「색 라벨이랑 **같은 디자인**으로」 — so this
/// takes the columns to write and the fill to write them on rather than
/// knowing what a mark is. A second widget that merely looked the same
/// would be a copy of a face that is deliberately identical.
/// 한 칸의 글자를 그 레일이 읽는 방향으로 세운다.
///
/// 🚨★★★ONE PLACE decides this. The colour plate and the take chip sit side
/// by side and made the same call separately — 「레일이면 세워 쓰고 x시트면
/// 가로로 쓴다」 — which is a copy even while the two agree. 유저: 「사본
/// 남으면 진짜 용서안할게」.
///
/// ⚠️The plate is a tall sliver beside a rail row and a wide sliver above an
/// x-sheet column, so the same two letters have to run the long way on each.
/// The caller brings its own [style]: the plate takes its ink from the block
/// colour and the take chip from the layer name, and that is a real
/// difference — the direction is not.
Widget layerPlateGlyphs({
  required String text,
  required Axis axis,
  required TextStyle style,
}) => axis == Axis.horizontal
    ? VerticalWritingText(
        text: text,
        latinForm: VerticalLatinForm.upright,
        lineHeight: SectionBandZone.lineHeight,
        // 「길면 글자 축소 허용」 — a long abbreviation packs and shrinks
        // rather than ellipsising. 시아게 is three glyphs where the rest are
        // two, and this is what lets it sit in the same plate.
        overflow: VerticalTextOverflow.pack,
        minFontSize: 4,
        style: style,
      )
    : Text(text, maxLines: 1, style: style);

class _LabelPlate extends StatelessWidget {
  const _LabelPlate({
    required this.fill,
    required this.columns,
    required this.axis,
  });

  final Color fill;

  /// What each vertical column writes, LEFT to RIGHT. Empty strings draw
  /// nothing and still hold the slot.
  final List<String> columns;

  final Axis axis;

  /// The same type the section band's tag wears, one column over.
  /// The same type the section band's tag wears, one column over.
  static const double _fontSize = 9;

  /// 🔒**w400 으로 확정**(유저 2026-08-28: 「일단 정했어. 얇은거. 400으로
  /// 가고싶어」). 고르는 동안은 설정이었다.
  ///
  /// 🧪실기 실측(유저): **100~500 은 얇고, 600~800 은 굵고, 900 은 엄청
  /// 굵다.** ⚠️번들 폰트에 Regular 와 Bold 뿐이니 두 단계일 것이라던 내
  /// 예측은 **틀렸다** — 900 에서 Skia 가 합성 볼드를 얹는다. 파일 목록만
  /// 보고 렌더러의 답을 예측한 대가다.
  static const FontWeight _fontWeight = FontWeight.w400;

  @override
  Widget build(BuildContext context) {
    // ⑳ still holds: every plate is FILLED, `none` included — it is the
    // paper colour rather than a hole in the rail. SizedBox.expand
    // fills the row's height on a horizontal rail and the header's width
    // on the sheet's vertical one; the slot provides the other extent.
    //
    // ⛔The glyphs are drawn STRAIGHT, with whatever anti-aliasing Skia
    // gives them. A `ColorFiltered` alpha step used to sit here — the
    // 「쌩2치화」 round — and why it went is written on
    // [AppAccentSettings], beside the weight that used to be a setting too.
    return SizedBox.expand(
      child: ColoredBox(color: fill, child: _label(fill)),
    );
  }

  /// The colour name, inked by the frame blocks' own luminance law
  /// ([timelineTextOnColor], #1109). Two plates stay bare: the sheet's
  /// vertical header (the slot is 14px TALL there — no column to stack
  /// glyphs in) and `none` (the paper colour has no name to announce; the
  /// plate itself keeps the tap target discoverable).
  /// 🚨★★★TWO COLUMNS, THE STAGE ON THE RIGHT. 유저 2026-08-27: 「세로로 LO가
  /// **오른쪽**에 있고 왼쪽에 세로로 작감 이렇게 있는게 맞을거같은데. **LO가
  /// 오른쪽인건 일본 세로쓰기가 오른쪽에서 왼쪽으로 읽으니까**」.
  ///
  /// ⛔Not stacked as two rows (LO above, 작감 below): 「띠가 지금 가로로
  /// 얇은거를 살리고싶어서」 — the band is [timelineLayerRowHeight] and stays
  /// that height. Two columns keep the plate as short as one.
  ///
  /// The ink is the frame blocks' own — 유저: 「프레임이름/코마숫자/색라벨은
  /// 다 같은 색상의 바탕 위에 올라가는 텍스트니까 **셋 다 같은 로직**」.
  Widget? _label(Color fill) {
    final shown = columns.where((text) => text.isNotEmpty).toList();
    if (shown.isEmpty) {
      return null;
    }
    // 🚨★★★ONE LAW, BOTH RAILS. 유저 2026-08-27: 「x시트 **로직적으로 통일**
    // 하는거 절대잊지말고」 — so the split, the fill and the order are decided
    // HERE once and the axis is the only thing that differs. The x-sheet used
    // to run its own `BoxFit.scaleDown` branch, which is exactly how it kept
    // missing whatever the rail had just learned.
    //
    // 🚨★★★EACH COLUMN FILLS ITS OWN AREA, BOTH WAYS. 유저 2026-08-28:
    // 「2글자로 작감이면 작감 **위 아래에 글자가 남거든**? 이거 그냥 **글자
    // 늘려서 꽉 채우게** 하면 멋있을거같아 … **옆으로도 자기 영역 내에서 꽉
    // 채우게** 하고싶어」.
    //
    // ⚠️`BoxFit.fill`, not `scaleDown`: the glyphs are STRETCHED to the box
    // rather than scaled inside it, so two characters and four fill the same
    // plate. That is also what makes the old 4px overflow impossible —
    // nothing is sized by its natural extent any more.
    //
    // ⛔[Expanded] splits the plate EVENLY, so 공정 and 수정 own half each and
    // neither pushes the other. With one column it takes the whole plate.
    return ClipRect(
      child: Flex(
        // The rail reads left→right, the sheet top→bottom: 유저 2026-08-27
        // 「x시트는 가로쓰기 가로표기로 **위에 LO 아래에 작감**」, and on the
        // rail 「평범하게 **왼쪽에 LO 오른쪽에 작감**」. Same list, laid the
        // way each surface is read.
        direction: axis == Axis.horizontal ? Axis.horizontal : Axis.vertical,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final text in shown)
            Expanded(
              child: FittedBox(fit: BoxFit.fill, child: _glyphs(text, fill)),
            ),
        ],
      ),
    );
  }

  /// One column's characters, through the shared decision.
  Widget _glyphs(String text, Color fill) =>
      layerPlateGlyphs(
    text: text,
    axis: axis,
    style: TextStyle(
      fontSize: _fontSize,
      // ⚠️번들 폰트에는 Regular 와 Bold 만 있다 — 100~900 중 어느 값을 줘도
      // Flutter 는 그 둘 중 가까운 쪽으로 떨어뜨린다.
      fontWeight: _fontWeight,
      height: SectionBandZone.lineHeight,
      color: timelineTextOnColor(fill),
    ),
  );
}

/// 🚨★★★ 유저 #1 (2026-08-14): 「액티브 레이어가 아닌 다른 레이어의 버튼
/// 누르면 작동안함 … 레이어에 있는 **모든 버튼이나 편집이** 그럼」.
///
/// ★A press that lands on a control belongs to that control
/// ([value_control_pointers.dart]). The rail row wraps its whole width in
/// the PICK region, so without this a press on one of these buttons also
/// moved the drawing target — which rebuilt the row out from under the
/// gesture still running on it. A tap survived (it had already fired); a
/// slider drag did not, and a button on a non-active row lost its release.
///
/// ⛔These are raw `IconButton`s rather than [AppIconButton] (which claims
/// on its own), so the claim has to be said here. One wrapper rather than
/// one per button: a control added to this file tomorrow gets it by
/// standing in the same place.
///
/// 🚨B3 (유저 2026-08-17): 「과거 주문 = 비지블·불투명도 **포함 모든 버튼**
/// 비액티브 레이어에서 조작 가능 — 비지블·불투명도만 구현돼 있음」. The eye
/// wore this wrapper and the opacity slider takes the STRONG claim inside
/// [FieldSlider]; every other rail control was still bare, so its press
/// also fired the row's PICK and moved the drawing target. EVERY control in
/// this file — and the row's inline chevrons/toggles — wears the claim now.
/// A press on a rail TOGGLE COLUMN belongs to that column, drag and all.
///
/// 🚨I-1 (유저 2026-08-24): 「레이어의 버튼 조작하는거 **일괄조작**하는 기능
/// … 탭 다운 한 채로 아래로 드래그하면 **해당 다른 레이어도 버튼조작**되도록」.
///
/// ⛔[RailControlPointer]'s claim is the WEAK one on purpose, and the reason
/// is written where it lives: 「a button owns its TAP; it does not own drags
/// — claiming the pointer outright broke a real one, because the
/// storyboard's row-order drag deliberately starts ON the visibility
/// button」. That is still true of the storyboard. It stopped being true of
/// the RAIL the moment a drag from a rail button became a verb of its own,
/// and until then the rail's Krita-style eye swipe could never run at all:
/// the row's eager pan won every gesture that started on the eye.
///
/// ⇒ The strong claim, applied by the RAIL to the columns it can swipe —
/// never by the widget, which the storyboard shares.
///
/// ⚠️Keep this in step with the grid's swipe column list. A column that
/// claims but is not listed swallows drags for nothing; one that is listed
/// but does not claim is unreachable, which is exactly the state the eye
/// was found in.
///
/// The LEADING columns wear it too now — the sheet toggle the report named
/// and the lane twirl beside it. They are worn HERE, at the rail's call
/// site, rather than inside the buttons: the x-sheet's column header uses
/// the same timesheet widget and has no swipe to claim for.
class RailSwipeColumnPointer extends StatelessWidget {
  const RailSwipeColumnPointer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        claimTapForControl(event.pointer);
        claimPointerForValueControl(event.pointer);
      },
      onPointerUp: (event) {
        releaseTapForControl(event.pointer);
        releasePointerForValueControl(event.pointer);
      },
      onPointerCancel: (event) {
        releaseTapForControl(event.pointer);
        releasePointerForValueControl(event.pointer);
      },
      child: child,
    );
  }
}

class RailControlPointer extends StatelessWidget {
  const RailControlPointer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) => claimTapForControl(event.pointer),
      onPointerUp: (event) => releaseTapForControl(event.pointer),
      // ⛔Cancel too: a claim that outlives its gesture silently deafens
      // every later press handed the same pointer id.
      onPointerCancel: (event) => releaseTapForControl(event.pointer),
      child: child,
    );
  }
}

/// 테이크 라벨의 얼굴 — **바탕 없이 글자만**.
///
/// 🚨유저 2026-08-27: 「테이크라벨은 **배경 삭제**해. 그러고 글자만 심플하게
/// **레이어이름처럼 디자인 통일**해서 흰색계열」.
///
/// ⛔So it does NOT reuse [_LabelPlate]: a plate is a filled slot, and this
/// is writing on the rail. What it reuses instead is the thing it was told
/// to match — [layerRowNameStyle], the very style the layer's name is set
/// in, so the two stay one decision. A copied `TextStyle` here would be the
/// second place to edit the day that style changes.
class _TakeText extends StatelessWidget {
  const _TakeText({required this.mark, required this.axis});

  final LayerMark mark;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final style = layerRowNameStyle(context).copyWith(
      fontSize: 9,
      fontWeight: FontWeight.bold,
      height: SectionBandZone.lineHeight,
    );
    return ClipRect(
      // ⛔NOT stretched. 유저 2026-08-28: 「테이크 글자는 이전처럼 flex하지말고
      // **그냥 평범하게** 하자」 — the colour plate fills its slot because the
      // fill IS the label there; T1 is just a number and reads better at its
      // own size.
      //
      // ⚠️The writing direction still comes from [layerPlateGlyphs]: standing
      // the glyphs up on the rail and laying them across on the sheet is the
      // shared decision, and only the FILL was ever this chip's own choice.
      child: Center(
        child: layerPlateGlyphs(text: mark.takeText, axis: axis, style: style),
      ),
    );
  }
}

/// 공정의 이름과 축약어, **번역을 거쳐서**.
///
/// 🚨★★★유저 2026-08-28: 「프로그램 언어에따라 **로컬라이즈 안되니까** 해주고」.
/// The enum in `models/` carries the English wording (it may not import
/// `ui/`), and everything the user reads goes through here — so a Japanese
/// UI stops showing 「용지」 beside 「ラベルなし」.
///
/// ⛔ONE pair of accessors, called by the plate, the flyout and the tooltip
/// alike. A surface that read `process.displayName` directly would be the
/// one place that never translates.
String layerProcessLabel(LayerProcess process) =>
    AppText.strings.layerProcessName(process.jsonValue, process.displayName);

String layerProcessAbbrev(LayerProcess process) =>
    AppText.strings.layerProcessAbbrev(process.jsonValue, process.abbreviation);

String layerReviseLabel(LayerRevise revise) =>
    AppText.strings.layerReviseName(revise.jsonValue, revise.displayName);

String layerReviseAbbrev(LayerRevise revise) =>
    AppText.strings.layerReviseAbbrev(revise.jsonValue, revise.abbreviation);

/// What the chip writes, translated — the pair the plate stacks.
///
/// ⚠️It lives beside the accessors rather than on [LayerMark] for the same
/// reason they do: the model cannot see the string tables.
({String process, String revise}) layerMarkChipText(LayerMark mark) => (
  process: mark.process == null ? '' : layerProcessAbbrev(mark.process!),
  revise: mark.revise == null ? '' : layerReviseAbbrev(mark.revise!),
);

/// The unabbreviated reading — tooltips and the flyout.
String layerMarkLabel(LayerMark mark) {
  final stage = mark.process;
  if (stage == null) {
    return '';
  }
  final correction = mark.revise;
  return correction == null
      ? layerProcessLabel(stage)
      : '${layerProcessLabel(stage)} ${layerReviseLabel(correction)}';
}
