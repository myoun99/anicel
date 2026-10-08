part of '../storyboard_panel.dart';

/// One panel of the conte row as the edit chrome sees it: a global frame
/// span, and what its two edges mean.
typedef _StoryboardStripGrip = ({
  CutId cutId,
  int startFrame,
  int endFrameExclusive,

  /// This panel's CUT-LOCAL ordinal. Every panel hangs a leading grip
  /// (user's rule 2026-08-02) and the grip is the same verb whatever the
  /// ordinal — the cut's lead edge, with this panel the one that gives up
  /// the commas. The ordinal is what tells the session WHICH panel that is.
  int panelIndex,

  /// The CUT-LOCAL timeline key of the block this panel's trailing edge
  /// comma-resizes, or null when that edge is the cut's own length
  /// instead (the last panel — it goes through the cut-edge begin).
  int? commaBlockKey,
});

/// THE TRACK'S CONTE ROW — the cuts' conte layers as ONE row of frame
/// blocks on the track's axis, under the V row.
///
/// 🗣️I-73 (유저 2026-10-08): 「우선 v행은 지금처럼 보여주는건 그대로
/// 보여줘 … 컷 선택만 되도록. 그러고 v행 아래에 콘티행 만들어서 거기서」 ·
/// 「띠 둘만 이사로 가자」 · 「콘티행도 동일하게 하고싶으니까」. The cut
/// block wore each panel's name and comma count in
/// two bands of its own; they are this row's blocks now, drawn by the
/// TIMELINE's row painter on the row [trackConteRowShown] lays out — a
/// panel's name at its head and its length at its end, the print every
/// frame block has — and the pictures stayed above, on the V row.
/// ↩️유저 2026-09-25 had moved that writing off the pictures into the cut
/// block's bands (「띠로 옮긴다 — 이름은 윗 띠, 코마는 아랫 띠」), and
/// 2026-09-26 gave the conte blocks a pair of their own inside the cut's
/// (「내부에 콘티블록 있으면 콘티블록의 띠도 생겨서」).
///
/// Everything a panel answers to is here, where the panel is a block: its
/// press, its range gesture, its selection band, its double click and its
/// edges. The V row above answers for the CUT alone.
///
/// A cut with no conte layer holds no block; its stretch of the row is the
/// button that makes one ([StoryboardConteCreatePainter]). A gap holds
/// nothing.
class _StoryboardConteRow extends StatelessWidget with _StoryboardRowRunLabels {
  const _StoryboardConteRow({
    required this.track,
    required this.layoutEntries,
    required this.width,
    required this.height,
    required this.timelineScale,
    required this.frameGeometry,
    required this.windowBucket,
    required this.viewportWidth,
    required this.showSeconds,
    required this.projectFrameRate,
    this.onRowFramePress,
    this.stripEdges,
    this.stripSelect,
    this.onCreateStoryboardLayer,
    this.onEditConteBlock,
  });

  final Track track;

  /// The track's cuts as this step lays them — the V row's own list, so a
  /// cut's panels ride its trim and its move with the block above them.
  final List<StoryboardTimelineLayoutEntry> layoutEntries;

  /// The scroll content's full width — the V row's own.
  final double width;

  /// Its label's height ([_StoryboardRowHeights.conte]) — one row.
  @override
  final double height;
  final TimelineScale timelineScale;

  /// The panel's live frame-axis geometry: what the blocks are painted on,
  /// and what the shared gesture reads to turn a pointer position into a
  /// track-global frame.
  @override
  final TimelineFrameGeometryHandle frameGeometry;

  /// The panel's window, as the V row's blocks painter takes it.
  @override
  final ValueListenable<int> windowBucket;
  @override
  final double viewportWidth;
  @override
  final bool showSeconds;
  @override
  final ProjectFrameRate projectFrameRate;

  /// The cells' press: the ROW ([trackConteRowId]) and the frame under the
  /// pointer, empty cells included.
  final StoryboardRowFramePress? onRowFramePress;

  /// The panels' edges ([_edgeChrome]). Null hangs none.
  final StoryboardStripEdgeCallbacks? stripEdges;

  /// Range selection on the panels — the cut's own, on the cut's own axis.
  /// Null keeps the row display-only.
  final StoryboardStripSelectCallbacks? stripSelect;

  /// D30: pressed on a no-layer cut's CREATE affordance. The gate and the
  /// dispatch both live with the host's session pair
  /// (canAddLayerOfKind/addLayerOfKind — T25); null keeps the affordance
  /// display-only.
  final ValueChanged<CutId>? onCreateStoryboardLayer;

  /// F-255: a double click on a conte block
  /// ([StoryboardPanel.onEditConteBlock]). Null keeps the block without one.
  final void Function(TrackId trackId, LayerId layerId, int globalFrame)?
  onEditConteBlock;

  /// The panels under [frame]: the covering cut and its conte layer — null
  /// in gaps and on cuts without one. The panels' GESTURE and its hit-test
  /// gate read this one answer, so what the callbacks would refuse is
  /// exactly what the gate lets fall through.
  ({StoryboardTimelineLayoutEntry entry, Layer layer})? _stripAt(int frame) {
    final entry = _cutEntryAt(layoutEntries, frame);
    if (entry == null) {
      return null;
    }
    final layer = storyboardLayerForCut(entry.cut);
    return layer == null ? null : (entry: entry, layer: layer);
  }

  int _frameAtX(double x) =>
      timelineScale.pixelsPerFrame <= 0 ? 0 : timelineScale.frameAt(x);

  /// One entry per PANEL of the row, in track order — what the edit chrome
  /// hangs its grips on.
  ///
  /// A cut edge is always on its panels (design, user's rule 2026-07-25):
  /// the first panel's leading edge IS the cut's start and the last panel's
  /// trailing edge IS its length. ↩️Those were the cut's ONLY grips while
  /// the panels were drawn inside the cut block; the cut block wears its own
  /// two now, on the V row (I-73), and these stay the panels'.
  ///
  /// An inner trailing edge needs its panel's own TIMELINE key (the block
  /// its comma resizes), which the coverage cell cannot answer — the first
  /// cell's startIndex is clamped to 0 whatever its key says — so the keys
  /// are read off the row alongside the cells.
  List<_StoryboardStripGrip> _stripGrips() => [
    for (final entry in layoutEntries)
      if (storyboardLayerForCut(entry.cut) case final layer?)
        ...() {
          final cells = storyboardCoverageCells(
            timeline: layer.timeline,
            cutDuration: entry.duration,
          );
          final keys = storyboardDivisionKeys(
            timeline: layer.timeline,
            cutDuration: entry.duration,
          );
          return [
            for (var index = 0; index < cells.length; index += 1)
              (
                cutId: entry.cutId,
                startFrame: entry.startFrame + cells[index].startIndex,
                endFrameExclusive:
                    entry.startFrame + cells[index].endIndexExclusive,
                panelIndex: index,
                commaBlockKey: index == cells.length - 1 || index >= keys.length
                    ? null
                    : keys[index],
              ),
          ];
        }(),
  ];

  /// THE EDGES, at the panels' boundaries — the timeline's chrome layer, as
  /// the timeline's rows mount it: on the blocks' paper, in the blocks' own
  /// corners.
  ///
  /// One shape of grip, and where it sits decides what it does: the first
  /// panel's leading edge is the CUT's lead edge, and every trailing edge is
  /// its panel's comma with the cut's length riding the row end (edge
  /// unification — the division verb is gone).
  ///
  /// ↩️They stood in the conte blocks' two bands inside the cut block, a
  /// triangle taking one band whole and never a picture (I-52, 유저
  /// 2026-09-28: 「썸네일이 존재하는 블록은 엣지를 썸네일 안가리도록 …
  /// 띠에만」); a block of this row has no picture to keep clear of.
  Widget _edgeChrome(
    StoryboardStripEdgeCallbacks stripEdges,
    List<_StoryboardStripGrip> grips,
    Color paper,
  ) => Positioned.fill(
    key: ValueKey<String>('storyboard-edit-chrome-slot-${track.id.value}'),
    child: TimelineRowEditChromeLayer(
      paintKey: ValueKey<String>('storyboard-edit-chrome-${track.id.value}'),
      // The grips sit on this row's blocks, and the blocks are the row's
      // colour label (⑲) — the ground law reads their ink off it.
      gripGround: paper,
      // The blocks' own window: the row spans the whole film, and the grips
      // are drawn where the view can reach, as the blocks under them are.
      windowBucket: windowBucket,
      viewportMainExtent: viewportWidth,
      // No layer: these blocks are panels of many cuts, and the row has no
      // run edges for a LayerId to name.
      layerId: null,
      resolver: TimelineRowChromeResolver(
        gripBlocks: [
          for (var index = 0; index < grips.length; index += 1)
            (
              ordinal: index,
              startIndex: grips[index].startFrame,
              endIndexExclusive: grips[index].endFrameExclusive,
              // EVERY panel hangs a leading grip (user's rule 2026-08-02).
              // R4 had left it on the first panel alone, because P5 #8's
              // interior front grips DELEGATED to the previous panel's
              // back grip — two handles doing one thing. They are not
              // that any more: a front grip takes the frames off the
              // cut's HEAD and a back grip off its TAIL, so the two edges
              // of one boundary name two edits.
              startGrip: true,
              endGrip: true,
            ),
        ],
        gripIdScope: trackConteRowId(track.id).value,
        layer: null,
        baseLayer: null,
        // I-44: the chrome stands on the block's PAPER — the row short of
        // its seam — so the edge triangles sit in the paper's own corners.
        crossAxisExtent: timelineRowPaperExtent(height),
        axis: Axis.horizontal,
        includeRunEdges: false,
      ),
      geometry: frameGeometry,
      axis: Axis.horizontal,
      grips: _gripVerbs(stripEdges, grips),
      runEdit: null,
    ),
  );

  /// What each grip begins. The row closes the identity in, by ordinal —
  /// the grip hooks themselves know nothing about cuts or panels.
  ///
  /// R10 R4: no impersonation. A grip reports the edge it IS, and the rule
  /// that decides what moves lives one layer down, in the session — which
  /// is where the "a front edge inside a cut is really the previous back
  /// edge" trick belonged all along.
  TimelineRowGripCallbacks _gripVerbs(
    StoryboardStripEdgeCallbacks stripEdges,
    List<_StoryboardStripGrip> grips,
  ) => TimelineRowGripCallbacks(
    onBegin: (_, ordinal, edge) {
      if (ordinal < 0 || ordinal >= grips.length) {
        return false;
      }
      final grip = grips[ordinal];
      if (edge == TimelineBlockEdge.start) {
        return stripEdges.onCutEdgeBegin(
          grip.cutId,
          TimelineBlockEdge.start,
          grip.panelIndex,
        );
      }
      final commaKey = grip.commaBlockKey;
      return commaKey == null
          ? stripEdges.onCutEdgeBegin(
              grip.cutId,
              TimelineBlockEdge.end,
              grip.panelIndex,
            )
          : stripEdges.onCommaBegin(grip.cutId, commaKey);
    },
    onUpdate: stripEdges.onUpdate,
    onEnd: stripEdges.onEnd,
    onCancel: stripEdges.onCancel,
  );

  /// The panels' half of the shared range gesture.
  ///
  /// A panel is a block of a CUT's own row, so its selection is the
  /// cut-local one — the object the timeline's rows sweep, on that cut's
  /// conte layer — which is also why the drag never leaves the cut it
  /// started in: a cut's own index cannot name a frame of another cut. That
  /// is the "clip to the anchor cut" rule, arriving as arithmetic rather
  /// than as a guard ([conteRowOwnFrameAt]; the sweep across cuts is for
  /// later, 유저 2026-10-08).
  ///
  /// The pressed FRAME says which cut, and therefore which conte layer, the
  /// drag is on, and the frames it hands on are that layer's OWN — the conte
  /// begins after the のりしろ an O.L leaves before it (F-227). ↩️It handed
  /// on the frame counted from the cut's start, which in a cut an O.L
  /// arrives into named the block before the one under the pointer
  /// (🧪2026-10-08: a sweep over the first panel selected its のりしろ).
  ///
  /// ↩️F-203 (유저 2026-09-28: 「v행 선택범위로 선택…하고 컷 잡아끌때 띠만
  /// 잡아야 반응하는상황? 그냥 컷 어디 잡아끌든 컷 움직이게」) had this
  /// gesture stand down inside a live CUT selection, because the conte
  /// blocks lay over the cut block and shadowed it. They lie under it now,
  /// on a row no cut selection covers.
  TimelineRangeGestureCallbacks? _stripGesture() {
    final stripSelect = this.stripSelect;
    if (stripSelect == null) {
      return null;
    }
    return TimelineRangeGestureCallbacks(
      isInSelection: (_, frame) {
        final strip = _stripAt(frame);
        final selection = stripSelect.selection.value;
        return strip != null &&
            selection != null &&
            selection.coversLayer(strip.layer.id) &&
            selection.contains(
              conteRowOwnFrameAt(strip.entry, strip.layer, frame),
            );
      },
      onSelectUpdate: (_, anchorIndex, headIndex, _) {
        final strip = _stripAt(anchorIndex);
        if (strip == null) {
          return;
        }
        stripSelect.onDrag(
          layerId: strip.layer.id,
          anchorIndex: conteRowOwnFrameAt(
            strip.entry,
            strip.layer,
            anchorIndex,
          ),
          headIndex: conteRowOwnFrameAt(strip.entry, strip.layer, headIndex),
        );
      },
      // The cells' press already seeks into the cut, so the tap only drops
      // the selection (R10: standing is handled by the press here).
      onTapClear: (_) => stripSelect.onClear(),
      // Sliding the panels: the same move the timeline's rows do, on the
      // cut's own axis. The pressed frame says which cut — and therefore
      // which conte layer — the drag belongs to, exactly as the select
      // half reads it.
      onMoveBegin: (_, frame) {
        final strip = _stripAt(frame);
        return strip != null &&
            (stripSelect.move?.onBegin(strip.layer.id) ?? false);
      },
      // No target row is ever reported: a cut has exactly one conte layer,
      // so there is nowhere sideways to land.
      onMoveUpdate: (frameDelta, _) =>
          stripSelect.move?.onUpdate(frameDelta, null),
      onMoveEnd: stripSelect.move?.onEnd ?? _noMove,
      onMoveCancel: stripSelect.move?.onCancel ?? _noMove,
    );
  }

  /// THE cells' press on this row: the row stood on at [frame] — the
  /// timeline's cell contract, through the storyboard's one press — and
  /// then, where the cut under it has no conte layer, the button that makes
  /// one.
  ///
  /// D30: the create judges THIS build's cuts — the snapshot the `+` was
  /// drawn from — so running after the press's activation cannot widen it.
  ///
  /// 🚨H13 (유저 2026-08-22) — **NO ACTIVE-CUT RULE.**
  ///
  /// > 「컷블록에 스토리보드레이어 없을때 뜨는 스토리보드레이어 추가버튼,
  /// > **액티브컷에만 띄우는게아니라 그런 규칙 두지말고** 그냥 다른
  /// > 컷블록도 없으면 띄우도록」
  ///
  /// Every cut with no conte layer wears the `+`, so pressing a `+` the user
  /// can SEE creates: the press lands in the cut first (its seek), and the
  /// host makes the layer in the cut the press just made active.
  void _pressed(TimelineRowAddress row, int frame) {
    onRowFramePress?.call(row, frame);
    final entry = _cutEntryAt(layoutEntries, frame);
    if (entry != null && storyboardLayerForCut(entry.cut) == null) {
      onCreateStoryboardLayer?.call(entry.cutId);
    }
  }

  /// F-255 (유저 2026-10-01: 「이름변경 입구 확대 … 콘티블록이나 컷블록에도
  /// 통일적용」): a double click on a conte block opens its name — the frame
  /// block's own double tap, on the cell it is.
  void Function(int frame)? get _edit {
    final onEditConteBlock = this.onEditConteBlock;
    if (onEditConteBlock == null) {
      return null;
    }
    return (frame) {
      final strip = _stripAt(frame);
      if (strip != null) {
        onEditConteBlock(track.id, strip.layer.id, frame);
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    final shown = trackConteRowShown(track.id, layoutEntries);
    final stripGesture = _stripGesture();
    final stripEdges = this.stripEdges;
    final stripSelect = this.stripSelect;
    final edit = _edit;
    return SizedBox(
      key: ValueKey<String>('storyboard-conte-row-${track.id.value}'),
      width: math.max(
        _storyboardCutsExtent(layoutEntries, timelineScale),
        width,
      ),
      height: height,
      child: Stack(
        children: [
          _cells(context, shown),
          // Each panel's length at its end — the timeline row's own print
          // (F-228), over the paper and under everything that answers.
          _runLabels(context, shown),
          _createButtons(context),
          // The cells' press — the S rows' and the transition row's own
          // layer, addressed to this row ([trackConteRowId], the id the
          // row's shown layer wears). Translucent and mounted BEFORE the
          // gesture and the grips, so they keep their priority.
          if (onRowFramePress != null ||
              onCreateStoryboardLayer != null ||
              edit != null)
            _storyboardRowPressLayer(
              key: ValueKey<String>('storyboard-conte-press-${track.id.value}'),
              layer: shown,
              cellExtent: timelineScale.pixelsPerFrame,
              frameAt: (local) => _frameAtX(local.dx),
              onRowFramePress: _pressed,
              onEdit: edit,
            ),
          // Mounted UNDER the grips so the edges keep priority.
          if (stripGesture != null) _gestureSlot(shown, stripGesture),
          if (stripSelect != null) _selectionBand(stripSelect),
          // THE EDGES ride ABOVE the range gesture so an edge keeps its
          // priority over it; the middles keep the rest.
          if (stripEdges != null)
            _edgeChrome(stripEdges, _stripGrips(), layerMarkColor(shown.mark)),
        ],
      ),
    );
  }

  /// THE blocks — the timeline's own row painter, on the cuts' conte layers
  /// as one row ([trackConteRowShown]): one painter for the whole film,
  /// windowed like the V row's above it.
  ///
  /// Held to the cuts that HAVE a conte layer. The row's painter marks the
  /// first cell of every empty run (the timesheet's X), and here a stretch
  /// with no block is not an empty drawing — it is a cut with no conte
  /// layer, which wears its button, or a gap, where there is no cut at all.
  Widget _cells(BuildContext context, Layer shown) {
    // I-44: the HOST's ground and lines, stated once by its law — as the
    // timeline's rows read them.
    final law = TimelineGridLaw.maybeOf(context);
    return Positioned.fill(
      child: ClipPath(
        clipBehavior: Clip.hardEdge,
        clipper: _ConteCutsClip(
          geometry: frameGeometry,
          spans: _cutSpans(withConteLayer: true),
        ),
        child: RepaintBoundary(
          child: CustomPaint(
            key: ValueKey<String>('storyboard-conte-cells-${track.id.value}'),
            painter: TimelineRowCellsPainter(
              layer: shown,
              geometry: frameGeometry,
              crossAxisExtent: height,
              exposureStateForLayer: timelineOwnCelsStateAt,
              frameNameForLayer: timelineOwnCelNameAt,
              colorScheme: Theme.of(context).colorScheme,
              baseTextStyle: DefaultTextStyle.of(context).style,
              windowBucket: windowBucket,
              viewportMainExtent: viewportWidth,
              paperGround: law?.ground,
              blockFrameLines: law?.blockFrameLines ?? false,
              framesPerSecond: law?.framesPerSecond ?? 0,
            ),
          ),
        ),
      ),
    );
  }

  /// The button of every cut that has no conte layer
  /// ([StoryboardConteCreatePainter]) — drawn, never pressed: the cells'
  /// press under it answers ([_pressed]).
  Widget _createButtons(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          key: ValueKey<String>('storyboard-conte-create-${track.id.value}'),
          painter: StoryboardConteCreatePainter(
            spans: _cutSpans(withConteLayer: false),
            geometry: frameGeometry,
            crossAxisExtent: height,
            colorScheme: Theme.of(context).colorScheme,
            baseTextStyle: DefaultTextStyle.of(context).style,
            windowBucket: windowBucket,
            viewportMainExtent: viewportWidth,
          ),
        ),
      ),
    ),
  );

  /// THE range gesture — the timeline's, not a copy of it: a pan paints a
  /// run of panels, a pan starting inside the selection slides it.
  ///
  /// Hit-testing gates the gesture to frames that HAVE panels: its pan
  /// claims the arena at DOWN (eager), so a press it cannot answer — a gap,
  /// a cut without a conte layer — must never reach it, or that press dies
  /// silently under it (the real-device "no selection where there is no cut
  /// block").
  Widget _gestureSlot(
    Layer shown,
    TimelineRangeGestureCallbacks stripGesture,
  ) => Positioned.fill(
    key: ValueKey<String>('storyboard-strip-gesture-slot-${track.id.value}'),
    child: _FrameHitGate(
      claimsDx: (dx) => _stripAt(_frameAtX(dx)) != null,
      // The gesture layer fills its Stack, so it needs one of its own here
      // — a second Positioned around it would be two ParentDataWidgets on
      // one render object.
      child: Stack(
        children: [
          TimelineFrameRangeGestureLayer(
            row: LayerRowAddress(shown.id),
            geometry: frameGeometry,
            crossAxisExtent: height,
            callbacks: stripGesture,
          ),
        ],
      ),
    ),
  );

  /// D30: the panels' own selection band — the timeline's ONE band
  /// decoration, drawn from the cut-local selection's own numbers. One
  /// listener for the ROW, never one a cut (old-tablet law),
  /// pointer-transparent like every band.
  Widget _selectionBand(StoryboardStripSelectCallbacks stripSelect) =>
      Positioned.fill(
        child: IgnorePointer(
          child: ValueListenableBuilder<TimelineFrameRangeSelection?>(
            valueListenable: stripSelect.selection,
            builder: (context, selection, _) => _rangeBand(selection),
          ),
        ),
      );

  /// The cuts that have a conte layer — or have none — in order, each as
  /// its frames `[start, endExclusive)` on the track's axis.
  List<({int start, int endExclusive})> _cutSpans({
    required bool withConteLayer,
  }) => [
    for (final entry in layoutEntries)
      if ((storyboardLayerForCut(entry.cut) != null) == withConteLayer)
        (start: entry.startFrame, endExclusive: entry.endFrame),
  ];

  /// The panels' range-selection band: the selected panels of the cut whose
  /// conte layer the selection names — laid where those frames stand on the
  /// track ([conteRowGlobalFrameOf]) and held inside the cut — or nothing
  /// when no cut here carries that layer.
  Widget _rangeBand(TimelineFrameRangeSelection? selection) {
    if (selection == null || timelineScale.pixelsPerFrame <= 0) {
      return const SizedBox.shrink();
    }
    for (final entry in layoutEntries) {
      final layer = storyboardLayerForCut(entry.cut);
      if (layer == null || layer.id != selection.layerId) {
        continue;
      }
      final start = math.max(
        entry.startFrame,
        conteRowGlobalFrameOf(entry, layer, selection.startIndex),
      );
      final end = math.min(
        entry.endFrame,
        conteRowGlobalFrameOf(entry, layer, selection.endIndexExclusive),
      );
      if (end <= start) {
        break;
      }
      return Stack(
        children: [
          Positioned(
            left: timelineScale.leftForFrame(start),
            top: 0,
            bottom: 0,
            width: timelineScale.spanWidth(start, end),
            child: Semantics(
              key: const ValueKey<String>('storyboard-strip-range-selection'),
              label: AppText.strings.tlSelectedPanelRange,
              container: true,
              // The band takes the shape of what it selects (F-26): a
              // panel is a frame block here, round as the timeline's are.
              // ↩️Square while a conte block lay inside its cut's plate
              // (유저 2026-09-26: 「블록이 모서리 둥근건 블록 자체」).
              child: DecoratedBox(
                decoration: timelineRangeSelectionBandDecorationAt(
                  cellExtent: timelineScale.pixelsPerFrame,
                  crossExtent: height,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

/// Holds the conte row's cells to the stretches of the track whose cut has
/// a conte layer ([_StoryboardConteRow]) — re-cut on a zoom step, which
/// moves the frames and builds nothing.
class _ConteCutsClip extends CustomClipper<Path> {
  _ConteCutsClip({required this.geometry, required this.spans})
    : super(reclip: geometry);

  final TimelineFrameGeometryHandle geometry;
  final List<({int start, int endExclusive})> spans;

  @override
  Path getClip(Size size) {
    final frames = geometry.value;
    final path = Path();
    for (final span in spans) {
      path.addRect(
        Rect.fromLTRB(
          frames.edgeAt(span.start),
          0,
          frames.edgeAt(span.endExclusive),
          size.height,
        ),
      );
    }
    return path;
  }

  @override
  bool shouldReclip(_ConteCutsClip oldClipper) =>
      !identical(oldClipper.geometry, geometry) ||
      !listEquals(oldClipper.spans, spans);
}

/// THE CONTE ROW'S CREATE BUTTON — over every cut that has no conte layer,
/// each its own: a plate the shape of the block that will stand there, with
/// the `+` where a panel's name would.
///
/// 🗣️유저 2026-09-26: 「지금 콘티블록 생성버튼이 중앙에있는데 그게아니라
/// 띠에? 콘티블록의 블록이름이 위치할 띠 쪽에 그냥 콘티블록 상단띠 전면을
/// 생성버튼으로 하는게 좋을지도?」 — the button takes the place the conte
/// blocks were always going to take, whole. That place was the cut block's
/// inner top band; it is the cut's stretch of this row now (I-73 — the
/// drawn proposal 유저 took on 2026-10-08: 「콘티 레이어가 없는 컷. 그
/// 구간이 비어 있고 ＋ 가 있습니다」). ↩️A 22px square centred in the strip
/// before 09-26, gone on any strip too narrow or too flat to hold it.
///
/// D30: an icon, not copy — and painted, like the blocks beside it: a film
/// of cuts with no conte layer costs a draw call a cut, never a widget.
/// Where it is drawn is where it is pressed ([_StoryboardConteRow._pressed]
/// reads the same cuts).
class StoryboardConteCreatePainter extends CustomPainter with RepaintOnProps {
  StoryboardConteCreatePainter({
    required this.spans,
    required this.geometry,
    required this.crossAxisExtent,
    required this.colorScheme,
    required this.baseTextStyle,
    required this.windowBucket,
    required this.viewportMainExtent,
  }) : super(repaint: Listenable.merge([geometry, windowBucket]));

  /// The cuts that wear the button, each as its frames on the track's axis.
  final List<({int start, int endExclusive})> spans;
  final TimelineFrameGeometryHandle geometry;
  final double crossAxisExtent;
  final ColorScheme colorScheme;
  final TextStyle baseTextStyle;
  final ValueListenable<int> windowBucket;
  final double viewportMainExtent;

  /// Each button's plate inside the visible window, row-local — THE probe
  /// surface, and what [paint] lays down.
  List<RRect> plates() {
    final frames = geometry.value;
    final cell = frames.frameCellExtent;
    if (cell <= 0) {
      return const [];
    }
    final window = viewportMainExtent <= 0
        ? (startIndex: 0, endIndexExclusive: 1 << 30)
        : timelineFrameWindowFor(
            bucket: windowBucket.value,
            cellExtent: cell,
            viewportExtent: viewportMainExtent,
          );
    return [
      for (final span in spans)
        if (span.endExclusive > window.startIndex &&
            span.start < window.endIndexExclusive)
          timelineBlockPaperShape(
            axis: Axis.horizontal,
            along: frames.edgeAt(span.endExclusive) - frames.edgeAt(span.start),
            rowExtent: crossAxisExtent,
            frameCellExtent: cell,
          ).shift(Offset(frames.edgeAt(span.start), 0)),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    // The plate a cut block is made of — what its inner band wore while the
    // button stood there.
    final plate = storyboardCutBlockBackgroundColor(
      colorScheme,
      hovered: false,
    );
    final fill = Paint()..color = plate;
    for (final shape in plates()) {
      canvas.drawRRect(shape, fill);
      canvas.save();
      canvas.clipRRect(shape);
      StoryboardCutBlocksPainter.paintBandWord(
        canvas,
        text: '+',
        style: StoryboardCutBlocksPainter.bandWordStyleOn(baseTextStyle),
        band: shape.outerRect,
        alignRight: false,
        ground: plate,
      );
      canvas.restore();
    }
  }

  @override
  // Geometry and the window are absent on purpose — they arrive through
  // `repaint`.
  Object get props => (
    ByList(spans),
    crossAxisExtent,
    colorScheme,
    baseTextStyle,
    viewportMainExtent,
  );
}
