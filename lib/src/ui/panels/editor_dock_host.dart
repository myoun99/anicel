import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../layout/device_grid.dart';
import '../theme/app_theme.dart' show AppColors;
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
    this.collapsed = false,
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

  /// Whether this dock's region is folded down — see [PanelCollapsedScope].
  final bool collapsed;

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
      // The sill's own controls stand down while anything is in flight, so
      // the strip goes back to being landing area.
      draggingTab: draggingTab,
      collapsed: collapsed,
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
  });

  /// ⛔No `keyId` any more. It existed so a SIDE RAIL's zone could name the
  /// rail rather than whichever of its group slots happened to be free, and
  /// side rails no longer draw a zone at all (유저, R4 #7) — the two that
  /// still do, the bottom dock and an emptied floor, are their own dock and
  /// have nothing to rename.
  final String dockId;

  final Axis axis;
  final ValueListenable<EditorPanelTabDragData?> draggingTab;
  final bool Function(EditorPanelTabDragData data) canAcceptTab;
  final ValueChanged<EditorPanelTabDragData> onDropped;
  final bool expandToFill;

  static const double thickness = 26;

  /// The gap between the band and the dock's edge, on all four sides.
  static const double margin = 2;

  /// What the zone occupies in the layout — the band plus both margins.
  /// This is what shifts the canvas, so this is what has to be on the
  /// device grid.
  static double footprintOf(BuildContext context) =>
      DeviceGrid.of(context).position(thickness + margin * 2);

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
            // 🚨This zone exists ONLY while a tab is in the air, and its
            // whole footprint shifts everything beside it — including the
            // canvas. So the x the canvas starts at is 0 / this / 48
            // depending on app state, and it changes on the tab-lift
            // frame, which is itself a layout-change frame. 30 × 1.25 =
            // 37.5: half a device pixel, on exactly the frame that hops.
            //
            // The FOOTPRINT is what the chain needs on the grid, and the
            // band absorbs the residue — which is the run rule working:
            // the total is quantized once and the last extent takes what
            // is left. Measured footprint at 1.125 / 1.25 / 1.35 / 1.75:
            // 33 / 37 / 40 / 52 device px, integral at all four.
            //
            // ⚠️The band's OWN edges stay off the grid, because leaf
            // crispness is a later PR's job. ⛔That is not "two runs over
            // one boundary" — an earlier draft of this comment said so
            // and was wrong: the margin/band split is nested inside the
            // footprint and shares no boundary with the outer chain, so
            // a run taking [2, 26, 2] would be the documented composing
            // pattern, not the forbidden one.
            final band = footprintOf(context) - margin * 2;
            return Container(
              key: ValueKey<String>('editor-dock-drop-rail-$dockId'),
              width: expandToFill
                  ? null
                  : (axis == Axis.vertical ? band : null),
              height: expandToFill
                  ? null
                  : (axis == Axis.horizontal ? band : null),
              margin: const EdgeInsets.all(margin),
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
                  // 「＋가 있는 모든 곳, 공통적으로」. This one only exists
                  // while a tab is in the air, so it is never disabled —
                  // hovering deepens the rail behind it, not the glyph.
                  color: AppColors.addGlyph(enabled: true),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
