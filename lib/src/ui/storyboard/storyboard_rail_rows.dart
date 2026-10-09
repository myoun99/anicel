part of '../storyboard_panel.dart';

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
  /// axis the keys live on.
  List<PropertyLaneRow> _trackEffectLanes(Track track) {
    if (track.effects.isEmpty) {
      return const [];
    }
    return effectPropertyLanes(
      track.effects,
      isExpanded: (effectId) => _state.widget.expandedTransformGroups.contains(
        _StoryboardPanelState.trackEffectGroupKey(track, effectId),
      ),
      valueAt: (effectId, parameterId, frameIndex) => effectParameterValueAt(
        track.effects,
        effectId,
        parameterId,
        frameIndex,
      ),
    );
  }

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
          expanded: _state.widget.expandedTransformGroups.contains(
            track.id.value,
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
  /// C5 (2026-08-17) holds by construction: the Audio lane is in the list
  /// exactly when the timeline's lane law emits one (`seAudioLanesFor` —
  /// nothing for a row with no sounds imported). The storyboard once mounted
  /// it off the twirl alone, and an empty S row showed a waveform strip its
  /// timeline twin never draws.
  List<PropertyLaneRow> _seLanes(Track track, int slot) {
    final layer = _trackSeAt(track, slot);
    return layer == null ? const [] : _seLanesOf(track, layer);
  }

  /// [_seLanes] read off [layer] — the S row as committed, or as a lane edit
  /// in flight shows it (its labels re-derive through here, F-195).
  List<PropertyLaneRow> _seLanesOf(Track track, Layer layer) {
    return propertyLanesForRow(
      layer: layer,
      rows: track.seLayers,
      expandedGroupKeys: _state.widget.expandedTransformGroups,
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
  bool get _anyLanesExpanded =>
      _state.widget.expandedSeAudioRows.isNotEmpty ||
      _state.widget.expandedTransformTracks.isNotEmpty ||
      _state.widget.project.tracks.any(
        (track) =>
            _cameraLanesOpen(track) ||
            _shownConteSeats(track).any((seat) => _conteLanesOpen(track, seat)),
      );

  /// Whether the rail can twirl at all: a display-only mount (no hooks) has
  /// nothing for the legend button to act on, so it does not draw one.
  bool get hasLaneTwirls =>
      _state.widget.onToggleSeRowLane != null ||
      _state.widget.onToggleTrackLane != null ||
      _state.widget.onToggleLayerLanes != null;

  void expandAllLanes() => _setAllLanes(expanded: true);

  void collapseAllLanes() => _setAllLanes(expanded: false);

  /// Toggles every lane row that is not already [expanded].
  ///
  /// ⛔THE `contains` GUARD IS THE VERB. It looks redundant — the button
  /// only says EXPAND while nothing is open — but it is what makes this an
  /// expansion rather than a per-row toggle, and the nested group set can
  /// leave a rail mixed: a blind sweep would close the one row you had
  /// opened by hand while it opened its neighbours. Written once per
  /// direction, the two guards were the same sentence with the sense
  /// flipped, and only one of them could be right about it.
  void _setAllLanes({required bool expanded}) {
    final toggleSe = _state.widget.onToggleSeRowLane;
    final toggleTrack = _state.widget.onToggleTrackLane;
    final toggleLayer = _state.widget.onToggleLayerLanes;
    for (final track in _state.widget.project.tracks) {
      if (toggleSe != null) {
        for (var slot = 0; slot < _seSlotCount(track); slot += 1) {
          final open = _state.widget.expandedSeAudioRows.contains(
            StoryboardPanel.seRowKey(track, slot),
          );
          if (open != expanded) {
            toggleSe(track, slot);
          }
        }
      }
      if (toggleTrack != null) {
        final open = _state.widget.expandedTransformTracks.contains(
          track.id.value,
        );
        if (open != expanded) {
          toggleTrack(track);
        }
      }
      if (toggleLayer != null) {
        _setProjectionLanes(track, toggleLayer, expanded: expanded);
      }
    }
  }
  /// [track]'s projection rows' twirls turned to [expanded] (I-73 ④ⓔ): the
  /// camera row's, and each conte row's that has lanes to show — each
  /// through the layer its twirl turns ([_cameraTwirlOf], [_conteTwirlOf]).
  void _setProjectionLanes(
    Track track,
    ValueChanged<LayerId> toggleLayer, {
    required bool expanded,
  }) {
    final camera = _cameraTwirlOf(track);
    if (camera != null && _cameraLanesOpen(track) != expanded) {
      toggleLayer(camera);
    }
    for (final seat in _shownConteSeats(track)) {
      final row = _conteTwirlOf(track, seat);
      if (row != null &&
          _conteLanes(track, seat).isNotEmpty &&
          _conteLanesOpen(track, seat) != expanded) {
        toggleLayer(row);
      }
    }
  }

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
  /// the timeline puts that row's kind in — the camera section.
  ///
  /// ⚠️ONE question for the three places that lay the row out — the row
  /// table, the rail's labels and the strips — or a hidden row would part a
  /// label from its strip by a row, the filter's lesson below.
  bool _showsTransitionRow(Track track) =>
      _sectionShown(timelineSectionForLayerKind(track.transitionLayer.kind));

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

  /// [_cameraHeadOf] with the cut it is the camera of.
  ({Cut cut, Layer layer})? _cameraHeadAt(Track track) {
    final activeCutId = _state.widget.activeCutId;
    if (activeCutId == null) {
      return null;
    }
    for (final cut in track.cuts) {
      if (cut.id == activeCutId) {
        final camera = cut.layers.cameraLayer;
        return camera == null ? null : (cut: cut, layer: camera);
      }
    }
    return null;
  }

  /// Whether [track]'s camera row has its lanes twirled down (I-73 ④ⓔ):
  /// whether a camera of its cuts has — a track's cameras twirl as one,
  /// their head being one (I-73-camera-row-Q1, and F-302's law for the rows
  /// that wear one head), so the row stays open across a gap, where no
  /// head is there to ask.
  bool _cameraLanesOpen(Track track) {
    final open = _state.widget.expandedLaneLayerIds;
    return open.isNotEmpty &&
        track.cuts.any(
          (cut) => open.contains(cut.layers.cameraLayer?.id),
        );
  }

  /// The camera [track]'s camera row's twirl turns — its cameras turn as
  /// one ([_cameraLanesOpen]): an open one while the row is open, so the
  /// turn shuts them all, else the head's, else the track's first.
  LayerId? _cameraTwirlOf(Track track) {
    final cameras = [
      for (final cut in track.cuts) ?cut.layers.cameraLayer?.id,
    ];
    final open = _state.widget.expandedLaneLayerIds;
    return cameras.where(open.contains).firstOrNull ??
        _cameraHeadOf(track)?.id ??
        cameras.firstOrNull;
  }

  /// The lanes [track]'s camera row twirls down: the timeline's camera
  /// lanes ([cameraPropertyLanes]) of the camera of the cut the session
  /// stands in, valued there — or, in a gap, the same lanes of the track's
  /// first camera, with nothing to read their values in.
  List<PropertyLaneRow> _cameraLanes(Track track) {
    final head = _cameraHeadAt(track);
    if (head != null) {
      return cameraPropertyLanes(
        head.layer,
        head.cut.camera.track,
        canvasSize: head.cut.canvasSize,
      );
    }
    for (final cut in track.cuts) {
      if (cut.layers.cameraLayer case final camera?) {
        return cameraPropertyLanes(camera, cut.camera.track, canvasSize: null);
      }
    }
    return const [];
  }

  /// Whether [track]'s conte row at [seat] has its lanes twirled down
  /// (I-73 ④ⓔ): whether a row at its seat has — the rows that wear one head
  /// twirl as one (F-302, [RailView.followHeads]).
  bool _conteLanesOpen(Track track, int seat) {
    final open = _state.widget.expandedLaneLayerIds;
    return open.isNotEmpty &&
        track.cuts.any((cut) => open.contains(conteRowAtSeat(cut, seat)?.id));
  }

  /// The row the conte row at [seat]'s twirl turns — the rows at its seat
  /// turn as one ([_conteLanesOpen]): an open one while the row is open, so
  /// the turn shuts them all, else the head's.
  LayerId? _conteTwirlOf(Track track, int seat) {
    final rows = [for (final cut in track.cuts) ?conteRowAtSeat(cut, seat)?.id];
    final open = _state.widget.expandedLaneLayerIds;
    return rows.where(open.contains).firstOrNull ?? rows.firstOrNull;
  }

  /// The cut the session stands in on [track], with its row at [seat] of
  /// its conte group — null in a gap, on another track, or where the cut
  /// holds no row there.
  ({Cut cut, Layer layer})? _conteStoodAt(Track track, int seat) {
    final activeCutId = _state.widget.activeCutId;
    for (final cut in track.cuts) {
      if (cut.id == activeCutId) {
        final row = conteRowAtSeat(cut, seat);
        return row == null ? null : (cut: cut, layer: row);
      }
    }
    return null;
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
  /// in the cut the session stands in, valued there — or, where there is
  /// none, the head's, with nothing to read their values in. A row riding
  /// the conte has none, as on the timeline.
  List<PropertyLaneRow> _conteLanes(Track track, int seat) {
    final stood = _conteStoodAt(track, seat);
    if (stood != null) {
      return _conteRowLanes(stood.cut, stood.layer, valued: true);
    }
    final head = conteHeadAt(track.cuts, seat);
    return head == null
        ? const []
        : _conteRowLanes(head.cut, head.row, valued: false);
  }

  /// [track]'s conte row at [seat] as its lanes are drawn from (I-73 ④ⓔ):
  /// each cut's row at that seat, and every lane of it — each groups'
  /// members whatever the twirls, so the row for a lane finds it in every
  /// cut.
  _ProjectionLanes _conteProjection(Track track, int seat) {
    final keyName = _StoryboardRowsAndLabels.conteLabelKeyName(seat);
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
        valueSourceAt: null,
        poseCentre: null,
      ),
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
  /// attach rows above the conte, the conte, the ones below it
  /// ([conteSeatsOf]) — under the V row (I-73): its section is the one the
  /// timeline puts the kind in, and the legend's filter judges each row as
  /// it judges every row ([_filterAllowsConteSeat]). The conte's own row is
  /// there whether or not a cut has a conte layer yet — a cut with none
  /// wears the button that makes one there. An attach row is there while
  /// some cut holds one at its seat and the group is not folded.
  ///
  /// 🚨ONE LIST for the three places that lay these rows out — the row
  /// table, the rail's labels and the strips — as [_shownSeSlots] is.
  List<int> _shownConteSeats(Track track) {
    if (!_sectionShown(timelineSectionForLayerKind(LayerKind.storyboard))) {
      return const [];
    }
    final base = conteHeadRowAt(track.cuts, 0);
    final folded =
        base != null &&
        _state.widget.collapsedAttachBaseIds.contains(base.id);
    return [
      for (final seat in folded ? const [0] : conteSeatsOf(track.cuts))
        if (_filterAllowsConteSeat(track, seat)) seat,
    ];
  }

  /// Whether the legend's filter lets the conte row at [seat] show
  /// ([_filterAllowsProjectionRow]) — with no head while no cut holds a
  /// layer there.
  bool _filterAllowsConteSeat(Track track, int seat) =>
      _filterAllowsProjectionRow(
        LayerRowAddress(trackConteRowId(track.id, seat: seat)),
        head: conteHeadRowAt(track.cuts, seat),
        kind: LayerKind.storyboard,
      );

  /// One track group's rail rows in TIMELINE order (R6 B3, R7-④): the S
  /// rows (each with its twirled-down Audio lane and Transform group)
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
  double _seRowGroupExtent(Track track, int slot) {
    var extent = 0.0;
    var inRun = false;
    for (final row in _trackGroupRowGeometry(track)) {
      if (row.railRow?.seSlot == slot) {
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

  /// Which rail rows a swipe SEGMENT crosses. The rail stacks three kinds
  /// and they do NOT share a subject: a V row's buttons are its TRACK's,
  /// while an S row's and the transition row's are that LAYER's own. One
  /// column, two verbs — so the row carries which it is rather than the
  /// column guessing.
  ///
  /// 🚨[layer] null means the V row. It is not "no subject": the V row's
  /// subject is its track. (↩️Its eye's was the cut under the playhead,
  /// looked up per press — UI-R13 #2 — until the eye left the row with
  /// I-73; the eye column reads null there now, and a sweep down it steps
  /// over the V rows.) [seSlot] is set only for an S row, because its lane
  /// twirl is addressed by slot rather than by layer.
  ///
  /// ⛔Naming only V rows was WRONG and the first version did it — a swipe
  /// down the eye column then stepped over every S row it crossed, and the
  /// test did not notice because it only asked about the three cuts. Every
  /// row that HAS the column has to answer; the column decides what it can
  /// paint, by returning null.
  ///
  /// 🚨★★★AND IT WALKS A STRETCH, NOT A POINT (F-66; the reason is in
  /// [RailColumnSwipe.rowsIn]). THIS is the rail the walk exists for — it
  /// stacks a transition row, S rows and a V row at three different heights
  /// with the lane groups between them, so no division names its rows and
  /// no sampling step is short enough to be safe.
  ///
  /// ⚠️It still stops at the far end of the segment, so a press near the top
  /// of a hundred-track board costs what it always did rather than the whole
  /// board.
  ///
  /// 🚨IT WALKS THE TABLE THE RAIL IS DRAWN FROM ([_trackGroupRowGeometry]).
  /// It kept a sum of its own and counted the S rows from slot 0, while the
  /// rail draws the TOP slot first — so with two S rows a stroke that stopped
  /// on S2 hid S1 and left S2 alone (found by text-scale-storyboard-rows).
  List<RailSwipeRow<StoryboardRailRow>> railRowsIn(double fromY, double toY) {
    final lo = fromY <= toY ? fromY : toY;
    final hi = fromY <= toY ? toY : fromY;
    final rows = <RailSwipeRow<StoryboardRailRow>>[];
    var top = 0.0;
    for (final track in _state.widget.project.tracks) {
      for (final row in _trackGroupRowGeometry(track)) {
        if (top > hi) {
          return rows;
        }
        // A lane carries no column of its own, so the walk steps OVER it —
        // the thing a fixed sampling step could never be trusted to do. The
        // identity is what the sweep dedupes by, so it has to separate a
        // track's V row from its S rows.
        final subject = row.railRow;
        if (subject != null && top + row.height > lo) {
          rows.add((
            row: subject,
            depth: 0,
            id: subject.layer?.id.value ?? 'v-${subject.track.id.value}',
          ));
        }
        top += row.height;
      }
    }
    return rows;
  }

  /// What THIS rail can toggle, handed to the ONE construction every rail
  /// shares ([railSwipeColumns]). 유저 2026-08-29: 「버튼이면 다 가능하도록」·
  /// 「로직적으로 다른규칙 두지말고 통일」 — which columns exist and where
  /// their bands fall stopped being this rail's business, and the two it was
  /// silently missing (the sheet toggle and the lane twirl) came back with
  /// the move.
  ///
  /// ⚠️[leadingOrigin] is 0: this rail's row plate starts at the rail's own
  /// edge and pads only on the right, unlike the layer rail's bordered plate.
  List<RailToggleColumn<StoryboardRailRow>> _railSwipeColumns() {
    final toggleTimesheet = _state.widget.onToggleLayerTimesheet;
    final toggleTrackLane = _state.widget.onToggleTrackLane;
    final toggleSeRowLane = _state.widget.onToggleSeRowLane;
    return railSwipeColumns<StoryboardRailRow>(
      crossExtent: _state._naturalRailWidth,
      columns: layerRailColumnWidthsIn(_state.context),
      leadingOrigin: 0,
      hasBlendColumn: StoryboardPanel.railHasBlendColumn,
      visibility: (valueOf: _rowEyeOn, toggle: _toggleRowEye),
      // The transition row draws no fx switch, and a kind that shows none
      // draws none either — both read null, which is the same answer the row
      // builder gives by mounting nothing.
      fx: (valueOf: _rowFxOn, toggle: _toggleRowFx),
      // ⛔The V row mounts NO sheet toggle, so it reads null here — the same
      // rule an attach row follows on the layer rail.
      timesheet: toggleTimesheet == null
          ? null
          : (valueOf: _rowOnTimesheet, toggle: _toggleRowTimesheet),
      // Two verbs again, and a third row kind with neither: the V row's
      // twirl opens the TRACK's transform lanes, an S row's opens that
      // SLOT's audio and transform lanes, and the transition row has none.
      laneToggle: toggleTrackLane == null && toggleSeRowLane == null
          ? null
          : (valueOf: _rowLaneOpen, toggle: _toggleRowLane),
    );
  }

  /// The eye column's value for a row: the layer's eye — null where the
  /// column has no verb, which is the V row too since its eye left (I-73).
  bool? _rowEyeOn(StoryboardRailRow row) {
    final layer = row.layer;
    return layer == null || _state.widget.onToggleLayerVisibility == null
        ? null
        : layerRailEyeIsOn(layer, live: _state.widget.layerEyeOnOf);
  }

  void _toggleRowEye(StoryboardRailRow row) {
    final layer = row.layer;
    if (layer != null) {
      _state.widget.onToggleLayerVisibility?.call(layer.id);
    }
  }

  /// The FX column's value for a row: the layer's FX state where the kind
  /// shows the toggle, the track's on a V row — null where it has no verb,
  /// which is an attach row too: it wears its base's switch
  /// ([isAttachedLayer]; no organizer folder is a row of this rail).
  bool? _rowFxOn(StoryboardRailRow row) {
    final toggleTrackFx = _state.widget.onToggleTrackFx;
    final trackFxStateOf = _state.widget.trackFxStateOf;
    final toggleLayerFx = _state.widget.onToggleLayerFx;
    final layerFxStateOf = _state.widget.layerFxStateOf;
    final layer = row.layer;
    if (layer != null) {
      return toggleLayerFx == null ||
              !layerKindShowsFxToggle(layer.kind) ||
              isAttachedLayer(layer)
          ? null
          : fxEnabledFromState(layerFxStateOf?.call(layer.id));
    }
    return toggleTrackFx == null || trackFxStateOf == null
        ? null
        : fxEnabledFromState(trackFxStateOf(row.track));
  }

  void _toggleRowFx(StoryboardRailRow row) {
    final toggleTrackFx = _state.widget.onToggleTrackFx;
    final toggleLayerFx = _state.widget.onToggleLayerFx;
    final layer = row.layer;
    if (layer != null) {
      toggleLayerFx?.call(layer.id);
      return;
    }
    toggleTrackFx?.call(row.track);
  }

  /// The timesheet column's value: whether the layer is on the sheet, for
  /// an eligible unattached layer row — null elsewhere, and on a conte row:
  /// its head mounts no sheet toggle
  /// ([_StoryboardRowsAndLabels.conteLabelRow]).
  bool? _rowOnTimesheet(StoryboardRailRow row) {
    final layer = row.layer;
    return layer != null &&
            row.conteSeat == null &&
            layerCarriesTimesheetToggle(layer)
        ? (_state.widget.layerOnTimesheetOf?.call(layer.id) ??
              layer.onTimesheet)
        : null;
  }

  void _toggleRowTimesheet(StoryboardRailRow row) {
    final toggleTimesheet = _state.widget.onToggleLayerTimesheet;
    final layer = row.layer;
    if (layer != null) {
      toggleTimesheet?.call(layer.id);
    }
  }

  /// The lane column's value: an SE row's lane state where it has lanes,
  /// a V row's transform lanes where the track owns any — null elsewhere.
  bool? _rowLaneOpen(StoryboardRailRow row) {
    final toggleTrackLane = _state.widget.onToggleTrackLane;
    final toggleSeRowLane = _state.widget.onToggleSeRowLane;
    final slot = row.seSlot;
    if (slot != null) {
      final hasLanes = _seLanes(row.track, slot).isNotEmpty;
      return toggleSeRowLane == null || !hasLanes
          ? null
          : (_state.widget.seRowLaneOpenOf?.call(row.track, slot) ??
                _state.widget.expandedSeAudioRows.contains(
                  StoryboardPanel.seRowKey(row.track, slot),
                ));
    }
    if (row.layer != null) {
      // The transition row: no twirl at all.
      return null;
    }
    return toggleTrackLane == null || _trackOwnLanes(row.track).isEmpty
        ? null
        : (_state.widget.trackLaneOpenOf?.call(row.track) ??
              _state.widget.expandedTransformTracks.contains(
                row.track.id.value,
              ));
  }

  void _toggleRowLane(StoryboardRailRow row) {
    final toggleTrackLane = _state.widget.onToggleTrackLane;
    final toggleSeRowLane = _state.widget.onToggleSeRowLane;
    final slot = row.seSlot;
    if (slot != null) {
      toggleSeRowLane?.call(row.track, slot);
      return;
    }
    if (row.layer == null) {
      toggleTrackLane?.call(row.track);
    }
  }

  List<Widget> railRowsForTrack(Track track, int index) {
    final seRows = _seRowsFor(track);
    final vRows = _vRowsFor(track, index);
    final camRows = [
      if (_showsCameraRow(track)) ...[
        _state._rows.cameraLabelRow(track),
        if (_cameraLanesOpen(track)) ..._cameraLaneLabels(track),
      ],
      if (_showsTransitionRow(track)) _state._rows.transitionLabelRow(track),
    ];
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
        ),
      // A section with no rows left draws no zone: an empty SE band would
      // be a label over nothing once the filter took its rows.
      if (seRows.isNotEmpty)
        _sectionZoneGroup(
          keyValue: 'storyboard-section-zone-${track.id.value}-se',
          label: 'SE',
          rows: seRows,
        ),
      if (_filterAllowsTrackRow(track))
        _sectionZoneGroup(
          keyValue: 'storyboard-section-zone-${track.id.value}-v',
          label: 'V',
          rows: vRows,
        ),
      // The CONTE row, directly under the V row whose cuts it reads (I-73,
      // 유저 2026-10-08: 「v행 아래에 콘티행 만들어서 거기서」). The band says
      // what the timeline's says over the same layers — the section their
      // kind sits in ([timelineSectionForLayerKind]).
      if (_shownConteSeats(track) case final seats when seats.isNotEmpty)
        _sectionZoneGroup(
          keyValue: 'storyboard-section-zone-${track.id.value}-conte',
          label: timelineSectionLabel(
            timelineSectionForLayerKind(LayerKind.storyboard),
          ),
          rows: [
            for (final seat in seats) ...[
              _state._rows.conteLabelRow(track, seat),
              if (_conteLanesOpen(track, seat))
                ..._conteLaneLabels(track, seat),
            ],
          ],
        ),
    ];
  }

  /// The SE section's rail rows for [track], top slot first: each slot
  /// the rail shows ([_shownSeSlots]), with its audio lane label and
  /// transform lane labels while the row is expanded.
  List<Widget> _seRowsFor(Track track) => [
    for (final slot in _shownSeSlots(track)) ...[
      _state._rows.seLabelRow(track, slot),
      if (_state.widget.expandedSeAudioRows.contains(
        StoryboardPanel.seRowKey(track, slot),
      ))
        ..._seLaneLabels(track, slot),
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
    return _state._rows.laneLabels(
      carrier: layer,
      groupKeyOf: (lane) => laneGroupKey(layer.id, lane.laneId),
      lanes: _seLanes(track, slot),
      // F-195: a value scrubbed here, or on the timeline's copy of this row,
      // is shown in its GLOBAL form — the axis this rail draws.
      follow: (_, lane, row) => TimelineDragPreviewRowGate(
        dragPreview: _state.widget.dragPreview,
        layer: layer,
        useGlobalForm: true,
        slice: (shown) => laneRowSlice(shown, lane.laneId),
        rowBuilder: (context, shown) => row(
          shown,
          identical(shown, layer)
              ? lane
              : laneAsPreviewed(lane, _seLanesOf(track, shown)),
        ),
      ),
      laneEdit: _state.widget.layerLaneEdit,
      onToggleGroupEnabled: onToggleEnabled == null
          ? null
          : (lane) => onToggleEnabled(layer, lane),
      onResetGroup: onReset == null ? null : (lane) => onReset(layer, lane),
      // The row exists or it does not; the open cut is not part of the
      // question (user, 2026-08-09).
      active: true,
      // An S row's keys are the TRACK's, so its labels read and seek the
      // GLOBAL playhead, as the V rows' do (R4b). ↩️They read the ACTIVE
      // cut's local cursor (#844 carried the frame over as it was): in any
      // cut but the first the value showed at the wrong frame, and the ◆
      // keyed there (F-102).
      frameCursor: _state.widget.playheadFrame,
      onSelectFrame: _state.widget.onSeekGlobalFrame,
    );
  }

  /// The camera row's lane labels, row for row with its lane strips
  /// (I-73 ④ⓔ): the timeline's camera lanes ([_cameraLanes]), on the camera
  /// of the cut the session stands in ([_projectionLaneLabels]) — the row's
  /// head.
  List<Widget> _cameraLaneLabels(Track track) {
    final head = _cameraHeadAt(track);
    final shown =
        head?.layer ??
        track.cuts.map((cut) => cut.layers.cameraLayer).nonNulls.firstOrNull;
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
    final stood = _conteStoodAt(track, seat);
    final shown = stood?.layer ?? conteHeadRowAt(track.cuts, seat);
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
    return _state._rows.laneLabels(
      carrier: labels.shown.copyWith(id: projection.rowId),
      lanes: labels.lanes,
      groupKeyOf: (lane) => laneGroupKey(labels.shown.id, lane.laneId),
      onToggleGroup: _state.widget.onToggleLaneGroupKey,
      follow: stood == null ? null : follow,
      laneEdit: stood == null
          ? null
          : _state.widget.cutLaneEdit?.landingOn(stood.layer),
      onToggleGroupEnabled: stood == null || toggleEnabled == null
          ? null
          : (lane) => toggleEnabled(stood.layer, lane),
      onResetGroup: stood == null || reset == null
          ? null
          : (lane) => reset(stood.layer, lane),
      active: stood != null,
      frameCursor: stood == null ? null : _state.widget.cutFrameCursor,
      onSelectFrame: stood == null || seek == null
          ? null
          : (frame) => seek(stood.cut.id, frame),
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
  Widget _withTrackLaneSplitter(Track track, Widget row) {
    final resize = _state.widget.onResizeTrackLanes;
    if (resize == null) {
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
              'storyboard-track-lane-splitter-${track.id.value}',
            ),
            axis: Axis.horizontal,
            onDragDelta: resize,
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
      _withTrackLaneSplitter(
        track,
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
            track: track,
            trackLabel: _vRowName(index),
            laneHeight: _state.widget.trackLaneHeight,
            laneExpanded: _state.widget.expandedTransformTracks.contains(
              track.id.value,
            ),
            onToggleLane: _state.widget.onToggleTrackLane == null
                ? null
                : () => _state.widget.onToggleTrackLane!(track),
            // V-track selection (UI-R18 #6): tapping selects the track (its
            // playhead-index cut becomes active). The highlight says THIS ROW
            // IS SELECTED — not "the active cut lives here", which is what the
            // cut block's own active border already says, and which could light
            // at the same time as an S row.
            active: _state.widget.selectedRow == TrackRowAddress(track.id),
            onSelectTrack: _state.widget.onSelectTrack == null
                ? null
                : () => _state.widget.onSelectTrack!(track.id),
            // R9 #21: the track's own display column.
            trackFxState:
                _state.widget.trackFxStateOf?.call(track) ?? LayerFxState.on,
            onToggleTrackFx: _state.widget.onToggleTrackFx == null
                ? null
                : () => _state.widget.onToggleTrackFx!(track),
          ),
        ),
      ),
      if (_state.widget.expandedTransformTracks.contains(track.id.value)) ...[
        // No Transform-group labels: a track row does not own one
        // ([timelineRowOwnsTransform]). Its twirl-down is the fx chain alone —
        // the same place a layer keeps its effects, and the same lane
        // substrate. Grabbing a header re-orders the chain, exactly as it does
        // on a layer's rail (the fx-order drag's subject only differs in WHICH
        // chain it names).
        ..._state._rows.draggableTrackEffectRows(
          track,
          _state._rows.laneLabels(
            carrier: Layer(
              id: trackTransformLaneCarrierId(track.id),
              name: 'V',
              frames: const [],
            ),
            groupKeyOf: (lane) {
              final parsed = parseEffectLaneId(lane.laneId);
              return parsed == null
                  ? track.id.value
                  : _StoryboardPanelState.trackEffectGroupKey(
                      track,
                      parsed.effectId,
                    );
            },
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
            laneEdit: _state.widget.trackLaneEditFor?.call(track),
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
            frameCursor: _state.widget.playheadFrame,
            onSelectFrame: _state.widget.onSeekGlobalFrame,
          ),
        ),
      ],
    ];
    return vRows;
  }

  /// One section's rail rows with the ZONE spanning the whole group over
  /// the rows' reserved band slots (UI-R7 #2): S1·S2 read as one SE
  /// sub-zone, exactly like the timeline's run zones.
  Widget _sectionZoneGroup({
    required String keyValue,
    required String label,
    required List<Widget> rows,
  }) {
    return Stack(
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: KeyedSubtree(
            key: ValueKey<String>(keyValue),
            child: SectionBandZone(label: label),
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
    List<Widget> trackGlobalRows,
  ) {
    final dragPreview = _state.widget.dragPreview ?? _noDragPreview;
    return Stack(
      children: [
        // Rebuilt only where the preview moves this track's cuts
        // ([_TrackStrip]).
        SlicedListenableBuilder<_TrackStrip>(
          listenable: dragPreview,
          slice: () => _previewedStripFor(index, dragPreview.value, entries),
          builder: (context, strip) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _stripRowsForTrack(
              track,
              index,
              strip,
              width,
              scale,
              trackGlobalRows,
            ),
          ),
        ),
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
        // precisely so a playhead move re-rasterizes none of them (R12-⑥).
        // Mounted bare inside it, every move repainted every strip — at ten
        // minutes every edge grip of the film and the plate grounds under
        // them, on every playback frame. The timeline's cursor layer rides
        // its own the same way — and a layout of its own besides
        // ([TickLayer]).
        Positioned.fill(
          child: IgnorePointer(
            child: TickLayer(
              child: _state._standing.trackStandingCell(track, scale),
            ),
          ),
        ),
      ],
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

  /// The group's rows in VISUAL order with their heights — mirrored from
  /// [_seStripRowsForTrack] and [_stripRowsForTrack] row for row. A new
  /// row kind must land in both, or the band drifts off its rows.
  /// R9 #25 — the rail row a select-drag's pointer is over.
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
  TimelineRowAddress? _railRowAtCrossOffset({
    required Track track,
    required TimelineRowAddress anchorRow,
    required double crossOffset,
  }) {
    final geometry = _trackGroupRowGeometry(track);
    final anchorIndex = geometry.indexWhere((slot) => slot.row == anchorRow);
    if (anchorIndex < 0) {
      return null;
    }
    final index = rowIndexForCrossOffset(
      crossOffset: crossOffset,
      anchorIndex: anchorIndex,
      heights: [for (final slot in geometry) slot.height],
    );
    // Audio and lane strips take up space but cannot BE a selection head:
    // walk back toward the anchor until a real row turns up, so a drag
    // that lands on one reaches as far as it legibly can instead of
    // collapsing to nothing.
    final step = index >= anchorIndex ? -1 : 1;
    for (var i = index; i >= 0 && i < geometry.length; i += step) {
      final address = geometry[i].row;
      if (address != null) {
        return address;
      }
      if (i == anchorIndex) {
        break;
      }
    }
    return anchorRow;
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
  TimelineLaneRangeCallbacks? _laneGestureCallbacksFor(
    Track track, {
    LayerId? projection,
  }) {
    final host = _state.widget.laneRange;
    if (host == null) {
      return null;
    }
    return TimelineLaneRangeCallbacks(
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
              headRow: escalation.head,
              anchorRow: anchor,
              spanRows: escalation.spanRows,
            );
          },
      onTapAt: host.onTapAt,
      onActivateAt: host.onActivateAt,
      onTapClear: host.onTapClear,
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
  TimelineGridRows gridRows(List<Track> tracks, Color hostGround) {
    final laneGround = timelineLaneGround(hostGround);
    return TimelineGridRows([
      for (final track in tracks)
        for (final slot in _trackGroupRowGeometry(track))
          (extent: slot.height, ground: slot.lane ? laneGround : hostGround),
    ]);
  }

  List<_StoryboardRailSlot> _trackGroupRowGeometry(Track track) {
    final heights = _state._rowHeights;
    final slots = <_StoryboardRailSlot>[];
    // Index 0 is the TOP of the group ([_trackRowBand] accumulates y from
    // here), and the camera section heads it — above the S rows, the way it
    // heads the cut timeline's rows: the CAMERA row first (I-73 ④), stood on
    // by its own address ([trackCameraRowId]) — no track-axis select-drag
    // lands on it — then the transition row.
    //
    // ⚠️It carries no [_StoryboardRailSlot.railRow] yet: the column sweep
    // reads an eye off the layer ([layerRailEyeIsOn]), and the camera row's
    // eye is the camera VIEW, not a flag of the layer — a sweep would spread
    // the opposite of what its first press set.
    if (_showsCameraRow(track)) {
      final rowId = trackCameraRowId(track.id);
      slots.add((
        row: null,
        laneRow: null,
        standRow: LayerRowAddress(rowId),
        bandRow: false,
        lane: false,
        railRow: null,
        height: heights.camera,
      ));
      // Its lanes, twirled down under it (I-73 ④ⓔ).
      if (_cameraLanesOpen(track)) {
        _addProjectionLaneSlots(slots, rowId, _cameraLanes(track));
      }
    }
    if (_showsTransitionRow(track)) {
      slots.add((
        row: LayerRowAddress(track.transitionLayer.id),
        laneRow: null,
        standRow: null,
        bandRow: false,
        lane: false,
        railRow: (
          track: track,
          layer: track.transitionLayer,
          seSlot: null,
          conteSeat: null,
        ),
        height: heights.transition,
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
        railRow: (track: track, layer: layer, seSlot: slot, conteSeat: null),
        height: heights.se,
      ));
      if (layer != null &&
          _state.widget.expandedSeAudioRows.contains(
            StoryboardPanel.seRowKey(track, slot),
          )) {
        // One slot per lane the rail draws ([_seLanes]) — a phantom or a
        // missing slot here would shift every row under it (C5). The Audio
        // lane keeps no lane address, as it had: no key range lands on it.
        for (final lane in _seLanes(track, slot)) {
          final audio = laneIsSeAudio(lane);
          slots.add((
            row: null,
            laneRow: audio ? null : LaneRowAddress(layer.id, lane.laneId),
            standRow: null,
            bandRow: !audio,
            lane: true,
            railRow: null,
            height: heights.lane,
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
        railRow: (track: track, layer: null, seSlot: null, conteSeat: null),
        height: _state.widget.trackLaneHeight,
      ));
      // The V track's OWN lane rows ([_trackTransformLaneStrips]'s shape):
      // its fx chain, and no Transform group — a track row does not own one
      // ([timelineRowOwnsTransform]). Leaving the removed slots here is
      // exactly how the ring lands on a neighbour: this table is what the
      // bands and the select-drag read, so a slot the rail no longer draws
      // shifts every row under it.
      if (_state.widget.expandedTransformTracks.contains(track.id.value)) {
        final carrierId = trackTransformLaneCarrierId(track.id);
        for (final lane in _trackEffectLanes(track)) {
          slots.add((
            row: null,
            laneRow: LaneRowAddress(carrierId, lane.laneId),
            standRow: null,
            bandRow: true,
            lane: true,
            railRow: null,
            height: heights.lane,
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
      final head = conteHeadRowAt(track.cuts, seat);
      slots.add((
        row: null,
        laneRow: null,
        standRow: LayerRowAddress(trackConteRowId(track.id, seat: seat)),
        bandRow: false,
        lane: false,
        railRow: head == null
            ? null
            : (track: track, layer: head, seSlot: null, conteSeat: seat),
        height: heights.conte,
      ));
      // Its lanes (I-73 ④ⓔ), as the camera row's are.
      if (_conteLanesOpen(track, seat)) {
        _addProjectionLaneSlots(
          slots,
          trackConteRowId(track.id, seat: seat),
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
  /// across the rows it covers.
  void _addProjectionLaneSlots(
    List<_StoryboardRailSlot> slots,
    LayerId rowId,
    List<PropertyLaneRow> lanes,
  ) {
    for (final lane in lanes) {
      slots.add((
        row: null,
        laneRow: LaneRowAddress(rowId, lane.laneId),
        standRow: null,
        bandRow: false,
        lane: true,
        railRow: null,
        height: _state._rowHeights.lane,
      ));
    }
  }

  /// One track group's strip rows, mirroring [railRowsForTrack] row for
  /// row (heights must stay in lockstep — the two columns share no
  /// scaffolding).
  List<Widget> _stripRowsForTrack(
    Track track,
    int index,
    _TrackStrip strip,
    double width,
    TimelineScale scale,
    List<Widget> trackGlobalRows,
  ) {
    final entries = strip.entries;
    return [
      // The CAMERA row heads the group (I-73 ④) — a row of the CUTS, so it
      // is built on them as this step lays them, like the V row below.
      if (_showsCameraRow(track))
        _cameraStripRow(track, strip, width, scale),
      // Prebuilt from the RAW project outside the drag-preview builder
      // (R10-③): identical instances per step = subtree rebuilds skipped.
      // The transition row and the S rows are both track-global, so both
      // qualify — a cut trim cannot change either.
      ...trackGlobalRows,
      // The filter hides the V row as the rail does — the strip and its
      // lanes with it, or every row under it parts from its label.
      if (_filterAllowsTrackRow(track)) ...[
        _StoryboardTrackRow(
          track: track,
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
          viewportWidth: _state._stripViewportWidth,
          railRowAt: (anchorRow, crossOffset) => _railRowAtCrossOffset(
            track: track,
            anchorRow: anchorRow,
            crossOffset: crossOffset,
          ),
          showSeconds: _state.widget.showSeconds,
          projectFrameRate: _state.widget.projectFrameRate,
          linkedCutIds: _state.widget.linkedCutIds,
          onOpenCutLinks: _state.widget.onOpenCutLinks,
          onEditCutBlock: _state.widget.onEditCutBlock,
        ),
        if (_state.widget.expandedTransformTracks.contains(track.id.value))
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
    ];
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
      track: track,
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
      builder: (context, transitionRow) => build(
        cameraRowReachesOf(
          strip.entries,
          transitionRowSpans(
            transitionRow,
            _state.widget.project.cameraInstructions,
          ),
        ),
      ),
    );
  }

  /// [track]'s camera row as its lanes are drawn from (I-73 ④ⓔ): each cut's
  /// camera, and the camera's lanes ([cameraPropertyLanes]).
  _ProjectionLanes _cameraProjection(Track track) => (
    rowId: trackCameraRowId(track.id),
    keyName: 'camera',
    markPrefix: 'storyboard-camera',
    layerOf: (cut) => cut.layers.cameraLayer,
    lanesOf: (cut, camera) =>
        cameraPropertyLanes(camera, cut.camera.track, canvasSize: null),
  );

  /// A projection row's lane strips (I-73 ④ⓔ), row for row with their
  /// labels — one a lane of [lanes] — over the cuts' own frames as [strip]
  /// lays them: a lane is held to each cut as its row is, and swept through
  /// the timeline's lane selection ([_laneGestureCallbacksFor]).
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
    return [
      for (final lane in lanes)
        _StoryboardProjectionLaneRow(
          track: track,
          projection: projection,
          laneId: lane.laneId,
          reaches: strip.reaches,
          width: strip.width,
          height: _state._rowHeights.lane,
          timelineScale: strip.scale,
          frameGeometry: _state._frameGeometry,
          windowBucket: _state._horizontalWindowBucket,
          viewportWidth: _state._stripViewportWidth,
          onRowFramePress: _state.widget.onRowFramePress,
          onCameraCutPress: _state.widget.onCameraCutPress,
          laneRange: laneRange,
        ),
    ];
  }

  /// The CONTE rows' strips — the conte's, and an attach row's at each seat
  /// the rail shows ([_shownConteSeats]) — on the cuts as this step lays
  /// them: a cut's panels ride its trim and its move with the block above
  /// them. Each row's lanes run under it while it is twirled open (I-73
  /// ④ⓔ), over the cuts' own frames as the camera row's do.
  List<Widget> _conteStripRows(
    Track track,
    _TrackStrip strip,
    double width,
    TimelineScale scale,
  ) => [
    for (final seat in _shownConteSeats(track)) ...[
      _StoryboardConteRow(
        track: track,
        seat: seat,
        layoutEntries: strip.entries,
        width: width,
        height: _state._rowHeights.conte,
        timelineScale: scale,
        frameGeometry: _state._frameGeometry,
        windowBucket: _state._horizontalWindowBucket,
        viewportWidth: _state._stripViewportWidth,
        showSeconds: _state.widget.showSeconds,
        projectFrameRate: _state.widget.projectFrameRate,
        onRowFramePress: _state.widget.onRowFramePress,
        stripEdges: _state.widget.stripEdges,
        stripSelect: _state.widget.stripSelect,
        onCreateStoryboardLayer: _state.widget.onCreateStoryboardLayer,
        onEditConteBlock: _state.widget.onEditConteBlock,
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
  List<Widget> _seStripRowsForTrack(
    Track track,
    int index,
    List<StoryboardTimelineLayoutEntry> entries,
    double width,
    TimelineScale scale,
  ) {
    final seRowsInDisplayOrder = _seRowsInDisplayOrder(track);
    final heights = _state._rowHeights;
    Widget seRow(int slot, Layer? layer) => _StoryboardSeRow(
      railRowAt: (anchorRow, crossOffset) => _railRowAtCrossOffset(
        track: track,
        anchorRow: anchorRow,
        crossOffset: crossOffset,
      ),
      seRowsInDisplayOrder: seRowsInDisplayOrder,
      trackIndex: index,
      slot: slot,
      layer: layer,
      layoutEntries: entries,
      width: width,
      height: heights.se,
      timelineScale: scale,
      projectFrameRate: _state.widget.projectFrameRate,
      frameGeometry: _state._frameGeometry,
      windowBucket: _state._horizontalWindowBucket,
      viewportWidth: _state._stripViewportWidth,
      showSeconds: _state.widget.showSeconds,
      audioPeaksFor: _state.widget.audioPeaksFor,
      seClipMarkerTooltip: _state.widget.seClipMarkerTooltip,
      onRowFramePress: _state.widget.onRowFramePress,
      onDropMediaAsset: _state.widget.onDropMediaAsset,
      acceptsMediaAsset: _state.widget.acceptsMediaAsset,
      onEditSeEntry: _state.widget.onEditSeEntry,
      seCommaDrag: _state.widget.seCommaDrag,
      seSelect: _state.widget.seSelect,
    );
    return [
      for (final slot in _shownSeSlots(track)) ...[
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
        if (_state.widget.expandedSeAudioRows.contains(
          StoryboardPanel.seRowKey(track, slot),
        ))
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
    final carrier = Layer(
      id: trackTransformLaneCarrierId(track.id),
      name: 'V',
      frames: const [],
    );
    final laneEdit = _state.widget.trackLaneEditFor?.call(track);
    final laneHeight = _state._rowHeights.lane;
    return [
      // The fx chain's strips, row for row with its labels — the rail and
      // the strips share no scaffolding, so the two lists are built from the
      // SAME lane list to keep them in lockstep.
      //
      // A key-move drag previews on the scoped channel. Nothing previewed here
      // before 2026-08-08 because nothing could MOVE here: the lane-move path
      // looked at a track's transform and never at its effects, so the drag
      // answered "nothing to move" and refused in silence.
      _followingTrackEffects(
        track,
        (previewed) {
          final lanes = previewed == null
              ? _trackEffectLanes(track)
              : _trackEffectLanes(track.copyWith(effects: previewed));
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final lane in lanes)
                _StoryboardLaneStripRow(
                  rowKey:
                      'storyboard-track-lane-row-$trackIndex-${lane.laneId}',
                  carrier: carrier,
                  lane: lane,
                  width: width,
                  height: laneHeight,
                  timelineScale: scale,
                  projectFrameRate: _state.widget.projectFrameRate,
                  laneEdit: laneEdit,
                  laneRange: _laneGestureCallbacksFor(track),
                ),
            ],
          );
        },
      ),
    ];
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
  /// accident past the first cut, structurally gone with the spans).
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
    return [
      for (final lane in _seLanes(track, slot))
        _StoryboardLaneStripRow(
          rowKey:
              'storyboard-se-lane-row-$trackIndex-${slot + 1}-${lane.laneId}',
          // The Audio band draws the in-flight take while one rolls (REC1-C,
          // `_seDisplayAt`); the list — and so the strip count — stays the
          // repository row's, in lockstep with the labels.
          carrier: laneIsSeAudio(lane)
              ? (_state._seDisplayAt(track, slot) ?? layer)
              : layer,
          lane: lane,
          width: width,
          height: _state._rowHeights.lane,
          timelineScale: scale,
          projectFrameRate: _state.widget.projectFrameRate,
          // The S row's lanes take the range gesture too (R5 ③b). Their
          // keys are the TRACK's, on the global axis this rail already
          // draws — so the span is stated where it lives, and the cut
          // panel is the one that has a window to fit it into.
          laneRange: _laneGestureCallbacksFor(track),
          audioLane: _state.widget.audioLane,
          audioPeaksFor: _state.widget.audioPeaksFor,
        ),
    ];
  }

  /// The base-layout TRACK-GLOBAL strip rows per track index — the transition
  /// row and the SE rows (+ their twirled-down lanes) — computed once per
  /// PANEL build and reused across drag-preview steps.
  List<List<Widget>> _trackGlobalStripRowsByTrack() {
    final layoutEntries = buildStoryboardTimelineLayout(_state.widget.project);
    final scale = _state._scale;
    final contentWidth = _state._contentWidthFor(
      _state.widget.project,
      layoutEntries,
      scale,
    );
    return [
      for (var index = 0; index < _state.widget.project.tracks.length; index++)
        [
          // Heads the group, matching the rail's row order.
          if (_showsTransitionRow(_state.widget.project.tracks[index]))
            _state._rows.transitionStripRow(
              _state.widget.project.tracks[index],
              contentWidth,
              scale,
            ),
          ..._seStripRowsForTrack(
            _state.widget.project.tracks[index],
            index,
            layoutEntries
                .where((entry) => entry.trackIndex == index)
                .toList(growable: false),
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

  @override
  bool operator ==(Object other) {
    if (other is! _TrackStrip || other.entries.length != entries.length) {
      return false;
    }
    for (var i = 0; i < entries.length; i += 1) {
      if (!identical(entries[i].cut, other.entries[i].cut)) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hashAll([for (final entry in entries) identityHashCode(entry.cut)]);
}
