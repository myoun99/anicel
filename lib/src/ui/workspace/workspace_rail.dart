part of '../editor_workspace.dart';

/// The RAIL — the column of panel groups beside the canvas: its slots,
/// groups and hosts, opening and toggling a group, dropping a tab into
/// one, the history controls and the colour face it carries, and the band
/// it paints — as its own object.
///
/// 🚨A collaborator carved out of `_EditorWorkspaceState` (the audit's SRP cut,
/// 2026-09-02). It reaches the State through `_state` and rebuilds
/// through `_rebuild`.
class _WorkspaceRail {
  _WorkspaceRail(this._state);

  final _EditorWorkspaceState _state;

  /// The slots of one rail, in order, whatever is in them.
  static List<String> _railSlotIds({required bool right}) => [
    for (var slot = 1; slot <= EditorWorkspace.railSlots; slot += 1)
      EditorWorkspace.railGroupId(right: right, slot: slot),
  ];

  /// The slots of one rail that HOLD something — the buttons that exist.
  List<String> _railGroups({required bool right}) => [
    for (final id in _railSlotIds(right: right))
      if (_state._layout.tabsIn(id).isNotEmpty) id,
  ];

  /// The open groups of one rail, in rail order — the column, top to
  /// bottom.
  List<String> openRailGroups({required bool right}) => [
    for (final id in _railGroups(right: right))
      if (_state._openRails.contains(id)) id,
  ];

  void _toggleRailGroup(String railId) {
    _state._rebuild(() {
      if (!_state._openRails.remove(railId)) {
        _state._openRails.add(railId);
      }
    });
    _state._layoutPersistence.scheduleLayoutSave();
  }

  /// The head of the tool rail: undo, redo and the onion toggle — what a
  /// hand reaches for BETWEEN strokes, which is the rail's whole job.
  ///
  /// Undo and redo keep the keys they wore in the top strip
  /// (`undo-button` / `redo-button`); they are old keys and a good number
  /// of tests hold them, so the move costs those tests nothing.
  ///
  /// Wording is borrowed from the action registry by id rather than tabled
  /// again — these three are registry actions, and their names are already
  /// translated for the shortcut dialog.
  Widget _railHistoryControls() {
    final session = _state.widget.session;
    final selection = _state.widget.canvasSelectionCommands;
    return ListenableBuilder(
      listenable: Listenable.merge([
        session,
        session.historyManager,
        session.onionSkinLayerIds,
        // ㉜: the deselect button's enablement is the SELECTION's news, and
        // it arrives on that object's own channel — the selection layer
        // mutates inside builds and gesture handlers, so its notify is
        // microtask-deferred rather than riding a session notify.
        ?selection,
        // 🚨…and the timeline's four kinds, each on its own notifier. The
        // button lets go of ALL FIVE now, so it has to hear all five — it
        // used to answer `hasRegion` alone and could afford to listen to the
        // marquee alone. ⛔A `session` notify does not carry these: they are
        // ValueNotifiers of their own.
        session.frameRangeSelection,
        session.laneRangeSelection,
        session.trackFrameRangeSelection,
        session.rowSelection,
      ]),
      builder: (context, _) {
        final strings = AppText.strings;
        final layer = session.activeLayer;
        // Onion is PER LAYER (the per-layer model retired the master
        // switch), so this button is the active row's onion — the same
        // thing the `O` action toggles, not the legend's bulk sweep.
        final onionOn =
            layer != null && session.onionSkinLayerIds.value.contains(layer.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RailButton(
              keyValue: 'undo-button',
              tooltip: strings.shortcutLabel(EditorActionIds.undo, 'Undo'),
              icon: Icons.undo,
              selected: false,
              onPressed: session.canUndo ? session.undo : null,
            ),
            const SizedBox(height: 4),
            RailButton(
              keyValue: 'redo-button',
              tooltip: strings.shortcutLabel(EditorActionIds.redo, 'Redo'),
              icon: Icons.redo,
              selected: false,
              onPressed: session.canRedo ? session.redo : null,
            ),
            const SizedBox(height: 4),
            RailButton(
              keyValue: 'rail-onion-skin-button',
              tooltip: strings.shortcutLabel(
                EditorActionIds.onionSkinToggle,
                'Toggle Onion Skin',
              ),
              icon: Icons.filter_none_outlined,
              selected: onionOn,
              onPressed: layer != null ? session.toggleOnionSkin : null,
            ),
            // ㉜ (user, 2026-08-12): 「선택 해제 버튼이 없다」. The VERB was
            // already here — `Ctrl+D` runs it — so this is the entrance and
            // nothing else. It sits with undo/redo/onion because it is the
            // same kind of thing: what a hand reaches for BETWEEN strokes.
            //
            // Its wording comes from the action registry by id, like its
            // three neighbours, so the button and the shortcut dialog cannot
            // end up calling it two different names.
            if (selection != null) ...[
              const SizedBox(height: 4),
              RailButton(
                keyValue: 'rail-deselect-button',
                tooltip: strings.shortcutLabel(
                  EditorActionIds.selectionDeselect,
                  'Deselect',
                ),
                icon: Icons.deselect,
                selected: false,
                // Dimmed with nothing selected rather than hidden: a button
                // that comes and goes is one you have to look for.
                //
                // 🚨`hasRegion`, NOT `hasSelection`. The region is a
                // DOCUMENT-level fact and survives tool switches (R28-S);
                // `hasSelection` asks the MOUNTED selection layer, which
                // exists only while a selection tool is active, and answers
                // `false` the moment that layer unbinds. So the button went
                // dead the instant you picked the brush, with the selection
                // still on screen and Ctrl+D still working — 유저: 「다른툴
                // 이동하면 선택중인상태인데도 비활성화되있어」.
                //
                // `hasSelection` keeps its own job: arrow keys nudge instead
                // of flipping frames, and that one really does need a live
                // layer to nudge.
                // 🚨ONE question, and it is the SESSION's — the marquee is
                // one of five selection kinds, and this button is now the
                // only door out of any of them (유저 2026-08-27: 「선택해제
                // 타임라인에 중복으로 존재하는거」 — the pill's copy is gone).
                //
                // ⚠️`hasRegion` alone was right while this cleared only the
                // marquee. It would now light for half of what it does.
                onPressed: session.hasAnySelection
                    ? session.clearAllSelections
                    : null,
              ),
            ],
          ],
        );
      },
    );
  }

  void _toggleLaneGroup(String groupKey) {
    final next = Set<String>.of(_state._expandedLaneGroupKeys.value);
    if (next.remove(groupKey)) {
      // Closing: only this group's MEMBERS go, so the header is what
      // swallows them and where the standing row lands (R5 #11).
      final row = parseLaneGroupKey(groupKey);
      if (row != null) {
        _state.widget.session.handOffCurrentRowOnFold(
          row.layerId,
          laneId: row.laneId,
        );
      }
    } else {
      next.add(groupKey);
    }
    _state._expandedLaneGroupKeys.value = next;
  }

  void _toggleAttachGroup(LayerId baseId) {
    final next = Set<LayerId>.of(_state._collapsedAttachBaseIds.value);
    if (!next.remove(baseId)) {
      next.add(baseId);
      // FOLDING while one of the group's attach rows is active (UI-R24
      // #4): hand the selection to the BASE so the group actually
      // disappears — the active-attach-stays-visible rule otherwise kept
      // the fold from taking effect until some other row was picked.
      final session = _state.widget.session;
      final active = session.activeLayer;
      if (active != null && active.attachedToLayerId == baseId) {
        session.selectLayer(baseId);
      }
    }
    _state._collapsedAttachBaseIds.value = next;
  }

  /// Putting a panel somewhere OPENS that somewhere.
  ///
  /// A rail group can be closed, and a panel placed into a closed one is a
  /// panel that has silently disappeared — the same failure whether it was
  /// dropped there, reopened from the Panels menu, or revealed by a browser
  /// "open". So every path that places a panel comes through here rather
  /// than each remembering on its own.
  void ensureRailOpen(String dockId) {
    if (!dockId.startsWith('rail-') || _state._openRails.contains(dockId)) {
      return;
    }
    _state._rebuild(() => _state._openRails.add(dockId));
    _state._layoutPersistence.scheduleLayoutSave();
  }

  /// Moves the tool strip to the requested edge (the left-handed choice).
  ///
  /// This used to be a tab drag across the workspace. With 고정 도킹 the
  /// tab has no grip, so the choice needed a switch — and it lands in the
  /// LAYOUT, which is already persisted, rather than a new setting file.
  void setToolRailOnRight(bool onRight) {
    final from = onRight
        ? EditorWorkspace.toolLeftGroupId
        : EditorWorkspace.toolRightGroupId;
    final to = onRight
        ? EditorWorkspace.toolRightGroupId
        : EditorWorkspace.toolLeftGroupId;
    final tabs = _state._layout.tabsIn(from);
    if (tabs.isEmpty) {
      return; // Already on the requested edge.
    }
    _state._mutatingLayout(() {
      for (final tabId in tabs) {
        _state._layout.moveTab(
          tabId: tabId,
          toDockId: to,
          insertIndex: _state._layout.tabsIn(to).length,
        );
      }
    });
  }

  /// The dual swatch, when [railId] is the group holding the colour picker.
  ///
  /// Null everywhere else: a rail button says what it holds with the glyph
  /// of its first panel, and this is the one panel whose STATE is the thing
  /// worth saying.
  Widget? _colorRailFace(String railId) {
    final background = _state.widget.colorBackground;
    if (background == null) {
      return null;
    }
    final holdsColor = _state._layout
        .tabsIn(railId)
        .contains(EditorWorkspace.colorWheelTabId);
    if (!holdsColor) {
      return null;
    }
    return SlicedValueListenableBuilder<BrushToolState, int>(
      valueListenable: _state._brushTool,
      slice: (state) => state.color,
      builder: (context, toolState) => ValueListenableBuilder<int>(
        valueListenable: background,
        // Keeps the swatch's long-standing name: it changed address, not
        // identity, and every finder that means "the colour control" says
        // this.
        builder: (context, backgroundColor, _) => ColorSlotPair(
          key: const ValueKey<String>('tool-color-button'),
          keyPrefix: 'tool-color',
          foreground: Color(toolState.color),
          background: Color(backgroundColor),
          // The Photoshop gesture, carried by the BACK SLOT itself.
          onBackgroundTap: () {
            final foreground = _state._brushTool.value.color;
            _state._brushTool.value = _state._brushTool.value.copyWith(
              color: backgroundColor,
            );
            background.value = foreground;
          },
        ),
      ),
    );
  }

  /// A panel dropped on a rail button JOINS that group and opens it —
  /// dropping something out of sight would be a silent move.
  void _dropIntoRailGroup(String railId, EditorPanelTabDragData data) {
    final tabs = _state._layout.tabsIn(railId);
    _state._mutatingLayout(() {
      _state._layout.moveTab(
        tabId: data.tabId,
        toDockId: railId,
        insertIndex: tabs.length,
      );
    });
    _state._rebuild(() => _state._openRails.add(railId));
    _state._layoutPersistence.scheduleLayoutSave();
  }

  /// One rail group's height: what it was left at, floored by what its
  /// panels need and capped by the rail.
  ///
  /// ⚠️Not a share of the rail. The rail used to divide its height between
  /// whatever was open, so opening a second group resized the first —
  /// which is a column's behaviour, not a floating panel's. 유저 확정: the
  /// saved height is FIXED, and a rail that cannot fit them all scrolls.
  double _railGroupHeight(String railId, double railExtent) {
    final floor = _state._verticalDockMinimumExtent(railId);
    final wanted = math.max(
      floor,
      _state._layout.dockExtent(
        railId,
        fallback: EditorWorkspace.railGroupHeight,
      ),
    );
    return railExtent.isFinite ? math.min(wanted, railExtent) : wanted;
  }

  /// The panel HOSTS of one rail, built once per workspace build and handed
  /// to [buildRailColumn] rather than built inside it.
  ///
  /// ★A host does not depend on any extent — only on WHAT is docked — so
  /// building it inside the extent builder made every splitter frame
  /// rebuild every open panel on both rails. Hoisting it means the element
  /// tree sees the identical widget instance and skips the subtree
  /// wholesale, exactly the way the floor rides through as a `child:`.
  Map<String, Widget> railHosts({required bool right}) => {
    for (final id in openRailGroups(right: right))
      id: _state._docks.buildDockHost(id),
  };

  /// The VERTICAL band one rail's column actually occupies, in the floor's
  /// own coordinates — or null when that rail has nothing open.
  ///
  /// A rail panel keeps the height it was left at, so an open rail covers a
  /// band and not a whole edge. Anything deciding whether it is IN THE WAY
  /// has to compare against this rather than against the width alone.
  ({double top, double bottom})? railBand({
    required bool right,
    required double stop,
    required bool onTop,
    required double height,
    required DeviceGrid grid,
  }) {
    final open = openRailGroups(right: right);
    if (open.isEmpty) {
      return null;
    }
    // The band's own top is a link in the chain to a rail-docked canvas:
    // the panel, and anything docked in it, begins here. `stop` is
    // already on the grid, and `position` composes exactly against a
    // snapped anchor — so this carries ONE rounding for the whole thing
    // rather than one for the stop and another for the gap.
    final top = grid.position(
      (onTop ? stop : 0) + _EditorWorkspaceState._railGroupGap,
    );
    final available = math.max(0.0, height - top - (onTop ? 0 : stop));
    // 🚨★★The band has to be laid out by the SAME arithmetic as the
    // column, in the same order, or it describes a rail that is not
    // drawn. The column runs `take(height)` then `take(gap)` per group, so
    // this runs the identical sequence and reads the position after the
    // last HEIGHT — the trailing gap is taken and never counted, exactly
    // as there.
    //
    // ⛔A raw sum here became measurably wrong the moment the column
    // became a run: driven on a height grip, 40 of 40 steps disagreed at
    // 1.125, 1.25 and 1.35, worst 0.98 device px. It reproduced at 1.25,
    // where every other quantization in this round is inert — which is
    // what identified the run conversion as the cause rather than the
    // ratio.
    //
    // ⚠️The two loops are still hand-duplicated: this one measures against
    // `available`, the column against its own `railExtent`. They agree by
    // care rather than by construction, and the honest fix is for the
    // column to publish its geometry — a larger change than this round.
    final run = grid.run(from: top);
    var contentEnd = top;
    for (final id in open) {
      run.take(_railGroupHeight(id, available));
      contentEnd = run.position;
      run.take(_EditorWorkspaceState._railGroupGap);
    }
    final content = contentEnd - top;
    return (top: top, bottom: top + math.min(content, available));
  }

  Widget buildRailColumn(
    EditorPanelDockSide side, {
    required double width,
    required Map<String, Widget> hosts,

    /// D37's "up to ¾ of the centre", resolved against what the OTHER dock
    /// is taking — so the grip stops where the drawn width stops.
    ///
    /// ⚠️Passed in rather than computed here: only the caller knows the
    /// window, and a grip whose ceiling disagreed with the layout's would
    /// spend the drag moving a number nobody draws.
    required double dragCeiling,
  }) {
    final right = side == EditorPanelDockSide.right;
    final open = openRailGroups(right: right);
    if (open.isEmpty) {
      // ⛔NO drop zone beside a closed rail (유저, R4 #7: 사이드에는 어차피
      // 띠에 버튼으로 추가하는거랑 똑같은 기능이니까 필요없다).
      //
      // A tall band appeared here whenever a tab lifted, and it offered
      // nothing the strip did not: `_buildRailButtons` already puts a drop
      // target on every group button AND raises one for the rail's first
      // empty slot for exactly as long as something is in flight. So the
      // band was a second door onto the same room, drawn across a third of
      // the window.
      //
      // The BOTTOM dock keeps its zone (`_buildBottomDock`) and so does an
      // emptied floor (`_buildCenterDock`) — those two have no strip button
      // standing in for them, so removing their band would leave a panel
      // dropped there with no way back.
      return const SizedBox.shrink();
    }
    // NO fill and NO border. A rail is not a container of panels, it is a
    // place panels float beside; anything painted here puts them back in a
    // box and undoes every rounded corner inside it.
    //
    // The box spans the GAP as well as the panels: that strip of pasteboard
    // between the strip and the panels is where the rail's own scrollbar
    // rides (유저, R3 #12), so it has to be inside something that knows
    // whether the rail is scrolling.
    return SizedBox(
      key: ValueKey<String>('editor-panel-dock-${right ? 'right' : 'left'}'),
      width: width + _EditorWorkspaceState._railGroupGap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final colorScheme = Theme.of(context).colorScheme;
          final railExtent = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : double.infinity;
          final heights = [
            for (final id in open) _railGroupHeight(id, railExtent),
          ];
          var content = 0.0;
          for (final height in heights) {
            content += height + _EditorWorkspaceState._railGroupGap;
          }
          content -= _EditorWorkspaceState._railGroupGap;

          // Each open group is its OWN floating object: the app's corner,
          // clipped so the corner is real rather than painted, and a gap of
          // pasteboard between it and its neighbour.
          //
          // ★Its grips live INSIDE that clip, laid along the two edges they
          // resize. The clip is what makes them read as the panel's own edge
          // lighting up rather than as a bar parked beside it — a 5px band
          // cannot carry a 14px corner by itself (유저, R2 #11).
          Widget group(int i) {
            final railId = open[i];
            return SuperellipseClip(
              shape: AppShapes.container(AppShapes.floatingPanelRadius),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: colorScheme.surface,
                        shape: AppShapes.container(
                          AppShapes.floatingPanelRadius,
                        ),
                      ),
                      child: hosts[railId] ?? const SizedBox.shrink(),
                    ),
                  ),
                  // The WIDTH grip, on this panel's inner edge — the edge
                  // facing the artwork. Every group has one and they all
                  // write the rail's single width, so the rail stays one
                  // column wide however many panels are on it.
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: right ? 0 : null,
                    right: right ? null : 0,
                    width: DockEdgeSplitter.thickness,
                    child: DockEdgeSplitter(
                      key: ValueKey<String>('dock-resize-$railId'),
                      axis: Axis.vertical,
                      onDragDelta: (delta) {
                        // ⚠️The sign flip has to be UNDONE on the way back.
                        // A right rail grows as the pointer moves LEFT, so
                        // reporting the width's own delta would hand the
                        // splitter a debt pointing the wrong way — and a
                        // debt with the wrong sign is worse than none: it
                        // would make the edge run ahead instead of behind.
                        final used = _state._layout.resizeDock(
                          EditorWorkspace.railWidthKey(right: right),
                          right ? -delta : delta,
                          fallback: width,
                          maxExtent: dragCeiling,
                        );
                        return right ? -used : used;
                      },
                    ),
                  ),
                  // The HEIGHT grip, on this panel's bottom edge. It costs
                  // no layout, so the gap below stays a gap.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: DockEdgeSplitter.thickness,
                    child: DockEdgeSplitter(
                      key: ValueKey<String>('dock-resize-$railId-height'),
                      axis: Axis.horizontal,
                      onDragDelta: (delta) => _state._layout.resizeDock(
                        railId,
                        delta,
                        fallback: EditorWorkspace.railGroupHeight,
                        minExtent: _state._verticalDockMinimumExtent(railId),
                        // The RAIL is the ceiling, not the model's default
                        // 640: that number guards a width, and a panel's
                        // height here can legitimately be more than it on a
                        // tall window and must be less than it on a short
                        // one. Without this the grip banked height the rail
                        // could never show and then dragged dead on the way
                        // back — measured: 60px of return travel moved the
                        // edge 9px. It is the same defect this round already
                        // fixed for the floating region.
                        maxExtent: railExtent.isFinite ? railExtent : null,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          // The rail's own cumulative chain, and the textbook case for a
          // run: floor each cumulative POSITION and take each extent as
          // the difference of neighbours. ⛔Snapping `heights[i]` and
          // `_railGroupGap` on their own instead would drift — n groups
          // would carry n roundings, all in the same direction, and the
          // last panel would walk off the rail's bottom.
          //
          // ⚠️A gap of 8 is 9 device px at 1.125 and 10.8 at 1.35, so the
          // run legitimately hands back slightly different gaps; that is
          // the residue landing where it must rather than accumulating.
          final children = <Widget>[];
          final run = DeviceGrid.of(context).run();
          for (var i = 0; i < open.length; i += 1) {
            final top = run.position;
            final height = run.take(heights[i]);
            children.add(
              Positioned(
                left: 0,
                right: 0,
                top: top,
                height: height,
                child: group(i),
              ),
            );
            run.take(_EditorWorkspaceState._railGroupGap);
          }

          final column = SizedBox(
            height: content,
            child: Stack(clipBehavior: Clip.none, children: children),
          );
          // The panels themselves keep their own width; the gap beside them
          // is the rail's, and belongs to the strip side.
          // The gap beside the strip. It is a link in the chain to the
          // RAIL-DOCKED canvas — everything inside the rail panel starts
          // after it — and 8 × 1.35 is 10.8, so it is off the grid at
          // exactly the product ratios a UI scale produces.
          final gap = DeviceGrid.of(
            context,
          ).position(_EditorWorkspaceState._railGroupGap);
          Widget inGap(Widget child) => Padding(
            // Keyed so the quantization can be PINNED. It is otherwise
            // unobservable from the canvas: 8 is already integral at
            // 1.125, 1.25 and 1.75, and at 1.35 — the one ratio where it
            // matters — a larger fraction upstream still dominates the
            // rail-docked boundary. Unpinned quantization is quantization
            // that a later edit undoes in silence.
            key: const ValueKey<String>('rail-group-gap'),
            padding: EdgeInsets.only(
              left: right ? 0 : gap,
              right: right ? gap : 0,
            ),
            child: child,
          );
          // 🚨★★★ ONE TREE SHAPE, ALWAYS (R6-⑤, 유저: 「아래스플리터가
          // 조작중에 멋대로 그립이 풀려버림. 클릭중인데도.」)
          //
          // This used to return two DIFFERENT trees — `Padding > Align >
          // column` under the rail's height, `Stack > … > SingleChildScrollView
          // > column` over it. Dragging the bottom height grip changes
          // `content`, so crossing that boundary swapped the trees, element
          // matching failed, and the whole column was rebuilt from scratch —
          // taking with it the State of the very `DockEdgeSplitter` the hand
          // was holding. The grip released itself mid-drag, while the button
          // was still down. The colour wheel and the timesheet hit it because
          // they are tall enough to sit near the boundary.
          //
          // ★The user's rule (넘칠 때만 스크롤) survives for free: a
          // `SingleChildScrollView` whose content fits has min == max extent,
          // and Flutter drops its drag recognizer at that point
          // (`shouldAcceptUserOffset`). So the scroller is always MOUNTED and
          // only sometimes LIVE, which is exactly what was wanted — and the
          // tree stops changing shape under a live gesture.
          final overflowing = railExtent.isFinite && content > railExtent;
          final controller = _state._railScrollControllers[right]!;
          return Stack(
            children: [
              Positioned.fill(
                // ⛔NOT the Material scrollbar. The framework's desktop
                // behaviour puts one on every vertical scrollable, and that
                // one fades out and FATTENS under the pointer — both of
                // which the app's own bar was written not to do (유저: 어떤
                // 레일이든 눌렀다고 크기가 바뀌지 않는다).
                child: inGap(
                  ScrollConfiguration(
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(scrollbars: false),
                    child: SingleChildScrollView(
                      key: ValueKey<String>(
                        'rail-scroll-${right ? 'right' : 'left'}',
                      ),
                      controller: controller,
                      // 🚨★★ THE RAIL OWNS ITS PANELS, NOT ITS COLUMN
                      // (유저 2026-08-15 #1: 「작은거 열면 밑에 공간 남는데
                      // 그 공간에서 터치가 안먹힘」 — 그리기도 안 됐다).
                      //
                      // The column is laid out full height whatever is open
                      // on it, and it has to be: R6-⑤ pinned ONE tree shape
                      // so a live splitter drag cannot rebuild itself away.
                      // But a scroller's default `hitTestBehavior` is
                      // `opaque`, so that full-height rectangle took every
                      // pointer that entered it — and the floor is
                      // full-bleed underneath, so the pasteboard below a
                      // short panel was a pane of glass over live canvas.
                      // One hit test stopping stops every verb at once:
                      // the tap, the stroke, the hover, the wheel.
                      //
                      // Deferring to the child says the true thing instead
                      // — the rail owns exactly the rectangles its panels
                      // occupy — and it says it without changing the tree.
                      // ⚠️Nothing is lost when the rail DOES scroll: then
                      // the content fills the viewport and there is no
                      // empty space to have dragged in.
                      hitTestBehavior: HitTestBehavior.deferToChild,
                      // Top-aligned when it does not fill, which is what the
                      // `Align` used to do on the non-scrolling branch.
                      //
                      // ⚠️OUTERMOST FIRST: this rail is the outer scroller
                      // of the app's deepest chain, and a leaf corrected
                      // under an uncorrected ancestor buys nothing —
                      // measured 4.985e-1 inner-only against 1.4e-14 with
                      // both.
                      child: DeviceGridScrollBody(
                        controller: controller,
                        axisDirection: AxisDirection.down,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: column,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 띠랑 패널 사이공간에 (유저, R3 #12). The bar rides the gap
              // between the strip and the panels rather than the panels'
              // far edge, where it lay on whatever the panel had there and
              // pointed away from the strip it belongs to. The lane IS the
              // gap — narrower than the app's other lanes, and it can be,
              // because nothing else is within reach of it to mis-hit.
              // The BAR stays conditional — it is the one thing here that
              // should appear only while there is something to scroll, and
              // adding or removing it cannot disturb the column: it is a
              // SIBLING in the stack, not an ancestor.
              if (overflowing)
                Positioned(
                  left: right ? null : 0,
                  right: right ? 0 : null,
                  top: 0,
                  bottom: 0,
                  width: _EditorWorkspaceState._railGroupGap,
                  child: AppControllerScrollbar(
                    controller: controller,
                    axis: Axis.vertical,
                    thumbKey: ValueKey<String>(
                      'rail-scroll-thumb-${right ? 'right' : 'left'}',
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// ★ Whether a rail's column runs PAST the floating region to the window's
  /// bottom edge, or stops at its top edge.
  ///
  /// One comparison, and deliberately not a setting: the column can go down
  /// there exactly when the region has pulled far enough in to leave room,
  /// which is something the user can see. [railWidth] is that rail's shared
  /// width plus its splitter — the space the column actually occupies.
  static bool railPassesBottom({
    required double bottomInset,
    required double railWidth,
  }) => bottomInset >= railWidth;
}
