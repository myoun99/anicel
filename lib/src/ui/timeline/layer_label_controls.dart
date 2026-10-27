
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show BoxHitTestEntry;

import '../input/control_press_claim.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/field_slider.dart';
import '../../models/attached_placement.dart';
import '../../models/layer.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';
import '../../models/layer_process.dart';
import '../theme/app_theme.dart';
import '../theme/layer_mark_palette.dart';
import '../widgets/panel_flyout.dart';
import '../text/app_strings.dart';
import '../text/model_vocabulary.dart';
import '../text/text_measure.dart';
// The fit math the band shares with the renderer (㉑): the cells a label
// costs and the cells a span holds.
import '../text/vertical_writing.dart'
    show verticalTextCapacityCells, verticalTextCells, verticalTextSpanCount;
import '../text/vertical_writing_text.dart';
// The default paper: [LayerMark.none] IS it (⑲/⑳).
import 'timeline_cell_style.dart'
    show timelineDrawingHeldColor, timelineTextOnColor;
import 'axis_turn.dart';
import 'berth_row.dart';
import 'memo_token.dart' show KeptPiece;
import '../widgets/named.dart';
import '../widgets/rail_glyph_button.dart';
import '../widgets/tick_text.dart' show textLineTypeIn;
import 'layer_plate_words.dart';

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
///
/// ★It IS the box — the slot along [axis], all the room the other way —
/// rather than a widget building a box around a box that fills: one
/// element where three stood, in every row of every rail, paid on every
/// panel reopen (card frame-panels-build-in-one-frame, 2026-10-25).
class LayerSectionBandCell extends SizedBox {
  LayerSectionBandCell({super.key, this.axis = Axis.horizontal})
    : super.fromSize(
        size: sizeAlong(
          axis,
          along: layerSectionLabelSlotWidth,
          across: double.infinity,
        ),
      );

  /// The rail's own direction — the slot's extent is measured along it, and
  /// the cell fills the other way (R10 R6).
  final Axis axis;
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
class SectionBandZone extends KeptPiece {
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

  /// What the band shows. ↩️Built again with its rail, the band handed its
  /// LayoutBuilder a new builder, which ran again in layout and so painted
  /// the rail's whole viewport (I-57, 10-14 — 🔬78 render objects of a
  /// storyboard crossing).
  @override
  Object? get facts => (label, extent);

  @override
  Widget buildKept(BuildContext context) {
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
  final cells = verticalTextCells(label, latinForm: VerticalLatinForm.upright);
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
const double layerClipSlotWidth = 22;
const double layerFxSlotWidth = 22;
const double layerVisibilitySlotWidth = 22;

// 64 → 42 (UI-R18 #4): the opacity bar reads fine at two-thirds width
// across all three panels' rails.
// 42 → 51 (text-scale-rail-opac, 유저 2026-09-25: 「칸을 가장 넓은 글자에
// 맞게 1배부터 넓힌다」): the legend's resting OPAC wanted 34.8 in the bar's
// 26 at 1× — short from the start, which growing with the text could never
// mend. The rails pay the 9.
// 51 → 44 (F-409, 유저 2026-10-19): 「불투명도 바, 너무 김. … 100이라는
// 숫자가 딱 들어갈 정도면 됨. 레전드도 그로인해 OPAC라는 글자가 OPA나 OP로
// 되도됨」. The bar is its insets and 「100」 (23.7 at 1×) — 40 — and the
// slot gives it a chip gap besides (`layerRailTrailingCells`); the legend
// says OP, which fits.
const double layerOpacitySlotWidth = 44;

/// R27 #6: the BLEND column — the layer's compositing mode, moved out of
/// the timeline toolbar and into the label itself (PS/CSP reading: the
/// mode belongs to the row, not to a far-away command bar). Rightmost
/// slot, immediately right of the opacity bar, per the user's placement.
///
/// 58 → 62 (F-409): the chip keeps its 58 and the slot pays its
/// chip gap (`layerRailTrailingCells`).
const double layerBlendSlotWidth = 62;

/// The rail's columns that hold WORDS — the opacity bar's digits, the
/// blend chip's mode and a lane's value boxes ([layerLaneValueSlotWidth])
/// — as wide as they are where the rail is shown. Every other column holds
/// an icon, and icons do not follow the OS text size.
///
/// 🚨text-scale-rail-columns (유저 2026-09-25, 「칸도 글자 따라 넓어진다」):
/// a column's 1× slot plus as much as its widest word grew — 0 at 1×, so
/// nothing drawn at 1× moves — and the rail pays for it, as it paid for the
/// blend column (R27 #6). 🔬At 1.5× 「100」 wanted 35.5 in the bar's 26.
typedef LayerRailColumnWidths = ({
  double opacity,
  double blend,
  double laneValue,
});

/// The columns at 1× — what a surface that never asks draws.
const LayerRailColumnWidths layerRailColumnWidthsAtOne = (
  opacity: layerOpacitySlotWidth,
  blend: layerBlendSlotWidth,
  laneValue: layerLaneValueSlotWidth,
);

/// [LayerRailColumnWidths] where [context] lays its text out.
///
/// Remembered against every input it reads — the text scaler, the language
/// and the two styles — so the storyboard's rows, which each ask, lay the
/// words out once between them and not once per row. A change to any input
/// is a different key, so the answer cannot go stale.
LayerRailColumnWidths layerRailColumnWidthsIn(BuildContext context) {
  final key = (
    scaler: MediaQuery.textScalerOf(context),
    language: AppText.language,
    value: FieldSlider.valueStyleIn(context),
    blend: _blendWordStyle(context),
  );
  final remembered = _railColumnsMemo;
  if (remembered != null && remembered.key == key) {
    return remembered.columns;
  }
  final columns = (
    opacity:
        layerOpacitySlotWidth +
        FieldSlider.widthGrowthIn(context, const ['100']),
    blend: layerBlendSlotWidth + layerBlendColumnGrowthIn(context),
    // Two boxes, each as much wider as its name and its widest number.
    laneValue:
        layerLaneValueSlotWidth +
        2 * FieldSlider.widthGrowthIn(context, const [_laneValueWidest]),
  );
  _railColumnsMemo = (key: key, columns: columns);
  return columns;
}

({Object key, LayerRailColumnWidths columns})? _railColumnsMemo;

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
///
/// 🗣️tool-settings-panel-tidy (유저 2026-10-10, 안 A): the value is the
/// tool settings' NUMBER BOXES — one for each number, a pair side by
/// side — and the column is two boxes holding a four-digit coordinate
/// with room to spare: 「A로하란거, 지금 너무 공간 빡빡하거든? 공간
/// 많으니까 다 쓰란건아닌데 좀 더 여유롭게 크게하자」. Each box carries its
/// hands after it, its ± and its pencil ([FieldSlider.handsReach]), as a
/// settings box does (「상자에 한걸음 올리기 내리기버튼들도 동일하게」), and
/// the rail pays the column's growth: 「값 칸이 188에서 약 260px로 넓어지고,
/// 레일도 그만큼 넓어집니다」 (asked 2026-10-10, 「문제없는데」). ↩️80px, the
/// value written in blue and shrunk to fit it; then 188, two bare boxes.
const double layerLaneValueSlotWidth =
    2 * _laneValueBoxWidth + layerLaneValueBoxGap + layerLaneValueHandsWidth;

/// What a pair's HANDS take of the column — each box's ± and pencil
/// ([FieldSlider.handsReach]) — the room the rail pays along its length for
/// them (`timelineLayerControlsWidth`) — and the sheet's stood-up header
/// none of: there a lane's value row, turned, fits in the lane's own column
/// under its name (`XSheetTimelineGrid.naturalHeaderBlockExtent`).
const double layerLaneValueHandsWidth = 2 * FieldSlider.handsReach;

/// One of the column's boxes at 1×, before its hands.
const double _laneValueBoxWidth = 91;

/// Between a pair's two boxes: the tool settings' gap between two cells.
const double layerLaneValueBoxGap = 6;

/// What one of the column's boxes says at its widest: its name and a
/// four-digit coordinate with its sign.
const String _laneValueWidest = 'X -0000.00';

/// The per-layer onion-skin toggle column (UI-R17 #5, TVPaint style).
const double layerOnionSlotWidth = 22;
const double layerControlChipGap = 4;

/// The HEADER GRAPH's button (I-89 ③) — a Transform or effect header's,
/// the camera row's (the row being its own Transform group, ㉙) — at the
/// end of its row's name (유저 2026-10-10 시안: [twirl][name][graph][reset]
/// [fx]). ↩️A column of the trailing run, reserved on every row, until
/// 2026-10-12: a row's own buttons come out of its name (I-89 Q1).
const double layerGraphSlotWidth = 22;

/// A member lane's COLOUR CHIPS (I-89 ③): one 9×9 swatch per number its
/// line draws, while its group's graph draws it — reserved on every member
/// row of a rail that draws graphs, so a name never moves when its chips
/// come (⛔없다가 생기는 UI 금지).
const double layerLaneChipsSlotWidth = 22;

/// A member lane's PIN (I-89 ③, AE's graph editor set): the lane drawn in
/// every open graph. Right before the value, so it stands in one column
/// whichever lanes carry a chain before it.
const double layerLanePinSlotWidth = 22;

/// Whether [kind] carries a blend mode at all. Only the ACTION-section
/// kinds composite artwork — plus FOLDERS, which blend their whole group
/// (R27 #29); SE/CAM/instruction rows reserve the slot so the control
/// columns and the legend header stay aligned.
bool layerKindShowsBlendControl(LayerKind kind) =>
    kind.isDrawingCel || kind.groupsLayers;

/// Which rail row a shared control stands on — what its tooltip names.
///
/// 🚨rail-subject-tooltips (found building F-124, 2026-09-17): the controls
/// carried their row as an English WORD and assembled their tooltips from
/// it (`'Hide $subject'`, `'Bypass $subject FX'`), which no translation
/// reached and F-37's scan could not see — it skips every literal with a
/// `$` in it. The row is named here; the words are the table's, one whole
/// sentence per control and row.
enum RailSubject {
  /// A layer's row — the timeline, the x-sheet and the storyboard's layer
  /// rows.
  layer,

  /// The storyboard's TRACK row: its FX switch is the track's own. (↩️Its
  /// eye showed the cut pictures, and said so, until the eye left the row
  /// — I-73, 2026-10-08. The eye is a layer row's alone now and names no
  /// subject.)
  track,
}

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
///
/// [_blendFontSize] is the chip's word — the size it is set in and the size
/// its box grows by.
const double _blendFontSize = 9.5;

TextStyle _blendWordStyle(BuildContext context) =>
    DefaultTextStyle.of(context).style.copyWith(fontSize: _blendFontSize);

/// How much wider the blend column's widest word — any mode, in the heavier
/// weight a non-normal mode wears — runs here than at 1× (the column's share
/// of text-scale-rail-columns, 유저 2026-09-25: 「칸도 글자 따라 넓어진다」).
/// 🔬「Normal」 wanted 56.6 in its 52 at 1.5× and 75.0 at 2×.
double layerBlendColumnGrowthIn(BuildContext context) => TextMeasure(
  context,
  _blendWordStyle(context).copyWith(fontWeight: FontWeight.w700),
).widthGrowthOf([
  for (final mode in LayerBlendMode.values) mode.labelFor(AppText.language),
]);

class LayerBlendModeChip extends StatelessWidget {
  const LayerBlendModeChip({
    super.key,
    required this.name,
    required this.optionKeyPrefix,
    required this.blendMode,
    required this.onBlendModeSelected,
    this.isGroup = false,
    this.axis = Axis.horizontal,
  });

  /// The RAIL's direction. Vertical is the x-sheet's stood-up column: the
  /// slot spends its extent as HEIGHT and the mode name reads down the
  /// button.
  /// This was the one control in the shared skeleton that hardcoded its
  /// axis, so on the sheet it drew a 58-wide chip inside a 28px column.
  final Axis axis;

  /// What a finder calls the chip ('timeline-layer-blend-a') — a [Named],
  /// as a [RailGlyphButton.name] is and for its reason.
  final String name;

  /// Prefix for the flyout option keys
  /// ('timeline-layer-blend-option-' + mode name).
  final String optionKeyPrefix;

  final LayerBlendMode blendMode;
  final ValueChanged<LayerBlendMode> onBlendModeSelected;

  /// GROUP rows get [LayerBlendMode.passThrough] in the list; a drawing
  /// layer has no members to pass through, so it never sees the option.
  /// The tooltip names the row by it too: the group row is the folder —
  /// the caller already derived its old `subject` word from this flag.
  final bool isGroup;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final nonNormal = blendMode != LayerBlendMode.normal;
    final vertical = axis == Axis.vertical;
    // 🚨F-170 (유저 2026-09-20): 「앱 초기 실행시, 레이어의 블렌드 모드가
    // 영어가 되있음. Normal로. 그 상태에서 다른 레이어로 이동하거나 프레임
    // 생성하면 표준이라고 한글로 바뀜」. The saved language lands after the
    // first frame; every other word re-reads it when the app rebuilds for
    // it, but this one was handed down as a VALUE by a host that does not
    // rebuild, with English as the default. Asked here, at build, like
    // every other vocabulary ([AppText.language]).
    final language = AppText.language;
    // The chip's word grows with the OS text size, and the box around it
    // grows by as much (text-scale-rail-rows: the bars' law — a box drawn
    // around one line at 1× grows as that line grows; 0 at 1×). Measured:
    // 「Normal」 wanted 20 in its 16 at 1.5×.
    final growth = TextMeasure(
      context,
      _blendWordStyle(context),
    ).lineGrowthOf(TextMeasure.everyScript);
    // Along the rail it is as long as its slot lets it be (the column's 1×
    // extent and its words' growth, [layerBlendColumnGrowthIn], less the
    // gap the slot keeps) — the rail asks that once, not every chip in it.
    return acrossBox(
      axis,
      20 + growth,
      // Centered in the slot so the button lines up under the legend's
      // BLND column header (R28 #2).
      // The panels' chip, pressed as the rail presses (I-57 ①): the rail's
      // plate face instead of a tooltip, a [Material] and an [InkWell] of
      // its own — ~43 elements a chip, mounted anew whenever a frame panel
      // is shown again (frame-panels-build-in-one-frame, 10-24). The chip
      // is clear, so its hover shows: the face paints it, in the chip's
      // outline.
      child: Center(
        child: RailFlyoutTrigger(
          name: name,
          tooltip: isGroup
              ? AppText.strings.railFolderBlendMode
              : AppText.strings.railLayerBlendMode,
          hoverShape: PanelFlyoutChip.shape,
          entriesBuilder: () => LayerBlendMode.optionsFor(
            isGroup: isGroup,
          ).asFlyoutChoices(
            current: blendMode,
            keyPrefix: optionKeyPrefix,
            labelOf: (mode) => mode.labelFor(language),
            onPicked: onBlendModeSelected,
          ),
          child: PanelFlyoutChip(
            axis: axis,
            label: blendMode.labelFor(language),
            expand: true,
            fontSize: _blendFontSize,
            fontWeight: nonNormal ? FontWeight.w700 : FontWeight.w400,
            labelColor: nonNormal
                ? AppColors.accent
                : colorScheme.onSurfaceVariant,
            padding: vertical
                ? const EdgeInsets.symmetric(horizontal: 2, vertical: 3)
                : const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          ),
        ),
      ),
    );
  }
}

/// ⚠️[layerCarriesTimesheetToggle] and [layerKindEligibleForTimesheetToggle]
/// moved to `models/layer.dart` (2026-09-10): the printed sheet asks the
/// same question, and `models` cannot import `ui`.
///
/// Almost every layer kind shows the opacity slider (unified layer controls
/// — "레이어는 싹 다 공통화"): compositing cels use it directly, the CAMERA
/// row's is its own opacity — the camera view's dim (F-363) — and
/// instruction rows carry the same control for entrance parity.
///
/// ⛔The TRANSITION row does not. It is the one row that carries no picture
/// of its own — it says WHEN two cuts cross-dissolve — so there is nothing
/// for a slider to fade, and [LayerKind.hasPictureOpacity] has answered false
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

/// Whether a row WEARS its own fx switch: its kind shows one
/// ([layerKindShowsFxToggle]) and it authors its own composite. An attach
/// row and its 공정 organizer folder wear their BASE's
/// (`attachRowWearsBaseComposite`, R9), whose switch governs what they
/// show.
///
/// 🚨ONE ANSWER for the row's switch, the column sweep and a press spread
/// across the row selection — a row the one passes by, all three pass by.
/// ↩️The sweep and the spread asked the kind alone, and flipped an attach
/// row's own switch: a flag nothing reads, on a row with no switch to show
/// it.
bool layerRowWearsFxSwitch(
  LayerKind kind, {
  required bool wearsBaseComposite,
}) => layerKindShowsFxToggle(kind) && !wearsBaseComposite;

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

/// A row's name as the row's EYE leaves it: [style] itself while the row is
/// [shown], and on a row that is not, its ink at the rail's one 「off」
/// ([AppColors.offAlpha]) — the alpha the eye and the colour label beside it
/// already wear, so a hidden row reads as off in one language.
///
/// 🗣️I-62 (유저 2026-10-03): 「레이어 비지블off시 색라벨 비활성화색?으로
/// 하는데, 추가로 레이어 이름도 비활성화색? 반투명? 어둡게」.
///
/// The colour stays the caller's ([layerRowNameStyle]: what a name is
/// coloured by is what the row IS); this only says how that colour reads on
/// a row that is off.
TextStyle layerRowNameStyleFor(TextStyle style, {required bool shown}) {
  final ink = style.color;
  return shown || ink == null
      ? style
      : style.copyWith(color: ink.withValues(alpha: AppColors.offAlpha));
}

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
}) => Text(
  'fx',
  // The switch's ICON, drawn in type — and icons do not follow the OS
  // text size (the viewport pill's `1:1` is the same case). Scaled as
  // text it folded onto two lines in its slot at 1.5×
  // (text-scale-rail-rows); the eye and the bucket beside it keep theirs.
  textScaler: TextScaler.noScaling,
  style: fxGlyphStyle(
    context: context,
    active: active,
    fontSize: fontSize,
    mixed: mixed,
  ),
);

/// The `fx` glyph's type — what [fxGlyph] sets it in, and what the rail's
/// fx switch draws it in ([RailTextGlyph]); one style for both.
TextStyle fxGlyphStyle({
  required BuildContext context,
  required bool active,
  double fontSize = 13,
  bool mixed = false,
}) => TextStyle(
  fontSize: fontSize,
  fontStyle: FontStyle.italic,
  fontWeight: FontWeight.w700,
  // MIXED (R8): the row's master says "some of my groups are off" — the
  // accent held back to half, so it reads as neither fully on nor off.
  color: mixed
      ? AppColors.accent.withValues(alpha: 0.5)
      : active
      ? AppColors.accent
      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
  // …plus a mark the colour-blind eye can still read.
  decoration: mixed ? TextDecoration.underline : TextDecoration.none,
  decorationColor: AppColors.accent.withValues(alpha: 0.5),
);

/// The ONE eye: whether this row shows.
///
/// It was written inline in three rails (timeline, x-sheet, storyboard)
/// and had already drifted — the glyph was 18px in one and 16px in the
/// other two. Same lesson as the fx switch: a control that exists three
/// times is a control nobody can restyle.
class LayerVisibilityToggleButton extends StatelessWidget {
  const LayerVisibilityToggleButton({
    super.key,
    required this.name,
    required this.isVisible,
    required this.onToggle,
    this.hiddenAbove = false,
    this.tooltip,
    this.size = layerVisibilitySlotWidth,
    this.iconSize = 18,
  });

  /// Whether a folder above the row has hidden it whatever its own switch
  /// says (`RailEye.hiddenAbove`) — the eye keeps its glyph and wears the
  /// off colour (F-185).
  final bool hiddenAbove;

  /// The whole tooltip, when the caller has one of its own — the guides
  /// panel says 「가이드 표시」 rather than 'Show guide'. Null keeps the
  /// layer's Show/Hide pair, which is what every rail wants.
  final String? tooltip;

  /// What a finder calls the eye ('timeline-layer-visibility-a') — its
  /// [RailGlyphButton.name].
  final String name;

  final bool isVisible;
  final VoidCallback onToggle;
  final double size;

  /// The x-sheet's column header runs a hair smaller than the rails.
  final double iconSize;

  String _showHide(AppStrings strings) =>
      isVisible ? strings.railHideLayer : strings.railShowLayer;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: 26,
      child: RailGlyphButton(
        name: name,
        tooltip: tooltip ?? _showHide(AppText.strings),
        // The rail's slot, promised by the column skeleton — see
        // [AppIconButtonBox].
        size: AppIconButtonBox(width: size, height: 26, iconSize: iconSize),
        glyph: RailIconGlyph(
          isVisible ? Icons.visibility : Icons.visibility_off,
          // 🚨F-58 (유저): 「비지블off일경우 색라벨이 불투명도가 낮아지는데.
          // 이거 멋대로 추가한건데 맘에드니 채용. 근데 내가말한건 **비지블off시
          // 비지블버튼 자체를 비활성화색(어둡게)** 하란거였음. 그러니 작업하고,
          // 추가적으로 **비지블버튼은 다른곳에서도 쓰니까 공용화/통일화**시켜서
          // 결과적으로 다른곳도 비활성화시 비활성화색 되도록」.
          //
          // ★HERE, so 「결과적으로 다른곳도」 is automatic rather than five
          // edits. ⚠️[AppColors.offAlpha] is the app's ONE off language —
          // the alpha the onion and fx icons already wear — so a hidden row
          // reads as off in one language rather than in three.
          //
          // F-185: a row a folder above has hidden keeps its own glyph and
          // wears that same off colour — 「on인채로 두되, 색만 비활성화색으로」.
          color: isVisible && !hiddenAbove
              ? null
              : IconTheme.of(
                  context,
                ).color?.withValues(alpha: AppColors.offAlpha),
        ),
        onPressed: onToggle,
      ),
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
    required this.name,
    required this.state,
    required this.onToggle,
    this.subject = RailSubject.layer,
    this.size = layerFxSlotWidth,
  });

  /// What a finder calls the switch — its [RailGlyphButton.name]; callers
  /// spell their own identity in ('timeline-layer-fx-a',
  /// 'storyboard-cut-fx-3').
  final String name;

  /// R8: the row's FX as ONE value, so "on/off" and "mixed" cannot drift
  /// apart on their way here. A layer row is a MASTER over its per-group
  /// switches and can be [LayerFxState.mixed]; the cut-level switch has no
  /// groups under it and only ever passes on/off.
  final LayerFxState state;

  final VoidCallback onToggle;

  /// The row this switch stands on — what its tooltip names.
  final RailSubject subject;

  final double size;

  /// ⚠️A track's switch is never [LayerFxState.mixed] — its master is
  /// stored state, not a reading of switches under it — so that arm words
  /// what a press does there: bypass.
  String _tooltipFor(AppStrings strings) => switch ((subject, state)) {
    (RailSubject.layer, LayerFxState.mixed) => strings.railBypassMixedLayerFx,
    (RailSubject.layer, LayerFxState.on) => strings.railBypassLayerFx,
    (RailSubject.layer, LayerFxState.off) => strings.railApplyLayerFx,
    (RailSubject.track, LayerFxState.off) => strings.railApplyTrackFx,
    (RailSubject.track, _) => strings.railBypassTrackFx,
  };

  @override
  Widget build(BuildContext context) {
    final mixed = state == LayerFxState.mixed;
    return SizedBox(
      width: size,
      height: 26,
      child: RailGlyphButton(
        name: name,
        tooltip: _tooltipFor(AppText.strings),
        // ⚠️The word sizes itself, so the box's iconSize reaches nothing
        // here — it is passed honest rather than zero.
        size: AppIconButtonBox(width: size, height: 26, iconSize: 16),
        glyph: RailTextGlyph(
          'fx',
          style: fxGlyphStyle(
            context: context,
            active: state != LayerFxState.off,
            mixed: mixed,
          ),
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
String layerKindDisplayName(LayerKind kind) =>
    kind.labelFor(AppText.language);

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
Color layerMarkColor(LayerMark mark) =>
    resolveLayerMarkColor(mark, noneColor: timelineDrawingHeldColor);

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
      child: RailGlyphButton(
        name: '$keyPrefix-layer-timesheet-$layerId',
        tooltip: onTimesheet
            ? AppText.strings.railRemoveFromTimesheet
            : AppText.strings.railAddToTimesheet,
        size: const AppIconButtonBox(
          width: layerTimesheetSlotWidth,
          height: layerTimesheetSlotWidth,
          iconSize: 16,
        ),
        glyph: RailIconGlyph(
          onTimesheet ? Icons.table_chart : Icons.table_chart_outlined,
          color: onTimesheet
              ? AppColors.accent
              : colorScheme.onSurface.withValues(alpha: 0.35),
        ),
        onPressed: () => onToggle(layerIdNow(context, layerId)),
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
              child: Named(
                '$keyPrefix-layer-attach-arrow-$idValue',
                child: layerAttachmentArrowIcon(context),
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
Widget layerAttachmentArrowIcon(BuildContext context) => Icon(
  Icons.subdirectory_arrow_right,
  size: 16,
  color: Theme.of(context).colorScheme.onSurfaceVariant,
);

/// A pick on a row's label chip, said as the EDIT it makes to a mark: a
/// label pick puts the picked label, a take pick keeps the label and sets
/// the take.
///
/// 🚨Said as an edit, not as the mark it makes, so a press spread over the
/// row selection makes the same edit on every row
/// (row-buttons-act-on-the-selection) — a take picked on one selected row
/// keeps every other row's own label. As a finished mark it would have
/// copied the pressed row's label onto them.
typedef LayerMarkEdit = LayerMark Function(LayerMark current);

class LayerMarkChip extends StatelessWidget {
  const LayerMarkChip({
    super.key,
    required this.keyPrefix,
    required this.layerId,
    required this.mark,
    required this.onMarkSelected,
    this.axis = Axis.horizontal,
    this.isVisible = true,
  });

  /// The chip for [layer]'s row: its id, its mark and its `isVisible`
  /// handed down from the one place that already answers 「is this row
  /// shown」 (see [isVisible]). The three rail surfaces used to pull the
  /// three fields off the layer each in their own argument list (the
  /// round-8 audit, 2026-09-06).
  ///
  /// [isVisible] is the row's EYE where the row reads it live (`RailEyes` —
  /// a memoized timeline row keeps the [layer] it was built with); a surface
  /// that rebuilds its rows whole leaves it to [layer].
  LayerMarkChip.forLayer(
    Layer layer, {
    Key? key,
    required String keyPrefix,
    required void Function(LayerId layerId, LayerMarkEdit edit) onMarkSelected,
    Axis axis = Axis.horizontal,
    bool? isVisible,
  }) : this(
         key: key,
         keyPrefix: keyPrefix,
         layerId: layer.id,
         mark: layer.mark,
         onMarkSelected: onMarkSelected,
         axis: axis,
         isVisible: isVisible ?? layer.isVisible,
       );

  final String keyPrefix;
  final LayerId layerId;
  final LayerMark mark;
  final void Function(LayerId layerId, LayerMarkEdit edit) onMarkSelected;

  /// 🚨★★★HIDDEN LAYER, DIMMED MARK (유저 2026-08-31, F-56: 「레이어,
  /// 비지블 off면 추가로 색도 비활성화색. **어니언스킨 off상태나 그런 다른
  /// 버튼 off상태랑 동급으로** 색 바꿈」).
  ///
  /// ⚠️Named `isVisible` and PASSED, not re-derived: the rail already answers
  /// 「is this row shown」 once per row and hands it down, which is the same
  /// shape the eye button beside it uses. ⛔A `dimmed:` flag computed at each
  /// call site would be a second place answering that question — the source
  /// scan in `hidden_folder_is_hidden_test` named all four the moment I did.
  ///
  /// ⚠️Not a colour of its own either: it wears the SAME alpha the rail's other off
  /// states wear, so 「off」 reads as one thing across the row instead of as
  /// three separate designs.
  final bool isVisible;

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
      alongBox(axis, layerMarkSlotWidth, child: _markTrigger(context)),
      alongBox(axis, layerTakeSlotWidth, child: _takeTrigger(context)),
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
    return RailFlyoutTrigger(
      name: '$keyPrefix-layer-take-$layerId',
      tooltip: AppText.strings.tlLayerTake,
      semanticLabel: AppText.strings.tlLayerTake,
      entriesBuilder: () => layerTakeFlyoutEntries(
        selectedTake: mark.take,
        onSelected: (take) => onMarkSelected(
          layerIdNow(context, layerId),
          (current) => current.withTake(take!),
        ),
      ),
      child: LayerTakeText(mark: mark, axis: axis),
    );
  }

  Widget _markTrigger(BuildContext context) {
    // R6 #4, the last of the five raw `PopupMenuButton`s: this one held out
    // because its rows name COLOURS, and the shared list had no way to show
    // one — see [PanelFlyoutItem.swatch]. Its own row height was 36, a sixth
    // number in a menu system that was supposed to have one.
    return RailFlyoutTrigger(
      name: '$keyPrefix-layer-mark-$layerId',
      tooltip: AppText.strings.tlLayerMark,
      semanticLabel: AppText.strings.tlLayerMark,
      // No padding: the mark sits in a fixed `layerMarkSlotWidth` rail
      // column, so padding would not grow a hit area — it would push every
      // slot after it out of the rail.
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
      entriesBuilder: () => layerMarkFlyoutEntries(
        onSelected: (option) => onMarkSelected(
          layerIdNow(context, layerId),
          (_) => option,
        ),
      ),
      child: LayerMarkPlate(mark: mark, isVisible: isVisible, axis: axis),
    );
  }
}

/// The colour-label flyout's rows — 「라벨 없음」, then every stage, each
/// opening its 上がり and corrections as a second level (유저 설계 I-4:
/// 「호버하면 추가로 앵커팝오버로 수정라벨이 뜨도록. 즉 축으로서 2가지가
/// 존재하도록」).
///
/// 🚨ONE LIST, TWO TRIGGERS. The rail's mark chip and the export window's
/// label picker both open THIS (유저 2026-09-09: 「타임라인에서 색라벨 고르는
/// 피커창 … 그거 그대로 공용화해서 재사용」); each hands in only what to do
/// with the pick.
List<PanelFlyoutEntry> layerMarkFlyoutEntries({
  required void Function(LayerMark mark) onSelected,
}) => [
  PanelFlyoutItem(
    keyValue: 'layer-mark-option-none',
    label: AppText.strings.tlLayerMarkNone,
    swatch: layerMarkColor(LayerMark.none),
    onSelected: () => onSelected(LayerMark.none),
  ),
  for (final process in LayerProcess.values)
    PanelFlyoutItem(
      // 🚨THE KEY SAYS WHAT THE ROW DOES. A stage that opens a child is
      // `…-stage-…`; a row that PICKS is `…-option-…`. They used to share a
      // key and the submenu's 소재 collided with the parent it hung off — two
      // widgets, one key, and every finder that touched either one broke.
      keyValue: revisesFor(process).isEmpty
          ? 'layer-mark-option-${process.jsonValue}'
          : 'layer-mark-stage-${process.jsonValue}',
      label: layerProcessLabel(process),
      swatch: layerMarkColor(LayerMark(process: process)),
      // 용지 carries no corrections, so it is a plain choice — no chevron,
      // no second level, and picking it labels the row.
      onSelected: revisesFor(process).isEmpty
          ? () => onSelected(LayerMark(process: process))
          : null,
      submenuBuilder: revisesFor(process).isEmpty
          ? null
          : () => [
              // 소재(上がり) first — 그 공정의 작업본이다. 이것이 「수정 없음」
              // 자리를 대신한다.
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
                  onSelected: () => onSelected(option),
                ),
            ],
    ),
];

/// The take flyout's rows — 1–9, and for the export window alone a leading
/// 「최신」 ([offerLatest]) that selects with `null`.
///
/// ⛔No 「없음」. 유저 2026-08-27: 「테이크도 … 라벨없음 삭제해. 테이크는
/// **기본값 T1**」 — a drawing is always some pass, so the first one is 1
/// rather than an absence. (색 라벨 keeps its 없음: 「색라벨은 라벨없음 그대로
/// 두자」.) 「최신」 is not an absence either: it is the export's rule 「the
/// newest take of each row」, the one item the export added to this list
/// (유저 2026-09-09: 「테이크 피커만 지금 최신이란 항목없으니 그거만 이번에만
/// 추가」).
List<PanelFlyoutEntry> layerTakeFlyoutEntries({
  required int? selectedTake,
  required void Function(int? take) onSelected,
  bool offerLatest = false,
}) => <int?>[
  if (offerLatest) null,
  ...LayerMark.takeChoices,
].asFlyoutValueChoices(
  current: selectedTake,
  choiceOf: (take) => PanelFlyoutChoice(
    key: 'layer-take-option-${take ?? 'latest'}',
    label: take == null
        ? AppText.strings.exTakeLatest
        : AppText.strings.tlLayerTakeNumber(take),
  ),
  onPicked: onSelected,
);

/// The colour plate alone, read-only: [LayerMarkChip]'s left half without
/// its trigger. The export window's layer list draws the rail's own plate
/// here (유저 2026-09-09: 「타임라인 아이콘이나 뭐나 싹 다 그대로 재사용」).
///
/// A6 (2026-08-17): the circle became the label PLATE — the full slot,
/// edge to edge (「패딩 절대 금지」), square corners, with the colour NAME
/// standing upright inside it (「가로쓰기 세로표시」). The click logic above
/// is untouched; only this face changed.
///
/// ★ONE BOX ([RenderLabelPlate]): the plate fills, splits and writes itself,
/// taking the words to write and the fill to write them on rather than
/// knowing what a mark is. ↩️It was this widget building a plate widget
/// building a fill around a clip around a row of stretched columns — four
/// to twelve elements a plate, on every rail row, paid on every panel
/// reopen (card frame-panels-build-in-one-frame, 2026-10-25).
class LayerMarkPlate extends LeafRenderObjectWidget {
  const LayerMarkPlate({
    super.key,
    required this.mark,
    this.isVisible = true,
    this.axis = Axis.horizontal,
  });

  final LayerMark mark;

  /// A hidden row's plate wears the rail's 「off」 alpha (F-56).
  final bool isVisible;
  final Axis axis;

  /// The same type the section band's tag wears, one column over.
  static const double _fontSize = 9;

  /// 🔒**w400 으로 확정**(유저 2026-08-28: 「일단 정했어. 얇은거. 400으로
  /// 가고싶어」). 고르는 동안은 설정이었다.
  ///
  /// 🧪실기 실측(유저): **100~500 은 얇고, 600~800 은 굵고, 900 은 엄청
  /// 굵다.** ⚠️번들 폰트에 Regular 와 Bold 뿐이니 두 단계일 것이라던 내
  /// 예측은 **틀렸다** — 900 에서 Skia 가 합성 볼드를 얹는다. 파일 목록만
  /// 보고 렌더러의 답을 예측한 대가다.
  ///
  /// ⛔The glyphs are drawn STRAIGHT, with whatever anti-aliasing Skia
  /// gives them. A `ColorFiltered` alpha step used to sit over them — the
  /// 「쌩2치화」 round — and why it went is written on
  /// `AppAccentSettings`, beside the weight that used to be a setting too.
  static const FontWeight _fontWeight = FontWeight.w400;

  /// ⑳ every plate is FILLED, `none` included — it is the paper colour
  /// rather than a hole in the rail.
  ///
  /// ⚠️0.45 is the rail's own 「off」 alpha — the same one the onion and
  /// fx icons wear — so a hidden layer reads as off in one language
  /// rather than in three.
  Color get _fill => !isVisible
      ? layerMarkColor(mark).withValues(alpha: AppColors.offAlpha)
      : layerMarkColor(mark);

  /// The words the plate writes, in its reading order, inked by the frame
  /// blocks' own luminance law ([timelineTextOnColor], #1109) — 유저:
  /// 「프레임이름/코마숫자/색라벨은 다 같은 색상의 바탕 위에 올라가는
  /// 텍스트니까 **셋 다 같은 로직**」. An empty one is not written: `none`
  /// writes nothing (the paper colour has no name to announce; the plate
  /// itself keeps the tap target discoverable), and a stage with no
  /// correction writes one word over the whole plate.
  ///
  /// 🚨★★★THE STAGE COMES FIRST — left on the rail, top on the sheet.
  ///
  /// 유저 2026-08-27 corrected an earlier call of theirs: 「LO작감시 왼쪽에
  /// 작감 오른쪽에 LO 오는데, 그게아니라 **평범하게 왼쪽에 LO 오른쪽에
  /// 작감** 오도록. 이유는 지금 **레이어영역 자체가 왼쪽부터 오른쪽으로
  /// 읽는걸 기준으로** 설계하고있어」.
  ///
  /// ⚠️The first reading (stage on the right, from Japanese vertical
  /// writing) was right about the writing and wrong about the SURFACE:
  /// the rail is a left-to-right column of names, and one label reading
  /// the other way would be the exception.
  ///
  /// ⛔Not stacked as two rows on the rail: 「띠가 지금 가로로 얇은거를
  /// 살리고싶어서」 — two columns keep the plate as short as one. The sheet
  /// stacks instead, because there the plate is wide and short.
  ///
  /// 🚨★★★ONE LAW, BOTH RAILS. 유저 2026-08-27: 「x시트 **로직적으로 통일**
  /// 하는거 절대잊지말고」 — so the split, the fill and the order are decided
  /// HERE once and the axis is the only thing that differs. The x-sheet used
  /// to run its own `BoxFit.scaleDown` branch, which is exactly how it kept
  /// missing whatever the rail had just learned.
  List<PlateWords> _wordsIn(BuildContext context) {
    final style = TextStyle(
      fontSize: _fontSize,
      fontWeight: _fontWeight,
      height: SectionBandZone.lineHeight,
      color: timelineTextOnColor(_fill),
    );
    final (:process, :revise) = layerMarkChipText(mark);
    return [
      for (final text in [process, revise])
        if (text.isNotEmpty)
          plateWordsIn(context, text: text, axis: axis, style: style),
    ];
  }

  @override
  RenderLabelPlate createRenderObject(BuildContext context) =>
      RenderLabelPlate(
        fill: _fill,
        words: _wordsIn(context),
        axis: axis,
        textDirection: Directionality.maybeOf(context),
      );

  @override
  void updateRenderObject(BuildContext context, RenderLabelPlate renderObject) {
    renderObject
      ..fill = _fill
      ..words = _wordsIn(context)
      ..axis = axis
      ..textDirection = Directionality.maybeOf(context);
  }
}

/// The rail's two label plates side by side at their slot widths, read-only
/// — the mark plate and, unless [showTake] is off, the take text. What a
/// surface that lists layers but does not edit their labels shows.
class LayerMarkPlates extends StatelessWidget {
  const LayerMarkPlates({
    super.key,
    required this.mark,
    this.isVisible = true,
    this.showTake = true,
  });

  final LayerMark mark;
  final bool isVisible;
  final bool showTake;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        width: layerMarkSlotWidth,
        child: LayerMarkPlate(mark: mark, isVisible: isVisible),
      ),
      if (showTake)
        SizedBox(
          width: layerTakeSlotWidth,
          child: LayerTakeText(mark: mark, axis: Axis.horizontal),
        ),
    ],
  );
}

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
PlateWords plateWordsIn(
  BuildContext context, {
  required String text,
  required Axis axis,
  required TextStyle style,
}) => switch (axis) {
  Axis.horizontal => StoodPlateWords(
    VerticalWritingText(
      text: text,
      latinForm: VerticalLatinForm.upright,
      lineHeight: SectionBandZone.lineHeight,
      // 「길면 글자 축소 허용」 — a long abbreviation packs and shrinks
      // rather than ellipsising. 시아게 is three glyphs where the rest are
      // two, and this is what lets it sit in the same plate.
      overflow: VerticalTextOverflow.pack,
      minFontSize: 4,
      style: style,
    ),
    context,
  ),
  // 🚨THE SAME LAW ACROSS THE PLATE (text-scale-sheet-plates, 유저
  // 2026-09-25: 「판은 그대로, 글자를 판에 맞춰 줄인다(레일과 같은 법)」):
  // the plate keeps its 14 and the words shrink into it — evenly, and only
  // past it — as the rail's `pack` above shrinks them down the column. At
  // 2× the take's T1 stood 18 tall on the sheet's plate and was cut top
  // and bottom.
  Axis.vertical => LyingPlateWords(
    text,
    // 🚨★★★THE GLYPH CARRIES NO LEADING OF ITS OWN — on the sheet as on
    // the rail. 유저 2026-09-17 (F-160): 「x시트의 색 라벨, LO만 글자가
    // 아래로 치우쳐져있고 용지는 살짝 위로 … 타임라인이랑 다른거있나?
    // 다른거있으면 법 통일하고 제대로 중앙에오도록」.
    //
    // There was one difference, and it was this line. The rail's painter
    // lays every glyph at `height: 1.0` and lets the CELL be the leading
    // ([paintVerticalText]); the sheet kept the caller's 1.15. A line box
    // that tall seats its ink by each FONT's ascent and descent, and a
    // Korean label is two fonts — BIZ UDPGothic draws `LO`, Nanum Gothic
    // draws 용지 — so the two sat at different heights in one plate.
    //
    // 🧪Measured with the app's faces loaded (the test binding's own box
    // font hides this completely): on the sheet `LO` sat 1.26px below
    // the Hangul labels on a 14px plate; on the rail, 0.25px. At 1.0 the
    // sheet reads 0.25px as well. The take text lays its glyphs through
    // here too, so it is the same law for both plates.
    textLineTypeIn(context, style.copyWith(height: 1.0)),
  ),
};

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
/// ⛔[ControlPressClaim]'s claim is the WEAK one on purpose: a button owns
/// its TAP, not drags. What makes the RAIL different is that a drag from a
/// rail button became a verb of its own — until then the rail's Krita-style
/// eye swipe could never run at all, because the row's eager pan won every
/// gesture that started on the eye.
///
/// 🚨THE SENTENCE THAT USED TO CARRY THIS said the weak claim was owed to
/// the storyboard, whose row-order drag "deliberately starts ON the
/// visibility button" — and concluded 「That is still true of the
/// storyboard」. It is not, and it never was: see the measurement kept at
/// [claimTapForControl]. The storyboard's row-order drag starts 126px from
/// the eye, a drag begun on the eye re-orders nothing, and the test the
/// sentence cited never mentioned visibility.
///
/// ⚠️So the storyboard's lack of swipe columns is not a constraint this
/// widget is honouring — it is an unfinished job. 유저 2026-08-29: 「타임
/// 라인이랑 왜 통일안한거지?」
///
/// ⇒ The strong claim, applied by the RAIL to the columns it can swipe —
/// never by the button widget itself, which rails other than this one also
/// mount.
///
/// 🚨★★★AND IT SAYS WHICH COLUMN THE PRESS IS IN ([column]) — what was
/// pressed decides, so the button under the press is the one that knows.
/// ↩️The rail worked it out again from where the press stood: each column
/// a band of the row, written beside the layout that lays the button —
/// the slot skeleton's sums, a member lane's inset, a name's end past the
/// twirl. Two answers to 「where is this button」 that had to agree, and
/// did not: the bands reached 4px past their slots into the next button
/// (F-475), and a column whose button stands where no sum reaches — a
/// lane header's twirl, a fold at a name's end — had no band at all.
///
/// A column worn on a rail whose list does not sweep it holds its press
/// all the same — the press is the button's — and sweeps nothing.
///
/// The LEADING columns wear it too now — the sheet toggle the report named
/// and the lane twirl beside it. They are worn HERE, at the rail's call
/// site, rather than inside the buttons: the x-sheet's column header uses
/// the same timesheet widget and has no swipe to claim for.
///
/// ★It IS the [DragVerbClaim] rather than a widget that builds one: five
/// columns of every rail row wear it, and a wrapper that only forwards its
/// child is one element per column paid on every panel reopen (card
/// frame-panels-build-in-one-frame, 2026-10-25).
class RailSwipeColumnPointer extends DragVerbClaim {
  // ⛔The WEAK half is NOT written again here. It is [ControlPressClaim],
  // the one widget every button in the app wears — the control inside
  // wears its own; what a swipe column adds is the STRONG claim, and that
  // is all it should have to say. ↩️A claim of the column's own stood here
  // for the bare `InkWell`s that had none and fired through it; the last
  // two (the storyboard rows' lane twirls) are the rail's twirl since
  // I-57 ①, and a claim with nothing under it to speak for is weight.
  //
  // ⛔Nor WHEN its controls act. 「타임라인같은 특정버튼」 (유저 확정
  // 2026-08-30) was first said here — 「a drag from here paints the
  // column」 — and the same day it became the whole row's: 「레이어 쪽
  // 버튼은 탭다운, 헤더쪽은 손떼면」. Every row a column stands in says it
  // for everything on it ([TimelineLayerControlsRow.build], the lane row,
  // the storyboard's label shell), so a scope here said it a second time
  // and cost an element per column on every panel reopen; it went
  // 2026-10-25 (card frame-panels-build-in-one-frame).
  const RailSwipeColumnPointer({
    super.key,
    required this.column,
    required super.child,
  });

  /// The column this button stands in — the one a drag from it sweeps.
  final RailSwipeColumn column;

  @override
  RenderRailSwipeColumnPointer createRenderObject(BuildContext context) =>
      RenderRailSwipeColumnPointer(column, behavior: behavior);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderRailSwipeColumnPointer renderObject,
  ) {
    super.updateRenderObject(context, renderObject);
    renderObject.column = column;
  }
}

/// The toggle columns a rail sweeps — which one a button stands in is the
/// button's to say ([RailSwipeColumnPointer.column]); what a row reads in
/// each and how a sweep flips it is the rail's list (`railSwipeColumns`).
enum RailSwipeColumn {
  visibility,
  onion,
  fx,
  clip,
  timesheet,

  /// A layer row's twirl of its property lanes.
  laneToggle,

  /// A header graph's button — a lane group header's, the camera row's.
  graph,
  lanePin,

  /// A folder's fold, or the attach group's riding a base — one twirl at
  /// the end of a row's name (`timelineGroupFoldFor`).
  groupFold,

  /// A lane group header's twirl — Transform, an effect.
  laneGroupToggle,
}

/// [RailSwipeColumnPointer]'s box: the strong claim, and the column it
/// tells a press is in ([railSwipeColumnPressedBy]).
class RenderRailSwipeColumnPointer extends RenderDragVerbClaim {
  RenderRailSwipeColumnPointer(this.column, {required super.behavior});

  RailSwipeColumn column;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    super.handleEvent(event, entry);
    if (event is PointerDownEvent) {
      _columnPressed = (down: event.original ?? event, column: column);
    }
  }
}

/// The last press a column's button took, as the press itself: the event
/// before any box's transform, which every box it is handed to shares.
({PointerEvent down, RailSwipeColumn column})? _columnPressed;

/// The column whose button took [down], or null when none did.
///
/// Asked by a rail of the same press on its own way up: hit-test dispatch
/// runs deepest-first, so the button has spoken by then. ⛔By the press
/// itself, not its pointer id: the record outlives its press, and an id is
/// only as unique as whoever numbered the events — a test's come round
/// again — so a column read off an earlier press would sweep from a button
/// this press never touched.
RailSwipeColumn? railSwipeColumnPressedBy(PointerDownEvent down) =>
    switch (_columnPressed) {
      (down: final pressed, :final column)
          when identical(pressed, down.original ?? down) =>
        column,
      _ => null,
    };

/// 테이크 라벨의 얼굴 — **바탕 없이 글자만**.
///
/// 🚨유저 2026-08-27: 「테이크라벨은 **배경 삭제**해. 그러고 글자만 심플하게
/// **레이어이름처럼 디자인 통일**해서 흰색계열」.
///
/// ⛔So it does NOT reuse [LayerMarkPlate]: a plate is a filled slot, and this
/// is writing on the rail. What it reuses instead is the thing it was told
/// to match — [layerRowNameStyle], the very style the layer's name is set
/// in, so the two stay one decision. A copied `TextStyle` here would be the
/// second place to edit the day that style changes.
///
/// ★ONE BOX ([RenderTakeText]): the take sets, places and says its word
/// itself. ↩️It was a clip around a centring box around the word's own box,
/// built by a widget of its own — four elements on every rail row, paid on
/// every panel reopen (card frame-panels-build-in-one-frame, 2026-10-25).
class LayerTakeText extends LeafRenderObjectWidget {
  const LayerTakeText({super.key, required this.mark, required this.axis});

  final LayerMark mark;
  final Axis axis;

  /// ⛔NOT stretched. 유저 2026-08-28: 「테이크 글자는 이전처럼 flex하지말고
  /// **그냥 평범하게** 하자」 — the colour plate fills its slot because the
  /// fill IS the label there; T1 is just a number and reads better at its
  /// own size, in the middle of its slot.
  ///
  /// ⚠️The writing direction still comes from [plateWordsIn]: standing the
  /// glyphs up on the rail and laying them across on the sheet is the
  /// shared decision, and only the FILL was ever this chip's own choice.
  PlateWords _wordIn(BuildContext context) => plateWordsIn(
    context,
    text: mark.takeText,
    axis: axis,
    style: layerRowNameStyle(context).copyWith(
      fontSize: 9,
      fontWeight: FontWeight.bold,
      height: SectionBandZone.lineHeight,
    ),
  );

  @override
  RenderTakeText createRenderObject(BuildContext context) => RenderTakeText(
    word: _wordIn(context),
    textDirection: Directionality.maybeOf(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderTakeText renderObject) {
    renderObject
      ..word = _wordIn(context)
      ..textDirection = Directionality.maybeOf(context);
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
String layerMarkLabel(LayerMark mark) => mark.labelFor(AppText.language);
