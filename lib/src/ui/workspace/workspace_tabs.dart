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
  /// homes, then anything else actually lying down there.
  ///
  /// 🚨 That tail is not a nicety, it closes a trap. The floor has NO tab
  /// strip ([_state._docks.buildCenterDock] builds it `chromeless`), so a panel
  /// dragged onto the center dock has no button anywhere — and the Panels
  /// menu reports it as OPEN, so the only thing that menu offers for it is
  /// CLOSING it. Listing whatever is down there is what makes it reachable
  /// again, for every panel and not just the viewers.
  ///
  /// Deliberately NOT a static list with the sub viewer added to it: that
  /// spelling would give the sub viewer a permanent button meaning "pull
  /// me off the rail and onto the floor", which is the opposite of what a
  /// panel that exists to sit beside the drawing is for.
  List<String> floorTabIds() {
    final onTheFloor = _state._layout.tabsIn(EditorWorkspace.centerGroupId);
    return [
      ..._EditorWorkspaceState._floorHomeTabIds,
      for (final tabId in onTheFloor)
        if (!_EditorWorkspaceState._floorHomeTabIds.contains(tabId)) tabId,
    ];
  }

  void closeTab(String tabId) {
    _state._mutatingLayout(() => _state._layout.removeTab(tabId));
  }

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
      // Keeps its decoded pages/PDF document across tab switches.
      keepAlive: true,
      builder: (context) => PanelAwareListenableBuilder(
        // The request is the HOST's own subscription; the position and
        // the viewport are read as VALUES here, so they rebuild from
        // this side.
        listenable: Listenable.merge([
          slot.viewport,
          slot.position,
          _state.widget.session.languageSettings,
        ]),
        builder: (context) => MediaViewerTabHost(
          viewerId: tabId,
          session: _state.widget.session,
          request: slot.request,
          position: slot.position.value,
          onPositionChanged: (position) => slot.position.value = position,
          onRequestPicked: slot.open,
          viewportController: slot.viewport,
          framedFor: slot.framedFor,
          onSwapViewers: () => _state._swapViewers(fromTabId: tabId),
          // I-14: the cut tool reaches the viewer, and a cut there lands in
          // the piece the canvas's cuts fill.
          brushTool: _state._brushTool,
          cutPieceSlot: _state._cutPieceSlot,
          // 유저 확정 ⑱: the promote button calls the SAME import every
          // other entrance calls, and takes the SAME copy-or-reference
          // default the import window opens on — a viewer-only policy
          // here would be a third import surface nobody remembers to fix.
          //
          // ⚠️The same default the import window starts on: the project
          // carries what it can. This button exists to promote a loose
          // path into something that travels with the project, so a
          // reference here would be the one answer it cannot mean.
          onRegisterAsset: (path) => _state.widget.session.mediaPool.importMediaFiles([
            path,
          ], copyIntoProject: true),
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
      // wheel and the palette both shrink on their own and say nothing.
      minContentHeight: kind == ColorPickerKind.rgb
          ? ColorPickerPanel.rgbContentExtent
          : null,
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

  EditorPanelTab tabFor(String tabId) {
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
          builder: (context) =>
              SlicedValueListenableBuilder<BrushToolState, CanvasTool>(
                valueListenable: _state._brushTool,
                slice: (state) => state.tool,
                builder: (context, toolState) => ToolsPanel(
                  tool: toolState.tool,
                  // Applied at PRESS time, not build time: the rail memory is
                  // the notifier's, not state this builder is sliced on.
                  onPress: _state._pressTool,
                  // The between-strokes group. Its own listeners, so undoing
                  // does not rebuild the tool column above it.
                  historyControls: _state._rail._railHistoryControls(),
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
          keepAlive: true,
          // The one panel that opts out of the static bake. It is full
          // of repaint boundaries by design (the artwork, the cursor
          // deck, the ants each own one), and its live-stroke path must
          // never be asked for a full-surface copy. It also does not
          // need it: with every panel closed, a canvas full of artwork
          // measured 2.5 ms hovering and 4.9 ms mid-stroke.
          staticRaster: false,
          builder: (context) => Stack(
            fit: StackFit.expand,
            children: [
              EditorCanvasArea(
                key: _state._canvasAreaKey,
                onInvokeAction: _state.widget.onInvokeAction,
                session: _state.widget.session,
                brushToolState: _state._brushTool,
                onBrushToolStateChanged: (state) =>
                    _state._brushTool.value = state,
                canvasViewCommands: _state.widget.canvasViewCommands,
                navigationRegionKey: _state.widget.canvasNavigationRegionKey,
                canvasSelectionCommands: _state.widget.canvasSelectionCommands,
                cutPieceSlot: _state._cutPieceSlot,
                cameraViewEnabled: _state._views._cameraViewEnabled,
                cameraDimOpacity: _state._views._cameraDimOpacity,
                expandedLaneLayerIds: _state._expandedLaneLayerIds,
                fillOptions: _state._views._fillOptions,
                selectionMaskOptions: _state._views._selectionMaskOptions,
                transformOptions: _state._transformOptions,
                eyedropperSource: _state._views._eyedropperSource,
                flipHud: _state.widget.flipHud,
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
                            selectedPresetId: toolState.presetId,
                            viewOptions: _state._brushPresetView.value,
                            onViewOptionsChanged: (options) {
                              _state._brushPresetView.value = options;
                              _state._layoutPersistence.scheduleLayoutSave();
                            },
                            onPresetApplied: _state._brushPresets._applyPreset,
                            onPresetSaveRequested:
                                _state._brushPresets.saveHeldBrushAsPreset,
                            onPresetDeleted: _state._presetLibrary.delete,
                            onPresetRenamed: _state._presetLibrary.rename,
                            onPresetsReordered: _state._presetLibrary.reorder,
                            onPresetImportRequested: () {
                              unawaited(
                                _state._brushPresets._importAndNotice(
                                  _state._presetLibrary.importFromFile,
                                ),
                              );
                            },
                            onGroupCreated: _state._presetLibrary.createGroup,
                            onGroupEdited: _state._presetLibrary.editGroup,
                            onGroupDeleted: _state._presetLibrary.deleteGroup,
                            onGroupsReordered:
                                _state._presetLibrary.reorderGroups,
                            onLibraryReset:
                                _state._presetLibrary.resetToDefaults,
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
                        guideLibrary: ListenableBuilder(
                          listenable: _state.widget.session,
                          builder: (context, _) => GuideLibraryList(
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
                                _state.widget.session.selectedGuideId,
                            onGuideSelected: (id) =>
                                _state.widget.session.selectedGuideId = id,
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
                                ValueListenableBuilder<CanvasColorSampleSource>(
                                  valueListenable:
                                      _state._views._eyedropperSource,
                                  // The tip library loads in two passes,
                                  // so the pickers have to follow it.
                                  builder: (context, eyedropperSource, _) =>
                                      ListenableBuilder(
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
                                        ]),
                                        builder: (context, _) => ToolSettingsPanel(
                                          state: toolState,
                                          onChanged: (state) =>
                                              _state._brushTool.value = state,
                                          guides: _state
                                              .widget
                                              .session
                                              .cutVerbs
                                              .activeCutGuides,
                                          selectedGuideId: _state
                                              .widget
                                              .session
                                              .selectedGuideId,
                                          onGuidesCommitted: _state
                                              .widget
                                              .session
                                              .cutVerbs
                                              .setActiveCutGuides,
                                          tips: _state._tipLibrary.tips,
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
                                          language: _state
                                              .widget
                                              .session
                                              .languageSettings
                                              .value
                                              .programLanguage,
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
              size: tool.size,
              onSizeSelected: (size) => _state._brushTool.value = _state
                  ._brushTool
                  .value
                  .copyWith(size: size),
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
            listenable: _state.widget.session,
            builder: (context, _) => MediaPoolPanel(
              assets: _state.widget.session.mediaPool.mediaAssets,
              // F-118: one list per file — the mark, its window and the
              // remove's question all read the session's answer.
              usesOf: (path) => _state.widget.session.mediaPool
                  .mediaAssetUses(path)
                  .map(mediaAssetUseLine),
              onImportRequested: () => _state._openImportWindow(poolOnly: true),
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
          minContentWidth: _state._minContentWidthFor(tabId),
          minContentHeight: _state._minContentHeightFor(tabId),
          locked: locked,
          // The heavy frame-axis panels keep their subtree offstage
          // across switches (R10-②) — switching back is instant.
          keepAlive: true,
          // 유저 확정 (2026-08-10): 재생 그룹과 설정은 문턱으로. Only the
          // ACTIVE tab's sill controls are mounted, so the timeline's
          // active-cut transport and the storyboard's all-cuts one share
          // the one strip without either knowing about the other.
          // 접으면 버튼행만 (유저 확정): the panel keeps its command bar and
          // offstages the grid, so the fold is 문턱 30 + this 36 = 66 — and
          // every verb a rough pass needs is still on screen while folded.
          collapsedExtent: TimelineCommandBar.height,
          sillTrailing: (context) => FramePanelSillControls(
            session: _state.widget.session,
            scope: PlaybackScope.activeCut,
            cameraViewEnabled: _state._views._cameraViewEnabled,
            cameraViewKeyValue: 'timeline-camera-view-button',
            playbackStartFrame: () => _state.widget.session.currentFrameIndex,
            onSkipToStart: () => _state.widget.session.selectFrameIndex(0),
          ),
          builder: (context) => PanelAwareListenableBuilder(
            // The session subscription lives HERE now (HomePage no longer
            // setStates the world). Seeks are NOT session notifies — the
            // grids ride the frame cursor and never rebuild for them.
            // Panel-aware (R12-①): notifies arriving while the tab sits
            // offstage are deferred to one catch-up on re-activation.
            listenable: Listenable.merge([
              _state.widget.session,
              _state._timelineOrientation,
              // Zoom (_timelinePixelsPerFrame) is NOT merged here (UI-R6
              // #4): the host scopes it to the panel subtree, so a zoom
              // step skips this whole tab rebuild.
              _state._showSecondsDisplay,
              _state._expandedLaneLayerIds,
              _state._expandedLaneGroupKeys,
              _state._hiddenTimelineSections,
              _state._collapsedAttachBaseIds,
              _state._timelineRowFilter,
            ]),
            builder: (context) => TimelineTabHost(
              session: _state.widget.session,
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
                _state._openImportWindow(
                  initialPaths: [path],
                  placeOnly: true,
                  spot: spot,
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
                _state._openImportWindow(
                  initialPaths: [path],
                  placeOnly: true,
                  spot: spot,
                );
              },
              orientation: _state._timelineOrientation.value,
              onOrientationChanged: (orientation) {
                _state._timelineOrientation.value = orientation;
                _state._flipHud.syncFlipAxisWithTimeline();
              },
              pixelsPerFrame: _state._timelinePixelsPerFrame.value,
              pixelsPerFrameListenable: _state._timelinePixelsPerFrame,
              onPixelsPerFrameChanged: (value) {
                _state._timelinePixelsPerFrame.value = value;
              },
              showSeconds: _state._showSecondsDisplay.value,
              onShowSecondsChanged: (show) {
                _state._showSecondsDisplay.value = show;
              },
              timelineRailExtent: _state._railExtents[LayerRailId.timeline],
              xsheetRailExtent: _state._railExtents[LayerRailId.xsheet],
              timelineFrameAxisOffset:
                  _state._frameAxisOffsets[LayerRailId.timeline],
              xsheetFrameAxisOffset: _state._frameAxisOffsets[LayerRailId.xsheet],
              expandedLaneLayerIds: _state._expandedLaneLayerIds.value,
              onToggleLayerLanes: _state._toggleLayerLanes,
              expandedLaneGroupKeys: _state._expandedLaneGroupKeys.value,
              onToggleLaneGroupKey: _state._rail._toggleLaneGroup,
              hiddenSections: _state._hiddenTimelineSections.value,
              onToggleSection: _state._toggleTimelineSection,
              rowFilter: _state._timelineRowFilter.value,
              onSetRowFilter: _state._setTimelineRowFilter,
              collapsedAttachBaseIds: _state._collapsedAttachBaseIds.value,
              onToggleAttachGroup: _state._rail._toggleAttachGroup,
              // Unified layer controls: the camera row's visibility/opacity
              // drive the same camera-view state as the canvas overlay and
              // the camera panel.
              cameraViewEnabled: _state._views._cameraViewEnabled,
              cameraDimOpacity: _state._views._cameraDimOpacity,
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
          minContentWidth: _state._minContentWidthFor(tabId),
          minContentHeight: _state._minContentHeightFor(tabId),
          locked: locked,
          keepAlive: true,
          // The same sill controls the timeline mounts — a different
          // playlist and a different "to start", and nothing else.
          collapsedExtent: TimelineCommandBar.height,
          sillTrailing: (context) => FramePanelSillControls(
            session: _state.widget.session,
            scope: PlaybackScope.allCuts,
            cameraViewEnabled: _state._views._cameraViewEnabled,
            cameraViewKeyValue: 'storyboard-camera-view-button',
            playbackStartFrame: () =>
                storyboardPlayheadFrame(_state.widget.session) ?? 0,
            onSkipToStart: () =>
                seekStoryboardPlayheadToTrackStart(_state.widget.session),
          ),
          builder: (context) => PanelAwareListenableBuilder(
            // Session subscription — the timeline tab's list exactly, and
            // for the same reason: seeks are NOT session notifies, so this
            // panel never rebuilds for one. Scrub moves, playback ticks and
            // committed seeks all ride the host's own channels (playhead
            // overlay + ruler, the rail's lane-label cursor, the command
            // bar's own subscription). `frameSeekCommitted` sat in THIS
            // merge until 2026-08-05 and cost a whole-panel rebuild per
            // arrow press — measured at 38ms a step (12 build / 22 layout /
            // 3 paint) with a six-cut project. Panel-aware (R12-①):
            // offstage notifies defer to one catch-up on re-activation.
            listenable: Listenable.merge([
              _state.widget.session,
              _state._storyboardPixelsPerFrame,
              _state._storyboardTrackLaneHeight,
              _state._showSecondsDisplay,
              _state._storyboardThumbnails,
            ]),
            builder: (context) => StoryboardTabHost(
              session: _state.widget.session,
              // A pool row let go on a track's frames: the place window, with
              // the drop's answer — a NEW cut there — shown locked.
              onPlaceMediaAsset: (path, spot) => _state._openImportWindow(
                initialPaths: [path],
                placeOnly: true,
                spot: spot,
              ),
              // R5 #9: ONE filter across the surfaces — the same state the
              // timeline and the sheet read, so a chip set on one is set
              // wherever the legend appears.
              rowFilter: _state._timelineRowFilter.value,
              onSetRowFilter: _state._setTimelineRowFilter,
              pixelsPerFrame: _state._storyboardPixelsPerFrame.value,
              onPixelsPerFrameChanged: (value) {
                _state._storyboardPixelsPerFrame.value = value;
              },
              showSeconds: _state._showSecondsDisplay.value,
              onShowSecondsChanged: (show) {
                _state._showSecondsDisplay.value = show;
              },
              railExtent: _state._railExtents[LayerRailId.storyboard],
              frameAxisOffset: _state._frameAxisOffsets[LayerRailId.storyboard],
              // ⛔No height setter any more (B7): the steppers left the bar,
              // and the planned V-track splitter is the next writer.
              trackLaneHeight: _state._storyboardTrackLaneHeight.value,
              thumbnailFor: _state._storyboardThumbnails.thumbnailFor,
              // ⛔The camera-view notifier no longer comes through here:
              // R28 #1's toggle rides the sill with the transport now
              // (`sillTrailing` above), so the panel does not see it.
            ),
          ),
        );
      case EditorWorkspace.conteTabId:
        return EditorPanelTab(
          id: tabId,
          label: AppText.strings.panelConte,
          icon: Icons.grid_on_outlined,
          buttonKey: const ValueKey<String>('timeline-mode-conte-button'),
          minContentWidth: _state._minContentWidthFor(tabId),
          minContentHeight: _state._minContentHeightFor(tabId),
          locked: locked,
          keepAlive: true,
          // The sheet reads the project and the SAME picture store the
          // storyboard strip draws from, so a cell and its strip panel are
          // one render rather than two that must be kept in step.
          // _brushTool is deliberately NOT merged (R18 UI-3): only the
          // ink overlay consumes it, through its own boundary builder.
          builder: (context) => PanelAwareListenableBuilder(
            listenable: Listenable.merge([
              _state.widget.session,
              _state._storyboardThumbnails,
              _state._views._conteViewport,
              _state._views._conteInkEnabled,
              _state._views._conteInk,
              // The locale reprints the sheet chrome (labels/tooltips).
              _state.widget.session.languageSettings,
            ]),
            builder: (context) => ConteTabHost(
              session: _state.widget.session,
              thumbnailFor: _state._storyboardThumbnails.thumbnailFor,
              // A landed thumbnail render repaints the page painter
              // directly (its compared fields don't change for async
              // pictures).
              thumbnailRepaint: _state._storyboardThumbnails,
              // The notifier ITSELF — the panel writes into this one, so
              // there is no copy to echo and nothing to go stale while the
              // panel is unmounted.
              viewportController: _state._views._conteViewport,
              inkController: _state._views._conteInk,
              brushToolState: _state._brushTool,
              inkEnabled: _state._views._conteInkEnabled.value,
              onInkEnabledChanged: (enabled) {
                _state._views._conteInkEnabled.value = enabled;
              },
            ),
          ),
        );
      case EditorWorkspace.envelopeTabId:
        return EditorPanelTab(
          id: tabId,
          label: AppText.strings.panelEnvelope,
          icon: Icons.mail_outline,
          buttonKey: const ValueKey<String>('timeline-mode-envelope-button'),
          minContentWidth: _state._minContentWidthFor(tabId),
          minContentHeight: _state._minContentHeightFor(tabId),
          locked: locked,
          keepAlive: true,
          // _brushTool is deliberately NOT merged (R18 UI-3): only the ink
          // overlay consumes it, through its own boundary builder.
          builder: (context) => PanelAwareListenableBuilder(
            listenable: Listenable.merge([
              _state.widget.session,
              _state._views._envelopeViewport,
              _state._views._envelopeInkEnabled,
              _state._views._envelopeFormId,
              _state._views._envelopeInk,
              // F-90: the envelope of the cut under the playhead, turning
              // over at a crossing like the sheet beside it.
              _state.widget.session.cutUnderPlayhead.listenable,
              _state.widget.session.languageSettings,
            ]),
            builder: (context) => CutEnvelopeTabHost(
              session: _state.widget.session,
              formId: _state._views._envelopeFormId.value,
              onFormIdChanged: (formId) {
                _state._views._envelopeFormId.value = formId;
              },
              viewportController: _state._views._envelopeViewport,
              inkController: _state._views._envelopeInk,
              brushToolState: _state._brushTool,
              inkEnabled: _state._views._envelopeInkEnabled.value,
              onInkEnabledChanged: (enabled) {
                _state._views._envelopeInkEnabled.value = enabled;
              },
              // 🚨WIRED NOW. The comment that stood here said this waited on
              // the 작품 정보 round because nothing set a logo or a 도장 path
              // yet, so a resolver had no source. The stamp picker in the
              // sheet-info window is that source.
              imageFor: _state._views._envelopeImages.imageFor,
            ),
          ),
        );
      case EditorWorkspace.timesheetTabId:
        return EditorPanelTab(
          id: tabId,
          label: AppText.strings.panelTimesheet,
          icon: Icons.table_chart_outlined,
          locked: locked,
          // Manages its own seams: the sheet's two strata are baked
          // separately so a content change never re-records the grid,
          // and the playhead and ink windows sit ABOVE both bakes so
          // they stay live. A wrapper around the whole tab would have
          // to include the playhead, and would then stand itself down
          // for the whole of playback.
          staticRaster: false,
          keepAlive: true,
          builder: (context) => PanelAwareListenableBuilder(
            // _brushTool is deliberately NOT merged here (R18 UI-3): the
            // sheet layout never depends on it, and rebuilding the whole
            // (keep-alive, often hidden) B4 document on every tool
            // switch / color notch was measurably half the tool-switch
            // jank. Only the ink overlay consumes the tool state, through
            // its own boundary builder inside the host.
            listenable: Listenable.merge([
              _state._views._timesheetContinuous,
              _state._views._timesheetPage,
              _state._views._timesheetViewport,
              _state._views._timesheetInkEnabled,
              // F-90: a crossing, played or dragged over, turns the sheet
              // over to the cut under the playhead.
              _state.widget.session.cutUnderPlayhead.listenable,
              // The notation language reprints the sheet (UI-R10 #7).
              _state.widget.session.languageSettings,
            ]),
            builder: (context) => TimesheetTabHost(
              session: _state.widget.session,
              continuous: _state._views._timesheetContinuous.value,
              onContinuousChanged: (continuous) {
                _state._views._timesheetContinuous.value = continuous;
              },
              page: _state._views._timesheetPage.value,
              onPageChanged: (page) {
                _state._views._timesheetPage.value = page;
              },
              viewportController: _state._views._timesheetViewport,
              inkController: _state._views._timesheetInk,
              brushToolState: _state._brushTool,
              inkEnabled: _state._views._timesheetInkEnabled.value,
              onInkEnabledChanged: (enabled) {
                _state._views._timesheetInkEnabled.value = enabled;
              },
            ),
          ),
        );
      default:
        throw ArgumentError.value(tabId, 'tabId', 'Unknown panel tab');
    }
  }

  /// Which panel is currently lying on the floor.
  String? activeFloorTabId() =>
      _state._layout.activeTabIn(EditorWorkspace.centerGroupId);

  /// The top strip's canvas/viewer switch: swap what the app is lying on.
  ///
  /// Selecting is the whole job when the panel is already down there, which
  /// is the default arrangement. It is not the only arrangement — a panel
  /// can be dragged anywhere, and a workspace saved before the floor existed
  /// still has the viewer among the paper tabs — so a switch that only
  /// selected would be a dead button for exactly the people whose layout
  /// predates it. Fetching it back is what makes the switch mean the same
  /// thing every time it is pressed.
  void selectFloorTab(String tabId) {
    final tabs = _state._layout.tabsIn(EditorWorkspace.centerGroupId);
    if (tabs.contains(tabId)) {
      _state._mutatingLayout(() {
        _state._layout.selectTab(EditorWorkspace.centerGroupId, tabId);
      });
      return;
    }
    _state._mutatingLayout(() {
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
