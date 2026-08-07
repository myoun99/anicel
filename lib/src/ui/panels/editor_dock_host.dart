import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/dock_edge_splitter.dart';
import 'editor_panel_layout.dart';
import 'editor_panel_tabs.dart';
import 'panel_flash.dart';

export '../widgets/dock_edge_splitter.dart' show DockEdgeSplitter;

/// What one section costs before its panels start losing rows: its tab
/// strip plus the tallest floor among the tabs it hosts.
///
/// The tallest among ALL of them, not the active one — a section that
/// shrinks while the conte is up and clips the moment you switch back to
/// the timeline is the same bug wearing a different hat.
double dockSectionFloorExtent(Iterable<EditorPanelTab> tabs) {
  var floor = 0.0;
  for (final tab in tabs) {
    floor = math.max(floor, tab.minContentHeight ?? 0);
  }
  return EditorPanelTabs.stripHeight + floor;
}

/// How a dock's stacking axis is divided between its sections.
///
/// Sections used to be plain `Expanded(flex: weight)`, which is
/// proportional and knows nothing about what a section NEEDS. That is only
/// correct while the weights happen to be proportional to the floors, and
/// they never are: a new section always arrives at weight 1
/// ([EditorPanelLayoutModel.moveTabToNewSection]) whatever it holds. One
/// tab drag was enough to starve the timeline back into the tab shell's
/// scroller and cut its bottom rows off — the report this whole round
/// exists to close, reached through the other door.
///
/// So: every section gets its floor first, and only the SURPLUS is shared
/// by weight. The splitter still moves size between neighbours; it just
/// cannot move a panel below what it needs. When the dock cannot pay even
/// the floors, they are scaled down together rather than starving whoever
/// happens to be last — and the shell's scroller is back to being the
/// guard for exactly that case.
List<double> dockSectionExtents({
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
  // [gap] is what sits BETWEEN two of these — a splitter inside a dock, and
  // nothing at all between the groups stacked on a rail, whose one splitter
  // is the rail's own inner edge.
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

/// Renders one dock of an [EditorPanelLayoutModel]: its sections stacked
/// vertically (panel below panel) with draggable splitters between them,
/// plus the Photoshop/AE-style drop feedback while a tab is in flight —
/// each eligible section shows a faint zone hint, and hovering lights up
/// the exact REGION the panel would occupy (top/bottom half = stack a new
/// section there, middle = join the section as a tab). The overlays float
/// above the content, so nothing shifts during a drag.
class EditorDockHost extends StatelessWidget {
  const EditorDockHost({
    super.key,
    required this.layout,
    required this.dockId,
    required this.tabResolver,
    required this.draggingTab,
    required this.canAcceptTab,
    required this.onTabSelected,
    required this.onTabMovedToSection,
    required this.onTabMovedToNewSection,
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
  final void Function(int sectionIndex, String tabId) onTabSelected;
  final void Function(
    EditorPanelTabDragData data,
    int sectionIndex,
    int insertIndex,
  )
  onTabMovedToSection;
  final void Function(EditorPanelTabDragData data, int atSectionIndex)
  onTabMovedToNewSection;
  final ValueChanged<EditorPanelTabDragData?> onTabDragChanged;
  final ValueChanged<String>? onToggleLock;
  final ValueChanged<String>? onCloseTab;

  /// The workspace's reveal-flash channel (UI-R17 #5), threaded to every
  /// section's panel shell.
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
    final sections = layout.sectionsIn(dockId);
    final resolved = [
      for (final section in sections)
        [for (final id in section.tabs) tabResolver(id)],
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalExtent = constraints.maxHeight;
        // Unbounded hosts cannot be given pixel heights; they keep the
        // proportional layout, which is what they always had.
        final extents = constraints.hasBoundedHeight
            ? dockSectionExtents(
                weights: [for (final section in sections) section.weight],
                floors: [
                  for (final tabs in resolved) dockSectionFloorExtent(tabs),
                ],
                totalExtent: totalExtent,
              )
            : null;
        // NO DROP OVERLAY. Dropping a panel above or below another one used
        // to split a dock into stacked sections — the free-form dock tree
        // this app is leaving behind. A panel goes where its BUTTON is now:
        // onto a rail button to join that group, onto a rail's empty space
        // to make one, onto the floating region's sill to join it. Those
        // three are the whole vocabulary, and none of them is a band drawn
        // over a panel's body.
        Widget section(int i) => Builder(
          builder: (context) => EditorPanelTabs(
            groupId: dockId,
            compact: compact,
            chromeless: chromeless,
            stripAtBottom: stripAtBottom,
            // The region's own controls belong to the LAST section, where
            // the strip that carries them is the one against the window
            // frame — the same edge the threshold is on.
            trailing: i == sections.length - 1 ? trailing : null,
            tabs: resolved[i],
            activeTabId: sections[i].activeTabId,
            onTabSelected: (tabId) => onTabSelected(i, tabId),
            canAcceptTab: canAcceptTab,
            onTabMoved: (data, insertIndex) =>
                onTabMovedToSection(data, i, insertIndex),
            onTabDragChanged: onTabDragChanged,
            onToggleLock: onToggleLock,
            onCloseTab: onCloseTab,
            flash: flash,
          ),
        );
        return Column(
          children: [
            for (var i = 0; i < sections.length; i += 1) ...[
              if (i > 0)
                // The section divider and the dock's edge grip were the
                // same widget twice; the shared splitter is the survivor.
                DockEdgeSplitter(
                  key: ValueKey<String>('dock-splitter-$dockId-$i'),
                  axis: Axis.horizontal,
                  onDragDelta: (delta) => layout.resizeSections(
                    dockId,
                    i - 1,
                    delta: delta,
                    totalExtent: totalExtent,
                  ),
                ),
              if (extents == null)
                Expanded(
                  flex: (sections[i].weight * 1000).round(),
                  child: section(i),
                )
              else
                SizedBox(height: extents[i], child: section(i)),
            ],
          ],
        );
      },
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
