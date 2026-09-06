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

  /// Rebuilds [builder] whenever the storyboard playhead moves — the
  /// cursor-layer subscription the ruler and the playhead overlay already
  /// take (F-19).
  ///
  /// Returns the built widget UNWRAPPED when there is no playhead channel:
  /// a host that never publishes one has nothing for the subscription to
  /// listen to, and a builder that never fires is a rebuild boundary paid
  /// for nothing.
  Widget _playheadFollowing(Widget Function(int? globalFrame) builder) {
    final playhead = _state.widget.playheadFrame;
    if (playhead == null) {
      return builder(null);
    }
    return ValueListenableBuilder<int?>(
      valueListenable: playhead,
      builder: (context, globalFrame, _) => builder(globalFrame),
    );
  }

  /// The shared lane substrate speaks Layer; label-only rows with no real
  /// layer (an SE slot that is empty) ride a synthetic carrier — its id
  /// only feeds the widget keys.
  Layer _vLaneCarrier(String seed) =>
      Layer(id: LayerId('v-$seed'), name: 'V', frames: const []);

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
      valueAt: (effectId, parameterId, frameIndex) {
        for (final effect in track.effects) {
          if (effect.id == effectId) {
            return effect.parameterOf(parameterId).resolveAt(frameIndex);
          }
        }
        return 0;
      },
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

  /// One S row's Transform-group lanes, header first, valued against the
  /// row's own TRACK-owned layer (the same raw-track resolution the
  /// timeline's value column uses — fx bypass never touches authoring
  /// values). No cut is consulted: the row belongs to the track.
  List<PropertyLaneRow> _seTransformLanes(Track track, int slot, Layer? layer) {
    final expanded = _state.widget.expandedTransformGroups.contains(
      StoryboardPanel.seRowKey(track, slot),
    );
    // The display size comes from the SESSION, exactly as the V row's
    // lanes take it — never from "the cut that happens to be open", which
    // made another track's S row show its values as defaults.
    final displaySize = _state.widget.poseDisplaySize;
    final lanes = layer == null
        ? transformPropertyLanes(
            TransformTrack.empty(),
            includeAnchorAndOpacity: true,
          )
        : transformPropertyLanes(
            layer.transformTrack,
            includeAnchorAndOpacity: true,
            poseAt: displaySize == null
                ? null
                : (frame) => layer.transformTrack.resolveAt(
                    frameIndex: frame,
                    orElse: () => layerIdentityPose(displaySize),
                  ),
            anchorAt: displaySize == null
                ? null
                : (frame) =>
                      resolveAnchorTrackAt(
                        layer.transformTrack.anchorPoint,
                        frame,
                      ) ??
                      CanvasPoint(
                        x: displaySize.width / 2,
                        y: displaySize.height / 2,
                      ),
            opacityAt: (frame) =>
                resolveOpacityTrackAt(layer.transformTrack.opacity, frame),
          );
    return [
      transformGroupHeader(expanded: expanded),
      if (expanded) ...lanes.where((lane) => !lane.isGroupHeader),
    ];
  }

  /// ㉒ (user, 2026-08-12): the legend's twirl-all — the one control the
  /// storyboard's legend was missing, because the header only draws it when
  /// a host hands it BOTH verbs and this host handed it neither.
  ///
  /// The rows have always twirled; what was absent was the bulk verb over
  /// them. So this is the timeline's [expandAllLanes] transposed onto the
  /// rows THIS rail draws — an S row per SE slot and a V row per track —
  /// rather than a new idea about expansion.
  bool get _anyLanesExpanded =>
      _state.widget.expandedSeAudioRows.isNotEmpty ||
      _state.widget.expandedTransformTracks.isNotEmpty;

  /// Whether the rail can twirl at all: a display-only mount (no hooks) has
  /// nothing for the legend button to act on, so it does not draw one.
  bool get hasLaneTwirls =>
      _state.widget.onToggleSeRowLane != null ||
      _state.widget.onToggleTrackLane != null;

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
    for (var slot = _seSlotCount(track) - 1; slot >= 0; slot -= 1)
      if (_trackSeAt(track, slot) case final layer?)
        TimelineDisplayRow.layer(layer, layerIndex: slot),
  ];

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
              _state.widget.layerFxStateOf?.call(layer.id) != LayerFxState.off,
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
            _state.widget.trackFxStateOf?.call(track) != LayerFxState.off,
      );

  /// C5 (2026-08-17): whether the [slot]th S row's twirl-down shows the
  /// Audio (waveform) lane — the row is twirled open AND the TIMELINE's
  /// own lane law emits one ([seAudioLanesFor]: an SE row with no sounds
  /// imported has no Audio lane there, so it has none here either). The
  /// storyboard used to mount the lane off the twirl alone, which is how
  /// an empty S row showed a waveform strip this rail's twin never draws.
  bool _seAudioLaneOpen(Track track, int slot) {
    if (!_state.widget.expandedSeAudioRows.contains(
      StoryboardPanel.seRowKey(track, slot),
    )) {
      return false;
    }
    final layer = _trackSeAt(track, slot);
    return layer != null && seAudioLanesFor(layer).isNotEmpty;
  }

  /// How tall ONE S ROW stands on the rail: the row, plus its Audio lane
  /// and Transform lanes when twirled open. The same construction
  /// `railRowsForTrack` lays out, read back as a number.
  double _seRowGroupExtent(Track track, int slot) {
    var extent = _seRowHeight;
    if (_state.widget.expandedSeAudioRows.contains(
      StoryboardPanel.seRowKey(track, slot),
    )) {
      if (_seAudioLaneOpen(track, slot)) {
        extent += _audioLaneHeight;
      }
      extent +=
          _seTransformLanes(track, slot, _trackSeAt(track, slot)).length *
          _transformLaneHeight;
    }
    return extent;
  }

  /// How tall one TRACK GROUP stands on the rail: its S rows, its V row,
  /// and its transform lanes when twirled open.
  ///
  /// This — not [StoryboardPanel.trackLaneHeight] — is a V row's drag
  /// pitch. Two V rows are separated by the whole group between them, so
  /// counting in the V row's own 64px moved two tracks per group and the
  /// widget test caught it immediately.
  double _trackGroupExtent(Track track) {
    var extent = _state.widget.trackLaneHeight + _transitionRowHeight;
    for (var slot = 0; slot < _seSlotCount(track); slot += 1) {
      // Through the S row's own accounting, so an open S row is counted
      // once and identically by both drags.
      extent += _seRowGroupExtent(track, slot);
    }
    if (_state.widget.expandedTransformTracks.contains(track.id.value)) {
      extent += _trackOwnLanes(track).length * _transformLaneHeight;
    }
    return extent;
  }

  /// How much of [_trackGroupExtent] stands ABOVE the V row — the rail draws
  /// the transition row and then the S rows before it (④).
  ///
  /// The V row is the handle but the GROUP is the pitch, so the drag has to
  /// be told where the handle sits inside the run; see
  /// [LayerRowDragTarget.grabOffsetWithinRun]. Written as the same sum
  /// [_trackGroupExtent] makes, minus the parts that come after, so the two
  /// cannot drift apart.
  double _trackGroupExtentAboveVRow(Track track) {
    var extent = _transitionRowHeight;
    for (var slot = 0; slot < _seSlotCount(track); slot += 1) {
      extent += _seRowGroupExtent(track, slot);
    }
    return extent;
  }

  /// Which rail row a swipe is over. The rail stacks three kinds and they
  /// do NOT share a subject: a V row's eye is its CUT's picture, while an S
  /// row's and the transition row's are that LAYER's own. One column, two
  /// verbs — so the row carries which it is rather than the column guessing.
  ///
  /// 🚨[layer] null means the V row. It is not "no subject": the V row's
  /// subject is a cut and is looked up per press, because the cut under the
  /// playhead is what its buttons act on (UI-R13 #2). [seSlot] is set only
  /// for an S row, because its lane twirl is addressed by slot rather than
  /// by layer.
  ///
  /// ⛔Naming only V rows was WRONG and the first version did it — a swipe
  /// down the eye column then stepped over every S row it crossed, and the
  /// test did not notice because it only asked about the three cuts. Every
  /// row that HAS the column has to answer; the column decides what it can
  /// paint, by returning null.
  StoryboardRailRow? _railSubjectAtY(double localY) {
    var top = 0.0;
    for (final track in _state.widget.project.tracks) {
      // The rail draws the transition row, then the S rows, then the V row
      // (④) — the same order [_trackGroupExtentAboveVRow] sums.
      if (localY >= top && localY < top + _transitionRowHeight) {
        return (track: track, layer: track.transitionLayer, seSlot: null);
      }
      var slotTop = top + _transitionRowHeight;
      for (var slot = 0; slot < _seSlotCount(track); slot += 1) {
        // The S ROW itself stands at the top of its group; the lanes that
        // follow it are the rest of [_seRowGroupExtent] and carry no column
        // of their own.
        if (localY >= slotTop && localY < slotTop + _seRowHeight) {
          return (track: track, layer: _trackSeAt(track, slot), seSlot: slot);
        }
        slotTop += _seRowGroupExtent(track, slot);
      }
      final vTop = top + _trackGroupExtentAboveVRow(track);
      if (localY >= vTop && localY < vTop + _state.widget.trackLaneHeight) {
        return (track: track, layer: null, seSlot: null);
      }
      top += _trackGroupExtent(track);
    }
    return null;
  }

  /// The same, as the shared swipe wants it. The identity is what the sweep
  /// dedupes by, so it has to separate a track's V row from its S rows.
  RailSwipeRow<StoryboardRailRow>? railRowAtY(double localY) {
    final subject = _railSubjectAtY(localY);
    return subject == null
        ? null
        : (
            row: subject,
            depth: 0,
            id: subject.layer?.id.value ?? 'v-${subject.track.id.value}',
          );
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

    // The cut a V row's buttons act on — the one under the playhead on that
    // track, which is what the row itself draws (UI-R13 #2). A track with no
    // cut there has no subject, so the column reads null and the sweep steps
    // over it.

    return railSwipeColumns<StoryboardRailRow>(
      crossExtent: StoryboardPanel._trackLabelWidth,
      leadingOrigin: 0,
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

  Cut? _cutOf(Track track) {
    final index = _state.widget.project.tracks.indexOf(track);
    return index < 0 ? null : _state._standing.cutAtPlayheadOn(index);
  }

  /// The eye column's value for a row: the layer's eye, or the cut's
  /// picture visibility on a V row — null where the column has no verb.
  bool? _rowEyeOn(StoryboardRailRow row) {
    final toggleCutVisibility = _state.widget.onToggleCutPictureVisibility;
    final cutVisibleOf = _state.widget.cutPictureVisibleOf;
    final toggleLayerVisibility = _state.widget.onToggleLayerVisibility;
    final layer = row.layer;
    if (layer != null) {
      return toggleLayerVisibility == null
          ? null
          : layerRailEyeIsOn(layer, live: _state.widget.layerEyeOnOf);
    }
    if (toggleCutVisibility == null) {
      return null;
    }
    final cut = _cutOf(row.track);
    return cut == null ? null : (cutVisibleOf?.call(cut.id) ?? true);
  }

  void _toggleRowEye(StoryboardRailRow row) {
    final toggleCutVisibility = _state.widget.onToggleCutPictureVisibility;
    final toggleLayerVisibility = _state.widget.onToggleLayerVisibility;
    final layer = row.layer;
    if (layer != null) {
      toggleLayerVisibility?.call(layer.id);
      return;
    }
    final cut = _cutOf(row.track);
    if (cut != null) {
      toggleCutVisibility?.call(cut.id);
    }
  }

  /// The FX column's value for a row: the layer's FX state where the kind
  /// shows the toggle, the track's on a V row — null where it has no verb.
  bool? _rowFxOn(StoryboardRailRow row) {
    final toggleTrackFx = _state.widget.onToggleTrackFx;
    final trackFxStateOf = _state.widget.trackFxStateOf;
    final toggleLayerFx = _state.widget.onToggleLayerFx;
    final layerFxStateOf = _state.widget.layerFxStateOf;
    final layer = row.layer;
    if (layer != null) {
      return toggleLayerFx == null || !layerKindShowsFxToggle(layer.kind)
          ? null
          : (layerFxStateOf?.call(layer.id) ?? LayerFxState.on) ==
                LayerFxState.on;
    }
    return toggleTrackFx == null || trackFxStateOf == null
        ? null
        : trackFxStateOf(row.track) == LayerFxState.on;
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
  /// an eligible unattached layer row — null elsewhere.
  bool? _rowOnTimesheet(StoryboardRailRow row) {
    final layer = row.layer;
    return layer != null &&
            layerKindEligibleForTimesheetToggle(layer.kind) &&
            layer.attachedToLayerId == null
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
      final hasLanes =
          _seAudioLaneOpen(row.track, slot) ||
          _seTransformLanes(
            row.track,
            slot,
            _trackSeAt(row.track, slot),
          ).isNotEmpty;
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
    final activeCut = _state._standing.activeCutOf(track);
    final seRows = _seRowsFor(track);
    final vRows = _vRowsFor(track, index, activeCut);
    return [
      // The transition row heads the group. It is a FIXTURE like S1/S2 — one
      // per track, always there — so it takes no filter gate and no reorder
      // drag: there is nothing to hide it behind and nowhere to move it to.
      //
      // The band says CAM because the transition row IS a camera-section row
      // ([timelineSectionForLayerKind]) — the label comes from that policy
      // rather than being typed here, so the two rails cannot start naming
      // the same section differently.
      _sectionZoneGroup(
        keyValue: 'storyboard-section-zone-${track.id.value}-transition',
        label: timelineSectionLabel(TimelineSection.camera),
        rows: [_state._rows.transitionLabelRow(track)],
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
    ];
  }

  /// The SE section's rail rows for [track], top slot first: each slot
  /// the filter allows, with its audio lane label and transform lane
  /// labels while the row is expanded.
  List<Widget> _seRowsFor(Track track) {
    final topSlot = _seSlotCount(track) - 1;
    final seRows = <Widget>[
      for (var slot = topSlot; slot >= 0; slot--)
        if (_filterAllowsSeRow(track, slot)) ...[
          _state._rows.seLabelRow(track, slot),
          if (_state.widget.expandedSeAudioRows.contains(
            StoryboardPanel.seRowKey(track, slot),
          )) ...[
            // Audio leads the S twirl-down (the row's main tool, timeline
            // parity); the Transform group sits below, collapsed default.
            // C5: present exactly when the timeline's lane law emits it.
            if (_seAudioLaneOpen(track, slot))
              _StoryboardLaneLabel(
                laneKey:
                    'storyboard-lane-label-'
                    '${track.id.value}'
                    '-s${slot + 1}-audio',
                label: AppText.strings.tlAudioLane,
                icon: Icons.graphic_eq,
                height: _audioLaneHeight,
              ),
            ..._state._rows.transformLaneLabels(
              carrier:
                  _trackSeAt(track, slot) ??
                  _vLaneCarrier('se-${StoryboardPanel.seRowKey(track, slot)}'),
              groupKey: StoryboardPanel.seRowKey(track, slot),
              lanes: _seTransformLanes(track, slot, _trackSeAt(track, slot)),
              laneEdit: _state.widget.layerLaneEdit,
              // The row exists or it does not; the open cut is not part of
              // the question (user, 2026-08-09).
              active: _trackSeAt(track, slot) != null,
              frameCursor: _state.widget.activeCutFrameCursor,
            ),
          ],
        ],
    ];
    return seRows;
  }

  /// The V section's rail rows for [track]: the draggable track label
  /// row (following the playhead), and the track's effect lane rows while
  /// its transform group is expanded.
  List<Widget> _vRowsFor(Track track, int index, Cut? activeCut) {
    final vRows = <Widget>[
      _state._rows.trackDraggable(
        track,
        index,
        // 🚨F-19 (유저 2026-08-24): 「스토리보드패널의 버튼, **룰러 스크럽시
        // 현재 인덱스의 컷에 따라 버튼이 갱신 안되고** … **손 떼야 갱신**되서
        // 활성화되거나 하는데 어떻게 가능한가?」
        //
        // Because of the cursor-layer split, and it was working as built:
        // [_playheadGlobalFrame] moves per scrub move, and only the playhead
        // overlay and the ruler subscribe to it — the panel deliberately does
        // NOT rebuild on a tick (W4). So [_cutAtPlayheadOn] read whatever the
        // frame had been at the last panel rebuild, which during a drag is
        // where the drag STARTED.
        //
        // ★So this row subscribes, the way the overlay does. One row per
        // track rebuilds per move — the cost the ruler beside it already
        // pays — and the alternative (rebuilding the panel) is the very
        // thing the split exists to avoid.
        //
        // ⛔NOT by making the ruler switch the active cut, which is what the
        // report wondered aloud about (「애초에 룰러에 따라 액티브컷 전환하도록
        // 하는게 구조적 해결일까」). The scrub PARKS on purpose — the whole
        // preview machinery (D6's no-flash rules, the territory flag) exists
        // because the active cut does not follow a drag — and switching it
        // per move would put a cut activation on every pointer move.
        _playheadFollowing(
          (_) => StoryboardTrackLabelRow(
            track: track,
            trackLabel: 'V${index + 1}',
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
            activeCut: activeCut,
            // UI-R13 #2: the fx/eye act on THIS track's cut at the current
            // global index (each track independently) — no stand-down, no
            // parked look. A gap simply means no cut exists there: the
            // buttons stay normal and a press is a no-op.
            subjectCut: _state._standing.cutAtPlayheadOn(index) ?? activeCut,
            cutPictureVisibleOf: _state.widget.cutPictureVisibleOf,
            onToggleCutPictureVisibility:
                _state.widget.onToggleCutPictureVisibility,
            // R9 #21: the track's own display columns.
            trackFxState:
                _state.widget.trackFxStateOf?.call(track) ?? LayerFxState.on,
            onToggleTrackFx: _state.widget.onToggleTrackFx == null
                ? null
                : () => _state.widget.onToggleTrackFx!(track),
            trackOpacity: _state.widget.trackOpacityOf?.call(track) ?? 1.0,
            onTrackOpacityChanged: _state.widget.onTrackOpacityChanged == null
                ? null
                : (opacity) =>
                      _state.widget.onTrackOpacityChanged!(track, opacity),
            onTrackOpacityChangeEnd:
                _state.widget.onTrackOpacityChangeEnd == null
                ? null
                : (opacity) =>
                      _state.widget.onTrackOpacityChangeEnd!(track, opacity),
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
          _state._rows.transformLaneLabels(
            carrier: Layer(
              id: trackTransformLaneCarrierId(track.id),
              name: 'V',
              frames: const [],
            ),
            groupKey: track.id.value,
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

  /// Per-row hairline under every STRIP row (UI-R5 storyboard unification:
  /// the timeline grid's row lines reach the frame area here too). Drawn
  /// as a foreground so row heights stay untouched (rail lockstep).
  ///
  /// ⛔The ink is READ from [timelineGridRowSeamInk], not spelled again
  /// here. It used to be a bare `BorderSide(outlineVariant)` — the same
  /// colour and, by `BorderSide`'s default width, the same 1.0, so the two
  /// rails matched on screen and a pixel test would have passed. That is
  /// exactly the copy that goes wrong LATER: change the law and only the
  /// timeline follows it. 유저 F-18: 「스토리보드패널 타임라인이랑 그리드
  /// 다를거같은데 절대 다르지 않도록 통일」 — "절대" is about the next
  /// change, not about today's pixels.
  Widget _stripRowLine(Widget row) {
    final seam = timelineGridRowSeamInk(Theme.of(_state.context).colorScheme);
    return Container(
      foregroundDecoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: seam.color, width: seam.strokeWidth),
        ),
      ),
      child: row,
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
    final dragPreview = _state.widget.dragPreview;
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: dragPreview == null
              ? _stripRowsForTrack(
                  track,
                  index,
                  entries,
                  width,
                  scale,
                  trackGlobalRows,
                )
              : [
                  ValueListenableBuilder<TimelineDragPreview?>(
                    valueListenable: dragPreview,
                    builder: (context, preview, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _stripRowsForTrack(
                        track,
                        index,
                        _previewedEntriesFor(index, preview, entries),
                        width,
                        scale,
                        trackGlobalRows,
                      ),
                    ),
                  ),
                ],
        ),
        Positioned.fill(
          child: IgnorePointer(child: _trackRangeBand(track, scale)),
        ),
        Positioned.fill(
          child: IgnorePointer(child: _trackLaneRangeBand(track, scale)),
        ),
        // Above both bands: standing and selected are two statements, and
        // the ring must stay readable inside a span that covers its row.
        Positioned.fill(
          child: IgnorePointer(
            child: _state._standing.trackStandingCellRing(track, scale),
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
  ) {
    if (preview == null) {
      return committed;
    }
    final project = projectWithTimelineDragPreview(
      _state.widget.project,
      preview,
    );
    if (identical(project, _state.widget.project)) {
      return committed;
    }
    return [
      for (final entry in buildStoryboardTimelineLayout(project))
        if (entry.trackIndex == trackIndex) entry,
    ];
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
    Track track, {
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
              decoration: timelineRangeSelectionBandDecoration,
            ),
          ),
        ),
      ],
    );
  }

  /// The LANE selection's band over this group's property-lane rows —
  /// the V track's own (R4b) and its S rows' alike (R5 ③b). The
  /// timeline's R27 #14 overlay language: ONE band with the cell
  /// selection's decoration across the spanned lane rows, drawn above the
  /// strips. Covered rows come from the SAME predicate the gesture and
  /// markers use ([laneSelectionCoversBandRow]), so the header row bands
  /// on a whole-group span, collapsed state included.
  ///
  /// The band is drawn straight from the selection's own numbers: both
  /// kinds of row here are on the track's global axis, which is the axis
  /// this rail measures in.
  Widget _trackLaneRangeBand(Track track, TimelineScale scale) {
    final selectionListenable = _state.widget.laneRange?.selection;
    if (selectionListenable == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<TimelineLaneSelection?>(
      valueListenable: selectionListenable,
      builder: (context, selection, _) {
        if (selection == null || scale.pixelsPerFrame <= 0) {
          return const SizedBox.shrink();
        }
        final subjectId = selection.layerId;
        return _rangeBand(
          track,
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
            width:
                (selection.endIndexExclusive - selection.startIndex) *
                scale.pixelsPerFrame,
          ),
          label: (
            key: 'storyboard-lane-range-selection',
            label: AppText.strings.tlSelectedLaneRange,
          ),
        );
      },
    );
  }

  /// The band itself: [selection.spanRows] top to bottom — intervening
  /// twirled-open lanes ride under it, exactly as the timeline's band
  /// covers lanes between two covered layer rows.
  Widget _trackRangeBand(Track track, TimelineScale scale) {
    final selectedRange =
        _state.widget.cutSelect?.selectedRange ??
        _state.widget.seSelect?.selectedRange;
    if (selectedRange == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<TrackFrameRangeSelection?>(
      valueListenable: selectedRange,
      builder: (context, selection, _) {
        if (selection == null ||
            selection.trackId != track.id ||
            scale.pixelsPerFrame <= 0) {
          return const SizedBox.shrink();
        }
        final spanned = selection.spanRows.toSet();
        return _rangeBand(
          track,
          // C②: an escalated lane drag's span carries LANE rows too — the
          // band covers them exactly as the timeline's covers the lanes it
          // swept.
          covers: (slot) {
            final address = slot.row ?? slot.laneRow;
            return address != null && spanned.contains(address);
          },
          span: (
            left: scale.leftForFrame(selection.startFrame),
            width: selection.lengthFrames * scale.pixelsPerFrame,
          ),
          label: (
            key: 'storyboard-frame-range-selection',
            label: AppText.strings.tlSelectedFrameRange,
          ),
        );
      },
    );
  }

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
  TimelineLaneRangeCallbacks? _laneGestureCallbacksFor(Track track) {
    final host = _state.widget.laneRange;
    if (host == null) {
      return null;
    }
    return TimelineLaneRangeCallbacks(
      selection: host.selection,
      onSelectUpdate:
          (layerId, laneId, anchorIndex, headIndex, headCrossOffset) {
            // Call-time reads (the stale-closure rule): the LIVE geometry.
            final geometry = _trackGroupRowGeometry(track);
            final addresses = [
              for (final slot in geometry) slot.row ?? slot.laneRow,
            ];
            final anchorAt = addresses.indexOf(LaneRowAddress(layerId, laneId));
            var rowDelta = 0;
            if (anchorAt >= 0) {
              rowDelta =
                  rowIndexForCrossOffset(
                    crossOffset: headCrossOffset,
                    anchorIndex: anchorAt,
                    heights: [for (final slot in geometry) slot.height],
                  ) -
                  anchorAt;
            }
            final escalation = resolveLaneSpanEscalationOverAddresses(
              rows: addresses,
              layerId: layerId,
              laneId: laneId,
              rowDelta: rowDelta,
            );
            if (escalation == null) {
              host.onSelectUpdate(
                layerId,
                laneId,
                anchorIndex,
                headIndex,
                resolveInGroupHeadLane(
                  rows: addresses,
                  layerId: layerId,
                  laneId: laneId,
                  rowDelta: rowDelta,
                ),
                // The span off the SAME drawn rows — 절대명령 2.
                laneSpanOverDrawnRows(
                  rows: addresses,
                  layerId: layerId,
                  laneId: laneId,
                  headLaneId:
                      resolveInGroupHeadLane(
                        rows: addresses,
                        layerId: layerId,
                        laneId: laneId,
                        rowDelta: rowDelta,
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
              anchorRow: LaneRowAddress(layerId, laneId),
              spanRows: escalation.spanRows,
            );
          },
      onTapAt: host.onTapAt,
      onTapClear: host.onTapClear,
      onMoveBegin: host.onMoveBegin,
      onMoveUpdate: host.onMoveUpdate,
      onMoveEnd: host.onMoveEnd,
      onMoveCancel: host.onMoveCancel,
    );
  }

  List<_StoryboardRailSlot> _trackGroupRowGeometry(Track track) {
    final slots = <_StoryboardRailSlot>[];
    // Index 0 is the TOP of the group ([_trackRowBand] accumulates y from
    // here), and the transition row heads it — above the S rows, the way the
    // camera section heads the cut timeline's rows.
    slots.add((
      row: LayerRowAddress(track.transitionLayer.id),
      laneRow: null,
      bandRow: false,
      height: _transitionRowHeight,
    ));
    for (var slot = _seSlotCount(track) - 1; slot >= 0; slot--) {
      final layer = _trackSeAt(track, slot);
      slots.add((
        row: layer == null ? null : LayerRowAddress(layer.id),
        laneRow: null,
        bandRow: false,
        height: _seRowHeight,
      ));
      if (_state.widget.expandedSeAudioRows.contains(
        StoryboardPanel.seRowKey(track, slot),
      )) {
        // C5: the audio slot exists exactly when the lane is drawn — a
        // phantom slot here would shift every row under it.
        if (_seAudioLaneOpen(track, slot)) {
          slots.add((
            row: null,
            laneRow: null,
            bandRow: false,
            height: _audioLaneHeight,
          ));
        }
        // The SE transform strips: the group header, plus the property
        // lanes when twirled open ([_seTransformLaneStrips]'s shape).
        void seLane(String laneId) => slots.add((
          row: null,
          laneRow: layer == null ? null : LaneRowAddress(layer.id, laneId),
          bandRow: layer != null,
          height: _transformLaneHeight,
        ));
        seLane(transformGroupHeaderLane.laneId);
        if (_state.widget.expandedTransformGroups.contains(
          StoryboardPanel.seRowKey(track, slot),
        )) {
          for (final laneId in const [
            'anchor-point',
            'position',
            'scale',
            'rotation',
            'opacity',
          ]) {
            seLane(laneId);
          }
        }
      }
    }
    slots.add((
      row: TrackRowAddress(track.id),
      laneRow: null,
      bandRow: false,
      height: _state.widget.trackLaneHeight,
    ));
    // The V track's OWN lane rows ([_trackTransformLaneStrips]'s shape): its fx
    // chain, and no Transform group — a track row does not own one
    // ([timelineRowOwnsTransform]). Leaving the removed slots here is exactly
    // how the ring lands on a neighbour: this table is what the bands and the
    // select-drag read, so a slot the rail no longer draws shifts every row
    // under it.
    if (_state.widget.expandedTransformTracks.contains(track.id.value)) {
      final carrierId = trackTransformLaneCarrierId(track.id);
      for (final lane in _trackEffectLanes(track)) {
        slots.add((
          row: null,
          laneRow: LaneRowAddress(carrierId, lane.laneId),
          bandRow: true,
          height: _transformLaneHeight,
        ));
      }
    }
    return slots;
  }

  /// One track group's strip rows, mirroring [railRowsForTrack] row for
  /// row (heights must stay in lockstep — the two columns share no
  /// scaffolding).
  List<Widget> _stripRowsForTrack(
    Track track,
    int index,
    List<StoryboardTimelineLayoutEntry> entries,
    double width,
    TimelineScale scale,
    List<Widget> trackGlobalRows,
  ) {
    return [
      // Prebuilt from the RAW project outside the drag-preview builder
      // (R10-③): identical instances per step = subtree rebuilds skipped.
      // The transition row and the S rows are both track-global, so both
      // qualify — a cut trim cannot change either.
      ...trackGlobalRows,
      _stripRowLine(
        _StoryboardTrackRow(
          track: track,
          layoutEntries: entries,
          activeCutId: _state.widget.activeCutId,
          onRowFramePress: _state.widget.onRowFramePress,
          laneHeight: _state.widget.trackLaneHeight,
          width: width,
          stripEdges: _state.widget.stripEdges,
          cutMove: _state.widget.cutMove,
          cutSelect: _state.widget.cutSelect,
          stripSelect: _state.widget.stripSelect,
          thumbnailFor: _state.widget.thumbnailFor,
          timelineScale: scale,
          frameGeometry: _state._frameGeometry,
          hoveredCutId: _state._hoveredCutId,
          windowBucket: _state._horizontalWindowBucket,
          viewportWidth: _state._stripViewportWidth,
          railRowAt: (anchorRow, crossOffset) => _railRowAtCrossOffset(
            track: track,
            anchorRow: anchorRow,
            crossOffset: crossOffset,
          ),
          showSeconds: _state.widget.showSeconds,
          projectFrameRate: _state.widget.projectFrameRate,
          onCreateStoryboardLayer: _state.widget.onCreateStoryboardLayer,
        ),
      ),
      if (_state.widget.expandedTransformTracks.contains(track.id.value))
        for (final strip in _trackTransformLaneStrips(
          track,
          index,
          entries,
          width,
          scale,
        ))
          _stripRowLine(strip),
    ];
  }

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
      timelineScale: scale,
      projectFrameRate: _state.widget.projectFrameRate,
      audioPeaksFor: _state.widget.audioPeaksFor,
      onRowFramePress: _state.widget.onRowFramePress,
      onEditSeEntry: _state.widget.onEditSeEntry,
      seCommaDrag: _state.widget.seCommaDrag,
      seSelect: _state.widget.seSelect,
      frameGeometry: _state._frameGeometry,
    );
    return [
      for (var slot = _seSlotCount(track) - 1; slot >= 0; slot--) ...[
        _stripRowLine(
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
        ),
        if (_state.widget.expandedSeAudioRows.contains(
          StoryboardPanel.seRowKey(track, slot),
        )) ...[
          // C5: the waveform strip exists exactly when the timeline's lane
          // law emits an Audio lane ([_seAudioLaneOpen]) — never for a row
          // with nothing imported.
          if (_seAudioLaneOpen(track, slot))
            _stripRowLine(
              _StoryboardAudioLaneRow(
                trackIndex: index,
                slot: slot,
                layer: _state._seDisplayAt(track, slot),
                layoutEntries: entries,
                width: width,
                timelineScale: scale,
                projectFrameRate: _state.widget.projectFrameRate,
                audioPeaksFor: _state.widget.audioPeaksFor,
                seClipMarkerTooltip: _state.widget.seClipMarkerTooltip,
                activeCutId: _state.widget.activeCutId,
                onSetAudioClipOffset: _state.widget.onSetAudioClipOffset,
              ),
            ),
          for (final strip in _seTransformLaneStrips(
            track,
            index,
            slot,
            entries,
            width,
            scale,
          ))
            _stripRowLine(strip),
        ],
      ],
    ];
  }

  /// Resolves [laneId] against a transform [track] for one strip span.
  PropertyLaneRow _laneOfTrack(TransformTrack track, String laneId) {
    if (laneId == transformGroupHeaderLane.laneId) {
      return transformGroupHeaderLane;
    }
    return transformPropertyLanes(
      track,
      includeAnchorAndOpacity: true,
    ).firstWhere((lane) => lane.laneId == laneId);
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
    return [
      // The fx chain's strips, row for row with its labels — the rail and
      // the strips share no scaffolding, so the two lists are built from the
      // SAME lane list to keep them in lockstep.
      //
      // A key-move drag previews on the scoped channel. Nothing previewed here
      // before 2026-08-08 because nothing could MOVE here: the lane-move path
      // looked at a track's transform and never at its effects, so the drag
      // answered "nothing to move" and refused in silence.
      ValueListenableBuilder(
        valueListenable:
            _state.widget.dragPreview ??
            const AlwaysStoppedAnimation<TimelineDragPreview?>(null),
        builder: (context, preview, _) {
          final previewEffects = preview is BlockMoveDragPreview
              ? preview.previewTrackEffects
              : null;
          final previewed = previewEffects?[track.id];
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
                  timelineScale: scale,
                  laneEdit: laneEdit,
                  laneRange: _laneGestureCallbacksFor(track),
                ),
            ],
          );
        },
      ),
    ];
  }

  /// One S row's Transform strip rows: CONTINUOUS key-marker rows on the
  /// slot layer's OWN track-global axis (R4b — the per-cut spans emitted
  /// cut-LOCAL frames into these global layers' lanes: an offset accident
  /// past the first cut, structurally gone with the spans).
  List<Widget> _seTransformLaneStrips(
    Track track,
    int trackIndex,
    int slot,
    List<StoryboardTimelineLayoutEntry> entries,
    double width,
    TimelineScale scale,
  ) {
    final rowKey = StoryboardPanel.seRowKey(track, slot);
    final expanded = _state.widget.expandedTransformGroups.contains(rowKey);
    final layer = _trackSeAt(track, slot);
    Widget strip(String laneId) => layer == null
        ? SizedBox(
            key: ValueKey<String>(
              'storyboard-se-lane-row-$trackIndex-${slot + 1}-$laneId',
            ),
            width: width,
            height: _transformLaneHeight,
          )
        : _StoryboardLaneStripRow(
            rowKey: 'storyboard-se-lane-row-$trackIndex-${slot + 1}-$laneId',
            carrier: layer,
            lane: _laneOfTrack(layer.transformTrack, laneId),
            width: width,
            timelineScale: scale,
            laneEdit: _state.widget.layerLaneEdit,
            // The S row's lanes take the range gesture too (R5 ③b). Their
            // keys are the TRACK's, on the global axis this rail already
            // draws — so the span is stated where it lives, and the cut
            // panel is the one that has a window to fit it into.
            laneRange: _laneGestureCallbacksFor(track),
          );
    return [
      strip(transformGroupHeaderLane.laneId),
      if (expanded) ...[
        strip('anchor-point'),
        strip('position'),
        strip('scale'),
        strip('rotation'),
        strip('opacity'),
      ],
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
          _stripRowLine(
            _state._rows.transitionStripRow(
              _state.widget.project.tracks[index],
              contentWidth,
              scale,
            ),
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
