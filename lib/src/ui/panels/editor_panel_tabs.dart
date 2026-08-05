import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'panel_flash.dart';
import 'panel_visibility_scope.dart';

/// One tab in an [EditorPanelTabs] group.
class EditorPanelTab {
  const EditorPanelTab({
    required this.id,
    required this.label,
    required this.icon,
    required this.builder,
    this.buttonKey,
    this.minContentWidth,
    this.minContentHeight,
    this.locked = false,
    this.keepAlive = false,
  });

  /// Stable identifier the group reports through `onTabSelected`.
  final String id;

  final String label;
  final IconData icon;

  /// Builds the tab's content; only the ACTIVE tab is built (panel state
  /// that must survive switches lives above the tab group) — unless
  /// [keepAlive] retains it offstage after its first activation.
  final WidgetBuilder builder;

  /// Once built, keep this tab's subtree mounted OFFSTAGE while another
  /// tab is active (R10-②): heavy panels (timeline, storyboard,
  /// timesheet, canvas) then switch back instantly instead of rebuilding
  /// from scratch. Offstage subtrees still rebuild on their listenables —
  /// keep this off for cheap panels.
  final bool keepAlive;

  /// Key for the tab strip button. Groups replacing older toggle buttons
  /// keep the legacy keys here so existing flows and tests keep working.
  final Key? buttonKey;

  /// Smallest size this panel lays out at. When the tab is docked somewhere
  /// smaller (frame-axis panels in a side dock), the shell hosts it at this
  /// size inside scrollers instead of letting its fixed rails and toolbars
  /// overflow.
  final double? minContentWidth;
  final double? minContentHeight;

  /// Drag-locked tabs stay put (the canvas panel defaults to locked so a
  /// stray drag can't undock the drawing surface).
  final bool locked;
}

/// A tab in flight between (or within) tab groups.
class EditorPanelTabDragData {
  const EditorPanelTabDragData({
    required this.tabId,
    required this.fromGroupId,
  });

  final String tabId;
  final String fromGroupId;
}

/// The CSP-style tabbed panel shell: a compact tab strip on top, the active
/// tab's content below. Selection is CONTROLLED by the owner (so it can
/// persist per-view state across switches). Rule of thumb: the strip only
/// switches — tools/buttons belong to each panel's own toolbar below it.
///
/// When [groupId] and [onTabMoved] are given, tabs become draggable (drag
/// starts immediately on pointer movement; a plain tap still just
/// switches): within the strip to reorder, and onto another group's strip
/// to re-dock. Drop position follows the pointer (left/right half of a
/// hovered tab inserts before/after it; the empty strip tail appends).
/// LOCKED tabs ([EditorPanelTab.locked]) refuse to lift; [onToggleLock]
/// puts a lock toggle for the active tab at the strip's end.
class EditorPanelTabs extends StatefulWidget {
  const EditorPanelTabs({
    super.key,
    required this.tabs,
    required this.activeTabId,
    required this.onTabSelected,
    this.compact = false,
    this.chromeless = false,
    this.groupId,
    this.onTabMoved,
    this.canAcceptTab,
    this.onTabDragChanged,
    this.onToggleLock,
    this.onCloseTab,
    this.flash,
  }) : assert(tabs.length > 0),
       assert(
         onTabMoved == null || groupId != null,
         'Draggable tab groups need a groupId',
       );

  final List<EditorPanelTab> tabs;
  final String activeTabId;
  final ValueChanged<String> onTabSelected;

  /// Icon-only tab buttons (the label moves into the tooltip) — for narrow
  /// docks where full labels would overflow the strip.
  final bool compact;

  /// Renders the CONTENT with no tab strip at all — no names, no glyphs,
  /// no grip, nothing to drop onto.
  ///
  /// For the fixed strips (사이드 띠 / 상단 띠, 유저 확정 「고정 도킹」):
  /// they hold one thing, it never moves, and a row of chrome above a
  /// column of tool buttons is a title for something that needs no title.
  /// Every other dock keeps its strip — a panel you switch between and
  /// rearrange still needs the tabs that say so.
  final bool chromeless;

  /// This group's identity in the dock layout; tags outgoing drags.
  final String? groupId;

  /// Called when a tab (possibly from another group) is dropped here.
  /// `insertIndex` counts this group's tabs BEFORE the moved tab is removed
  /// from its old position.
  final void Function(EditorPanelTabDragData data, int insertIndex)? onTabMoved;

  /// Whether a hovering tab may drop into this group (defaults to yes).
  final bool Function(EditorPanelTabDragData data)? canAcceptTab;

  /// Fires with the drag data when a tab lifts off this strip and with
  /// null when the drag ends — lets the dock layout reveal its drop zones
  /// for the tab in flight.
  final ValueChanged<EditorPanelTabDragData?>? onTabDragChanged;

  /// Toggles a tab's drag lock (every tab button carries the toggle, left
  /// of its name). Null hides the toggle.
  final ValueChanged<String>? onToggleLock;

  /// Closes (hides) a panel via the X on its tab. Null hides the button;
  /// locked tabs never show it (lock = pinned).
  final ValueChanged<String>? onCloseTab;

  /// The workspace's reveal channel (UI-R17 #5): when a flash request
  /// names a tab THIS group hosts, the panel body blinks to show where
  /// the already-open panel lives.
  final PanelFlashController? flash;

  static const double stripHeight = 30;

  @override
  State<EditorPanelTabs> createState() => _EditorPanelTabsState();
}

class _EditorPanelTabsState extends State<EditorPanelTabs> {
  /// Keep-alive tabs that have been activated at least once: they stay
  /// mounted offstage so switching back is instant (R10-②).
  final Set<String> _builtTabIds = <String>{};

  /// Keep-alive tabs' built content, cached by tab id (R12-①): a strip
  /// rebuild (tab switch, lock toggle, any layout notify) hands Flutter
  /// the IDENTICAL widget instance, so the heavy panel subtree is skipped
  /// wholesale and a switch costs an Offstage flag flip. CONTRACT: a
  /// keep-alive tab's builder must close over stable objects only (the
  /// session, long-lived notifiers) and subscribe internally — the cache
  /// never re-runs it.
  final Map<String, Widget> _contentCache = <String, Widget>{};

  /// Stable per-tab visibility feeds for [PanelVisibilityScope] (heavy
  /// hosts pause their rebuilds while offstage). Never disposed eagerly:
  /// a pruned tab's subtree unmounts in the same build and detaches its
  /// own listeners; the plain notifier then just gets collected.
  final Map<String, ValueNotifier<bool>> _tabVisibility =
      <String, ValueNotifier<bool>>{};

  bool get _dragEnabled => widget.groupId != null && widget.onTabMoved != null;

  bool _willAccept(EditorPanelTabDragData data) =>
      widget.canAcceptTab?.call(data) ?? true;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tabs = widget.tabs;
    final active = tabs.firstWhere(
      (tab) => tab.id == widget.activeTabId,
      orElse: () => tabs.first,
    );
    // Retention bookkeeping inline with build (no setState needed — the
    // set only ever matters to THIS build): the active keep-alive tab
    // joins, tabs that left the group drop out.
    _builtTabIds.removeWhere(
      (id) => !tabs.any((tab) => tab.id == id && tab.keepAlive),
    );
    _contentCache.removeWhere((id, _) => !_builtTabIds.contains(id));
    _tabVisibility.removeWhere((id, _) => !tabs.any((tab) => tab.id == id));
    if (active.keepAlive) {
      _builtTabIds.add(active.id);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.chromeless)
          Container(
            height: EditorPanelTabs.stripHeight,
            color: colorScheme.surfaceContainerLow,
            child: Stack(
              children: [
                // The append drop target carpets the whole strip BEHIND the
                // tabs: drops on empty strip space append, drops on a tab
                // hit its own insertion targets above.
                if (_dragEnabled)
                  Positioned.fill(
                    child: _TabStripTailDropRegion(
                      willAccept: _willAccept,
                      onDropped: (data) =>
                          widget.onTabMoved!(data, tabs.length),
                    ),
                  ),
                // Tabs keep their natural width (name always visible) and
                // the strip scrolls when they overflow the dock. Buttons
                // STRETCH the strip's full height so the selected tab meets
                // the content edge-to-edge (no strip-colored gap under it).
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < tabs.length; index += 1)
                        _buildTabButton(index),
                    ],
                  ),
                ),
              ],
            ),
          ),
        // The content area shares the selected tab's background so the tab
        // reads as part of the panel, not a floating chip above it. Built
        // keep-alive tabs stay in the stack offstage (state, scroll
        // positions and caches survive the switch).
        Expanded(
          child: ColoredBox(
            color: colorScheme.surface,
            child: Stack(
              fit: StackFit.expand,
              children: [
                for (final tab in tabs)
                  if (tab.id == active.id || _builtTabIds.contains(tab.id))
                    Offstage(
                      key: ValueKey<String>('panel-content-${tab.id}'),
                      offstage: tab.id != active.id,
                      child: TickerMode(
                        enabled: tab.id == active.id,
                        child: PanelVisibilityScope(
                          visible: _visibilityFor(
                            tab.id,
                            visible: tab.id == active.id,
                          ),
                          child: tab.keepAlive
                              ? (_contentCache[tab.id] ??= _buildTabContent(
                                  tab,
                                ))
                              : _buildTabContent(tab),
                        ),
                      ),
                    ),
                // The reveal blink (UI-R17 #5): fires when the flash
                // channel names a tab this group hosts.
                if (widget.flash != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ValueListenableBuilder<PanelFlashRequest?>(
                        valueListenable: widget.flash!.requests,
                        builder: (context, request, _) {
                          if (request == null ||
                              !tabs.any((tab) => tab.id == request.tabId)) {
                            return const SizedBox.shrink();
                          }
                          return PanelFlashOverlay(
                            key: ValueKey<String>(
                              'panel-flash-${request.tabId}-${request.seq}',
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The stable visibility feed for [tabId], its value refreshed inline
  /// with this build. Setting the value here fires descendant listeners
  /// mid-build — legal, they are below this widget and rebuild this frame.
  ValueNotifier<bool> _visibilityFor(String tabId, {required bool visible}) {
    final notifier = _tabVisibility.putIfAbsent(
      tabId,
      () => ValueNotifier<bool>(visible),
    );
    notifier.value = visible;
    return notifier;
  }

  /// One tab's content; panels with a minimum content size larger than
  /// the dock render at that size inside scrollers.
  Widget _buildTabContent(EditorPanelTab tab) {
    if (tab.minContentWidth == null && tab.minContentHeight == null) {
      return Builder(builder: tab.builder);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(tab.minContentWidth ?? 0, constraints.maxWidth);
        final height = math.max(
          tab.minContentHeight ?? 0,
          constraints.maxHeight,
        );
        if (width <= constraints.maxWidth && height <= constraints.maxHeight) {
          return Builder(builder: tab.builder);
        }
        Widget content = SizedBox(
          width: width,
          height: height,
          child: Builder(builder: tab.builder),
        );
        if (height > constraints.maxHeight) {
          content = SingleChildScrollView(child: content);
        }
        if (width > constraints.maxWidth) {
          content = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: content,
          );
        }
        return content;
      },
    );
  }

  Widget _buildTabButton(int index) {
    final tab = widget.tabs[index];
    final selected = tab.id == widget.activeTabId;
    // The grip is the ONLY drag surface (R10-⑩): the rest of the tab is
    // a plain tap target, so selection never waits on the drag arena and
    // a stray drag can't tear a tab off mid-click. Locked tabs keep the
    // grip VISIBLE but inert (R12-⑨: locking must never reshape the tab).
    final grip = _dragEnabled ? _buildDragGrip(tab) : null;
    final button = _PanelTabButton(
      key: tab.buttonKey ?? ValueKey<String>('panel-tab-${tab.id}'),
      label: tab.label,
      icon: tab.icon,
      compact: widget.compact,
      selected: selected,
      locked: tab.locked,
      lockKey: ValueKey<String>('panel-lock-${tab.id}'),
      closeKey: ValueKey<String>('panel-close-${tab.id}'),
      dragGrip: grip,
      // Every tab carries its controls — selecting a tab must never
      // reshape its button.
      onToggleLock: widget.onToggleLock != null
          ? () => widget.onToggleLock!(tab.id)
          : null,
      // Locked tabs keep the X visible but inert (pinned = it does
      // nothing, the tab's shape never changes).
      onClose: widget.onCloseTab != null
          ? () => widget.onCloseTab!(tab.id)
          : null,
      onPressed: () => widget.onTabSelected(tab.id),
    );
    if (!_dragEnabled) {
      return button;
    }
    return _TabDropRegion(
      willAccept: _willAccept,
      // Left half inserts before this tab, right half after it.
      onDropped: (dropped, after) =>
          widget.onTabMoved!(dropped, after ? index + 1 : index),
      child: button,
    );
  }

  /// The drag handle at the tab's left edge — the three-line grip icon.
  /// Locked tabs render the SAME icon dimmed and inert: the tab's footprint
  /// never changes with the lock state (R12-⑨).
  Widget _buildDragGrip(EditorPanelTab tab) {
    if (tab.locked) {
      return Padding(
        key: ValueKey<String>('panel-grip-${tab.id}'),
        padding: const EdgeInsets.only(right: 2),
        child: Icon(
          Icons.drag_indicator,
          size: 12,
          color: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
        ),
      );
    }
    final data = EditorPanelTabDragData(
      tabId: tab.id,
      fromGroupId: widget.groupId!,
    );
    return Draggable<EditorPanelTabDragData>(
      data: data,
      maxSimultaneousDrags: 1,
      // The avatar origin IS the pointer, so drop regions can split
      // themselves into exact before/after halves from the drag offset.
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: _PanelTabDragFeedback(label: tab.label, icon: tab.icon),
      ),
      onDragStarted: () => widget.onTabDragChanged?.call(data),
      // onDragEnd covers completion AND cancellation.
      onDragEnd: (_) => widget.onTabDragChanged?.call(null),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Padding(
          key: ValueKey<String>('panel-grip-${tab.id}'),
          padding: const EdgeInsets.only(right: 2),
          child: Icon(
            Icons.drag_indicator,
            size: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Drop target around one tab button: highlights the insertion edge that
/// matches the pointer's half and reports before/after on drop.
class _TabDropRegion extends StatefulWidget {
  const _TabDropRegion({
    required this.willAccept,
    required this.onDropped,
    required this.child,
  });

  final bool Function(EditorPanelTabDragData data) willAccept;
  final void Function(EditorPanelTabDragData data, bool after) onDropped;
  final Widget child;

  @override
  State<_TabDropRegion> createState() => _TabDropRegionState();
}

class _TabDropRegionState extends State<_TabDropRegion> {
  /// Which insertion edge the hover points at; null while not hovered.
  bool? _hoverAfter;

  bool _isAfter(Offset globalOffset) {
    final box = context.findRenderObject() as RenderBox;
    return box.globalToLocal(globalOffset).dx > box.size.width / 2;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DragTarget<EditorPanelTabDragData>(
      onWillAcceptWithDetails: (details) => widget.willAccept(details.data),
      onMove: (details) {
        if (!widget.willAccept(details.data)) {
          return;
        }
        final after = _isAfter(details.offset);
        if (after != _hoverAfter) {
          setState(() => _hoverAfter = after);
        }
      },
      onLeave: (_) => setState(() => _hoverAfter = null),
      onAcceptWithDetails: (details) {
        setState(() => _hoverAfter = null);
        widget.onDropped(details.data, _isAfter(details.offset));
      },
      builder: (context, candidateData, rejectedData) {
        final hoverAfter = candidateData.isEmpty ? null : _hoverAfter;
        return Stack(
          // Passes the strip's tight height through so the tab button can
          // stretch to it (loose fit would re-center the button and bring
          // the gap under the tab back).
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (hoverAfter != null)
              Positioned(
                left: hoverAfter ? null : 0,
                right: hoverAfter ? 0 : null,
                top: 0,
                bottom: 0,
                width: 2,
                child: ColoredBox(color: colorScheme.primary),
              ),
          ],
        );
      },
    );
  }
}

/// The empty strip tail: dropping there appends the tab to this group.
class _TabStripTailDropRegion extends StatelessWidget {
  const _TabStripTailDropRegion({
    required this.willAccept,
    required this.onDropped,
  });

  final bool Function(EditorPanelTabDragData data) willAccept;
  final void Function(EditorPanelTabDragData data) onDropped;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DragTarget<EditorPanelTabDragData>(
      onWillAcceptWithDetails: (details) => willAccept(details.data),
      onAcceptWithDetails: (details) => onDropped(details.data),
      builder: (context, candidateData, rejectedData) {
        return Stack(
          children: [
            const SizedBox.expand(),
            if (candidateData.isNotEmpty)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 2,
                child: ColoredBox(color: colorScheme.primary),
              ),
          ],
        );
      },
    );
  }
}

/// The floating chip under the pointer while a tab is dragged.
class _PanelTabDragFeedback extends StatelessWidget {
  const _PanelTabDragFeedback({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelTabButton extends StatelessWidget {
  const _PanelTabButton({
    super.key,
    required this.label,
    required this.icon,
    required this.compact,
    required this.selected,
    required this.locked,
    required this.lockKey,
    required this.closeKey,
    required this.onPressed,
    this.dragGrip,
    this.onToggleLock,
    this.onClose,
  });

  final String label;
  final IconData icon;
  final bool compact;
  final bool selected;
  final bool locked;
  final Key lockKey;
  final Key closeKey;
  final VoidCallback onPressed;

  /// The drag handle at the tab's left edge (R10-⑩) — the only surface
  /// that lifts the tab; null for locked tabs and non-draggable groups.
  final Widget? dragGrip;

  /// Taps on the lock glyph toggle the drag lock instead of selecting.
  final VoidCallback? onToggleLock;

  /// Taps on the X close (hide) the panel; null hides the button.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    // Every tab shows [name] [lock] [X] all the time — selection only
    // changes colors, never the button's shape.
    return Tooltip(
      message: label,
      // Manual trigger: hover tooltips still work, but no long-press
      // recognizer competes with drag lifts.
      triggerMode: TooltipTriggerMode.manual,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            // The selected tab wears the PANEL BODY color so it flows
            // seamlessly into the content below it.
            color: selected ? colorScheme.surface : Colors.transparent,
            border: Border(
              top: BorderSide(
                width: 2,
                color: selected ? colorScheme.primary : Colors.transparent,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ?dragGrip,
              if (compact)
                Icon(icon, size: 14, color: foreground)
              else
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: foreground,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              const SizedBox(width: 4),
              if (onToggleLock != null)
                _TabGlyphButton(
                  glyphKey: lockKey,
                  tooltip: locked ? 'Unlock $label drag' : 'Lock $label drag',
                  icon: locked ? Icons.lock : Icons.lock_open_outlined,
                  // The lock reads at a glance: accent ONLY when locked.
                  color: locked
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  onTap: onToggleLock!,
                )
              else if (locked)
                Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.lock, size: 11, color: colorScheme.primary),
                ),
              if (onClose != null)
                _TabGlyphButton(
                  glyphKey: closeKey,
                  tooltip: locked ? '$label is locked' : 'Close $label',
                  icon: Icons.close,
                  // Locked: same footprint, dimmed and inert — the dead X
                  // still absorbs its tap so it never selects the tab.
                  color: locked
                      ? colorScheme.onSurfaceVariant.withValues(alpha: 0.35)
                      : colorScheme.onSurfaceVariant,
                  onTap: locked ? () {} : onClose!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small tappable glyph inside a tab button (close / lock): its own hit
/// region so taps don't select the tab.
class _TabGlyphButton extends StatelessWidget {
  const _TabGlyphButton({
    required this.glyphKey,
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final Key glyphKey;
  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      triggerMode: TooltipTriggerMode.manual,
      child: GestureDetector(
        key: glyphKey,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(icon, size: 11, color: color),
        ),
      ),
    );
  }
}
