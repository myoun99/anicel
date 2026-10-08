import 'package:flutter/foundation.dart';

import '../../models/attached_layer_resolve.dart' show attachedLayersOf;
import '../../models/layer.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../services/commands/toggle_id_in_set_command.dart';
import '../../services/project_lookup.dart' show layerAnywhereOrNull;
import '../editor_session_manager.dart';
import '../timeline/layer_label_controls.dart'
    show LayerMarkEdit, layerKindShowsFxToggle, layerKindShowsOpacityControl;
import '../timeline/layer_rail_columns.dart' show layerRailEyeIsOn;
import '../timeline/property_lane_model.dart'
    show laneGroupKey, parseLaneGroupKey;
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
/// [cameraView] and [cameraDim] are the timeline's camera row: its eye and
/// its slider drive the camera view, not layer flags. The storyboard's rail
/// has no camera row and passes neither.
class SessionRowButtonPresses {
  const SessionRowButtonPresses(
    this.session, {
    this.cameraView,
    this.cameraDim,
  });

  final EditorSessionManager session;
  final ValueNotifier<bool>? cameraView;
  final ValueNotifier<double>? cameraDim;

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

  void toggleFillReference(LayerId pressed) =>
      session.rowSelectionVerbs.pressAcross(
        pressed,
        valueOf: (id) => _ifRow(
          id,
          (layer) => layer.kind.carriesFillReference,
          (id) => _row(id)!.isFillReference,
        ),
        flip: session.layerSwitches.toggleLayerFillReference,
        description: 'Toggle fill reference',
      );

  /// The fx master reads as the tap flips it: a mixed row is ON — a tap
  /// turns it off (`EffectsAndFx.toggleLayerFx`).
  void toggleFx(LayerId pressed) => session.rowSelectionVerbs.pressAcross(
    pressed,
    valueOf: (id) => _ifRow(
      id,
      (layer) => layerKindShowsFxToggle(layer.kind),
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
        session.rowSelectionVerbs.rowsActedOnBy(pressed),
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
    final layer = _row(id);
    if (layer == null ||
        timelineLanesForLayer(
          layer: layer,
          session: session,
          expandedGroupKeys: session.railView.expandedLaneGroupKeys.value,
        ).isEmpty) {
      return null;
    }
    return session.railView.expandedLaneLayerIds.value.contains(id);
  }

  /// 🚨UNDOABLE (유저 2026-08-29: 「아무튼 레이어에 있는 버튼 싹다」). The
  /// property-lane twirl — the one the fx lanes live under — is a button
  /// on a layer row like any other.
  ///
  /// ⛔The closing half still runs here and NOT inside the command: the
  /// fold law hands the standing row to the layer when its lanes leave
  /// the screen (R5 #11), and that is a selection move, not part of the
  /// membership this undoes.
  void _toggleLanesOf(LayerId id) {
    final expanded = session.railView.expandedLaneLayerIds;
    final closing = expanded.value.contains(id);
    session.historyManager.execute(
      ToggleIdInSetCommand(
        notifier: expanded,
        layerId: id,
        // F-302: every use of a linked row twirls with it.
        alongWith: session.rowsFoldingWith(id),
        debugLabel: 'Toggle layer lanes',
      ),
    );
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
  void toggleLaneGroup(String groupKey) {
    final expanded = session.railView.expandedLaneGroupKeys;
    final next = Set<String>.of(expanded.value);
    final row = parseLaneGroupKey(groupKey);
    final everyUse = [
      groupKey,
      if (row != null)
        for (final use in session.rowsFoldingWith(row.layerId))
          laneGroupKey(use, row.laneId),
    ];
    if (next.contains(groupKey)) {
      next.removeAll(everyUse);
      // Closing: only this group's MEMBERS go, so the header is what
      // swallows them and where the standing row lands (R5 #11).
      if (row != null) {
        session.handOffCurrentRowOnFold(row.layerId, laneId: row.laneId);
      }
    } else {
      next.addAll(everyUse);
    }
    expanded.value = next;
  }

  bool? _groupOpen(LayerId id) {
    final layer = _row(id);
    final layers = session.activeCutOrNull?.layers;
    if (layer == null || layers == null) {
      return null;
    }
    if (layer.kind.groupsLayers) {
      return !layer.collapsed;
    }
    if (attachedLayersOf(id, layers).isEmpty) {
      return null;
    }
    return !session.railView.collapsedAttachBaseIds.value.contains(id);
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
  /// until I-32 pressed it across a selection.
  void _toggleAttachFoldOf(LayerId baseId) {
    final folded = session.railView.collapsedAttachBaseIds;
    if (!folded.value.contains(baseId)) {
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
      session.handOffCurrentRowOnAttachFold(baseId);
    }
    session.historyManager.execute(
      ToggleIdInSetCommand(
        notifier: folded,
        layerId: baseId,
        // F-302: every use of a linked base folds its group with it.
        alongWith: session.rowsFoldingWith(baseId),
        debugLabel: 'Toggle attach group',
      ),
    );
  }

  void previewOpacity(LayerId pressed, double opacity) {
    if (_isCamera(pressed) && cameraDim != null) {
      cameraDim!.value = opacity;
      return;
    }
    session.opacityVerbs.previewLayersOpacity(_opacityRows(pressed), opacity);
  }

  void commitOpacity(LayerId pressed, double opacity) {
    if (_isCamera(pressed) && cameraDim != null) {
      cameraDim!.value = opacity;
      return;
    }
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

  void setGain(LayerId pressed, double gain) => _setAudio(
    pressed,
    (id) => session.layerSwitches.setLayerAudio(layerId: id, gain: gain),
  );

  void setPan(LayerId pressed, double pan) => _setAudio(
    pressed,
    (id) => session.layerSwitches.setLayerAudio(layerId: id, pan: pan),
  );

  void _setAudio(LayerId pressed, void Function(LayerId id) set) =>
      session.rowSelectionVerbs.pickAcross(pressed, (id) {
        final layer = _row(id);
        if (layer != null && _hasMixer(layer)) {
          set(id);
        }
      }, description: 'Set layer audio');

  /// The rows the speaker is drawn on (`_muteButton` in the rail row).
  static bool _hasMixer(Layer layer) => layer.kind == LayerKind.se;

  /// The rows a slider press moves: what the slider of each row it acts on
  /// moves ([_sliderRowsOf]).
  Set<LayerId> _opacityRows(LayerId pressed) => {
    for (final id in session.rowSelectionVerbs.rowsActedOnBy(pressed))
      ..._sliderRowsOf(id),
  };

  /// The rows the slider on [id] moves: [id] itself when it carries an
  /// opacity slider of its own — the camera's is the view's dim, and stays
  /// out — and the attach layers riding it while its group is folded.
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
      layer != null &&
      layerKindShowsOpacityControl(layer.kind) &&
      layer.kind != LayerKind.camera;

  bool? _eyeOf(LayerId id) {
    if (_isCamera(id) && cameraView != null) {
      return cameraView!.value;
    }
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
    if (_isCamera(id) && cameraView != null) {
      cameraView!.value = !cameraView!.value;
      return;
    }
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
    final layers = session.activeCutOrNull?.layers;
    if (layers == null ||
        !session.railView.collapsedAttachBaseIds.value.contains(base)) {
      return const [];
    }
    return attachedLayersOf(base, layers);
  }

  bool _isCamera(LayerId id) => _row(id)?.kind == LayerKind.camera;

  Layer? _row(LayerId id) =>
      layerAnywhereOrNull(session.repository.requireProject(), id);

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
