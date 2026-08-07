import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
