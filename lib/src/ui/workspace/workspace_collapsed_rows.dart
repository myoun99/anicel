part of '../editor_workspace.dart';

/// The COLLAPSED ROWS — the one-row timeline the workspace shows while the
/// timeline panel is collapsed: its height, its rail and track and frame
/// rows, its overlay and the flip HUD row — as their own object.
///
/// 🚨A collaborator carved out of `_EditorWorkspaceState` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: two fields of its own and eleven
/// State members shared. It reaches the State through `_state`.
class _WorkspaceCollapsedRows {
  _WorkspaceCollapsedRows(this._state);

  final _EditorWorkspaceState _state;

  /// The collapsed row over the artwork — only for the tabs that HAVE a row
  /// to show. A collapsed conte or viewer says nothing here, which is the
  /// same answer its zero [EditorPanelTab.collapsedExtent] gives inside.
  ///
  /// It reads the FLIP HUD's snapshot on purpose (see [CollapsedRowOverlay]):
  /// one description of "where am I", built from the rows the timeline is
  /// displaying, so the thing that moves the cursor and the thing that draws
  /// it cannot disagree.
  Widget collapsedRowOverlay() {
    final tabId = _state._layout.activeTabIn(EditorWorkspace.bottomGroupId);
    if (tabId != EditorWorkspace.timelineTabId &&
        tabId != EditorWorkspace.storyboardTabId) {
      return const SizedBox.shrink();
    }
    // Keyed by the project, like every panel ([_WorkspaceTabs.tabFor]): the
    // row mounts the timeline's own row widgets, whose State is the
    // project's.
    return KeyedSubtree(
      key: ObjectKey(_state.widget.session),
      child: ListenableBuilder(
        listenable: _collapsedRowStructure,
        builder: (context, _) => _collapsedRow(),
      ),
    );
  }

  /// Whether the folded row is the STORYBOARD's — its track row rather
  /// than the timeline's layer row.
  ///
  /// D15 (유저 2026-08-21: 「트랙이 보여야 하는데 프레임이 보임 … 심지어
  /// 수정 전 구버전 간편오버레이가 보임」). Both symptoms were one cause and
  /// it was not a copy: `collapsedRowOverlay` let either tab through and
  /// then built the timeline's row unconditionally, so a folded storyboard
  /// showed the timeline's — unfamiliar, and rightly reported as "an old
  /// version". There was no storyboard branch at all.
  bool get _collapsedRowIsStoryboard =>
      _state._layout.activeTabIn(EditorWorkspace.bottomGroupId) ==
      EditorWorkspace.storyboardTabId;

  /// THE folded row's height — the height of the row it is showing.
  ///
  /// 유저 확정 (2026-08-21): 「간편오버레이 높이도 해당 행 높이에따라서 맞춤.
  /// 이 높이 맞추는건 타임라인의 간편오버레이든 동일하게」 — one law, both
  /// panels. The storyboard's V row is as tall as its own splitter left it
  /// ([StoryboardPanel.trackLaneHeight], D15 ④); a timeline row asks the
  /// timeline's own per-row rule, which answers one number today and stays
  /// the place to change if it ever answers two.
  ///
  /// ⚠️Every consumer of the fold's height reads THIS — the row itself, the
  /// space the region reserves above the canvas, and the floor inset. That
  /// was already the intent (「그래야 수정했을때 아무것도 안고치고
  /// 반영되니까」); it just had a constant to read instead of a row.
  /// ⚠️The timeline half is the row height the panel builds its metrics
  /// from ([timelineLayerRowHeightIn] — a row grows with its words under the
  /// OS text size), because that is what [timelineDisplayRowExtent] answers
  /// for EVERY timeline row — the rule is real, it simply has one answer
  /// today. If it ever grows a second, that function is where it grows and
  /// this line follows it there.
  double collapsedRowHeight() => _collapsedRowIsStoryboard
      ? _state._storyboardTrackLaneHeight.value
      : timelineLayerRowHeightIn(_state.context);

  Widget _collapsedRow() {
    if (_collapsedRowIsStoryboard) {
      return _collapsedTrackRow();
    }
    final rail = _state._railExtents[LayerRailId.timeline];
    return CollapsedRowOverlay(
      height: collapsedRowHeight(),
      snapshot: _state._flipHud.flipHudSnapshot(FlipHudAxis.frame),
      // 유저 확정: 레일 폭은 가로 스플리터를 그대로 따라간다 — the same
      // stored window the panel's own rail lays out against, so narrowing
      // one narrows the other by construction rather than by agreement.
      //
      // 🚨⛔It used to hand over `rail?.value ?? layerRailMinimumWindowExtent`,
      // and a null `value` does NOT mean the minimum — it means 「자연폭」.
      // Reading it as the minimum sized the overlay's rail at
      // `layerRailLeadingWidth + 14`: the leading cluster plus one letter of
      // the name, which is the `▸ ▦ ● 🎞 A` in the user's photo. That one
      // line made three complaints out of one bug — 「버튼이 없다」,
      // 「길이가 다르다」, 「열이 안 맞는다」 — and the buttons were never
      // removed, only cut off outside the window.
      //
      // Handing the OBJECT over lets `LayerRailWindow` answer it, the same
      // way the panel's own rail does.
      rail: rail,
      naturalRailWidth: _collapsedMetrics().layerControlsWidth,
      // 🚨F-143: and the frame axis where the open grid left it — the same
      // kept value that grid is handed, so the folded row shows the frames
      // the open one was showing instead of frame 0.
      frameAxisOffset: _state._frameAxisOffsets[LayerRailId.timeline],
      // Where the open grid starts its wash — the drawn end, のりしろ
      // included — so the folded row's starts at the same frame.
      drawnFrameCount: _state.widget.session.activeCutSpan
          .activeCutDrawnFrameCount,
      pixelsPerFrame: _state._timelinePixelsPerFrame.value,
      framesPerSecond: _state.widget.session.projectSettings.projectFrameRate.countingBase,
      railChild: _collapsedRailRow(),
      frameRowBuilder: _collapsedFrameRowBuilder(),
    );
  }

  /// The folded STORYBOARD's row — the track, with its cuts as blocks.
  ///
  /// Same shell, same law, different row: the rail half mounts the panel's
  /// own [StoryboardTrackLabelRow] chromeless (the timeline half mounts its
  /// real controls row for exactly this reason) and the frame half asks
  /// [storyboardCutBlocksPainterFor], the call the panel's track row makes.
  /// 「썸네일 띄움 · 텍스트같은것도 같은 규칙따라서 위치 맞춤」 (D15 ③) is
  /// therefore not implemented here at all — it arrives with the painter.
  ///
  /// ⚠️Its rail is the STORYBOARD's window, not the timeline's: they are
  /// two splitters over two different rails, and reading the timeline's
  /// here is what would put the folded row's columns out of step with the
  /// panel it folded.
  Widget _collapsedTrackRow() {
    final session = _state.widget.session;
    final trackId = session.selectedTrackId;
    final entries = [
      for (final entry in session.projectSettings.projectLayout())
        if (entry.trackId == trackId) entry,
    ];
    final track = entries.isEmpty
        ? null
        : session.trackOwningCut(entries.first.cutId);
    final pixelsPerFrame = _state._storyboardPixelsPerFrame.value;
    final height = collapsedRowHeight();
    return CollapsedRowOverlay(
      height: height,
      // The TRACK snapshot — the same one the flip window shows on this
      // axis, so the two summaries of "where am I" cannot disagree.
      snapshot: _state._flipHud._flipHudTrackSnapshot(session),
      rail: _state._railExtents[LayerRailId.storyboard],
      // F-143: the storyboard's own axis, beside its own rail window.
      frameAxisOffset: _state._frameAxisOffsets[LayerRailId.storyboard],
      naturalRailWidth: StoryboardTrackLabelRow.railWidthIn(_state.context),
      pixelsPerFrame: pixelsPerFrame,
      framesPerSecond: session.projectSettings.projectFrameRate.countingBase,
      // No track (an empty film) falls back to the overlay's own strip,
      // which draws the snapshot — the same fallback the timeline's lane
      // rows take.
      railChild: track == null
          ? null
          : StoryboardTrackLabelRow(
              track: track,
              // The panel labels its V rows by POSITION, and this is the
              // selected one; a film has one track (전제 8), so the index
              // is 0 and the label is V1.
              trackLabel: 'V1',
              laneHeight: height,
              chromeless: true,
              activeCut: session.activeCutOrNull,
              subjectCut: session.activeCutOrNull,
              cutPictureVisibleOf: session.isCutPictureVisible,
            ),
      frameRowBuilder: track == null
          ? null
          : (context, geometry) => CustomPaint(
              key: const ValueKey<String>('collapsed-storyboard-cut-blocks'),
              painter: storyboardCutBlocksPainterFor(
                entries: entries,
                geometry: geometry,
                crossAxisExtent: height,
                minBlockWidth: StoryboardPanel.cutBlockMinWidth,
                activeCutId: session.activeCutOrNull?.id,
                rowAddress: TrackRowAddress(track.id),
                colorScheme: Theme.of(context).colorScheme,
                baseTextStyle:
                    Theme.of(context).textTheme.labelSmall ??
                    DefaultTextStyle.of(context).style,
                showSeconds: _state._showSecondsDisplay.value,
                countingBase: session.projectSettings.projectFrameRate.countingBase,
                // D15 ③: the thumbnails come from the store the panel
                // draws from, so a picture rendered for one is already
                // rendered for the other.
                thumbnails: _state._storyboardThumbnails.thumbnails,
              ),
            ),
    );
  }

  /// The rail half of the collapsed row: the REAL rail row, chromeless.
  ///
  /// 유저 확정: 「기존에 있는 fx접기버튼·타임시트on·레이어아이콘·레이어이름
  /// 이런 거 싹 그대로」. Mounting the row is the only way to mean *그대로* —
  /// a second widget listing the same slots would be right on the day it was
  /// written and wrong on the day the rail grows a column.
  ///
  /// The callbacks are all no-ops: the overlay is inside an `IgnorePointer`,
  /// so nothing here can be pressed and the row never asks who would answer.
  /// Null for a property lane — the rail shows a name and a value there, not
  /// a control cluster, and the overlay draws that itself.
  Widget? _collapsedRailRow() {
    final session = _state.widget.session;
    // A LAYER row only. The sealed address is what decides — a lane is a
    // different shape of rail and the overlay draws that half itself.
    final row = session.currentRow;
    if (row is! LayerRowAddress) {
      return null;
    }
    final layer = session.layers
        .where((candidate) => candidate.id == row.layerId)
        .firstOrNull;
    if (layer == null) {
      return null;
    }
    final controls = TimelineLayerControlsRow(
      chromeless: true,
      layer: layer,
      active: true,
      // 🚨THE TIMELINE'S OWN NUMBERS (유저 2026-08-13: 「레이어영역의
      // 가로길이같은거 타임라인 그대로 가져와. 그래야 열의 규격이 맞을거니까」).
      // This used to be `TimelineGridMetrics.defaults` while the panel drew
      // with `defaults.copyWith(frameCellWidth: …)` — two metrics for one row,
      // which is exactly the kind of second opinion mounting the real row was
      // supposed to end.
      metrics: _collapsedMetrics(),
      // The view state the rail reads, from the same places the timeline tab
      // reads it — not a second opinion, the same getters.
      fxState: session.effectsAndFx.layerFxState(layer.id),
      onionSkinEnabled: session.onionSkin.isLayerOnionSkinEnabled(layer.id),
      isLayerSoloed: session.visibilitySolo.soloedSeLayerIds.value.contains(
        layer.id,
      ),
      linkPartners: session.layerVerbs.linkPartnersOf(layer.id),
      // A row HAS lanes when its lanes are not empty — the same question the
      // panel asks. Hardcoding `true` gave a twirl to rows that have nothing
      // to twirl.
      hasLanes: timelineLanesForLayer(
        layer: layer,
        session: session,
        expandedGroupKeys: session.railView.expandedLaneGroupKeys.value,
      ).isNotEmpty,
      lanesExpanded: session.railView.expandedLaneLayerIds.value.contains(
        layer.id,
      ),
      // 🚨A NULL CALLBACK IS NOT "no handler", IT IS "NO COLUMN": this row
      // reads `onToggleLayerOnionSkin != null` and friends as whether the
      // slot exists at all. Leaving them out to mean "nothing can be pressed
      // here" is what deleted the buttons the user came back about — 「없는
      // 버튼이 많고 폭 규격이 안 맞는다」 — and it also shifted every column
      // after them, which is the other half of the same report.
      //
      // Handing over live no-ops is safe rather than sloppy: the whole
      // overlay sits inside an `IgnorePointer`, so nothing here can be
      // pressed and no callback can ever run.
      onSelectLayer: (_) {},
      onToggleLayerVisibility: (_) {},
      onLayerOpacityChanged: (_, _) {},
      onToggleLayerTimesheet: (_) {},
      onLayerMarkSelected: (_, _) {},
      onToggleLayerFx: (_) {},
      onToggleLayerOnionSkin: (_) {},
      onToggleLanes: (_) {},
      onToggleLayerFillReference: (_) {},
      onOpenLayerMixer: (_, _) {},
      onOpenLayerReference: (_, _) async {},
      onLayerBlendModeSelected: (_, _) {},
    );
    // Its eye is the rail's, a folder above that hides the row included
    // (F-185).
    return RailEyes.forLayers([layer], stack: session.layers, child: controls);
  }

  /// The metrics BOTH halves of the collapsed row are built from.
  ///
  /// One object, because the two halves are one row: the rail's columns and
  /// the frame cells beside them have to agree about how tall the row is and
  /// how wide a frame is, and the only way to guarantee that is to ask once.
  /// ⚠️The ROW HEIGHT is the overlay's, and it is the one number that may
  /// differ: the strip is its own height by design, while every horizontal
  /// measurement — rail width, section gutter, frame cell — comes from the
  /// panel so the columns line up under it.
  TimelineGridMetrics _collapsedMetrics() => TimelineGridMetrics(
    minimumVisibleFrameCells:
        TimelineGridMetrics.defaults.minimumVisibleFrameCells,
    layerControlsWidth: TimelineGridMetrics.defaults.layerControlsWidth,
    frameCellWidth: _state._timelinePixelsPerFrame.value,
    layerRowHeight: collapsedRowHeight(),
    verticalScrollbarWidth: TimelineGridMetrics.defaults.verticalScrollbarWidth,
    sectionLabelGutterWidth:
        TimelineGridMetrics.defaults.sectionLabelGutterWidth,
  );

  /// ⑩ 구조 = 리빌드: everything that changes the collapsed row's SHAPE.
  ///
  /// The root of ⑩ was not a stale snapshot — `_flipHudSnapshot` rebuilds
  /// correctly every pass. It was that nothing asked for a pass, so the
  /// overlay went on showing the build it was born with.
  ///
  /// 🚨The session is in here ON PURPOSE and it is not the rejected shape:
  /// a frame seek is NOT a session notify (see [selectFrameIndex]), so this
  /// fires when the row LIST changes and stays quiet while the playhead
  /// runs. 유저가 기각한 안은 「인덱스 옮길 때마다 위젯 싹 다시 만들기」이고
  /// the index never comes through here — it is the cursor layer's value
  /// channel, one layer down.
  ///
  /// Bound ONCE per project on screen ([bindSession]): a merge rebuilt per
  /// pass re-subscribes on every build.
  ///
  /// ⚠️BOTH panels' channels are in here, because either can be the folded
  /// row (D15). A storyboard-only zoom or a V-splitter drag changes this
  /// row's shape exactly as the timeline's own do, and a merge that knew
  /// only the timeline's would leave the folded track row showing the
  /// build it was born with — the very symptom ⑩ was.
  late Listenable _collapsedRowStructure;

  /// R26 #44's fact bundle for the collapsed row — bound ONCE per project,
  /// exactly like the timeline tab's own: a fresh bundle per build
  /// re-subscribes the row painters every pass and defeats the repaint
  /// gating it exists for.
  late TimelineCelContentSource _collapsedCelContent;

  /// Binds both to [session] — the workspace's door for the project coming
  /// on screen (I-7). They read the project's own notifiers, so a pair
  /// made once for the window would go on hearing the first project.
  void bindSession(EditorSessionManager session) {
    _collapsedRowStructure = Listenable.merge([
      session,
      session.railView.expandedLaneLayerIds,
      session.railView.expandedLaneGroupKeys,
      session.railView.hiddenSections,
      session.railView.rowFilter,
      session.railView.collapsedAttachBaseIds,
      _state._timelinePixelsPerFrame,
      _state._railExtents[LayerRailId.timeline],
      _state._storyboardPixelsPerFrame,
      _state._storyboardTrackLaneHeight,
      _state._showSecondsDisplay,
      _state._railExtents[LayerRailId.storyboard],
    ]);
    _collapsedCelContent = TimelineCelContentSource(
      hasContent: session.layerStack.celHasContentForLayer,
      revision: session.layerStack.celTintRevision,
    );
  }

  /// The FRAME half of the collapsed row: the REAL row the timeline draws.
  ///
  /// ⑩ 뿌리 C — the overlay used to draw this half itself, and every symptom
  /// reported against it was that copy falling behind the original: blocks
  /// that did not move, names that never appeared, SE rows shaped
  /// differently, an index that did not update. Mounting the row is the only
  /// version of *그대로* that stays true when the row grows a column.
  ///
  /// ★It costs nothing per frame tick, which is what makes it allowed here:
  /// `TimelineFrameCellsRow` is CURSOR-INDEPENDENT by design, so 구조는
  /// 리빌드 · 인덱스는 리페인트 is what mounting it already does — no
  /// overlay-wide `ListenableBuilder`, which is the shape the user rejected.
  ///
  /// Null for a row the timeline has no widget for — the gap's TRACK row,
  /// whose blocks are cuts rather than exposures. That one still falls back
  /// to the painter, and this is why it survives.
  Widget Function(BuildContext, TimelineFrameGeometryHandle)?
  _collapsedFrameRowBuilder() {
    final session = _state.widget.session;
    final row = session.currentRow;
    final layerId = switch (row) {
      LayerRowAddress(:final layerId) => layerId,
      LaneRowAddress(:final layerId) => layerId,
      _ => null,
    };
    if (layerId == null) {
      return null;
    }
    final layer = session.layers
        .where((candidate) => candidate.id == layerId)
        .firstOrNull;
    if (layer == null) {
      return null;
    }
    final metrics = _collapsedMetrics();
    final lane = row is LaneRowAddress
        ? timelineLanesForLayer(
            layer: layer,
            session: session,
            expandedGroupKeys: session.railView.expandedLaneGroupKeys.value,
          ).where((candidate) => candidate.laneId == row.laneId).firstOrNull
        : null;
    if (row is LaneRowAddress && lane == null) {
      return null;
    }
    final displayRow = lane == null
        ? TimelineDisplayRow.layer(layer, layerIndex: 0)
        : TimelineDisplayRow.lane(layer, lane, layerIndex: 0);
    return (context, geometry) => Stack(
      fit: StackFit.expand,
      children: [
        if (lane != null)
          TimelineLaneFrameRow(
            layer: layer,
            lane: lane,
            frameStartIndex: geometry.value.frameStartIndex,
            frameEndIndexExclusive: geometry.value.frameEndIndexExclusive,
            leadingFrameSpacerWidth: 0,
            trailingFrameSpacerWidth: 0,
            metrics: metrics,
            // Display-only: the overlay is inside an `IgnorePointer`, so
            // the band has nobody to answer.
          )
        else
          TimelineFrameCellsRow(
            layer: layer,
            // 🚨GROUND OFF — 유저 2026-08-13: 「원래 구상대로라면 프레임셀쪽은
            // 바탕색은 싹 없애고 … 전체적으로 반투명하게 하기로 하지
            // 않았나?」. Mounting the real row (⑩ root C) brought the
            // timeline's ground with it until the row was taught to drop it
            // (`chromeless`). ⇒ I-44: no row paints a ground any more — the
            // grid sheet under the rows does, and the overlay's sheet has no
            // ground to paint ([CollapsedRowOverlay]'s law: the artwork).
            // The row is its paper, here as in the panel.
            //
            // The panel's world, spelled the panel's way: this row bakes on
            // the one tile store now, which keeps ONE live generation.
            substrateGeneration: timelineSubstrateGeneration(
              projectId: session.repository.requireProject().id.value,
              cutId: session.activeCutId?.value,
            ),
            playbackFrameCount:
                session.activeCutSpan.activeCutPlaybackFrameCount,
            geometry: geometry,
            crossAxisExtent: collapsedRowHeight(),
            exposureStateForLayer: session.exposureStateForLayer,
            frameNameForLayer: session.frameVerbs.frameNameForLayer,
            celContent: _collapsedCelContent,
            projectFrameRate: session.projectSettings.projectFrameRate,
            // The CAMERA row's union summary (B4) — the same shared
            // markers the timeline row mounts; ⑩ root C says this overlay
            // mounts the real row, columns and all.
            unionLane: timelineCameraUnionLane(layer: layer, session: session),
            // `commaDrag`/`rangeGesture` stay null — display-only, same
            // reason.
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
          ),
        // 🚨WHERE YOU ARE is a separate layer on purpose, and it is the
        // whole of "인덱스는 리페인트": the row above is CURSOR-INDEPENDENT
        // by design, so the playhead cannot live in it — it lives here, on
        // a value channel, and a frame tick repaints this and rebuilds
        // nothing. That is also why the overlay needs no listener of its
        // own: 문답 7's 「커서 = 스냅샷이 정본 / 그림 = 위젯이 정본」 is
        // exactly these two children, in this order.
        TimelineCursorLayer(
          frameCursor: session.editingFrameCursor,
          rows: [displayRow],
          activeLayerId: layer.id,
          currentRow: session.currentRowListenable,
          frameStartIndex: geometry.value.frameStartIndex,
          frameEndIndexExclusive: geometry.value.frameEndIndexExclusive,
          leadingFrameSpacerWidth: 0,
          metrics: metrics,
          exposureStateForLayer: session.exposureStateForLayer,
          crossAxisExtent: collapsedRowHeight(),
        ),
      ],
    );
  }
}
