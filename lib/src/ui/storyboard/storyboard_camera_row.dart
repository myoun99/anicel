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
/// ([timelineUnionKeySpan]), joined by the shared line
/// ([TimelineLaneKeysLine]), which steps between the lines where the cut
/// does, and named over it by the shared word ([timelineStretchWordSpan]).
/// A row has nothing of its own to draw them with.
class _StoryboardCameraRow extends StatelessWidget {
  const _StoryboardCameraRow({
    required this.track,
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

  final Track track;

  /// The track's cuts as this step lays them, each with its own frames on
  /// the track ([cameraRowReachesOf]).
  final List<CameraRowReach> reaches;

  /// The scroll content's full width — the V row's own.
  final double width;

  /// Its label's height ([_StoryboardRowHeights.camera]) — one row.
  final double height;
  final TimelineScale timelineScale;
  final TimelineFrameGeometryHandle frameGeometry;
  final ValueListenable<int> windowBucket;
  final double viewportWidth;

  /// The vocabulary the camera's moves are written in ([cameraUnionHeader]).
  final CameraInstructionDef? Function(String id) instructionDefById;

  /// A press where no cut's own frames are — a gap: the row and the frame
  /// under the pointer, the storyboard's one cell press.
  final StoryboardRowFramePress? onRowFramePress;

  /// A press on a cut's own frames: the cut it lands in and the frame of the
  /// cut's own under the pointer ([StoryboardCameraCutPress]).
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

  LayerId get _rowId => trackCameraRowId(track.id);

  int _frameAtX(double x) =>
      timelineScale.pixelsPerFrame <= 0 ? 0 : timelineScale.frameAt(x);

  /// [_reachAt]'s cut and its camera layer — what a sweep there selects
  /// on. Null where no cut's own frames reach, or the cut has no camera
  /// layer to hold a selection.
  ({CameraRowReach reach, LayerId camera})? _cameraAt(
    int frame, {
    required bool upper,
  }) {
    final reach = _reachAt(frame, upper: upper);
    final camera = reach?.entry.cut.layers.cameraLayer;
    return reach == null || camera == null
        ? null
        : (reach: reach, camera: camera.id);
  }

  /// THE cut a pointer at [frame] means — the one whose own frames hold it;
  /// over an O.L, the one on the line the pointer is on: the leaving cut on
  /// the upper half, the arriving cut on the lower. Null where no cut's own
  /// frames reach.
  CameraRowReach? _reachAt(int frame, {required bool upper}) {
    final at = [
      for (final reach in reaches)
        if (reach.reaches(frame)) reach,
    ];
    if (at.isEmpty) {
      return null;
    }
    return upper ? at.first : at.last;
  }

  void _pressed(Offset local, int frame) {
    final reach = _reachAt(frame, upper: local.dy < height / 2);
    if (reach == null) {
      onRowFramePress?.call(LayerRowAddress(_rowId), frame);
      return;
    }
    onCameraCutPress?.call(
      track.id,
      reach.entry.cutId,
      reach.ownFrameAt(frame),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onEdit = onEditCameraCell;
    return SizedBox(
      key: ValueKey<String>('storyboard-camera-row-${track.id.value}'),
      width: math.max(
        _storyboardCutsExtent([for (final reach in reaches) reach.entry],
            timelineScale),
        width,
      ),
      height: height,
      child: Stack(
        children: [
          _ground(context),
          _StoryboardCutStarts(
            paintKey: ValueKey<String>(
              'storyboard-camera-cut-starts-${track.id.value}',
            ),
            starts: [for (final reach in reaches) reach.entry.startFrame],
            geometry: frameGeometry,
            windowBucket: windowBucket,
            viewportWidth: viewportWidth,
          ),
          Positioned.fill(child: IgnorePointer(child: _keys())),
          if (onRowFramePress != null ||
              onCameraCutPress != null ||
              onEdit != null)
            _storyboardRowPressLayer(
              key: ValueKey<String>(
                'storyboard-camera-press-${track.id.value}',
              ),
              row: LayerRowAddress(_rowId),
              cellExtent: timelineScale.pixelsPerFrame,
              frameAt: (local) => timelineScale.pixelsPerFrame <= 0
                  ? null
                  : timelineScale.frameAt(local.dx),
              onRowFramePress: onRowFramePress,
              onPressAt: _pressed,
              onEdit: onEdit == null ? null : (_) => onEdit(),
            ),
          if (stripSelect case final select?) ...[
            _gestureSlot(select, upper: true),
            _gestureSlot(select, upper: false),
            _selectionBand(select),
          ],
        ],
      ),
    );
  }

  /// The row's ground ([StoryboardCameraRowPainter]) — each cut's のりしろ
  /// and the stretches two cuts share — painted, never pressed.
  Widget _ground(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          key: ValueKey<String>('storyboard-camera-ground-${track.id.value}'),
          painter: StoryboardCameraRowPainter(
            reaches: reaches,
            geometry: frameGeometry,
            crossAxisExtent: height,
            colorScheme: Theme.of(context).colorScheme,
            windowBucket: windowBucket,
            viewportMainExtent: viewportWidth,
          ),
        ),
      ),
    ),
  );

  /// THE range gesture — the timeline's, as the conte row lays it — over
  /// [upper]'s half of the row: a pan selects a run of a cut's own frames,
  /// a pan from inside the selection moves the keys on them. Each half
  /// says which cut its press means where two cuts' own frames run at once
  /// ([_reachAt]), so the row takes it in two; and it answers only where
  /// a cut's own frames reach, as the conte row's answers only on panels.
  Widget _gestureSlot(
    StoryboardStripSelectCallbacks select, {
    required bool upper,
  }) => Positioned(
    key: ValueKey<String>(
      'storyboard-camera-gesture-${upper ? 'upper' : 'lower'}-'
      '${track.id.value}',
    ),
    left: 0,
    right: 0,
    top: upper ? 0 : height / 2,
    height: height / 2,
    child: _FrameHitGate(
      claimsDx: (dx) => _cameraAt(_frameAtX(dx), upper: upper) != null,
      child: Stack(
        children: [
          TimelineFrameRangeGestureLayer(
            row: LayerRowAddress(_rowId),
            geometry: frameGeometry,
            crossAxisExtent: height / 2,
            callbacks: _rangeGesture(select, upper: upper),
          ),
        ],
      ),
    ),
  );

  /// The camera's half of the shared range gesture: the conte row's
  /// ([_StoryboardConteRow._stripGesture]) on the cut's camera layer and its
  /// own frames — a sweep held to the cut it began in, because a cut's own
  /// index names no frame of another ([CameraRowReach.ownFrameAt]).
  TimelineRangeGestureCallbacks _rangeGesture(
    StoryboardStripSelectCallbacks select, {
    required bool upper,
  }) => TimelineRangeGestureCallbacks(
    isInSelection: (_, frame) {
      final at = _cameraAt(frame, upper: upper);
      final selection = select.selection.value;
      return at != null &&
          selection != null &&
          selection.coversLayer(at.camera) &&
          selection.contains(at.reach.ownFrameAt(frame));
    },
    onSelectUpdate: (_, anchorIndex, headIndex, _) {
      final at = _cameraAt(anchorIndex, upper: upper);
      if (at == null) {
        return;
      }
      select.onDrag(
        layerId: at.camera,
        anchorIndex: at.reach.ownFrameAt(anchorIndex),
        headIndex: at.reach.ownFrameAt(headIndex),
      );
    },
    onTapClear: (_) => select.onClear(),
    onMoveBegin: (_, frame) {
      final at = _cameraAt(frame, upper: upper);
      return at != null && (select.move?.onBegin(at.camera) ?? false);
    },
    // A cut has one camera layer: there is nowhere sideways to land.
    onMoveUpdate: (frameDelta, _) => select.move?.onUpdate(frameDelta, null),
    onMoveEnd: select.move?.onEnd ?? _noMove,
    onMoveCancel: select.move?.onCancel ?? _noMove,
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
      final start = reach.trackFrameOf(selection.startIndex);
      final end = math.min(
        reach.mediaEnd,
        reach.trackFrameOf(selection.endIndexExclusive),
      );
      if (end <= start) {
        return const SizedBox.shrink();
      }
      final edges = {
        start,
        for (final edge in [reach.arrivingUntil, reach.leavingFrom])
          if (edge > start && edge < end) edge,
        end,
      }.toList()..sort();
      return Stack(
        children: [
          for (var index = 0; index + 1 < edges.length; index += 1)
            _bandPiece(reach, edges[index], edges[index + 1]),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  /// The band over `[from, to)` — frames of [reach]'s cut on one line.
  Widget _bandPiece(CameraRowReach reach, int from, int to) {
    final line = reach.lineAt(from);
    final across = line == CameraRowLine.middle ? height : height / 2;
    return Positioned(
      key: ValueKey<String>('storyboard-camera-range-selection-$from'),
      left: timelineScale.leftForFrame(from),
      top: line == CameraRowLine.lower ? height / 2 : 0,
      width: timelineScale.spanWidth(from, to),
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

  /// Every cut's keys and the line between them, inside the panel's window
  /// — re-made when the window crosses a bucket, laid out on the live axis
  /// in between, as the V row's blocks are painted.
  Widget _keys() => ValueListenableBuilder<int>(
    valueListenable: windowBucket,
    builder: (context, _, _) {
      final window = visibleFrameWindowFor(
        bucket: windowBucket,
        viewportMainExtent: viewportWidth,
        cellExtent: timelineScale.pixelsPerFrame,
        frameStartIndex: 0,
        frameEndIndexExclusive: 1 << 30,
      );
      return TimelineFrameSpanLayout(
        key: ValueKey<String>('storyboard-camera-keys-${track.id.value}'),
        geometry: frameGeometry,
        crossAxisExtent: height,
        axis: Axis.horizontal,
        children: [
          for (final reach in reaches)
            if (reach.mediaEnd > window.startIndex &&
                reach.mediaStart < window.endIndexExclusive)
              ..._cutKeys(reach, window),
        ],
      );
    },
  );

  /// [reach]'s cut's camera keys inside its own frames and [window]: the
  /// line between its first and its last, the moves over it, then the marks
  /// over them.
  List<Widget> _cutKeys(
    CameraRowReach reach,
    ({int startIndex, int endIndexExclusive}) window,
  ) {
    final cut = reach.entry.cut;
    final camera = cut.layers.cameraLayer;
    if (camera == null) {
      return const [];
    }
    final lane = cameraUnionHeader(
      cut.camera.track,
      defById: instructionDefById,
    );
    final line = _line(reach, camera, lane, window);
    return [
      ?line,
      for (final stretch in lane.stretchWords)
        if (_stretchOnTheLine(reach, stretch, window) case final placed?)
          timelineStretchWordSpan(
            keyPrefix: 'storyboard-camera',
            layer: camera,
            stretch: placed,
            axis: Axis.horizontal,
          ),
      for (final key in lane.keyedFrames.toList()..sort())
        if (reach.reaches(reach.trackFrameOf(key)) &&
            reach.trackFrameOf(key) >= window.startIndex &&
            reach.trackFrameOf(key) < window.endIndexExclusive)
          _key(reach, camera, lane, key),
    ];
  }

  /// [stretch] where this row writes it, on the track: over the part of it
  /// its cut draws on the one line in the middle — 「키 이름은 한 줄일
  /// 때만」, the drawn proposal's, holds for the move's name as for a key's:
  /// two lines leave no room for a word — or null where none of it is
  /// there, or the window holds none of it.
  LaneStretchWord? _stretchOnTheLine(
    CameraRowReach reach,
    LaneStretchWord stretch,
    ({int startIndex, int endIndexExclusive}) window,
  ) {
    final from = math.max(
      reach.trackFrameOf(stretch.from),
      reach.arrivingUntil,
    );
    final to = math.min(reach.trackFrameOf(stretch.to), reach.leavingFrom - 1);
    if (to < from ||
        to < window.startIndex ||
        from >= window.endIndexExclusive) {
      return null;
    }
    return (from: from, to: to, word: stretch.word, ink: stretch.ink);
  }

  /// One key's mark, on the line its cut is drawn on there.
  Widget _key(
    CameraRowReach reach,
    Layer camera,
    PropertyLaneRow lane,
    int key,
  ) {
    final at = reach.trackFrameOf(key);
    final line = reach.lineAt(at);
    return timelineUnionKeySpan(
      keyPrefix: 'storyboard-camera',
      layer: camera,
      lane: lane,
      frame: key,
      at: at,
      crossExtent: line == CameraRowLine.middle
          ? height
          : height * _cameraRowLineBand,
      crossInset: switch (line) {
        CameraRowLine.middle => null,
        CameraRowLine.upper => 0,
        CameraRowLine.lower => height * (1 - _cameraRowLineBand),
      },
      // 「키 이름은 한 줄일 때만」 — two lines leave no room for a word.
      named: line == CameraRowLine.middle,
    );
  }

  /// The line between [reach]'s cut's first key and its last, clamped to
  /// the end of its own frames, stepping where its cut changes lines — or
  /// null while it has no two keys there to join. Its own frames begin at
  /// its frame 0, before every key.
  Widget? _line(
    CameraRowReach reach,
    Layer camera,
    PropertyLaneRow lane,
    ({int startIndex, int endIndexExclusive}) window,
  ) {
    final span = timelineKeysLineSpan(lane.keyedFrames);
    if (span == null) {
      return null;
    }
    final from = reach.trackFrameOf(span.first);
    final last = reach.trackFrameOf(span.last);
    final to = math.min(last, reach.mediaEnd - 1);
    if (to < from ||
        to < window.startIndex ||
        from >= window.endIndexExclusive) {
      return null;
    }
    return TimelineFrameSpan(
      key: ValueKey<String>('storyboard-camera-line-span-${camera.id}'),
      placement: TimelineFrameSpanPlacement(
        startIndex: from,
        endIndexExclusive: to + 1,
      ),
      child: TimelineLaneKeysLine(
        key: ValueKey<String>('storyboard-camera-line-${camera.id}'),
        axis: Axis.horizontal,
        cells: to + 1 - from,
        color: layerMarkColor(camera.mark),
        endsAtKey: last == to,
        crossFraction: _cameraRowLineAt(reach.lineAt(from)),
        // In box order: a track's spans never overlap, so a stretch shared
        // with the cut before ends before one shared with the cut after
        // begins — a cut an O.L covers whole has both at its ends.
        steps: [
          for (final edge in {reach.arrivingUntil, reach.leavingFrom})
            if (edge > from && edge <= to)
              (edge: edge - from, to: _cameraRowLineAt(reach.lineAt(edge))),
        ],
      ),
    );
  }
}

/// A press on the camera row that lands in a cut: the track, the cut whose
/// own frames hold the pointer — over an O.L, the one on the pointer's line
/// — and the frame of the cut's own under it.
typedef StoryboardCameraCutPress =
    void Function(TrackId trackId, CutId cutId, int ownFrame);

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
    required this.viewportMainExtent,
  }) : super(repaint: Listenable.merge([geometry, windowBucket]));

  final List<CameraRowReach> reaches;
  final TimelineFrameGeometryHandle geometry;
  final double crossAxisExtent;
  final ColorScheme colorScheme;
  final ValueListenable<int> windowBucket;
  final double viewportMainExtent;

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
    viewportMainExtent,
  );
}
