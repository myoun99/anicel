part of '../storyboard_panel.dart';

/// THIS RAIL'S COLUMN SWEEP: the ONE list every rail sweeps
/// ([timelineSwipeColumns]), over this rail's rows as the timeline's rail
/// holds one ([_StoryboardRailSlot.display]), with what it reads and
/// presses handed across this rail's border — a projection row by its own
/// id to the layer it has in hand, the V row by its lane carrier to its
/// TRACK (I-89 ①ⓒ).
///
/// 🗣️유저 2026-10-13: 「다시 말하지만 이런건 다 콘티패널에도 동일하게
/// 있어야해. 같은 법으로」. ↩️This rail kept a list of its own over a row
/// of its own (`StoryboardRailRow`): the eye, the fx switch, the sheet
/// toggle and the twirl of its S, transition, V and conte rows — the
/// camera row, every lane's group switch and the graph and pin columns
/// stepped over.
class _StoryboardRailSweep {
  _StoryboardRailSweep(this._state);

  final _StoryboardPanelState _state;

  StoryboardPanel get _widget => _state.widget;

  _StoryboardRailRows get _rows => _state._railRows;

  /// Which rail rows a swipe SEGMENT crosses: each that wears a layer
  /// ([_StoryboardRailSlot.display]) — a lane as much as a row — by its
  /// address, which the sweep dedupes by.
  ///
  /// 🚨★★★AND IT WALKS A STRETCH, NOT A POINT (F-66; the reason is in
  /// [RailColumnSwipe.rowsIn]). THIS is the rail the walk exists for — it
  /// stacks rows of five heights with the lanes between them, so no
  /// division names its rows and no sampling step is short enough to be
  /// safe.
  ///
  /// ⚠️It still stops at the far end of the segment, so a press near the top
  /// of a hundred-track board costs what it always did rather than the whole
  /// board.
  ///
  /// 🚨IT WALKS THE TABLE THE RAIL IS DRAWN FROM
  /// ([_StoryboardRailRows._trackGroupRowGeometry]). It kept a sum of its
  /// own and counted the S rows from slot 0, while the rail draws the TOP
  /// slot first — so with two S rows a stroke that stopped on S2 hid S1 and
  /// left S2 alone (found by text-scale-storyboard-rows).
  List<RailSwipeRow<TimelineDisplayRow>> rowsIn(double fromY, double toY) {
    final lo = fromY <= toY ? fromY : toY;
    final hi = fromY <= toY ? toY : fromY;
    final rows = <RailSwipeRow<TimelineDisplayRow>>[];
    var top = 0.0;
    for (final track in _widget.project.tracks) {
      for (final slot in _rows._trackGroupRowGeometry(track)) {
        if (top > hi) {
          return rows;
        }
        if (slot.display case final row? when top + slot.height > lo) {
          rows.add((row: row, id: row.address));
        }
        top += slot.height;
      }
    }
    return rows;
  }

  /// The columns the sweep paints.
  List<RailToggleColumn<TimelineDisplayRow>> columns() =>
      timelineSwipeColumns(hooks: _hooks());

  /// What this rail's rows read and call, handed to the list as a grid
  /// hands its own ([timelineRailSwipeHooks]): each verb called with the
  /// id the row's button calls it with, each read taken off the layer the
  /// row wears ([_held]) — live where the host reads it.
  RailSwipeHooks _hooks() {
    final widget = _widget;
    final groupOnOf = widget.laneGroupOnOf;
    final groupOpenOf = widget.laneGroupOpenOf;
    final groupToggle = widget.onToggleLaneGroupKey;
    final twirl = widget.onToggleLayerLanes;
    return (
      onToggleLayerVisibility: widget.onToggleLayerVisibility,
      layerEyeOnOf: _readHeld(widget.layerEyeOnOf),
      onToggleLayerOnionSkin: widget.onToggleLayerOnionSkin,
      layerOnionSkinEnabledOf: _readHeld(widget.layerOnionSkinEnabledOf),
      onToggleLayerFx:
          widget.onToggleLayerFx == null && widget.onToggleTrackFx == null
          ? null
          : _toggleFx,
      layerFxStateOf: _fxStateOf,
      wearsBaseComposite: _wearsBaseComposite,
      onToggleLaneGroupEnabled:
          widget.onToggleLaneGroupEnabled == null &&
              widget.onToggleTrackEffectEnabled == null
          ? null
          : _toggleGroup,
      laneGroupOnOf: groupOnOf == null
          ? null
          : (rowId, header) => groupOnOf(_held(rowId), header),
      // This rail hands its rows no clip toggle, so they carry none.
      onToggleLayerClip: null,
      layerClipsOf: null,
      onToggleLayerTimesheet: widget.onToggleLayerTimesheet,
      layerOnTimesheetOf: _readHeld(widget.layerOnTimesheetOf),
      onToggleLayerLanes: twirl == null
          ? null
          : (rowId) {
              if (_twirlOf(rowId)?.twirl.id case final turns?) {
                twirl(turns);
              }
            },
      lanesForLayer: (layer) => _twirlOf(layer.id)?.lanes ?? const [],
      laneOpenOf: (rowId) => switch (_twirlOf(rowId)) {
        final drawn? => _rows._openNow(drawn.twirl),
        null => false,
      },
      laneGraphVerbs: _rows._laneGraphVerbs,
      laneGraphsNow: () => switch (widget.laneGraphsNow) {
        final now? => _rows._graphsOnTheRows(now()),
        null => _rows._laneGraphs,
      },
      hands: (
        eye: (row) => !_carriesATrack(row.layer.id),
        fx: (row) => _carriesATrack(row.layer.id)
            ? widget.onToggleTrackFx != null
            : widget.onToggleLayerFx != null,
        timesheet: (row) => handsSheetToggle(row.layer.id),
        groupSwitch: _handsGroupSwitch,
      ),
      foldOf: _foldOf,
      groupFoldOpenOf: _readHeld(widget.groupFoldOpenOf),
      onToggleLaneGroup: groupToggle == null
          ? null
          : (layer, lane) =>
                groupToggle(laneGroupKey(_held(layer.id), lane.laneId)),
      laneGroupOpenOf: groupOpenOf == null
          ? null
          : (rowId, header) => groupOpenOf(_held(rowId), header),
      // A lane row's hand is its label's ([_StoryboardRailRows._laneHandOf]).
      laneHandOf: (row) => switch (_rows._laneHandOf(row.layer.id)) {
        (edit: final edit?, :final cursor) => (
          edit: edit,
          frame: laneRowFrame(cursor),
        ),
        _ => null,
      },
    );
  }

  /// [row]'s group fold, as its label is told
  /// ([_StoryboardRailRows._conteGroupFoldOf]).
  ///
  /// ⛔MUTANT SURVIVES (F-475, 2026-10-27): pressing by the row's own id
  /// reddens nothing — the host's press finds the layer in hand itself
  /// (`layerActedOn`). It presses by the layer in hand anyway, as the
  /// row's own twirl does (`layerIdNow`), so the stroke and the press
  /// cannot part.
  TimelineGroupFold _foldOf(TimelineDisplayRow row) {
    final fold = _rows._conteGroupFoldOf(row.layer.id);
    final toggle = fold.onToggle;
    return (
      has: fold.has,
      expanded: fold.expanded,
      onToggle: toggle == null ? null : (rowId) => toggle(_held(rowId)),
    );
  }

  /// Whether [rowId]'s row is handed the sheet toggle — what its label
  /// mounts the toggle by and the sweep paints by: every row its kind
  /// gives one, but the V row, whose subject is its TRACK, and the camera
  /// row, whose flag is a record of its cut's own (🗣️I-89-Q22, 유저
  /// 2026-10-16: 「시트토글은 카메라는 로컬기록이니까 없음」). The conte rows
  /// take it: their flag is their head's, one for the track's cuts
  /// ([ConteHead.onTimesheet] — Q22: 「글로벌시키고 넣고 머리로 하나」).
  bool handsSheetToggle(LayerId rowId) =>
      !_carriesATrack(rowId) && trackIdOfCameraRow(rowId) == null;

  /// The layer [rowId]'s row wears — a projection row's in hand, every
  /// other row's its own — which the host reads its flags off.
  LayerId _held(LayerId rowId) => _rows._rowInHand(rowId)?.layer.id ?? rowId;

  /// [read] by a row's id, taken off the layer it wears ([_held]).
  bool Function(LayerId rowId)? _readHeld(
    bool Function(LayerId layerId)? read,
  ) => read == null ? null : (rowId) => read(_held(rowId));

  /// Whether [rowId] is the V row's lane carrier — the row whose subject is
  /// its TRACK.
  static bool _carriesATrack(LayerId rowId) =>
      trackIdOfTransformLaneCarrier(rowId) != null;

  /// The fx switch, pressed as the row's label presses it: the V row's its
  /// TRACK's, as the panel holds it at the press; every other row's by its
  /// own id.
  void _toggleFx(LayerId rowId) {
    if (trackIdOfTransformLaneCarrier(rowId) case final trackId?) {
      _rows._actOnTrack(trackId, _widget.onToggleTrackFx);
      return;
    }
    _widget.onToggleLayerFx?.call(rowId);
  }

  /// The fx state a row's switch shows, as its label shows it.
  LayerFxState _fxStateOf(LayerId rowId) {
    final widget = _widget;
    final state = switch (trackIdOfTransformLaneCarrier(rowId)) {
      final trackId? => switch (_rows._trackNamed(trackId)) {
        final track? => widget.trackFxStateOf?.call(track),
        null => null,
      },
      null => widget.layerFxStateOf?.call(_held(rowId)),
    };
    return state ?? LayerFxState.on;
  }

  /// Whether [layer]'s row wears its base's composite, as its label is
  /// told: a projection head's layer in hand, asked of the stack it stands
  /// in.
  bool _wearsBaseComposite(Layer layer) =>
      switch (_rows._rowInHand(layer.id)) {
        (:final cut, layer: final inHand, stood: _)? =>
          attachRowWearsBaseComposite(inHand, cut.layers),
        null => false,
      };

  /// A lane group's switch, pressed as its header's label presses it: a V
  /// row's effect on its TRACK, a projection row's group on the layer of
  /// the cut stood in, an S row's on its layer.
  void _toggleGroup(Layer layer, PropertyLaneRow lane) {
    final rowId = layer.id;
    if (trackIdOfTransformLaneCarrier(rowId) case final trackId?) {
      final toggle = _widget.onToggleTrackEffectEnabled;
      if (parseEffectLaneId(lane.laneId) case final effect?
          when toggle != null) {
        _rows._actOnTrack(trackId, (track) => toggle(track, effect.effectId));
      }
      return;
    }
    final toggle = _widget.onToggleLaneGroupEnabled;
    if (trackIdOfProjectionRow(rowId) == null) {
      toggle?.call(layer, lane);
    } else if (_rows._rowInHand(rowId) case (
      cut: _,
      layer: final stood,
      stood: true,
    )?) {
      toggle?.call(stood, lane);
    }
  }

  /// Whether a lane [row]'s header wears its group's switch, as its label
  /// mounts it ([_toggleGroup]): a projection row's only while its cut is
  /// stood in.
  bool _handsGroupSwitch(TimelineDisplayRow row) {
    final rowId = row.layer.id;
    if (_carriesATrack(rowId)) {
      return _widget.onToggleTrackEffectEnabled != null;
    }
    return _widget.onToggleLaneGroupEnabled != null &&
        (trackIdOfProjectionRow(rowId) == null ||
            (_rows._rowInHand(rowId)?.stood ?? false));
  }

  /// The twirl [rowId]'s row draws, as its label holds it, and the lanes it
  /// twirls down — an S row's its SE row's, the V row's its track's by its
  /// lane carrier, a projection head's its head family's (F-360). Null for
  /// a row with no lanes, which draws none.
  ({_Twirl twirl, List<PropertyLaneRow> lanes})? _twirlOf(LayerId rowId) {
    final rows = _rows;
    if (_trackOf(trackIdOfTransformLaneCarrier(rowId)) case final track?) {
      return _drawn(rowId, track.lanesExpanded, rows._trackOwnLanes(track));
    }
    if (_trackOf(trackIdOfCameraRow(rowId)) case final track?) {
      return _drawn(
        rows._cameraTwirlOf(track),
        rows._cameraLanesOpen(track),
        rows._cameraLanes(track),
      );
    }
    if (trackConteRowOf(rowId) case (:final trackId, :final seat)?) {
      final track = rows._trackNamed(trackId);
      return track == null
          ? null
          : _drawn(
              rows._conteTwirlOf(track, seat),
              rows._conteLanesOpen(track, seat),
              rows._conteLanes(track, seat),
            );
    }
    for (final track in _widget.project.tracks) {
      final slot = track.seLayers.indexWhere((layer) => layer.id == rowId);
      if (slot >= 0) {
        return _drawn(
          rowId,
          rows._seLanesOpen(track, slot),
          rows._seLanes(track, slot),
        );
      }
    }
    return null;
  }

  Track? _trackOf(TrackId? trackId) =>
      trackId == null ? null : _rows._trackNamed(trackId);

  /// The twirl that turns [turns], [open] or shut — none where it has no
  /// row to turn or no [lanes] to twirl down.
  static ({_Twirl twirl, List<PropertyLaneRow> lanes})? _drawn(
    LayerId? turns,
    bool open,
    List<PropertyLaneRow> lanes,
  ) => turns == null || lanes.isEmpty
      ? null
      : (twirl: (id: turns, open: open), lanes: lanes);
}
