import 'package:flutter/material.dart';

import '../../models/layer_kind.dart';
import '../widgets/panel_flyout.dart';
import 'timeline_section_policy.dart';
import '../text/app_strings.dart';

/// The section flyout's commands (host-wired; null leaves the section tags
/// display-only).
class TimelineSectionRailCallbacks {
  const TimelineSectionRailCallbacks({
    required this.onToggleSection,
    required this.onAddLayerOfKind,
    required this.onSetSectionLayersVisibility,
    required this.onSoloSection,
  });

  /// Folds/unfolds a hideable section (the shared hiddenSections state).
  final ValueChanged<TimelineSection> onToggleSection;

  /// Adds a layer of the section's home kind.
  final ValueChanged<LayerKind> onAddLayerOfKind;

  /// Shows/hides every layer belonging to the section.
  final void Function(TimelineSection section, bool visible)
  onSetSectionLayersVisibility;

  /// Folds every OTHER hideable section.
  final ValueChanged<TimelineSection> onSoloSection;
}

/// The kind the section's AppText.strings.tlAddLayerHere creates.
LayerKind timelineSectionHomeKind(TimelineSection section) {
  return switch (section) {
    TimelineSection.drawing => LayerKind.animation,
    TimelineSection.se => LayerKind.se,
    // The camera itself is one-per-cut; the section's addable rows are
    // instructions.
    TimelineSection.camera => LayerKind.instruction,
  };
}

/// The section flyout (fold / add layer here / solo / section-wide eye),
/// anchored from the row's INLINE section tag since UI-R5 (the bracket
/// gutter is retired — sections live inside the rows, user rule).
List<PanelFlyoutEntry> timelineSectionFlyoutEntries(
  TimelineSection section,
  TimelineSectionRailCallbacks callbacks,
) {
  final name = section.name;
  return [
    PanelFlyoutHeader(timelineSectionLabel(section)),
    if (timelineSectionHideable(section))
      PanelFlyoutItem(
        keyValue: 'section-flyout-fold-$name',
        label: AppText.strings.tlFoldSection,
        icon: Icons.unfold_less,
        onSelected: () => callbacks.onToggleSection(section),
      ),
    PanelFlyoutItem(
      keyValue: 'section-flyout-add-$name',
      label: AppText.strings.tlAddLayerHere,
      icon: Icons.add,
      onSelected: () =>
          callbacks.onAddLayerOfKind(timelineSectionHomeKind(section)),
    ),
    PanelFlyoutItem(
      keyValue: 'section-flyout-solo-$name',
      label: AppText.strings.tlOnlyThisSection,
      icon: Icons.filter_center_focus,
      onSelected: () => callbacks.onSoloSection(section),
    ),
    const PanelFlyoutDivider(),
    PanelFlyoutItem(
      keyValue: 'section-flyout-show-$name',
      label: AppText.strings.tlShowSectionLayers,
      icon: Icons.visibility,
      onSelected: () => callbacks.onSetSectionLayersVisibility(section, true),
    ),
    PanelFlyoutItem(
      keyValue: 'section-flyout-hide-$name',
      label: AppText.strings.tlHideSectionLayers,
      icon: Icons.visibility_off,
      onSelected: () => callbacks.onSetSectionLayersVisibility(section, false),
    ),
  ];
}
