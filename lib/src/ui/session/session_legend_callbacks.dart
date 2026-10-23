import 'package:flutter/foundation.dart';

import '../../models/layer_blend_mode.dart';
import '../../models/layer_id.dart';
import '../../models/layer_mark.dart';
import '../editor_session_manager.dart';
import '../timeline/timeline_legend_menus.dart'
    show LayerLegendCallbacks;
import '../timeline/timeline_row_filter.dart';

/// The legend's verbs wired to [session] and to the host's row filter —
/// the one wiring behind the timeline rail's legend and the storyboard's
/// (the audit's clone scan, 2026-09-03). A host names the verbs of the
/// columns its rail has and leaves the rest null: the onion-skin's are the
/// timeline's alone; the blend's is both rails' since the storyboard's took
/// that column with the conte row's head (I-73, 2026-10-08).
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
