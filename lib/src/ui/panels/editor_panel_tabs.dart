import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../layout/device_grid.dart';
import '../theme/app_theme.dart';
import '../widgets/grip_band.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/static_raster.dart';
import '../widgets/superellipse_clip.dart';
import 'panel_collapsed_scope.dart';
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
    this.staticRaster = true,
    this.sillTrailing,
    this.collapsedExtent = 0,
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

  /// Whether this tab's content may be baked into a [StaticRaster] while
  /// it is not changing. **Defaults to ON, and that is the point.**
  ///
  /// The measurement that started this: hovering the pen over an empty
  /// canvas cost 27.6 ms/frame of raster, of which 24.0 ms was panels
  /// that were not changing at all. The fix cannot be a thing each panel
  /// author remembers to apply — the panel added next month would be
  /// heavy again. So it lives HERE, on the one funnel every docked panel
  /// passes through, and a new tab is light without doing anything.
  ///
  /// Opting out is for a surface that owns its own retention story. The
  /// canvas is the only one today: it is full of repaint boundaries by
  /// design and its live-stroke path must never be asked for a copy.
  /// (A panel that merely animates SOMETIMES does not need this — the
  /// wrapper notices and stands itself down. See
  /// [StaticRaster.maxConsecutiveCaptures].)
  final bool staticRaster;

  /// What THIS tab puts on the group's 문턱, right-aligned, ahead of the
  /// group's own [EditorPanelTabs.trailing].
  ///
  /// Only the ACTIVE tab's is mounted, which is what makes the sill able to
  /// carry a panel's own controls at all: the frame panels put their
  /// playback transport and their settings pill here (유저 확정,
  /// 2026-08-10), and 「존재할 거면 늘 그 자리에」 holds because the sill's
  /// right edge is fixed while the tabs grow from the left.
  final WidgetBuilder? sillTrailing;

  /// How tall this panel needs to be when the region is COLLAPSED — see
  /// [PanelCollapsedScope] for why the shell owns this at all.
  ///
  /// Zero means the honest thing: the panel has nothing to say at that size,
  /// so the shell shows NOTHING and the region is its sill alone (유저 확정
  /// for 콘티·뷰어: 「진짜 깔끔하게 내용물 안 보이게」). The frame panels ask
  /// for their command bar's height and keep working while folded.
  final double collapsedExtent;
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
    this.draggingTab,
    this.collapsed = false,
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

  /// The tab in flight ANYWHERE in the workspace — including one lifted off
  /// another group and headed here. The sill's right-hand controls fade out
  /// while it is non-null so the whole strip is landing area again; see
  /// [_EditorPanelTabsState._buildSillTrailing].
  final ValueListenable<EditorPanelTabDragData?>? draggingTab;

  /// Whether the REGION this group lives in is folded down. The strip stays
  /// exactly as it is — collapsed is not closed — and the content area
  /// switches to the active tab's collapsed form; see [PanelCollapsedScope].
  final bool collapsed;

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

  /// What one tab costs across the strip: a 16px glyph with 8px of breath
  /// on each side. Stated rather than measured because the strip has to
  /// decide how many fit BEFORE laying them out.
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

  /// Whether the pointer is anywhere on this PANEL.
  ///
  /// 유저, R3 #9: 패널에 호버하면 기본색. The band that lifts a panel used to
  /// appear only once the pointer was on the tab itself, which is a handle
  /// you cannot find without already knowing where it is. Hovering the panel
  /// is the moment to say "there is a handle, and it is here".
  ///
  /// A notifier and not `setState`: the strip holds the panel's whole
  /// content, and repainting a 2px band is not a reason to rebuild it.
  final ValueNotifier<bool> _panelHovered = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _panelHovered.dispose();
    super.dispose();
  }

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
            // A link in the chain to the RAIL-DOCKED canvas: everything in
            // the panel below this strip starts at this height, and a
            // docked canvas is one of those things. 30 × 1.25 = 37.5 —
            // unlike the 48s in the window chain, this one is off the grid
            // at Windows' own scaling steps, and it is measurably what
            // held the second canvas boundary off at every ratio while the
            // editing canvas was already clean.
            height: DeviceGrid.of(
              context,
            ).position(EditorPanelTabs.stripHeight),
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
                // THE SEAM between the tab strip and the panel body (유저,
                // R4 #1: 패널 아이콘쪽 영역 밑에 가로선 둬서 탭이랑 내용
                // 구분할 수 있게). The strip and the body are the SAME fill —
                // `surfaceContainerLow` and `surface` both resolve to
                // #1E2022 — so with nothing drawn between them the tabs
                // float in an unbroken field and the panel has no top.
                //
                // ★Painted UNDER the tabs on purpose. The selected tab's
                // fill is opaque and runs the strip's full height, so it
                // cuts its own gap in this line: the strip is separated from
                // the body, and the OPEN tab still grows out of it as one
                // shape — the 「선택 탭은 패널의 발」 contract, which a line
                // drawn over the top would have broken. One widget keeps
                // both promises and there is no arithmetic to get wrong.
                //
                // The colour is the app's one line: the same
                // `outlineVariant` the edge docks draw their vertical seam
                // with and that `ToolsPanel.groupDivider` uses between the
                // rail's clusters.
                Positioned(
                  key: const ValueKey<String>('panel-strip-seam'),
                  left: 0,
                  right: 0,
                  top: widget.stripAtBottom ? 0 : null,
                  bottom: widget.stripAtBottom ? null : 0,
                  height: 1,
                  // Tight on both axes from the `Positioned`, so this leaf
                  // has a size — unlike the band above, which had to be told.
                  child: ColoredBox(color: colorScheme.outlineVariant),
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
                //
                // ★ONE Row, not a Stack overlay (2026-08-10). The trailing
                // group used to be `Align`ed over the tabs and the tab count
                // guessed 32px of room for it — which was fine while it held
                // one chevron and wrong the moment the sill grew a transport
                // and a settings pill. A Row lays its INFLEXIBLE child out
                // first and hands the `Flexible` what is left, so the tab
                // count is measured against the room that actually exists
                // and cannot drift from what the trailing group costs.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ⑪ 유저 2026-08-12: 「타임라인 문턱에 있는 재생이나
                    // 설정버튼 왜 우측정렬안했지? 말한것들좀 지키자.」
                    //
                    // `Expanded`, not `Flexible`. A loose `Flexible` is only
                    // as wide as the tabs inside it, so the trailing group sat
                    // immediately after them — reading as left-aligned, and
                    // sliding sideways every time a tab was added. Taking all
                    // the room pins the trailing group to the right edge,
                    // which is the entire reason it was put there (유저
                    // 2026-08-10: 「왼쪽 정렬이면 패널을 추가할 때 재생 버튼이
                    // 밀린다」).
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // How many fit. The overflow button costs one slot,
                          // so it only appears when it actually buys room.
                          final fits =
                              (constraints.maxWidth /
                                      EditorPanelTabs._tabExtent)
                                  .floor();
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
                    ),
                    _buildSillTrailing(context, active),
                  ],
                ),
              ],
            ),
          );

    return MouseRegion(
      opaque: false,
      onEnter: (_) => _panelHovered.value = true,
      onExit: (_) => _panelHovered.value = false,
      child: Column(
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
                          // A collapsed region whose active tab declared no
                          // collapsed form shows NOTHING — not a crop of the
                          // panel, not a sliver of its top. That is the whole
                          // contract, and offstage is how it is kept: the
                          // subtree stays mounted (a keep-alive tab must not
                          // lose its state to a fold) and simply does not lay
                          // out.
                          offstage:
                              tab.id != active.id ||
                              (widget.collapsed && tab.collapsedExtent <= 0),
                          child: TickerMode(
                            enabled: tab.id == active.id && !widget.collapsed,
                            child: PanelVisibilityScope(
                              visible: _visibilityFor(
                                tab.id,
                                visible: tab.id == active.id,
                              ),
                              // OUTSIDE the content cache on purpose: the
                              // cached widget instance never changes, and an
                              // inherited dependency marks its dependents
                              // dirty directly — so folding reaches a
                              // keep-alive panel without dropping the cache
                              // that makes tab switches instant.
                              child: PanelCollapsedScope(
                                collapsed:
                                    widget.collapsed && tab.id == active.id,
                                child: tab.keepAlive
                                    ? (_contentCache[tab.id] ??=
                                          _buildTabContent(tab))
                                    : _buildTabContent(tab),
                              ),
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
      ),
    );
  }

  /// The sill's right-hand group: the ACTIVE tab's own controls, then the
  /// group's ([EditorPanelTabs.trailing]).
  ///
  /// ★It gets out of the way while a tab is in flight. The whole strip is a
  /// drop target ([_TabStripTailDropRegion] carpets it), so anything sitting
  /// on it is eating landing area — and this group is no longer one chevron
  /// but a transport and a pill. Fading it out is not decoration: it hands
  /// the sill back to the drag for exactly as long as the drag lasts.
  Widget _buildSillTrailing(BuildContext context, EditorPanelTab active) {
    final own = active.sillTrailing?.call(context);
    final group = widget.trailing;
    if (own == null && (group == null || group.isEmpty)) {
      return const SizedBox.shrink();
    }
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [?own, ...?group],
    );
    final dragging = widget.draggingTab;
    if (dragging == null) {
      return row;
    }
    return ValueListenableBuilder<EditorPanelTabDragData?>(
      valueListenable: dragging,
      builder: (context, inFlight, child) => IgnorePointer(
        ignoring: inFlight != null,
        child: AnimatedOpacity(
          opacity: inFlight != null ? 0 : 1,
          duration: const Duration(milliseconds: 120),
          child: child,
        ),
      ),
      child: row,
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
  ///
  /// ★THE funnel every docked panel passes through, and therefore the
  /// only place the "a panel is light unless it says otherwise" rule can
  /// live. See [EditorPanelTab.staticRaster].
  Widget _buildTabContent(EditorPanelTab tab) => _buildTabInterior(tab);

  /// Wraps [child] in the panel bake unless the tab opted out.
  ///
  /// ⚠️Called at each of the interior's leaves rather than once around
  /// the outside, and that placement is not cosmetic. The overflow
  /// branches below put the panel inside a `SingleChildScrollView`, and a
  /// viewport IS a repaint boundary — so a bake around the outside would
  /// find one, stand down, and the panel would silently go back to
  /// paying full raster price. It would do that only when the dock is
  /// narrow enough to overflow, which means the cost would appear and
  /// disappear as the user drags a splitter, and no test that pumps a
  /// single window size would ever see it.
  Widget _bake(EditorPanelTab tab, Widget child) {
    if (!tab.staticRaster) {
      return child;
    }
    // A keep-alive tab stays MOUNTED offstage, and `Offstage` keeps the
    // render object attached — so nothing would ever release its baked
    // image. Seven tabs ship keep-alive; that is seven full-panel RGBA
    // surfaces held for panels nobody is looking at.
    //
    // The visibility feed is already here for the same reason (heavy
    // hosts stand down offstage), and `enabled` drops the image in its
    // setter rather than waiting for a paint that will never come while
    // hidden. `child` is captured OUTSIDE the builder, so a tab switch
    // rebuilds one widget and not the panel.
    final visible = _tabVisibility[tab.id];
    StaticRaster bake(bool enabled) => StaticRaster(
      debugLabel: 'panel:${tab.id}',
      enabled: enabled,
      child: child,
    );
    if (visible == null) {
      return bake(true);
    }
    return ValueListenableBuilder<bool>(
      valueListenable: visible,
      builder: (context, isVisible, _) => bake(isVisible),
    );
  }

  Widget _buildTabInterior(EditorPanelTab tab) {
    // ★A COLLAPSED panel never meets the minimum-size scroller. That branch
    // is what turned folding into cropping: it takes "the dock is smaller
    // than my floor" and answers "then lay out at the floor and let them
    // scroll", which is right for a frame panel squeezed into a side rail
    // and exactly wrong here — the panel has already been told to render a
    // form that fits, and putting that form in a scroller would give it back
    // a height it did not ask for.
    if (widget.collapsed ||
        (tab.minContentWidth == null && tab.minContentHeight == null)) {
      return _bake(tab, Builder(builder: tab.builder));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(tab.minContentWidth ?? 0, constraints.maxWidth);
        final height = math.max(
          tab.minContentHeight ?? 0,
          constraints.maxHeight,
        );
        if (width <= constraints.maxWidth && height <= constraints.maxHeight) {
          return _bake(tab, Builder(builder: tab.builder));
        }
        Widget content = SizedBox(
          width: width,
          height: height,
          child: _bake(tab, Builder(builder: tab.builder)),
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
      panelHovered: _panelHovered,
      dragData: _dragEnabled && !tab.locked
          ? EditorPanelTabDragData(tabId: tab.id, fromGroupId: widget.groupId!)
          : null,
      onTabDragChanged: widget.onTabDragChanged,
      onPressed: () => widget.onTabSelected(tab.id),
      stripAtBottom: widget.stripAtBottom,
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
/// one icon. A zone is the same promise in the same place, invisible at
/// rest: the ONLY surface that lifts a tab, so selection never waits on a
/// drag arena and a stray drag cannot tear a tab off mid-click (R10-⑩).
///
/// ★AND THE ZONE IS THE ACTIVE RULE (유저, R2 #9). The tab used to carry
/// two marks on two different edges — a 2px accent rule on the window-facing
/// edge saying "this one is open", and a separate lift zone on the leading
/// edge saying "you may drag me". They are one band now, on the edge the
/// rule was already on, and its THICKNESS is what says which thing it is
/// saying: 2px for a state you read, 6px for a handle you can reach. The
/// colour ladder underneath is the app's one grip ladder, unchanged.
class _PanelTabButton extends StatefulWidget {
  const _PanelTabButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.locked,
    required this.gripKey,
    required this.panelHovered,
    required this.onPressed,
    required this.stripAtBottom,
    this.dragData,
    this.onTabDragChanged,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool locked;
  final Key gripKey;

  /// Whether the pointer is anywhere on the PANEL this tab belongs to —
  /// the first rung of the band's ladder (유저, R3 #9).
  final ValueListenable<bool> panelHovered;
  final VoidCallback onPressed;

  /// Which side of the panel this tab's strip is on — the tab has to know,
  /// because BOTH of its facing-dependent marks were drawn as if the strip
  /// were always on top: the accent rule along the seam the panel wants
  /// invisible, and the square corners on the edge that should be rounded.
  final bool stripAtBottom;

  /// What this tab carries when lifted; null for locked tabs and
  /// non-draggable groups, which keep the zone's footprint and never arm.
  final EditorPanelTabDragData? dragData;
  final ValueChanged<EditorPanelTabDragData?>? onTabDragChanged;

  // ⛔The three numbers and the colour ladder LEFT this class (2026-08-10):
  // they are [GripBand] now, because the command pill's `＋` wears the same
  // band along its own top edge to open its list of kinds. A second copy of
  // 「2px for a state, 6px for a handle, and the target is 8 either way」 is
  // exactly the drift this repo keeps paying for.

  @override
  State<_PanelTabButton> createState() => _PanelTabButtonState();
}

class _PanelTabButtonState extends State<_PanelTabButton> {
  bool _gripHovered = false;
  bool _dragging = false;

  bool get _armed => widget.dragData != null;

  /// Thick when there is something to grab, thin when it is only offering
  /// itself.
  double get _bandExtent => _armed && (_dragging || _gripHovered)
      ? GripBand.reach
      : GripBand.rest;

  /// The app's one grip ladder ([GripBand.ink]), and NOTHING ELSE (유저,
  /// R3 #9).
  ///
  /// ⛔The ACTIVE rung is gone. The band used to turn accent for the open
  /// tab, which meant the tab you were most likely to want to drag was the
  /// one tab whose band could never say "you may drag me" — the two signals
  /// were sharing one surface and the louder one always won. Which panel is
  /// open is still said twice over without it: the selected tab wears the
  /// body's own fill and its glyph is accent.
  ///
  /// A tab that cannot be lifted has no band at all, which is why the
  /// `_armed` gate stays here rather than moving into the ladder.
  Color _bandColor(bool panelHovered) => _armed
      ? GripBand.ink(
          nearby: panelHovered,
          hovered: _gripHovered,
          active: _dragging,
        )
      : Colors.transparent;

  /// The tab's silhouette: rounded on the edge AWAY from the panel body,
  /// square where it meets it.
  RoundedSuperellipseBorder _shape() => AppShapes.containerRadius(
    widget.stripAtBottom
        ? const BorderRadius.vertical(
            bottom: Radius.circular(AppShapes.wellRadius),
          )
        : const BorderRadius.vertical(
            top: Radius.circular(AppShapes.wellRadius),
          ),
  );

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = widget.selected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    Widget grip = MouseRegion(
      cursor: _armed ? SystemMouseCursors.grab : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _gripHovered = true),
      onExit: (_) => setState(() => _gripHovered = false),
      child: SizedBox(
        key: widget.gripKey,
        height: GripBand.hitExtent,
        // The TARGET is a constant 8px of the edge; the band inside it
        // grows toward the frame, so a pointer resting on the grip never
        // finds the thing it is over moving out from under it.
        child: Align(
          alignment: widget.stripAtBottom
              ? Alignment.bottomCenter
              : Alignment.topCenter,
          child: ValueListenableBuilder<bool>(
            valueListenable: widget.panelHovered,
            builder: (context, panelHovered, _) => SizedBox(
              // BOTH axes, not just the height. `Align` hands its child
              // LOOSE constraints, and a `ColoredBox` with no child takes
              // `constraints.smallest` — so a band told only how THICK to be
              // laid out 0px wide. It was coloured correctly, on the right
              // edge, climbing the right ladder, and invisible: the whole
              // handle simply did not exist on screen (유저, R4 #6).
              //
              // ⚠️Third time this trap has bitten: R1a collapsed a grip's
              // HEIGHT the same way. A `ColoredBox` is a leaf — it never has
              // a size of its own to fall back on.
              width: double.infinity,
              height: _bandExtent,
              child: ColoredBox(color: _bandColor(panelHovered)),
            ),
          ),
        ),
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
          child: _PanelTabDragFeedback(label: widget.label, icon: widget.icon),
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
      // ⛔No MouseRegion of its own any more: the band's first rung is the
      // PANEL being hovered, not this button, and the InkWell already
      // paints its own hover for the button itself.
      child: InkWell(
        onTap: widget.onPressed,
        // THE SELECTED TAB IS THE PANEL'S FOOT, not a chip lying on the
        // sill. It wears the body's own fill and rounds only the corners
        // AWAY from the body, so the seam between them disappears and the
        // panel reads as one shape that grows out of its buttons — which
        // is what the sill was for. Its neighbours are bare, so the fill
        // still says which one is on, alongside the accent glyph and the
        // band on the edge facing the WINDOW rather than along the seam
        // the panel wants invisible.
        //
        // The band is CLIPPED to that shape, the way every other grip in
        // the app is clipped to the panel it belongs to: the tab's rounded
        // corners cut it, so it reads as the tab's own edge.
        child: SuperellipseClip(
          shape: _shape(),
          // PASSTHROUGH, not the default loose fit. A loose Stack hands
          // its non-positioned child the incoming constraints LOOSENED,
          // so the tab's body shrank to its 16px glyph and sat at the top
          // of a 30px strip: the selected fill stopped reaching the panel
          // body it is supposed to merge into, and every glyph rode 7px
          // high. Passthrough keeps the strip's tight height and the
          // loose width, which is exactly what a tab wants — as tall as
          // the strip, as wide as what it holds.
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: ShapeDecoration(
                  color: widget.selected
                      ? colorScheme.surface
                      : Colors.transparent,
                  shape: _shape(),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, size: 16, color: foreground),
                    if (widget.locked) ...[
                      const SizedBox(width: 3),
                      Icon(Icons.lock, size: 9, color: colorScheme.primary),
                    ],
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: widget.stripAtBottom ? null : 0,
                bottom: widget.stripAtBottom ? 0 : null,
                child: grip,
              ),
            ],
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
    // R6 #4: the shared flyout. This list was the app's row grammar copied
    // out by hand — 32px, 12pt, an icon and an 8px gap — and it had already
    // drifted (a 14px glyph against the flyout's 16), which is how a copy
    // announces itself.
    return PanelFlyoutTrigger(
      key: ValueKey<String>('panel-tab-overflow-${groupId ?? 'group'}'),
      tooltip: '+${hidden.length}',
      padding: EdgeInsets.zero,
      entriesBuilder: () => [
        for (final tab in hidden)
          PanelFlyoutItem(
            keyValue: 'panel-tab-overflow-item-${tab.id}',
            label: tab.label,
            icon: tab.icon,
            // ⛔NOT a check. The open panel accents, exactly as the tinted
            // glyph here always did — 「어차피 선택하면 ui적으로 색 바뀌니까
            // 그거로 충분해」 (R11-①).
            selected: tab.id == activeTabId,
            onSelected: () => onTabSelected(tab.id),
          ),
      ],
      // When the OPEN panel is one of the hidden ones, this button says so.
      // A compressed strip used to show `+2` and nothing else — no tab lit
      // anywhere — so the only way to learn what was on screen was to open
      // the popover and look. It speaks for the active tab instead.
      //
      // Deliberately WITHOUT moving anything: pulling the active tab back
      // into view would make the visible set depend on the selection, and
      // tabs that jump under the pointer when you pick one are the thing
      // "selection must not rearrange the buttons" exists to prevent.
      child: SizedBox(
        width: EditorPanelTabs._tabExtent,
        child: Center(
          child: _activeHidden == null
              ? Text(
                  '+${hidden.length}',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                )
              : Icon(_activeHidden!.icon, size: 16, color: colorScheme.primary),
        ),
      ),
    );
  }

  /// The hidden tab that is currently OPEN, if the overflow swallowed it.
  EditorPanelTab? get _activeHidden {
    for (final tab in hidden) {
      if (tab.id == activeTabId) {
        return tab;
      }
    }
    return null;
  }
}
