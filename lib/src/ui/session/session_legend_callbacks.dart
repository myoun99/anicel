import 'package:flutter/foundation.dart';

import '../../models/layer_mark.dart';
import '../editor_session_manager.dart';
import '../timeline/timeline_legend_menus.dart'
    show LayerLegendCallbacks;
import '../timeline/timeline_row_filter.dart';

/// The legend's verbs wired to [session] and to the host's row filter —
/// the one wiring behind the timeline rail's legend and the storyboard's
/// (the audit's clone scan, 2026-09-03). Both rails carry every column now,
/// so every bulk verb is the session's; the onion panel's door is the
/// host's to open ([onRevealOnionSkinPanel]). ↩️A host named the onion's
/// and the blend's verbs or left them null: the onion was the timeline's
/// alone until F-443 (유저 2026-10-23: 「레전드행에도 버튼있는거 감수」), the
/// blend both rails' since the conte row's head took that column (I-73,
/// 2026-10-08).
LayerLegendCallbacks sessionLegendCallbacks(
  EditorSessionManager session, {
  required TimelineRowFilter rowFilter,
  required ValueChanged<TimelineRowFilter>? onSetRowFilter,
  VoidCallback? onRevealOnionSkinPanel,
}) => LayerLegendCallbacks(
  onShowAllLayers: () => session.layerSwitches.setAllLayersVisibility(true),
  onHideAllLayers: () => session.layerSwitches.setAllLayersVisibility(false),
  onToggleVisibilitySolo: session.visibilitySolo.toggleLayerVisibilitySolo,
  onToggleOnionSkinForDisplayed:
      session.onionSkin.toggleOnionSkinForDisplayedLayers,
  onRevealOnionSkinPanel: onRevealOnionSkinPanel,
  onSheetAllOn: () => session.layerSwitches.setAllLayersOnTimesheet(true),
  onSheetAllOff: () => session.layerSwitches.setAllLayersOnTimesheet(false),
  onClearMarkFilter: () => onSetRowFilter?.call(
    rowFilter.copyWith(markColors: const <LayerMark>{}),
  ),
  onClearAllFillReferences: session.layerSwitches.clearAllFillReferences,
  onBypassAllFx: () => session.effectsAndFx.setAllLayersFxBypassed(true),
  onEnableAllFx: () => session.effectsAndFx.setAllLayersFxBypassed(false),
  onToggleMarkFilter: (mark) =>
      onSetRowFilter?.call(rowFilter.toggledMark(mark)),
  onToggleKindFilter: (kind) =>
      onSetRowFilter?.call(rowFilter.toggledKind(kind)),
  onToggleSheetOnlyFilter: () => onSetRowFilter?.call(
    rowFilter.copyWith(onTimesheetOnly: !rowFilter.onTimesheetOnly),
  ),
  onToggleFxOnlyFilter: () =>
      onSetRowFilter?.call(rowFilter.copyWith(fxOnly: !rowFilter.fxOnly)),
  onToggleFillReferenceOnlyFilter: () => onSetRowFilter?.call(
    rowFilter.copyWith(fillReferenceOnly: !rowFilter.fillReferenceOnly),
  ),
  onPreviewLayersOpacity: session.opacityVerbs.previewLayersOpacity,
  onCommitLayersOpacity: session.opacityVerbs.commitLayersOpacity,
  onSetBlendModeForDisplayed: session.layerSwitches.setBlendModeForLayers,
);
