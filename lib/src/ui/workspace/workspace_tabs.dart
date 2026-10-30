part of '../editor_workspace.dart';

/// The PANEL TABS — which tab each panel id stands for (the one table the
/// docks and the rail both read), the floor tabs, the media viewer and
/// colour tabs, and selecting or closing one — as their own object.
///
/// 🚨A collaborator carved out of `_EditorWorkspaceState` (the audit's SRP cut,
/// 2026-09-02). It reaches the State through `_state` and rebuilds
/// through `_rebuild`.
class _WorkspaceTabs {
  _WorkspaceTabs(this._state);

  final _EditorWorkspaceState _state;

  /// What the top strip's floor switch offers, in strip order: the two
  /// homes, which nothing moves ([_WorkspaceDocks._canDockAccept]).
  ///
  /// ↩️It listed anything else lying in the center dock after them: the
  /// floor has no tab strip, so a panel dragged there had no button
  /// anywhere. 🗣️I-147 (유저 2026-10-30: 「캔버스패널이랑 메인뷰어패널은
  /// 지금처럼 배경고정. 못움직임」) closed the center to every other panel,
  /// and a panel lies on the floor from a top strip group of its own — the
  /// sub viewer too, which this list had kept off the floor because it
  /// exists to sit beside the drawing; the user listed it among the panels
  /// to lay, and where its button stands says which it does.
  List<String> floorTabIds() => _EditorWorkspaceState._floorHomeTabIds;

  void closeTab(String tabId) {
    _state._mutatingLayout(() => _state._layout.removeTab(tabId));
  }

  /// 래스터라이즈 (vanishing-point-types-Q5 · Q6): the picked guide's lines baked
  /// onto [paper] off the frame's clock, then laid on the cels through the
  /// paste's door as one undo. Null with no paper to bake onto.
  ValueChanged<DrawingGuide>? _guideRasterizer(
    BuildContext context,
    CanvasSize? paper,
  ) {
    if (paper == null) {
      return null;
    }
    final pixels = _state.widget.session.pixelVerbs;
    return (guide) => unawaited(
      guideLinesOnPaper(
        guide,
        canvasSize: paper,
        color: guideColorOf(context),
      ).then((picture) {
        if (picture != null) {
          pixels.landCanvasPicture(picture, description: 'Rasterize guide');
        }
      }),
    );
  }

  /// What the tool settings show of the session — the slice their panel
  /// rebuilds by, with [fillSource] and [eyedropperSource] the two sources
  /// it names the read layers of.
  ///
  /// 🚨I-57 ㉢ (10-13, measured on the user's project): every tool's panel
  /// is kept alive, and each one rebuilt on EVERY session notify — a cut
  /// switch rebuilt them all, 121 widgets a panel, and so did every
  /// stroke's commit, though the brush's panel shows nothing of the cut.
  _ToolSettingsCut _toolSettingsCut(
    CanvasReadSource fillSource,
    CanvasReadSource eyedropperSource,
  ) {
    final session = _state.widget.session;
    ByList<String>? reads(CanvasReadSource source) => switch (layerNamesReadBy(
      source,
      session.activeCutOrNull,
      session.activeLayerId,
    )) {
      final names? => ByList(names),
      null => null,
    };
    return (
      tips: _state._tipLibrary.tips,
      guides: session.cutVerbs.activeCutGuides,
      selectedGuideId: session.cutVerbs.selectedGuideId,
      fillReads: reads(fillSource),
      eyedropperReads: reads(eyedropperSource),
      pasteboard: session.activePasteboardOrNull,
      language: session.languageSettings.value.programLanguage,
    );
  }

  /// A panel's host — the timeline's, the storyboard's, the conte's, the
  /// envelope's, the timesheet's: [host], built again whenever [listenable]
  /// moves, on a layer of its own.
  ///
  /// 🚨Its own layer (timesheet-rebuilds-on-every-scrub-move, found by
  /// I-22's scrub measurement 09-27): a sheet's tab builds its host again on
  /// every pan and zoom — the view the sheet is printed through — and the
  /// two that show the cut under the playhead (F-90) on every crossing a
  /// scrub makes, at a far zoom every move. Built bare in the dock's layout
  /// scope, each laid the dock out again and repainted it whole. 🚨F-244: the
  /// frame panels too — they build their host again on every edit, and bare,
  /// every commit (a comma drag's release) laid the dock out again and
  /// repainted the page's root around the panel.
  ///
  /// A host that says what it prints of the session ([printed]) hears the
  /// session only when that changes. 🔬The conte and the envelope heard all
  /// of it in [listenable] and rebuilt — 107 and 108 elements — for a guide
  /// picked on the canvas or the onion switched on, news neither prints
  /// (session-news-rebuilds-unsliced, 2026-10-20). The timesheet hears it
  /// inside its host, through its document's memo key; the frame panels
  /// still hear it all, what they show of it being their rows' facts
  /// (F-244).
  ///
  /// ⛔A sheet's VIEW is not in [listenable]: its panel hears the view
  /// itself ([BrushCanvasPanel.viewportController], 08-21) and prints the
  /// sheet over it. 🔬Heard here as well — from when the view was handed
  /// down as a value — the timesheet's, the conte's and the envelope's
  /// hosts were built again, whole, at every step of a pan
  /// (tick-pins-allow-panel-hosts, 10-24).
  Widget _panelHost({
    required Listenable listenable,
    Object? Function()? printed,
    required WidgetBuilder host,
  }) => TickLayer.host(
    child: ListenableBuilder(
      listenable: listenable,
      builder: (context, _) => printed == null
          ? host(context)
          : SlicedListenableBuilder<Object?>(
              listenable: _state.widget.session,
              slice: printed,
              builder: (context, _) => host(context),
            ),
    ),
  );

  /// Both viewers, built from one place: same panel, same code, different
  /// [MediaViewerSlot]. Anything that reads as "the main one does X"
  /// belongs in the slot or in the callbacks, never in a second copy of
  /// this builder.
  EditorPanelTab _mediaViewerTab({
    required String tabId,
    required String label,
    required IconData icon,
    required bool locked,
  }) {
    final slot = _state._viewerSlot(tabId);
    return EditorPanelTab(
      id: tabId,
      label: label,
      icon: icon,
      locked: locked,
      canvasBase: true,
      builder: (context) => ListenableBuilder(
        // The request, the position and the viewport are the HOST's own
        // subscriptions (the page read moves with the view, F-201) — so
        // nothing here rebuilds it for them. The brush switch is the slot's;
        // the language, every tab's ([OpenTabContent]).
        listenable: slot.brushAllowed,
        builder: (context, _) => MediaViewerTabHost(
          viewerId: tabId,
          session: _state.widget.session,
          request: slot.request,
          position: slot.position,
          onRequestPicked: slot.open,
          onRequestClosed: () => slot.open(null),
          viewportController: slot.viewport,
          framedFor: slot.framedFor,
          keptFraming: slot.keptFramingOf,
          loudness: slot.loudness,
          selection: _state.widget.viewerSelections?[tabId],
          onSwapViewers: () => _state._swapViewers(fromTabId: tabId),
          // I-14: the cut tool reaches the viewer, and a cut there lands in
          // the piece the canvas's cuts fill.
          brushTool: _state._brushTool,
          cutPieceSlot: _state._cutPieceSlot,
          // I-114: the brush writes on a file the project carries.
          inkController: _state._views._viewerInk,
          brushAllowed: slot.brushAllowed.value,
          onBrushAllowedChanged: (allowed) => slot.brushAllowed.value = allowed,
          // 유저 확정 ⑱: the promote button calls the SAME import every
          // other entrance calls — a viewer-only policy here would be a
          // third import surface nobody remembers to fix. Since F-282-Q4
          // (유저 2026-10-09, 가) that is literally the same window: the
          // file goes through the one door to the pool's import window.
          // ↩️It registered on the spot until then, carried — the default
          // the window opens on, which it still is.
          onRegisterAsset: (path) => _state._door.open(_state.context, [
            handedPath(path),
          ], toPool: true),
          isPathRegistered: (path) =>
              _state.widget.session.repository.currentProject?.mediaAssetByPath(
                path,
              ) !=
              null,
          onAssetDropped: (data) =>
              _state._openDroppedAsset(data, tabId: tabId),
        ),
      ),
    );
  }

  /// One of the three colour panels. They differ by their picker and by
  /// nothing else — same live colour, same palette, same status bar — so
  /// they are built from one place rather than three that could drift.
  EditorPanelTab _colorTab(
    String tabId, {
    required ColorPickerKind kind,
    required String label,
    required IconData icon,
    required bool locked,
  }) {
    return EditorPanelTab(
      id: tabId,
      label: label,
      icon: icon,
      locked: locked,
      // The RGB bars are a FIXED stack — three rows, nothing that can give —
      // so the panel states what they cost and a group shorter than that
      // scrolls rather than clipping the blue channel off the bottom. The
      // wheel shrinks on its own, but the default palette under it does not
      // (I-131), so it states that much; the palette scrolls its own.
      minContentHeight: ColorPickerPanel.contentExtentIn(_state.context, kind),
      minContentWidth: ColorPickerPanel.minContentWidthIn(_state.context),
      builder: (context) {
        final palette = _state.widget.colorPalette;
        final onPaletteChanged = _state.widget.onColorPaletteChanged;
        if (palette == null || onPaletteChanged == null) {
          return const SizedBox.shrink();
        }
        return SlicedValueListenableBuilder<BrushToolState, int>(
          valueListenable: _state._brushTool,
          slice: (state) => state.color,
          builder: (context, toolState) =>
              ValueListenableBuilder<ColorPaletteState>(
                valueListenable: palette,
                builder: (context, paletteState, _) => ColorPickerPanel(
                  kind: kind,
                  color: toolState.color,
                  palette: paletteState,
                  onColorChanged: (color) => _state._brushTool.value = _state
                      ._brushTool
                      .value
                      .copyWith(color: color),
                  onPaletteChanged: onPaletteChanged,
                ),
              ),
        );
      },
    );
  }

  /// The drawing canvas, [leftPill] on its left edge.
  Widget _canvasArea({required CanvasEdgePill? leftPill}) => EditorCanvasArea(
    key: _state._canvasAreaKey,
    onInvokeAction: _state.widget.onInvokeAction,
    session: _state.widget.session,
    brushToolState: _state._brushTool,
    onBrushToolStateChanged: (state) => _state._brushTool.value = state,
    canvasViewCommands: _state.widget.canvasViewCommands,
    navigationRegionKey: _state.widget.canvasNavigationRegionKey,
    canvasSelectionCommands: _state.widget.canvasSelectionCommands,
    canvasTextCommands: _state.widget.canvasTextCommands,
    textToolOptions: _state._views._textToolOptions,
    cutPieceSlot: _state._cutPieceSlot,
    lastStroke: _state.widget.lastStroke,
    toolHold: _state.widget.toolHold,
    // F-363: the project's camera row's eye and opacity.
    cameraViewEnabled: _state.widget.session.cameraViewMode.enabled,
    cameraDimOpacity: _state.widget.session.cameraViewMode.dim,
    expandedLaneLayerIds: _state.widget.session.railView.expandedLaneLayerIds,
    fillOptions: _state._views._fillOptions,
    selectionMaskOptions: _state._views._selectionMaskOptions,
    transformOptions: _state._transformOptions,
    eyedropperSource: _state._views._eyedropperSource,
    flipHud: _state.widget.flipHud,
    leftPill: leftPill,
  );

  /// [tabId]'s tab, built for the project on screen.
  ///
  /// 🚨★★★EVERY PANEL IS BUILT FOR ONE PROJECT (I-7, a project per tab). A
  /// panel host takes the session into its State — listeners, stores,
  /// caches made from it — and a project tab switch hands this window another
  /// session. Keyed by the session, each panel is made again for the
  /// project that came on screen instead of carrying the last one's State
  /// into it: one key here rather than a switch handler in every host,
  /// which is the shape that forgets one.
  EditorPanelTab tabFor(String tabId) =>
      _tabForId(tabId).builtFor(_state.widget.session);

  EditorPanelTab _tabForId(String tabId) {
    final locked = _state._lockedTabIds.contains(tabId);
    switch (tabId) {
      case EditorWorkspace.toolsTabId:
        return EditorPanelTab(
          id: tabId,
          label: AppText.strings.panelTools,
          icon: Icons.handyman_outlined,
          locked: locked,
          // Sliced (R18 UI-1): only an actual TOOL change reshapes this
          // panel — color/size/knob tweaks must not rebuild it.
          // I-128: the shortcut buttons stand above the tools unless the
          // workspace holds the strip to its tools alone.
          builder: (context) => ValueListenableBuilder<bool>(
            valueListenable: _state._railToolsOnly,
            builder: (context, toolsOnly, _) =>
                SlicedValueListenableBuilder<BrushToolState, CanvasTool>(
                  valueListenable: _state._brushTool,
                  slice: (state) => state.tool,
                  builder: (context, toolState) => ToolsPanel(
                    tool: toolState.tool,
                    // Applied at PRESS time, not build time: the rail memory
                    // is the notifier's, not state this builder is sliced on.
                    onPress: _state._pressTool,
                    // The between-strokes group. Its own listeners, so
                    // undoing does not rebuild the tool column above it.
                    historyControls: toolsOnly
                        ? null
                        : _state._rail._railHistoryControls(),
                  ),
                ),
          ),
        );
      case EditorWorkspace.colorWheelTabId:
        return _colorTab(
          tabId,
          kind: ColorPickerKind.wheel,
          label: AppText.strings.panelColorWheel,
          icon: Icons.palette_outlined,
          locked: locked,
        );
      case EditorWorkspace.colorRgbTabId:
        return _colorTab(
          tabId,
          kind: ColorPickerKind.rgb,
          label: AppText.strings.panelColorRgb,
          icon: Icons.tune,
          locked: locked,
        );
      case EditorWorkspace.colorPaletteTabId:
        return _colorTab(
          tabId,
          kind: ColorPickerKind.palette,
          label: AppText.strings.panelColorPalette,
          icon: Icons.grid_view_outlined,
          locked: locked,
        );
      case EditorWorkspace.canvasTabId:
        return EditorPanelTab(
          id: tabId,
          label: AppText.strings.panelCanvas,
          icon: Icons.image_outlined,
          locked: locked,
          // The one panel that opts out of the static bake. It is full
          // of repaint boundaries by design (the artwork, the cursor
          // deck, the ants each own one), and its live-stroke path must
          // never be asked for a full-surface copy. It also does not
          // need it: with every panel closed, a canvas full of artwork
          // measured 2.5 ms hovering and 4.9 ms mid-stroke.
          staticRaster: false,
          // Nor from a still image, for a reason of its own: the canvas
          // is the one surface whose pixels may never move (유저
          // 2026-09-25, 「결과 절대 바뀌면 안되는건 캔버스뿐임」).
          stillRaster: false,
          builder: (context) => Stack(
            fit: StackFit.expand,
            children: [
              // 🚨F-244: the area hears every edit (its session subscription
              // is its own), and bare in the workspace's layout scope each
              // rebuild laid the workspace out again and repainted the
              // page's root — the canvas is a panel host like the others
              // ([_panelHost]), on a layer of its own. The expanding stack is
              // what makes the layer's constraints tight.
              TickLayer.host(
                // I-34: the brush's values stand on the drawing unless the
                // workspace stands them on the top strip.
                child: ValueListenableBuilder<bool>(
                  valueListenable: _state._brushValuesOnStrip,
                  builder: (context, onStrip, _) => _canvasArea(
                    leftPill: onStrip
                        ? null
                        : CanvasEdgePill(
                            width: BrushValuesPill.widthIn(context),
                            child: BrushValuesPill(
                              brushTool: _state._brushTool,
                            ),
                          ),
                  ),
                ),
              ),
              // A pool row dropped on the STAGE (§7): the cut and the layer
              // are the ones already under the cursor, so this entrance
              // fills nothing extra — it opens the place window with the
              // file listed and lets the window ask the rest.
              //
              // A permanent slot rather than a target mounted while a drag
              // runs: the canvas is a GlobalKey subtree, and a structure
              // that appears mid-drag would re-parent it. It costs nothing
              // to keep — the target draws nothing and absorbs no hit test
              // until a matching drag is in flight.
              Positioned.fill(
                child: MediaAssetDropTarget(
                  key: const ValueKey<String>('canvas-asset-drop'),
                  onDrop: (data, _) => _state._openImportWindow(
                    initialPaths: [data.path],
                    placeOnly: true,
                    // 「놓으면 활성 레이어 바로 위를 기본값으로 채운 배치
                    // 창이 열린다」 — the drop's answer, shown locked.
                    spot: const AboveActiveLayerSpot(),
                  ),
                ),
              ),
            ],
          ),
        );
      case EditorWorkspace.brushesTabId:
        // The TOOL LIBRARY (R11-④, CSP sub-tool palette): content follows
        // the active tool — painting tools get the preset library (each
        // remembers its own selection), selection tools their variants.
        return EditorPanelTab(
          id: tabId,
          label: AppText.strings.panelToolLibrary,
          // ⛔NOT the brush glyph (유저, R3 #7). The tool strip's own brush
          // button already wears it two rows above, so the rail read as
          // having the brush twice — and this panel is not the brush, it is
          // the SET you pick one out of.
          icon: Icons.widgets_outlined,
          locked: locked,
          // Sliced (R18 UI-1) + per-tool keep-alive (R18 UI-4): the
          // library follows the active tool and that tool's remembered
          // preset — nothing else — and switching back to a tool whose
          // preset didn't change is a pure index flip (the preset grid
          // was the other half of the per-switch rebuild cost).
          builder: (context) =>
              SlicedValueListenableBuilder<
                BrushToolState,
                (CanvasTool, CanvasShapeKind?, BrushPresetId?)
              >(
                valueListenable: _state._brushTool,
                // The shape kind rides in the slice: without it, picking a
                // different outline changes the state but not this slice,
                // and the tiles keep painting the old one as selected.
                slice: (state) => (
                  state.tool,
                  state.activeShapeKind,
                  state.presetId,
                ),
                builder: (context, toolState) =>
                    KeyedKeepAliveStack<
                      CanvasTool,
                      (BrushPresetId?, CanvasShapeKind?)
                    >(
                      keys: CanvasTool.values,
                      activeKey: toolState.tool,
                      // TS3: the SHAPE belongs here as much as in the slice
                      // above. The slice decides whether this builder runs;
                      // this decides whether the kept-alive subtree is
                      // thrown away — and a cached panel is reused whole, so
                      // with the preset alone (null for every drag-out verb,
                      // for ever) picking the lasso changed the state, ran
                      // the builder, hit the cache and left the tiles
                      // painting the rectangle as selected. The tap still
                      // worked, which is exactly what made it read as a
                      // UI-only lie.
                      stateOf: () => (
                        toolState.presetId,
                        toolState.activeShapeKind,
                      ),
                      builder: (context) => ToolLibraryPanel(
                        transformOptions: _state._transformOptions,
                        tool: toolState.tool,
                        onPress: _state._pressTool,
                        shapeKind:
                            toolState.activeShapeKind ?? CanvasShapeKind.rect,
                        brushLibrary: ListenableBuilder(
                          // The view toggles ride in too: a restored or
                          // reset layout has to reach a panel already open.
                          listenable: Listenable.merge([
                            _state._presetLibrary,
                            _state._brushPresetView,
                          ]),
                          builder: (context, _) => BrushPresetPanel(
                            presets: _state._presetLibrary.presets,
                            groups: _state._presetLibrary.groups,
                            // This panel is THIS tool's library (F-319):
                            // its rows and tabs press for it and wear its
                            // keys, and both tools' panels read the one
                            // look.
                            tool: toolState.tool,
                            look: _state._brushGroups.look,
                            selectedPresetId: toolState.presetId,
                            viewOptions: _state._brushPresetView.value,
                            onViewOptionsChanged: (options) {
                              _state._brushPresetView.value = options;
                              _state._layoutPersistence.scheduleLayoutSave();
                            },
                            onPresetApplied:
                                _state._brushGroups.rowPressOf[toolState.tool],
                            onPresetSaveRequested:
                                _state._brushPresets.saveHeldBrushAsPreset,
                            onPresetDeleted: _state._brushPresets.deletePreset,
                            onPresetRenamed: _state._presetLibrary.rename,
                            onPresetsReordered:
                                _state._brushPresets.arrangePresets,
                            onPresetImportRequested: () {
                              unawaited(
                                _state._brushPresets._importAndNotice(
                                  _state._presetLibrary.importFromFile,
                                ),
                              );
                            },
                            onGroupCreated: _state._presetLibrary.createGroup,
                            onGroupEdited: _state._presetLibrary.editGroup,
                            onGroupDeleted: _state._brushPresets.deleteGroup,
                            onGroupOpened:
                                _state._brushGroups.tabPressOf[toolState.tool],
                            onGroupsReordered:
                                _state._brushPresets.arrangeGroups,
                            onLibraryReset:
                                _state._brushPresets.resetLibrary,
                            onPresetExported: (id) {
                              unawaited(
                                _state._brushPresets._exportAndNotice([
                                  for (final preset
                                      in _state._presetLibrary.presets)
                                    if (preset.id == id) preset,
                                ]),
                              );
                            },
                            onGroupExported: (groupId) {
                              unawaited(
                                _state._brushPresets._exportAndNotice(
                                  _state._presetLibrary.presetsInGroup(groupId),
                                ),
                              );
                            },
                          ),
                        ),
                        // The cut's own guides. Unlike the brush library
                        // above — app-wide and permanent — this list belongs
                        // to the CUT, so it follows the session.
                        // What it shows is the slice: a session notify that
                        // changes none of it — a stroke's commit, a switch
                        // between cuts with the same guides — stops here
                        // (I-57 ㉢).
                        guideLibrary: SlicedListenableBuilder(
                          listenable: _state.widget.session,
                          slice: () => (
                            guides:
                                _state.widget.session.cutVerbs.activeCutGuides,
                            canvasSize:
                                _state
                                    .widget
                                    .session
                                    .activeCutOrNull
                                    ?.canvasSize ??
                                BrushCanvasDefaults.canvasSize,
                            selectedGuideId:
                                _state.widget.session.cutVerbs.selectedGuideId,
                          ),
                          builder: (context, shown) => GuideLibraryList(
                            guides: shown.guides,
                            canvasSize: shown.canvasSize,
                            selectedGuideId: shown.selectedGuideId,
                            onGuideSelected: (id) =>
                                _state.widget.session.cutVerbs.selectedGuideId =
                                    id,
                            onGuidesCommitted: _state
                                .widget
                                .session
                                .cutVerbs
                                .setActiveCutGuides,
                          ),
                        ),
                      ),
                    ),
              ),
        );
      case EditorWorkspace.brushSettingsTabId:
        // TOOL SETTINGS (R11-④, CSP tool property palette): the active
        // tool's detailed knobs.
        return EditorPanelTab(
          id: tabId,
          label: AppText.strings.panelToolSettings,
          icon: Icons.tune,
          locked: locked,
          // Per-tool keep-alive (R18 UI-4): switching back to a tool whose
          // settings didn't change is a pure index flip — the frozen-panel
          // experiment showed these per-switch rebuilds were the bulk of
          // the tool-switch jank. Each tool's panel also keeps its own
          // scroll position, CSP-style.
          builder: (context) => ValueListenableBuilder<BrushToolState>(
            valueListenable: _state._brushTool,
            builder: (context, toolState, _) => ValueListenableBuilder<FloodFillOptions>(
              valueListenable: _state._views._fillOptions,
              builder: (context, fillOptions, _) =>
                  KeyedKeepAliveStack<
                    CanvasTool,
                    (BrushToolState, FloodFillOptions)
                  >(
                    keys: CanvasTool.values,
                    activeKey: toolState.tool,
                    stateOf: () => (toolState, fillOptions),
                    // The inner listenables SUBSCRIBE for themselves,
                    // which is why they need not appear in the
                    // keep-alive tuple above: that tuple decides when
                    // the kept-alive subtree is thrown away, not when
                    // it rebuilds.
                    builder: (context) => ValueListenableBuilder<TransformToolOptions>(
                      valueListenable: _state._transformOptions,
                      builder: (context, transformOptions, _) =>
                          ValueListenableBuilder<SelectionMaskOptions>(
                            valueListenable:
                                _state._views._selectionMaskOptions,
                            builder: (context, maskOptions, _) =>
                                ValueListenableBuilder<CanvasReadSource>(
                                  valueListenable:
                                      _state._views._eyedropperSource,
                                  // The tip library loads in two passes,
                                  // so the pickers have to follow it.
                                  builder: (context, eyedropperSource, _) =>
                                      SlicedListenableBuilder<
                                        _ToolSettingsCut
                                      >(
                                        // The guides live on the CUT and
                                        // the selection is UI state, so
                                        // both have to reach this panel:
                                        // neither is in the keep-alive
                                        // tuple above, which decides when
                                        // the subtree is discarded rather
                                        // than when it rebuilds.
                                        listenable: Listenable.merge([
                                          _state._tipLibrary,
                                          _state.widget.session,
                                          _state.widget.session
                                              .languageSettings,
                                        ]),
                                        slice: () => _toolSettingsCut(
                                          fillOptions.source,
                                          eyedropperSource,
                                        ),
                                        builder: (context, cut) => ToolSettingsPanel(
                                          state: toolState,
                                          brushDetailAt: _state._brushDetailAt,
                                          onChanged: (state) =>
                                              _state._brushTool.value = state,
                                          guides: cut.guides,
                                          selectedGuideId: cut.selectedGuideId,
                                          onGuidesCommitted: _state
                                              .widget
                                              .session
                                              .cutVerbs
                                              .setActiveCutGuides,
                                          onGuidesPreview: _state
                                              .widget
                                              .session
                                              .cutVerbs
                                              .previewActiveCutGuides,
                                          onGuideRasterized: _guideRasterizer(
                                            context,
                                            cut.pasteboard?.canvas,
                                          ),
                                          tips: cut.tips,
                                          onTipImportRequested: () {
                                            unawaited(
                                              _state._brushPresets
                                                  ._importAndNotice(
                                                    _state
                                                        ._tipLibrary
                                                        .importFromFile,
                                                  ),
                                            );
                                          },
                                          fillOptions: fillOptions,
                                          onFillOptionsChanged: (options) =>
                                              _state._views._fillOptions.value =
                                                  options,
                                          eyedropperSource: eyedropperSource,
                                          onEyedropperSourceChanged: (source) =>
                                              _state
                                                      ._views
                                                      ._eyedropperSource
                                                      .value =
                                                  source,
                                          readLayerNames: (source) =>
                                              layerNamesReadBy(
                                                source,
                                                _state
                                                    .widget
                                                    .session
                                                    .activeCutOrNull,
                                                _state
                                                    .widget
                                                    .session
                                                    .activeLayerId,
                                              ),
                                          selectionMaskOptions: maskOptions,
                                          onSelectionMaskOptionsChanged:
                                              (options) =>
                                                  _state
                                                          ._views
                                                          ._selectionMaskOptions
                                                          .value =
                                                      options,
                                          transformOptions: transformOptions,
                                          onTransformOptionsChanged:
                                              (options) =>
                                                  _state._transformOptions
                                                          .value =
                                                      options,
                                          selectionCommands: _state
                                              .widget
                                              .canvasSelectionCommands,
                                          canvasTraces:
                                              _state.widget.canvasTraces,
                                          textOptions:
                                              _state._views._textToolOptions,
                                          textCommands:
                                              _state.widget.canvasTextCommands,
                                          textFonts: _state._fonts,
                                          // The wall 선택 반전 inverts out
                                          // to (I-23): the cut on screen.
                                          pasteboard: cut.pasteboard,
                                          cutPieceSlot: _state._cutPieceSlot,
                                          // TS8: composite order is
                                          // the BLEND's answer, so
                                          // the button no longer
                                          // carries one.
                                          onCutPasteAtOrigin: _state
                                              ._cutPieceSlot
                                              .pasteAtOrigin,
                                          onRegisterCutPieceAsTip: _state
                                              ._brushPresets
                                              ._registerCutPieceAsTip,
                                          onRenameTip:
                                              _state._brushPresets._renameTip,
                                          onDeleteTip:
                                              _state._brushPresets._deleteTip,
                                          language: cut.language,
                                        ),
                                      ),
                                ),
                          ),
                    ),
                  ),
            ),
          ),
        );
      // R9 #14: there is no Color TAB. The wheel and the palette are the
      // two tabs of the 「컬러 버튼창」, opened from the top strip's
      // selected-colour swatch. A saved layout still naming this id drops
      // it on restore — the store validates against the current defaults.
      case EditorWorkspace.onionSkinTabId:
        return EditorPanelTab(
          id: tabId,
          label: AppText.strings.panelOnionSkin,
          icon: Icons.layers_outlined,
          locked: locked,
          builder: (context) => ValueListenableBuilder<OnionSkinSettings>(
            valueListenable: _state.widget.session.onionSkin.settings,
            builder: (context, settings, _) => OnionSkinPanel(
              settings: settings,
              currentColorOf: () => _state._brushTool.value.color,
              onChanged: (next) =>
                  _state.widget.session.appSettings.setOnionSkinSettings(next),
            ),
          ),
        );
      // I-2: the tool's sizes as buttons — its own preset rack now, not the
      // snap list (유저 2026-08-29 threw out the "one list" premise; a snap
      // is where a drag catches, a preset is what you point at). See
      // [ToolSizePresetPanel] for the user's own words.
      case EditorWorkspace.toolSizeTabId:
        return EditorPanelTab(
          id: tabId,
          label: AppText.strings.panelToolSize,
          icon: Icons.line_weight,
          locked: locked,
          builder: (context) => ValueListenableBuilder<BrushToolState>(
            valueListenable: _state._brushTool,
            builder: (context, tool, _) => ToolSizePresetPanel(
              size: tool.activeSize,
              onSizeSelected: (size) => _state._brushTool.value = _state
                  ._brushTool
                  .value
                  .withActiveSize(size),
            ),
          ),
        );
      case EditorWorkspace.mediaTabId:
        return EditorPanelTab(
          id: tabId,
          label: AppText.strings.panelMedia,
          icon: Icons.library_music_outlined,
          locked: locked,
          builder: (context) => ListenableBuilder(
            // I-97: a sheet's photo is a use as well, and a sheet's ink is
            // written without the session saying so.
            listenable: Listenable.merge([
              _state.widget.session,
              _state.widget.session.mediaPool.sheetPhotoWrites,
            ]),
            builder: (context, _) => MediaPoolPanel(
              assets: _state.widget.session.mediaPool.mediaAssets,
              // F-118: one list per file — the mark, its window and the
              // remove's question all read the session's answer.
              usesOf: (path) => _state.widget.session.mediaPool
                  .mediaAssetUses(path)
                  .map(
                    (use) => mediaAssetUseLine(
                      use,
                      framePlace: _state.widget.session.framePlaceLabel,
                    ),
                  ),
              onImportRequested: () =>
                  unawaited(_state._pickAndOpen(toPool: true)),
              onRenameAsset: _state.widget.session.mediaPool.renameMediaAsset,
              onRelinkAsset: (oldPath, newPath, grants) {
                // The token first: the relink itself is undoable and the
                // grant is not, so recording it before the path moves
                // keeps the two from disagreeing about which file the
                // session may read.
                _state.widget.session.mediaGrants.rememberMediaGrants(grants);
                unawaited(
                  _state.widget.session.mediaPool.relinkMediaAsset(oldPath, newPath),
                );
              },
              // RELINK-2: the loss banner reads the session's cached
              // answer rather than probing the disk per row.
              missingPaths: _state.widget.session.mediaPool.missingMediaPaths,
              modifiedTimes: _state.widget.session.mediaPool.mediaModifiedTimes,
              // 유저 2026-08-30: 「아무튼 실제크기」 — what a carried asset
              // occupies compressed, rather than the length its file had
              // when it was registered.
              storedBytes: _state.widget.session.projectFile.mediaStoredBytes,
              conformBytes:
                  _state.widget.session.projectFile.conformStoredBytes,
              onRelinkMissing: () =>
                  runMediaRelinkFlow(context, _state.widget.session),
              onRemoveAsset: _state.widget.session.mediaPool.removeMediaAsset,
              onPromoteAsset:
                  _state.widget.session.mediaPool.promoteMediaAssetIntoProject,
              onExportAssetWav: (asset) =>
                  _state._exportAssetWav(context, asset),
              onOpenAsset: (asset) => _state._openAssetInViewer(
                asset,
                tabId: EditorWorkspace.mediaViewerTabId,
              ),
              onOpenAssetInSubViewer: (asset) => _state._openAssetInViewer(
                asset,
                tabId: EditorWorkspace.mediaViewerSubTabId,
              ),
              onPlaceAsset: (asset) => _state._openImportWindow(
                initialPaths: [asset.path],
                placeOnly: true,
              ),
            ),
          ),
        );
      case EditorWorkspace.mediaViewerTabId:
        return _mediaViewerTab(
          tabId: tabId,
          label: AppText.strings.panelMediaViewer,
          icon: Icons.preview_outlined,
          locked: locked,
        );
      case EditorWorkspace.mediaViewerSubTabId:
        return _mediaViewerTab(
          tabId: tabId,
          label: AppText.strings.panelMediaViewerSub,
          // 🔄**결정이 뒤집혔다** (유저 2026-08-28, F-46): 「서브뷰어 패널
          // 아이콘을 일반 뷰어 패널 아이콘을 재사용. 즉 **둘이 똑같은 아이콘**
          // 사용. **다 감안하고 말하는것임**」.
          //
          // ⚠️전에 여기 있던 이유는 이것이었다 — 「레일 버튼은 아이콘이 전부라
          // 두 뷰어가 `preview_outlined` 를 같이 쓰면 사람이 구분 못 하는 버튼
          // 둘이 된다」. **틀린 관찰은 아니지만 유저가 그것까지 알고 뒤집었다.**
          // 지우지 않고 적어 둔다: 안 적으면 다음에 읽는 쪽이 「구분이 안 되네」
          // 하고 되돌린다.
          //
          // ⛔되묻지 말 것.
          icon: Icons.preview_outlined,
          locked: locked,
        );
      case EditorWorkspace.timelineTabId:
        return EditorPanelTab(
          id: tabId,
          label: AppText.strings.panelTimeline,
          icon: Icons.view_timeline_outlined,
          // The legacy mode-toggle keys stay on the tab buttons so every
          // existing flow (and test helper) keeps working.
          buttonKey: const ValueKey<String>('timeline-mode-timeline-button'),
          minContentHeight: _state._minContentHeightFor(tabId),
          locked: locked,
          // F-452: its bars are thick — the splitter may lie over them.
          sparesSplitters: false,
          // ↩️유저 확정 (2026-08-10): 재생 그룹과 설정은 문턱으로 — the
          // settings went to the top strip, and the transport to the head of
          // the panel's own bar (F-111-Q1, 10-08) — its right group from
          // F-463, its left group's head since F-491 — which its host seats
          // (`FramePanelTransport`).
          // 접으면 버튼행만 (유저 확정): the panel keeps its command bar and
          // offstages the grid, so the fold is 문턱 30 + this 36 = 66 — and
          // every verb a rough pass needs is still on screen while folded.
          collapsedExtent: TimelineCommandBar.heightIn(_state.context),
          builder: (context) => _panelHost(
            // The session subscription lives HERE now (HomePage no longer
            // setStates the world). Seeks are NOT session notifies — the
            // grids ride the frame cursor and never rebuild for them.
            listenable: Listenable.merge([
              _state.widget.session,
              _state._timelineOrientation,
              // Zoom (_timelinePixelsPerFrame) is NOT merged here (UI-R6
              // #4): the host scopes it to the panel subtree, so a zoom
              // step skips this whole tab rebuild.
              _state._rulerView,
              _state.widget.session.railView.drawn,
            ]),
            host: (context) => TimelineTabHost(
              session: _state.widget.session,
              transformOptions: _state._transformOptions,
              // A pool row dropped on a drawing layer: select what it
              // landed on, then open the place window with the file
              // already decided. The drop FILLS the answers and the
              // window still asks them — the round's rule, so a drop
              // cannot commit something nobody looked at.
              // A drop FILLS the window's answers rather than deciding for
              // the user (§7): the row it landed on becomes the active
              // layer and the cell it landed on becomes the playhead, and
              // the window opens on top of that with the file already
              // listed. Nothing imports until the window says so.
              onPlaceMediaAsset: (layerId, frameIndex, path) {
                final session = _state.widget.session;
                // A drop that lands nowhere does nothing and opens nothing.
                final spot = session.dropSpotFor(layerId, frameIndex, path);
                if (spot == null) {
                  return;
                }
                // 🚨T4 — a drop LANDS somewhere, and landing is standing, so
                // it goes through the verb like every other door (F-13). The
                // two calls it replaces were `selectLayer` + `selectFrameIndex`
                // — the verb's own body, minus the law.
                session.standOnRow(
                  LayerRowAddress(layerId),
                  frameIndex: frameIndex,
                );
                if (spot is ReferenceSwapSpot) {
                  unawaited(_state._swapReference(layerId, path));
                  return;
                }
                unawaited(
                  _state._openImportWindow(
                    initialPaths: [path],
                    placeOnly: true,
                    spot: spot,
                  ),
                );
              },
              // A pool row let go on the LAYER AREA: a new layer at the gap
              // the rail's caret showed (「레이어 영역(가로선) → 새 레이어」).
              // Nothing is stood on — the row does not exist yet.
              onPlaceMediaAssetBetweenLayers: (displayLayers, slot, path) {
                final spot = _state.widget.session.layerSlotSpotFor(
                  displayLayers,
                  slot,
                  path,
                );
                if (spot == null) {
                  return;
                }
                unawaited(
                  _state._openImportWindow(
                    initialPaths: [path],
                    placeOnly: true,
                    spot: spot,
                  ),
                );
              },
              orientation: _state._timelineOrientation.value,
              onOrientationChanged: _state._setTimelineOrientation,
              pixelsPerFrame: _state._timelinePixelsPerFrame.value,
              pixelsPerFrameListenable: _state._timelinePixelsPerFrame,
              onPixelsPerFrameChanged: _state._setTimelineZoom,
              onZoomFit: _state._fitTimelineZoom,
              rulerView: _state._rulerView.value,
              onRulerViewChanged: (view) {
                _state._rulerView.value = view;
              },
              timelineRailExtent: _state._railExtents[LayerRailId.timeline],
              xsheetRailExtent: _state._railExtents[LayerRailId.xsheet],
              rail: TabRailWiring.of(_state.widget.session),
              // The legend's "open onion panel" (UI-R17 #5): already open
              // = the panel flashes in place (the common reveal logic).
              onRevealOnionSkinPanel: () =>
                  _state._revealPanel(EditorWorkspace.onionSkinTabId),
            ),
          ),
        );
      case EditorWorkspace.storyboardTabId:
        return EditorPanelTab(
          id: tabId,
          label: AppText.strings.panelStoryboard,
          icon: Icons.movie_outlined,
          buttonKey: const ValueKey<String>('timeline-mode-storyboard-button'),
          minContentHeight: _state._minContentHeightFor(tabId),
          locked: locked,
          // F-452: as the timeline's.
          sparesSplitters: false,
          collapsedExtent: TimelineCommandBar.heightIn(_state.context),
          builder: (context) => _panelHost(
            // Session subscription — the timeline tab's list exactly, and
            // for the same reason: seeks are NOT session notifies, so this
            // panel never rebuilds for one. Scrub moves, playback ticks and
            // committed seeks all ride the host's own channels (playhead
            // overlay + ruler, the rail's lane-label cursor, the command
            // bar's own subscription). `frameSeekCommitted` sat in THIS
            // merge until 2026-08-05 and cost a whole-panel rebuild per
            // arrow press — measured at 38ms a step (12 build / 22 layout /
            // 3 paint) with a six-cut project.
            // ↩️The thumbnail store sat here too, so every picture that
            // landed rebuilt the whole panel — at I-22's ten-minute zoom,
            // one per cut on the film. The blocks that ask repaint on it
            // now ([StoryboardThumbnails]).
            listenable: Listenable.merge([
              _state.widget.session,
              _state._storyboardPixelsPerFrame,
              // The rail's view is no session notify: a section toggle
              // (F-199), a fold (I-73), a twirl — the camera row's lanes, a
              // conte row's and their groups (I-73 ④ⓔ), an S row's, a V
              // row's (F-360) — a header graph (I-89 ①) and the filter.
              _state.widget.session.railView.drawn,
              _state._storyboardTrackLaneHeight,
              _state._rulerView,
            ]),
            host: (context) => StoryboardTabHost(
              session: _state.widget.session,
              transformOptions: _state._transformOptions,
              // A pool row let go on a track's frames: the place window, with
              // the drop's answer — a NEW cut there — shown locked.
              onPlaceMediaAsset: (path, spot) => _state._openImportWindow(
                initialPaths: [path],
                placeOnly: true,
                spot: spot,
              ),
              // R5 #9: ONE filter across the surfaces — the same state the
              // timeline and the sheet read, so a chip set on one is set
              // wherever the legend appears. And so the sections (F-199),
              // the attach folds, the lane twirls (I-73 ④ⓔ — the camera
              // row's head is the timeline's camera row, and turns its lanes
              // there too) and the header graphs (I-89 ①): the timeline's
              // own wiring.
              rail: TabRailWiring.of(_state.widget.session),
              // And the legend's onion panel door, as the timeline's (F-443).
              onRevealOnionSkinPanel: () =>
                  _state._revealPanel(EditorWorkspace.onionSkinTabId),
              pixelsPerFrame: _state._storyboardPixelsPerFrame.value,
              onPixelsPerFrameChanged: _state._setStoryboardZoom,
              onZoomFit: _state._fitStoryboardZoom,
              rulerView: _state._rulerView.value,
              onRulerViewChanged: (view) {
                _state._rulerView.value = view;
              },
              railExtent: _state._railExtents[LayerRailId.storyboard],
              // ⛔No steppers any more (B7): the V rows' splitter is the
              // height's one writer, and it asks the NOTIFIER, not the value
              // this build took — a drag's steps outrun the rebuilds.
              trackLaneHeight: _state._storyboardLaneHeight(context),
              onResizeTrackLanes: (delta) {
                final height = _state._storyboardTrackLaneHeight;
                final ceiling = _state._storyboardLaneCeiling(context);
                // From the height the rows are DRAWN at: one set above
                // today's ceiling moves from where the hand sees it.
                final before = _state._storyboardLaneHeight(context);
                height.value = StoryboardPanel.clampTrackLaneHeight(
                  before + delta,
                  ceiling: ceiling,
                );
                return height.value - before;
              },
              thumbnails: _state._storyboardThumbnails.thumbnails,
              // The rows the ↑/↓ walk and the flip window read while the
              // storyboard is the panel being worked in.
              rowsChannel: _state._storyboardRows,
            ),
          ),
        );
      case EditorWorkspace.conteTabId:
        return EditorPanelTab(
          id: tabId,
          label: AppText.strings.panelConte,
          icon: Icons.grid_on_outlined,
          buttonKey: const ValueKey<String>('timeline-mode-conte-button'),
          minContentHeight: _state._minContentHeightFor(tabId),
          locked: locked,
          canvasBase: true,
          // The sheet reads the project and the SAME picture store the
          // storyboard strip draws from, so a cell and its strip panel are
          // one render rather than two that must be kept in step.
          // _brushTool is deliberately NOT merged (R18 UI-3): only the
          // ink overlay consumes it, through its own boundary builder.
          builder: (context) => _panelHost(
            listenable: Listenable.merge([
              _state._views._conteBrushAllowed,
              _state._views._conteInk,
              // Its pictures' cels, followed through the store: an undo
              // that moves no row still moves their pixels (F-80 ②).
              _state._views._contePictures,
            ]),
            printed: () => ConteTabHost.printedBy(_state.widget.session),
            host: (context) => ConteTabHost(
              session: _state.widget.session,
              // A landed thumbnail render repaints the page painter
              // directly (its compared fields don't change for async
              // pictures) — and only it: the store left this tab's merge,
              // which rebuilt the whole sheet for every picture as well.
              thumbnails: _state._storyboardThumbnails.thumbnails,
              // The notifier ITSELF — the panel writes into this one, so
              // there is no copy to echo and nothing to go stale while the
              // panel is unmounted.
              viewportController: _state._views._conteViewport,
              inkController: _state._views._conteInk,
              pictures: _state._views._contePictures,
              brushToolState: _state._brushTool,
              brushAllowed: _state._views._conteBrushAllowed.value,
              onBrushAllowedChanged: (enabled) {
                _state._views._conteBrushAllowed.value = enabled;
              },
              // The logo and the cover picture, from the decode cache the
              // envelope prints from — a landed decode repaints the page.
              imageFor: _state._views._sheetImages.imageFor,
              imageRepaint: _state._views._sheetImages,
            ),
          ),
        );
      case EditorWorkspace.envelopeTabId:
        return EditorPanelTab(
          id: tabId,
          label: AppText.strings.panelEnvelope,
          icon: Icons.mail_outline,
          buttonKey: const ValueKey<String>('timeline-mode-envelope-button'),
          minContentHeight: _state._minContentHeightFor(tabId),
          locked: locked,
          canvasBase: true,
          // _brushTool is deliberately NOT merged (R18 UI-3): only the ink
          // overlay consumes it, through its own boundary builder.
          builder: (context) => _panelHost(
            listenable: Listenable.merge([
              _state._views._envelopeBrushAllowed,
              _state._views._envelopeInk,
              // F-90: the envelope of the cut under the playhead, turning
              // over at a crossing like the sheet beside it.
              _state.widget.session.cutUnderPlayhead.listenable,
            ]),
            printed: () => CutEnvelopeTabHost.printedBy(_state.widget.session),
            host: (context) => CutEnvelopeTabHost(
              session: _state.widget.session,
              // The work's choice, written back to the work — one undo.
              formId: _state.widget.session.timesheetInfo.envelopeFormId,
              onFormIdChanged: (formId) {
                final session = _state.widget.session;
                session.updateTimesheetInfo(
                  session.timesheetInfo.copyWith(envelopeFormId: formId),
                );
              },
              viewportController: _state._views._envelopeViewport,
              inkController: _state._views._envelopeInk,
              brushToolState: _state._brushTool,
              brushAllowed: _state._views._envelopeBrushAllowed.value,
              onBrushAllowedChanged: (enabled) {
                _state._views._envelopeBrushAllowed.value = enabled;
              },
              // 🚨WIRED NOW. The comment that stood here said this waited on
              // the 작품 정보 round because nothing set a logo or a 도장 path
              // yet, so a resolver had no source. The stamp picker in the
              // sheet-info window is that source.
              imageFor: _state._views._sheetImages.imageFor,
              imageRepaint: _state._views._sheetImages,
            ),
          ),
        );
      case EditorWorkspace.timesheetTabId:
        return EditorPanelTab(
          id: tabId,
          label: AppText.strings.panelTimesheet,
          icon: Icons.table_chart_outlined,
          locked: locked,
          canvasBase: true,
          // Manages its own seams: the sheet's two strata are baked
          // separately so a content change never re-records the grid,
          // and the playhead and ink windows sit ABOVE both bakes so
          // they stay live. A wrapper around the whole tab would have
          // to include the playhead, and would then stand itself down
          // for the whole of playback.
          staticRaster: false,
          builder: (context) => _panelHost(
            // _brushTool is deliberately NOT merged here (R18 UI-3): the
            // sheet layout never depends on it, and rebuilding the whole
            // B4 document on every tool switch / color notch was
            // measurably half the tool-switch jank. Only the ink overlay
            // consumes the tool state, through its own boundary builder
            // inside the host.
            listenable: Listenable.merge([
              _state._views._timesheetBrushAllowed,
              _state._views._timesheetDataSheet,
              // F-90: a crossing, played or dragged over, turns the sheet
              // over to the cut under the playhead.
              _state.widget.session.cutUnderPlayhead.listenable,
            ]),
            host: (context) => TimesheetTabHost(
              session: _state.widget.session,
              // The host hears the page itself — the panel moves it.
              reading: _state._views._timesheetPage,
              viewportController: _state._views._timesheetViewport,
              inkController: _state._views._timesheetInk,
              brushToolState: _state._brushTool,
              brushAllowed: _state._views._timesheetBrushAllowed.value,
              onBrushAllowedChanged: (enabled) {
                _state._views._timesheetBrushAllowed.value = enabled;
              },
              dataSheet: _state._views._timesheetDataSheet.value,
              onDataSheetChanged: (shown) {
                _state._views._timesheetDataSheet.value = shown;
              },
              // The files the ink's photos are drawn from (I-97), from the
              // decode cache the conte and the envelope print from.
              imageFor: _state._views._sheetImages.imageFor,
              imageRepaint: _state._views._sheetImages,
            ),
          ),
        );
      default:
        throw ArgumentError.value(tabId, 'tabId', 'Unknown panel tab');
    }
  }

  /// Which panel is currently lying on the floor.
  String? activeFloorTabId() =>
      _state._layout.activeTabIn(_state._laidFloorDockId());

  /// The top strip's canvas/viewer switch: swap what the app is lying on.
  ///
  /// Selecting is the whole job when the panel is already down there, which
  /// is the default arrangement. It is not the only arrangement — a panel
  /// can be dragged anywhere, and a workspace saved before the floor existed
  /// still has the viewer among the paper tabs — so a switch that only
  /// selected would be a dead button for exactly the people whose layout
  /// predates it. Fetching it back is what makes the switch mean the same
  /// thing every time it is pressed.
  ///
  /// Pressed while a top strip group lies there, it takes the floor back.
  void selectFloorTab(String tabId) {
    _state._claimPanelOf(tabId);
    final tabs = _state._layout.tabsIn(EditorWorkspace.centerGroupId);
    if (tabs.contains(tabId)) {
      _state._mutatingLayout(() {
        _state._laidFloorTab.value = null;
        _state._layout.selectTab(EditorWorkspace.centerGroupId, tabId);
      });
      return;
    }
    _state._mutatingLayout(() {
      _state._laidFloorTab.value = null;
      // A panel CLOSED from the Panels list is in no dock at all, and
      // `moveTab` moves only what it can already locate — so pressing
      // 캔버스 after closing the canvas did nothing whatsoever, and the
      // Panels list was the only way back to the app's own floor. Adding
      // it is the same answer `_revealPanel` already gives, and `addTab`
      // does not front what it appends, so say which one is showing.
      if (_state._layout.locateTab(tabId) == null) {
        _state._layout.addTab(tabId, toDockId: EditorWorkspace.centerGroupId);
      } else {
        _state._layout.moveTab(
          tabId: tabId,
          toDockId: EditorWorkspace.centerGroupId,
          insertIndex: tabs.length,
        );
      }
      _state._layout.selectTab(EditorWorkspace.centerGroupId, tabId);
    });
  }
}

/// What the tool settings show of the session ([_WorkspaceTabs
/// ._toolSettingsCut]): equal answers, no rebuild. The tips compare by the
/// list — the library hands a new one for every change.
typedef _ToolSettingsCut = ({
  List<BrushTipEntry> tips,
  CutGuides guides,
  GuideId? selectedGuideId,
  ByList<String>? fillReads,
  ByList<String>? eyedropperReads,
  PasteboardWall? pasteboard,
  AppLanguage language,
});
