import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/dock_edge_splitter.dart';
import 'editor_panel_layout.dart';
import 'editor_panel_tabs.dart';
import 'panel_flash.dart';

export '../widgets/dock_edge_splitter.dart' show DockEdgeSplitter;

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

  @override
  Widget build(BuildContext context) {
    final sections = layout.sectionsIn(dockId);
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalExtent = constraints.maxHeight;
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
              Expanded(
                flex: (sections[i].weight * 1000).round(),
                child: _SectionDropOverlay(
                  dockId: dockId,
                  sectionIndex: i,
                  tabCount: sections[i].tabs.length,
                  draggingTab: draggingTab,
                  canAcceptTab: canAcceptTab,
                  onTabMovedToSection: onTabMovedToSection,
                  onTabMovedToNewSection: onTabMovedToNewSection,
                  child: EditorPanelTabs(
                    groupId: dockId,
                    compact: compact,
                    tabs: [for (final id in sections[i].tabs) tabResolver(id)],
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
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Which drop region of a section the pointer is over.
enum _DropRegion { above, join, below }

/// Floats the drop zones over a section while an eligible tab is in
/// flight: a faint outline hints the section takes drops; hovering lights
/// the target region up brightly (PS/AE style).
class _SectionDropOverlay extends StatelessWidget {
  const _SectionDropOverlay({
    required this.dockId,
    required this.sectionIndex,
    required this.tabCount,
    required this.draggingTab,
    required this.canAcceptTab,
    required this.onTabMovedToSection,
    required this.onTabMovedToNewSection,
    required this.child,
  });

  final String dockId;
  final int sectionIndex;
  final int tabCount;
  final ValueListenable<EditorPanelTabDragData?> draggingTab;
  final bool Function(EditorPanelTabDragData data) canAcceptTab;
  final void Function(
    EditorPanelTabDragData data,
    int sectionIndex,
    int insertIndex,
  )
  onTabMovedToSection;
  final void Function(EditorPanelTabDragData data, int atSectionIndex)
  onTabMovedToNewSection;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<EditorPanelTabDragData?>(
      valueListenable: draggingTab,
      builder: (context, dragging, _) {
        final eligible = dragging != null && canAcceptTab(dragging);
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (eligible)
              // The strip keeps its own precise per-tab targets; the
              // overlay covers only the content region below it.
              Positioned(
                left: 0,
                right: 0,
                top: EditorPanelTabs.stripHeight,
                bottom: 0,
                child: _DropBands(
                  dockId: dockId,
                  sectionIndex: sectionIndex,
                  onDropped: (data, region) => switch (region) {
                    _DropRegion.above => onTabMovedToNewSection(
                      data,
                      sectionIndex,
                    ),
                    _DropRegion.join => onTabMovedToSection(
                      data,
                      sectionIndex,
                      tabCount,
                    ),
                    _DropRegion.below => onTabMovedToNewSection(
                      data,
                      sectionIndex + 1,
                    ),
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DropBands extends StatefulWidget {
  const _DropBands({
    required this.dockId,
    required this.sectionIndex,
    required this.onDropped,
  });

  final String dockId;
  final int sectionIndex;
  final void Function(EditorPanelTabDragData data, _DropRegion region)
  onDropped;

  @override
  State<_DropBands> createState() => _DropBandsState();
}

class _DropBandsState extends State<_DropBands> {
  _DropRegion? _hovered;

  void _setHovered(_DropRegion? region) {
    if (region != _hovered) {
      setState(() => _hovered = region);
    }
  }

  Widget _band(_DropRegion region, String keySuffix) {
    return DragTarget<EditorPanelTabDragData>(
      onWillAcceptWithDetails: (details) {
        _setHovered(region);
        return true;
      },
      onLeave: (_) => _setHovered(null),
      onAcceptWithDetails: (details) {
        _setHovered(null);
        widget.onDropped(details.data, region);
      },
      builder: (context, candidateData, rejectedData) => SizedBox.expand(
        key: ValueKey<String>(
          'dock-drop-$keySuffix-${widget.dockId}-${widget.sectionIndex}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Faint hint: this section accepts the tab in flight.
        IgnorePointer(
          child: Container(
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.05),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.45),
              ),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        // The bright region preview under the pointer.
        if (_hovered != null)
          Align(
            alignment: _hovered == _DropRegion.below
                ? Alignment.bottomCenter
                : Alignment.topCenter,
            child: FractionallySizedBox(
              heightFactor: _hovered == _DropRegion.join ? 1 : 0.5,
              widthFactor: 1,
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.25),
                    border: Border.all(color: colorScheme.primary, width: 1.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        Column(
          children: [
            Expanded(child: _band(_DropRegion.above, 'above')),
            Expanded(flex: 2, child: _band(_DropRegion.join, 'join')),
            Expanded(child: _band(_DropRegion.below, 'below')),
          ],
        ),
      ],
    );
  }
}

/// A collapsed (empty) dock: invisible until an ELIGIBLE tab is in flight,
/// then a slim glowing rail appears; dropping a tab there re-populates the
/// dock. With [expandToFill] the dock keeps its region instead (the center
/// dock must not collapse the whole workspace middle) and the drop surface
/// covers it all.
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

  final String dockId;
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
              key: ValueKey<String>('editor-dock-drop-rail-$dockId'),
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
