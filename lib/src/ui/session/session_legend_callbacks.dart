import 'package:flutter/foundation.dart';

import '../../models/layer_blend_mode.dart';
import '../../models/layer_id.dart';
import '../../models/layer_mark.dart';
import '../editor_session_manager.dart';
import '../timeline/timeline_layer_controls_header.dart'
    show LayerLegendCallbacks;
import '../timeline/timeline_row_filter.dart';

/// The legend's verbs wired to [session] and to the host's row filter —
/// the one wiring behind the timeline rail's legend and the storyboard's
/// (the audit's clone scan, 2026-09-03). The onion-skin and blend verbs are
/// the timeline's alone: its rail has those columns, the storyboard's does
/// not, so each host names them or leaves them null.
LayerLegendCallbacks sessionLegendCallbacks(
  EditorSessionManager session, {
  required TimelineRowFilter rowFilter,
  required ValueChanged<TimelineRowFilter>? onSetRowFilter,
  VoidCallback? onToggleOnionSkinForDisplayed,
  VoidCallback? onRevealOnionSkinPanel,
  void Function(Set<LayerId> layerIds, LayerBlendMode mode)?
  onSetBlendModeForDisplayed,
}) => LayerLegendCallbacks(
  onShowAllLayers: () => session.layerSwitches.setAllLayersVisibility(true),
  onHideAllLayers: () => session.layerSwitches.setAllLayersVisibility(false),
  onToggleVisibilitySolo: session.visibilitySolo.toggleLayerVisibilitySolo,
  onToggleOnionSkinForDisplayed: onToggleOnionSkinForDisplayed,
  onRevealOnionSkinPanel: onRevealOnionSkinPanel,
  onSheetAllOn: () => session.layerSwitches.setAllLayersOnTimesheet(true),
  onSheetAllOff: () => session.layerSwitches.setAllLayersOnTimesheet(false),
  onClearMarkFilter: () => onSetRowFilter?.call(
    rowFilter.copyWith(markColors: const <LayerMark>{}),
  ),
  onClearAllFillReferences: session.layerSwitches.clearAllFillReferences,
  onMuteAllSe: () => session.layerSwitches.setAllSeLayersMuted(true),
  onUnmuteAllSe: () => session.layerSwitches.setAllSeLayersMuted(false),
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
  onSetBlendModeForDisplayed: onSetBlendModeForDisplayed,
);
