part of '../editor_workspace.dart';

/// The WORKSPACE DOCKS — where a panel tab may dock, the edge, bottom and
/// centre docks the workspace builds, the bottom dock's height and its
/// collapse, and the rail buttons — as their own object.
///
/// 🚨A collaborator carved out of `_EditorWorkspaceState` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: nine State members shared,
/// the layout model above all. It reaches the State through `_state` and
/// rebuilds through `_rebuild`.
class _WorkspaceDocks {
  _WorkspaceDocks(this._state);

  final _EditorWorkspaceState _state;

  /// The first EMPTY slot of a rail, or null when the pool is full. This is
  /// where a panel dropped on the rail's "new group" target lands.
  String? _emptyRailSlot({required bool right}) {
    for (final id in _EditorWorkspaceState._railSlotIds(right: right)) {
      if (_state._layout.tabsIn(id).isEmpty) {
        return id;
      }
    }
    return null;
  }

  void _toggleTabLock(String tabId) {
    _state._rebuild(() {
      if (!_state._lockedTabIds.remove(tabId)) {
        _state._lockedTabIds.add(tabId);
      }
    });
    _state._layoutPersistence.scheduleLayoutSave();
  }

  bool _canDockAccept(String dockId, EditorPanelTabDragData data) {
    // The slim edge docks only host narrow-fit panels (the tool bar);
    // everything else docks anywhere.
    if ((dockId == EditorWorkspace.toolLeftGroupId ||
            dockId == EditorWorkspace.toolRightGroupId) &&
        !_EditorWorkspaceState._edgeDockTabIds.contains(data.tabId)) {
      return false;
    }
    return _state._layout.canMoveTab(tabId: data.tabId, toDockId: dockId);
  }

  /// A dock's stacked sections with the PS/AE-style drop feedback.
  Widget buildDockHost(
    String dockId, {
    bool compact = false,
    bool chromeless = false,
    bool stripAtBottom = false,
    List<Widget>? trailing,
    bool collapsed = false,
  }) {
    return EditorDockHost(
      chromeless: chromeless,
      stripAtBottom: stripAtBottom,
      trailing: trailing,
      collapsed: collapsed,
      layout: _state._layout,
      dockId: dockId,
      tabResolver: _state._tabFor,
      draggingTab: _state._draggingTab,
      compact: compact,
      canAcceptTab: (data) => _canDockAccept(dockId, data),
      onTabSelected: (tabId) => _state._mutatingLayout(() {
        _state._layout.selectTab(dockId, tabId);
      }),
      onTabMoved: (data, insertIndex) => _state._mutatingLayout(() {
        _state._layout.moveTab(
          tabId: data.tabId,
          toDockId: dockId,
          insertIndex: insertIndex,
        );
      }),
      onTabDragChanged: (data) => _state._draggingTab.value = data,
      onToggleLock: _toggleTabLock,
      onCloseTab: _state._closeTab,
      flash: _state._panelFlash,
    );
  }

  void _dropIntoEmptyDock(String dockId, EditorPanelTabDragData data) {
    _state._mutatingLayout(() {
      _state._layout.moveTab(
        tabId: data.tabId,
        toDockId: dockId,
        insertIndex: 0,
      );
    });
    _state._ensureRailOpen(dockId);
  }

  EditorDockDropZone _emptyDockZone(
    String dockId,
    Axis axis, {
    bool expandToFill = false,
  }) {
    return EditorDockDropZone(
      dockId: dockId,
      axis: axis,
      draggingTab: _state._draggingTab,
      canAcceptTab: (data) => _canDockAccept(dockId, data),
      expandToFill: expandToFill,
      onDropped: (data) => _dropIntoEmptyDock(dockId, data),
    );
  }

  /// A workspace STRIP: 48px of buttons down one edge.
  ///
  /// One of the two also holds the tool column (whichever [dockId] the
  /// `tools` tab currently lives in — the left-handed switch moves it); the
  /// other is the SUB-STRIP, which used to be an empty 0px dock. Both carry
  /// the same thing underneath: one button per rail GROUP, which opens and
  /// closes that group's column beside the strip.
  Widget buildEdgeDock(String dockId, EditorPanelDockSide side) {
    final right = side == EditorPanelDockSide.right;
    final hasTools = _state._layout.tabsIn(dockId).isNotEmpty;
    final groups = _state._railGroups(right: right);
    final emptySlot = _emptyRailSlot(right: right);
    if (!hasTools && groups.isEmpty && emptySlot == null) {
      return _emptyDockZone(dockId, Axis.vertical);
    }
    return EditorPanelDock.filled(
      side: side,
      // The THIRD link in the window-origin chain: this strip decides the
      // x the canvas starts at. 48 is on the grid at every Windows scaling
      // step (48 = 16x3) and off it the moment a UI scale makes the ratio
      // a product.
      width: DeviceGrid.of(_state.context).position(ToolsPanel.dockWidth),
      dockId: dockId,
      // 고정 도킹 (유저 확정): the strip renders with NO panel frame — no tab
      // name, no lock, no X, no grip. It holds what it holds, and a header
      // over a column of buttons is a title for something that needs no
      // title. Every other dock keeps its strip.
      //
      // Baked, and this one is in the FLOOR: the two strips are the only
      // chrome that survives every rung of the ladder, including "every
      // panel closed" — which measured 2.5–3.6 ms/frame with nothing on
      // screen but them, the top strip and an empty canvas. Dozens of
      // icon buttons and swatches, re-executed on the GPU for a pointer
      // that moved over the canvas. Hover and selection dirty it, and
      // that is exactly when it should re-bake.
      child: StaticRaster(
        debugLabel: 'edge-dock:$dockId',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The tool column is rendered as CONTENT, not through a dock host.
            // A host fills whatever it is handed — that is right for a panel
            // and wrong for a strip, and it is why the group buttons under the
            // tools sat at the far end of the tool strip while the sub-strip's
            // sat at the top. Both strips read from the top down now, which is
            // the only way they read as one family.
            if (hasTools)
              Flexible(
                child: Builder(
                  builder: (context) => _state
                      ._tabFor(_state._layout.tabsIn(dockId).first)
                      .builder(context),
                ),
              ),
            // 도구툴그룹밑에도 (유저, R3 #15). The tool column already ends its
            // history cluster with one of these; the panel buttons under it
            // are a third kind of thing and were the only seam on the strip
            // with nothing marking it.
            if (hasTools && (groups.isNotEmpty || emptySlot != null))
              _stripDivider(_state.context),
            _buildRailButtons(
              right: right,
              groups: groups,
              emptySlot: emptySlot,
            ),
          ],
        ),
      ),
    );
  }

  /// The rule between the tool column and the panel buttons under it,
  /// indented to the same left edge the buttons on both sides of it use.
  Widget _stripDivider(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 3),
    child: ToolsPanel.groupDivider(context),
  );

  /// The rail's group buttons.
  ///
  /// 띠는 스크롤하지 않는다 (유저 확정): a strip that scrolls hands drags to
  /// its scroll arena before the buttons ever see them, and dragging a
  /// panel ONTO a button is how a group is made. So the column is plain —
  /// eight slots is the pool, and eight 42px buttons fit any window tall
  /// enough to draw in.
  Widget _buildRailButtons({
    required bool right,
    required List<String> groups,
    required String? emptySlot,
  }) {
    return ValueListenableBuilder<EditorPanelTabDragData?>(
      valueListenable: _state._draggingTab,
      builder: (context, dragging, _) {
        return Padding(
          padding: const EdgeInsets.only(left: 3, top: 4, bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final railId in groups) ...[
                _RailGroupButton(
                  railId: railId,
                  open: _state._openRails.contains(railId),
                  tabs: [
                    for (final tabId in _state._layout.tabsIn(railId))
                      _state._tabFor(tabId),
                  ],
                  // The COLOUR group's button is the swatch itself. The
                  // strip's swatch was the one place the two colours you
                  // paint with were readable without opening anything, and
                  // moving the picker to a rail would have taken that with
                  // it — so the button that opens the picker shows them,
                  // and tapping the back slot still swaps (⛔there is no
                  // swap glyph: that would be the same verb twice).
                  face: _state._colorRailFace(railId),
                  dragging: dragging,
                  onPressed: () => _state._toggleRailGroup(railId),
                  onTabDropped: (data) =>
                      _state._dropIntoRailGroup(railId, data),
                ),
                const SizedBox(height: 4),
              ],
              // The one empty slot on offer, and only while something is in
              // flight: a permanently visible "+" would be a button that
              // does nothing until you happen to be dragging.
              if (emptySlot != null && dragging != null)
                _RailGroupButton(
                  railId: emptySlot,
                  open: false,
                  tabs: const [],
                  dragging: dragging,
                  onPressed: null,
                  onTabDropped: (data) =>
                      _state._dropIntoRailGroup(emptySlot, data),
                ),
            ],
          ),
        );
      },
    );
  }

  /// The canvas keeps at least this much of the workspace's height, the
  /// way [minCenterWidth] keeps it width against the side docks. The bottom
  /// dock had no such guard, and the floor this round added is a force that
  /// GROWS it — without a ceiling a few stacked sections would push the
  /// canvas to zero and then refuse to shrink back.
  static const double _minCenterHeight = 120;

  /// What the window can spare for the bottom dock: everything but the
  /// canvas's own minimum and the splitter between them.
  ///
  /// ONE helper, read by BOTH the render clamp and the splitter's stop. The
  /// first round of this change wrote those two from different premises —
  /// one capped at the model's maximum, the other capped at nothing — and
  /// they agreed only in the default configuration.
  double bottomDockCeiling(double availableExtent) {
    if (!availableExtent.isFinite) {
      return double.infinity;
    }
    return math.max(
      0.0,
      availableExtent - _minCenterHeight - DockEdgeSplitter.thickness,
    );
  }

  /// 🚨결정 8: 「하단 = **화면 절반**까지」 — how far the dock may be DRAGGED,
  /// and how tall it OPENS. The number the user gave was never in the code
  /// as a limit; it lived only in the opening fallback.
  ///
  /// ⚠️Deliberately NOT [bottomDockCeiling]. That one answers a different
  /// question — what the WINDOW can physically spare — and the dock's own
  /// minimum (the height its panels need to render at all) is measured
  /// against it. Folding half the window into that answer squeezed panels
  /// below their floor on any window taller than twice the timeline's
  /// minimum, which is most of them; measured, it took a row of lanes off
  /// two test surfaces that had nothing to do with dock size.
  ///
  /// ★A ceiling on the HAND is not a licence to under-draw. Half the window
  /// is where a drag stops; a panel that needs more than that to exist at
  /// all still gets what the window can spare.
  double bottomDockDragCeiling(double availableExtent) {
    if (!availableExtent.isFinite) {
      return double.infinity;
    }
    return math.max(
      0.0,
      math.min(
        availableExtent * EditorWorkspace.bottomDockCeilingFraction,
        bottomDockCeiling(availableExtent),
      ),
    );
  }

  /// The collapsed floating region: its 문턱 plus whatever the ACTIVE tab
  /// says it needs at that size ([EditorPanelTab.collapsedExtent]).
  ///
  /// Collapsed is not CLOSED — 유저 확정. The region stays on screen, keeps
  /// its threshold, and keeps taking drops; it just stops asking for a
  /// third of the drawing.
  ///
  /// ⛔It used to be a flat 70. That number was a guess at "the sill plus a
  /// brief line of whatever is open", and the panel was never told about it:
  /// the dock simply handed it 40px over a 136px floor, the shell's overflow
  /// branch put it in a scroller at its natural height, and what showed was
  /// the top of it — the command bar and four pixels of grid. Asking the tab
  /// is what turns that crop into a representation, and it is also what lets
  /// a tab with nothing to say at that size collapse to its sill alone
  /// (유저 확정 for 콘티·뷰어).
  double _collapsedBottomHeight() {
    final tabId = _state._layout.activeTabIn(EditorWorkspace.bottomGroupId);
    final extent = tabId == null ? 0.0 : _state._tabFor(tabId).collapsedExtent;
    return EditorPanelTabs.stripHeight + math.max(0.0, extent);
  }

  /// How tall the bottom panel is drawn — read by the layout that positions
  /// it AND by the cover the floor is told about, so the panel and the hole
  /// it makes in the artwork can never disagree.
  double bottomDockHeight(double availableExtent) {
    if (_state._bottomDockCollapsed) {
      // Through the same ceiling as the open height: collapsed is smaller,
      // but in a window short enough for even that to crowd the drawing out
      // it is still the window that decides.
      return math.min(
        _collapsedBottomHeight(),
        math.max(0.0, bottomDockCeiling(availableExtent)),
      );
    }
    // Clamped on the way OUT as well as on the drag: a workspace saved
    // before this floor existed, or one whose bottom dock gained a taller
    // tab since, must still open at a height its panels fit in.
    // D37: half the window when nothing has been dragged (유저 원문:
    // 「타임라인 세로 = 화면 절반」). A dock the user HAS sized keeps its
    // pixels — see [sideDockWidthFraction] for why a fraction is the
    // opening and not a binding.
    // ⛔결정 8 did NOT clamp HERE, and the attempt is left recorded because
    // it looked obviously right and was not: 「하단 = 화면 절반까지」 limits
    // the HAND, and capping this expression at a bare half changed a dock
    // whose panels need more than half to render at all — that dock then
    // drew under its own floor. Measured: it took a row of lanes off two
    // test surfaces that never touch dock size.
    //
    // 🆕H22 (유저 2026-08-23): 「타임라인패널 크기 키워둔채로 창 크기
    // 축소하면 **그 크기 그대로 유지**되어있음. 창 크기 바꾸면 사이드띠의
    // 패널이랑 통일해서 비율대로 작아져야하는데」 — so the half DOES bind on
    // the way out. It is what the side rails have always done (their 37.5%
    // ceiling is applied where they are drawn, not only where they are
    // dragged), and this dock being the one exception is the report.
    //
    // ★Both readings hold at once because the floor is folded into the
    // ceiling rather than left underneath it: the half stops a DRAGGED
    // height from surviving a window that shrank, and a dock that needs
    // more than half to exist at all is still never squeezed below what it
    // needs. 결정 8's failure mode was a ceiling that could win against the
    // floor; this one cannot.
    final floor = _state._verticalDockMinimumExtent(
      EditorWorkspace.bottomGroupId,
    );
    final opening = EditorWorkspace.bottomDockHeightFallbackFor(
      availableExtent,
      DeviceGrid.of(_state.context),
    );
    // ★The half binds a DRAGGED height and nothing else, and that is the
    // whole difference between this and the attempt 결정 8 rejected. An
    // opening is already computed from the window in front of us; clamping
    // it again is what squeezed a dock under its own floor. A dragged
    // height was chosen in a window that may be gone, so it is the one that
    // has to answer to the window that is here.
    final wanted = math.max(
      _state._layout.hasDockExtent(EditorWorkspace.bottomGroupId)
          ? math.min(
              _state._layout.dockExtent(
                EditorWorkspace.bottomGroupId,
                fallback: opening,
              ),
              bottomDockDragCeiling(availableExtent),
            )
          : opening,
      floor,
    );
    // …but never past what the window has. A floor is a promise about how
    // the dock divides its own height, not a claim on someone else's: when
    // the window cannot pay it, the dock yields and the sections share the
    // shortfall ([dockSectionExtents]) with the shell's scroller behind
    // them. The user can always drag their way back out.
    return math.min(wanted, bottomDockCeiling(availableExtent));
  }

  /// The floating region over the canvas: the timeline and the paper panels
  /// it switches between.
  ///
  /// It is a Stack child of this route and NOT an OverlayPortal — an
  /// OverlayPortal's child draws under the next OverlayEntry, so one dialog
  /// would bury the timeline and swallow its clicks. Being a plain child
  /// means it takes pointers over its whole rectangle, which is why the
  /// clip is not decoration: without it the four corners the silhouette cut
  /// away would still eat strokes aimed at the canvas behind them.
  /// The floating region's PANELS — the heavy part, and the part that does
  /// not depend on a single extent.
  ///
  /// Built above the extent builder and handed in, so pulling the region's
  /// edge re-lays the timeline out without rebuilding it (see the note where
  /// it is built).
  Widget buildBottomDockContent({required bool onTop}) => buildDockHost(
    EditorWorkspace.bottomGroupId,
    // 이름 없이 아이콘만 (유저 확정) — the 문턱 says WHICH panel with a
    // glyph and a tooltip. The tab's label is still its only accessibility
    // name, so the names move into the tooltip rather than out of
    // existence.
    compact: true,
    // 정체성은 창틀 향한 변에: the 문턱 rides the edge against the window
    // frame, which is the far side from the artwork — so it flips with the
    // region out of the same law that moved the resize handle.
    stripAtBottom: !onTop,
    trailing: [_bottomCollapseButton(onTop: onTop)],
    collapsed: _state._bottomDockCollapsed,
  );

  Widget buildBottomDock({
    required double availableExtent,
    required Widget? content,
    bool inset = false,
    bool onTop = false,
    List<Widget> grips = const [],
  }) {
    if (content == null ||
        _state._layout.tabsIn(EditorWorkspace.bottomGroupId).isEmpty) {
      return _emptyDockZone(EditorWorkspace.bottomGroupId, Axis.horizontal);
    }
    return DecoratedBox(
      // The ring the palette reserves for exactly this: a floating panel
      // has to end somewhere, and it is lying on a colour the user picked,
      // so no fill of ours can be relied on to contrast with it. Drawn
      // OUTSIDE the clip, or the clip would eat its outer half.
      position: DecorationPosition.foreground,
      decoration: ShapeDecoration(
        shape: _floatingBottomShape(
          inset: inset,
          onTop: onTop,
          side: const BorderSide(color: AppColors.backdrop),
        ),
      ),
      child: SuperellipseClip(
        key: const ValueKey<String>('floating-bottom-region'),
        shape: _floatingBottomShape(inset: inset, onTop: onTop),
        // The height is the layout's to hand out now (see
        // [bottomDockHeight]); the region just fills what it is given.
        //
        // ★The grips are INSIDE this clip (R2 #11). They used to sit
        // outside it, beside the region, which is why hovering one lit a
        // straight bar against a rounded panel: the clip is what makes a
        // grip read as the panel's own edge.
        child: Stack(
          children: [
            Positioned.fill(child: content),
            ...grips,
          ],
        ),
      ),
    );
  }

  /// The silhouette of the floating region.
  ///
  /// A corner that lies ON the window's own edge is square: a rounded one
  /// there would show the scaffold through the notch rather than the
  /// artwork, which reads as a rendering fault rather than as a shape. So
  /// the rule is about where the edges ARE, and it keeps holding when the
  /// region gains its symmetric side inset.
  RoundedSuperellipseBorder _floatingBottomShape({
    bool inset = false,
    bool onTop = false,
    BorderSide side = BorderSide.none,
  }) {
    const radius = Radius.circular(AppShapes.floatingPanelRadius);
    // The corner that lies ON the window's own edge is square; the one
    // facing the artwork is round. Which is which flips with the region's
    // edge, and pulling the sides in rounds the flush pair too, because
    // then they are not touching the frame either.
    final flush = inset ? radius : Radius.zero;
    return AppShapes.containerRadius(
      BorderRadius.vertical(
        top: onTop ? flush : radius,
        bottom: onTop ? radius : flush,
      ),
      side: side,
    );
  }

  Widget _bottomCollapseButton({bool onTop = false}) {
    return AppIconButton(
      keyValue: 'floating-bottom-collapse',
      tooltip: _state._bottomDockCollapsed
          ? AppText.strings.panelExpandRegion
          : AppText.strings.panelCollapseRegion,
      size: AppIconButtonSize.dense,
      onPressed: () {
        _state._rebuild(
          () => _state._bottomDockCollapsed = !_state._bottomDockCollapsed,
        );
        _state._layoutPersistence.scheduleLayoutSave();
      },
      // The chevron points where the region would GO — toward the artwork
      // to open, toward the frame to collapse — so it flips with the edge
      // rather than always meaning "down".
      icon: Icon(
        _state._bottomDockCollapsed == onTop
            ? Icons.keyboard_arrow_down
            : Icons.keyboard_arrow_up,
      ),
    );
  }

  /// The center dock hosts the canvas tab by default. Unlike the edge
  /// docks it always occupies its region — when emptied it stays a
  /// full-size drop surface.
  Widget buildCenterDock() {
    if (_state._layout.tabsIn(EditorWorkspace.centerGroupId).isEmpty) {
      return _emptyDockZone(
        EditorWorkspace.centerGroupId,
        Axis.vertical,
        expandToFill: true,
      );
    }
    // The floor has NO tab strip. Two reasons, and either alone would be
    // enough: the strip would be under the panels floating on it (the left
    // column starts at the floor's own top-left corner, so its first 30
    // pixels are exactly where the tabs used to be), and the switch between
    // the floor's panels has moved to the top strip, where it is reachable
    // whatever is open.
    //
    // Losing the strip also takes the canvas's lock glyph and its X, and
    // that is the protection rather than a hole in it: a surface with no
    // grip cannot be dragged off the floor by a slip of the hand, which is
    // what the default lock was there to prevent.
    return buildDockHost(EditorWorkspace.centerGroupId, chromeless: true);
  }
}
