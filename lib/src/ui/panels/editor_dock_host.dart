import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/dock_edge_splitter.dart';
import 'editor_panel_layout.dart';
import 'editor_panel_tabs.dart';
import 'panel_flash.dart';

export '../widgets/dock_edge_splitter.dart' show DockEdgeSplitter;

/// What one panel group costs before its panels start losing rows: its tab
/// strip plus the tallest floor among the tabs it hosts.
///
/// The tallest among ALL of them, not the active one — a group that
/// shrinks while the conte is up and clips the moment you switch back to
/// the timeline is the same bug wearing a different hat.
double panelGroupFloorExtent(Iterable<EditorPanelTab> tabs) {
  var floor = 0.0;
  for (final tab in tabs) {
    floor = math.max(floor, tab.minContentHeight ?? 0);
  }
  return EditorPanelTabs.stripHeight + floor;
}

/// How a stacking axis is divided between the panel groups on it.
///
/// The share used to be plain `Expanded(flex: weight)`, which is
/// proportional and knows nothing about what a group NEEDS. That is only
/// correct while the weights happen to be proportional to the floors, and
/// they never are.
///
/// So: every group gets its floor first, and only the SURPLUS is shared by
/// weight. When the stack cannot pay even the floors, they are scaled down
/// together rather than starving whoever happens to be last — and the
/// shell's scroller is back to being the guard for exactly that case.
List<double> stackedGroupExtents({
  required List<double> weights,
  required List<double> floors,
  required double totalExtent,
  double gap = DockEdgeSplitter.thickness,
}) {
  final count = weights.length;
  assert(floors.length == count);
  if (count == 0) {
    return const [];
  }
  // [gap] is what sits BETWEEN two of these — the pasteboard a rail leaves
  // between two floating groups.
  final flexSpace = math.max(0.0, totalExtent - (count - 1) * gap);
  var floorSum = 0.0;
  for (final floor in floors) {
    floorSum += floor;
  }
  if (floorSum >= flexSpace) {
    return [
      for (final floor in floors)
        floorSum > 0 ? flexSpace * floor / floorSum : flexSpace / count,
    ];
  }
  // Water-filling: pin whoever their weighted share would starve, then
  // re-share what is left among the rest. One pin per pass, because
  // pinning changes the divisor for everyone else.
  final extents = List<double>.filled(count, 0);
  final pinned = List<bool>.filled(count, false);
  var remaining = flexSpace;
  while (true) {
    var freeWeight = 0.0;
    var freeCount = 0;
    for (var i = 0; i < count; i += 1) {
      if (pinned[i]) {
        continue;
      }
      freeWeight += weights[i];
      freeCount += 1;
    }
    if (freeCount == 0) {
      break;
    }
    var starved = -1;
    for (var i = 0; i < count; i += 1) {
      if (pinned[i]) {
        continue;
      }
      final share = freeWeight > 0
          ? remaining * weights[i] / freeWeight
          : remaining / freeCount;
      if (share < floors[i]) {
        starved = i;
        break;
      }
    }
    if (starved < 0) {
      for (var i = 0; i < count; i += 1) {
        if (pinned[i]) {
          continue;
        }
        extents[i] = freeWeight > 0
            ? remaining * weights[i] / freeWeight
            : remaining / freeCount;
      }
      break;
    }
    pinned[starved] = true;
    extents[starved] = floors[starved];
    remaining -= floors[starved];
  }
  return extents;
}

/// Renders one dock of an [EditorPanelLayoutModel]: ONE tab group, and
/// nothing else.
///
/// It used to render a STACK of groups with draggable splitters between
/// them, and Photoshop/AE-style drop bands that made more of them. The
/// bands went first; this is the rest of the same removal. A dock is what
/// one rail button opens, and one button opens one panel group — a dock
/// that could be cut in half was the old free-form dock tree still
/// standing behind the new vocabulary, quietly rebuilding itself out of
/// any workspace file that remembered one.
class EditorDockHost extends StatelessWidget {
  const EditorDockHost({
    super.key,
    required this.layout,
    required this.dockId,
    required this.tabResolver,
    required this.draggingTab,
    required this.canAcceptTab,
    required this.onTabSelected,
    required this.onTabMoved,
    required this.onTabDragChanged,
    this.onToggleLock,
    this.onCloseTab,
    this.flash,
    this.compact = false,
    this.chromeless = false,
    this.stripAtBottom = false,
    this.trailing,
  });

  final EditorPanelLayoutModel layout;
  final String dockId;
  final EditorPanelTab Function(String tabId) tabResolver;

  /// The tab currently in flight anywhere in the workspace (null = none).
  final ValueListenable<EditorPanelTabDragData?> draggingTab;

  final bool Function(EditorPanelTabDragData data) canAcceptTab;
  final ValueChanged<String> onTabSelected;
  final void Function(EditorPanelTabDragData data, int insertIndex) onTabMoved;
  final ValueChanged<EditorPanelTabDragData?> onTabDragChanged;
  final ValueChanged<String>? onToggleLock;
  final ValueChanged<String>? onCloseTab;

  /// The workspace's reveal-flash channel (UI-R17 #5), threaded to the
  /// panel shell.
  final PanelFlashController? flash;
  final bool compact;

  /// Drops the tab strip entirely — see [EditorPanelTabs.chromeless]. Used
  /// by the fixed tool strip, which holds one panel forever.
  final bool chromeless;

  /// Moves the strip to the panel's bottom inner edge (the 문턱 of a
  /// floating region) — see [EditorPanelTabs.stripAtBottom].
  final bool stripAtBottom;

  /// Controls belonging to the REGION rather than to a tab (collapse), put
  /// at the far end of the strip against the window frame.
  final List<Widget>? trailing;

  @override
  Widget build(BuildContext context) {
    final tabIds = layout.tabsIn(dockId);
    final activeTabId = layout.activeTabIn(dockId);
    if (tabIds.isEmpty || activeTabId == null) {
      return const SizedBox.shrink();
    }
    // NO DROP OVERLAY, and no stack to drop into. A panel goes where its
    // BUTTON is: onto a rail button to join that group, onto a rail's empty
    // space to make one, onto the floating region's sill to join it. Those
    // three are the whole vocabulary.
    return EditorPanelTabs(
      groupId: dockId,
      compact: compact,
      chromeless: chromeless,
      stripAtBottom: stripAtBottom,
      trailing: trailing,
      tabs: [for (final id in tabIds) tabResolver(id)],
      activeTabId: activeTabId,
      onTabSelected: onTabSelected,
      canAcceptTab: canAcceptTab,
      onTabMoved: onTabMoved,
      onTabDragChanged: onTabDragChanged,
      onToggleLock: onToggleLock,
      onCloseTab: onCloseTab,
      flash: flash,
    );
  }
}

class EditorDockDropZone extends StatelessWidget {
  const EditorDockDropZone({
    super.key,
    required this.dockId,
    required this.axis,
    required this.draggingTab,
    required this.canAcceptTab,
    required this.onDropped,
    this.expandToFill = false,
    this.keyId,
  });

  final String dockId;

  /// Names the rail in the test key when the dock it drops INTO is an
  /// implementation detail — a rail's empty zone targets whichever of its
  /// group slots happens to be free, but it is still "the left rail" to
  /// everyone looking at it.
  final String? keyId;
  final Axis axis;
  final ValueListenable<EditorPanelTabDragData?> draggingTab;
  final bool Function(EditorPanelTabDragData data) canAcceptTab;
  final ValueChanged<EditorPanelTabDragData> onDropped;
  final bool expandToFill;

  static const double thickness = 26;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<EditorPanelTabDragData?>(
      valueListenable: draggingTab,
      builder: (context, dragging, _) {
        final eligible = dragging != null && canAcceptTab(dragging);
        if (!eligible) {
          return expandToFill
              ? ColoredBox(color: colorScheme.surfaceContainerLowest)
              : const SizedBox.shrink();
        }
        return DragTarget<EditorPanelTabDragData>(
          onAcceptWithDetails: (details) => onDropped(details.data),
          builder: (context, candidateData, rejectedData) {
            final hovered = candidateData.isNotEmpty;
            return Container(
              key: ValueKey<String>(
                'editor-dock-drop-rail-${keyId ?? dockId}',
              ),
              width: expandToFill
                  ? null
                  : (axis == Axis.vertical ? thickness : null),
              height: expandToFill
                  ? null
                  : (axis == Axis.horizontal ? thickness : null),
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: hovered
                    ? colorScheme.primary.withValues(alpha: 0.25)
                    : colorScheme.primary.withValues(alpha: 0.06),
                border: Border.all(
                  color: hovered
                      ? colorScheme.primary
                      : colorScheme.primary.withValues(alpha: 0.45),
                  width: hovered ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Icon(
                  Icons.add,
                  size: 14,
                  color: hovered
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
