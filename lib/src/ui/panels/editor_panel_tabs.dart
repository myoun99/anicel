import '../widgets/app_tooltip.dart';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../layout/device_grid.dart';
import '../theme/app_theme.dart';
import '../widgets/dock_edge_splitter.dart' show DockSplitterEdges;
import '../widgets/drag_chip.dart';
import '../widgets/grip_band.dart';
import '../widgets/kept_tail_row.dart';
import '../widgets/overflow_scrollers.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/static_raster.dart';
import '../widgets/superellipse_clip.dart';
import '../widgets/tick_layer.dart';
import 'panel_collapsed_scope.dart';
import 'open_tab_content.dart';
import 'panel_flash.dart';
import '../input/control_press_claim.dart';

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
    this.staticRaster = true,
    this.stillRaster = true,
    this.sparesSplitters = true,
    this.collapsedExtent = 0,
    this.canvasBase = false,
    this.contentIdentity,
  });

  /// Stable identifier the group reports through `onTabSelected`.
  final String id;

  final String label;
  final IconData icon;

  /// Builds the tab's content. Only the ACTIVE tab is built, and only while
  /// its region shows it — what must survive a switch lives above the tab
  /// group ([EditorPanelTabs]).
  ///
  /// Run once while the tab stays open ([OpenTabContent] — its CONTRACT is
  /// this builder's).
  final WidgetBuilder builder;

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

  /// Whether the dock region showing this tab may be drawn from one still
  /// image while nothing in it changes (`StillRaster`, around each dock).
  /// Defaults to ON, like [staticRaster] and for the same reason.
  ///
  /// ⛔A DIFFERENT QUESTION from [staticRaster], so a different field:
  /// that one asks whether a bake taken on every change pays, this one
  /// whether the tab's pixels may come from an image at all. The timesheet
  /// says no to the first — its playhead would stand the bake down for the
  /// whole of playback — and has no reason to say no to this one.
  ///
  /// The canvas says no (유저 2026-09-25, raster-cache-when-still-Q1): it is
  /// the one surface whose pixels may never move —
  /// 「결과 절대 바뀌면 안되는건 캔버스뿐임」.
  final bool stillRaster;

  /// Whether the content stands off the edges its group's splitters lie on
  /// ([DockSplitterEdges]), so a scrollbar on such an edge is not under the
  /// band. Defaults to ON.
  ///
  /// 🗣️F-452 (유저 2026-10-23): 「타임라인/콘티패널은 예외. 겹치는게
  /// 세로스크롤바인데 여긴 애초에 큰 스크롤바 써서 신경안쓰이고 공간 안주는게
  /// 세련되보임」.
  final bool sparesSplitters;

  // ↩️A tab put its own controls on the group's 문턱 here (`sillTrailing`,
  // 유저 확정 2026-08-10): the frame panels' transport and settings pill,
  // right-aligned ahead of the group's own [EditorPanelTabs.trailing]. The
  // settings went to the top strip and the transport to the head of the
  // panel's own bar (F-111-Q1, 10-08) — its right group from F-463, its
  // left group's head since F-491 — and no tab put anything there.

  /// How tall this panel needs to be when the region is COLLAPSED — see
  /// [PanelCollapsedScope] for why the shell owns this at all.
  ///
  /// Zero means the honest thing: the panel has nothing to say at that size,
  /// so the shell shows NOTHING and the region is its sill alone (유저 확정
  /// for 콘티·뷰어: 「진짜 깔끔하게 내용물 안 보이게」). The frame panels ask
  /// for their command bar's height and keep working while folded.
  final double collapsedExtent;

  /// Whether this panel is a CANVAS-BASE panel — one whose content is a
  /// canvas panel standing on the canvas base (`BrushCanvasPanel
  /// .canvasBase`): the sheets and the viewers.
  ///
  /// 🗣️I-147 (유저 2026-10-30): 「캔버스베이스 패널들. 즉 콘티용지나
  /// 타임시트나 컷봉투나 서브뷰어나 이런것들. 상단띠 통해 배경에 깔수있게」 —
  /// these, and only these, may lie on the floor: they are what the top
  /// strip's floor buttons hold.
  final bool canvasBase;

  /// What this tab's content is built FOR — null for a tab whose builder
  /// is the same whatever happens. The open content ([OpenTabContent]) is
  /// handed back only while this stays the same; see [builtFor].
  final Object? contentIdentity;

  /// This tab with what it builds keyed by [identity], so it is made again
  /// whenever that changes and never carries its State across it, the
  /// content cache included ([contentIdentity]).
  EditorPanelTab builtFor(Object identity) {
    final key = ObjectKey(identity);
    return EditorPanelTab(
      id: id,
      label: label,
      icon: icon,
      builder: (context) => KeyedSubtree(key: key, child: builder(context)),
      buttonKey: buttonKey,
      minContentWidth: minContentWidth,
      minContentHeight: minContentHeight,
      locked: locked,
      staticRaster: staticRaster,
      stillRaster: stillRaster,
      sparesSplitters: sparesSplitters,
      collapsedExtent: collapsedExtent,
      canvasBase: canvasBase,
      contentIdentity: identity,
    );
  }
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
/// LOCKED tabs ([EditorPanelTab.locked]) refuse to lift.
class EditorPanelTabs extends StatefulWidget {
  const EditorPanelTabs({
    super.key,
    required this.tabs,
    required this.activeTabId,
    required this.onTabSelected,
    this.compact = false,
    this.chromeless = false,
    this.stripAtBottom = false,
    this.stripEdgeOutline = 0,
    this.trailing,
    this.groupId,
    this.onTabMoved,
    this.canAcceptTab,
    this.onTabDragChanged,
    this.draggingTab,
    this.collapsed = false,
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

  /// The width of an outline the host draws OVER the strip's outer edge —
  /// the floating region's ring, which is painted on top of what the region
  /// holds. The tabs' grip bands stand that far in from the edge.
  ///
  /// 🗣️F-257 (유저 2026-10-02): 「바닥 도킹 패널만 탭 띠가 표시안됨. 규칙/법
  /// 통일」, and where (2026-10-08): 「밑 도킹영역인 지금으로치면
  /// 타임라인패널이나 콘티패널이 있는곳. 그 곳의 패널 버튼만 버튼에 호버해야
  /// 드래그가능한 회색 띠가 뜸. 다른 사이드띠 패널들은 패널 안에 들어가기만하면
  /// 띠가 뜨는데」.
  ///
  /// 🔬Measured (2026-10-08, the app's own pixels): the band DID take its
  /// ink the moment the pointer entered that panel, like every dock's — and
  /// could not be seen. A resting band is two pixels on the strip's outer
  /// edge; in the floating region that edge is the region's outline, so the
  /// ring covered one of the two and dimmed the other. Only the reaching
  /// band — six pixels, under the pointer — rose clear of it.
  final double stripEdgeOutline;

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
  /// What the content area holds: the open tab's content, as its region
  /// shows it — nothing at all when the region is folded and the tab has no
  /// folded form. Built once while the tab stays open ([OpenTabContent]).
  ///
  /// 🚨★★★A PANEL IS BUILT ONLY WHILE IT SHOWS (유저 2026-10-14: 「한번이라도
  /// 열린 뒤? 열려있을때만 지어지는게 맞는구조 아닌가?」 · 「이건 모든 패널
  /// 공통적인 사항이야」). ↩️A heavy tab used to stay mounted OFFSTAGE once
  /// opened (R10-②, so a switch back was instant), and offstage still builds
  /// and lays out: 🔬in the I-57 playback census (10-14) the timeline kept
  /// behind the storyboard was 65% of every film frame's rebuilds — its
  /// grid turning pages for a playhead nobody could see. What must outlive a
  /// switch lives above the tab group; a gate that stood a hidden panel down
  /// (R12-①) has nothing left to stand down.
  ///
  /// 🚨결정 3 (유저 2026-08-22, 세 번째 요청) — **A TICKER RUNS WHERE THE PANEL
  /// SHOWS.**
  ///
  /// > 「아직도 접기 직전의 인덱스 상태 기준으로 활성/비활성 **색**. **내부
  /// > 로직 자체는 제대로 작동**하니 **겉모습만** 갱신 안 되는 듯. 그리고
  /// > **3번째 말하는 것 같은데** 접고나서 **버튼 호버시 바탕 흰색** 되는 게
  /// > 사라진다」
  ///
  /// ⛔The mute that kept it read `&& !widget.collapsed`, which muted a tab
  /// that had DECLARED a folded form — a surface still on screen. Every
  /// `IconButton`'s colour crosses an `AnimatedTheme` and every hover wash is
  /// an `InkHighlight` fade; both are driven by tickers, so both froze at the
  /// value they held when the fold happened. Built only where it shows, a
  /// panel has no ticker to mute: ⛔put no `TickerMode` around a tab here.
  Widget? _contentOf(EditorPanelTab active) {
    if (widget.collapsed && active.collapsedExtent <= 0) {
      return null;
    }
    return _onItsFloor(
      active,
      OpenTabContent(
        tabId: active.id,
        identity: active.contentIdentity,
        build: () => _bake(active, Builder(builder: active.builder)),
      ),
    );
  }

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
    final content = _contentOf(active);

    final strip = _strip(context, colorScheme, tabs);

    return MouseRegion(
      opaque: false,
      onEnter: (_) => _panelHovered.value = true,
      onExit: (_) => _panelHovered.value = false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (strip != null && !widget.stripAtBottom) strip,
          // The content area shares the selected tab's background so the tab
          // reads as part of the panel, not a floating chip above it.
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
                    if (content != null)
                      KeyedSubtree(
                        key: ValueKey<String>('panel-content-${active.id}'),
                        // OUTSIDE the cached content on purpose: that
                        // instance never changes, and an inherited
                        // dependency marks its dependents dirty directly —
                        // so a fold reaches the panel without dropping the
                        // cache.
                        child: Padding(
                          // Mounted whether it pads or not: a panel moved
                          // between rails changes how far it stands off,
                          // never what it sits in (F-103's one tree shape).
                          padding: active.sparesSplitters
                              ? DockSplitterEdges.of(context)
                              : EdgeInsets.zero,
                          child: PanelCollapsedScope(
                            collapsed: widget.collapsed,
                            child: content,
                          ),
                        ),
                      ),
                    if (widget.flash != null) _flashOverlay(tabs),
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

  /// The tab strip — none when chromeless: the tail drop region, the
  /// seam, the tab buttons that fit (an overflow button holds the rest),
  /// and the sill's trailing controls.
  Widget? _strip(
    BuildContext context,
    ColorScheme colorScheme,
    List<EditorPanelTab> tabs,
  ) {
    // A link in the chain to the RAIL-DOCKED canvas: everything in the
    // panel below this strip starts at this height, and a docked canvas is
    // one of those things. 30 × 1.25 = 37.5 — unlike the 48s in the window
    // chain, this one is off the grid at Windows' own scaling steps, and it
    // is measurably what held the second canvas boundary off at every ratio
    // while the editing canvas was already clean.
    final height = DeviceGrid.of(context).position(EditorPanelTabs.stripHeight);
    return widget.chromeless
        ? null
        : SizedBox(
            height: height,
            // 🚨The strip is a TICK LAYER. ↩️(I-22 ③) The sill carried the
            // transport, whose readouts move on a tick — the level meter on
            // every frame played, the drop count on every frame missed —
            // and rebuilt bare they laid out the workspace floor and
            // repainted the PAGE on every playback frame; F-111 took the
            // transport to its panel's bar. What keeps the layer now is the
            // strip's own changes: a hovered tab is drawn live over the
            // region's image ([StillRaster]) rather than taking it again —
            // 🔬a hover in and out took the bottom region's image three
            // times without the layer, once with it (10-24, test app).
            child: TickLayer(
              child: Stack(
                children: [
                  // 🚨The strip's ground is painted INSIDE the layer (10-27,
                  // F-244-drag-start ③). Painted around it, it went into the
                  // region's own picture after the panel above — a picture
                  // whose bounds are the whole region — and held the part of
                  // the region's image above the timeline's moving cursor at
                  // the region's full height.
                  Positioned.fill(
                    child: ColoredBox(color: colorScheme.surfaceContainerLow),
                  ),
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
                  // ★ONE row, not a Stack overlay (2026-08-10). The trailing
                  // group used to be `Align`ed over the tabs and the tab count
                  // guessed 32px of room for it — which was fine while it held
                  // one chevron and wrong the moment the sill grew a transport
                  // and a settings pill. The row lays the trailing group out
                  // first and hands the tabs what is left ([KeptTailRow]), so
                  // the tab count is measured against the room that actually
                  // exists and cannot drift from what the trailing group costs.
                  //
                  // ⑪ 유저 2026-08-12: 「타임라인 문턱에 있는 재생이나
                  // 설정버튼 왜 우측정렬안했지? 말한것들좀 지키자.」 The tabs
                  // take ALL the room the group leaves, which pins the group
                  // to the right edge — the entire reason it was put there
                  // (유저 2026-08-10: 「왼쪽 정렬이면 패널을 추가할 때 재생
                  // 버튼이 밀린다」). ↩️A loose `Flexible` was only as wide as
                  // the tabs inside it, so the group sat immediately after
                  // them — reading as left-aligned, and sliding sideways every
                  // time a tab was added.
                  //
                  // A strip too narrow for the group and one tab shows the
                  // group whole, smaller, and the tabs keep one tab's place:
                  // the overflow button, the one way to them. ↩️The group was
                  // laid out past the strip's end, and the button cut at the
                  // room's edge (09-25) — 10px over at 340 (2026-10-15),
                  // while the frame panels' transport stood on the sill and
                  // took nearly a rail's whole width.
                  KeptTailRow(
                    headKeeps: EditorPanelTabs._tabExtent,
                    head: LayoutBuilder(
                      builder: (context, constraints) {
                        // How many fit. The overflow button costs one slot,
                        // so it only appears when it actually buys room.
                        final fits =
                            (constraints.maxWidth / EditorPanelTabs._tabExtent)
                                .floor();
                        final overflowing = fits < tabs.length;
                        final shown = overflowing
                            ? math.max(0, fits - 1)
                            : tabs.length;
                        return Row(
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
                    tail: SizedBox(
                      height: height,
                      child: _buildSillTrailing(),
                    ),
                  ),
                ],
              ),
            ),
          );
  }

  /// The reveal blink (UI-R17 #5): fires when the flash channel names a
  /// tab this group hosts.
  Widget _flashOverlay(List<EditorPanelTab> tabs) => Positioned.fill(
    child: IgnorePointer(
      child: ValueListenableBuilder<PanelFlashRequest?>(
        valueListenable: widget.flash!.requests,
        builder: (context, request, _) {
          if (request == null || !tabs.any((tab) => tab.id == request.tabId)) {
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
  );

  /// The sill's right-hand group ([EditorPanelTabs.trailing]).
  ///
  /// ★It gets out of the way while a tab is in flight. The whole strip is a
  /// drop target ([_TabStripTailDropRegion] carpets it), so anything sitting
  /// on it is eating landing area. Fading it out is not decoration: it hands
  /// the sill back to the drag for exactly as long as the drag lasts.
  /// ↩️(Put in when the group held a transport and a pill beside its
  /// chevron, 2026-08-10 — F-111 took them off the sill.)
  Widget _buildSillTrailing() {
    final group = widget.trailing;
    if (group == null || group.isEmpty) {
      return const SizedBox.shrink();
    }
    final row = Row(mainAxisSize: MainAxisSize.min, children: group);
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

  /// Wraps [child] in the panel bake unless the tab opted out.
  ///
  /// ★THE funnel every docked panel passes through ([_contentOf]), and
  /// therefore the only place the "a panel is light unless it says
  /// otherwise" rule can live. See [EditorPanelTab.staticRaster].
  ///
  /// ⚠️Innermost, under the floor's scrollers ([_onItsFloor]), and that
  /// placement is not cosmetic. The scrollers put the panel inside a
  /// `SingleChildScrollView`, and a viewport IS a repaint boundary — so a
  /// bake around the outside would find one, stand down, and the panel
  /// would silently go back to paying full raster price. It would do that
  /// only when the dock is narrow enough to overflow, which means the cost
  /// would appear and disappear as the user drags a splitter, and no test
  /// that pumps a single window size would ever see it.
  Widget _bake(EditorPanelTab tab, Widget child) {
    if (!tab.staticRaster) {
      return child;
    }
    return StaticRaster(debugLabel: 'panel:${tab.id}', child: child);
  }

  /// [content] on [tab]'s floor: a panel with a minimum content size
  /// larger than the dock renders at that size inside scrollers.
  ///
  /// 🚨THE FLOOR IS THE TAB'S AS IT STANDS — read here, round the open
  /// content and never inside it, which is handed back as first built
  /// ([OpenTabContent]). A floor is measured in words at the OS's text size,
  /// and the timeline's in its orientation. ↩️ca4b75959 kept the scrollers
  /// with the content: the OS text size doubled under a running app left
  /// the colour panel on its 1× floor, and its status bar overflowed 52px
  /// (master_check, 2026-10-24).
  Widget _onItsFloor(EditorPanelTab tab, Widget content) {
    if (tab.minContentWidth == null && tab.minContentHeight == null) {
      return content;
    }
    // 🚨ONE TREE SHAPE whether the dock fits the panel or not, open or folded
    // (F-103, 유저:
    // 「뷰어패널 파일 연 상태에서, 해당 띠의 다른 패널 열거나 닫거나 하면 …
    // 보이던 그림같은게 사라졌다가 생김 … 뷰어패널이 아니라 다른 패널을
    // 열고닫는게 뷰어패널에 영향있다는뜻」). The scrollers used to be
    // mounted only on the axis that overflowed, so a neighbour opening or
    // closing — which moves the dock across the panel's floor — changed the
    // parent chain and the panel's State was new: the viewer read its file
    // again. A fold did the same from its own bare branch. Both scrollers
    // are always there now ([OverflowScrollers]), and a fold only drops the
    // floor, so crossing the floor or folding changes how far they scroll,
    // never what the panel sits in. Whether a tab has a floor at all is its
    // id's, so the shape holds from build to build. The bake stays
    // innermost ([_bake]).
    return Builder(
      builder: (context) {
        // ★A COLLAPSED panel never meets its floor. The floor is what
        // turned folding into cropping: it takes "the dock is smaller than
        // my floor" and answers "then lay out at the floor and let them
        // scroll", which is right for a frame panel squeezed into a side
        // rail and exactly wrong here — the panel has already been told to
        // render a form that fits, and laying that form out at the floor
        // would give it back a height it did not ask for.
        //
        // The fold is read HERE, through the scope, and not where the tab's
        // content is built: the open content ([OpenTabContent]) is built
        // once, so a fold decided there held whatever its first
        // build saw (F-103). [content] is built OUTSIDE this builder, so a
        // fold rebuilds the scrollers and not the panel.
        final folded = PanelCollapsedScope.of(context);
        return OverflowScrollers(
          minWidth: folded ? 0 : tab.minContentWidth ?? 0,
          minHeight: folded ? 0 : tab.minContentHeight ?? 0,
          child: content,
        );
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
      edgeOutline: widget.stripEdgeOutline,
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
    final box = context.findRenderObject()! as RenderBox;
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
class _PanelTabButton extends StatelessWidget {
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
    required this.edgeOutline,
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

  /// How far in from the strip's outer edge the band stands — the width of
  /// an outline drawn over that edge ([EditorPanelTabs.stripEdgeOutline]).
  final double edgeOutline;

  /// What this tab carries when lifted; null for locked tabs and
  /// non-draggable groups, which keep the zone's footprint and never arm.
  final EditorPanelTabDragData? dragData;
  final ValueChanged<EditorPanelTabDragData?>? onTabDragChanged;

  // ⛔The three numbers and the colour ladder LEFT this class (2026-08-10):
  // they are [GripBand] now, because the command pill's `＋` wears the same
  // band along its own top edge to open its list of kinds. A second copy of
  // 「2px for a state, 6px for a handle, and the target is 8 either way」 is
  // exactly the drift this repo keeps paying for.

  /// The tab's silhouette: rounded on the edge AWAY from the panel body,
  /// square where it meets it.
  RoundedSuperellipseBorder _shape() => AppShapes.containerRadius(
    stripAtBottom
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
    final foreground = selected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    // The app's one lifting band ([LiftingGripBand]) — the strip's buttons
    // wear it too (I-147).
    final grip = LiftingGripBand<EditorPanelTabDragData>(
      gripKey: gripKey,
      data: dragData,
      // Every drag's chip, hung where every drag hangs it (I-39) — this
      // one sat centred on the pointer, a look of its own.
      feedback: DragChip(items: [(icon: icon, label: label)]),
      nearby: panelHovered,
      atBottom: stripAtBottom,
      edgeOutline: edgeOutline,
      onLifted: onTabDragChanged,
    );

    return AppTooltip(
      message: label,
      // Manual trigger: hover tooltips still work, but no long-press
      // recognizer competes with drag lifts.
      triggerMode: TooltipTriggerMode.manual,
      // ⛔No MouseRegion of its own any more: the band's first rung is the
      // PANEL being hovered, not this button, and the InkWell already
      // paints its own hover for the button itself.
      child: ControlPressClaim(
        onPressed: onPressed,
        child: InkWell(
          mouseCursor: AppCursors.press,
          onTap: silentPress(onPressed),
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
                    color: selected
                        ? colorScheme.surface
                        : Colors.transparent,
                    shape: _shape(),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 16, color: foreground),
                      if (locked) ...[
                        const SizedBox(width: 3),
                        Icon(Icons.lock, size: 9, color: colorScheme.primary),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: stripAtBottom ? null : 0,
                  bottom: stripAtBottom ? 0 : null,
                  child: grip,
                ),
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
