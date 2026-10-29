part of '../storyboard_panel.dart';

/// One block of a conte row as the edit chrome sees it: a global frame
/// span, which of its two edges are there to grip, and what a grip on one
/// begins.
///
/// One shape of grip, and where it sits decides what it does — so the
/// block says it, and the hooks under it know nothing of cuts, panels or
/// rows ([_StoryboardPanelEdges]).
typedef _StoryboardStripGrip = ({
  int startFrame,
  int endFrameExclusive,
  bool startGrip,
  bool endGrip,
  bool Function(TimelineBlockEdge edge) begin,
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
///
/// THE ATTACH ROWS of the conte are this row again, at their [seat] (유저:
/// 「콘티행도 동일하게 하고싶으니까 어태치 접기펼치기버튼등 동일하게
/// 할수있는거 다 넣는거 잊지말고」; the drawn proposal: 「어태치 행 — 서면
/// 블록 · 끌면 콘티 행과 같음 · 플립 블록 단위 · 삭제 서 있는 블록 · 코마
/// 블록 길이 · 타임라인의 자리 = 그 어태치 행」): each cut's row at that
/// seat, as the timeline shows it, its blocks' two edges their own
/// ([_StoryboardPanelEdges]). What is the CONTE's alone stays on seat 0 —
/// the button that makes a cut's conte, and edges that are the cut's own
/// length.
class _StoryboardConteRow extends KeptPiece with _StoryboardRowRunLabels {
  const _StoryboardConteRow({
    required this.trackId,
    required this.seat,
    required this.layoutEntries,
    required this.width,
    required this.height,
    required this.timelineScale,
    required this.frameGeometry,
    required this.windowBucket,
    required this.showSeconds,
    required this.projectFrameRate,
    this.onRowFramePress,
    this.stripEdges,
    this.stripSelect,
    this.onCreateStoryboardLayer,
    this.onEditConteBlock,
    this.conteCelContent,
    this.stepsUntilShown,
  });

  /// The track whose row this is — its keys' and its verbs' word.
  final TrackId trackId;

  /// Which row of the track's conte group this is (`models/conte_group
  /// .dart`): 0 the conte, +k the k-th attach row above it, −k below.
  final int seat;

  /// The track's cuts as this step lays them — the V row's own list, so a
  /// cut's panels ride its trim and its move with the block above them.
  final List<StoryboardTimelineLayoutEntry> layoutEntries;

  /// The row's word in its keys: the track's id for the conte — the keys
  /// the row had before it had seats — and the seat's word after it for an
  /// attach row.
  String get _scope => seat == 0
      ? trackId.value
      : '${trackId.value}-'
            '${_StoryboardRowsAndLabels.conteLabelKeyName(seat)}';

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
  final bool showSeconds;
  @override
  final ProjectFrameRate projectFrameRate;

  /// The cells' press: the ROW ([trackConteRowId]) and the frame under the
  /// pointer, empty cells included.
  final StoryboardRowFramePress? onRowFramePress;

  /// The blocks' edges ([_edges]). Null hangs none.
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

  /// The unworked-block tint ([StoryboardPanel.conteCelContent]). Null
  /// tints nothing.
  final ConteCelContent? conteCelContent;

  /// How many steps on the playing run shows a cut's frame
  /// ([StoryboardPanel.stepsUntilShown]) — asked of the cut under each of
  /// this row's film frames ([_stepsUntilShownAt]).
  final int? Function(CutId cutId, int frameIndex)? stepsUntilShown;

  /// How many steps on the playing run shows film frame [frame] of this
  /// row: the cut covering it there, at its own frame — none in a gap.
  int? _stepsUntilShownAt(int frame) {
    final ask = stepsUntilShown;
    if (ask == null) {
      return null;
    }
    final entry = _cutEntryAt(layoutEntries, frame);
    return entry == null ? null : ask(entry.cutId, frame - entry.startFrame);
  }

  /// The panels under [frame]: the covering cut and its layer at this row's
  /// seat — null in gaps and on cuts without one. The panels' GESTURE and
  /// its hit-test gate read this one answer, so what the callbacks would
  /// refuse is exactly what the gate lets fall through.
  ({StoryboardTimelineLayoutEntry entry, Layer layer})? _stripAt(int frame) {
    final entry = _cutEntryAt(layoutEntries, frame);
    if (entry == null) {
      return null;
    }
    final layer = conteRowAtSeat(entry.cut, seat);
    return layer == null ? null : (entry: entry, layer: layer);
  }

  int _frameAtX(double x) =>
      timelineScale.pixelsPerFrame <= 0 ? 0 : timelineScale.frameAt(x);

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
              conteRowOwnFrameAt(strip.entry, frame),
            );
      },
      onSelectUpdate: (_, anchorIndex, headIndex, _) {
        final strip = _stripAt(anchorIndex);
        if (strip == null) {
          return;
        }
        stripSelect.onDrag(
          layerId: strip.layer.id,
          anchorIndex: conteRowOwnFrameAt(strip.entry, anchorIndex),
          headIndex: conteRowOwnFrameAt(strip.entry, headIndex),
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
    if (seat == 0 &&
        entry != null &&
        storyboardLayerForCut(entry.cut) == null) {
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
        onEditConteBlock(trackId, strip.layer.id, frame);
      }
    };
  }

  /// What the row shows — its cuts by how they lie
  /// ([StoryboardTimelineLayoutEntry.==]: the very cuts, at the same
  /// places), which is all its blocks, its buttons and its edges are made
  /// of.
  ///
  /// 🚨I-57 (10-14): built again with the panel on every notify and every
  /// cut crossed, the row built its cells again — 🔬what they say to a
  /// screen reader was the largest part of a crossing's semantics on the
  /// AMMI OP.
  @override
  Object? get facts => (
    trackId,
    seat,
    ByList(layoutEntries),
    width,
    height,
    timelineScale.pixelsPerFrame,
    timelineScale.minBlockWidth,
    ByIdentity(frameGeometry),
    ByIdentity(windowBucket),
    showSeconds,
    projectFrameRate,
    onRowFramePress != null,
    stripEdges != null,
    stripSelect != null,
    onCreateStoryboardLayer != null,
    onEditConteBlock != null,
    conteCelContent != null,
    stepsUntilShown != null,
  );

  @override
  Widget buildKept(BuildContext context) {
    final shown = trackConteRowShown(trackId, layoutEntries, seat: seat);
    final headShown = _headShown();
    final stripGesture = _stripGesture();
    final edges = stripEdges;
    final stripSelect = this.stripSelect;
    final edit = _edit;
    return SizedBox(
      key: ValueKey<String>('storyboard-conte-row-$_scope'),
      width: math.max(
        _storyboardCutsExtent(layoutEntries, timelineScale),
        width,
      ),
      height: height,
      child: Stack(
        children: [
          _cells(context, shown, headShown: headShown),
          // Each panel's length at its end — the timeline row's own print
          // (F-228), over the paper and under everything that answers.
          _runLabels(
            context,
            shown,
            shown: headShown,
            celContent: _celContent(shown),
          ),
          // Where each cut begins — the projection rows' dashed line, the
          // camera row's own ([StoryboardCutStartsPainter]).
          _StoryboardCutStarts(
            paintKey: ValueKey<String>('storyboard-conte-cut-starts-$_scope'),
            starts: [for (final entry in layoutEntries) entry.startFrame],
            geometry: frameGeometry,
            windowBucket: windowBucket,
          ),
          if (seat == 0) _createButtons(context),
          // The cells' press — the S rows' and the transition row's own
          // layer, addressed to this row ([trackConteRowId], the id the
          // row's shown layer wears). Translucent and mounted BEFORE the
          // gesture and the grips, so they keep their priority.
          if (onRowFramePress != null ||
              onCreateStoryboardLayer != null ||
              edit != null)
            _storyboardRowPressLayer(
              key: ValueKey<String>('storyboard-conte-press-$_scope'),
              row: LayerRowAddress(shown.id),
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
          if (edges != null) _edges(edges, _blocks(context, shown, headShown)),
        ],
      ),
    );
  }

  /// The row [shown] as its cells draw its blocks: the head's eye
  /// ([headShown]), its cels and the host's ground.
  TimelineBlockRow _blocks(
    BuildContext context,
    Layer shown,
    bool headShown,
  ) => (
    layer: shown,
    shown: headShown,
    content: _celContent(shown),
    ground: TimelineGridLaw.maybeOf(context)?.ground,
  );

  /// The row's edges, over its blocks ([_StoryboardPanelEdges]) — on them
  /// as [row] draws them, the cells' own (I-129).
  Widget _edges(
    StoryboardStripEdgeCallbacks stripEdges,
    TimelineBlockRow row,
  ) => Positioned.fill(
    key: ValueKey<String>('storyboard-edit-chrome-slot-$_scope'),
    child: _StoryboardPanelEdges(
      trackId: trackId,
      seat: seat,
      scope: _scope,
      layoutEntries: layoutEntries,
      stripEdges: stripEdges,
      row: row,
      height: height,
      frameGeometry: frameGeometry,
      windowBucket: windowBucket,
    ),
  );

  /// THE blocks — the timeline's own row painter, on the cuts' conte layers
  /// as one row ([trackConteRowShown]): one painter for the whole film,
  /// windowed like the V row's above it.
  ///
  /// Held to the cuts that HAVE a conte layer. The row's painter marks the
  /// first cell of every empty run (the timesheet's X), and here a stretch
  /// with no block is not an empty drawing — it is a cut with no conte
  /// layer, which wears its button, or a gap, where there is no cut at all.
  Widget _cells(BuildContext context, Layer shown, {required bool headShown}) {
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
            key: ValueKey<String>('storyboard-conte-cells-$_scope'),
            painter: TimelineRowCellsPainter(
              layer: shown,
              geometry: frameGeometry,
              crossAxisExtent: height,
              exposureStateForLayer: timelineOwnCelsStateAt,
              frameNameForLayer: timelineOwnCelNameAt,
              colorScheme: Theme.of(context).colorScheme,
              baseTextStyle: DefaultTextStyle.of(context).style,
              windowBucket: windowBucket,
              paperGround: law?.ground,
              blockFrameLines: law?.blockFrameLines ?? false,
              unnamedMark: TimelineGridLaw.unnamedMarkOf(context),
              framesPerSecond: law?.framesPerSecond ?? 0,
              celContent: _celContent(shown),
              shown: headShown,
              // Baked as the timeline's rows are, in a world no live cut
              // moves (TimelineTileRasterSource.followsTheLiveCut).
              tileStore: TimelineGridTileStore.instance,
              stepsUntilShown: _stepsUntilShownAt,
              substrateGeneration: filmSubstrateGeneration,
              followsTheLiveCut: false,
              devicePixelRatio: EffectiveDevicePixelRatio.of(context),
            ),
          ),
        ),
      ),
    );
  }

  /// Whether the row's eye shows its blocks (I-129): its HEAD's, as the
  /// folders of the head's cut gate it ([railEyesOf]) — the row wears its
  /// head's eye as it wears its head's colour label ([trackConteRowShown]).
  /// One eye answers for every cut's blocks because a track's conte lays
  /// ONE head on its row in every cut, the eye with it ([ConteHead], F-343
  /// — 유저 2026-10-08: 「이거만 눈이랑 불투명도조차 링크하도록. 그거마저
  /// 머리로서 하나로되도록 통일」).
  bool _headShown() =>
      _conteHeadEye([
        for (final entry in layoutEntries) entry.cut,
      ], seat)?.shown ??
      true;

  /// The timeline's unworked-block tint (R26 #44) on this row's blocks,
  /// each one's cel asked of the cut it stands in and that cut's row at
  /// this seat ([_stripAt]) — the timeline's rows ask the active cut
  /// alone, and this row crosses every cut. None without
  /// [conteCelContent].
  ///
  /// 🗣️F-357 (유저 2026-10-14): 「콘티패널의 콘티레이어 프레임블록,
  /// 타임라인패널처럼 그림없으면 연해지는거 왜 통일안했는지? 법 통일해서
  /// 적용」. ↩️The row was laid over the film (I-73) with no tint at all.
  ///
  /// 🚨ONE SOURCE FOR ONE LAYING, kept on [shown] — which is itself kept
  /// while the cuts lie alike ([trackConteRowShown]), so the frames name
  /// the same cuts. The painter compares the fact by value, and a closure
  /// made on each build is a new fact every time: the row painted the
  /// whole film's conte cells again for a build that moved none of them
  /// (I-57).
  TimelineCelContentSource? _celContent(Layer shown) {
    final content = conteCelContent;
    if (content == null) {
      return null;
    }
    final kept = _celContents[shown];
    if (kept != null && kept.content == content) {
      return kept.source;
    }
    // The cel the block at [frame] shows and the cut it lies in — null on a
    // cell no block covers, where neither the grey nor the red is.
    ({Cut cut, LayerId layer, FrameId cel})? celAt(Layer row, int frame) {
      final cel = coveringDrawingBlockAt(row.timeline, frame)?.frameId;
      final strip = _stripAt(frame);
      return cel == null || strip == null
          ? null
          : (cut: strip.entry.cut, layer: strip.layer.id, cel: cel);
    }

    final source = TimelineCelContentSource(
      hasContent: (row, frame) => switch (celAt(row, frame)) {
        null => true,
        (:final cut, :final layer, :final cel) => content.holdsAPicture(
          cut,
          layer,
          cel,
        ),
      },
      cannotRead: (row, frame) => switch (celAt(row, frame)) {
        null => false,
        (:final cut, :final layer, :final cel) => content.cannotBeRead(
          cut,
          layer,
          cel,
        ),
      },
      revision: CelContentRevision.everyRow(content.revision),
    );
    _celContents[shown] = (content: content, source: source);
    return source;
  }

  /// [_celContent]'s source for each row as laid, with what it asks.
  static final Expando<
    ({ConteCelContent content, TimelineCelContentSource source})
  >
  _celContents = Expando('conte cel contents');

  /// The button of every cut that has no conte layer
  /// ([StoryboardConteCreatePainter]) — drawn, never pressed: the cells'
  /// press under it answers ([_pressed]).
  Widget _createButtons(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          key: ValueKey<String>('storyboard-conte-create-$_scope'),
          painter: StoryboardConteCreatePainter(
            spans: _cutSpans(withConteLayer: false),
            geometry: frameGeometry,
            crossAxisExtent: height,
            colorScheme: Theme.of(context).colorScheme,
            baseTextStyle: DefaultTextStyle.of(context).style,
            windowBucket: windowBucket,
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
  /// a cut without a conte layer — never reaches it. ↩️On the cut block that
  /// press died silently under it (the real-device "no selection where there
  /// is no cut block"): the cut's own gesture lay beneath. Nothing of THIS
  /// row answers a drag where it holds no panel (🧪2026-10-08: with the gate
  /// open every press, sweep and double click here read the same), so the
  /// gate is what keeps it that way for whatever is laid under the row next.
  Widget _gestureSlot(
    Layer shown,
    TimelineRangeGestureCallbacks stripGesture,
  ) => Positioned.fill(
    key: ValueKey<String>('storyboard-strip-gesture-slot-$_scope'),
    child: HitGate(
      admits: (position) => _stripAt(_frameAtX(position.dx)) != null,
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

  /// The cuts that hold a layer at this row's seat — or hold none — in
  /// order, each as its frames `[start, endExclusive)` on the track's axis.
  List<({int start, int endExclusive})> _cutSpans({
    required bool withConteLayer,
  }) => [
    for (final entry in layoutEntries)
      if ((conteRowAtSeat(entry.cut, seat) != null) == withConteLayer)
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
      final layer = conteRowAtSeat(entry.cut, seat);
      if (layer == null || layer.id != selection.layerId) {
        continue;
      }
      final start = math.max(
        entry.startFrame,
        conteRowGlobalFrameOf(entry, selection.startIndex),
      );
      final end = math.min(
        entry.endFrame,
        conteRowGlobalFrameOf(entry, selection.endIndexExclusive),
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

/// A CONTE ROW'S EDGES, at its blocks' boundaries — the timeline's chrome
/// layer, as the timeline's rows mount it: on the blocks' paper, in the
/// blocks' own corners. The row mounts it over its blocks
/// ([_StoryboardConteRow]).
///
/// One shape of grip, and where it sits decides what it does:
///
/// - on the CONTE (seat 0) the first panel's leading edge is the CUT's lead
///   edge, and every trailing edge is its panel's comma with the cut's
///   length riding the row end (edge unification — the division verb is
///   gone);
/// - on a row riding it, a block's two edges are that block's alone, as
///   its grips on the timeline are (I-73 — the drawn proposal 유저 took on
///   2026-10-08: 「엣지 — 블록의 양 끝」).
///
/// ↩️They stood in the conte blocks' two bands inside the cut block, a
/// triangle taking one band whole and never a picture (I-52, 유저
/// 2026-09-28: 「썸네일이 존재하는 블록은 엣지를 썸네일 안가리도록 …
/// 띠에만」); a block of this row has no picture to keep clear of.
class _StoryboardPanelEdges extends StatelessWidget {
  const _StoryboardPanelEdges({
    required this.trackId,
    required this.seat,
    required this.scope,
    required this.layoutEntries,
    required this.stripEdges,
    required this.row,
    required this.height,
    required this.frameGeometry,
    required this.windowBucket,
  });

  final TrackId trackId;

  /// Which row of the track's conte group this is ([_StoryboardConteRow]).
  final int seat;

  /// The row's word in its keys (`_StoryboardConteRow._scope`).
  final String scope;

  /// The track's cuts as this step lays them — the conte row's own list.
  final List<StoryboardTimelineLayoutEntry> layoutEntries;
  final StoryboardStripEdgeCallbacks stripEdges;

  /// The row the blocks are drawn as ([TimelineRowEditChromeLayer.gripRow])
  /// — its paper the ground the grips' ink is read off.
  final TimelineBlockRow row;

  /// The conte row's height.
  final double height;
  final TimelineFrameGeometryHandle frameGeometry;
  final ValueListenable<int> windowBucket;

  /// One entry per block of the row, in track order — what the edit chrome
  /// hangs its grips on.
  List<_StoryboardStripGrip> _grips() => [
    for (final entry in layoutEntries)
      ...seat == 0 ? _panelGrips(entry) : _riderGrips(entry),
  ];

  /// The conte's PANELS in [entry]'s cut.
  ///
  /// A cut edge is always on its panels (design, user's rule 2026-07-25):
  /// the first panel's leading edge IS the cut's start and the last panel's
  /// trailing edge IS its length. ↩️Those were the cut's ONLY grips while
  /// the panels were drawn inside the cut block; the cut block wears its own
  /// two now, on the V row (I-73), and these stay the panels'.
  ///
  /// EVERY panel hangs a leading grip (user's rule 2026-08-02). R4 had left
  /// it on the first panel alone, because P5 #8's interior front grips
  /// DELEGATED to the previous panel's back grip — two handles doing one
  /// thing. They are not that any more: a front grip takes the frames off
  /// the cut's HEAD and a back grip off its TAIL, so the two edges of one
  /// boundary name two edits.
  ///
  /// An inner trailing edge needs its panel's own TIMELINE key (the block
  /// its comma resizes), which the coverage cell cannot answer — the first
  /// cell's startIndex is clamped to 0 whatever its key says — so the keys
  /// are read off the row alongside the cells.
  List<_StoryboardStripGrip> _panelGrips(StoryboardTimelineLayoutEntry entry) {
    final layer = storyboardLayerForCut(entry.cut);
    if (layer == null) {
      return const [];
    }
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
          startFrame: entry.startFrame + cells[index].startIndex,
          endFrameExclusive: entry.startFrame + cells[index].endIndexExclusive,
          startGrip: true,
          endGrip: true,
          begin: _panelEdge(
            entry.cutId,
            panelIndex: index,
            commaBlockKey: index == cells.length - 1 || index >= keys.length
                ? null
                : keys[index],
          ),
        ),
    ];
  }

  /// What a grip on the panel at [panelIndex] of [cutId] begins.
  ///
  /// [panelIndex] is the panel's CUT-LOCAL ordinal: a leading grip is the
  /// same verb whatever the ordinal — the cut's lead edge, with this panel
  /// the one that gives up the commas — and the ordinal is what tells the
  /// session WHICH panel that is. [commaBlockKey] is the CUT-LOCAL timeline
  /// key of the block the trailing edge comma-resizes, or null when that
  /// edge is the cut's own length instead (the last panel — it goes through
  /// the cut-edge begin).
  ///
  /// R10 R4: no impersonation. A grip reports the edge it IS, and the rule
  /// that decides what moves lives one layer down, in the session — which
  /// is where the "a front edge inside a cut is really the previous back
  /// edge" trick belonged all along.
  bool Function(TimelineBlockEdge edge) _panelEdge(
    CutId cutId, {
    required int panelIndex,
    required int? commaBlockKey,
  }) =>
      (edge) => edge == TimelineBlockEdge.start || commaBlockKey == null
      ? stripEdges.onCutEdgeBegin(cutId, edge, panelIndex)
      : stripEdges.onCommaBegin(cutId, commaBlockKey);

  /// The blocks of [entry]'s row at this seat — its own stored ones, as the
  /// timeline's row hangs them ([timelineLayerGripBlocks]) — where the strip
  /// shows them: held inside the cut's conte, a block that runs past an end
  /// cut off there ([trackConteRowShown]).
  ///
  /// An edge that is not where the row draws it has no grip — what a sound
  /// spilling in from an earlier cut follows on the timeline (UI-R7 #6). A
  /// SYNCED row hangs none at all: it owns no timing, and its base's grips
  /// move both (W5).
  List<_StoryboardStripGrip> _riderGrips(StoryboardTimelineLayoutEntry entry) {
    final row = conteRowAtSeat(entry.cut, seat);
    if (row == null || isSyncedAttachedLayer(row)) {
      return const [];
    }
    // The conte's frames, in the row's own.
    final first = conteRowOwnFrameAt(entry, entry.startFrame);
    final end = first + entry.duration;
    return [
      for (final block in timelineLayerGripBlocks(row))
        if (block.endIndexExclusive > first && block.startIndex < end)
          (
            startFrame: conteRowGlobalFrameOf(
              entry,
              math.max(block.startIndex, first),
            ),
            endFrameExclusive: conteRowGlobalFrameOf(
              entry,
              math.min(block.endIndexExclusive, end),
            ),
            startGrip: block.startIndex >= first,
            endGrip: block.endIndexExclusive <= end,
            begin: (edge) => stripEdges.onRowEdgeBegin(
              entry.cutId,
              row.id,
              block.startIndex,
              edge,
            ),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final grips = _grips();
    return TimelineRowEditChromeLayer(
      paintName: 'storyboard-edit-chrome-$scope',
      // The grips sit on this row's blocks, and the blocks are the row's
      // colour label (⑲) — the ground law reads their ink off it.
      gripGround: layerMarkColor(row.layer.mark),
      gripRow: row,
      // The blocks' own window: the row spans the whole film, and the grips
      // are drawn where the view can reach, as the blocks under them are.
      windowBucket: windowBucket,
      // No layer: these blocks are rows of many cuts, and the row has no
      // run edges for a LayerId to name.
      layerId: null,
      resolver: TimelineRowChromeResolver(
        gripBlocks: [
          for (var index = 0; index < grips.length; index += 1)
            (
              ordinal: index,
              startIndex: grips[index].startFrame,
              endIndexExclusive: grips[index].endFrameExclusive,
              startGrip: grips[index].startGrip,
              endGrip: grips[index].endGrip,
            ),
        ],
        gripIdScope: trackConteRowId(trackId, seat: seat).value,
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
      // The row closes the identity in, by ordinal — the grip hooks
      // themselves know nothing about cuts, panels or rows.
      grips: TimelineRowGripCallbacks(
        onBegin: (_, ordinal, edge) =>
            ordinal >= 0 &&
            ordinal < grips.length &&
            grips[ordinal].begin(edge),
        onUpdate: stripEdges.onUpdate,
        onEnd: stripEdges.onEnd,
        onCancel: stripEdges.onCancel,
      ),
      runEdit: null,
    );
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
  }) : super(repaint: Listenable.merge([geometry, windowBucket]));

  /// The cuts that wear the button, each as its frames on the track's axis.
  final List<({int start, int endExclusive})> spans;
  final TimelineFrameGeometryHandle geometry;
  final double crossAxisExtent;
  final ColorScheme colorScheme;
  final TextStyle baseTextStyle;
  final ValueListenable<int> windowBucket;

  /// How far the view reaches along the frames — the live geometry's
  /// ([TimelineFrameGeometry.viewExtentPx]).
  double get viewportMainExtent => geometry.value.viewExtentPx;

  /// Each button's plate inside the visible window, row-local — THE probe
  /// surface, and what [paint] lays down.
  List<RRect> plates() {
    final frames = geometry.value;
    final cell = frames.frameCellExtent;
    if (cell <= 0) {
      return const [];
    }
    final window = visibleFrameWindowFor(
      bucket: windowBucket,
      viewportMainExtent: viewportMainExtent,
      cellExtent: cell,
      frameStartIndex: 0,
      frameEndIndexExclusive: 1 << 30,
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
  );
}

/// The eye of the row that speaks for [seat] among [cuts] ([conteHeadAt]),
/// as the folders of its cut gate it: the ONE eye every cut's row at that
/// seat wears on the storyboard, its blocks and its keys alike (F-343,
/// I-129) - or null while no cut holds a row there.
RailEye? _conteHeadEye(Iterable<Cut> cuts, int seat) {
  final head = conteHeadAt(cuts, seat);
  return head == null ? null : _cutsOwnEye(head.cut, head.row);
}
