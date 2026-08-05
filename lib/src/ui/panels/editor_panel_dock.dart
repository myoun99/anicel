import 'package:flutter/material.dart';

import 'panel_scrollbar.dart';

/// Which screen edge the dock is attached to; the hairline border sits on
/// the edge facing the canvas.
enum EditorPanelDockSide { left, right }

class EditorPanelDock extends StatefulWidget {
  /// A dock stacking [children] vertically in a scrollable list.
  const EditorPanelDock({
    super.key,
    required List<Widget> this.children,
    this.width = 260,
    this.side = EditorPanelDockSide.right,
  }) : child = null,
       dockId = null;

  /// A dock filled by a single [child] (e.g. a tab shell) flush against the
  /// dock edges — no padding, no scroll list. Unlike the list variant the
  /// width is taken as-is (slim edge docks go below the palette minimum).
  const EditorPanelDock.filled({
    super.key,
    required Widget this.child,
    this.width = 260,
    this.side = EditorPanelDockSide.right,
    this.dockId,
  }) : children = null;

  final List<Widget>? children;
  final Widget? child;
  final double width;
  final EditorPanelDockSide side;

  /// Distinguishes the dock's test key when several docks share a side
  /// (e.g. the slim tool edge dock next to the left palette dock).
  final String? dockId;

  @override
  State<EditorPanelDock> createState() => _EditorPanelDockState();
}

class _EditorPanelDockState extends State<EditorPanelDock> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLeft = widget.side == EditorPanelDockSide.left;
    final borderSide = BorderSide(color: colorScheme.outlineVariant);
    final children = widget.children;
    return Container(
      key: ValueKey<String>(
        'editor-panel-dock-${widget.dockId ?? (isLeft ? 'left' : 'right')}',
      ),
      width: widget.width,
      constraints: children == null
          ? null
          : const BoxConstraints(minWidth: 180),
      padding: children == null
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(8, 8, 0, 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          left: isLeft ? BorderSide.none : borderSide,
          right: isLeft ? borderSide : BorderSide.none,
        ),
      ),
      child: children == null
          ? widget.child!
          : PanelScrollbar(
              controller: _scrollController,
              child: ListView.separated(
                controller: _scrollController,
                itemCount: children.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) => children[index],
              ),
            ),
    );
  }
}
