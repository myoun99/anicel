import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
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
    this.stripAtBottom = false,
    this.trailing,
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

  /// Puts the strip on the panel's BOTTOM inner edge — the 문턱 of a panel
  /// that floats over the canvas rather than sitting in a column.
  ///
  /// 기하는 캔버스 향한 변에, 정체성은 창틀 향한 변에 (유저 확정): the edge
  /// facing the artwork carries the resize handle, and the edge facing the
  /// window frame carries "which panel is this". Dock the region at the top
  /// instead and both flip, from the same one law.
  final bool stripAtBottom;

  /// Controls pinned to the strip's far end — the collapse toggle, and
  /// whatever else belongs to the REGION rather than to a tab.
  final List<Widget>? trailing;

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

  /// What one tab costs across the strip: the 8px lift zone, a 16px glyph
  /// and its trailing breath. Stated rather than measured because the strip
  /// has to decide how many fit BEFORE laying them out.
  static const double _tabExtent = 32;

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

    final strip = widget.chromeless
        ? null
        : Container(
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
                // ★띠는 스크롤하지 않는다 (유저 확정). It used to be a
                // horizontal scroller, and the reason to stop is not taste
                // but GESTURE: inside a scrollable, a drag goes to the
                // scroll arena before the tab under the finger ever sees
                // it — the same reason long-press was taken out of the app
                // — and dragging a tab is how a panel is moved. Compressed,
                // that fight does not exist.
                //
                // Buttons STRETCH the strip's full height so the selected
                // tab meets the content edge-to-edge.
                LayoutBuilder(
                  builder: (context, constraints) {
                    final trailingRoom = widget.trailing == null ? 0.0 : 32.0;
                    final room = math.max(
                      0.0,
                      constraints.maxWidth - trailingRoom,
                    );
                    // How many fit. The overflow button costs one slot, so
                    // it only appears when it actually buys room.
                    final fits = (room / EditorPanelTabs._tabExtent).floor();
                    final overflowing = fits < tabs.length;
                    final shown = overflowing
                        ? math.max(0, fits - 1)
                        : tabs.length;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var index = 0; index < shown; index += 1)
                          _buildTabButton(index),
                        if (overflowing)
                          _TabOverflowButton(
                            groupId: widget.groupId,
                            hidden: tabs.sublist(shown),
                            activeTabId: widget.activeTabId,
                            onTabSelected: widget.onTabSelected,
                          ),
                      ],
                    );
                  },
                ),
                if (widget.trailing != null)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: widget.trailing!,
                    ),
                  ),
              ],
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (strip != null && !widget.stripAtBottom) strip,
        // The content area shares the selected tab's background so the tab
        // reads as part of the panel, not a floating chip above it. Built
        // keep-alive tabs stay in the stack offstage (state, scroll
        // positions and caches survive the switch).
        Expanded(
          // A panel's content may not paint outside the panel.
          //
          // It always could: the content box is a Stack, which does not
          // clip, and a host that lays out a little taller than the room it
          // was given simply spilled past the bottom. That was invisible
          // while the strip was on TOP — the spill went off the region's
          // bottom edge, which was the window's bottom edge. With the strip
          // on the bottom inner edge the spill goes UNDER the 문턱, where it
          // is still hit-testable but permanently covered: a long-press
          // aimed at the sheet's last row switched the panel instead.
          child: ClipRect(
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
        ),
        if (strip != null && widget.stripAtBottom) strip,
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
    // The zone is the ONLY drag surface (R10-⑩): the rest of the tab is a
    // plain tap target, so selection never waits on the drag arena and a
    // stray drag can't tear a tab off mid-click. A LOCKED tab keeps the
    // zone's footprint and never arms it — locking must never reshape the
    // tab (R12-⑨).
    final button = _PanelTabButton(
      key: tab.buttonKey ?? ValueKey<String>('panel-tab-${tab.id}'),
      label: tab.label,
      icon: tab.icon,
      selected: selected,
      locked: tab.locked,
      gripKey: ValueKey<String>('panel-grip-${tab.id}'),
      dragData: _dragEnabled && !tab.locked
          ? EditorPanelTabDragData(tabId: tab.id, fromGroupId: widget.groupId!)
          : null,
      onTabDragChanged: widget.onTabDragChanged,
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
      // The tab in flight wears the same fill the tab wears when it is
      // switched on: a drag avatar is the one surface the pointer is
      // literally carrying, and on a dark UI its drop shadow is nearly
      // nothing, so the fill has to do the lifting.
      color: colorScheme.surfaceContainerHigh,
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


/// One tab: an icon, and an 8px strip of its leading edge that lifts it.
///
/// 패널 이름 글자는 어디에도 안 띄운다 (유저 확정). The name lives in the
/// tooltip, which was always the tab's only accessibility name anyway, and
/// [EditorPanelTab.label] stays a field because the settings popover builds
/// its panel list out of it. What went with the name is the lock glyph and
/// the X: closing is the settings list's job now, and the lock's job — a
/// stray drag must not tear the drawing surface off — is done structurally,
/// because the floor has no strip to grip in the first place.
///
/// ⛔The GRIP glyph is gone, not the grip. Three dots said "you may drag
/// me" at the cost of being the widest thing on a button that is otherwise
/// one icon. The 8px zone is the same promise in the same place, invisible
/// at rest: the ONLY surface that lifts a tab, so selection never waits on
/// a drag arena and a stray drag cannot tear a tab off mid-click (R10-⑩).
class _PanelTabButton extends StatefulWidget {
  const _PanelTabButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.locked,
    required this.gripKey,
    required this.onPressed,
    this.dragData,
    this.onTabDragChanged,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool locked;
  final Key gripKey;
  final VoidCallback onPressed;

  /// What this tab carries when lifted; null for locked tabs and
  /// non-draggable groups, which keep the zone's footprint and never arm.
  final EditorPanelTabDragData? dragData;
  final ValueChanged<EditorPanelTabDragData?>? onTabDragChanged;

  /// The lift zone's width — a stylus-friendly sliver of the leading edge.
  static const double gripExtent = 8;

  @override
  State<_PanelTabButton> createState() => _PanelTabButtonState();
}

class _PanelTabButtonState extends State<_PanelTabButton> {
  bool _buttonHovered = false;
  bool _gripHovered = false;
  bool _dragging = false;

  /// The four states, on the ladder the app's scrollbar thumb already
  /// climbs: invisible until the pointer is on the BUTTON, brighter on the
  /// zone itself, accent while it is actually lifting something.
  Color get _gripColor {
    if (widget.dragData == null) {
      return Colors.transparent;
    }
    if (_dragging) {
      return AppColors.accent;
    }
    if (_gripHovered) {
      return AppColors.gripHover;
    }
    if (_buttonHovered) {
      return AppColors.hairlineStrong;
    }
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = widget.selected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    Widget grip = MouseRegion(
      cursor: widget.dragData == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.grab,
      onEnter: (_) => setState(() => _gripHovered = true),
      onExit: (_) => setState(() => _gripHovered = false),
      // The ZONE is the paint. It used to hold a 2x14 rounded bar, which is
      // a drag-handle GLYPH by another name — the very thing this round
      // deleted everywhere else. A grip is a region of the button that
      // lights up, not a mark drawn on it, so the whole 8px lights up and
      // it runs the button's full height instead of floating in its middle.
      // The height is EXPLICIT: a ColoredBox with no child collapses to zero
      // under the Row's loose cross-axis constraint, and a zero-height zone
      // is not a lift zone — it takes the drag with it.
      child: SizedBox(
        key: widget.gripKey,
        width: _PanelTabButton.gripExtent,
        height: EditorPanelTabs.stripHeight,
        child: ColoredBox(color: _gripColor),
      ),
    );
    final data = widget.dragData;
    if (data != null) {
      grip = Draggable<EditorPanelTabDragData>(
        data: data,
        maxSimultaneousDrags: 1,
        // The avatar origin IS the pointer, so drop regions can split
        // themselves into exact before/after halves from the drag offset.
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: FractionalTranslation(
          translation: const Offset(-0.5, -0.5),
          child: _PanelTabDragFeedback(
            label: widget.label,
            icon: widget.icon,
          ),
        ),
        onDragStarted: () {
          setState(() => _dragging = true);
          widget.onTabDragChanged?.call(data);
        },
        // onDragEnd covers completion AND cancellation.
        onDragEnd: (_) {
          setState(() => _dragging = false);
          widget.onTabDragChanged?.call(null);
        },
        child: grip,
      );
    }

    return Tooltip(
      message: widget.label,
      // Manual trigger: hover tooltips still work, but no long-press
      // recognizer competes with drag lifts.
      triggerMode: TooltipTriggerMode.manual,
      child: MouseRegion(
        onEnter: (_) => setState(() => _buttonHovered = true),
        onExit: (_) => setState(() => _buttonHovered = false),
        child: InkWell(
          onTap: widget.onPressed,
          child: Container(
            padding: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              // The selected tab wears the one level reserved for "switched
              // on"; everything else is the panel's own chrome fill.
              color: widget.selected
                  ? colorScheme.surfaceContainerHigh
                  : Colors.transparent,
              border: Border(
                top: BorderSide(
                  width: 2,
                  color: widget.selected
                      ? colorScheme.primary
                      : Colors.transparent,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                grip,
                Icon(widget.icon, size: 16, color: foreground),
                if (widget.locked) ...[
                  const SizedBox(width: 3),
                  Icon(Icons.lock, size: 9, color: colorScheme.primary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The strip's overflow: what did not fit, in a popover.
///
/// 넘치면 오버플로로 넘긴다 (유저 확정). The list is the compressed strip's
/// honest tail rather than a second scroll surface — and it is the one place
/// panel NAMES are allowed, because a row of unlabelled glyphs in a menu is
/// a puzzle rather than a list.
class _TabOverflowButton extends StatelessWidget {
  const _TabOverflowButton({
    required this.groupId,
    required this.hidden,
    required this.activeTabId,
    required this.onTabSelected,
  });

  final String? groupId;
  final List<EditorPanelTab> hidden;
  final String activeTabId;
  final ValueChanged<String> onTabSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      key: ValueKey<String>('panel-tab-overflow-${groupId ?? 'group'}'),
      tooltip: '+${hidden.length}',
      position: PopupMenuPosition.under,
      popUpAnimationStyle: instantMenuAnimation,
      itemBuilder: (context) => [
        for (final tab in hidden)
          PopupMenuItem<String>(
            key: ValueKey<String>('panel-tab-overflow-item-${tab.id}'),
            value: tab.id,
            height: 32,
            child: Row(
              children: [
                Icon(
                  tab.icon,
                  size: 14,
                  color: tab.id == activeTabId
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(tab.label, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
      ],
      onSelected: onTabSelected,
      child: SizedBox(
        width: EditorPanelTabs._tabExtent,
        child: Center(
          child: Text(
            '+${hidden.length}',
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
