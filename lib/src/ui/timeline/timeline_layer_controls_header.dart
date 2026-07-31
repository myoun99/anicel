import 'package:flutter/material.dart';

import '../../models/app_language.dart' show AppLanguage;
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
import '../text/app_strings.dart';

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
class TimelineLayerControlsHeader extends StatelessWidget {
  const TimelineLayerControlsHeader({
    super.key,
    required this.metrics,
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
    this.blendLanguage = AppLanguage.en,
  });

  /// PROGRAM language for the blend column's mode names (R27 #6).
  final AppLanguage blendLanguage;

  final TimelineGridMetrics metrics;

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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final legend = this.legend;

    // R9 #22: the cell no longer carries its own width — the rail's shared
    // column skeleton sizes it, so a legend icon cannot drift off the
    // column it labels (its kind cell used to be 18 against the rows' 22).
    Widget cell({
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
          child: InkWell(
            key: ValueKey<String>(keyValue),
            onTap: () =>
                showPanelFlyout(anchorContext, entries: entriesBuilder()),
            child: content,
          ),
        ),
      );
    }

    // Legend icons read like the row toggles now (R3 feedback #2): GRAY at
    // rest, ACCENT while their column's display-solo/state is engaged.
    final restColor = colorScheme.onSurfaceVariant;
    Widget legendIcon(IconData icon, {bool engaged = false}) =>
        Icon(icon, size: 13, color: engaged ? AppColors.accent : restColor);

    return Container(
      width: metrics.layerControlsWidth,
      height: metrics.layerRowHeight,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  // The rows' own column skeleton, so every legend icon
                  // sits over the column it names (R9 #22). The sections
                  // cell rides the reserved band slot (UI-R5/R6 #5).
                  ...layerRailLeadingCells(
                    // Over the rows' inline section band (UI-R5/R6 #5):
                    // the sections flyout.
                    sectionBand: cell(
                      keyValue: 'legend-sections',
                      tooltip: AppText.strings.tlSections,
                      entriesBuilder: _sectionEntries,
                      child: Icon(
                        Icons.view_agenda_outlined,
                        size: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    laneToggle:
                        onExpandAllLanes != null && onCollapseAllLanes != null
                        // The lane column's header: fold/unfold EVERY
                        // layer's lanes in one tap (R3 feedback #5).
                        ? Tooltip(
                            message: anyLanesExpanded
                                ? 'Collapse all layers'
                                : 'Expand all layers',
                            child: InkWell(
                              key: const ValueKey<String>('legend-lanes-toggle'),
                              onTap: anyLanesExpanded
                                  ? onCollapseAllLanes
                                  : onExpandAllLanes,
                              child: Center(
                                child: Icon(
                                  anyLanesExpanded
                                      ? Icons.unfold_less
                                      : Icons.unfold_more,
                                  size: 13,
                                  color: restColor,
                                ),
                              ),
                            ),
                          )
                        : null,
                    timesheet: cell(
                      keyValue: 'legend-sheet',
                      tooltip: AppText.strings.tlColTimesheet,
                      entriesBuilder: legend == null
                          ? null
                          : () => [
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
                              if (showRowSolos) ...[
                                const PanelFlyoutDivider(),
                                PanelFlyoutItem(
                                  keyValue: 'legend-filter-sheet',
                                  label: AppText.strings.tlSoloSheetOnRows,
                                  icon: Icons.center_focus_strong_outlined,
                                  checked: rowFilter.onTimesheetOnly,
                                  onSelected: legend.onToggleSheetOnlyFilter,
                                ),
                              ],
                            ],
                      child: legendIcon(
                        Icons.table_chart_outlined,
                        engaged: rowFilter.onTimesheetOnly,
                      ),
                    ),
                    mark: cell(
                      keyValue: 'legend-mark',
                      tooltip: AppText.strings.tlColMark,
                      entriesBuilder: legend == null
                          ? null
                          : () => [
                              PanelFlyoutItem(
                                keyValue: 'legend-mark-clear',
                                label: AppText.strings.tlClearAllMarks,
                                icon: Icons.label_off_outlined,
                                onSelected: legend.onClearAllMarks,
                              ),
                              if (showRowSolos && marksInUse.isNotEmpty) ...[
                                const PanelFlyoutDivider(),
                                PanelFlyoutHeader(AppText.strings.tlSoloColor),
                                for (final mark in LayerMark.values)
                                  if (mark != LayerMark.none &&
                                      marksInUse.contains(mark))
                                    PanelFlyoutItem(
                                      keyValue:
                                          'legend-filter-mark-${mark.name}',
                                      label: layerMarkDisplayName(mark),
                                      checked: rowFilter.markColors.contains(
                                        mark,
                                      ),
                                      onSelected: () =>
                                          legend.onToggleMarkFilter(mark),
                                    ),
                              ],
                            ],
                      child: legendIcon(
                        Icons.label_outline,
                        engaged: rowFilter.markColors.isNotEmpty,
                      ),
                    ),
                    // Kind-solo flyout over the rows' TYPE BUTTON column
                    // (R4 #8): solo one layer TYPE like the mark colors.
                    typeButton: cell(
                      keyValue: 'legend-kind',
                      tooltip: AppText.strings.tlColLayerKind,
                      entriesBuilder:
                          legend == null || kindsInUse.isEmpty || !showRowSolos
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
                                    onSelected: () =>
                                        legend.onToggleKindFilter(kind),
                                  ),
                            ],
                      child: legendIcon(
                        Icons.interests_outlined,
                        engaged: rowFilter.kinds.isNotEmpty,
                      ),
                    ),
                  ),
                  // Plain heading (R4 #3): the old LAYER ▾ flyout's jobs
                  // moved to the command bar (add) and the lane-column
                  // toggle (fold all).
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'LAYER',
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
                    fillReference: cell(
                      keyValue: 'legend-fill-ref',
                      tooltip: AppText.strings.tlColFillReference,
                      entriesBuilder: legend == null
                          ? null
                          : () => [
                              PanelFlyoutItem(
                                keyValue: 'legend-fill-ref-clear',
                                label: AppText.strings.tlClearAllFillRefs,
                                icon: Icons.format_color_reset_outlined,
                                onSelected: legend.onClearAllFillReferences,
                              ),
                              if (showRowSolos) ...[
                                const PanelFlyoutDivider(),
                                PanelFlyoutItem(
                                  keyValue: 'legend-filter-fill-ref',
                                  label: AppText.strings.tlSoloFillReferences,
                                  icon: Icons.center_focus_strong_outlined,
                                  checked: rowFilter.fillReferenceOnly,
                                  onSelected:
                                      legend.onToggleFillReferenceOnlyFilter,
                                ),
                              ],
                            ],
                      child: legendIcon(
                        Icons.format_color_fill,
                        engaged: rowFilter.fillReferenceOnly,
                      ),
                    ),
                    fx: cell(
                      keyValue: 'legend-fx',
                      tooltip: AppText.strings.tlColFx,
                      entriesBuilder: legend == null
                          ? null
                          : () => [
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
                              if (showRowSolos) ...[
                                const PanelFlyoutDivider(),
                                PanelFlyoutItem(
                                  keyValue: 'legend-filter-fx',
                                  label: AppText.strings.tlSoloFxOnRows,
                                  icon: Icons.center_focus_strong_outlined,
                                  checked: rowFilter.fxOnly,
                                  onSelected: legend.onToggleFxOnlyFilter,
                                ),
                              ],
                            ],
                      // The shared fx glyph (R28 follow-up) — the column
                      // header and the row switches read the same mark.
                      child: fxGlyph(
                        context: context,
                        active: rowFilter.fxOnly,
                        fontSize: 11,
                      ),
                    ),
                    // Onion legend (UI-R17 #5): bulk apply/clear over the
                    // displayed layers + the panel reveal. Hosts without
                    // the callback (storyboard rail) skip the COLUMN so
                    // their row columns stay aligned.
                    hasOnionColumn: legend?.onToggleOnionSkinForDisplayed != null,
                    onion: legend?.onToggleOnionSkinForDisplayed == null
                        ? null
                        : cell(
                            keyValue: 'legend-onion',
                            tooltip: AppText.strings.tlColOnionSkin,
                            entriesBuilder: () => [
                              PanelFlyoutItem(
                                keyValue: 'legend-onion-toggle-displayed',
                                label: displayedOnionSkinOn
                                    ? 'Clear onion on displayed layers'
                                    : 'Apply onion to displayed layers',
                                icon: Icons.filter_none,
                                checked: displayedOnionSkinOn,
                                onSelected:
                                    legend!.onToggleOnionSkinForDisplayed!,
                              ),
                              if (legend.onRevealOnionSkinPanel != null)
                                PanelFlyoutItem(
                                  keyValue: 'legend-onion-open-panel',
                                  label: AppText.strings.tlOpenOnionPanel,
                                  icon: Icons.open_in_new,
                                  onSelected: legend.onRevealOnionSkinPanel!,
                                ),
                            ],
                            child: legendIcon(
                              Icons.filter_none,
                              engaged: displayedOnionSkinOn,
                            ),
                          ),
                    visibility: cell(
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
                                label: AppText.strings.tlSoloActiveLayer,
                                icon: Icons.center_focus_strong_outlined,
                                checked: visibilitySoloEnabled,
                                onSelected: legend.onToggleVisibilitySolo,
                              ),
                            ],
                      child: legendIcon(
                        Icons.visibility_outlined,
                        engaged: visibilitySoloEnabled,
                      ),
                    ),
                    // The mute cell is a DIRECT all-SE toggle (R3 feedback
                    // #10): one tap mutes/unmutes every SE row, colored by
                    // the muted state — no flyout.
                    mute: Tooltip(
                      message: allSeMuted ? 'Unmute all SE' : 'Mute all SE',
                      child: InkWell(
                        key: const ValueKey<String>('legend-mute'),
                        onTap: legend == null
                            ? null
                            : (allSeMuted
                                  ? legend.onUnmuteAllSe
                                  : legend.onMuteAllSe),
                        child: Center(
                          child: legendIcon(
                            allSeMuted
                                ? Icons.volume_off
                                : Icons.volume_up_outlined,
                            engaged: allSeMuted,
                          ),
                        ),
                      ),
                    ),
                    // MASTER opacity bar (R4 #6): drags every DISPLAYED
                    // row's opacity (filter-passing — solo a color/kind
                    // first to scope it). Gray at rest on the LAST
                    // committed value (UI-R6 #2); accent + live % while
                    // adjusting; preview per move, ONE write on release.
                    opacity: legend != null && displayedLayerIds != null
                        ? Tooltip(
                            message: 'All displayed layers opacity',
                            child: FieldSlider(
                              key: const ValueKey<String>('legend-opacity'),
                              min: 0,
                              max: 1,
                              value: displayedOpacity.clamp(0.0, 1.0).toDouble(),
                              valueText: 'OPAC',
                              valueTextBuilder: (value) =>
                                  '${(value * 100).round()}%',
                              displayFactor: 100,
                              height: 18,
                              restingAccent: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.45),
                              onChanged: (value) =>
                                  legend.onPreviewLayersOpacity(
                                    displayedLayerIds!(),
                                    value,
                                  ),
                              onChangeEnd: (value) =>
                                  legend.onCommitLayersOpacity(
                                    displayedLayerIds!(),
                                    value,
                                  ),
                            ),
                          )
                        : cell(
                            keyValue: 'legend-opacity',
                            tooltip: AppText.strings.tlColOpacity,
                            child: Text(
                              'OPAC',
                              style: TextStyle(
                                fontSize: 8.5,
                                letterSpacing: 0.6,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                    // R27 #6: the BLEND column header — one pick applies
                    // the mode to every displayed compositing row, the
                    // master opacity bar's logic in a flyout. Hosts
                    // without the bulk callback (the storyboard rail) skip
                    // the COLUMN so their row columns stay aligned (the
                    // onion precedent).
                    hasBlendColumn:
                        legend?.onSetBlendModeForDisplayed != null &&
                        displayedLayerIds != null,
                    blend:
                        legend?.onSetBlendModeForDisplayed == null ||
                            displayedLayerIds == null
                        ? null
                        : cell(
                            keyValue: 'legend-blend',
                            tooltip: AppText.strings.tlColBlendMode,
                            entriesBuilder: () => [
                              PanelFlyoutHeader(
                                AppText.strings.tlAllDisplayedLayers,
                              ),
                              // The bulk set writes DRAWING rows;
                              // pass-through is a group-only answer, so it
                              // never appears here.
                              for (final mode in LayerBlendMode.optionsFor(
                                isGroup: false,
                              ))
                                PanelFlyoutItem(
                                  keyValue: 'legend-blend-${mode.name}',
                                  label: mode.labelFor(blendLanguage),
                                  onSelected: () =>
                                      legend!.onSetBlendModeForDisplayed!(
                                        displayedLayerIds!(),
                                        mode,
                                      ),
                                ),
                            ],
                            child: Text(
                              'BLND',
                              style: TextStyle(
                                fontSize: 8.5,
                                letterSpacing: 0.6,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
