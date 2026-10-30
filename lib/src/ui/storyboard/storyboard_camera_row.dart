part of '../storyboard_panel.dart';

/// THE TRACK'S CAMERA ROW — the cuts' camera layers as ONE row on the
/// track's axis, at the top of the track's CAM section (I-73 ④).
///
/// 🗣️유저 2026-10-08: 「그리고 카메라는 로컬이랑 똑같이 최상단행. cam섹션의
/// 제일 위」 · 「카메라 행 범위는 키표시/이동/레인 등 모든거 콘티패널에서
/// 가능. 컷 클램핑만 되도록」 · 「카메라행은 ol떄 2줄로 만드는거 ok」 ·
/// 「컷 클리핑하는거 사이 점선으로 만드는거 좋네. 굉장히 알기쉬워. 그러고
/// 아까 말한 선을 이 2줄로 나뉘는거에도 잘 적용하면 이어져있단 느낌
/// 날거같거든. ol쪽 만나면 선을 뭔가 꺾어서 위로 향하게 해서 직선
/// 잇는다던가?」.
///
/// Each cut's camera is drawn over the cut's OWN frames ([CameraRowReach]):
/// its place on the track and the のりしろ an O.L asks before and after it.
/// Where two cuts' own frames run at once the row splits in two — the cut
/// leaving on the upper line, the cut arriving on the lower — and each cut's
/// のりしろ is washed on its own half; everywhere else a cut is drawn on the
/// one line in the middle. A key the cut keeps outside its own frames is not
/// drawn: the row is clamped to the cut.
///
/// The keys are the TIMELINE's camera row's — the camera's lane
/// ([cameraUnionHeader]) drawn by the shared key marks
/// ([timelineLaneKeySpan]), joined by the shared line
/// ([TimelineLaneKeysLine]), which steps between the lines where the cut
/// does, and named over it by the shared word ([timelineStretchWordSpan]).
/// A row has nothing of its own to draw them with.
class _StoryboardCameraRow extends KeptPiece
    with _StoryboardProjectionKeys {
  const _StoryboardCameraRow({
    required this.trackId,
    required this.reaches,
    required this.width,
    required this.height,
    required this.timelineScale,
    required this.frameGeometry,
    required this.windowBucket,
    required this.viewportWidth,
    required this.instructionDefById,
    this.onRowFramePress,
    this.onCameraCutPress,
    this.onEditCameraCell,
    this.stripSelect,
  });

  @override
  final TrackId trackId;
  @override
  final List<CameraRowReach> reaches;
  @override
  final double width;

  /// Its label's height ([_StoryboardRowHeights.camera]) — one row.
  @override
  final double height;
  @override
  final TimelineScale timelineScale;
  @override
  final TimelineFrameGeometryHandle frameGeometry;
  @override
  final ValueListenable<int> windowBucket;
  @override
  final double viewportWidth;

  /// The vocabulary the camera's moves are written in ([cameraUnionHeader]).
  final CameraInstructionDef? Function(String id) instructionDefById;

  @override
  final StoryboardRowFramePress? onRowFramePress;
  @override
  final StoryboardCameraCutPress? onCameraCutPress;

  /// A double click on the row's cell — the timeline camera row's own
  /// (「빈 칸이면 만들고, 찬 칸이면 연다」): the camera layer of the cut the
  /// first click stood in, at the frame it stood on.
  final VoidCallback? onEditCameraCell;

  /// The cut-local range selection and its move — the conte row's
  /// ([StoryboardStripSelectCallbacks]) — on the camera layer of the cut a
  /// sweep starts in: 「카메라 행 범위는 키표시/이동/레인 등 모든거
  /// 콘티패널에서 가능. 컷 클램핑만 되도록」 (유저 2026-10-08).
  final StoryboardStripSelectCallbacks? stripSelect;

  LayerId get _rowId => trackCameraRowId(trackId);

  @override
  TimelineRowAddress get _address => LayerRowAddress(_rowId);

  @override
  String get _keyName => 'camera';

  @override
  String get _markPrefix => 'storyboard-camera';

  @override
  Layer? _layerOf(Cut cut) => cut.layers.cameraLayer;

  /// The camera's lane — the timeline's camera row's: its keys' union, with
  /// the moves named over its line.
  @override
  PropertyLaneRow _laneOf(Cut cut, Layer layer) =>
      cameraUnionHeader(cut.camera.track, defById: instructionDefById);

  /// What the row shows — its cuts by how they lie and how far each one's
  /// own frames reach ([CameraRowReach.==]), and the vocabulary its moves
  /// are named in: one lookup of one set while the set is the same.
  ///
  /// 🚨I-57 (10-14): built again with the panel on every notify and every
  /// cut crossed, the row handed its LayoutBuilders new builders — 🔬two of
  /// the layouts a crossing ran in the strip on the AMMI OP, each painting
  /// the whole strip's layer again.
  @override
  Object? get facts => (
    trackId,
    ByList(reaches),
    width,
    height,
    timelineScale.pixelsPerFrame,
    timelineScale.minBlockWidth,
    ByIdentity(frameGeometry),
    ByIdentity(windowBucket),
    // By the window its keys are built for, not the breadth — the S rows'
    // own reason ([_StoryboardSeRow.facts]).
    timelineFrameWindowReachFor(
      viewportExtent: viewportWidth,
      cellExtent: timelineScale.pixelsPerFrame,
    ),
    instructionDefById,
    onRowFramePress != null,
    onCameraCutPress != null,
    onEditCameraCell != null,
    stripSelect != null,
  );

  @override
  Widget buildKept(BuildContext context) {
    final onEdit = onEditCameraCell;
    return _strip(
      context,
      keys: _keys(),
      onEdit: onEdit == null ? null : (_) => onEdit(),
      over: [
        if (stripSelect case final select?) ...[
          ..._gestureSlots(_cellsOf(select)),
          _selectionBand(select),
        ],
      ],
    );
  }

  /// The CELL selection a sweep here writes: the conte row's
  /// ([_StoryboardConteRow._stripGesture]), on the camera layer of the cut
  /// the sweep began in and the frames of its own.
  _ProjectionSweeps _cellsOf(StoryboardStripSelectCallbacks select) => (
    holds: (layer, ownFrame) {
      final selection = select.selection.value;
      return selection != null &&
          selection.coversLayer(layer) &&
          selection.contains(ownFrame);
    },
    select: (layer, anchor, head, _) =>
        select.onDrag(layerId: layer, anchorIndex: anchor, headIndex: head),
    clear: select.onClear,
    beginMove: (layer) => select.move?.onBegin(layer) ?? false,
    moveBy: (frameDelta) => select.move?.onUpdate(frameDelta, null),
    endMove: select.move?.onEnd ?? _noMove,
    cancelMove: select.move?.onCancel ?? _noMove,
  );

  /// The selection's band — the timeline's ONE band decoration — over the
  /// selected frames of the cut whose camera layer it names, on the line
  /// that cut is drawn on there: the whole row where it runs alone, its
  /// half where it shares its own frames with a neighbour. One listener
  /// for the row, pointer-transparent like every band.
  Widget _selectionBand(StoryboardStripSelectCallbacks select) =>
      Positioned.fill(
        child: IgnorePointer(
          child: ValueListenableBuilder<TimelineFrameRangeSelection?>(
            valueListenable: select.selection,
            builder: (context, selection, _) => _rangeBand(selection),
          ),
        ),
      );

  Widget _rangeBand(TimelineFrameRangeSelection? selection) {
    if (selection == null || timelineScale.pixelsPerFrame <= 0) {
      return const SizedBox.shrink();
    }
    for (final reach in reaches) {
      if (reach.entry.cut.layers.cameraLayer?.id != selection.layerId) {
        continue;
      }
      // Held inside the cut: the timeline's cells run on past its end, and
      // a selection made there names frames this row does not draw.
      return Stack(
        children: [
          for (final stretch in reach.stretchesOf(
            selection.startIndex,
            selection.endIndexExclusive,
          ))
            _bandPiece(stretch),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  /// The band over one [stretch] of a cut's own frames, on its line.
  Widget _bandPiece(CameraRowStretch stretch) {
    final across = stretch.line == CameraRowLine.middle ? height : height / 2;
    return Positioned(
      key: ValueKey<String>('storyboard-camera-range-selection-${stretch.from}'),
      left: timelineScale.leftForFrame(stretch.from),
      top: stretch.line == CameraRowLine.lower ? height / 2 : 0,
      width: timelineScale.spanWidth(stretch.from, stretch.to),
      height: across,
      child: Semantics(
        label: AppText.strings.tlSelectedFrameRange,
        container: true,
        child: DecoratedBox(
          decoration: timelineRangeSelectionBandDecorationAt(
            cellExtent: timelineScale.pixelsPerFrame,
            crossExtent: across,
          ),
        ),
      ),
    );
  }
}

/// A press on the camera row, or on one of its lanes, that lands in a cut:
/// the [row] pressed, the cut whose own frames hold the pointer — over an
/// O.L, the one on the pointer's line — and the frame of the cut's own
/// under it.
typedef StoryboardCameraCutPress =
    void Function(TimelineRowAddress row, CutId cutId, int ownFrame);

/// How far down the camera row its UPPER line runs, and its LOWER — the
/// drawn proposal's (I-73 ④, 4판): 「위 줄(행 높이의 27%) = 나가는 컷, 아래
/// 줄(73%) = 들어오는 컷」.
const double _cameraRowUpperLine = 0.27;
const double _cameraRowLowerLine = 0.73;

/// The band a key mark stands in on one of the two lines, across: the half
/// of the row its line runs through, and a little past the middle — the
/// proposal's 0~54% and 46~100%.
const double _cameraRowLineBand = 0.54;

double _cameraRowLineAt(CameraRowLine line) => switch (line) {
  CameraRowLine.middle => 0.5,
  CameraRowLine.upper => _cameraRowUpperLine,
  CameraRowLine.lower => _cameraRowLowerLine,
};

/// THE CAMERA ROW'S GROUND — what lies under its keys: each cut's のりしろ
/// washed on the half its line runs through, a thin line across the middle
/// of every stretch two cuts share, and a dashed line where each cut
/// begins. Painted, never pressed, over the panel's window alone.
///
/// The のりしろ wears the timeline's のりしろ colour ([AppColors.noriShiro],
/// the boundary line the timeline draws at a cut's drawn end), faint.
class StoryboardCameraRowPainter extends CustomPainter with RepaintOnProps {
  StoryboardCameraRowPainter({
    required this.reaches,
    required this.geometry,
    required this.crossAxisExtent,
    required this.colorScheme,
    required this.windowBucket,
  }) : super(repaint: Listenable.merge([geometry, windowBucket]));

  final List<CameraRowReach> reaches;
  final TimelineFrameGeometryHandle geometry;
  final double crossAxisExtent;
  final ColorScheme colorScheme;
  final ValueListenable<int> windowBucket;

  /// How far the view reaches along the frames — the live geometry's, so a
  /// widened view repaints the row ([TimelineFrameGeometry.viewExtentPx]).
  double get viewportMainExtent => geometry.value.viewExtentPx;

  /// The のりしろ's wash — the drawn proposal's 30%.
  static const double noriShiroWashAlpha = 0.3;

  /// The frames as laid out now and the panel's window over them — where
  /// every probe below starts — or null while a cell has no extent to lay
  /// anything on.
  ({
    TimelineFrameGeometry frames,
    ({int startIndex, int endIndexExclusive}) window,
  })?
  _laidOut() {
    final frames = geometry.value;
    final cell = frames.frameCellExtent;
    if (cell <= 0) {
      return null;
    }
    return (
      frames: frames,
      window: visibleFrameWindowFor(
        bucket: windowBucket,
        viewportMainExtent: viewportMainExtent,
        cellExtent: cell,
        frameStartIndex: 0,
        frameEndIndexExclusive: 1 << 30,
      ),
    );
  }

  /// Every のりしろ wash inside the window, row-local — THE probe surface,
  /// and what [paint] lays down.
  List<Rect> noriShiroWashes() {
    final laid = _laidOut();
    if (laid == null) {
      return const [];
    }
    final (:frames, :window) = laid;
    final half = crossAxisExtent / 2;
    final rects = <Rect>[];
    void wash(int from, int to, CameraRowReach reach) {
      final start = math.max(from, window.startIndex);
      final end = math.min(to, window.endIndexExclusive);
      if (end <= start) {
        return;
      }
      final (top, bottom) = switch (reach.lineAt(start)) {
        CameraRowLine.middle => (0.0, crossAxisExtent),
        CameraRowLine.upper => (0.0, half),
        CameraRowLine.lower => (half, crossAxisExtent),
      };
      rects.add(
        Rect.fromLTRB(frames.edgeAt(start), top, frames.edgeAt(end), bottom),
      );
    }

    for (final reach in reaches) {
      // The のりしろ before the cut's place, and after it. Each lies on one
      // line: only a span two sides share asks for one (a fade stays inside
      // its cut), it asks as much of the neighbour across that edge — or of
      // the gap — and a track's spans never overlap.
      wash(reach.mediaStart, reach.entry.startFrame, reach);
      wash(reach.entry.endFrame, reach.mediaEnd, reach);
    }
    return rects;
  }

  /// The stretches two cuts share inside the window, as the line across
  /// their middle — row-local.
  List<(Offset, Offset)> sharedMiddles() {
    final laid = _laidOut();
    if (laid == null) {
      return const [];
    }
    final (:frames, :window) = laid;
    final middle = crossAxisExtent / 2;
    return [
      for (final reach in reaches)
        if (reach.leavingFrom < reach.mediaEnd &&
            reach.mediaEnd > window.startIndex &&
            reach.leavingFrom < window.endIndexExclusive)
          (
            Offset(
              frames.edgeAt(math.max(reach.leavingFrom, window.startIndex)),
              middle,
            ),
            Offset(
              frames.edgeAt(math.min(reach.mediaEnd, window.endIndexExclusive)),
              middle,
            ),
          ),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final wash = Paint()
      ..color = AppColors.noriShiro.withValues(alpha: noriShiroWashAlpha);
    for (final rect in noriShiroWashes()) {
      canvas.drawRect(rect, wash);
    }
    final divider = Paint()
      ..color = colorScheme.outlineVariant
      ..strokeWidth = 1;
    for (final (from, to) in sharedMiddles()) {
      canvas.drawLine(from, to, divider);
    }
  }

  @override
  // Geometry and the window are absent on purpose — they arrive through
  // `repaint`.
  Object get props => (
    ByList([
      for (final reach in reaches)
        (
          reach.entry.startFrame,
          reach.entry.endFrame,
          reach.mediaStart,
          reach.mediaEnd,
          reach.arrivingUntil,
          reach.leavingFrom,
        ),
    ]),
    crossAxisExtent,
    colorScheme,
  );
}
