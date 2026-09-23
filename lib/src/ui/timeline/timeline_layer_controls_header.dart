import 'package:flutter/material.dart';

import '../input/control_press_claim.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';
import '../theme/app_theme.dart';
import '../widgets/field_slider.dart';
import '../widgets/panel_flyout.dart';
import 'layer_label_controls.dart';
import 'layer_rail_columns.dart';
import 'timeline_grid_metrics.dart';
import 'timeline_row_filter.dart';
import 'timeline_section_policy.dart';
import '../shortcuts/editor_action_registry.dart';
import '../shortcuts/editor_shortcut_scope.dart';
import '../text/app_strings.dart';
import '../text/model_vocabulary.dart';
import '../text/vertical_writing_text.dart';

/// The rail legend's bulk commands (session-backed; the host wires them).
/// Project-state sweeps (sheet/mark/fill-ref) land as ONE undo; the
/// view-ish ones (eye/mute/fx/opacity) mirror their per-row toggles. The
/// row-solo facets and the master opacity bar ride the same struct.
class LayerLegendCallbacks {
  const LayerLegendCallbacks({
    required this.onShowAllLayers,
    required this.onHideAllLayers,
    required this.onToggleVisibilitySolo,
    required this.onSheetAllOn,
    required this.onSheetAllOff,
    required this.onClearAllMarks,
    required this.onClearAllFillReferences,
    required this.onMuteAllSe,
    required this.onUnmuteAllSe,
    required this.onBypassAllFx,
    required this.onEnableAllFx,
    required this.onToggleMarkFilter,
    required this.onToggleKindFilter,
    required this.onToggleSheetOnlyFilter,
    required this.onToggleFxOnlyFilter,
    required this.onToggleFillReferenceOnlyFilter,
    required this.onPreviewLayersOpacity,
    required this.onCommitLayersOpacity,
    this.onToggleOnionSkinForDisplayed,
    this.onRevealOnionSkinPanel,
    this.onSetBlendModeForDisplayed,
  });

  final VoidCallback onShowAllLayers;
  final VoidCallback onHideAllLayers;

  /// Toggles the visibility SOLO MODE (follows the active layer; R3
  /// feedback #3) — a mode switch, not a one-shot eye sweep.
  final VoidCallback onToggleVisibilitySolo;
  final VoidCallback onSheetAllOn;
  final VoidCallback onSheetAllOff;
  final VoidCallback onClearAllMarks;
  final VoidCallback onClearAllFillReferences;
  final VoidCallback onMuteAllSe;
  final VoidCallback onUnmuteAllSe;
  final VoidCallback onBypassAllFx;
  final VoidCallback onEnableAllFx;

  /// R2/R4 row-filter facet toggles (mark colors + layer kinds).
  final ValueChanged<LayerMark> onToggleMarkFilter;
  final ValueChanged<LayerKind> onToggleKindFilter;
  final VoidCallback onToggleSheetOnlyFilter;
  final VoidCallback onToggleFxOnlyFilter;
  final VoidCallback onToggleFillReferenceOnlyFilter;

  /// The legend's MASTER opacity bar (R4 #6): per-move preview + one
  /// commit on release, over the rows the rail currently displays (the
  /// grid computes the set).
  final void Function(Set<LayerId> layerIds, double opacity)
  onPreviewLayersOpacity;
  final void Function(Set<LayerId> layerIds, double opacity)
  onCommitLayersOpacity;

  /// Onion legend (UI-R17 #5): bulk-apply/clear for every DISPLAYED
  /// drawing layer, and the "open the onion panel" reveal (already open =
  /// the panel flashes in place). Null hides the onion legend cell.
  final VoidCallback? onToggleOnionSkinForDisplayed;
  final VoidCallback? onRevealOnionSkinPanel;

  /// R27 #6: the BLEND column's bulk command — the master opacity bar's
  /// rule applied to the mode: one pick sets every DISPLAYED row that
  /// composites (the same [displayedLayerIds] set the opacity bar drags).
  final void Function(Set<LayerId> layerIds, LayerBlendMode mode)?
  onSetBlendModeForDisplayed;
}

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
class TimelineLayerControlsHeader extends StatelessWidget {
  const TimelineLayerControlsHeader({
    super.key,
    required this.metrics,
    this.axis = Axis.horizontal,
    this.railExtent,
    this.hasOnionColumn,
    this.hasBlendColumn,
    this.legend,
    this.hiddenSections = const {},
    this.onToggleSection,
    this.onCollapseAllLanes,
    this.onExpandAllLanes,
    this.rowFilter = TimelineRowFilter.none,
    this.marksInUse = const {},
    this.kindsInUse = const {},
    this.visibilitySoloEnabled = false,
    this.anyLanesExpanded = false,
    this.allSeMuted = false,
    this.displayedLayerIds,
    this.displayedOpacity = 1.0,
    this.displayedOnionSkinOn = false,
    this.showRowSolos = true,
  });

  final TimelineGridMetrics metrics;

  /// The rail's own direction (R10 R6): horizontal above the timeline's
  /// rail, vertical in the x-sheet's corner.
  final Axis axis;

  /// Overrides how far the legend runs along [axis]. The x-sheet's corner
  /// passes the header block's resolved height, which is the natural
  /// stood-up rail only when the panel is tall enough to hold it; null
  /// takes the natural extent.
  final double? railExtent;

  /// Forces the optional columns on or off instead of inferring them from
  /// [legend]'s bulk callbacks. The x-sheet's corner needs this: its rows
  /// carry onion and blend but it has no legend flyouts to infer from, and
  /// a legend that disagreed with its rows would stop naming their columns.
  final bool? hasOnionColumn;
  final bool? hasBlendColumn;

  /// Null renders a display-only legend (no flyouts) — passive hosts.
  final LayerLegendCallbacks? legend;

  final Set<TimelineSection> hiddenSections;
  final ValueChanged<TimelineSection>? onToggleSection;

  /// The active row filter (for the legend flyouts' check marks).
  final TimelineRowFilter rowFilter;

  /// Marks currently assigned across the active cut's layers — the
  /// "solo color X" list is built from these (empty color set skipped).
  final Set<LayerMark> marksInUse;

  /// Kinds present across the active cut's layers — the "solo kind" list
  /// (R4 #8) is built from these.
  final Set<LayerKind> kindsInUse;

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

  List<PanelFlyoutEntry> _sectionEntries() {
    return [
      PanelFlyoutHeader(AppText.strings.tlSections),
      PanelFlyoutItem(
        keyValue: 'legend-section-se',
        label: AppText.strings.tlShowSeRows,
        icon: Icons.music_note_outlined,
        enabled: onToggleSection != null,
        checked: !hiddenSections.contains(TimelineSection.se),
        onSelected: () => onToggleSection?.call(TimelineSection.se),
      ),
      PanelFlyoutItem(
        keyValue: 'legend-section-camera',
        label: AppText.strings.tlShowCameraRows,
        icon: Icons.videocam_outlined,
        enabled: onToggleSection != null,
        checked: !hiddenSections.contains(TimelineSection.camera),
        onSelected: () => onToggleSection?.call(TimelineSection.camera),
      ),
    ];
  }

  // R9 #22: the cell no longer carries its own width — the rail's shared
  // column skeleton sizes it, so a legend icon cannot drift off the
  // column it labels (its kind cell used to be 18 against the rows' 22).
  Widget _cell({
    required String keyValue,
    required String tooltip,
    required Widget child,
    List<PanelFlyoutEntry> Function()? entriesBuilder,
  }) {
    final content = Center(child: child);
    // The key stays on the cell whether or not it can open a flyout —
    // it's the column's stable address (legend alignment tests).
    if (entriesBuilder == null) {
      return Tooltip(
        key: ValueKey<String>(keyValue),
        message: tooltip,
        child: content,
      );
    }
    return Builder(
      builder: (anchorContext) => Tooltip(
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
    LayerLegendCallbacks? legend,
    ColorScheme colorScheme,
  ) {
    return _cell(
      keyValue: 'legend-sections',
      tooltip: AppText.strings.tlSections,
      entriesBuilder: _sectionEntries,
      child: Icon(
        Icons.view_agenda_outlined,
        size: 13,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget? _buildLaneToggle(LayerLegendCallbacks? legend, Color restColor) {
    // The lane column's header: fold/unfold EVERY layer's lanes in one tap
    // (R3 feedback #5). The toggle has ONE handler, named once.
    final onToggle = anyLanesExpanded ? onCollapseAllLanes : onExpandAllLanes;
    return onExpandAllLanes != null && onCollapseAllLanes != null
        ? Tooltip(
            message: anyLanesExpanded
                ? 'Collapse all layers'
                : 'Expand all layers',
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

  /// One legend cell whose flyout is BULK OPS then, only where the host
  /// shows row solos, a divider and the SOLO entries.
  ///
  /// The template four cells spell out (timesheet, mark, fill-ref, fx).
  /// A null [legend] means no flyout at all; a solo half that comes back
  /// EMPTY takes its divider with it, so a host with row solos on but
  /// nothing to solo never shows a stray line.
  ///
  /// [_buildTypeButton] deliberately calls [_cell] directly instead: its
  /// whole flyout is solos with no bulk half, so it nulls the builder
  /// outright — an all-or-nothing law, not this one.
  Widget _legendFlyoutCell({
    required String keyValue,
    required String tooltip,
    required Widget child,
    required _LegendFlyout? flyout,
  }) {
    return _cell(
      keyValue: keyValue,
      tooltip: tooltip,
      child: child,
      entriesBuilder: flyout == null
          ? null
          : () {
              final solos = showRowSolos
                  ? flyout.solo()
                  : const <PanelFlyoutEntry>[];
              return [
                ...flyout.bulk(),
                if (solos.isNotEmpty) const PanelFlyoutDivider(),
                ...solos,
              ];
            },
    );
  }

  Widget _buildTimesheet(LayerLegendCallbacks? legend, Color restColor) {
    return _legendFlyoutCell(
      keyValue: 'legend-sheet',
      tooltip: AppText.strings.tlColTimesheet,
      flyout: legend == null
          ? null
          : _LegendFlyout(
              bulk: () => [
                PanelFlyoutItem(
                  keyValue: 'legend-sheet-all-on',
                  label: AppText.strings.tlAllOnTimesheet,
                  icon: Icons.table_chart,
                  onSelected: legend.onSheetAllOn,
                ),
                PanelFlyoutItem(
                  keyValue: 'legend-sheet-all-off',
                  label: AppText.strings.tlAllOffTimesheet,
                  icon: Icons.table_chart_outlined,
                  onSelected: legend.onSheetAllOff,
                ),
              ],
              solo: () => [
                PanelFlyoutItem(
                  keyValue: 'legend-filter-sheet',
                  label: AppText.strings.tlSoloSheetOnRows,
                  icon: Icons.center_focus_strong_outlined,
                  checked: rowFilter.onTimesheetOnly,
                  onSelected: legend.onToggleSheetOnlyFilter,
                ),
              ],
            ),
      child: _legendIcon(
        Icons.table_chart_outlined,
        restColor: restColor,
        engaged: rowFilter.onTimesheetOnly,
      ),
    );
  }

  Widget _buildMark(LayerLegendCallbacks? legend, Color restColor) {
    return _legendFlyoutCell(
      keyValue: 'legend-mark',
      tooltip: AppText.strings.tlColMark,
      flyout: legend == null
          ? null
          : _LegendFlyout(
              bulk: () => [
                PanelFlyoutItem(
                  keyValue: 'legend-mark-clear',
                  label: AppText.strings.tlClearAllMarks,
                  icon: Icons.label_off_outlined,
                  onSelected: legend.onClearAllMarks,
                ),
              ],
              // 🚨THE MARKS IN USE, not every mark there
              // could be. A mark is a 공정/수정 pair now,
              // so «every value» is a product of two lists
              // and most of it would never appear in this
              // project — the filter was always about what
              // is actually on the rows, and this says so.
              //
              // Answering EMPTY when nothing is marked is what drops the
              // divider too — the old `showRowSolos && marksInUse
              // .isNotEmpty` gate, said once by the template.
              solo: () => marksInUse.isEmpty
                  ? const []
                  : [
                      PanelFlyoutHeader(AppText.strings.tlSoloColor),
                      for (final mark
                          in marksInUse.toList()
                            ..sort((a, b) => a.sortKey.compareTo(b.sortKey)))
                        if (!mark.isNone)
                          PanelFlyoutItem(
                            keyValue: 'legend-filter-mark-${mark.keySlug}',
                            label: layerMarkDisplayName(mark),
                            checked: rowFilter.markColors.contains(mark),
                            onSelected: () => legend.onToggleMarkFilter(mark),
                          ),
                    ],
            ),
      child: _legendIcon(
        Icons.label_outline,
        restColor: restColor,
        engaged: rowFilter.markColors.isNotEmpty,
      ),
    );
  }

  Widget _buildTypeButton(LayerLegendCallbacks? legend, Color restColor) {
    return _cell(
      keyValue: 'legend-kind',
      tooltip: AppText.strings.tlColLayerKind,
      entriesBuilder: legend == null || kindsInUse.isEmpty || !showRowSolos
          ? null
          : () => [
              PanelFlyoutHeader(AppText.strings.tlSoloKind),
              for (final kind in LayerKind.values)
                if (kindsInUse.contains(kind))
                  PanelFlyoutItem(
                    keyValue: 'legend-filter-kind-${kind.name}',
                    label: layerKindDisplayName(kind),
                    icon: layerKindIcon(kind),
                    checked: rowFilter.kinds.contains(kind),
                    onSelected: () => legend.onToggleKindFilter(kind),
                  ),
            ],
      child: _legendIcon(
        Icons.interests_outlined,
        restColor: restColor,
        engaged: rowFilter.kinds.isNotEmpty,
      ),
    );
  }

  Widget _buildFillReference(LayerLegendCallbacks? legend, Color restColor) {
    return _legendFlyoutCell(
      keyValue: 'legend-fill-ref',
      tooltip: AppText.strings.tlColFillReference,
      flyout: legend == null
          ? null
          : _LegendFlyout(
              bulk: () => [
                PanelFlyoutItem(
                  keyValue: 'legend-fill-ref-clear',
                  label: AppText.strings.tlClearAllFillRefs,
                  icon: Icons.format_color_reset_outlined,
                  onSelected: legend.onClearAllFillReferences,
                ),
              ],
              solo: () => [
                PanelFlyoutItem(
                  keyValue: 'legend-filter-fill-ref',
                  label: AppText.strings.tlSoloFillReferences,
                  icon: Icons.center_focus_strong_outlined,
                  checked: rowFilter.fillReferenceOnly,
                  onSelected: legend.onToggleFillReferenceOnlyFilter,
                ),
              ],
            ),
      child: _legendIcon(
        Icons.format_color_fill,
        restColor: restColor,
        engaged: rowFilter.fillReferenceOnly,
      ),
    );
  }

  Widget _buildFx(BuildContext context, LayerLegendCallbacks? legend) {
    return _legendFlyoutCell(
      keyValue: 'legend-fx',
      tooltip: AppText.strings.tlColFx,
      flyout: legend == null
          ? null
          : _LegendFlyout(
              bulk: () => [
                PanelFlyoutItem(
                  keyValue: 'legend-fx-enable-all',
                  label: AppText.strings.tlApplyAllFx,
                  onSelected: legend.onEnableAllFx,
                ),
                PanelFlyoutItem(
                  keyValue: 'legend-fx-bypass-all',
                  label: AppText.strings.tlBypassAllFx,
                  onSelected: legend.onBypassAllFx,
                ),
              ],
              solo: () => [
                PanelFlyoutItem(
                  keyValue: 'legend-filter-fx',
                  label: AppText.strings.tlSoloFxOnRows,
                  icon: Icons.center_focus_strong_outlined,
                  checked: rowFilter.fxOnly,
                  onSelected: legend.onToggleFxOnlyFilter,
                ),
              ],
            ),
      // The shared fx glyph (R28 follow-up) — the column
      // header and the row switches read the same mark.
      child: fxGlyph(context: context, active: rowFilter.fxOnly, fontSize: 11),
    );
  }

  Widget? _buildOnion(
    LayerLegendCallbacks? legend,
    bool hasOnion,
    Color restColor,
  ) {
    return !hasOnion
        ? null
        : _cell(
            keyValue: 'legend-onion',
            tooltip: AppText.strings.tlColOnionSkin,
            entriesBuilder: legend?.onToggleOnionSkinForDisplayed == null
                ? null
                : () => [
                    PanelFlyoutItem(
                      keyValue: 'legend-onion-toggle-displayed',
                      label: displayedOnionSkinOn
                          ? 'Clear onion on displayed layers'
                          : 'Apply onion to displayed layers',
                      icon: Icons.filter_none,
                      checked: displayedOnionSkinOn,
                      onSelected: legend!.onToggleOnionSkinForDisplayed,
                    ),
                    if (legend.onRevealOnionSkinPanel != null)
                      PanelFlyoutItem(
                        keyValue: 'legend-onion-open-panel',
                        label: AppText.strings.tlOpenOnionPanel,
                        icon: Icons.open_in_new,
                        onSelected: legend.onRevealOnionSkinPanel,
                      ),
                  ],
            child: _legendIcon(
              Icons.filter_none,
              restColor: restColor,
              engaged: displayedOnionSkinOn,
            ),
          );
  }

  Widget _buildVisibility(LayerLegendCallbacks? legend, Color restColor) {
    return _cell(
      keyValue: 'legend-eye',
      tooltip: AppText.strings.tlColVisibility,
      entriesBuilder: legend == null
          ? null
          : () => [
              PanelFlyoutItem(
                keyValue: 'legend-eye-show-all',
                label: AppText.strings.tlShowAll,
                icon: Icons.visibility,
                onSelected: legend.onShowAllLayers,
              ),
              PanelFlyoutItem(
                keyValue: 'legend-eye-hide-all',
                label: AppText.strings.tlHideAll,
                icon: Icons.visibility_off,
                onSelected: legend.onHideAllLayers,
              ),
              PanelFlyoutItem(
                keyValue: 'legend-eye-solo',
                // The registry's name: `=` presses this item (I-19).
                label: editorActionLabel(EditorActionIds.layerVisibilitySolo),
                shortcuts: const [EditorActionIds.layerVisibilitySolo],
                icon: Icons.center_focus_strong_outlined,
                checked: visibilitySoloEnabled,
                onSelected: legend.onToggleVisibilitySolo,
              ),
            ],
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
    return Tooltip(
      message: allSeMuted ? 'Unmute all SE' : 'Mute all SE',
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
    LayerLegendCallbacks? legend,
    bool isVertical,
    ColorScheme colorScheme,
  ) {
    return legend != null && displayedLayerIds != null && !isVertical
        ? Tooltip(
            message: AppText.strings.tlAllDisplayedOpacity,
            child: FieldSlider.opacity(
              key: const ValueKey<String>('legend-opacity'),
              value: displayedOpacity.clamp(0.0, 1.0).toDouble(),
              // The COLUMN's name while it rests, its number while it is
              // dragged (R4 #6) — the one bar whose resting text is not
              // its value.
              restingText: 'OPAC',
              height: 18,
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
    LayerLegendCallbacks? legend,
    bool hasBlend,
    ColorScheme colorScheme,
  ) {
    return !hasBlend
        ? null
        : _cell(
            keyValue: 'legend-blend',
            tooltip: AppText.strings.tlColBlendMode,
            entriesBuilder:
                legend?.onSetBlendModeForDisplayed == null ||
                    displayedLayerIds == null
                ? null
                : () => [
                    PanelFlyoutHeader(AppText.strings.tlAllDisplayedLayers),
                    // The bulk set writes DRAWING rows;
                    // pass-through is a group-only answer,
                    // so it never appears here.
                    for (final mode in LayerBlendMode.optionsFor(
                      isGroup: false,
                    ))
                      PanelFlyoutItem(
                        keyValue: 'legend-blend-${mode.name}',
                        label: mode.labelFor(AppText.language),
                        onSelected: () => legend!.onSetBlendModeForDisplayed!(
                          displayedLayerIds!(),
                          mode,
                        ),
                      ),
                  ],
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
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final legend = this.legend;

    final restColor = colorScheme.onSurfaceVariant;

    final isVertical = axis == Axis.vertical;
    // Which optional columns this host carries. Hoisted because the stood-up
    // legend has to SIZE itself from the same answer it lays out from — a
    // Column has no `Expanded` slack to hide a disagreement in, unlike the
    // horizontal rail where the LAYER heading absorbs it.
    final hasOnion =
        hasOnionColumn ?? legend?.onToggleOnionSkinForDisplayed != null;
    final hasBlend =
        hasBlendColumn ??
        (legend?.onSetBlendModeForDisplayed != null &&
            displayedLayerIds != null);

    // The legend spans the rail: the rail's extent along its own axis, one
    // row across it. Stood up, the two swap — and the rail's extent is the
    // TIMELINE'S, because the x-sheet's own `layerControlsWidth` means its
    // frame-number rail, a different thing entirely.
    final railExtent =
        this.railExtent ??
        (isVertical
            ? timelineLayerControlsWidth -
                  (hasOnion ? 0 : layerOnionSlotWidth) -
                  (hasBlend ? 0 : layerBlendSlotWidth)
            : metrics.layerControlsWidth);
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
                    sectionBand: _buildSectionBand(legend, colorScheme),
                    laneToggle: _buildLaneToggle(legend, restColor),
                    timesheet: _buildTimesheet(legend, restColor),
                    mark: _buildMark(legend, restColor),
                    // Kind-solo flyout over the rows' TYPE BUTTON column
                    // (R4 #8): solo one layer TYPE like the mark colors.
                    typeButton: _buildTypeButton(legend, restColor),
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
                    fillReference: _buildFillReference(legend, restColor),
                    fx: _buildFx(context, legend),
                    // Onion legend (UI-R17 #5): bulk apply/clear over the
                    // displayed layers + the panel reveal. Hosts without
                    // the callback (storyboard rail) skip the COLUMN so
                    // their row columns stay aligned.
                    hasOnionColumn: hasOnion,
                    // The HEADING follows the COLUMN, and only the flyout
                    // follows the callbacks. It used to be the other way
                    // round, which is why the x-sheet — whose rows carry
                    // onion but which passes no legend bulk commands —
                    // reserved the slot and left it blank: the one column
                    // on that surface with no heading over it.
                    onion: _buildOnion(legend, hasOnion, restColor),
                    visibility: _buildVisibility(legend, restColor),
                    // The mute cell is a DIRECT all-SE toggle (R3 feedback
                    // #10): one tap mutes/unmutes every SE row, colored by
                    // the muted state — no flyout.
                    mute: _buildMute(legend, restColor),
                    // MASTER opacity bar (R4 #6): drags every DISPLAYED
                    // row's opacity (filter-passing — solo a color/kind
                    // first to scope it). Gray at rest on the LAST
                    // committed value (UI-R6 #2); accent + live % while
                    // adjusting; preview per move, ONE write on release.
                    // Stood up, the bar stands down: a 28px-wide column is
                    // not a slider, and a rotated one would lose the arena
                    // (a vertical screen drag never reaches a horizontal
                    // recognizer). The column keeps its heading.
                    opacity: _buildOpacity(legend, isVertical, colorScheme),
                    // R27 #6: the BLEND column header — one pick applies
                    // the mode to every displayed compositing row, the
                    // master opacity bar's logic in a flyout. Hosts
                    // without the bulk callback (the storyboard rail) skip
                    // the COLUMN so their row columns stay aligned (the
                    // onion precedent).
                    hasBlendColumn: hasBlend,
                    // Heading follows the COLUMN, flyout follows the bulk
                    // callback — see the onion cell above.
                    blend: _buildBlend(legend, hasBlend, colorScheme),
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

/// One legend cell's flyout halves, both LAZY: the entries are built when
/// the list opens, not when the header builds.
///
/// A value rather than two more parameters on the cell, and it exists only
/// where the legend does — the callbacks are already captured, so the cell
/// never asks again whether it has a legend.
class _LegendFlyout {
  const _LegendFlyout({required this.bulk, required this.solo});

  /// The bulk ops — always shown.
  final List<PanelFlyoutEntry> Function() bulk;

  /// The row SOLOS — shown only where the host filters rows, and an EMPTY
  /// answer takes the divider with it.
  final List<PanelFlyoutEntry> Function() solo;
}
