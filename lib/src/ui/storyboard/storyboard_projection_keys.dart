part of '../storyboard_panel.dart';

/// WHAT A PROJECTION ROW'S KEYS ARE DRAWN WITH — the camera row's, and every
/// lane a projection row twirls down: each cut's keys of one lane of the
/// cut's layer the row shows, over the cut's own frames ([CameraRowReach]),
/// split in two lines where two cuts' own frames run at once, on the row's
/// ground of のりしろ, under the dashes where each cut begins; and the press
/// that stands on the row there.
///
/// 🗣️유저 2026-10-08 (I-73 ④): 「카메라 행 범위는 키표시/이동/레인 등 모든거
/// 콘티패널에서 가능. 컷 클램핑만 되도록」. A lane the row twirls down is
/// drawn as the row is, from its own lane of each cut's layer — on the
/// timeline a lane is drawn as its row is too ([TimelineLaneFrameRow]): the
/// same marks, the same line, held to the same cut.
mixin _StoryboardProjectionKeys on Widget {
  TrackId get trackId;

  /// The track's cuts as this step lays them, each with its own frames on
  /// the track ([cameraRowReachesOf]).
  List<CameraRowReach> get reaches;

  /// The scroll content's full width — the V row's own.
  double get width;

  /// Its label's height — one row.
  double get height;
  TimelineScale get timelineScale;
  TimelineFrameGeometryHandle get frameGeometry;
  ValueListenable<int> get windowBucket;
  double get viewportWidth;

  /// A press where no cut's own frames are — a gap: the row and the frame
  /// under the pointer, the storyboard's one cell press.
  StoryboardRowFramePress? get onRowFramePress;

  /// A press on a cut's own frames: the row, the cut it lands in and the
  /// frame of the cut's own under the pointer ([StoryboardCameraCutPress]).
  StoryboardCameraCutPress? get onCameraCutPress;

  /// The address this row is stood on by: the projection row's, or one of
  /// its lanes'.
  TimelineRowAddress get _address;

  /// The word this row's parts are keyed by.
  String get _keyName;

  /// The word its key marks are keyed by, before their layer's id.
  String get _markPrefix;

  /// The layer of [cut] the row shows ([projectedRowOf]), or null where
  /// the cut holds none.
  Layer? _layerOf(Cut cut);

  /// The lane of [cut]'s [layer] this row draws, or null where it draws
  /// none.
  PropertyLaneRow? _laneOf(Cut cut, Layer layer);

  /// The eye [cut]'s [layer] wears on this row — its cut's own answer for
  /// it by default ([_cutsOwnEye]).
  RailEye _eyeOf(Cut cut, Layer layer) => _cutsOwnEye(cut, layer);

  /// Every cut's layer this row shows, with the eye it wears here
  /// ([_eyeOf]) — what its keys, its line and its words are drawn in, as
  /// the row's blocks are: 🗣️I-129-Q1 (유저 2026-10-25 「셋 다 같은 법으로
  /// 흐린다」 — 투영 키는 폴더 숨김도 본다). ↩️They read each layer's own
  /// switch alone, so a folder that hid the row left its keys dark.
  Map<LayerId, RailEye> get _eyes => {
    for (final reach in reaches)
      if (_layerOf(reach.entry.cut) case final layer?)
        layer.id: _eyeOf(reach.entry.cut, layer),
  };

  int _frameAtX(double x) =>
      timelineScale.pixelsPerFrame <= 0 ? 0 : timelineScale.frameAt(x);

  /// [_reachAt]'s cut and the layer the row shows of it — what a sweep there
  /// selects on. Null where no cut's own frames reach, or the cut holds no
  /// layer there to hold a selection.
  ({CameraRowReach reach, LayerId layer})? _layerAt(
    int frame, {
    required bool upper,
  }) {
    final reach = _reachAt(frame, upper: upper);
    final layer = reach == null ? null : _layerOf(reach.entry.cut);
    return reach == null || layer == null
        ? null
        : (reach: reach, layer: layer.id);
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
      onRowFramePress?.call(_address, frame);
      return;
    }
    onCameraCutPress?.call(
      _address,
      reach.entry.cutId,
      reach.ownFrameAt(frame),
    );
  }

  /// The row: its ground, where each cut begins, [keys] — pointer-blind —
  /// and the press, with [over] laid above them all. [onEdit] is its cell's
  /// double click.
  Widget _strip(
    BuildContext context, {
    required Widget keys,
    required void Function(int frame)? onEdit,
    required List<Widget> over,
  }) => SizedBox(
    key: ValueKey<String>('storyboard-$_keyName-row-${trackId.value}'),
    width: math.max(
      _storyboardCutsExtent([
        for (final reach in reaches) reach.entry,
      ], timelineScale),
      width,
    ),
    height: height,
    child: Stack(
      children: [
        _ground(context),
        _StoryboardCutStarts(
          paintKey: ValueKey<String>(
            'storyboard-$_keyName-cut-starts-${trackId.value}',
          ),
          starts: [for (final reach in reaches) reach.entry.startFrame],
          geometry: frameGeometry,
          windowBucket: windowBucket,
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: RailEyes(eyes: _eyes, child: keys),
          ),
        ),
        if (onRowFramePress != null || onCameraCutPress != null || onEdit != null)
          _storyboardRowPressLayer(
            key: ValueKey<String>(
              'storyboard-$_keyName-press-${trackId.value}',
            ),
            row: _address,
            cellExtent: timelineScale.pixelsPerFrame,
            frameAt: (local) => timelineScale.pixelsPerFrame <= 0
                ? null
                : timelineScale.frameAt(local.dx),
            onRowFramePress: onRowFramePress,
            onPressAt: _pressed,
            onEdit: onEdit,
          ),
        ...over,
      ],
    ),
  );

  /// The row's ground ([StoryboardCameraRowPainter]) — each cut's のりしろ
  /// and the stretches two cuts share — painted, never pressed.
  Widget _ground(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          key: ValueKey<String>(
            'storyboard-$_keyName-ground-${trackId.value}',
          ),
          painter: StoryboardCameraRowPainter(
            reaches: reaches,
            geometry: frameGeometry,
            crossAxisExtent: height,
            colorScheme: Theme.of(context).colorScheme,
            windowBucket: windowBucket,
          ),
        ),
      ),
    ),
  );

  /// THE range gesture — the timeline's, as the conte row lays it — over
  /// both halves of the row, writing [sweeps]: the row's cells, or a lane's
  /// keys.
  List<Widget> _gestureSlots(_ProjectionSweeps sweeps) => [
    _gestureSlot(_rangeGesture(sweeps, upper: true), upper: true),
    _gestureSlot(_rangeGesture(sweeps, upper: false), upper: false),
  ];

  /// [upper]'s half of the range gesture on [sweeps] — a sweep held to the
  /// cut it began in, because a cut's own index names no frame of another
  /// ([CameraRowReach.ownFrameAt]). The pointer's reach across rows is
  /// measured from the row's top, which the lower half sits under by half
  /// a row.
  TimelineRangeGestureCallbacks _rangeGesture(
    _ProjectionSweeps sweeps, {
    required bool upper,
  }) => TimelineRangeGestureCallbacks(
    isInSelection: (_, frame) {
      final at = _layerAt(frame, upper: upper);
      return at != null && sweeps.holds(at.layer, at.reach.ownFrameAt(frame));
    },
    onSelectUpdate: (_, anchorIndex, headIndex, headCrossOffset) {
      final at = _layerAt(anchorIndex, upper: upper);
      if (at == null) {
        return;
      }
      sweeps.select(
        at.layer,
        at.reach.ownFrameAt(anchorIndex),
        at.reach.ownFrameAt(headIndex),
        headCrossOffset + (upper ? 0 : height / 2),
      );
    },
    onTapClear: (_) => sweeps.clear(),
    onMoveBegin: (_, frame) {
      final at = _layerAt(frame, upper: upper);
      return at != null && sweeps.beginMove(at.layer);
    },
    // A cut holds one layer a row shows, and a lane's keys move along it:
    // there is nowhere sideways to land.
    onMoveUpdate: (frameDelta, _) => sweeps.moveBy(frameDelta),
    onMoveEnd: sweeps.endMove,
    onMoveCancel: sweeps.cancelMove,
  );

  /// [upper]'s half of the row, answering only where a cut's own frames
  /// reach on that line ([_reachAt]), as the conte row's answers only on
  /// panels. Each half says which cut its press means where two cuts' own
  /// frames run at once, so the row takes it in two.
  Widget _gestureSlot(
    TimelineRangeGestureCallbacks callbacks, {
    required bool upper,
  }) => Positioned(
    key: ValueKey<String>(
      'storyboard-$_keyName-gesture-${upper ? 'upper' : 'lower'}-'
      '${trackId.value}',
    ),
    left: 0,
    right: 0,
    top: upper ? 0 : height / 2,
    height: height / 2,
    child: HitGate(
      admits: (position) =>
          _layerAt(_frameAtX(position.dx), upper: upper) != null,
      child: Stack(
        children: [
          TimelineFrameRangeGestureLayer(
            row: _address,
            geometry: frameGeometry,
            crossAxisExtent: height / 2,
            callbacks: callbacks,
          ),
        ],
      ),
    ),
  );

  /// Every cut's keys and the line between them, inside the panel's window
  /// — re-made when the window crosses a bucket, laid out on the live axis
  /// in between, as the V row's blocks are painted. A key [selection] holds
  /// is ringed.
  Widget _keys({TimelineLaneSelection? selection}) =>
      ValueListenableBuilder<int>(
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
            key: ValueKey<String>(
              'storyboard-$_keyName-keys-${trackId.value}',
            ),
            geometry: frameGeometry,
            crossAxisExtent: height,
            axis: Axis.horizontal,
            children: [
              for (final reach in reaches)
                if (reach.mediaEnd > window.startIndex &&
                    reach.mediaStart < window.endIndexExclusive)
                  ..._cutKeys(reach, window, selection),
            ],
          );
        },
      );

  /// [reach]'s cut's keys inside its own frames and [window]: the line
  /// between its first and its last, the moves over it, then the marks
  /// over them.
  List<Widget> _cutKeys(
    CameraRowReach reach,
    ({int startIndex, int endIndexExclusive}) window,
    TimelineLaneSelection? selection,
  ) {
    final cut = reach.entry.cut;
    final layer = _layerOf(cut);
    final lane = layer == null ? null : _laneOf(cut, layer);
    if (layer == null || lane == null) {
      return const [];
    }
    final line = _line(reach, layer, lane, window);
    return [
      ?line,
      for (final stretch in lane.stretchWords)
        if (_stretchOnTheLine(reach, stretch, window) case final placed?)
          timelineStretchWordSpan(
            keyPrefix: _markPrefix,
            layer: layer,
            stretch: placed,
            axis: Axis.horizontal,
          ),
      for (final key in lane.keyedFrames.toList()..sort())
        if (reach.reaches(reach.trackFrameOf(key)) &&
            reach.trackFrameOf(key) >= window.startIndex &&
            reach.trackFrameOf(key) < window.endIndexExclusive)
          _key(reach, layer, lane, (
            frame: key,
            selected:
                selection != null &&
                laneSelectionCoversBandRow(selection, layer.id, lane.laneId) &&
                selection.contains(key),
          )),
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
    return (from: from, to: to, word: stretch.word);
  }

  /// One [key]'s mark — ringed while its lane selection holds it — on the
  /// line its cut is drawn on there.
  Widget _key(
    CameraRowReach reach,
    Layer layer,
    PropertyLaneRow lane,
    ({int frame, bool selected}) key,
  ) {
    final at = reach.trackFrameOf(key.frame);
    final line = reach.lineAt(at);
    return timelineLaneKeySpan(
      keyPrefix: _markPrefix,
      layer: layer,
      lane: lane,
      frame: key.frame,
      // The storyboard lays its track across, as its rows' spans do.
      axis: Axis.horizontal,
      at: at,
      crossExtent: height * _markBand(line),
      crossInset: switch (line) {
        CameraRowLine.middle => null,
        CameraRowLine.upper => 0,
        CameraRowLine.lower => height * (1 - _cameraRowLineBand),
      },
      // 「키 이름은 한 줄일 때만」 — two lines leave no room for a word.
      named: line == CameraRowLine.middle,
      selected: key.selected,
    );
  }

  /// How much of the row across the band a key mark stands in on [line]
  /// takes: all of it on the one line in the middle, the line's own band
  /// on either of the two.
  double _markBand(CameraRowLine line) =>
      line == CameraRowLine.middle ? 1 : _cameraRowLineBand;

  /// The line between [reach]'s cut's first key and its last, clamped to
  /// the end of its own frames, stepping where its cut changes lines — or
  /// null while it has no two keys there to join. Its own frames begin at
  /// its frame 0, before every key.
  Widget? _line(
    CameraRowReach reach,
    Layer layer,
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
      key: ValueKey<String>('storyboard-$_keyName-line-span-${layer.id}'),
      placement: TimelineFrameSpanPlacement(
        startIndex: from,
        endIndexExclusive: to + 1,
      ),
      child: TimelineLaneKeysLine(
        key: ValueKey<String>('storyboard-$_keyName-line-${layer.id}'),
        axis: Axis.horizontal,
        cells: to + 1 - from,
        layer: layer,
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
        // The cut's marks on it — none past the cut's own end, where no
        // mark is drawn — each in the band of the line the cut is drawn on
        // there.
        rings: [
          for (final key in timelineHollowKeyFrames(lane))
            if (reach.trackFrameOf(key) case final at when at <= to)
              (cell: at - from, band: _markBand(reach.lineAt(at))),
        ],
      ),
    );
  }
}

/// ONE LANE OF A PROJECTION ROW, twirled down under it (I-73 ④ⓔ) — the
/// camera row's: each cut's [laneId] lane of the layer the row shows of it
/// ([projection]), over the cut's own frames, drawn as the row draws its
/// keys ([_StoryboardProjectionKeys]).
///
/// It is stood on by the lane's address on this rail ([LaneRowAddress] of
/// the row's id), which the session reads as that lane of the layer the row has
/// in hand in the cut it stands in. A sweep selects the lane's keys of the
/// cut it begins in, on that layer, in the cut's own frames — held to the
/// cut ([CameraRowReach.ownFrameAt]) — and a sweep from inside the
/// selection moves them, through the timeline's own lane selection and
/// lane move ([laneRange]).
class _StoryboardProjectionLaneRow extends StatelessWidget
    with _StoryboardProjectionKeys {
  const _StoryboardProjectionLaneRow({
    required this.trackId,
    required this.projection,
    required this.laneId,
    required this.reaches,
    required this.width,
    required this.height,
    required this.timelineScale,
    required this.frameGeometry,
    required this.windowBucket,
    required this.viewportWidth,
    this.onRowFramePress,
    this.onCameraCutPress,
    this.laneRange,
  });

  @override
  final TrackId trackId;

  /// The projection row whose lane this is.
  final _ProjectionLanes projection;

  /// The lane of the cuts' layers this row draws.
  final String laneId;

  @override
  final List<CameraRowReach> reaches;
  @override
  final double width;
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
  @override
  final StoryboardRowFramePress? onRowFramePress;
  @override
  final StoryboardCameraCutPress? onCameraCutPress;

  /// The timeline's lane selection and lane move, as this rail hands them
  /// to every lane it draws — its double click the lane's own too (a key
  /// opens, an empty cell is keyed). Null keeps the row display-only.
  final TimelineLaneRangeCallbacks? laneRange;

  @override
  TimelineRowAddress get _address => LaneRowAddress(projection.rowId, laneId);

  @override
  String get _keyName => '${projection.keyName}-lane-$laneId';

  @override
  String get _markPrefix => projection.markPrefix;

  @override
  Layer? _layerOf(Cut cut) => projection.layerOf(cut);

  @override
  RailEye _eyeOf(Cut cut, Layer layer) => projection.eyeOf(cut, layer);

  @override
  PropertyLaneRow? _laneOf(Cut cut, Layer layer) {
    for (final lane in projection.lanesOf(cut, layer)) {
      if (lane.laneId == laneId) {
        return lane;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final lanes = laneRange;
    final activate = lanes?.onActivateAt;
    return _strip(
      context,
      keys: lanes == null
          ? _keys()
          : ValueListenableBuilder<TimelineLaneSelection?>(
              valueListenable: lanes.selection,
              builder: (context, selection, _) => _keys(selection: selection),
            ),
      // The first click stood on the lane of the cut it landed in, so the
      // lane's own double click answers there.
      onEdit: activate == null
          ? null
          : (frame) => activate(projection.rowId, laneId, frame),
      over: [
        if (lanes != null) ..._gestureSlots(_keysOf(lanes)),
      ],
    );
  }

  /// The LANE selection a sweep here writes: this lane's keys of the layer
  /// the sweep began on, in its cut's own frames — the timeline's lane
  /// selection and lane move, as every lane this rail draws hands them on.
  _ProjectionSweeps _keysOf(TimelineLaneRangeCallbacks lanes) => (
    holds: (layer, ownFrame) {
      final selection = lanes.selection.value;
      return selection != null &&
          laneSelectionCoversBandRow(selection, layer, laneId) &&
          selection.contains(ownFrame);
    },
    select: (layer, anchor, head, headCrossOffset) =>
        lanes.onSelectUpdate(layer, laneId, anchor, head, headCrossOffset),
    clear: lanes.onTapClear,
    beginMove: (_) => lanes.onMoveBegin(),
    moveBy: lanes.onMoveUpdate,
    endMove: lanes.onMoveEnd,
    cancelMove: lanes.onMoveCancel,
  );
}

/// The selection a projection row's sweep writes
/// ([_StoryboardProjectionKeys._gestureSlots]) — the row's cells, or a
/// lane's keys — told the layer the sweep began on and the frames of its
/// cut's own: whether it holds one, a select from an anchor to a head (and
/// how far across the rows the pointer has gone), a let-go, and a move of
/// what it holds.
typedef _ProjectionSweeps = ({
  bool Function(LayerId layer, int ownFrame) holds,
  void Function(LayerId layer, int anchor, int head, double headCrossOffset)
  select,
  VoidCallback clear,
  bool Function(LayerId layer) beginMove,
  ValueChanged<int> moveBy,
  VoidCallback endMove,
  VoidCallback cancelMove,
});

/// WHAT A PROJECTION ROW'S LANES ARE DRAWN FROM (I-73 ④ⓔ): the row
/// ([trackCameraRowId]), the word its parts are keyed by, the word its key
/// marks are, the layer it shows of a cut ([projectedRowOf]), and that
/// layer's lanes there — every one of them, whatever the twirls: a lane row
/// finds its own among them by id, in every cut — valued in that cut, the
/// line a header graph draws of it there (I-89 ①) — and the eye that
/// layer wears on the row ([_StoryboardProjectionKeys._eyeOf]).
typedef _ProjectionLanes = ({
  LayerId rowId,
  String keyName,
  String markPrefix,
  Layer? Function(Cut cut) layerOf,
  List<PropertyLaneRow> Function(Cut cut, Layer layer) lanesOf,
  RailEye Function(Cut cut, Layer layer) eyeOf,
});

/// [layer]'s eye as its own [cut]'s folders gate it — the timeline rail's
/// answer for it there ([railEyesOf]).
RailEye _cutsOwnEye(Cut cut, Layer layer) =>
    railEyesOf([layer], stack: cut.layers)[layer.id]!;
