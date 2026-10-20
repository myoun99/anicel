import 'package:flutter/material.dart';

import '../../models/layer_blend_mode.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';
import '../shortcuts/editor_action_registry.dart';
import '../shortcuts/editor_shortcut_scope.dart' show editorActionLabel;
import '../text/app_strings.dart';
import '../text/model_vocabulary.dart' show LayerBlendModeWords;
import '../widgets/panel_flyout.dart';
import 'layer_label_controls.dart'
    show layerKindDisplayName, layerKindIcon, layerMarkDisplayName;
import 'timeline_row_filter.dart';
import 'timeline_section_policy.dart';

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
    required this.onClearMarkFilter,
    required this.onClearAllFillReferences,
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
  final VoidCallback onClearMarkFilter;
  final VoidCallback onClearAllFillReferences;
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

  /// Which optional verbs are here — what a legend shows of them: a column
  /// that opens a flyout or one that does not. The required verbs close
  /// over the session (R13-2), so having a legend says the rest.
  ({bool onion, bool reveal, bool blend}) get shape => (
    onion: onToggleOnionSkinForDisplayed != null,
    reveal: onRevealOnionSkinPanel != null,
    blend: onSetBlendModeForDisplayed != null,
  );
}

/// One legend column's flyout, built when it opens — or null where that
/// column opens none.
typedef LegendFlyout = List<PanelFlyoutEntry> Function();

/// The kinds the TIMELINE's rows can be ([TimelineLegendMenus.kinds]):
/// every kind — a cut's layers, its track's S rows, transition row and
/// camera row all stand on its rail (F-408).
final Set<LayerKind> timelineRailKinds = Set.unmodifiable(LayerKind.values);

/// The rail legend's menus as they open, for ONE panel's header: each
/// column's flyout, and with [rows] every row of them at once.
///
/// 🗣️I-40 (유저 2026-09-18): 「버튼 전수감사해서 숏컷리스트에 등록 … 뭐든 모든
/// 버튼」; asked how far (I-40-Q1, 10-08): the command buttons and menu rows
/// of the editing screen. ★A KEY AND ITS MENU ROW ARE ONE PRESS
/// ([pressFlyoutRow]): the header shows these lists, and the panel that
/// built its header publishes them for the shell, which presses a row by
/// its action on the panel being worked in — the same lists, so a key acts
/// only where its row would, on the rows that panel counts.
///
/// ↩️These were private methods of the header widget, which only a mounted
/// header could ask; they are the same rows, moved, each now naming its
/// action (the timeline bar's menus went the same way: TimelineBarMenus).
class TimelineLegendMenus {
  const TimelineLegendMenus({
    required this.legend,
    this.hiddenSections = const {},
    this.onToggleSection,
    this.rowFilter = TimelineRowFilter.none,
    this.marksInUse = noMarks,
    this.kinds = const {},
    this.visibilitySoloEnabled = false,
    this.displayedLayerIds,
    this.displayedOnionSkinOn = false,
  });

  /// No marks in use — a legend over no rows that carry one.
  static Set<LayerMark> noMarks() => const {};

  /// Null for a display-only legend: no column but the sections opens.
  final LayerLegendCallbacks? legend;

  final Set<TimelineSection> hiddenSections;
  final ValueChanged<TimelineSection>? onToggleSection;

  /// The active row filter (for the flyouts' check marks).
  final TimelineRowFilter rowFilter;

  /// Marks currently assigned across the panel's layers — the 「solo color
  /// X」 list is built from these — read when the list is.
  ///
  /// 🚨READ, NEVER HELD (I-57, 10-14): held, the two sets changed at every
  /// cut switch, and the header that hands them on was built again whole
  /// for sets none of its cells shows (🔬221 widgets of a crossing's 821)
  /// — `displayedLayerIds` went this way on 10-13 for the same reason.
  final Set<LayerMark> Function() marksInUse;

  /// The kinds this panel's rows can be — the kind solos (R4 #8), every one
  /// listed whether a row of it is on the panel now or not.
  ///
  /// 🗣️F-408 (유저 2026-10-19): 「타임라인패널의 레전드의 종류솔로,
  /// 애니메이션레이어가 없으니 추가. 대응하는 레이어가 다 있어야함.
  /// 콘티패널엔 이미지레이어 없으니 대응안되는거 리스트 정리」. ↩️It listed
  /// the kinds the rows carried, so a cut with no animation row had no
  /// animation solo.
  final Set<LayerKind> kinds;

  /// Whether the visibility SOLO MODE is on (the eye flyout's check).
  final bool visibilitySoloEnabled;

  /// The rows the rail currently DISPLAYS — the blend sweep's target set.
  /// Null takes the blend column's flyout away.
  final Set<LayerId> Function()? displayedLayerIds;

  /// Whether every displayed drawing layer is ghosting (UI-R17 #5).
  final bool displayedOnionSkinOn;

  /// Every row of every flyout the legend opens right now ([flyoutRowsOf])
  /// — what a key presses one of.
  List<PanelFlyoutItem> rows() => flyoutRowsOf([
    for (final flyout in [
      sections,
      sheet,
      mark,
      kind,
      fillReference,
      fx,
      onion,
      visibility,
      blend,
    ])
      if (flyout != null) ...flyout(),
  ]).toList();

  /// The section band's flyout — opens with or without a legend.
  LegendFlyout get sections => () => [
    PanelFlyoutHeader(AppText.strings.tlSections),
    PanelFlyoutItem(
      keyValue: 'legend-section-se',
      label: AppText.strings.tlShowSeRows,
      shortcuts: const [RailLegendActionIds.sectionSe],
      icon: Icons.music_note_outlined,
      enabled: onToggleSection != null,
      checked: !hiddenSections.contains(TimelineSection.se),
      onSelected: () => onToggleSection?.call(TimelineSection.se),
    ),
    PanelFlyoutItem(
      keyValue: 'legend-section-camera',
      label: AppText.strings.tlShowCameraRows,
      shortcuts: const [RailLegendActionIds.sectionCamera],
      icon: Icons.videocam_outlined,
      enabled: onToggleSection != null,
      checked: !hiddenSections.contains(TimelineSection.camera),
      onSelected: () => onToggleSection?.call(TimelineSection.camera),
    ),
  ];

  /// One column's flyout: its BULK OPS, then a divider and the SOLO
  /// entries. A solo half that comes back EMPTY takes its divider with it,
  /// so a legend with nothing to solo never shows a stray line. No legend,
  /// no flyout.
  ///
  /// ↩️A host could turn the solos off (`showRowSolos`) — the storyboard's,
  /// until it took every chip (#904, 2026-08-09: 「있는거면 다 달아서
  /// 통일」); no host has since, and the switch went with I-89 ① ⓖ.
  ///
  /// The template four columns spell out (timesheet, mark, fill-ref, fx).
  /// [kind] deliberately does not: its whole flyout is solos with no bulk
  /// half, so it opens nothing outright — an all-or-nothing law, not this
  /// one.
  LegendFlyout? _bulkThenSolos(
    List<PanelFlyoutEntry> Function(LayerLegendCallbacks legend) bulk,
    List<PanelFlyoutEntry> Function(LayerLegendCallbacks legend) solos,
  ) {
    final legend = this.legend;
    if (legend == null) return null;
    return () {
      final solo = solos(legend);
      return [
        ...bulk(legend),
        if (solo.isNotEmpty) const PanelFlyoutDivider(),
        ...solo,
      ];
    };
  }

  /// The one glyph a column's SOLO row wears.
  static const IconData _soloGlyph = Icons.center_focus_strong_outlined;

  LegendFlyout? get sheet => _bulkThenSolos(
    (legend) => [
      PanelFlyoutItem(
        keyValue: 'legend-sheet-all-on',
        label: AppText.strings.tlAllOnTimesheet,
        shortcuts: const [RailLegendActionIds.sheetAllOn],
        icon: Icons.table_chart,
        onSelected: legend.onSheetAllOn,
      ),
      PanelFlyoutItem(
        keyValue: 'legend-sheet-all-off',
        label: AppText.strings.tlAllOffTimesheet,
        shortcuts: const [RailLegendActionIds.sheetAllOff],
        icon: Icons.table_chart_outlined,
        onSelected: legend.onSheetAllOff,
      ),
    ],
    (legend) => [
      PanelFlyoutItem(
        keyValue: 'legend-filter-sheet',
        label: AppText.strings.tlSoloSheetOnRows,
        shortcuts: const [RailLegendActionIds.soloSheet],
        icon: _soloGlyph,
        checked: rowFilter.onTimesheetOnly,
        onSelected: legend.onToggleSheetOnlyFilter,
      ),
    ],
  );

  LegendFlyout? get mark =>
      _bulkThenSolos((legend) => [_markFilterReset(legend)], _markSolos);

  /// 🚨THE FILTER'S OWN WAY BACK, not the labels' eraser
  /// (clear-all-marks-meaning-Q1, 유저 2026-09-25: 「마크 모두 지우기를 삭제.
  /// 그리고 마크 필터해제 넣고」). The row that stood here wiped every
  /// layer's label; beside the solo list it read as 「undo the solo」, and
  /// pressed that way it erased the project's labels and left the solo in
  /// place.
  PanelFlyoutItem _markFilterReset(LayerLegendCallbacks legend) =>
      PanelFlyoutItem(
        keyValue: 'legend-mark-filter-clear',
        label: AppText.strings.tlClearMarkFilter,
        shortcuts: const [RailLegendActionIds.markFilterClear],
        icon: Icons.filter_alt_off_outlined,
        enabled: rowFilter.markColors.isNotEmpty,
        onSelected: legend.onClearMarkFilter,
      );

  /// The colour solos — 🚨THE MARKS IN USE, not every mark there could be.
  /// A mark is a 공정/수정 pair now, so «every value» is a product of two
  /// lists and most of it would never appear in this project — the filter
  /// was always about what is actually on the rows, and this says so.
  ///
  /// Answering EMPTY when nothing is marked is what drops the divider too —
  /// the old `showRowSolos && marksInUse.isNotEmpty` gate, said once by the
  /// template.
  ///
  /// 🚨AND EVERY MARK THE FILTER HOLDS, in use or not
  /// (mark-filter-held-after-its-mark-is-gone, 유저 2026-09-25: 「레이아웃만
  /// 켜고, 다시 돌리려고 마크 모두 지우기 눌렀는데도 초기화안됨」). Clearing
  /// every label left LO in the filter and gone from this list: every row
  /// but the standing one hidden, and nothing here to uncheck.
  List<PanelFlyoutEntry> _markSolos(LayerLegendCallbacks legend) {
    final listed = {...marksInUse(), ...rowFilter.markColors}
      ..removeWhere((mark) => mark.isNone);
    return listed.isEmpty
        ? const []
        : [
            PanelFlyoutHeader(AppText.strings.tlSoloColor),
            for (final mark
                in listed.toList()
                  ..sort((a, b) => a.sortKey.compareTo(b.sortKey)))
              PanelFlyoutItem(
                keyValue: 'legend-filter-mark-${mark.keySlug}',
                label: layerMarkDisplayName(mark),
                shortcuts: [railSoloMarkActionId(mark)],
                checked: rowFilter.markColors.contains(mark),
                onSelected: () => legend.onToggleMarkFilter(mark),
              ),
          ];
  }

  /// The kind solos (R4 #8) — the panel's [kinds] AND every kind the filter
  /// holds: the filter is every panel's (R5 #9), so a kind held from a
  /// panel that has it stays listed on one that has not, where its solo can
  /// still be undone (mark-filter-held-after-its-mark-is-gone).
  LegendFlyout? get kind {
    final legend = this.legend;
    if (legend == null ||
        kinds.isEmpty && rowFilter.kinds.isEmpty) {
      return null;
    }
    return () {
      final listed = {...kinds, ...rowFilter.kinds};
      return [
        PanelFlyoutHeader(AppText.strings.tlSoloKind),
        for (final kind in LayerKind.values)
          if (listed.contains(kind))
            PanelFlyoutItem(
              keyValue: 'legend-filter-kind-${kind.name}',
              label: layerKindDisplayName(kind),
              shortcuts: [railSoloKindActionId(kind)],
              icon: layerKindIcon(kind),
              checked: rowFilter.kinds.contains(kind),
              onSelected: () => legend.onToggleKindFilter(kind),
            ),
      ];
    };
  }

  LegendFlyout? get fillReference => _bulkThenSolos(
    (legend) => [
      PanelFlyoutItem(
        keyValue: 'legend-fill-ref-clear',
        label: AppText.strings.tlClearAllFillRefs,
        shortcuts: const [RailLegendActionIds.fillReferenceClear],
        icon: Icons.format_color_reset_outlined,
        onSelected: legend.onClearAllFillReferences,
      ),
    ],
    (legend) => [
      PanelFlyoutItem(
        keyValue: 'legend-filter-fill-ref',
        label: AppText.strings.tlSoloFillReferences,
        shortcuts: const [RailLegendActionIds.soloFillReference],
        icon: _soloGlyph,
        checked: rowFilter.fillReferenceOnly,
        onSelected: legend.onToggleFillReferenceOnlyFilter,
      ),
    ],
  );

  LegendFlyout? get fx => _bulkThenSolos(
    (legend) => [
      PanelFlyoutItem(
        keyValue: 'legend-fx-enable-all',
        label: AppText.strings.tlApplyAllFx,
        shortcuts: const [RailLegendActionIds.fxEnableAll],
        onSelected: legend.onEnableAllFx,
      ),
      PanelFlyoutItem(
        keyValue: 'legend-fx-bypass-all',
        label: AppText.strings.tlBypassAllFx,
        shortcuts: const [RailLegendActionIds.fxBypassAll],
        onSelected: legend.onBypassAllFx,
      ),
    ],
    (legend) => [
      PanelFlyoutItem(
        keyValue: 'legend-filter-fx',
        label: AppText.strings.tlSoloFxOnRows,
        shortcuts: const [RailLegendActionIds.soloFx],
        icon: _soloGlyph,
        checked: rowFilter.fxOnly,
        onSelected: legend.onToggleFxOnlyFilter,
      ),
    ],
  );

  /// The onion column's flyout (UI-R17 #5) — only where the host wires the
  /// sweep. The storyboard's does not: the sweep is the open cut's drawing
  /// rows, which its rail does not show, and 「공통으로 안되는건 애초에
  /// 콘티패널에 버튼두지않음」 (I-89-Q22) — its heading stands over its conte
  /// rows' onions, as the x-sheet's does over its own.
  LegendFlyout? get onion {
    final legend = this.legend;
    final toggle = legend?.onToggleOnionSkinForDisplayed;
    if (legend == null || toggle == null) return null;
    return () => [
      PanelFlyoutItem(
        keyValue: 'legend-onion-toggle-displayed',
        // ↩️Written in English here, in every language, until I-40's round
        // on the legend found it (10-09).
        label: displayedOnionSkinOn
            ? AppText.strings.tlClearOnionOnDisplayed
            : AppText.strings.tlApplyOnionToDisplayed,
        shortcuts: const [RailLegendActionIds.onionOnDisplayed],
        icon: Icons.filter_none,
        checked: displayedOnionSkinOn,
        onSelected: toggle,
      ),
      if (legend.onRevealOnionSkinPanel != null)
        PanelFlyoutItem(
          keyValue: 'legend-onion-open-panel',
          label: AppText.strings.tlOpenOnionPanel,
          shortcuts: const [RailLegendActionIds.onionOpenPanel],
          icon: Icons.open_in_new,
          onSelected: legend.onRevealOnionSkinPanel,
        ),
    ];
  }

  LegendFlyout? get visibility {
    final legend = this.legend;
    if (legend == null) return null;
    return () => [
      PanelFlyoutItem(
        keyValue: 'legend-eye-show-all',
        label: AppText.strings.tlShowAll,
        shortcuts: const [RailLegendActionIds.eyeShowAll],
        icon: Icons.visibility,
        onSelected: legend.onShowAllLayers,
      ),
      PanelFlyoutItem(
        keyValue: 'legend-eye-hide-all',
        label: AppText.strings.tlHideAll,
        shortcuts: const [RailLegendActionIds.eyeHideAll],
        icon: Icons.visibility_off,
        onSelected: legend.onHideAllLayers,
      ),
      PanelFlyoutItem(
        keyValue: 'legend-eye-solo',
        // The registry's name: `=` presses this item (I-19).
        label: editorActionLabel(EditorActionIds.layerVisibilitySolo),
        shortcuts: const [EditorActionIds.layerVisibilitySolo],
        icon: _soloGlyph,
        checked: visibilitySoloEnabled,
        onSelected: legend.onToggleVisibilitySolo,
      ),
    ];
  }

  /// R27 #6: the BLEND column's flyout — one pick applies the mode to every
  /// displayed compositing row, the master opacity bar's logic in a list.
  LegendFlyout? get blend {
    final sweep = legend?.onSetBlendModeForDisplayed;
    final displayed = displayedLayerIds;
    if (sweep == null || displayed == null) return null;
    return () => [
      PanelFlyoutHeader(AppText.strings.tlAllDisplayedLayers),
      // The bulk set writes DRAWING rows; pass-through is a group-only
      // answer, so it never appears here.
      for (final mode in railBlendModes)
        PanelFlyoutItem(
          keyValue: 'legend-blend-${mode.name}',
          label: mode.labelFor(AppText.language),
          shortcuts: [railBlendActionId(mode)],
          onSelected: () => sweep(displayed(), mode),
        ),
    ];
  }
}
