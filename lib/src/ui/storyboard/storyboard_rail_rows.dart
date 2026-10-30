part of '../storyboard_panel.dart';

/// A twirl as the rail draws it: the row it turns — a layer, or the V row's
/// lane carrier — and whether this build reads it open.
typedef _Twirl = ({LayerId id, bool open});

/// A row of the rail as a pointer counts it
/// ([_StoryboardRailRows._pointerTable]): the address it is stood on by,
/// the address of the row the timeline's rail holds for it
/// ([_StoryboardRailSlot.display]), and its track.
typedef _PointerRow = ({
  TimelineRowAddress? standing,
  TimelineRowAddress? held,
  TrackId track,
});

/// Every lane the rail draws, every track's, as the timeline's rows hold it
/// (I-89 ①): the [lanes] as they are, the [rows] they make seated in their
/// groups' open header graphs ([seatLaneGraphs]), where those sit — each
/// at its extent, an open graph's room after its last lane
/// ([timelineRowEdgesOf]) — and which of them each lane is [at]. The
/// timeline's own seating on this rail's lanes: an ENLARGED graph folds
/// every other lane of the rail, every track's — the panel is what it is
/// enlarged over.
typedef _LaneSeating = ({
  List<TimelineDisplayRow> lanes,
  List<TimelineDisplayRow> rows,
  TimelineRowEdges edges,
  Map<TimelineRowAddress, int> at,
});

/// One lane as the table lays it ([_StoryboardRailRows._seatedLane]): its
/// [index] among the lanes, its [row] — seated in the open graph that draws
/// it, folded where the enlarged one says — its [extent], and the [room] an
/// open graph stands past it.
typedef _SeatedLane = ({
  int index,
  TimelineDisplayRow row,
  double extent,
  double room,
});

/// How [_StoryboardRailRows._laneFrameSide] draws a carrier's lanes: each
/// lane's [strip] at its extent — and, in an open graph, each lane as the
/// lines [linesOf] reads its row as now (a projection row's, one a cut),
/// their handles written through [laneEdit] and their keys picked and
/// carried by [laneRange], the lane selection the strips take (I-3).
typedef _LanesDrawn = ({
  PropertyLaneEditCallbacks? laneEdit,
  TimelineLaneRangeCallbacks? laneRange,
  Iterable<LaneGraphLine> Function(TimelineDisplayRow row) linesOf,
  Widget Function(TimelineDisplayRow row, double height) strip,
});

/// What a lane row of this rail keys and sets its lane with — the [edit]
/// its label calls — and the [cursor] naming the frame it stands on
/// ([_StoryboardRailRows._laneHandOf]).
typedef _LaneHand = ({
  PropertyLaneEditCallbacks? edit,
  ValueListenable<int?>? cursor,
});

/// THE RAIL'S ROWS AND LANES — the rows the storyboard's rail shows for
/// a track and its SE rows, in display order, filtered; their extents,
/// sections and geometry; the subject and row at a rail position; the
/// swipe columns the rail sweeps; and the lanes those rows carry — own,
/// effect and transform lanes, their labels, strips, twirls, range band
/// and gestures — as their own object.
///
/// 🚨A collaborator carved out of `_StoryboardPanelState` (the audit's SRP
/// cut, 2026-09-02). Measured first as two families — the rows read the
/// lanes in twenty-four places and the lanes read the rows back, so
/// they are one. It reaches the State through `_state` and rebuilds
/// through `_rebuild`.
class _StoryboardRailRows {
  _StoryboardRailRows(this._state);

  final _StoryboardPanelState _state;

  LayerRailExtent get _railExtent =>
      _state.widget.railExtent ??
      (_state._ownedRailExtent ??= LayerRailExtent());

  /// One V track's EFFECT lanes, below its Transform group — the same rows a
  /// layer's chain gets, one level up: this chain filters the whole
  /// composited cut (user 2026-08-08). Values resolve at GLOBAL frames, the
  /// axis the keys live on. Its groups open as the track keeps them, by
  /// lane id as a layer row keeps its own (F-360, `Track.expandedLaneGroups`).
  List<PropertyLaneRow> _trackEffectLanes(Track track) {
    if (track.effects.isEmpty) {
      return const [];
    }
    return effectPropertyLanes(
      track.effects,
      // A track's chain is no cut's: it names no row.
      cutRows: const [],
      isExpanded: (effectId) =>
          track.expandedLaneGroups.contains(effectGroupLaneId(effectId)),
      valueAt: (effectId, parameterId, time) => effectParameterValueAtTime(
        track.effects,
        effectId,
        parameterId,
        time,
      ),
    );
  }

  /// The layer the V row's own lanes are worn by on this rail — its lane
  /// carrier ([trackTransformLaneCarrierId]) — by its labels, its strips
  /// and the graphs over them alike.
  static Layer _trackLaneCarrier(Track track) => Layer(
    id: trackTransformLaneCarrierId(track.id),
    name: 'V',
    frames: const [],
  );

  /// The V row's OWN lanes — its Transform group when it has one, then its
  /// EFFECT chain.
  ///
  /// The rail ASKS [timelineRowOwnsTransform] rather than deciding: a track row
  /// answers no since the teardown, so the pose lanes and the fade's Opacity
  /// lane are simply absent, and giving another row the same answer is one case
  /// in that policy instead of an edit here.
  List<PropertyLaneRow> _trackOwnLanes(Track track) {
    return [
      if (timelineRowOwnsTransform(subject: TimelineTransformSubject.track))
        transformGroupHeader(
          expanded: track.expandedLaneGroups.contains(
            transformGroupHeaderLane.laneId,
          ),
        ),
      ..._trackEffectLanes(track),
    ];
  }

  /// One S row's lanes: THE list an SE row twirls down ([propertyLanesForRow],
  /// F-101), read on this track's rail — the row itself at the rail's global
  /// frame (the same raw-track resolution the timeline's value column uses —
  /// fx bypass never touches authoring values), an unkeyed pose in the middle
  /// of the camera frame. No cut is consulted: the row belongs to the track.
  ///
  /// C5 (2026-08-17) holds by construction: the list is the timeline's lane
  /// law's own, so an S row twirls down exactly the lanes its timeline twin
  /// draws. ↩️The storyboard once mounted the Audio lane off the twirl alone,
  /// and an empty S row showed a waveform strip its twin never drew.
  List<PropertyLaneRow> _seLanes(Track track, int slot) {
    final layer = _trackSeAt(track, slot);
    return layer == null ? const [] : _seLanesOf(track, layer);
  }

  /// [_seLanes] read off [layer] — the S row as committed, or as a lane edit
  /// in flight shows it (its labels re-derive through here, F-195) — its
  /// groups open as the rows keep them, or as [expandedGroupKeys] says.
  List<PropertyLaneRow> _seLanesOf(
    Track track,
    Layer layer, {
    Set<String>? expandedGroupKeys,
  }) {
    return propertyLanesForRow(
      layer: layer,
      rows: track.seLayers,
      expandedGroupKeys:
          expandedGroupKeys ?? _state.widget.expandedLaneGroupKeys,
      valueSourceAt: (frameIndex) => (layer: layer, frame: frameIndex),
      // The display size comes from the SESSION, exactly as the V row's
      // lanes take it — never from "the cut that happens to be open", which
      // made another track's S row show its values as defaults.
      poseCentre: _state.widget.poseDisplaySize,
    );
  }

  /// ㉒ (user, 2026-08-12): the legend's twirl-all — the one control the
  /// storyboard's legend was missing, because the header only draws it when
  /// a host hands it BOTH verbs and this host handed it neither.
  ///
  /// The rows have always twirled; what was absent was the bulk verb over
  /// them. So this is the timeline's [expandAllLanes] transposed onto the
  /// rows THIS rail draws — an S row per SE slot, a V row per track, and
  /// the camera row a track (I-73 ④ⓔ) — rather than a new idea about
  /// expansion.
  bool get _anyLanesExpanded => _state.widget.project.tracks.any(
    (track) =>
        _ownTwirlsOf(track).any((twirl) => twirl.open) ||
        _cameraLanesOpen(track) ||
        _shownConteSeats(track).any((seat) => _conteLanesOpen(track, seat)),
  );

  /// Whether the rail can twirl at all: a display-only mount (no hooks) has
  /// nothing for the legend button to act on, so it does not draw one.
  bool get hasLaneTwirls => _state.widget.onToggleLayerLanes != null;

  void expandAllLanes() => _setAllLanes(expanded: true);

  void collapseAllLanes() => _setAllLanes(expanded: false);

  /// Toggles every lane row that is not already [expanded].
  ///
  /// ⛔THE GUARD IS THE VERB. It looks redundant — the button only says
  /// EXPAND while nothing is open — but it is what makes this an expansion
  /// rather than a per-row toggle, and the nested group set can leave a
  /// rail mixed: a blind sweep would close the one row you had opened by
  /// hand while it opened its neighbours. Written once per direction, the
  /// two guards were the same sentence with the sense flipped, and only one
  /// of them could be right about it.
  ///
  /// ONE undo step for the press, as the timeline's
  /// ([RailSweepHistory.asOneStep]): a twirl the rows carry is written
  /// through history (F-360).
  void _setAllLanes({required bool expanded}) {
    final toggle = _state.widget.onToggleLayerLanes;
    if (toggle == null) {
      return;
    }
    RailSweepHistory.asOneStep(
      _state.context,
      expanded ? 'Expand all lanes' : 'Collapse all lanes',
      () {
        for (final track in _state.widget.project.tracks) {
          _setTrackLanes(track, toggle, expanded: expanded);
        }
      },
    );
  }

  /// [track]'s rows' twirls turned to [expanded] — its own rows'
  /// ([_ownTwirlsOf]) and its projection rows' (I-73 ④ⓔ): the camera
  /// row's, and each conte row's that has lanes to show, each through the
  /// layer its twirl turns ([_cameraTwirlOf], [_conteTwirlOf]).
  void _setTrackLanes(
    Track track,
    ValueChanged<LayerId> toggle, {
    required bool expanded,
  }) {
    for (final twirl in [
      ..._ownTwirlsOf(track),
      if (_cameraTwirlOf(track) case final camera?)
        (id: camera, open: _cameraLanesOpen(track)),
      for (final seat in _shownConteSeats(track))
        if (_conteTwirlOf(track, seat) case final row?
            when _conteLanes(track, seat).isNotEmpty)
          (id: row, open: _conteLanesOpen(track, seat)),
    ]) {
      if (_openNow(twirl) != expanded) {
        toggle(twirl.id);
      }
    }
  }

  /// [track]'s OWN rows' twirls — an S row's per slot, the V row's — each
  /// the row's (F-360): the S row's its SE row's, the timeline's row too
  /// (F-101), the V row's its track's.
  List<_Twirl> _ownTwirlsOf(Track track) => [
    for (var slot = 0; slot < _seSlotCount(track); slot += 1)
      ?_seTwirlOf(track, slot),
    ?_trackTwirlOf(track),
  ];

  /// The twirl [track]'s S row at [slot] draws — null while the slot holds
  /// no row, or its row no lanes.
  _Twirl? _seTwirlOf(Track track, int slot) {
    final row = _trackSeAt(track, slot);
    return row == null || _seLanes(track, slot).isEmpty
        ? null
        : (id: row.id, open: _seLanesOpen(track, slot));
  }

  /// The twirl [track]'s V row draws, by the row's lane carrier — null
  /// while the track owns no lanes.
  _Twirl? _trackTwirlOf(Track track) => _trackOwnLanes(track).isEmpty
      ? null
      : (id: trackTransformLaneCarrierId(track.id), open: track.lanesExpanded);

  /// Whether [track]'s S row at [slot] has its lanes twirled down: its SE
  /// row's own twirl, read as the timeline's SE row reads it.
  bool _seLanesOpen(Track track, int slot) => switch (_trackSeAt(track, slot)) {
    final row? => _state.widget.expandedLaneLayerIds.contains(row.id),
    null => false,
  };

  /// Whether [twirl] is open RIGHT NOW: read live where the host can
  /// ([StoryboardPanel.layerLanesOpenOf]) — the twirl-all turns row after
  /// row as one step, and a press spread across the selection may already
  /// have turned the next — else as this build reads it.
  bool _openNow(_Twirl twirl) =>
      _state.widget.layerLanesOpenOf?.call(twirl.id) ?? twirl.open;

  /// The S row, made draggable — the rail's row-order drag, on the third
  /// surface.
  ///
  /// Only the track holding the ACTIVE CUT offers it: the session commits
  /// an S move against the selected track's list, and another track's rows
  /// would write to the wrong one. An empty slot has nothing to move.
  ///
  /// The pitch is this row's OWN GROUP — the S row plus its lanes when
  /// twirled open (R5 ③b-5). `_seRowHeight` alone was the pitch only while
  /// nothing was open, and one open row made the drag count slots faster
  /// than the pointer crossed rows. The caret still showed the truth, so
  /// this was never a wrong commit — only a drag that moved at the wrong
  /// rate under the hand.
  ///
  /// ⚠️Rows of DIFFERING heights still drift after the first step: the
  /// shared drag widget takes one extent, not a list. The V rows have the
  /// same limitation for the same reason, and one per-row extent list
  /// would close both.
  /// The track's S rows in the order the RAIL draws them — top-down from the
  /// highest slot, so slot 0 sits just above the V row.
  ///
  /// ⚠️Track-owned rows, so the GLOBAL layers — never the display clones a
  /// move would refuse to commit to. Two things read this now (the frame
  /// area's move drag and A5-3②'s row selection) and they must walk the rows
  /// in the same order or a span and a slide would disagree about which row
  /// the pointer just crossed.
  List<TimelineDisplayRow> _seRowsInDisplayOrder(Track track) => [
    for (final slot in _shownSeSlots(track))
      if (_trackSeAt(track, slot) case final layer?)
        TimelineDisplayRow.layer(layer, layerIndex: slot),
  ];

  /// The rows a band's move on [track]'s S rows walks: [_seRowsInDisplayOrder]
  /// with the lanes the rail draws under each — a lane lands its band on its
  /// own S row ([resolveBlockMoveTargetLayer]), so the walk still crosses no
  /// row whose blocks are not sounds.
  ///
  /// 🚨H20: a band pressed on a LANE counts its row steps from that lane, as
  /// the timeline's does, so the lanes are rows of the walk. The S row a band
  /// is pressed on counts them too: they are rows the pointer crosses.
  List<TimelineDisplayRow> _seMoveRows(Track track) {
    final seIds = {
      for (final row in _seRowsInDisplayOrder(track)) row.layer.id,
    };
    return [
      for (final slot in _trackGroupRowGeometry(track))
        if (slot.display case final row? when seIds.contains(row.layer.id))
          row,
    ];
  }

  /// The S slots the rail SHOWS for [track], top slot first — the order the
  /// rail draws them (slot 0 sits just above the V row) — with the legend's
  /// filter applied ([_filterAllowsSeRow]).
  ///
  /// 🚨ONE LIST for everything that lays an S row out: the rail's labels, the
  /// strips beside them, and the one row table the bands, the sheet, the
  /// select-drag, the ring and the swipe read. The filter once reached the
  /// labels alone, so every row under a hidden one parted from its strip by
  /// a row (storyboard-filter-leaves-the-strips, measured 94 over 124).
  List<int> _shownSeSlots(Track track) => [
    if (_sectionShown(TimelineSection.se))
      for (var slot = _seSlotCount(track) - 1; slot >= 0; slot -= 1)
        if (_filterAllowsSeRow(track, slot)) slot,
  ];

  /// Whether the rail shows [section] — the set the timeline's grids read
  /// (F-199: 「콘티패널도 타임라인이랑 동일하게 se나 카메라섹션 접을수있게
  /// 로직통일」). The V row belongs to no section and always shows.
  bool _sectionShown(TimelineSection section) =>
      !_state.widget.hiddenSections.contains(section);

  /// Whether the rail shows [track]'s transition row: its section is the one
  /// the timeline puts that row's kind in — the camera section — and the
  /// legend's filter judges it as every row ([_filterAllowsProjectionRow]).
  /// ↩️F-408: it asked the section alone, so a solo left it standing where
  /// the timeline's transition row, a layer row, went.
  ///
  /// ⚠️ONE question for the three places that lay the row out — the row
  /// table, the rail's labels and the strips — or a hidden row would part a
  /// label from its strip by a row, the filter's lesson below.
  bool _showsTransitionRow(Track track) =>
      _sectionShown(timelineSectionForLayerKind(track.transitionLayer.kind)) &&
      _filterAllowsProjectionRow(
        LayerRowAddress(track.transitionLayer.id),
        head: track.transitionLayer,
        kind: track.transitionLayer.kind,
      );

  /// Whether the rail shows [track]'s CAMERA row (I-73 ④): its section is
  /// the one the timeline puts the kind in — the camera section, whose top
  /// row it is — and the legend's filter judges it as every row
  /// ([_filterAllowsCameraRow]).
  ///
  /// ⚠️ONE question for the three places that lay the row out — the row
  /// table, the rail's labels and the strips — as [_showsTransitionRow] is.
  bool _showsCameraRow(Track track) =>
      _sectionShown(timelineSectionForLayerKind(LayerKind.camera)) &&
      _filterAllowsCameraRow(track);

  /// The camera row's HEAD on [track]: the camera layer of the cut the
  /// session stands in, when that cut is on this track — the row the
  /// timeline shows at the top of its CAM section, so the two panels' camera
  /// rows are one row (「카메라는 로컬이랑 똑같이 최상단행」). Null in a gap,
  /// and on every other track.
  Layer? _cameraHeadOf(Track track) => _cameraHeadAt(track)?.layer;

  /// [_cameraHeadOf] with the cut it is the camera of: the camera row's
  /// row in hand while it is the stood cut's own ([_stoodInHand]).
  ({Cut cut, Layer layer})? _cameraHeadAt(Track track) =>
      _stoodInHand(track, LayerRowAddress(trackCameraRowId(track.id)));

  /// [track]'s projection row [row] IN HAND ([projectionRowInHandOn]) — the
  /// layer the rail wears for it and its lanes are drawn from — and whether
  /// it is the row of the cut the session stands in ([stood]): only there
  /// are its lanes valued, edited and followed. Null while no cut holds a
  /// row there.
  ({Cut cut, Layer layer, bool stood})? _inHand(
    Track track,
    TimelineRowAddress row,
  ) {
    final activeCutId = _state.widget.activeCutId;
    final inHand = projectionRowInHandOn(
      track.cuts,
      row,
      standingIn: activeCutId,
    );
    return inHand == null
        ? null
        : (
            cut: inHand.cut,
            layer: inHand.row,
            stood: inHand.cut.id == activeCutId,
          );
  }

  /// [_inHand] while it is the stood cut's own row; null otherwise.
  ({Cut cut, Layer layer})? _stoodInHand(
    Track track,
    TimelineRowAddress row,
  ) => switch (_inHand(track, row)) {
    (:final cut, :final layer, stood: true) => (cut: cut, layer: layer),
    _ => null,
  };

  /// Whether [track]'s camera row has its lanes twirled down (I-73 ④ⓔ):
  /// whether a camera of its cuts has — a track's cameras twirl as one,
  /// their head being one (I-73-camera-row-Q1, and F-302's law for the rows
  /// that wear one head), so the row stays open across a gap, where no
  /// head is there to ask.
  bool _cameraLanesOpen(Track track) {
    final open = _state.widget.expandedLaneLayerIds;
    return open.isNotEmpty &&
        cameraHeadFamilyOf(track.cuts).any(open.contains);
  }

  /// The camera [track]'s camera row's twirl turns — its cameras turn as
  /// one ([_cameraLanesOpen]): an open one while the row is open, so the
  /// turn shuts them all, else the head's, else the track's first.
  LayerId? _cameraTwirlOf(Track track) {
    final cameras = cameraHeadFamilyOf(track.cuts);
    final open = _state.widget.expandedLaneLayerIds;
    return cameras.where(open.contains).firstOrNull ??
        _cameraHeadOf(track)?.id ??
        cameras.firstOrNull;
  }

  /// The lanes [track]'s camera row twirls down: the timeline's camera
  /// lanes ([cameraPropertyLanes]) of its camera in hand ([_inHand]),
  /// valued in the cut the session stands in — or, in a gap, the same lanes
  /// of the track's first camera, with nothing to read their values in.
  List<PropertyLaneRow> _cameraLanes(Track track) =>
      switch (_inHand(track, LayerRowAddress(trackCameraRowId(track.id)))) {
        (:final cut, :final layer, :final stood) => cameraPropertyLanes(
          layer,
          cut.camera.track,
          canvasSize: stood ? cut.canvasSize : null,
        ),
        null => const [],
      };

  /// Whether [track]'s conte row at [seat] has its lanes twirled down
  /// (I-73 ④ⓔ): whether a row at its seat has — the rows that wear one head
  /// twirl as one, the twirl's command writing it on every one of them
  /// (F-360, `headMirrorTargets`).
  bool _conteLanesOpen(Track track, int seat) {
    final open = _state.widget.expandedLaneLayerIds;
    return open.isNotEmpty &&
        conteHeadFamilyAt(track.cuts, seat).any(open.contains);
  }

  /// The row the conte row at [seat]'s twirl turns — the rows at its seat
  /// turn as one ([_conteLanesOpen]): an open one while the row is open, so
  /// the turn shuts them all, else the head's.
  LayerId? _conteTwirlOf(Track track, int seat) {
    final rows = conteHeadFamilyAt(track.cuts, seat);
    final open = _state.widget.expandedLaneLayerIds;
    return rows.where(open.contains).firstOrNull ?? rows.firstOrNull;
  }

  /// [rowId]'s group fold: a conte row's is THE TIMELINE ROW'S answer for
  /// the layer it has in hand ([timelineGroupFoldFor]) — a 공정 folder
  /// folds the rows it files, the conte the rows riding it — and no other
  /// row of this rail folds. ONE answer for the row's label and the column
  /// sweep that paints it (F-475).
  ///
  /// ↩️The label and the sweep each asked 「the conte's seat, with rows
  /// over or under it」 — the attach half alone, twice, and no folder
  /// ([conteGroupOf], I-99).
  ///
  /// The host's verb is the one chevron (I-32) — a folder's fold or a
  /// base's group — so both halves press it.
  TimelineGroupFold _conteGroupFoldOf(LayerId rowId) {
    final inHand = trackIdOfConteRow(rowId) == null
        ? null
        : _rowInHand(rowId);
    if (inHand == null) {
      return (has: false, expanded: true, onToggle: null);
    }
    final layers = inHand.cut.layers;
    final toggle = _state.widget.onToggleAttachGroup;
    return timelineGroupFoldFor(
      row: TimelineDisplayRow.layer(
        inHand.layer,
        layerIndex: layers.indexOf(inHand.layer),
      ),
      layers: layers,
      collapsedAttachBaseIds: _state.widget.collapsedAttachBaseIds,
      onToggleLayerCollapsed: toggle,
      onToggleAttachGroup: toggle,
    );
  }

  /// [row]'s lanes in [cut] — THE list its timeline row twirls down
  /// ([propertyLanesForRow]), with its groups twirled as the timeline's
  /// are; [valued] reads them at a frame of the cut's own.
  List<PropertyLaneRow> _conteRowLanes(
    Cut cut,
    Layer row, {
    required bool valued,
  }) => propertyLanesForRow(
    layer: row,
    rows: cut.layers,
    expandedGroupKeys: _state.widget.expandedLaneGroupKeys,
    valueSourceAt: valued ? (frame) => (layer: row, frame: frame) : null,
    poseCentre: valued ? cut.canvasSize : null,
  );

  /// The lanes [track]'s conte row at [seat] twirls down: those of its row
  /// in hand ([_inHand]) — valued in the cut the session stands in, or,
  /// where that cut holds none, the head's, with nothing to read their
  /// values in — the timeline's lanes of the row, a rider's own (I-99).
  List<PropertyLaneRow> _conteLanes(Track track, int seat) =>
      switch (_inHand(track, _conteRow(track, seat))) {
        (:final cut, :final layer, :final stood) => _conteRowLanes(
          cut,
          layer,
          valued: stood,
        ),
        null => const [],
      };

  static LayerRowAddress _conteRow(Track track, int seat) =>
      LayerRowAddress(trackConteRowId(track.id, seat: seat));

  /// [track]'s conte row at [seat] as its lanes are drawn from (I-73 ④ⓔ):
  /// each cut's row at that seat, and every lane of it — each groups'
  /// members whatever the twirls, so the row for a lane finds it in every
  /// cut — valued in that cut, which a header graph draws its line of
  /// (I-89 ①).
  _ProjectionLanes _conteProjection(Track track, int seat) {
    final keyName = _StoryboardRowsAndLabels.conteLabelKeyName(seat);
    // The row's blocks wear its head's eye in every cut (I-129), and so do
    // its keys.
    final headEye = _conteHeadEye(track.cuts, seat);
    return (
      rowId: trackConteRowId(track.id, seat: seat),
      keyName: keyName,
      markPrefix: 'storyboard-$keyName',
      layerOf: (cut) => conteRowAtSeat(cut, seat),
      lanesOf: (cut, row) => propertyLanesForRow(
        layer: row,
        rows: cut.layers,
        expandedGroupKeys: {
          laneGroupKey(row.id, transformGroupHeaderLane.laneId),
          for (final effect in row.effects)
            laneGroupKey(row.id, effectGroupLaneId(effect.id)),
        },
        valueSourceAt: (frame) => (layer: row, frame: frame),
        poseCentre: cut.canvasSize,
      ),
      eyeOf: (cut, row) => headEye ?? _cutsOwnEye(cut, row),
    );
  }

  /// Whether the legend's filter lets the camera row show
  /// ([_filterAllowsProjectionRow]) — with no head in a gap.
  bool _filterAllowsCameraRow(Track track) => _filterAllowsProjectionRow(
    LayerRowAddress(trackCameraRowId(track.id)),
    head: _cameraHeadOf(track),
    kind: LayerKind.camera,
  );

  /// Whether the legend's filter lets a PROJECTION row show — a row of the
  /// track drawn from each cut's own layer, stood on by [address]. Its
  /// [head] IS a layer, so it answers every chip, as an S row does
  /// ([TimelineRowFilter.allowsLayerRow]); with no head the row is judged on
  /// the one facet it has, its [kind]. The row stood on is spared.
  bool _filterAllowsProjectionRow(
    LayerRowAddress address, {
    required Layer? head,
    required LayerKind kind,
  }) {
    final standing = _state.widget.selectedRow == address;
    return head == null
        ? _state.widget.rowFilter.allowsRow(
            standing: standing,
            kind: kind,
            fxEnabled: true,
          )
        : _state.widget.rowFilter.allowsLayerRow(
            head,
            standing: standing,
            fxEnabled: fxEnabledFromState(
              _state.widget.layerFxStateOf?.call(head.id),
            ),
          );
  }

  /// The seats of [track]'s conte group the rail SHOWS, top row first — the
  /// attach rows above the conte and the 공정 folders filing them, the
  /// conte, the ones below it ([conteSeatsOf]) — under the V row (I-73).
  /// A seat is there while the timeline would show its head
  /// ([_conteSeatShown]). The conte's own row is there whether or not a
  /// cut has a conte layer yet — a cut with none wears the button that
  /// makes one there.
  ///
  /// 🚨ONE LIST for the three places that lay these rows out — the row
  /// table, the rail's labels and the strips — as [_shownSeSlots] is.
  List<int> _shownConteSeats(Track track) {
    final folders = <Cut, LayerFolderIndex>{};
    return [
      for (final seat in conteSeatsOf(track.cuts))
        if (_conteSeatShown(track, seat, folders)) seat,
    ];
  }

  /// Whether the rail shows [track]'s conte row at [seat]: THE TIMELINE'S
  /// ANSWER for its head in the head's cut ([layerRowHiddenBy]) — its
  /// section, its group's fold, the legend's filter, a folder above it
  /// shut — and while no cut holds a layer there, the section and the
  /// filter's answer for its kind ([_filterAllowsProjectionRow]).
  ///
  /// ↩️It asked the section, the base's fold and the filter of its own,
  /// and no folder: the group's folders were no seats ([conteGroupOf],
  /// I-99).
  ///
  /// [folders] holds each head cut's index for one pass over the seats.
  bool _conteSeatShown(
    Track track,
    int seat,
    Map<Cut, LayerFolderIndex> folders,
  ) {
    final address = LayerRowAddress(trackConteRowId(track.id, seat: seat));
    final head = conteHeadAt(track.cuts, seat);
    if (head == null) {
      return _sectionShown(timelineSectionForLayerKind(LayerKind.storyboard)) &&
          _filterAllowsProjectionRow(
            address,
            head: null,
            kind: LayerKind.storyboard,
          );
    }
    final widget = _state.widget;
    final layers = head.cut.layers;
    return layerRowHiddenBy(
          head.row,
          folders: folders[head.cut] ??= LayerFolderIndex(layers),
          attachBaseId: attachGroupBaseOf(head.row, layers),
          hiddenSections: widget.hiddenSections,
          rowFilter: widget.rowFilter,
          collapsedAttachBaseIds: widget.collapsedAttachBaseIds,
          standingLayerId: widget.selectedRow == address ? head.row.id : null,
          fxEnabledOf: (id) =>
              fxEnabledFromState(widget.layerFxStateOf?.call(id)),
        ) ==
        null;
  }

  /// One track group's rail rows in TIMELINE order (R6 B3, R7-④): the S
  /// rows (each with its twirled-down 「오디오」 and Transform groups)
  /// ABOVE the V track row and ITS Transform group, slots counting UP from
  /// the bottom like the timeline's layer stack (S1 sits right above V,
  /// S2 above it); the section ZONE spans the whole group (UI-R7 #2).
  /// Whether the legend's filter lets this S row show (R5 #9).
  ///
  /// An S row IS a layer, so it answers every chip
  /// ([TimelineRowFilter.allowsLayerRow]).
  bool _filterAllowsSeRow(Track track, int slot) {
    final layer = _trackSeAt(track, slot);
    return layer == null ||
        _state.widget.rowFilter.allowsLayerRow(
          layer,
          standing: _state.widget.selectedRow == LayerRowAddress(layer.id),
          fxEnabled:
              fxEnabledFromState(_state.widget.layerFxStateOf?.call(layer.id)),
        );
  }

  /// Whether the filter lets this V row show.
  ///
  /// A track carries `fxEnabled` and nothing else the chips read, so it is
  /// judged on that alone — the fx chip filters it exactly like a layer,
  /// and the chips whose field it lacks leave it be. Same rule as the S
  /// row above; only the facets differ, because the rows differ.
  ///
  /// When tracks gain a mark (the user means to), pass it here and the mark
  /// chip starts filtering V rows with no change to the rule.
  bool _filterAllowsTrackRow(Track track) =>
      _state.widget.rowFilter.allowsRow(
        standing: _state.widget.selectedRow == TrackRowAddress(track.id),
        fxEnabled:
            fxEnabledFromState(_state.widget.trackFxStateOf?.call(track)),
      );

  /// How tall ONE S ROW stands on the rail: the row, plus its lanes when
  /// twirled open — its run in the table the rail is drawn from
  /// ([_trackGroupRowGeometry]), read back as a number.
  double _seRowGroupExtent(Track track, int slot) =>
      _rowRunExtent(track, (row) => row.seSlot == slot);

  /// How tall the conte row at [seat] stands on the rail: the row, plus its
  /// lanes when twirled open — [_seRowGroupExtent]'s run, on that row.
  double _conteRowGroupExtent(Track track, int seat) {
    final row = LayerRowAddress(trackConteRowId(track.id, seat: seat));
    return _rowRunExtent(track, (slot) => slot.standRow == row);
  }

  /// The run of [track]'s table from the row [isRow] names through the
  /// lanes under it, read back as a number.
  double _rowRunExtent(
    Track track,
    bool Function(_StoryboardRailSlot slot) isRow,
  ) {
    var extent = 0.0;
    var inRun = false;
    for (final row in _trackGroupRowGeometry(track)) {
      if (isRow(row)) {
        inRun = true;
      } else if (inRun && !row.lane) {
        break;
      }
      if (inRun) {
        extent += row.height;
      }
    }
    return extent;
  }

  /// How tall one TRACK GROUP stands on the rail: every row of it in the
  /// table the rail is drawn from — its S rows, its V row, and their lanes
  /// when twirled open.
  ///
  /// This — not [StoryboardPanel.trackLaneHeight] — is a V row's drag
  /// pitch. Two V rows are separated by the whole group between them, so
  /// counting in the V row's own 64px moved two tracks per group and the
  /// widget test caught it immediately.
  double _trackGroupExtent(Track track) => _trackGroupRowGeometry(
    track,
  ).fold(0, (extent, row) => extent + row.height);

  /// How much of [_trackGroupExtent] stands ABOVE the V row — the rail draws
  /// the transition row and then the S rows before it (④).
  ///
  /// The V row is the handle but the GROUP is the pitch, so the drag has to
  /// be told where the handle sits inside the run; see
  /// [LayerRowDragTarget.grabOffsetWithinRun]. Read off the same table as
  /// [_trackGroupExtent], so the two cannot drift apart.
  double _trackGroupExtentAboveVRow(Track track) {
    var extent = 0.0;
    for (final row in _trackGroupRowGeometry(track)) {
      if (row.row is TrackRowAddress) {
        break;
      }
      extent += row.height;
    }
    return extent;
  }

  /// [track]'s rail rows, section by section, as the rows' window [rows]
  /// lays them.
  List<Widget> railRowsForTrack(Track track, int index, _WindowedRows rows) {
    // In the table's order — the window lays each section's units off it.
    final camRows = rows.lay(_camRowsFor(track));
    final seRows = rows.lay(_seRowsFor(track));
    final vRows = _filterAllowsTrackRow(track)
        ? rows.lay([() => _vRowsFor(track, index)])
        : const <Widget>[];
    final conteRows = rows.lay(_conteRowsFor(track));
    return [
      // The CAM section heads the group: the camera row at its top, as the
      // timeline's camera row tops its own (I-73 ④, 유저 2026-10-08:
      // 「카메라는 로컬이랑 똑같이 최상단행. cam섹션의 제일 위」), then the
      // transition row. The transition row is a FIXTURE like S1/S2 — one per
      // track, always there — so it takes no filter gate and no reorder drag:
      // there is nothing to hide it behind and nowhere to move it to.
      //
      // The band says CAM because both rows ARE camera-section rows
      // ([timelineSectionForLayerKind]) — the label comes from that policy
      // rather than being typed here, so the two rails cannot start naming
      // the same section differently.
      if (camRows.isNotEmpty)
        _sectionZoneGroup(
          keyValue: 'storyboard-section-zone-${track.id.value}-camera',
          label: timelineSectionLabel(TimelineSection.camera),
          rows: camRows,
          laidBy: rows,
        ),
      // A section with no rows left draws no zone: an empty SE band would
      // be a label over nothing once the filter took its rows.
      if (seRows.isNotEmpty)
        _sectionZoneGroup(
          keyValue: 'storyboard-section-zone-${track.id.value}-se',
          label: 'SE',
          rows: seRows,
          laidBy: rows,
        ),
      if (_filterAllowsTrackRow(track))
        _sectionZoneGroup(
          keyValue: 'storyboard-section-zone-${track.id.value}-v',
          label: 'V',
          rows: vRows,
          laidBy: rows,
        ),
      // The CONTE row, directly under the V row whose cuts it reads (I-73,
      // 유저 2026-10-08: 「v행 아래에 콘티행 만들어서 거기서」). The band says
      // what the timeline's says over the same layers — the section their
      // kind sits in ([timelineSectionForLayerKind]).
      if (conteRows.isNotEmpty)
        _sectionZoneGroup(
          keyValue: 'storyboard-section-zone-${track.id.value}-conte',
          label: timelineSectionLabel(
            timelineSectionForLayerKind(LayerKind.storyboard),
          ),
          rows: conteRows,
          laidBy: rows,
        ),
    ];
  }

  /// The CAM section's rail rows for [track]: the camera row with its lanes
  /// while it is twirled open (I-73 ④ⓔ), then the transition row.
  List<_RowUnit> _camRowsFor(Track track) => [
    if (_showsCameraRow(track))
      () => [
        _state._rows.cameraLabelRow(track),
        if (_cameraLanesOpen(track)) ..._cameraLaneLabels(track),
      ],
    if (_showsTransitionRow(track))
      () => [_state._rows.transitionLabelRow(track)],
  ];

  /// The conte section's rail rows for [track], top seat first
  /// ([_shownConteSeats]): each row with its lanes while it is twirled open
  /// (I-73 ④ⓔ).
  List<_RowUnit> _conteRowsFor(Track track) => [
    for (final seat in _shownConteSeats(track))
      () => [
        _state._rows.conteLabelRow(track, seat),
        if (_conteLanesOpen(track, seat)) ..._conteLaneLabels(track, seat),
      ],
  ];

  /// The SE section's rail rows for [track], top slot first: each slot
  /// the rail shows ([_shownSeSlots]), with its lane labels while the row
  /// is expanded.
  List<_RowUnit> _seRowsFor(Track track) => [
    for (final slot in _shownSeSlots(track))
      () => [
        _state._rows.seLabelRow(track, slot),
        if (_seLanesOpen(track, slot)) ..._seLaneLabels(track, slot),
      ],
  ];

  /// One S row's lane labels on the shared substrate, row for row with
  /// [_seLaneStrips]: its headers answer to the timeline's own switch and
  /// reset, and every group keys by [laneGroupKey], the timeline's (F-101).
  List<Widget> _seLaneLabels(Track track, int slot) {
    final layer = _trackSeAt(track, slot);
    if (layer == null) {
      return const [];
    }
    final onToggleEnabled = _state.widget.onToggleLaneGroupEnabled;
    final onReset = _state.widget.onResetLaneGroup;
    final lanes = _seLanes(track, slot);
    final labels = _state._rows.laneLabels(
      carrier: layer,
      groupKeyOf: (lane) => laneGroupKey(layer.id, lane.laneId),
      lanes: lanes,
      follow: (_, lane, row) => _followingSeLane(track, layer, lane, row),
      onToggleGroupEnabled: onToggleEnabled == null
          ? null
          : (lane) => onToggleEnabled(layer, lane),
      onResetGroup: onReset == null ? null : (lane) => onReset(layer, lane),
      // The row exists or it does not; the open cut is not part of the
      // question (user, 2026-08-09).
      active: true,
      // An S row's keys are the TRACK's, so its labels seek the GLOBAL
      // playhead they stand on ([_laneHandOf]), as the V rows' do (R4b).
      // ↩️They read the ACTIVE cut's local cursor (#844 carried the frame
      // over as it was): in any cut but the first the value showed at the
      // wrong frame, and the ◆ keyed there (F-102).
      onSelectFrame: _state.widget.onSeekGlobalFrame,
      graphVerbs: _laneGraphVerbs,
    );
    return _state._rows.laneRows(layer.id, lanes, labels, chainId: layer.id);
  }

  /// [lane] of [layer], an S row of [track], built by [build] as an edit in
  /// flight shows it — a value scrubbed here or on the timeline's copy of
  /// the row, a key range slid — in its GLOBAL form, the axis this rail
  /// draws (F-195). Its label and its strip read the lane through here, so
  /// the two cannot show different keys mid-drag.
  ///
  /// ↩️The strip read the lane as committed: a key slid along an S row's
  /// lane stood still on its strip until the release, while the label and
  /// the V row's strips moved (I-89 ⓕ, 2026-10-21).
  Widget _followingSeLane(
    Track track,
    Layer layer,
    PropertyLaneRow lane,
    Widget Function(Layer shown, PropertyLaneRow lane) build,
  ) => TimelineDragPreviewRowGate(
    dragPreview: _state.widget.dragPreview,
    layer: layer,
    useGlobalForm: true,
    slice: (shown) => laneRowSlice(shown, lane.laneId),
    rowBuilder: (context, shown) => build(
      shown,
      identical(shown, layer)
          ? lane
          : laneAsPreviewed(lane, _seLanesOf(track, shown)),
    ),
  );

  /// The camera row's lane labels, row for row with its lane strips
  /// (I-73 ④ⓔ): the timeline's camera lanes ([_cameraLanes]), on the camera
  /// of the cut the session stands in ([_projectionLaneLabels]) — the row's
  /// head.
  List<Widget> _cameraLaneLabels(Track track) {
    final head = _cameraHeadAt(track);
    final shown = _inHand(
      track,
      LayerRowAddress(trackCameraRowId(track.id)),
    )?.layer;
    if (shown == null) {
      return const [];
    }
    return _projectionLaneLabels(
      _cameraProjection(track),
      (stood: head, shown: shown, lanes: _cameraLanes(track)),
      // F-195: a value scrubbed here, or a key range slid, shows as the
      // camera holds it in flight.
      follow: head == null
          ? null
          : (carrier, lane, row) => _followingCamera(
              head.cut,
              (cameraTrack) => row(
                carrier,
                laneAsPreviewed(
                  lane,
                  cameraPropertyLanes(
                    head.layer,
                    cameraTrack,
                    canvasSize: head.cut.canvasSize,
                  ),
                ),
              ),
            ),
    );
  }

  /// A conte row's lane labels, row for row with its lane strips (I-73
  /// ④ⓔ): its timeline row's lanes ([_conteLanes]), on the row at its seat
  /// of the cut the session stands in ([_projectionLaneLabels]) — or, where
  /// that cut holds none, the row's head.
  List<Widget> _conteLaneLabels(Track track, int seat) {
    final stood = _stoodInHand(track, _conteRow(track, seat));
    final shown = _inHand(track, _conteRow(track, seat))?.layer;
    if (shown == null) {
      return const [];
    }
    return _projectionLaneLabels(
      _conteProjection(track, seat),
      (stood: stood, shown: shown, lanes: _conteLanes(track, seat)),
      // F-195: as the timeline's row gate follows its row.
      follow: stood == null
          ? null
          : (carrier, lane, row) => TimelineDragPreviewRowGate(
              dragPreview: _state.widget.dragPreview,
              layer: stood.layer,
              slice: (previewed) => laneRowSlice(previewed, lane.laneId),
              rowBuilder: (context, previewed) => row(
                carrier,
                identical(previewed, stood.layer)
                    ? lane
                    : laneAsPreviewed(
                        lane,
                        _conteRowLanes(stood.cut, previewed, valued: true),
                      ),
              ),
            ),
    );
  }

  /// A PROJECTION row's lane labels (I-73 ④ⓔ): [labels]' lanes worn by the
  /// ROW — stood on and lit by its own lane addresses
  /// ([_ProjectionLanes.rowId]), their groups twirled with the timeline's —
  /// read on the row's layer of the cut the session stands in
  /// ([labels]' `stood`): valued at the frame of its own that cut is on,
  /// edited, walked and switched there as the timeline's lanes are, and
  /// following an edit in flight there ([follow]). With nothing stood in —
  /// a gap, or a cut that holds no layer there — their names alone, on the
  /// layer [labels] shows.
  List<Widget> _projectionLaneLabels(
    _ProjectionLanes projection,
    ({
      ({Cut cut, Layer layer})? stood,
      Layer shown,
      List<PropertyLaneRow> lanes,
    })
    labels, {
    required Widget Function(
      Layer carrier,
      PropertyLaneRow lane,
      Widget Function(Layer carrier, PropertyLaneRow lane) row,
    )?
    follow,
  }) {
    final stood = labels.stood;
    final seek = _state.widget.onSeekCutFrame;
    final toggleEnabled = _state.widget.onToggleLaneGroupEnabled;
    final reset = _state.widget.onResetLaneGroup;
    final rows = _state._rows.laneLabels(
      carrier: labels.shown.copyWith(id: projection.rowId),
      lanes: labels.lanes,
      groupKeyOf: (lane) => laneGroupKey(labels.shown.id, lane.laneId),
      follow: stood == null ? null : follow,
      onToggleGroupEnabled: stood == null || toggleEnabled == null
          ? null
          : (lane) => toggleEnabled(stood.layer, lane),
      onResetGroup: stood == null || reset == null
          ? null
          : (lane) => reset(stood.layer, lane),
      active: stood != null,
      onSelectFrame: stood == null || seek == null
          ? null
          : (frame) => seek(stood.cut.id, frame),
      // I-89 ①: by the row's own id, which this rail keys its graphs by.
      graphVerbs: _laneGraphVerbs,
    );
    return _state._rows.laneRows(
      projection.rowId,
      labels.lanes,
      rows,
      chainId: stood?.layer.id,
    );
  }

  /// [build] with [cut]'s camera track as the drag channel shows it — a key
  /// range slid along it, a value scrubbed in it — rebuilt whenever that
  /// moves: the camera lanes' labels read the track through here, as the
  /// strips read it off the cut the channel lays out.
  Widget _followingCamera(
    Cut cut,
    Widget Function(TransformTrack cameraTrack) build,
  ) {
    final dragPreview = _state.widget.dragPreview ?? _noDragPreview;
    return SlicedListenableBuilder<TransformTrack>(
      listenable: dragPreview,
      slice: () =>
          timelineDragPreviewCameraTrackFor(dragPreview.value, cut.id) ??
          cut.camera.track,
      builder: (context, cameraTrack) => build(cameraTrack),
    );
  }

  /// A V row's label [row] with the V rows' splitter along its bottom edge
  /// ([StoryboardPanel.onResizeTrackLanes]) — the row's own edge, lit when
  /// the pointer comes to it — or the row alone when the host takes no
  /// resize. Every V row carries one, and each moves the height they share.
  ///
  /// The resize is the host's as it stands at the drag: the row is kept
  /// with its splitter ([_StoryboardRowsAndLabels.trackDraggable]).
  Widget _withTrackLaneSplitter(TrackId trackId, Widget row) {
    if (_state.widget.onResizeTrackLanes == null) {
      return row;
    }
    return Stack(
      children: [
        row,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: DockEdgeSplitter.thickness,
          child: DockEdgeSplitter(
            key: ValueKey<String>(
              'storyboard-track-lane-splitter-${trackId.value}',
            ),
            axis: Axis.horizontal,
            onDragDelta: (delta) =>
                _state.widget.onResizeTrackLanes?.call(delta) ?? 0,
          ),
        ),
      ],
    );
  }

  /// The V section's rail rows for [track]: the draggable track label row,
  /// and the track's effect lane rows while its transform group is
  /// expanded.
  List<Widget> _vRowsFor(Track track, int index) {
    final vRows = <Widget>[
      _state._rows.trackDraggable(
        track,
        index,
        // ↩️F-19 (유저 2026-08-24): 「스토리보드패널의 버튼, **룰러 스크럽시
        // 현재 인덱스의 컷에 따라 버튼이 갱신 안되고** … **손 떼야 갱신**되서
        // 활성화되거나 하는데 어떻게 가능한가?」
        //
        // The button was this row's EYE, the one cell that showed which
        // cut stands under the playhead. The panel deliberately does NOT
        // rebuild on a tick (W4, the cursor-layer split), so the eye read
        // the frame of the last panel rebuild — where the drag STARTED —
        // until it took the subscription the overlay and the ruler take
        // (09-28: on a tick layer of its own; it had been the whole row).
        // The eye left the row with I-73 (2026-10-08, see
        // [StoryboardTrackLabelRow.trackFxState]) and the subscription
        // with it: nothing this row shows follows the playhead now.
        //
        // ⛔What that round ruled OUT stands for whatever follows the
        // playhead next: NOT by making the ruler switch the active cut,
        // which is what the report wondered aloud about (「애초에 룰러에
        // 따라 액티브컷 전환하도록 하는게 구조적 해결일까」). The scrub PARKS
        // on purpose — the whole preview machinery (D6's no-flash rules,
        // the territory flag) exists because the active cut does not
        // follow a drag — and switching it per move would put a cut
        // activation on every pointer move.
        StoryboardTrackLabelRow(
          trackId: track.id,
          trackLabel: storyboardVideoRowName(index),
          laneHeight: _state.widget.trackLaneHeight,
          laneExpanded: track.lanesExpanded,
          // The row's verbs ask for the track as the panel holds it at the
          // press: the row is kept while what it shows holds, and it shows
          // nothing of the track's cuts. The twirl is the track's own
          // (F-360), turned by its lane carrier — drawn while the track has
          // lanes to twirl down, as every row's twirl is ([_trackTwirlOf]),
          // and as the column sweep paints it. ↩️It stood on a track with
          // none, turning nothing, since a track row owns no Transform
          // group ([timelineRowOwnsTransform]).
          onToggleLane:
              _state.widget.onToggleLayerLanes == null ||
                  _trackTwirlOf(track) == null
              ? null
              : () => _state.widget.onToggleLayerLanes?.call(
                  trackTransformLaneCarrierId(track.id),
                ),
          // V-track selection (UI-R18 #6): tapping selects the track (its
          // playhead-index cut becomes active). The highlight says THIS ROW
          // IS SELECTED — not "the active cut lives here", which is what the
          // cut block's own active border already says, and which could light
          // at the same time as an S row.
          active: _state.widget.selectedRow == TrackRowAddress(track.id),
          onSelectTrack: _state.widget.onSelectTrack == null
              ? null
              : () => _state.widget.onSelectTrack!(track.id),
          onSettledPress: _state.widget.onSettledPress,
          // R9 #21: the track's own display column.
          trackFxState:
              _state.widget.trackFxStateOf?.call(track) ?? LayerFxState.on,
          onToggleTrackFx: _state.widget.onToggleTrackFx == null
              ? null
              : () => _actOnTrack(track.id, _state.widget.onToggleTrackFx),
        ),
      ),
      if (track.lanesExpanded) ...[
        // No Transform-group labels: a track row does not own one
        // ([timelineRowOwnsTransform]). Its twirl-down is the fx chain alone —
        // the same place a layer keeps its effects, and the same lane
        // substrate. Grabbing a header re-orders the chain, exactly as it does
        // on a layer's rail (the fx-order drag's subject only differs in WHICH
        // chain it names).
        ..._state._rows.laneRows(
          trackTransformLaneCarrierId(track.id),
          _trackEffectLanes(track),
          _state._rows.laneLabels(
            carrier: _trackLaneCarrier(track),
            // A layer row's own key ([laneGroupKey]), on the lane carrier.
            groupKeyOf: (lane) =>
                laneGroupKey(trackTransformLaneCarrierId(track.id), lane.laneId),
            lanes: _trackEffectLanes(track),
            // F-195: the V row's chain as an edit in flight shows it — the
            // one function its key strips read too.
            follow: (carrier, lane, row) => _followingTrackEffects(
              track,
              (previewed) => row(
                carrier,
                previewed == null
                    ? lane
                    : laneAsPreviewed(
                        lane,
                        _trackEffectLanes(track.copyWith(effects: previewed)),
                      ),
              ),
            ),
            onToggleGroupEnabled:
                _state.widget.onToggleTrackEffectEnabled == null
                ? null
                : (lane) {
                    final parsed = parseEffectLaneId(lane.laneId);
                    if (parsed != null) {
                      _state.widget.onToggleTrackEffectEnabled!(
                        track,
                        parsed.effectId,
                      );
                    }
                  },
            onResetGroup: _state.widget.onResetTrackEffectGroup == null
                ? null
                : (lane) => _state.widget.onResetTrackEffectGroup!(
                    track,
                    lane.laneId,
                  ),
            active: true,
            onSelectFrame: _state.widget.onSeekGlobalFrame,
            graphVerbs: _laneGraphVerbs,
          ),
          chainId: trackTransformLaneCarrierId(track.id),
        ),
      ],
    ];
    return vRows;
  }

  /// One section's rail rows with the ZONE spanning the whole group over
  /// the rows' reserved band slots (UI-R7 #2): S1·S2 read as one SE
  /// sub-zone, exactly like the timeline's run zones. The zone is the
  /// pass's: a move of the window lays the rows again, never it
  /// ([_WindowedRows.kept]).
  Widget _sectionZoneGroup({
    required String keyValue,
    required String label,
    required List<Widget> rows,
    required _WindowedRows laidBy,
  }) {
    return Stack(
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
        laidBy.kept(
          keyValue,
          () => Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: KeyedSubtree(
              key: ValueKey<String>(keyValue),
              child: SectionBandZone(label: label),
            ),
          ),
        ),
      ],
    );
  }

  /// One track's whole strip section: its rows in a column, with the
  /// track-axis range selection drawn OVER them as the timeline's one
  /// selection band (R27 #14 — cells, lanes and now this rail draw exactly
  /// the same band, so a storyboard span cannot read as a different kind
  /// of selection).
  /// One track's strip rows, re-timed by an in-flight drag.
  ///
  /// This is where the preview channel is READ — not at the panel's root,
  /// which is where it used to be. A cut-length drag published one number
  /// and the whole body re-recorded for it: the rail, the ruler, the label
  /// column, the scrollbars, every SE strip. Measured at 172ms a step
  /// against the timeline's 24ms for the same edit — and 112ms of that was
  /// the rebuild ALONE, with the previewed project swapped back out for the
  /// committed one so nothing downstream had changed.
  ///
  /// The timeline never paid it, for a structural reason rather than a
  /// clever one: it subscribes at the LEAVES — the cut-end line, the ruler
  /// line, the out-of-cut wash, and a per-row gate that substitutes one
  /// Layer. This is the storyboard's version of that gate, at the altitude
  /// the strip's own unit of work sits at.
  ///
  /// The track-global rows are already handed in from outside the
  /// subscription (R10-③, the same idea reached one row at a time);
  /// everything else in the body now builds from the committed project once.
  Widget trackGroupSection(
    Track track,
    int index,
    List<StoryboardTimelineLayoutEntry> entries,
    double width,
    TimelineScale scale,
    List<List<Widget>> trackGlobalRows,
  ) {
    // As tall as the rail draws the group ([_trackGroupExtent]), so the
    // strip's tick layer ([_trackStrip]) is handed its size from above —
    // the one way a tick layer keeps its layout in.
    return SizedBox(
      width: width,
      height: _trackGroupExtent(track),
      child: Stack(
        children: [
          _trackStrip(track, index, entries, width, scale, trackGlobalRows),
          Positioned.fill(
            child: IgnorePointer(child: _trackRangeBand(track, scale)),
          ),
          Positioned.fill(
            child: IgnorePointer(child: _trackLaneRangeBand(track, scale)),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: _projectionLaneBand(track, scale, entries),
            ),
          ),
          // 🚨On its OWN layer (I-22 ③): the standing cell follows the
          // playhead, and the strips around it are one RepaintBoundary
          // precisely so a playhead move re-rasterizes none of them
          // (R12-⑥). Mounted bare inside it, every move repainted every
          // strip — at ten minutes every edge grip of the film and the plate
          // grounds under them, on every playback frame. The timeline's
          // cursor layer rides its own the same way — and a layout of its
          // own besides ([TickLayer]).
          Positioned.fill(
            child: IgnorePointer(
              child: TickLayer(
                child: _state._standing.trackStandingCell(track, scale),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// [track]'s strip rows, rebuilt only where the preview moves its cuts
  /// ([_TrackStrip]) — filling its group on a TICK LAYER of their own: a
  /// drag step is a tick (F-244).
  ///
  /// 🚨F-446 (10-24): rebuilt bare in the body's layout scope, a step's
  /// strip laid out the track's column, the scroll content and both
  /// viewports, and repainted the storyboard's body around them — on a
  /// panel comma, a cut's trim or move, and the SE row's comma, whose gate
  /// stands in the column too.
  ///
  /// The rows' window lays them ([_StoryboardRowsWindow]), as the rail's.
  Widget _trackStrip(
    Track track,
    int index,
    List<StoryboardTimelineLayoutEntry> entries,
    double width,
    TimelineScale scale,
    List<List<Widget>> trackGlobalRows,
  ) {
    final dragPreview = _state.widget.dragPreview ?? _noDragPreview;
    final window = _state._rowsWindow;
    return Positioned.fill(
      child: TickLayer(
        // A preview step is a pass of its own: the window keeps nothing
        // a drag moved across it.
        child: SlicedListenableBuilder<_TrackStrip>(
          listenable: dragPreview,
          slice: () => _previewedStripFor(index, dragPreview.value, entries),
          builder: (context, strip) => window.laidColumn(
            window.stripKeepOf(index),
            (rowsOf) => _stripRowsForTrack(
              track,
              index,
              strip,
              width,
              scale,
              trackGlobalRows,
              rowsOf(index),
            ),
          ),
        ),
      ),
    );
  }

  /// [committed]'s track re-timed by [preview], or [committed] itself when
  /// no drag is in flight.
  ///
  /// The layout is recomputed for the WHOLE film and then filtered, because
  /// a cut's length or leading gap moves every cut behind it — the strip's
  /// geometry is global in a way the timeline's per-row one is not. It is a
  /// walk over a list of cuts, which is the cheap half of what the root
  /// subscription used to do; the expensive half was rebuilding the panel
  /// around it.
  List<StoryboardTimelineLayoutEntry> _previewedEntriesFor(
    int trackIndex,
    TimelineDragPreview? preview,
    List<StoryboardTimelineLayoutEntry> committed,
  ) => _previewedStripFor(trackIndex, preview, committed).entries;

  /// [_previewedEntriesFor]'s cuts with the track's transition row as the
  /// same preview carries it — a cut edge drag takes the O.L across the
  /// boundary it crosses (`_trackWithCutTrimPreview`) — which is where the
  /// camera row reads its cuts' のりしろ ([cameraRowReachesOf]).
  _TrackStrip _previewedStripFor(
    int trackIndex,
    TimelineDragPreview? preview,
    List<StoryboardTimelineLayoutEntry> committed,
  ) {
    final committedRow =
        _state.widget.project.tracks[trackIndex].transitionLayer;
    if (preview == null) {
      return _TrackStrip(committed, committedRow);
    }
    final project = projectWithTimelineDragPreview(
      _state.widget.project,
      preview,
    );
    if (identical(project, _state.widget.project)) {
      return _TrackStrip(committed, committedRow);
    }
    return _TrackStrip([
      for (final entry in buildStoryboardTimelineLayout(project))
        if (entry.trackIndex == trackIndex) entry,
    ], project.tracks[trackIndex].transitionLayer);
  }

  /// The selection band both rail sweeps draw: the vertical extent that
  /// [covers] sweeps out of [_trackGroupRowGeometry], laid at the
  /// horizontal [span] the selection names, or nothing when the sweep
  /// reaches no row on this track.
  ///
  /// ⛔ONE BAND FOR BOTH SWEEPS. Drawn separately, a decoration or a
  /// row-geometry change reached the lane band and left the frame band
  /// behind — and the two sit on the same rows.
  Widget _rangeBand(
    Track track,
    TimelineScale scale, {
    required bool Function(_StoryboardRailSlot slot) covers,
    required ({double left, double width}) span,
    required ({String key, String label}) label,
  }) {
    double y = 0;
    double? top;
    double? bottom;
    for (final slot in _trackGroupRowGeometry(track)) {
      if (covers(slot)) {
        top ??= y;
        bottom = y + slot.height;
      }
      y += slot.height;
    }
    if (top == null || bottom == null) {
      return const SizedBox.shrink();
    }
    return Stack(
      children: [
        Positioned(
          left: span.left,
          top: top,
          width: span.width,
          height: bottom - top,
          child: Semantics(
            key: ValueKey<String>(label.key),
            label: label.label,
            container: true,
            child: DecoratedBox(
              decoration: timelineRangeSelectionBandDecorationAt(
                cellExtent: scale.pixelsPerFrame,
                crossExtent: bottom - top,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The subscribe-guard-draw scaffold both rail sweeps share: nothing
  /// without a selection listenable, nothing while it holds no selection
  /// or the scale is degenerate, otherwise [_rangeBand] with the plan
  /// [plan] reads off the selection — or nothing when [plan] says the
  /// selection is not this track's.
  ///
  /// The band is drawn straight from the selection's own numbers: both
  /// kinds of row here are on the track's global axis, which is the axis
  /// this rail measures in.
  Widget _selectionBand<T>(
    Track track,
    TimelineScale scale,
    ValueListenable<T?>? selection,
    ({
      bool Function(_StoryboardRailSlot slot) covers,
      ({double left, double width}) span,
      ({String key, String label}) label,
    })?
    Function(T selection)
    plan,
  ) {
    if (selection == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<T?>(
      valueListenable: selection,
      builder: (context, current, _) {
        if (current == null || scale.pixelsPerFrame <= 0) {
          return const SizedBox.shrink();
        }
        final planned = plan(current);
        if (planned == null) {
          return const SizedBox.shrink();
        }
        return _rangeBand(
          track,
          scale,
          covers: planned.covers,
          span: planned.span,
          label: planned.label,
        );
      },
    );
  }

  /// The LANE selection's band over this group's property-lane rows —
  /// the V track's own (R4b) and its S rows' alike (R5 ③b). The
  /// timeline's R27 #14 overlay language: ONE band with the cell
  /// selection's decoration across the spanned lane rows, drawn above the
  /// strips. Covered rows come from the SAME predicate the gesture and
  /// markers use ([laneSelectionCoversBandRow]), so the header row bands
  /// on a whole-group span, collapsed state included.
  Widget _trackLaneRangeBand(Track track, TimelineScale scale) =>
      _selectionBand<TimelineLaneSelection>(
        track,
        scale,
        _state.widget.laneRange?.selection,
        (selection) {
          final subjectId = selection.layerId;
          return (
            covers: (slot) {
              final laneRow = slot.laneRow;
              return slot.bandRow &&
                  laneRow != null &&
                  laneRow.layerId == subjectId &&
                  laneSelectionCoversBandRow(
                    selection,
                    subjectId,
                    laneRow.laneId,
                  );
            },
            span: (
              left: scale.leftForFrame(selection.startIndex),
              width: scale.spanWidth(
                selection.startIndex,
                selection.endIndexExclusive,
              ),
            ),
            label: (
              key: 'storyboard-lane-range-selection',
              label: AppText.strings.tlSelectedLaneRange,
            ),
          );
        },
      );

  /// The LANE selection's band over a projection row's lanes (I-73 ④ⓔ —
  /// the camera row's, a conte row's): the selection names one cut's layer
  /// in the cut's own frames, so the band
  /// lies over that cut's own frames, on the line the cut is drawn on there
  /// ([CameraRowReach.stretchesOf]) — across every lane it spans where the
  /// cut runs alone, and over the cut's half of each where it shares its
  /// frames with a neighbour. The one band decoration, as the track's lane
  /// band ([_trackLaneRangeBand]) wears.
  Widget _projectionLaneBand(
    Track track,
    TimelineScale scale,
    List<StoryboardTimelineLayoutEntry> entries,
  ) {
    final selection = _state.widget.laneRange?.selection;
    if (selection == null ||
        !(_cameraLanesOpen(track) ||
            _shownConteSeats(track).any(
              (seat) => _conteLanesOpen(track, seat),
            ))) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<TimelineLaneSelection?>(
      valueListenable: selection,
      builder: (context, current, _) =>
          current == null || scale.pixelsPerFrame <= 0
          ? const SizedBox.shrink()
          : Stack(
              children: _projectionLaneBandPieces(
                track,
                scale,
                entries,
                current,
              ),
            ),
    );
  }

  List<Widget> _projectionLaneBandPieces(
    Track track,
    TimelineScale scale,
    List<StoryboardTimelineLayoutEntry> entries,
    TimelineLaneSelection selection,
  ) {
    // The cut whose layer the selection names, and the projection row that
    // shows that layer ([projectionRowIdOf]).
    final reaches = cameraRowReachesOf(
      entries,
      transitionRowSpans(
        track.transitionLayer,
        _state.widget.project.cameraInstructions,
      ),
    );
    final named = [
      for (final reach in reaches)
        if (projectionRowIdOf(track.id, reach.entry.cut, selection.layerId)
            case final rowId?)
          (reach: reach, rowId: rowId),
    ].firstOrNull;
    if (named == null) {
      return const [];
    }
    final (:reach, :rowId) = named;
    final covered = <({double top, double bottom})>[];
    var y = 0.0;
    for (final slot in _trackGroupRowGeometry(track)) {
      final lane = slot.laneRow;
      if (lane != null &&
          lane.layerId == rowId &&
          laneSelectionCoversBandRow(selection, selection.layerId, lane.laneId)) {
        covered.add((top: y, bottom: y + slot.height));
      }
      y += slot.height;
    }
    if (covered.isEmpty) {
      return const [];
    }
    return [
      for (final stretch in reach.stretchesOf(
        selection.startIndex,
        selection.endIndexExclusive,
      ))
        if (stretch.line == CameraRowLine.middle)
          _laneBandPiece(
            scale,
            stretch,
            (top: covered.first.top, bottom: covered.last.bottom),
          )
        else
          for (final row in covered)
            _laneBandPiece(scale, stretch, switch (stretch.line) {
              CameraRowLine.upper => (
                top: row.top,
                bottom: (row.top + row.bottom) / 2,
              ),
              _ => (top: (row.top + row.bottom) / 2, bottom: row.bottom),
            }),
    ];
  }

  /// One piece of [_projectionLaneBand]: [stretch]'s frames, [across] the
  /// rows.
  Widget _laneBandPiece(
    TimelineScale scale,
    CameraRowStretch stretch,
    ({double top, double bottom}) across,
  ) => Positioned(
    key: ValueKey<String>(
      'storyboard-projection-lane-range-selection-${stretch.from}-'
      '${across.top}',
    ),
    left: scale.leftForFrame(stretch.from),
    top: across.top,
    width: scale.spanWidth(stretch.from, stretch.to),
    height: across.bottom - across.top,
    child: Semantics(
      label: AppText.strings.tlSelectedLaneRange,
      container: true,
      child: DecoratedBox(
        decoration: timelineRangeSelectionBandDecorationAt(
          cellExtent: scale.pixelsPerFrame,
          crossExtent: across.bottom - across.top,
        ),
      ),
    ),
  );

  /// The band itself: [selection.spanRows] top to bottom — intervening
  /// twirled-open lanes ride under it, exactly as the timeline's band
  /// covers lanes between two covered layer rows.
  Widget _trackRangeBand(Track track, TimelineScale scale) =>
      _selectionBand<TrackFrameRangeSelection>(
        track,
        scale,
        _state.widget.cutSelect?.selectedRange ??
            _state.widget.seSelect?.selectedRange,
        (selection) {
          if (selection.trackId != track.id) {
            return null;
          }
          final spanned = selection.spanRows.toSet();
          return (
            // C②: an escalated lane drag's span carries LANE rows too — the
            // band covers them exactly as the timeline's covers the lanes it
            // swept.
            covers: (slot) {
              final address = slot.row ?? slot.laneRow;
              return address != null && spanned.contains(address);
            },
            span: (
              left: scale.leftForFrame(selection.startFrame),
              width: scale.spanWidth(
                selection.startFrame,
                selection.startFrame + selection.lengthFrames,
              ),
            ),
            label: (
              key: 'storyboard-frame-range-selection',
              label: AppText.strings.tlSelectedFrameRange,
            ),
          );
        },
      );

  /// The track [trackId] names, as the panel holds it now — what a kept
  /// row's verb asks for at the press (I-57, 10-14): a TRACK closed over
  /// where the row was built would be the track as it stood then, before a
  /// cut came or an S row went, while the row showed nothing that changed.
  Track? _trackNamed(TrackId trackId) => _state.widget.project.tracks
      .where((track) => track.id == trackId)
      .firstOrNull;

  /// [verb] on the track [trackId] names at the press ([_trackNamed]) —
  /// nothing once it is gone.
  void _actOnTrack(TrackId trackId, ValueChanged<Track>? verb) {
    if (_trackNamed(trackId) case final track?) {
      verb?.call(track);
    }
  }

  /// The group's rows in VISUAL order with their heights — mirrored from
  /// [_seStripRowsForTrack] and [_stripRowsForTrack] row for row. A new
  /// row kind must land in both, or the band drifts off its rows.
  /// R9 #25 — what a select-drag pressed on [anchorRow] has swept: every
  /// row from the anchor's to the one its pointer is over, in the order
  /// this rail DRAWS them, lanes and all — the slice the timeline's grids
  /// hand over ([resolveSelectionSpanOverAddresses]).
  ///
  /// [crossOffset] is the pointer's cross-axis distance from the ANCHOR
  /// row's top (negative above it), handed up raw by the shared gesture.
  /// It resolves against [_trackGroupRowGeometry] — the very table the
  /// band painter uses — so the row the selection reaches and the row the
  /// user sees highlighted can no longer be two different answers.
  ///
  /// This rail is the one surface with rows of several heights (SE 30, the
  /// V row 28–160, audio 36, transform 26), which is why the old scalar
  /// "offset ÷ my own height" worked everywhere else and failed here.
  ///
  /// 🚨H20 (유저 2026-08-23: 「둘다 유저가 선택하게」): a lane is a row a
  /// span ends on and holds, as on the timeline. ↩️The head skipped the
  /// lane strips and the session cut the span out of its own rows, which
  /// name no lane: a sweep from an S row's cells down its lanes held the
  /// S row alone, and a press on a lane it seemed to cover started a
  /// selection of its own (conte-sweep-leaves-the-lanes-out, 🧪10-25).
  /// That list of the session's held the rail's order this table draws —
  /// the transition row, the S rows highest slot first, the V row (user
  /// 2026-08-11; leading with the V row inverted every cross-row drag) —
  /// and left a hidden section's rows off, as this table does (F-199).
  ///
  /// 🚨Asked at the drag, of the track [trackId] names as the panel holds
  /// it THEN ([_trackNamed]): a kept row drags with the lookup it was
  /// built with.
  _RailSweepAt _railSweepOn(TrackId trackId) => (anchorRow, crossOffset) {
    final track = _trackNamed(trackId);
    if (track == null) {
      return null;
    }
    final geometry = _trackGroupRowGeometry(track);
    // An Audio strip takes up space but cannot BE a selection head.
    final swept = _sweptOver(
      [for (final slot in geometry) slot.row ?? slot.laneRow],
      [for (final slot in geometry) slot.height],
      anchor: anchorRow,
      crossOffset: crossOffset,
    );
    if (swept == null) {
      return null;
    }
    return resolveSelectionSpanOverAddresses(
      rows: swept.rows,
      anchor: anchorRow,
      rowDelta: swept.rowDelta,
    );
  };

  /// The track band's bundle on [lane] of [track] — the S rows' cells' own
  /// ([_storyboardBandCallbacks]), handed to the lane's strip as its band:
  /// a press inside the band on a lane is the band's move (H20). Null where
  /// this rail selects no band.
  TimelineRangeGestureCallbacks? _bandOnLane(
    Track track,
    LaneRowAddress lane,
  ) {
    final select = _state.widget.seSelect;
    return select == null
        ? null
        : _storyboardBandCallbacks(
            row: lane,
            select: select,
            railSweepAt: _railSweepOn(track.id),
            rows: _seMoveRows(track),
          );
  }

  /// The ROW SELECTION over this rail, as the timeline's rail draws it —
  /// one band over each run of [selected] rows, laid on the table the rail
  /// is drawn from (F-322: 「타임라인이랑 완벽통일」). ↩️This rail drew none,
  /// so a span it selected could not be seen.
  Widget rowSelectionBands(List<TimelineRowAddress> selected) {
    final table = _railTable();
    return TimelineRowSelectionBands(
      selectedFlags: [
        for (final slot in table.slots)
          switch (_standingAddressOf(slot)) {
            final address? => selected.contains(address),
            null => false,
          },
      ],
      edges: table.edges,
      crossExtent: _state._naturalRailWidth - layerSectionLabelSlotWidth,
    );
  }

  /// Every slot of the rail, track group after track group, and where each
  /// lies along it — the WHOLE rail as [_trackGroupRowGeometry] lays it,
  /// which the row selection's bands and the reveal's row
  /// ([_StoryboardStanding.standingRowItem]) are both laid on.
  ({List<_StoryboardRailSlot> slots, TimelineRowEdges edges}) _railTable() {
    final slots = [
      for (final track in _state.widget.project.tracks)
        ..._trackGroupRowGeometry(track),
    ];
    return (
      slots: slots,
      edges: TimelineRowEdges([
        for (final slot in slots)
          (extent: slot.height, room: 0, joinsNext: false),
      ]),
    );
  }

  /// The rail's rows as the rows' window cuts them ([_StoryboardRowsWindow])
  /// — [_railTable]'s, a head row joined with the lanes twirled under it:
  /// one unit, as the strips draw a camera row and its lanes in one
  /// ([_cameraStripRow]). Read once a build ([forgetLaneSeating]).
  _RowsWindowTable get windowTable => _windowTable ??= _windowTableNow();
  _RowsWindowTable? _windowTable;

  _RowsWindowTable _windowTableNow() {
    final slots = <_StoryboardRailSlot>[];
    final firstSlots = <int>[];
    for (final track in _state.widget.project.tracks) {
      firstSlots.add(slots.length);
      slots.addAll(_trackGroupRowGeometry(track));
    }
    return (
      edges: TimelineRowEdges([
        for (var index = 0; index < slots.length; index += 1)
          (
            extent: slots[index].height,
            room: 0,
            joinsNext: index + 1 < slots.length && slots[index + 1].lane,
          ),
      ]),
      slots: slots,
      firstSlots: firstSlots,
    );
  }

  /// Where a SELECT drag pressed on [anchor]'s label has reached, in rows
  /// of [_StoryboardSheet.rows] from it, asked with the pointer's distance
  /// from that label's top ([LayerRowDragTarget.selectRowDeltaAt]).
  ///
  /// Read off the table every track's rail is drawn from
  /// ([_trackGroupRowGeometry]): a row here is as tall as its kind, so the
  /// pressed row's own height cannot count the rest (F-322). A slot nobody
  /// stands on — an open graph's room, an S slot with no layer — hands the
  /// span on to the nearest row toward the anchor, as the cells' sweep does
  /// ([_sweptOver]).
  int Function(double offset) selectRowDeltaFrom(TimelineRowAddress anchor) =>
      (offset) {
        final slots = [
          for (final track in _state.widget.project.tracks)
            ..._trackGroupRowGeometry(track),
        ];
        return _sweptOver(
              [for (final slot in slots) _standingAddressOf(slot)],
              [for (final slot in slots) slot.height],
              anchor: anchor,
              crossOffset: offset,
            )?.rowDelta ??
            0;
      };

  /// Where a pointer [offset] from the top of [anchor]'s label stands, in
  /// rows of the rail from that top ([LayerRowDragTarget.pointerRowsAt]),
  /// read off the table every track's rail is drawn from — where the room
  /// an open graph stands past its lanes is no row (I-89 ③,
  /// [TimelineRowEdges.rowsAt]), as on the timeline's rail.
  double Function(double offset) pointerRowsFrom(TimelineRowAddress anchor) =>
      (offset) {
        final table = _pointerTable();
        final anchorAt = table.rows.indexWhere(
          (row) => row.standing == anchor,
        );
        return anchorAt < 0 ? 0 : table.edges.rowsAt(anchorAt, offset);
      };

  /// How far past [anchor]'s label its two lines stand
  /// ([LayerRowDragTarget.linesBeyond]): to where its unit begins and
  /// ends on the table a pointer counts ([_pointerTable]) — the lanes a row
  /// stands for read as the timeline's rail reads them ([ownsTheLane], over
  /// the rows the timeline holds for these), and a V row's whole track
  /// group, which its drag carries.
  ///
  /// 🚨The timeline's law on this rail (10-25): every line stood at the
  /// label's own edges — under an S row, a conte row and an fx header while
  /// their lanes followed, and at the V row inside a group whose drop lands
  /// past the rows above and below it.
  ({double lead, double trail}) Function() linesBeyondFrom(
    TimelineRowAddress anchor,
  ) => () {
    final table = _pointerTable();
    final rows = table.rows;
    final at = rows.indexWhere((row) => row.standing == anchor);
    if (at < 0) {
      return (lead: 0.0, trail: 0.0);
    }
    final head = rows[at].held;
    final track = rows[at].track;
    final owns = switch ((anchor, head)) {
      (TrackRowAddress(), _) => (int index) => rows[index].track == track,
      (_, final head?) => (int index) => ownsTheLane(head, rows[index].held),
      _ => (int _) => false,
    };
    return linesBeyondRow(
      table.edges,
      at,
      rowUnitAround(at, rows.length, owns),
    );
  };

  /// The rail's rows as a pointer counts them — the room an open graph
  /// stands past its lanes folded into the row before it (I-89 ③,
  /// [TimelineRowEdges.rowsAt]), as on the timeline's rail — and where they
  /// lie along it.
  ({TimelineRowEdges edges, List<_PointerRow> rows}) _pointerTable() {
    final slots = <TimelineRowSlot>[];
    final rows = <_PointerRow>[];
    for (final track in _state.widget.project.tracks) {
      for (final slot in _trackGroupRowGeometry(track)) {
        if (_isRoom(slot)) {
          final last = slots.removeLast();
          slots.add((extent: last.extent, room: slot.height, joinsNext: false));
          continue;
        }
        slots.add((extent: slot.height, room: 0, joinsNext: false));
        rows.add((
          standing: _standingAddressOf(slot),
          held: slot.display?.address,
          track: track.id,
        ));
      }
    }
    return (edges: TimelineRowEdges(slots), rows: rows);
  }

  /// C② — the lane strips' gesture bundle for [track]: raw cross pixels
  /// resolved against THIS rail's mixed-height row table (R9 #25), the
  /// in-group head lane read off the same table, and the drag JOINING the
  /// track-axis cells law the moment it leaves its lane group — the same
  /// wrap the timeline grids apply, over this panel's own rows.
  ///
  /// The lanes of the PROJECTION row [projection] (I-73 ④ⓔ — the camera
  /// row's) take it too: their rows read as the lanes of the layer a sweep
  /// on them began on ([_laneSweepOver]), and the sweep stays in their
  /// group — it names one cut's layer in the cut's own frames, which no
  /// row of the track's axis shares.
  ///
  /// [band] is the track band's bundle on the ONE lane the strip draws
  /// ([_bandOnLane]), as the timeline's grids hand theirs (H20).
  TimelineLaneRangeCallbacks? _laneGestureCallbacksFor(
    Track track, {
    LayerId? projection,
    TimelineRangeGestureCallbacks? band,
  }) {
    final host = _state.widget.laneRange;
    if (host == null) {
      return null;
    }
    return TimelineLaneRangeCallbacks(
      band: band,
      selection: host.selection,
      onSelectUpdate:
          (layerId, laneId, anchorIndex, headIndex, headCrossOffset) {
            final anchor = LaneRowAddress(layerId, laneId);
            final sweep = _laneSweepOver(
              track,
              anchor: anchor,
              headCrossOffset: headCrossOffset,
              projection: projection,
            );
            final escalation = projection != null
                ? null
                : resolveLaneSpanEscalationOverAddresses(
                    rows: sweep.rows,
                    layerId: layerId,
                    laneId: laneId,
                    rowDelta: sweep.rowDelta,
                  );
            if (escalation == null) {
              host.onSelectUpdate(
                layerId,
                laneId,
                anchorIndex,
                headIndex,
                // The span off the SAME drawn rows — 절대명령 2.
                laneSpanOverDrawnRows(
                  rows: sweep.rows,
                  layerId: layerId,
                  laneId: laneId,
                  headLaneId:
                      resolveInGroupHeadLane(
                        rows: sweep.rows,
                        layerId: layerId,
                        laneId: laneId,
                        rowDelta: sweep.rowDelta,
                      ) ??
                      laneId,
                ),
              );
              return;
            }
            // JOIN the track-axis cells law with the sliced span — the
            // timeline's escalation shape, on this rail's own selection.
            _state.widget.seSelect?.onDrag(
              layerId: layerId,
              anchorGlobalFrame: anchorIndex,
              headGlobalFrame: headIndex,
              anchorRow: anchor,
              spanRows: escalation.spanRows,
            );
          },
      // A box on a header graph over these lanes picks as a sweep on them
      // does: a projection row's in the one cut's layer it began in.
      onSelectRows: (rows, anchorIndex, headIndex) {
        final anchor = rows.first;
        final lanes = laneBoxLanesOf(rows);
        if (projection != null || lanes.length == rows.length) {
          host.onSelectUpdate(
            anchor.layerId,
            anchor.laneId,
            anchorIndex,
            headIndex,
            lanes,
          );
          return;
        }
        _state.widget.seSelect?.onDrag(
          layerId: anchor.layerId,
          anchorGlobalFrame: anchorIndex,
          headGlobalFrame: headIndex,
          anchorRow: anchor,
          spanRows: rows,
        );
      },
      onTapAt: host.onTapAt,
      onActivateAt: host.onActivateAt,
      onTapClear: host.onTapClear,
      onCreateKeys: host.onCreateKeys,
      onMoveBegin: host.onMoveBegin,
      onMoveUpdate: host.onMoveUpdate,
      onMoveEnd: host.onMoveEnd,
      onMoveCancel: host.onMoveCancel,
    );
  }

  /// The rows [track]'s table draws, by the address a lane selection names
  /// each by — the lanes of the projection row [projection] as the lanes of
  /// [anchor]'s layer, the layer of the cut a sweep on them began on — and
  /// how many rows from [anchor]'s the pointer stands at [headCrossOffset].
  ///
  /// Call-time reads (the stale-closure rule): the LIVE geometry.
  ({List<TimelineRowAddress?> rows, int rowDelta}) _laneSweepOver(
    Track track, {
    required LaneRowAddress anchor,
    required double headCrossOffset,
    required LayerId? projection,
  }) {
    final geometry = _trackGroupRowGeometry(track);
    final rows = [
      for (final slot in geometry)
        switch (slot.laneRow) {
          final lane? when lane.layerId == projection => LaneRowAddress(
            anchor.layerId,
            lane.laneId,
          ),
          _ => slot.row ?? slot.laneRow,
        },
    ];
    final anchorAt = rows.indexOf(anchor);
    return (
      rows: rows,
      rowDelta: anchorAt < 0
          ? 0
          : rowIndexForCrossOffset(
                  crossOffset: headCrossOffset,
                  anchorIndex: anchorAt,
                  heights: [for (final slot in geometry) slot.height],
                ) -
                anchorAt,
    );
  }

  /// The grid sheet's rows (I-44): every track group's rows in the order the
  /// strip column stacks them, each at its rail height — a lane on the lane
  /// ground, every other row on the panel's own.
  ///
  /// ⛔The SAME table the rail, the bands and the select-drag read
  /// ([_trackGroupRowGeometry]), so the sheet cannot rule a row the strip
  /// column does not have. The rows paint no ground and no seam of their
  /// own any more — the lane band washed itself, and every strip row wore a
  /// foreground border of its own (UI-R5: the timeline's row lines reaching
  /// the frame area here too; a lane band, with its own border as well,
  /// wore two). This is where both are, drawn by the timeline's own sheet —
  /// 유저 F-18: 「스토리보드패널 타임라인이랑 그리드 다를거같은데 절대 다르지
  /// 않도록 통일」, where "절대" is about the next change, not today's pixels.
  ///
  /// An open header graph is ONE row of it, its lanes and its room: the
  /// timeline's sheet rules a graph so ([TimelineRowEdges.unitSpanOf]) — it
  /// rests on the lane ground, and no seam runs through its picture.
  ///
  /// Where a row strokes a dash of its own ([_dashedOn]) the sheet leaves
  /// its line to it ([TimelineGridRows.dashes], F-347) — read off the strip
  /// [preview] lays, the one those rows are built from
  /// ([trackGroupSection]).
  TimelineGridRows gridRows(
    List<Track> tracks,
    Color hostGround, {
    required TimelineDragPreview? preview,
  }) {
    final laneGround = timelineLaneGround(hostGround);
    final seating = _laneSeating;
    final layout = buildStoryboardTimelineLayout(_state.widget.project);
    final rows = <TimelineGridRow>[];
    final dashes = <TimelineGridDash>[];
    var edge = 0.0;
    void lay(TimelineGridRow row, {List<int> dashed = const []}) {
      dashes.addAll([
        for (final frame in dashed)
          (frame: frame, from: edge, to: edge + row.extent),
      ]);
      rows.add(row);
      edge += row.extent;
    }

    for (final (index, track) in tracks.indexed) {
      final entries = _previewedEntriesFor(index, preview, [
        for (final entry in layout)
          if (entry.trackIndex == index) entry,
      ]);
      for (final slot in _trackGroupRowGeometry(track)) {
        if (slot.graph == null) {
          lay(
            (extent: slot.height, ground: slot.lane ? laneGround : hostGround),
            dashed: _dashedOn(slot, entries),
          );
        } else if (seating.at[slot.display?.address] case final index?
            when seating.edges.unitOf(index).first == index) {
          lay((
            extent: seating.edges.unitSpanOf(index).extent,
            ground: laneGround,
          ));
        }
      }
    }
    return TimelineGridRows(rows, dashes: dashes);
  }

  /// Where [slot] strokes a dash of its own over [entries]' cuts: at each
  /// one's start on a projection row, its lanes too ([projectionRowUnder] —
  /// the rows that mount [StoryboardCutStartsPainter]), and nowhere on any
  /// other. The sheet under the open rows ([gridRows]) and the folded row's
  /// ([_StoryboardFolded]) both leave those boundaries to it (F-347).
  static List<int> _dashedOn(
    _StoryboardRailSlot slot,
    List<StoryboardTimelineLayoutEntry> entries,
  ) => projectionRowUnder(slot.display?.address) == null
      ? const []
      : [for (final entry in entries) entry.startFrame];

  /// [track]'s rows as the rail is drawn from them ([_trackGroupSlots]),
  /// each lane laid as the header graphs stand (I-89 ①): at its extent,
  /// seated in its group's open graph, and the ROOM an open graph stands
  /// past its lanes in a slot of its own after the last of them — the
  /// timeline's rows' own seating ([_laneSeating]).
  List<_StoryboardRailSlot> _trackGroupRowGeometry(Track track) {
    final seating = _laneSeating;
    return [
      for (final slot in _trackGroupSlots(track))
        if (seating.at[slot.display?.address] case final index?) ...[
          _seated(
            slot,
            seating.edges.extentOf(index),
            seating.rows[index].graph,
          ),
          if (seating.edges.roomOf(index) > 0)
            _roomOf(seating.rows[index].graph, seating.edges.roomOf(index)),
        ] else
          slot,
    ];
  }

  /// [slot] laid [height] tall, in the open [graph] that draws it.
  static _StoryboardRailSlot _seated(
    _StoryboardRailSlot slot,
    double height,
    TimelineGraphSeat? graph,
  ) => (
    row: slot.row,
    laneRow: slot.laneRow,
    standRow: slot.standRow,
    bandRow: slot.bandRow,
    lane: slot.lane,
    seSlot: slot.seSlot,
    height: height,
    display: slot.display,
    graph: graph,
  );

  /// The room [graph] stands past its lanes, [height] tall: on the lane
  /// ground, and no row anybody stands on — as the timeline's rail lays it
  /// after an open graph's last lane.
  static _StoryboardRailSlot _roomOf(TimelineGraphSeat? graph, double height) =>
      (
        row: null,
        laneRow: null,
        standRow: null,
        bandRow: false,
        lane: true,
        seSlot: null,
        height: height,
        display: null,
        graph: graph,
      );

  /// Whether [slot] is an open graph's room ([_roomOf]): no lane of its
  /// own, in the graph it stands past.
  static bool _isRoom(_StoryboardRailSlot slot) =>
      slot.display == null && slot.graph != null;

  /// Every lane this rail draws as the timeline's rows hold it, seated and
  /// laid ([_LaneSeating]) — read once a build ([forgetLaneSeating]), as
  /// the rail, the strips and every gesture read one table.
  _LaneSeating get _laneSeating => _seating ??= _laneSeatingFor(
    _state.widget.rowSelection?.value ?? const [],
  );
  _LaneSeating? _seating;

  /// What [_laneSeating] and [_laneGraphs] were read for goes with the
  /// build they were read in.
  void forgetLaneSeating() {
    _seating = null;
    _graphs = null;
    _windowTable = null;
  }

  /// THE HEADER GRAPHS AS THIS RAIL KEYS ITS ROWS (I-89 ①): the session's
  /// own ([StoryboardPanel.laneGraphs]), and a PROJECTION row's lanes by
  /// the row's own id as well — what the layer it has in hand wears
  /// ([_projectionRowsInHand]). Read once a build ([forgetLaneSeating]).
  ///
  /// The session keys a graph and a pin by a cut's layer, and turns the
  /// rows that wear one head as one (`SessionRowButtonPresses._everyUseOf`,
  /// `RailView.followHeads`), so the layer in hand speaks for the row — as
  /// it does for the groups the row twirls open. But this rail stands on
  /// the row by its own address, so it seats, draws and presses the row's
  /// graphs by that: the key is changed ONCE, at the border — here, and
  /// back again for a press ([_laneGraphVerbs]).
  LaneGraphsView get _laneGraphs =>
      _graphs ??= _graphsOnTheRows(_state.widget.laneGraphs);
  LaneGraphsView? _graphs;

  /// [graphs] as this rail keys its rows ([_laneGraphs]): every key the
  /// session holds, and a projection row's own beside the one its layer in
  /// hand is held by.
  LaneGraphsView _graphsOnTheRows(LaneGraphsView graphs) {
    if (graphs.open.isEmpty && graphs.pinned.isEmpty) {
      return graphs;
    }
    final rowOf = {
      for (final MapEntry(key: row, value: layer)
          in _projectionRowsInHand().entries)
        layer: row,
    };
    String? onTheRow(String key) => switch (parseLaneGroupKey(key)) {
      (:final layerId, :final laneId) when rowOf.containsKey(layerId) =>
        laneGroupKey(rowOf[layerId]!, laneId),
      _ => null,
    };
    return graphs.copyWith(
      open: {
        ...graphs.open,
        for (final MapEntry(:key, :value) in graphs.open.entries)
          ?onTheRow(key): value,
      },
      pinned: {
        ...graphs.pinned,
        for (final key in graphs.pinned) ?onTheRow(key),
      },
    );
  }

  /// Each projection row of this rail — every track's camera row, and its
  /// conte row at every seat the rail shows — by its own id, to the layer
  /// it has in hand ([_inHand]); none for a row no cut holds a layer for.
  Map<LayerId, LayerId> _projectionRowsInHand() => {
    for (final track in _state.widget.project.tracks) ...{
      if (_inHand(track, LayerRowAddress(trackCameraRowId(track.id)))
          case final inHand?)
        trackCameraRowId(track.id): inHand.layer.id,
      for (final seat in _shownConteSeats(track))
        if (_inHand(track, _conteRow(track, seat)) case final inHand?)
          trackConteRowId(track.id, seat: seat): inHand.layer.id,
    },
  };

  /// THE HEADER GRAPHS' VERBS AS THIS RAIL HANDS THEM (I-89 ①): the
  /// session's ([StoryboardPanel.laneGraphVerbs]), a press on a projection
  /// row's lane by the row's own id handed on as that lane of the layer the
  /// row has in hand — [_laneGraphs] read the other way, the session
  /// turning the row's head family as one. Asked at the press, of the rows
  /// as they stand then: a row kept from an earlier build keeps these.
  LaneGraphVerbs? get _laneGraphVerbs {
    final verbs = _state.widget.laneGraphVerbs;
    if (verbs == null) {
      return null;
    }
    String held(String key) => _laneKeyInHand(key) ?? key;
    return (
      toggle: (key) => verbs.toggle(held(key)),
      togglePin: (key) => verbs.togglePin(held(key)),
      plot: (key, mode) => verbs.plot(held(key), mode),
      resize: (key, extent) => verbs.resize(held(key), extent),
      enlarge: (key) => verbs.enlarge(held(key)),
      pen: (key) => verbs.pen(held(key)),
      transformBox: (key) => verbs.transformBox(held(key)),
      snap: (key) => verbs.snap(held(key)),
    );
  }

  /// The lane [key] names on a projection row, by the row's own id, as the
  /// session holds it: that lane of the layer the row has in hand — or
  /// null for a key of any other row, and for a row no cut holds a layer
  /// for.
  String? _laneKeyInHand(String key) {
    final lane = parseLaneGroupKey(key);
    if (lane == null) {
      return null;
    }
    return switch (_rowInHand(lane.layerId)) {
      final inHand? => laneGroupKey(inHand.layer.id, lane.laneId),
      null => null,
    };
  }

  /// The projection row [rowId] names, IN HAND ([_inHand]) — null for an
  /// id of any other row, and for a row no cut holds a layer for.
  ({Cut cut, Layer layer, bool stood})? _rowInHand(LayerId rowId) {
    final trackId = trackIdOfProjectionRow(rowId);
    final track = trackId == null ? null : _trackNamed(trackId);
    return track == null ? null : _inHand(track, LayerRowAddress(rowId));
  }

  /// What a lane of [rowId]'s row keys and sets its lane with, and where it
  /// stands ([_LaneHand]) — ONE answer for its label and for the column
  /// sweep that presses its ◆ and its flag ring (F-475), so a stroke
  /// presses a lane where the lane's own button would:
  ///
  /// - the V row's lane carrier, its TRACK's verbs;
  /// - a projection row, the verbs of the layer it has in hand of the cut
  ///   the session stands in, at that cut's own frame — and none while no
  ///   cut is stood in there (I-73 ④ⓔ);
  /// - an S row, its layer's.
  ///
  /// The track's rows — V and S alike, their keys are the track's — stand
  /// on the GLOBAL playhead (R4b). ↩️The S rows read the ACTIVE cut's local
  /// cursor (#844 carried the frame over as it was): in any cut but the
  /// first the value showed at the wrong frame, and the ◆ keyed there
  /// (F-102).
  _LaneHand _laneHandOf(LayerId rowId) {
    final widget = _state.widget;
    if (trackIdOfTransformLaneCarrier(rowId) case final trackId?) {
      return (
        edit: switch (_trackNamed(trackId)) {
          final track? => widget.trackLaneEditFor?.call(track),
          null => null,
        },
        cursor: widget.playheadFrame,
      );
    }
    if (trackIdOfProjectionRow(rowId) == null) {
      return (edit: widget.layerLaneEdit, cursor: widget.playheadFrame);
    }
    return switch (_rowInHand(rowId)) {
      (cut: _, :final layer, stood: true)? => (
        edit: widget.cutLaneEdit?.landingOn(layer),
        cursor: widget.cutFrameCursor,
      ),
      _ => (edit: null, cursor: null),
    };
  }

  /// Every lane of every track's table ([_trackGroupSlots]) seated for the
  /// row selection [selected] ([seatLaneGraphs]) and laid along a view as
  /// long as the rail's ([timelineRowEdgesOf]).
  _LaneSeating _laneSeatingFor(List<TimelineRowAddress> selected) {
    final lanes = [
      for (final track in _state.widget.project.tracks)
        for (final slot in _trackGroupSlots(track))
          if (slot.display case final row? when row.isLane) row,
    ];
    final rows = seatLaneGraphs(
      lanes,
      _laneGraphs,
      selection: selected.toSet(),
    );
    return (
      lanes: lanes,
      rows: rows,
      edges: timelineRowEdgesOf(
        rows,
        TimelineGridMetrics(layerRowHeight: _state._rowHeights.lane),
        view: _state._middleViewportHeight,
      ),
      at: {for (final (index, row) in rows.indexed) row.address: index},
    );
  }

  /// [lane] as the table lays it ([_laneSeating]) — null for a lane the
  /// table has not.
  _SeatedLane? _seatedLane(TimelineRowAddress lane) {
    final seating = _laneSeating;
    return switch (seating.at[lane]) {
      final index? => (
        index: index,
        row: seating.rows[index],
        extent: seating.edges.extentOf(index),
        room: seating.edges.roomOf(index),
      ),
      null => null,
    };
  }

  /// The open graph [lane] is drawn in while the row selection is
  /// [selected] ([_pickedRows]).
  TimelineGraphSeat? _seatIn(
    _SeatedLane lane,
    List<TimelineRowAddress> selected,
  ) => _pickedRows(selected)[lane.index].graph;

  /// [_laneSeating]'s rows with the row selection [selected] told to their
  /// graphs ([seatLaneGraphs]) — which lanes each draws as picked. The rail
  /// draws the selection on a listener of its own and a span grows per
  /// pointer move, so what reads the picked lanes reads them here, once a
  /// selection for every lane that asks.
  List<TimelineDisplayRow> _pickedRows(List<TimelineRowAddress> selected) {
    final lanes = _laneSeating.lanes;
    if (_picked case (:final of, :final by, :final rows)
        when identical(of, lanes) && identical(by, selected)) {
      return rows;
    }
    final rows = seatLaneGraphs(
      lanes,
      _laneGraphs,
      selection: selected.toSet(),
    );
    _picked = (of: lanes, by: selected, rows: rows);
    return rows;
  }

  /// What [_pickedRows] last seated: the table's lanes it seated — a build's
  /// own list — and the selection it told them.
  ({
    List<TimelineDisplayRow> of,
    List<TimelineRowAddress> by,
    List<TimelineDisplayRow> rows,
  })?
  _picked;

  /// The lines the pin [key] names on this rail's own rows (I-89 ①), as a
  /// drag in flight shows them: a projection row's lane, by the row's own
  /// id, a cut at a time ([_projectionLines]) — or the one lane of an S
  /// row's, or of a V row's on its lane carrier ([_laneGraphLineOf]).
  /// None for a lane that draws no line, or a row the rail has not.
  Iterable<LaneGraphLine> _laneGraphLinesOf(String key) {
    final lane = parseLaneGroupKey(key);
    final trackId = lane == null
        ? null
        : trackIdOfProjectionRow(lane.layerId);
    final track = trackId == null ? null : _trackNamed(trackId);
    final projection = lane == null || track == null
        ? null
        : _projectionOf(track, lane.layerId);
    if (lane == null || track == null || projection == null) {
      return [?_laneGraphLineOf(key)];
    }
    return [
      for (final line in _projectionLines(
        projection,
        _reachesNow(track),
        lane.laneId,
      ))
        if (line.lane.curve != null) line,
    ];
  }

  /// The projection row [rowId] of [track] as its lanes are drawn from —
  /// the camera row's, or the conte row's at its seat.
  _ProjectionLanes? _projectionOf(Track track, LayerId rowId) {
    if (trackIdOfCameraRow(rowId) != null) {
      return _cameraProjection(track);
    }
    return switch (trackConteRowOf(rowId)) {
      (:final seat, trackId: _) => _conteProjection(track, seat),
      null => null,
    };
  }

  /// [projection]'s lane [laneId] a cut at a time over [reaches] (I-89 ①):
  /// each cut's own lane of the layer the row shows there, valued in that
  /// cut, drawn over the cut's own frames on the track — 「컷 클램핑만
  /// 되도록」 (유저 2026-10-08), the row's strip holding each cut's keys so.
  List<LaneGraphLine> _projectionLines(
    _ProjectionLanes projection,
    List<CameraRowReach> reaches,
    String laneId,
  ) => [
    for (final reach in reaches)
      if (projection.layerOf(reach.entry.cut) case final layer?)
        for (final lane in projection.lanesOf(reach.entry.cut, layer))
          if (lane.laneId == laneId)
            (
              layer: layer,
              lane: lane,
              reach: (start: reach.mediaStart, end: reach.mediaEnd),
            ),
  ];

  /// [track]'s cuts' reaches as a drag in flight lays them — their places
  /// and the のりしろ its transition row asks ([_onTheReaches] hears the
  /// same, row by row).
  List<CameraRowReach> _reachesNow(Track track) {
    final index = _state.widget.project.tracks.indexOf(track);
    final preview = _state.widget.dragPreview?.value;
    final strip = _previewedStripFor(index, preview, [
      for (final entry in buildStoryboardTimelineLayout(_state.widget.project))
        if (entry.trackIndex == index) entry,
    ]);
    return _reachesOn(
      strip.entries,
      timelineDragPreviewGlobalLayerFor(preview, track.transitionLayer.id) ??
          strip.transitionRow,
    );
  }

  /// [entries]' cuts — one track's — with their reaches under the のりしろ
  /// [transitionRow] asks of each ([cameraRowReachesOf]).
  List<CameraRowReach> _reachesOn(
    List<StoryboardTimelineLayoutEntry> entries,
    Layer transitionRow,
  ) => cameraRowReachesOf(
    entries,
    transitionRowSpans(
      transitionRow,
      _state.widget.project.cameraInstructions,
    ),
  );

  /// The lane the pin [key] names on an S row or a V row's lane carrier —
  /// on the track's axis, as a drag in flight shows it
  /// ([laneGraphLineAmong]); null for any other row's.
  LaneGraphLine? _laneGraphLineOf(String key) {
    final preview = _state.widget.dragPreview?.value;
    for (final track in _state.widget.project.tracks) {
      final line =
          laneGraphLineAmong(
            key,
            rows: [
              for (final layer in track.seLayers)
                timelineDragPreviewGlobalLayerFor(preview, layer.id) ?? layer,
            ],
            lanesOf: (layer, open) =>
                _seLanesOf(track, layer, expandedGroupKeys: open),
          ) ??
          laneGraphLineAmong(
            key,
            rows: [_trackLaneCarrier(track)],
            lanesOf: (_, open) => _trackEffectLanes(
              track.copyWith(
                effects: timelineDragPreviewTrackEffectsFor(preview, track.id),
                expandedLaneGroups: {
                  for (final group in open) ?parseLaneGroupKey(group)?.laneId,
                },
              ),
            ),
          );
      if (line != null) {
        return line;
      }
    }
    return null;
  }

  /// The grid this rail's header graphs are drawn in (I-89 ①), a lane
  /// [metrics] high, their keys edited and picked as [drawn]'s lanes' are —
  /// on this rail's frames, the track's: its playhead the global one, its
  /// end the movie's, where the end line stands (graph-key-drag-snaps).
  LaneGraphGrid _laneGraphGridOf(
    TimelineGridMetrics metrics,
    _LanesDrawn drawn,
  ) => (
    frameAxis: (
      geometry: _state._frameGeometry,
      windowBucket: _state._horizontalWindowBucket,
      axis: Axis.horizontal,
      laneExtent: metrics.layerRowHeight,
      playhead: _state.widget.playheadFrame,
      frameCount: movieEndFrames(_state.widget.project),
    ),
    frameAxisController: _state._horizontalController,
    keyPrefix: 'storyboard',
    verbs: _laneGraphVerbs,
    laneEdit: drawn.laneEdit,
    laneRange: drawn.laneRange,
  );

  /// [carrierId]'s [lanes] on the frame side as the table lays them
  /// (I-89 ①): each lane's strip at its extent, and an open graph's lanes
  /// as ONE graph across their unit — the timeline's frame side
  /// ([laneGraphFrameSide]) on this rail's frame axis, each lane drawn as
  /// [drawn] reads it now and the pins this rail's rows hold as guests
  /// ([_laneGraphLinesOf]) — keyed as this rail keys its rows
  /// ([_laneGraphs]). While a graph is open among them it follows the row
  /// selection, which picks what it draws ([_pickedRows]).
  List<Widget> _laneFrameSide(
    LayerId carrierId,
    List<PropertyLaneRow> lanes,
    _LanesDrawn drawn,
  ) {
    final (laneEdit: _, laneRange: _, :linesOf, :strip) = drawn;
    final seating = _laneSeating;
    final first = lanes.isEmpty
        ? null
        : seating.at[LaneRowAddress(carrierId, lanes.first.laneId)];
    if (first == null) {
      return const [];
    }
    final metrics = TimelineGridMetrics(
      layerRowHeight: _state._rowHeights.lane,
    );
    final grid = _laneGraphGridOf(metrics, drawn);
    List<Widget> laid(List<TimelineDisplayRow> rows) => laneGraphFrameSide(
      (
        rows: rows.sublist(first, first + lanes.length),
        first: first,
        edges: seating.edges,
        kept: timelineRowBuiltNow,
      ),
      grid,
      lines: (seat, seated) => laneGraphLines(seat, seated, (
        standing: _state.widget.currentRowHooks?.currentRow,
        moves: _state.widget.dragPreview,
        linesOf: linesOf,
        pinned: _laneGraphs.pinned,
        guestsOf: _laneGraphLinesOf,
      )),
      cells: (row) => strip(row, timelineDisplayRowExtent(row, metrics)),
    );
    final selection = _state.widget.rowSelection;
    final laneRows = seating.rows.sublist(first, first + lanes.length);
    if (selection == null || !laneRows.any((row) => row.graph != null)) {
      return laid(seating.rows);
    }
    return [
      ValueListenableBuilder<List<TimelineRowAddress>>(
        valueListenable: selection,
        builder: (context, selected, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: laid(_pickedRows(selected)),
        ),
      ),
    ];
  }

  /// [track]'s rows, top first, each at its kind's height — every lane as
  /// a row of its own, unseated.
  List<_StoryboardRailSlot> _trackGroupSlots(Track track) {
    final heights = _state._rowHeights;
    final slots = <_StoryboardRailSlot>[];
    // Index 0 is the TOP of the group ([_trackRowBand] accumulates y from
    // here), and the camera section heads it — above the S rows, the way it
    // heads the cut timeline's rows: the CAMERA row first (I-73 ④), stood on
    // by its own address ([trackCameraRowId]) — no track-axis select-drag
    // lands on it — then the transition row.
    //
    // A head wears its row's own id to the column sweep, as its presses act
    // on the row; a headless row — in a gap, or while the host has not
    // wired the head's verbs — has no button to sweep. ↩️The camera row
    // carried none: its eye was the camera VIEW, not a flag of the layer,
    // until it became the layer's own (F-363).
    final headsWired = _state._rows._headVerbsWired;
    if (_showsCameraRow(track)) {
      final rowId = trackCameraRowId(track.id);
      final head = headsWired ? _cameraHeadAt(track)?.layer : null;
      slots.add((
        row: null,
        laneRow: null,
        standRow: LayerRowAddress(rowId),
        bandRow: false,
        lane: false,
        seSlot: null,
        height: heights.camera,
        display: head == null
            ? null
            : TimelineDisplayRow.layer(
                head.copyWith(id: rowId),
                layerIndex: 0,
              ),
        graph: null,
      ));
      // Its lanes, twirled down under it (I-73 ④ⓔ).
      if (_cameraLanesOpen(track)) {
        _addProjectionLaneSlots(slots, track, rowId, _cameraLanes(track));
      }
    }
    if (_showsTransitionRow(track)) {
      slots.add((
        row: LayerRowAddress(track.transitionLayer.id),
        laneRow: null,
        standRow: null,
        bandRow: false,
        lane: false,
        seSlot: null,
        height: heights.transition,
        display: TimelineDisplayRow.layer(track.transitionLayer, layerIndex: 0),
        graph: null,
      ));
    }
    for (final slot in _shownSeSlots(track)) {
      final layer = _trackSeAt(track, slot);
      slots.add((
        row: layer == null ? null : LayerRowAddress(layer.id),
        laneRow: null,
        standRow: null,
        bandRow: false,
        lane: false,
        seSlot: slot,
        height: heights.se,
        display: layer == null
            ? null
            : TimelineDisplayRow.layer(layer, layerIndex: slot),
        graph: null,
      ));
      if (layer != null && _seLanesOpen(track, slot)) {
        // One slot per lane the rail draws ([_seLanes]) — a phantom or a
        // missing slot here would shift every row under it (C5).
        for (final lane in _seLanes(track, slot)) {
          slots.add((
            row: null,
            laneRow: LaneRowAddress(layer.id, lane.laneId),
            standRow: null,
            bandRow: true,
            lane: true,
            seSlot: null,
            height: heights.lane,
            display: TimelineDisplayRow.lane(layer, lane, layerIndex: 0),
            graph: null,
          ));
        }
      }
    }
    // The filter hides the V row as the rail does — the row and its lanes.
    if (_filterAllowsTrackRow(track)) {
      slots.add((
        row: TrackRowAddress(track.id),
        laneRow: null,
        standRow: null,
        bandRow: false,
        lane: false,
        seSlot: null,
        height: _state.widget.trackLaneHeight,
        // Its subject is its TRACK, which its lane carrier stands for.
        display: TimelineDisplayRow.layer(
          _trackLaneCarrier(track),
          layerIndex: 0,
        ),
        graph: null,
      ));
      // The V track's OWN lane rows ([_trackTransformLaneStrips]'s shape):
      // its fx chain, and no Transform group — a track row does not own one
      // ([timelineRowOwnsTransform]). Leaving the removed slots here is
      // exactly how the ring lands on a neighbour: this table is what the
      // bands and the select-drag read, so a slot the rail no longer draws
      // shifts every row under it.
      if (track.lanesExpanded) {
        final carrier = _trackLaneCarrier(track);
        for (final lane in _trackEffectLanes(track)) {
          slots.add((
            row: null,
            laneRow: LaneRowAddress(carrier.id, lane.laneId),
            standRow: null,
            bandRow: true,
            lane: true,
            seSlot: null,
            height: heights.lane,
            display: TimelineDisplayRow.lane(carrier, lane, layerIndex: 0),
            graph: null,
          ));
        }
      }
    }
    // The CONTE rows close the group, under the V row and the V row's own
    // lanes (I-73): one a seat ([_shownConteSeats]). Each is stood on
    // ([_StoryboardRailSlot.standRow]) — no track-axis select-drag lands on
    // it — and carries the columns its head does, once a cut holds a layer
    // at its seat to be that head.
    for (final seat in _shownConteSeats(track)) {
      final rowId = trackConteRowId(track.id, seat: seat);
      final head = headsWired
          ? _inHand(track, _conteRow(track, seat))?.layer
          : null;
      slots.add((
        row: null,
        laneRow: null,
        standRow: LayerRowAddress(rowId),
        bandRow: false,
        lane: false,
        seSlot: null,
        height: heights.conte,
        display: head == null
            ? null
            : TimelineDisplayRow.layer(
                head.copyWith(id: rowId),
                layerIndex: 0,
              ),
        graph: null,
      ));
      // Its lanes (I-73 ④ⓔ), as the camera row's are.
      if (_conteLanesOpen(track, seat)) {
        _addProjectionLaneSlots(
          slots,
          track,
          rowId,
          _conteLanes(track, seat),
        );
      }
    }
    return slots;
  }

  /// A projection row's lane slots — one a lane of [lanes], each stood on
  /// by its address on this rail (I-73 ④ⓔ). A lane selection there names a
  /// cut's layer in the cut's own frames, so the band over it is the cut's
  /// own ([_projectionLaneBand]) — not the track's, which this table lays
  /// across the rows it covers. Its lanes are worn by the ROW, as its labels
  /// wear them: the layer in hand, by the row's own id.
  void _addProjectionLaneSlots(
    List<_StoryboardRailSlot> slots,
    Track track,
    LayerId rowId,
    List<PropertyLaneRow> lanes,
  ) {
    final carrier = _inHand(
      track,
      LayerRowAddress(rowId),
    )?.layer.copyWith(id: rowId);
    for (final lane in lanes) {
      slots.add((
        row: null,
        laneRow: LaneRowAddress(rowId, lane.laneId),
        standRow: null,
        bandRow: false,
        lane: true,
        seSlot: null,
        height: _state._rowHeights.lane,
        display: carrier == null
            ? null
            : TimelineDisplayRow.lane(carrier, lane, layerIndex: 0),
        graph: null,
      ));
    }
  }

  /// One track group's strip rows, mirroring [railRowsForTrack] row for
  /// row (heights must stay in lockstep — the two columns share no
  /// scaffolding), as the rows' window [rows] lays them.
  List<Widget> _stripRowsForTrack(
    Track track,
    int index,
    _TrackStrip strip,
    double width,
    TimelineScale scale,
    List<List<Widget>> trackGlobalRows,
    _WindowedRows rows,
  ) {
    final entries = strip.entries;
    return rows.lay([
      // The CAMERA row heads the group (I-73 ④) — a row of the CUTS, so it
      // is built on them as this step lays them, like the V row below.
      if (_showsCameraRow(track))
        () => [_cameraStripRow(track, strip, width, scale)],
      // Prebuilt from the RAW project outside the drag-preview builder
      // (R10-③): identical instances per step = subtree rebuilds skipped.
      // The transition row and the S rows are both track-global, so both
      // qualify — a cut trim cannot change either.
      for (final unit in trackGlobalRows) () => unit,
      // The filter hides the V row as the rail does — the strip and its
      // lanes with it, or every row under it parts from its label.
      if (_filterAllowsTrackRow(track))
        () => [
          _StoryboardTrackRow(
            trackId: track.id,
            layoutEntries: entries,
            onRowFramePress: _state.widget.onRowFramePress,
            onDropMediaAsset: _state.widget.onDropMediaAsset,
            acceptsMediaAsset: _state.widget.acceptsMediaAsset,
            laneHeight: _state.widget.trackLaneHeight,
            width: width,
            stripEdges: _state.widget.stripEdges,
            cutMove: _state.widget.cutMove,
            cutSelect: _state.widget.cutSelect,
            thumbnails: _state.widget.thumbnails,
            timelineScale: scale,
            frameGeometry: _state._frameGeometry,
            hoveredCutId: _state._hoveredCutId,
            standingCutId: _state._standing.standingCutOn(track),
            windowBucket: _state._horizontalWindowBucket,
            railSweepAt: _railSweepOn(track.id),
            showSeconds: _state.widget.showSeconds,
            projectFrameRate: _state.widget.projectFrameRate,
            linkedCutIds: _state.widget.linkedCutIds,
            onOpenCutLinks: _state.widget.onOpenCutLinks,
            onEditCutBlock: _state.widget.onEditCutBlock,
          ),
          if (track.lanesExpanded)
            for (final strip in _trackTransformLaneStrips(
              track,
              index,
              entries,
              width,
              scale,
            ))
              strip,
        ],
      ..._conteStripRows(track, strip, width, scale),
    ]);
  }

  /// The CAMERA row's strip (I-73 ④): the cuts as this step lays them, each
  /// over its own frames under the のりしろ the track's transition row asks
  /// of it ([_onTheReaches]) — and its lanes under it while it is twirled
  /// open (④ⓔ).
  Widget _cameraStripRow(
    Track track,
    _TrackStrip strip,
    double width,
    TimelineScale scale,
  ) => _onTheReaches(track, strip, (reaches) {
    final row = _StoryboardCameraRow(
      trackId: track.id,
      reaches: reaches,
      width: width,
      height: _state._rowHeights.camera,
      timelineScale: scale,
      frameGeometry: _state._frameGeometry,
      windowBucket: _state._horizontalWindowBucket,
      viewportWidth: _state._stripViewportWidth,
      instructionDefById: _state.widget.project.cameraInstructions.defById,
      onRowFramePress: _state.widget.onRowFramePress,
      onCameraCutPress: _state.widget.onCameraCutPress,
      onEditCameraCell: _state.widget.onEditCameraCell,
      stripSelect: _state.widget.stripSelect,
    );
    if (!_cameraLanesOpen(track)) {
      return row;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        ..._projectionLaneStrips(
          track,
          _cameraProjection(track),
          _cameraLanes(track),
          (reaches: reaches, width: width, scale: scale),
        ),
      ],
    );
  });

  /// [build] with [track]'s cuts' own frames as this step lays them, under
  /// the のりしろ the track's transition row asks of each
  /// ([cameraRowReachesOf]). That row is read as the drag in flight shows it
  /// — a cut edge drag carries an O.L in [strip], and a span's own edge drag
  /// is the row's global preview — so a のりしろ follows the hand on these
  /// rows alone: the span's edge drag rebuilds no other strip.
  Widget _onTheReaches(
    Track track,
    _TrackStrip strip,
    Widget Function(List<CameraRowReach> reaches) build,
  ) {
    final dragPreview = _state.widget.dragPreview ?? _noDragPreview;
    return SlicedListenableBuilder<Layer>(
      listenable: dragPreview,
      slice: () =>
          timelineDragPreviewGlobalLayerFor(
            dragPreview.value,
            track.transitionLayer.id,
          ) ??
          strip.transitionRow,
      builder: (context, transitionRow) =>
          build(_reachesOn(strip.entries, transitionRow)),
    );
  }

  /// [track]'s camera row as its lanes are drawn from (I-73 ④ⓔ): each cut's
  /// camera, and the camera's lanes ([cameraPropertyLanes]) — valued on the
  /// cut's canvas, which a header graph draws its line of (I-89 ①).
  _ProjectionLanes _cameraProjection(Track track) => (
    rowId: trackCameraRowId(track.id),
    keyName: 'camera',
    markPrefix: 'storyboard-camera',
    layerOf: (cut) => cut.layers.cameraLayer,
    lanesOf: (cut, camera) => cameraPropertyLanes(
      camera,
      cut.camera.track,
      canvasSize: cut.canvasSize,
    ),
    eyeOf: _cutsOwnEye,
  );

  /// A projection row's lane strips (I-73 ④ⓔ), row for row with their
  /// labels — one a lane of [lanes] — over the cuts' own frames as [strip]
  /// lays them: a lane is held to each cut as its row is, and swept through
  /// the timeline's lane selection ([_laneGestureCallbacksFor]). And an open
  /// header graph over them as the table lays it ([_laneFrameSide]), each
  /// lane a line a cut, held to the cut as its keys are (I-89 ①).
  List<Widget> _projectionLaneStrips(
    Track track,
    _ProjectionLanes projection,
    List<PropertyLaneRow> lanes,
    ({List<CameraRowReach> reaches, double width, TimelineScale scale}) strip,
  ) {
    final laneRange = _laneGestureCallbacksFor(
      track,
      projection: projection.rowId,
    );
    return _laneFrameSide(projection.rowId, lanes, (
      // The edits its labels key by: the cut stood in's (I-73 ④ⓔ). A
      // handle on the line of a cut not stood in writes that cut, where it
      // is: the lane verbs read and write the cut holding the row
      // (I-89-Q23, 유저: 「강제로 서있게해서 고치는건 … 불편함」).
      laneEdit: _state.widget.cutLaneEdit,
      laneRange: laneRange,
      linesOf: (row) =>
          _projectionLines(projection, strip.reaches, row.lane!.laneId),
      strip: (row, height) => _StoryboardProjectionLaneRow(
        trackId: track.id,
        projection: projection,
        laneId: row.lane!.laneId,
        reaches: strip.reaches,
        width: strip.width,
        height: height,
        timelineScale: strip.scale,
        frameGeometry: _state._frameGeometry,
        windowBucket: _state._horizontalWindowBucket,
        viewportWidth: _state._stripViewportWidth,
        onRowFramePress: _state.widget.onRowFramePress,
        onCameraCutPress: _state.widget.onCameraCutPress,
        laneRange: laneRange,
      ),
    ));
  }

  /// The CONTE rows' strips — the conte's, and an attach row's at each seat
  /// the rail shows ([_shownConteSeats]) — on the cuts as this step lays
  /// them: a cut's panels ride its trim and its move with the block above
  /// them. Each row's lanes run under it while it is twirled open (I-73
  /// ④ⓔ), over the cuts' own frames as the camera row's do.
  List<_RowUnit> _conteStripRows(
    Track track,
    _TrackStrip strip,
    double width,
    TimelineScale scale,
  ) => [
    for (final seat in _shownConteSeats(track))
      () => [
        _StoryboardConteRow(
          trackId: track.id,
          seat: seat,
          layoutEntries: strip.entries,
          width: width,
          height: _state._rowHeights.conte,
          timelineScale: scale,
          frameGeometry: _state._frameGeometry,
          windowBucket: _state._horizontalWindowBucket,
          showSeconds: _state.widget.showSeconds,
          projectFrameRate: _state.widget.projectFrameRate,
          onRowFramePress: _state.widget.onRowFramePress,
          stripEdges: _state.widget.stripEdges,
          stripSelect: _state.widget.stripSelect,
          onCreateStoryboardLayer: _state.widget.onCreateStoryboardLayer,
          onEditConteBlock: _state.widget.onEditConteBlock,
          conteCelContent: _state.widget.conteCelContent,
          stepsUntilShown: _state.widget.stepsUntilShown,
        ),
        if (_conteLanesOpen(track, seat))
          _onTheReaches(
            track,
            strip,
            (reaches) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _projectionLaneStrips(
                track,
                _conteProjection(track, seat),
                _conteLanes(track, seat),
                (reaches: reaches, width: width, scale: scale),
              ),
            ),
          ),
      ],
  ];

  /// One track's SE strip rows (+ twirled-down audio/transform lanes) —
  /// track-global content, built from the base layout.
  List<List<Widget>> _seStripRowsForTrack(
    Track track,
    int index,
    double width,
    TimelineScale scale,
  ) {
    final moveRows = _seMoveRows(track);
    final heights = _state._rowHeights;
    Widget seRow(int slot, Layer? layer) => _StoryboardSeRow(
      railSweepAt: _railSweepOn(track.id),
      moveRows: moveRows,
      trackIndex: index,
      slot: slot,
      layer: layer,
      width: width,
      height: heights.se,
      timelineScale: scale,
      projectFrameRate: _state.widget.projectFrameRate,
      frameGeometry: _state._frameGeometry,
      windowBucket: _state._horizontalWindowBucket,
      viewportWidth: _state._stripViewportWidth,
      showSeconds: _state.widget.showSeconds,
      audioPeaksFor: _state.widget.audioPeaksFor,
      soundCannotPlay: _state.widget.soundCannotPlay,
      seClipMarkerTooltip: _state.widget.seClipMarkerTooltip,
      onRowFramePress: _state.widget.onRowFramePress,
      onDropMediaAsset: _state.widget.onDropMediaAsset,
      acceptsMediaAsset: _state.widget.acceptsMediaAsset,
      onEditSeEntry: _state.widget.onEditSeEntry,
      seCommaDrag: _state.widget.seCommaDrag,
      seSelect: _state.widget.seSelect,
    );
    return [
      for (final slot in _shownSeSlots(track)) [
        // The gate keeps comma drags LIVE here (UI-R7 #7): these rows
        // are built once per panel build (identical instances across
        // cut-trim preview steps, R10-③), so without it an SE edge drag
        // only showed on release. It resolves the GLOBAL preview form —
        // this strip renders the track axis, not the active-cut clone.
        switch (_state._seDisplayAt(track, slot)) {
          null => seRow(slot, null),
          final globalLayer => TimelineDragPreviewRowGate(
            dragPreview: _state.widget.dragPreview,
            layer: globalLayer,
            useGlobalForm: true,
            rowBuilder: (context, layer) => seRow(slot, layer),
          ),
        },
        if (_seLanesOpen(track, slot))
          for (final strip in _seLaneStrips(track, index, slot, width, scale))
            strip,
      ],
    ];
  }

  /// The V track's own strip rows.
  ///
  /// No Transform strips: a track row does not own a Transform group
  /// ([timelineRowOwnsTransform]). The pose lanes and the cut-fade envelope
  /// that used to sit here are gone — the fade is F.I/F.O spans on the
  /// transition row, whose strip is always visible instead of two twirls deep.
  List<Widget> _trackTransformLaneStrips(
    Track track,
    int trackIndex,
    List<StoryboardTimelineLayoutEntry> entries,
    double width,
    TimelineScale scale,
  ) {
    final carrier = _trackLaneCarrier(track);
    final laneEdit = _state.widget.trackLaneEditFor?.call(track);
    final preview = _state.widget.dragPreview;
    // [lane] as the chain [effects] a drag in flight shows re-derives it.
    PropertyLaneRow shownAs(
      PropertyLaneRow lane,
      List<LayerEffect>? effects,
    ) => effects == null
        ? lane
        : laneAsPreviewed(
            lane,
            _trackEffectLanes(track.copyWith(effects: effects)),
          );
    // The fx chain's strips, row for row with its labels — the rail and the
    // strips share no scaffolding, so the two lists are built from the SAME
    // lane list to keep them in lockstep.
    final laneRange = _laneGestureCallbacksFor(track);
    return _laneFrameSide(carrier.id, _trackEffectLanes(track), (
      laneEdit: laneEdit,
      laneRange: laneRange,
      linesOf: (row) => [
        (
          layer: carrier,
          lane: shownAs(
            row.lane!,
            timelineDragPreviewTrackEffectsFor(preview?.value, track.id),
          ),
          reach: null,
        ),
      ],
      // A key-move drag previews on the scoped channel. Nothing previewed
      // here before 2026-08-08 because nothing could MOVE here: the
      // lane-move path looked at a track's transform and never at its
      // effects, so the drag answered "nothing to move" and refused in
      // silence.
      strip: (row, height) => _followingTrackEffects(
        track,
        (effects) => _StoryboardLaneStripRow(
          rowKey: 'storyboard-track-lane-row-$trackIndex-${row.lane!.laneId}',
          carrier: carrier,
          lane: shownAs(row.lane!, effects),
          width: width,
          height: height,
          timelineScale: scale,
          laneEdit: laneEdit,
          laneRange: _laneGestureCallbacksFor(
            track,
            band: _bandOnLane(
              track,
              LaneRowAddress(carrier.id, row.lane!.laneId),
            ),
          ),
        ),
      ),
    ));
  }

  /// [build] with [track]'s EFFECT chain as the drag channel shows it — a
  /// key range slid along it, a value scrubbed in it — or null as
  /// committed, rebuilt whenever the channel moves. The V row's strips and
  /// its labels both read the chain through here, so the two cannot come to
  /// show different chains mid-drag.
  Widget _followingTrackEffects(
    Track track,
    Widget Function(List<LayerEffect>? previewed) build,
  ) => ValueListenableBuilder<TimelineDragPreview?>(
    valueListenable:
        _state.widget.dragPreview ??
        const AlwaysStoppedAnimation<TimelineDragPreview?>(null),
    builder: (context, preview, _) =>
        build(timelineDragPreviewTrackEffectsFor(preview, track.id)),
  );

  /// One S row's lane strips, row for row with [_seLaneLabels]: CONTINUOUS
  /// rows on the slot layer's OWN track-global axis (R4b — the per-cut spans
  /// emitted cut-LOCAL frames into these global layers' lanes: an offset
  /// accident past the first cut, structurally gone with the spans) — and
  /// an open header graph over its lanes ([_laneFrameSide]), each lane in
  /// the GLOBAL form a drag in flight shows it in, as the labels show it
  /// (F-195).
  List<Widget> _seLaneStrips(
    Track track,
    int trackIndex,
    int slot,
    double width,
    TimelineScale scale,
  ) {
    final layer = _trackSeAt(track, slot);
    if (layer == null) {
      return const [];
    }
    final preview = _state.widget.dragPreview;
    // The S row's lanes take the range gesture too (R5 ③b). Their keys are
    // the TRACK's, on the global axis this rail already draws — so the span
    // is stated where it lives, and the cut panel is the one that has a
    // window to fit it into.
    final laneRange = _laneGestureCallbacksFor(track);
    return _laneFrameSide(layer.id, _seLanes(track, slot), (
      laneEdit: _state.widget.layerLaneEdit,
      laneRange: laneRange,
      linesOf: (row) {
        final shown =
            timelineDragPreviewGlobalLayerFor(preview?.value, row.layer.id) ??
            row.layer;
        return [
          (
            layer: shown,
            lane: previewedLaneRow(
              row: row,
              previewLayer: shown,
              lanesForLayer: (shown) => _seLanesOf(track, shown),
            ),
            reach: null,
          ),
        ];
      },
      strip: (row, height) => _followingSeLane(
        track,
        layer,
        row.lane!,
        (_, lane) => _StoryboardLaneStripRow(
          rowKey:
              'storyboard-se-lane-row-$trackIndex-${slot + 1}-${lane.laneId}',
          carrier: layer,
          lane: lane,
          width: width,
          height: height,
          timelineScale: scale,
          laneRange: _laneGestureCallbacksFor(
            track,
            band: _bandOnLane(track, LaneRowAddress(layer.id, lane.laneId)),
          ),
        ),
      ),
    ));
  }

  /// The base-layout TRACK-GLOBAL strip rows per track index — the transition
  /// row and the SE rows (+ their twirled-down lanes), one unit of the rows'
  /// window each — computed once per PANEL build and reused across
  /// drag-preview steps.
  List<List<List<Widget>>> _trackGlobalStripRowsByTrack() {
    final layoutEntries = buildStoryboardTimelineLayout(_state.widget.project);
    final scale = _state._scale;
    final contentWidth = _state._contentWidthFor(layoutEntries, scale);
    return [
      for (var index = 0; index < _state.widget.project.tracks.length; index++)
        [
          // Heads the group, matching the rail's row order.
          if (_showsTransitionRow(_state.widget.project.tracks[index]))
            [
              _state._rows.transitionStripRow(
                _state.widget.project.tracks[index],
                contentWidth,
                scale,
              ),
            ],
          ..._seStripRowsForTrack(
            _state.widget.project.tracks[index],
            index,
            contentWidth,
            scale,
          ),
        ],
    ];
  }
}

/// A track's cuts as a drag preview lays them — what its rows are built
/// from ([_StoryboardRailRows.trackGroupSection]): the same strip while it
/// is the same cut objects in the same order, which is all a layout is
/// made of ([cutSpansOfCuts]).
///
/// So a step that moves none of them — an SE row's comma, whose rows are
/// built outside (R10-③) — rebuilds none of its rows. 🔬Measured
/// (storyboard-drags-lay-out-alone, 10-01): it rebuilt every one of them at
/// every step.
///
/// It carries the track's transition row as the same preview shows it — a
/// cut edge drag takes the O.L across the boundary it crosses — for the
/// camera row, which reads its cuts' のりしろ off it (I-73 ④). ⛔The row is
/// not part of what makes two strips the same: a cut edge drag moves a cut
/// anyway, and a span's own edge drag is heard by the camera row itself
/// ([_StoryboardRailRows._cameraStripRow]'s slice reads the preview). In
/// the strip's sameness it would rebuild every row of the track at every
/// step of that drag, and the mutation run (10-09) found no row drawing
/// differently for it.
final class _TrackStrip {
  const _TrackStrip(this.entries, this.transitionRow);

  final List<StoryboardTimelineLayoutEntry> entries;
  final Layer transitionRow;

  /// The entries' own sameness — the very cuts at the same places
  /// ([StoryboardTimelineLayoutEntry.==]), which the same cut objects in the
  /// same order always are.
  @override
  bool operator ==(Object other) =>
      other is _TrackStrip && listEquals(other.entries, entries);

  @override
  int get hashCode => Object.hashAll(entries);
}

/// Where a sweep pressed on [anchor] has reached, the pointer [crossOffset]
/// from the top of its row, in a table of rows [heights] tall: how many of
/// the NAMED rows ([rows]) lie from the anchor's to the row it stands over
/// — walked back toward the anchor past rows [addresses] names none for
/// (a graph's room, a slot nobody stands on), so a drag that ends on one
/// reaches as far as it legibly can rather than collapsing to nothing.
/// Null when the anchor is not in the table.
({List<TimelineRowAddress> rows, int rowDelta})? _sweptOver(
  List<TimelineRowAddress?> addresses,
  List<double> heights, {
  required TimelineRowAddress anchor,
  required double crossOffset,
}) {
  final anchorIndex = addresses.indexOf(anchor);
  if (anchorIndex < 0) {
    return null;
  }
  var at = rowIndexForCrossOffset(
    crossOffset: crossOffset,
    anchorIndex: anchorIndex,
    heights: heights,
  );
  final towardAnchor = at >= anchorIndex ? -1 : 1;
  while (at != anchorIndex && addresses[at] == null) {
    at += towardAnchor;
  }
  final rows = addresses.nonNulls.toList();
  return (
    rows: rows,
    rowDelta: rows.indexOf(addresses[at]!) - rows.indexOf(anchor),
  );
}
