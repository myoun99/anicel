import '../widgets/app_tooltip.dart';
import 'package:flutter/material.dart';

import '../input/control_press_claim.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';
import '../theme/app_theme.dart';
import '../widgets/field_slider.dart';
import '../widgets/panel_flyout.dart';
import 'layer_label_controls.dart';
import 'layer_rail_columns.dart';
import 'memo_token.dart' show BySet, KeptPiece;
import 'timeline_grid_metrics.dart';
import 'timeline_legend_menus.dart';
import 'timeline_row_filter.dart';
import 'timeline_section_policy.dart';
import '../text/app_strings.dart';
import '../text/vertical_writing_text.dart';

/// The rail header cell, reborn as the LEGEND (R-toolbar round): the wide
/// '+ Layer' button is gone — instead each control column gets an icon
/// lined up exactly over its slot (Excel-header reading), and clicking a
/// legend icon opens the shared flyout with that column's bulk commands.
/// The corner cell above the section gutter opens the sections flyout.
///
/// R10 R6: stood up ([axis] vertical) this is the X-SHEET'S CORNER — the
/// box above the frame-number rail that used to read 'Frame' and label
/// nothing. Same list, same order, same slot extents, turned 90°, so the
/// sheet's column headers get named by the icons that name the timeline's.
class TimelineLayerControlsHeader extends KeptPiece {
  const TimelineLayerControlsHeader({
    super.key,
    required this.metrics,
    this.axis = Axis.horizontal,
    this.railExtent,
    required this.optionalColumns,
    this.legend,
    this.hiddenSections = const {},
    this.onToggleSection,
    this.onCollapseAllLanes,
    this.onExpandAllLanes,
    this.rowFilter = TimelineRowFilter.none,
    this.marksInUse = TimelineLegendMenus.noMarks,
    this.kinds = const {},
    this.visibilitySoloEnabled = false,
    this.anyLanesExpanded = false,
    this.allSeMuted = false,
    this.displayedLayerIds,
    this.displayedOpacity = 1.0,
    this.displayedOnionSkinOn = false,
    this.showRowSolos = true,
  }) : assert(
         axis == Axis.horizontal || railExtent != null,
         'a stood-up legend is told its extent',
       );

  final TimelineGridMetrics metrics;

  /// The rail's own direction (R10 R6): horizontal above the timeline's
  /// rail, vertical in the x-sheet's corner.
  final Axis axis;

  /// How far the legend runs along [axis]; null takes the rail's width,
  /// which is an answer only lying down. Stood up it is the x-sheet's
  /// corner, told the header block's extent
  /// ([XSheetTimelineGrid.naturalHeaderBlockExtent]) — the value the block
  /// and its window read. ↩️A stood-up legend used to sum one up for itself
  /// when it was told none, by a sum the block's had stopped matching (it
  /// never took the lane values' hands off); nothing ever stood it up
  /// without telling it.
  final double? railExtent;

  /// The optional columns the ROWS beside this legend carry — the host's
  /// answer, which the legend lays its headings out by and, stood up,
  /// sizes itself from. A legend that disagreed with its rows would stop
  /// naming their columns.
  ///
  /// ↩️It used to be inferred from [legend]'s bulk callbacks unless forced,
  /// which is why the x-sheet's corner had to force it: its rows carry
  /// onion and blend, and it has no flyouts to infer them from. Every host
  /// says it now, so the heading follows the column on every surface.
  final LayerRailOptionalColumns optionalColumns;

  /// Null renders a display-only legend (no flyouts) — passive hosts.
  final LayerLegendCallbacks? legend;

  final Set<TimelineSection> hiddenSections;
  final ValueChanged<TimelineSection>? onToggleSection;

  /// The active row filter (for the legend flyouts' check marks).
  final TimelineRowFilter rowFilter;

  /// Marks currently assigned across the active cut's layers — the
  /// "solo color X" list is built from these (empty color set skipped),
  /// read when it is ([TimelineLegendMenus.marksInUse] has why).
  final Set<LayerMark> Function() marksInUse;

  /// The kinds this panel's rows can be — the "solo kind" list (R4 #8,
  /// [TimelineLegendMenus.kinds] has F-408's why).
  final Set<LayerKind> kinds;

  /// The rows the rail currently DISPLAYS (filter-passing, non-camera) —
  /// the master opacity bar's target set (R4 #6). Null disables the bar.
  final Set<LayerId> Function()? displayedLayerIds;

  /// The master bar's resting value: the LAST value committed through the
  /// bar (UI-R6 #2) — not a live average of the rows.
  final double displayedOpacity;

  /// Whether every displayed drawing layer is currently ghosting (the
  /// onion legend's engaged state, UI-R17 #5).
  final bool displayedOnionSkinOn;

  /// Hosts without a row filter (the storyboard's track-global rail,
  /// UI-R5) pass false: the 'Solo …' flyout entries and the kind-solo
  /// flyout stand down while the bulk ops and the master bar keep working.
  final bool showRowSolos;

  /// Whether the visibility SOLO MODE is on (eye legend state color +
  /// flyout check).
  final bool visibilitySoloEnabled;

  /// Whether any layer's lanes are expanded — the lane-column header
  /// toggle folds/unfolds ALL layers based on this (R3 feedback #5).
  final bool anyLanesExpanded;

  /// Whether every SE row is muted — the mute legend cell is a direct
  /// all-SE toggle (R3 feedback #10), colored by this state.
  final bool allSeMuted;

  /// Grid-provided lane sweeps (the grid owns lane expansion knowledge).
  final VoidCallback? onCollapseAllLanes;
  final VoidCallback? onExpandAllLanes;

  /// What the header shows and what its flyouts read when they open — its
  /// ~15 tooltip and flyout cells are built again only when one of these
  /// moves, on every grid that stands one up.
  ///
  /// ↩️(UI-R7 #1) the timeline gated it on a token of its own and the
  /// storyboard and the x-sheet built it again on every build; the one
  /// keep is the header's now (I-57, 10-14). The words are the program
  /// language's, read at build.
  ///
  /// ⛔Three kinds of slot outlive their mutants (10-14), kept because
  /// every fact the header shows is here, as a row's are
  /// ([LayerControlsRowFacts]): the language — the theme is keyed on it, so
  /// a switch builds the header again anyway; the legend's shape — its
  /// verbs are its host's, the same for the panel's life; and each metric
  /// alone — a text scale moves the three together (the controls width is
  /// the columns' sum on the rail, the row height on the sheet).
  @override
  Object? get facts => (
    metrics.layerControlsWidth,
    metrics.layerRowHeight,
    metrics.railColumns,
    axis,
    railExtent,
    optionalColumns,
    legend?.shape,
    BySet(hiddenSections),
    onToggleSection != null,
    rowFilter,
    marksInUse,
    BySet(kinds),
    visibilitySoloEnabled,
    anyLanesExpanded,
    allSeMuted,
    displayedLayerIds != null,
    displayedOpacity,
    displayedOnionSkinOn,
    showRowSolos,
    onCollapseAllLanes != null,
    onExpandAllLanes != null,
    AppText.language,
  );

  /// The legend's menus — this header's flyouts and, published by the panel
  /// that built this header, what a key presses one of (I-40). ONE place
  /// makes them from this header's own fields, so the rows a key presses
  /// are the rows this header shows.
  TimelineLegendMenus get menus => TimelineLegendMenus(
    legend: legend,
    hiddenSections: hiddenSections,
    onToggleSection: onToggleSection,
    rowFilter: rowFilter,
    marksInUse: marksInUse,
    kinds: kinds,
    visibilitySoloEnabled: visibilitySoloEnabled,
    displayedLayerIds: displayedLayerIds,
    displayedOnionSkinOn: displayedOnionSkinOn,
    showRowSolos: showRowSolos,
  );

  // R9 #22: the cell no longer carries its own width — the rail's shared
  // column skeleton sizes it, so a legend icon cannot drift off the
  // column it labels (its kind cell used to be 18 against the rows' 22).
  Widget _cell({
    required String keyValue,
    required String tooltip,
    required Widget child,
    LegendFlyout? entriesBuilder,
  }) {
    final content = Center(child: child);
    // The key stays on the cell whether or not it can open a flyout —
    // it's the column's stable address (legend alignment tests).
    if (entriesBuilder == null) {
      return AppTooltip(
        key: ValueKey<String>(keyValue),
        message: tooltip,
        child: content,
      );
    }
    return Builder(
      builder: (anchorContext) => AppTooltip(
        message: tooltip,
        child: ControlPressClaim(
          onPressed: () =>
              showPanelFlyout(anchorContext, entries: entriesBuilder()),
          child: InkWell(
            key: ValueKey<String>(keyValue),
            onTap: silentPress(
              () => showPanelFlyout(anchorContext, entries: entriesBuilder()),
            ),
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionBand(
    TimelineLegendMenus menus,
    ColorScheme colorScheme,
  ) {
    return _cell(
      keyValue: 'legend-sections',
      tooltip: AppText.strings.tlSections,
      entriesBuilder: menus.sections,
      child: Icon(
        Icons.view_agenda_outlined,
        size: 13,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget? _buildLaneToggle(Color restColor) {
    // The lane column's header: fold/unfold EVERY layer's lanes in one tap
    // (R3 feedback #5). The toggle has ONE handler, named once.
    final onToggle = anyLanesExpanded ? onCollapseAllLanes : onExpandAllLanes;
    return onExpandAllLanes != null && onCollapseAllLanes != null
        ? AppTooltip(
            // ↩️Written in English here, in every language, until I-40's
            // round on the legend found it (10-09).
            message: anyLanesExpanded
                ? AppText.strings.tlCollapseAllLayers
                : AppText.strings.tlExpandAllLayers,
            child: ControlPressClaim(
              onPressed: onToggle,
              child: InkWell(
                key: const ValueKey<String>('legend-lanes-toggle'),
                onTap: silentPress(onToggle),
                child: Center(
                  child: Icon(
                    anyLanesExpanded ? Icons.unfold_less : Icons.unfold_more,
                    size: 13,
                    color: restColor,
                  ),
                ),
              ),
            ),
          )
        : null;
  }

  Widget _buildTimesheet(TimelineLegendMenus menus, Color restColor) {
    return _cell(
      keyValue: 'legend-sheet',
      tooltip: AppText.strings.tlColTimesheet,
      entriesBuilder: menus.sheet,
      child: _legendIcon(
        Icons.table_chart_outlined,
        restColor: restColor,
        engaged: rowFilter.onTimesheetOnly,
      ),
    );
  }

  Widget _buildMark(TimelineLegendMenus menus, Color restColor) {
    return _cell(
      keyValue: 'legend-mark',
      tooltip: AppText.strings.tlColMark,
      entriesBuilder: menus.mark,
      child: _legendIcon(
        Icons.label_outline,
        restColor: restColor,
        engaged: rowFilter.markColors.isNotEmpty,
      ),
    );
  }

  Widget _buildTypeButton(TimelineLegendMenus menus, Color restColor) {
    return _cell(
      keyValue: 'legend-kind',
      tooltip: AppText.strings.tlColLayerKind,
      entriesBuilder: menus.kind,
      child: _legendIcon(
        Icons.interests_outlined,
        restColor: restColor,
        engaged: rowFilter.kinds.isNotEmpty,
      ),
    );
  }

  Widget _buildFillReference(TimelineLegendMenus menus, Color restColor) {
    return _cell(
      keyValue: 'legend-fill-ref',
      tooltip: AppText.strings.tlColFillReference,
      entriesBuilder: menus.fillReference,
      child: _legendIcon(
        Icons.format_color_fill,
        restColor: restColor,
        engaged: rowFilter.fillReferenceOnly,
      ),
    );
  }

  Widget _buildFx(BuildContext context, TimelineLegendMenus menus) {
    return _cell(
      keyValue: 'legend-fx',
      tooltip: AppText.strings.tlColFx,
      entriesBuilder: menus.fx,
      // The shared fx glyph (R28 follow-up) — the column
      // header and the row switches read the same mark.
      child: fxGlyph(context: context, active: rowFilter.fxOnly, fontSize: 11),
    );
  }

  Widget? _buildOnion(
    TimelineLegendMenus menus,
    bool hasOnion,
    Color restColor,
  ) {
    return !hasOnion
        ? null
        : _cell(
            keyValue: 'legend-onion',
            tooltip: AppText.strings.tlColOnionSkin,
            entriesBuilder: menus.onion,
            child: _legendIcon(
              Icons.filter_none,
              restColor: restColor,
              engaged: displayedOnionSkinOn,
            ),
          );
  }

  Widget _buildVisibility(TimelineLegendMenus menus, Color restColor) {
    return _cell(
      keyValue: 'legend-eye',
      tooltip: AppText.strings.tlColVisibility,
      entriesBuilder: menus.visibility,
      child: _legendIcon(
        Icons.visibility_outlined,
        restColor: restColor,
        engaged: visibilitySoloEnabled,
      ),
    );
  }

  Widget _buildMute(LayerLegendCallbacks? legend, Color restColor) {
    // One handler for the toggle, named once — the press claim and the tap
    // fire the same thing, and saying so twice was two more forks.
    final toggle = legend == null
        ? null
        : (allSeMuted ? legend.onUnmuteAllSe : legend.onMuteAllSe);
    return AppTooltip(
      // ↩️Written in English here, in every language, until I-40's round on
      // the legend found it (10-09).
      message: allSeMuted
          ? AppText.strings.tlUnmuteAllSe
          : AppText.strings.tlMuteAllSe,
      child: ControlPressClaim(
        onPressed: toggle,
        child: InkWell(
          key: const ValueKey<String>('legend-mute'),
          onTap: silentPress(toggle),
          child: Center(
            child: _legendIcon(
              allSeMuted ? Icons.volume_off : Icons.volume_up_outlined,
              restColor: restColor,
              engaged: allSeMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOpacity(
    BuildContext context,
    LayerLegendCallbacks? legend,
    ColorScheme colorScheme,
  ) {
    return legend != null && displayedLayerIds != null
        ? AppTooltip(
            message: AppText.strings.tlAllDisplayedOpacity,
            child: FieldSlider.opacity(
              key: const ValueKey<String>('legend-opacity'),
              axis: axis,
              value: displayedOpacity.clamp(0.0, 1.0).toDouble(),
              // The COLUMN's name while it rests, its number while it is
              // dragged (R4 #6) — the one bar whose resting text is not
              // its value.
              restingText: 'OPAC',
              height: 18 + FieldSlider.growthIn(context),
              restingAccent: colorScheme.onSurfaceVariant.withValues(
                alpha: 0.45,
              ),
              onChanged: (value) =>
                  legend.onPreviewLayersOpacity(displayedLayerIds!(), value),
              onChangeEnd: (value) =>
                  legend.onCommitLayersOpacity(displayedLayerIds!(), value),
            ),
          )
        : _cell(
            keyValue: 'legend-opacity',
            tooltip: AppText.strings.tlColOpacity,
            child: _columnHeading('OPAC', colorScheme, axis),
          );
  }

  Widget? _buildBlend(
    TimelineLegendMenus menus,
    bool hasBlend,
    ColorScheme colorScheme,
  ) {
    return !hasBlend
        ? null
        : _cell(
            keyValue: 'legend-blend',
            tooltip: AppText.strings.tlColBlendMode,
            entriesBuilder: menus.blend,
            child: _columnHeading('BLND', colorScheme, axis),
          );
  }

  /// Legend icons read like the row toggles now (R3 feedback #2): GRAY at
  /// rest, ACCENT while their column's display-solo/state is engaged.
  Widget _legendIcon(
    IconData icon, {
    required Color restColor,
    bool engaged = false,
  }) => Icon(icon, size: 13, color: engaged ? AppColors.accent : restColor);

  @override
  Widget buildKept(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final legend = this.legend;
    final menus = this.menus;

    final restColor = colorScheme.onSurfaceVariant;

    final isVertical = axis == Axis.vertical;
    final optional = optionalColumns;

    // The legend spans the rail: the rail's extent along its own axis, one
    // row across it. Stood up, the two swap — and across it is the sheet's
    // `layerControlsWidth`, which there means its frame-number rail.
    final railExtent = this.railExtent ?? metrics.layerControlsWidth;
    final crossExtent = isVertical
        ? metrics.layerControlsWidth
        : metrics.layerRowHeight;

    return Container(
      width: isVertical ? crossExtent : railExtent,
      height: isVertical ? railExtent : crossExtent,
      decoration: BoxDecoration(
        // A PLATE on the rail, not a chrome surface: the rows below carry the
        // same border ink, so with one chrome fill the legend became a layer
        // row byte for byte and the eye lost the top of the rail.
        color: AppColors.washUp,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      // The legend is laid out WHOLE, always. Cutting it to a short panel
      // is the rail window's job, and it cuts the rows beside it at the
      // same line — which is exactly what the two mechanisms this replaces
      // could not promise (R6a clipped the legend while scaling the
      // headers, and below 494px they parted visibly).
      child: Flex(
        direction: axis,
        children: [
          Expanded(
            child: Padding(
              // The rail's trailing breathing room. Stood up there is none
              // to give: the sheet's header block is sized to exactly this
              // list of slots, so 8px of padding is 8px of overflow.
              padding: isVertical
                  ? EdgeInsets.zero
                  : const EdgeInsets.only(right: 8),
              child: Flex(
                direction: axis,
                children: [
                  // The rows' own column skeleton, so every legend icon
                  // sits over the column it names (R9 #22). The sections
                  // cell rides the reserved band slot (UI-R5/R6 #5).
                  ...layerRailLeadingCells(
                    axis: axis,
                    // Over the rows' inline section band (UI-R5/R6 #5):
                    // the sections flyout.
                    sectionBand: _buildSectionBand(menus, colorScheme),
                    laneToggle: _buildLaneToggle(restColor),
                    timesheet: _buildTimesheet(menus, restColor),
                    mark: _buildMark(menus, restColor),
                    // Kind-solo flyout over the rows' TYPE BUTTON column
                    // (R4 #8): solo one layer TYPE like the mark colors.
                    typeButton: _buildTypeButton(menus, restColor),
                  ),
                  // Plain heading (R4 #3): the old LAYER ▾ flyout's jobs
                  // moved to the command bar (add) and the lane-column
                  // toggle (fold all). Stood up it writes vertically, the
                  // same table the columns' own names use.
                  Expanded(
                    child: isVertical
                        ? VerticalWritingText(
                            key: const ValueKey<String>('legend-layer'),
                            // The same word as lying down: F-37 tabled the
                            // timeline's heading and left this one English.
                            text: AppText.strings.tlLegendLayer,
                            // Stands up with the names it heads (user,
                            // 2026-08-08): a heading lying down over a
                            // column of upright names reads as a different
                            // kind of label than the thing it labels.
                            latinForm: VerticalLatinForm.upright,
                            mainAlignment: 0,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          )
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              AppText.strings.tlLegendLayer,
                              key: const ValueKey<String>('legend-layer'),
                              style: TextStyle(
                                fontSize: 9,
                                letterSpacing: 0.8,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                  ),
                  ...layerRailTrailingCells(
                    axis: axis,
                    columns: metrics.railColumns,
                    optionalColumns: optional,
                    fillReference: _buildFillReference(menus, restColor),
                    fx: _buildFx(context, menus),
                    // Onion legend (UI-R17 #5): bulk apply/clear over the
                    // displayed layers + the panel reveal. Hosts without
                    // the callback (storyboard rail) skip the COLUMN so
                    // their row columns stay aligned.
                    //
                    // The HEADING follows the COLUMN, and only the flyout
                    // follows the callbacks. It used to be the other way
                    // round, which is why the x-sheet — whose rows carry
                    // onion but which passed no legend bulk commands then —
                    // reserved the slot and left it blank: the one column
                    // on that surface with no heading over it.
                    onion: _buildOnion(menus, optional.onion, restColor),
                    visibility: _buildVisibility(menus, restColor),
                    // The mute cell is a DIRECT all-SE toggle (R3 feedback
                    // #10): one tap mutes/unmutes every SE row, colored by
                    // the muted state — no flyout.
                    mute: _buildMute(legend, restColor),
                    // MASTER opacity bar (R4 #6): drags every DISPLAYED
                    // row's opacity (filter-passing — solo a color/kind
                    // first to scope it). Gray at rest on the LAST
                    // committed value (UI-R6 #2); accent + live % while
                    // adjusting; preview per move, ONE write on release.
                    // ↩️Stood up, the bar stood down (R10 R6, 08-01): a
                    // 28px-wide column was no slider, and a rotated one
                    // lost the arena. A bar runs down a column now, as the
                    // x-sheet's own rows' bars do ([FieldSlider.axis]), and
                    // the corner opens what the rail's header opens
                    // (F-408 ②).
                    opacity: _buildOpacity(context, legend, colorScheme),
                    // R27 #6: the BLEND column header — one pick applies
                    // the mode to every displayed compositing row, the
                    // master opacity bar's logic in a flyout. A host that
                    // does not carry the column skips it, so its row
                    // columns stay aligned (the onion precedent).
                    //
                    // Heading follows the COLUMN, flyout follows the bulk
                    // callback — see the onion cell above.
                    blend: _buildBlend(menus, optional.blend, colorScheme),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A column's four-letter heading, written the way its rail runs.
  ///
  /// R5 #1: on the sheet these were the last two labels still lying down.
  /// Every other piece of text in that column stands up — the row names,
  /// the section band's ACTION/SE/CAM, the lane names — so OPAC and BLND
  /// were the only place left where reading the sheet meant tilting your
  /// head. The letters stand and the word runs down the column.
  ///
  /// `letterSpacing` goes with the turn: it is a HORIZONTAL notion and the
  /// vertical renderer zeroes it anyway (the leading comes from the cell
  /// extent), so carrying it across would only say something untrue.
  static Widget _columnHeading(
    String label,
    ColorScheme colorScheme,
    Axis axis,
  ) {
    final style = TextStyle(
      fontSize: 8.5,
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurfaceVariant,
    );
    return axis == Axis.horizontal
        ? Text(label, style: style.copyWith(letterSpacing: 0.6))
        : ClipRect(
            child: VerticalWritingText(
              text: label,
              latinForm: VerticalLatinForm.upright,
              style: style,
            ),
          );
  }
}
