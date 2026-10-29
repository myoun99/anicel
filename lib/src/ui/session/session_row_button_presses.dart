import '../../models/attached_layer_resolve.dart'
    show attachRowWearsBaseComposite, attachedLayersOf;
import '../../models/layer.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/track_row_twirls.dart';
import '../../models/track_transform_lane_carrier.dart';
import '../../services/project_lookup.dart'
    show cutPositionOf, cutWritingRow, layerAnywhereOrNull, rowTwirlsOf;
import '../editor_session_manager.dart';
import '../text/readout_text.dart' show columnValueText;
import '../timeline/layer_label_controls.dart'
    show LayerMarkEdit, layerKindShowsOpacityControl, layerRowWearsFxSwitch;
import '../timeline/lane_graph.dart'
    show LaneGraph, LaneGraphMode, LaneGraphVerbs;
import '../timeline/layer_rail_columns.dart' show layerRailEyeIsOn;
import '../timeline/property_lane_model.dart'
    show laneGroupKey, parseLaneGroupKey;
import '../timeline/se_sound_lane_policy.dart' show seSoundTotalVolumeLaneId;
import '../timeline/timeline_lane_provider.dart' show timelineLanesForLayer;

/// The rail rows' buttons wired to [session] as a PRESS on one row asks
/// them — the one wiring behind the timeline rail (the x-sheet's column
/// headers are that rail stood up), the storyboard's rows, and the SE
/// mixer their speaker opens.
///
/// 🚨A PRESS INSIDE THE ROW SELECTION IS A PRESS ON EVERY SELECTED ROW, as
/// one undo; outside it, that row's alone (row-buttons-act-on-the-selection,
/// 유저 2026-09-25: 「타임시트on off버튼이나 색라벨 변경,참조,fx,어니언,
/// 비지블,소리,불투명도,블렌드 이런거 다 선택범위 내부 레이어 조절하면
/// 선택범위 레이어 모두 적용. 언두하나」) — [RowSelection.pressAcross] and
/// [RowSelection.pickAcross], on the rows [RowSelection.rowsActedOnBy] has
/// answered since 09-11. A button asks each row the reading the column
/// swipe asks it, so a row without the button is passed by and a swipe
/// that starts on a selected row paints on from what the press set.
///
/// Rows are found ANYWHERE: the storyboard's rail carries the tracks' own
/// SE and transition rows, which no cut holds.
///
/// The CAMERA row's buttons are its layer's, as every row's are (F-363,
/// 유저 2026-10-15: 「기본적으로 레이어 버튼은 그게 기준」): its eye and its
/// slider — the camera view's switch and its dim (`CameraViewMode`) — write
/// the layer, across the selection like the rest. ↩️They wrote two
/// notifiers the window held, and only for the row pressed.
class SessionRowButtonPresses {
  const SessionRowButtonPresses(this.session);

  final EditorSessionManager session;

  void toggleVisibility(LayerId pressed) =>
      session.rowSelectionVerbs.pressAcross(
        pressed,
        valueOf: _eyeOf,
        flip: _flipEye,
        description: 'Toggle visibility',
      );

  void toggleTimesheet(LayerId pressed) =>
      session.rowSelectionVerbs.pressAcross(
        pressed,
        valueOf: (id) => _ifRow(
          id,
          layerCarriesTimesheetToggle,
          session.layerSwitches.isLayerOnTimesheet,
        ),
        flip: session.layerSwitches.toggleLayerTimesheet,
        description: 'Toggle timesheet',
      );

  void toggleClip(LayerId pressed) =>
      session.rowSelectionVerbs.pressAcross(
        pressed,
        valueOf: (id) => _ifRow(
          id,
          (layer) => layer.kind.takesClipping,
          session.layerSwitches.isLayerClipping,
        ),
        flip: session.layerSwitches.toggleLayerClip,
        description: 'Toggle clip to layer below',
      );

  /// The fx master reads as the tap flips it: a mixed row is ON — a tap
  /// turns it off (`EffectsAndFx.toggleLayerFx`). A row wearing its base's
  /// switch has none of its own ([layerRowWearsFxSwitch]).
  void toggleFx(LayerId pressed) => session.rowSelectionVerbs.pressAcross(
    pressed,
    valueOf: (id) => _ifRow(
      id,
      (layer) => layerRowWearsFxSwitch(
        layer.kind,
        wearsBaseComposite: attachRowWearsBaseComposite(
          layer,
          _stackOf(layer.id) ?? const [],
        ),
      ),
      (id) => fxEnabledFromState(session.effectsAndFx.layerFxState(id)),
    ),
    flip: session.effectsAndFx.toggleLayerFx,
    description: 'Toggle FX',
  );

  void toggleOnionSkin(LayerId pressed) =>
      session.rowSelectionVerbs.pressAcross(
        pressed,
        valueOf: (id) => _ifRow(
          id,
          (layer) => layer.kind.takesOnionSkin,
          session.onionSkin.isLayerOnionSkinEnabled,
        ),
        flip: session.onionSkin.toggleLayerOnionSkin,
        description: 'Toggle onion skin',
      );

  /// A label or take picked on [pressed], made as the same EDIT on every
  /// row it acts on — a take keeps each row's own label.
  void pickMark(LayerId pressed, LayerMarkEdit edit) =>
      session.rowSelectionVerbs.pickAcross(pressed, (id) {
        final layer = _row(id);
        if (layer != null) {
          session.layerMarks.setLayerMark(id, edit(layer.mark));
        }
      }, description: 'Set layer label');

  void pickBlendMode(LayerId pressed, LayerBlendMode mode) =>
      session.layerSwitches.setBlendModeForLayers(
        session.rowSelectionVerbs.layersActedOnBy(pressed),
        mode,
      );

  /// The twirl of a row's property lanes (the fx lanes live under it).
  ///
  /// 🗣️I-32 (유저 2026-09-14): 「… 색라벨 변경,테이크,fx펼치기,타임시트on,off,
  /// 그룹펼치기, … 레이어에 있는 버튼 전부 조사하고 연결해서
  /// 일괄조작가능하게」 — the twirl and the group fold were the two left
  /// pressing their own row only.
  void toggleLanes(LayerId pressed) => session.rowSelectionVerbs.pressAcross(
    pressed,
    valueOf: _lanesOpen,
    flip: _toggleLanesOf,
    description: 'Toggle layer lanes',
  );

  /// The GROUP fold: ONE chevron with two verbs (`timelineGroupFoldFor`) — a
  /// folder's own fold, or the attach group riding a base — so across the
  /// selection a folder and a base fold together (I-32).
  void toggleGroupFold(LayerId pressed) =>
      session.rowSelectionVerbs.pressAcross(
        pressed,
        valueOf: _groupOpen,
        flip: _toggleGroupOf,
        description: 'Toggle group fold',
      );

  bool? _lanesOpen(LayerId id) {
    // The V row: no layer, so no layer's lanes to ask about — its button is
    // drawn only while its track has some, and its twirl is its track's.
    if (trackIdOfTransformLaneCarrier(id) != null) {
      return _twirlsOf(id)?.lanesExpanded;
    }
    final layer = _row(id);
    if (layer == null ||
        timelineLanesForLayer(
          layer: layer,
          session: session,
          expandedGroupKeys: session.railView.expandedLaneGroupKeys.value,
        ).isEmpty) {
      return null;
    }
    return layer.lanesExpanded;
  }

  /// 🚨UNDOABLE (유저 2026-08-29: 「아무튼 레이어에 있는 버튼 싹다」). The
  /// property-lane twirl — the one the fx lanes live under — is a button
  /// on a layer row like any other, and the row's own (F-360): every use
  /// of a linked row twirls with it (F-302), every row of its head too.
  ///
  /// ⛔The closing half still runs here and NOT inside the command: the
  /// fold law hands the standing row to the layer when its lanes leave
  /// the screen (R5 #11), and that is a selection move, not part of the
  /// twirl this undoes.
  void _toggleLanesOf(LayerId id) {
    final closing = _twirlsOf(id)?.lanesExpanded ?? false;
    session.layerSwitches.toggleLayerLanes(id);
    if (closing) {
      session.handOffCurrentRowOnFold(id);
    }
  }

  /// A lane GROUP's twirl inside a row's twirl-down — Transform, an
  /// effect's header — by its view-state key ([laneGroupKey]).
  ///
  /// 🗣️F-302 (유저 2026-10-05): 「겸용컷, 레이어에서 fx 접기펼치기 … 공유.
  /// 지금 겸용컷별로 독립적임. 펼친 상태 접힌 상태 공유하라는것. 법통일」 —
  /// the same group of every use of a linked row opens and shuts with it: a
  /// linked row's effects are one chain, so its groups are one too.
  ///
  /// ↩️It was the workspace's own, and wrote the pressed row's key alone.
  /// ↩️It was then the rail's view, outside history — the one fold that did
  /// not undo — until F-360 put it on the row beside its twirl.
  void toggleLaneGroup(String groupKey) {
    final row = parseLaneGroupKey(groupKey);
    // A key that names no row has no row to keep its twirl on.
    final twirls = row == null ? null : _twirlsOf(row.layerId);
    if (row == null || twirls == null) {
      return;
    }
    final closing = twirls.expandedLaneGroups.contains(row.laneId);
    if (closing) {
      // Closing: only this group's MEMBERS go, so the header is what
      // swallows them and where the standing row lands (R5 #11).
      session.handOffCurrentRowOnFold(row.layerId, laneId: row.laneId);
    }
    session.layerSwitches.setLayerLaneGroupExpanded(
      row.layerId,
      row.laneId,
      expanded: !closing,
    );
  }

  /// The header graphs' buttons as a grid is handed them (I-89 ③).
  LaneGraphVerbs get laneGraphVerbs => (
    toggle: toggleLaneGraph,
    togglePin: toggleLanePin,
    plot: plotLaneGraph,
    resize: resizeLaneGraph,
    enlarge: enlargeLaneGraph,
    pen: penLaneGraph,
    transformBox: transformBoxLaneGraph,
  );

  /// A group's HEADER GRAPH on or off, by the group's key — on every use of
  /// its row (F-302, as the group's twirl beside it), and on no other
  /// group: 「그래프를 누른 레일만 상태변경」 (유저 2026-10-10).
  ///
  /// A graph stands in its lanes' place, so one turned on over a shut group
  /// opens the group with it — through the group's own twirl, the camera
  /// row's being the row's (㉙). Shutting the group keeps the graph for
  /// when it opens again. ⚠️View state: no undo — while the twirl it opens
  /// is the row's, and does (F-360).
  ///
  /// The graph is written BEFORE the group opens: the twirl is a command,
  /// and what follows a command reads the graphs as they stand.
  void toggleLaneGraph(String groupKey) {
    final graphs = session.railView.laneGraphs;
    final open = Map<String, LaneGraph>.of(graphs.value.open);
    final everyUse = _everyUseOf(groupKey);
    final opening = !open.containsKey(groupKey);
    if (opening) {
      for (final key in everyUse) {
        open[key] = const LaneGraph();
      }
    } else {
      open.removeWhere((key, _) => everyUse.contains(key));
    }
    graphs.value = graphs.value.copyWith(open: open);
    if (opening) {
      _openGroupOf(groupKey);
    }
  }

  /// A group's open graph ENLARGED over every other row, or let back — on
  /// every use of its row, as what it plots and how far it stands are; and
  /// every other graph let back with it: one group's graph is enlarged at
  /// a time (I-89 ③D, the mock's 5판). A graph that is shut stays shut.
  /// View state, as the graph is: no undo.
  void enlargeLaneGraph(String groupKey) {
    final graphs = session.railView.laneGraphs;
    final open = graphs.value.open;
    final pressed = open[groupKey];
    if (pressed == null) {
      return;
    }
    final enlarging = !pressed.enlarged;
    final everyUse = _everyUseOf(groupKey);
    graphs.value = graphs.value.copyWith(
      open: {
        for (final MapEntry(:key, value: graph) in open.entries)
          key: graph.copyWith(enlarged: enlarging && everyUse.contains(key)),
      },
    );
  }

  /// A lane PINNED to every open graph, or let go, by the lane's own key —
  /// on every use of its row. AE's graph editor set (유저 2026-10-10:
  /// 「ae의 그래프세트? … 남겨도 될거같긴한데」). View state, no undo.
  void toggleLanePin(String laneKey) {
    final graphs = session.railView.laneGraphs;
    final pinned = Set<String>.of(graphs.value.pinned);
    final everyUse = _everyUseOf(laneKey);
    if (pinned.contains(laneKey)) {
      pinned.removeAll(everyUse);
    } else {
      pinned.addAll(everyUse);
    }
    graphs.value = graphs.value.copyWith(pinned: pinned);
  }

  /// What a group's open graph PLOTS, on every use of its row. View state,
  /// no undo.
  void plotLaneGraph(String groupKey, LaneGraphMode mode) =>
      _reshapeLaneGraph(groupKey, (graph) => graph.copyWith(mode: mode));

  /// A group's open graph's PEN taken up or put down (I-3 ④), on every use
  /// of its row — what the pressed one has, all of them turned to the
  /// other. View state, no undo.
  void penLaneGraph(String groupKey) {
    final pressed = session.railView.laneGraphs.value.open[groupKey];
    if (pressed == null) {
      return;
    }
    _reshapeLaneGraph(groupKey, (graph) => graph.copyWith(pen: !pressed.pen));
  }

  /// A group's open graph's TRANSFORM BOX shown or hidden (AE's 「Show
  /// Transform Box」), on every use of its row — what the pressed one has,
  /// all of them turned to the other. View state, no undo.
  void transformBoxLaneGraph(String groupKey) {
    final pressed = session.railView.laneGraphs.value.open[groupKey];
    if (pressed == null) {
      return;
    }
    _reshapeLaneGraph(
      groupKey,
      (graph) => graph.copyWith(transformBox: !pressed.transformBox),
    );
  }

  /// How far a group's open graph stands along the rail — its grip's — on
  /// every use of its row. View state, no undo.
  void resizeLaneGraph(String groupKey, double extent) =>
      _reshapeLaneGraph(groupKey, (graph) => graph.copyWith(extent: extent));

  /// [reshape] laid on [groupKey]'s graph wherever it stands open on a use
  /// of its row; a shut one stays shut.
  void _reshapeLaneGraph(
    String groupKey,
    LaneGraph Function(LaneGraph graph) reshape,
  ) {
    final graphs = session.railView.laneGraphs;
    final open = Map<String, LaneGraph>.of(graphs.value.open);
    for (final key in _everyUseOf(groupKey)) {
      if (open[key] case final graph?) {
        open[key] = reshape(graph);
      }
    }
    graphs.value = graphs.value.copyWith(open: open);
  }

  /// [groupKey]'s group twirled open where it is shut: the camera row's
  /// lanes — its group is the row — or the header's members.
  ///
  /// Read off the row's twirls ([_twirlsOf]), as the twirl verbs are: a V
  /// row's lane carrier is no layer, and its fx header's graph opened shut
  /// while the row's twirls were asked of a layer (I-89 ①).
  void _openGroupOf(String groupKey) {
    final row = parseLaneGroupKey(groupKey);
    final twirls = row == null ? null : _twirlsOf(row.layerId);
    if (row == null || twirls == null) {
      return;
    }
    if (_row(row.layerId)?.kind == LayerKind.camera) {
      if (!twirls.lanesExpanded) {
        _toggleLanesOf(row.layerId);
      }
      return;
    }
    if (!twirls.expandedLaneGroups.contains(row.laneId)) {
      toggleLaneGroup(groupKey);
    }
  }

  /// The keys a press on one row's lane reaches: [key] itself, and the
  /// same lane on every use of its row (F-302) — what a group's graph and a
  /// lane's pin are written to. ↩️Its twirl too, until F-360 put the twirl
  /// on the row, whose command walks the row's head.
  List<String> _everyUseOf(String key) {
    final row = parseLaneGroupKey(key);
    return [
      key,
      if (row != null)
        for (final use in session.rowsFoldingWith(row.layerId))
          laneGroupKey(use, row.laneId),
    ];
  }

  bool? _groupOpen(LayerId id) {
    final layer = _row(id);
    final layers = _stackOf(id);
    if (layer == null || layers == null) {
      return null;
    }
    if (!layer.kind.groupsLayers && attachedLayersOf(id, layers).isEmpty) {
      return null;
    }
    return !layer.collapsed;
  }

  void _toggleGroupOf(LayerId id) {
    if (_row(id)?.kind.groupsLayers ?? false) {
      session.folders.toggleLayerCollapsed(id);
      return;
    }
    _toggleAttachFoldOf(id);
  }

  /// A base's attach group, folded or opened — undoable like the lane
  /// twirl beside it (「아무튼 레이어에 있는 버튼 싹다」), which it was not
  /// until I-32 pressed it across a selection. The base's own `collapsed`,
  /// the folder's field and command (F-360).
  void _toggleAttachFoldOf(LayerId baseId) {
    if (!(_row(baseId)?.collapsed ?? false)) {
      // FOLDING while one of the group's attach rows is active (UI-R24
      // #4): hand the selection to the BASE so the group actually
      // disappears — the active-attach-stays-visible rule otherwise kept
      // the fold from taking effect until some other row was picked.
      //
      // ↩️Through the session's fold law since F-81, which asks what the
      // group holds — the organizer folder and a nested one too — instead
      // of 「is the active row an attach row of this base」.
      //
      // ↩️F-169: that rule is gone (nothing stands inside a shut group), so
      // this hand-off is what keeps the fold from shutting over you.
      //
      // Every use the fold shuts hands on, as every use folds (F-302) — the
      // conte pressed in one cut shuts the group in the cut you stand in.
      for (final use in session.rowsFoldingWith(baseId)) {
        session.handOffCurrentRowOnAttachFold(use);
      }
    }
    // F-302: every use of a linked base folds its group with it.
    session.folders.toggleAttachGroup(baseId);
  }

  void previewOpacity(LayerId pressed, double opacity) =>
      session.opacityVerbs.previewLayersOpacity(_opacityRows(pressed), opacity);

  void commitOpacity(LayerId pressed, double opacity) {
    session.rowSelectionVerbs.pickAcross(pressed, (id) {
      for (final row in _sliderRowsOf(id)) {
        session.opacityVerbs.commitLayerOpacity(row, opacity);
      }
    }, description: 'Set opacity');
  }

  // ── the SE mixer: the speaker's window, pressed as the speaker ────────

  void toggleMute(LayerId pressed) => session.rowSelectionVerbs.pressAcross(
    pressed,
    valueOf: (id) => _ifRow(id, _hasMixer, (id) => _row(id)!.muted),
    flip: session.layerSwitches.toggleLayerMuted,
    description: 'Toggle layer mute',
  );

  /// Solo is monitoring — never saved, never exported — so it spreads like
  /// the rest and leaves nothing to undo, as the eye's Solo does (F-125).
  void toggleSolo(LayerId pressed) => session.rowSelectionVerbs.pressAcross(
    pressed,
    valueOf: (id) => _ifRow(
      id,
      _hasMixer,
      (id) => session.visibilitySolo.soloedSeLayerIds.value.contains(id),
    ),
    flip: session.visibilitySolo.toggleLayerSolo,
    description: 'Toggle solo',
  );

  /// The window's bar (I-145-Q1 「따로 한 값 — 두 입구」): the row's Total,
  /// written as a value typed into its 「오디오」 group's lane is — one field,
  /// two doors. The Total holds no keys, so the frame names nothing.
  void setTotalVolume(LayerId pressed, double share) =>
      session.rowSelectionVerbs.pickAcross(pressed, (id) {
        final layer = _row(id);
        if (layer != null && _hasMixer(layer)) {
          session.laneVerbs.setLaneValueAt(
            id,
            seSoundTotalVolumeLaneId,
            0,
            columnValueText(share * 100),
            frameIsGlobal: true,
            description: 'Set total volume',
            scaleLinked: false,
          );
        }
      }, description: 'Set total volume');

  /// The rows the speaker is drawn on (`_muteButton` in the rail row).
  static bool _hasMixer(Layer layer) => layer.kind == LayerKind.se;

  /// The rows a slider press moves: what the slider of each row it acts on
  /// moves ([_sliderRowsOf]).
  Set<LayerId> _opacityRows(LayerId pressed) => {
    for (final id in session.rowSelectionVerbs.layersActedOnBy(pressed))
      ..._sliderRowsOf(id),
  };

  /// The rows the slider on [id] moves: [id] itself when it carries an
  /// opacity slider of its own, and the attach layers riding it while its
  /// group is folded.
  ///
  /// 🚨F-266 (유저 2026-10-03): 「어태치 레이어가 있을떄, 기준레이어
  /// 접혀있을때 비지블 on off가 내부 어태치된 레이어들한테도 적용되는데, 이거
  /// 불투명도 조절도 똑같이 접혀있을때 모두한테 적용되도록. 접혀있을떄만」. The
  /// same rows the eye sets ([_flipEye], F-184) — the layers, not the group's
  /// organizer folders, whose strength is their own value as their eye is.
  /// Unfolded, every row keeps its own slider.
  List<LayerId> _sliderRowsOf(LayerId id) => [
    for (final row in [?_row(id), ..._foldedRidersOf(id)])
      if (_hasOwnSlider(row)) row.id,
  ];

  static bool _hasOwnSlider(Layer? layer) =>
      layer != null && layerKindShowsOpacityControl(layer.kind);

  bool? _eyeOf(LayerId id) {
    final layer = _row(id);
    return layer == null
        ? null
        : layerRailEyeIsOn(layer, live: session.layerSwitches.isLayerEyeOn);
  }

  /// 🚨F-184 (유저 2026-09-26): 「어태치 레이어가 접혀있을때의 기준레이어의
  /// 비지블 버튼은 내부 어태치레이어 전체에 적용. 즉 비지블on하면 어태치레이어들
  /// 다 on됨. 다시말하지만 어태치 접혀있을때만. 펼치기 상태에선 지금처럼
  /// 각각」. The eye of a FOLDED group's base sets every attach layer riding
  /// it to what it set the base to — a rider that already shows it is passed
  /// by, the column swipe's rule. Unfolded, each row keeps its own eye. The
  /// group's organizer folders keep theirs: a folder's eye is its own value,
  /// which the composite hides by, and that is F-185's law, not this one.
  void _flipEye(LayerId id) {
    final shown = _eyeOf(id);
    session.layerSwitches.toggleLayerVisibility(id);
    for (final rider in _foldedRidersOf(id)) {
      if (_eyeOf(rider.id) == shown) {
        session.layerSwitches.toggleLayerVisibility(rider.id);
      }
    }
  }

  /// The attach layers riding [base] while its group is folded on the rail
  /// — none while it is open.
  List<Layer> _foldedRidersOf(LayerId base) {
    final layers = _stackOf(base);
    if (layers == null || !(_row(base)?.collapsed ?? false)) {
      return const [];
    }
    return attachedLayersOf(base, layers);
  }

  Layer? _row(LayerId id) =>
      layerAnywhereOrNull(session.repository.requireProject(), id);

  /// [id]'s twirls as the project holds them ([rowTwirlsOf]).
  RowTwirls? _twirlsOf(LayerId id) =>
      rowTwirlsOf(session.repository.requireProject(), id);

  /// The stack [id]'s row stands in — its own cut's, wherever that is: the
  /// storyboard's rail presses the conte rows of cuts that are not the
  /// active one (I-73). ↩️The active cut's, always; a base pressed from
  /// that rail under another cut was then asked about a stack it is not in,
  /// and answered that it carries no attach group.
  List<Layer>? _stackOf(LayerId id) {
    final project = session.repository.requireProject();
    final cutId = cutWritingRow(project, id, standing: session.activeCutId);
    return cutId == null ? null : cutPositionOf(project, cutId)?.cut.layers;
  }

  /// [read] for a row that has the button ([has]); null for one that has
  /// not, or for an id no row answers to.
  bool? _ifRow(
    LayerId id,
    bool Function(Layer layer) has,
    bool Function(LayerId id) read,
  ) {
    final layer = _row(id);
    return layer != null && has(layer) ? read(id) : null;
  }
}
