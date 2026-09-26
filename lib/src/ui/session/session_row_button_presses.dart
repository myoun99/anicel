import 'package:flutter/foundation.dart';

import '../../models/attached_layer_resolve.dart' show attachedLayersOf;
import '../../models/layer.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../services/project_lookup.dart' show layerAnywhereOrNull;
import '../editor_session_manager.dart';
import '../timeline/layer_label_controls.dart'
    show LayerMarkEdit, layerKindShowsFxToggle, layerKindShowsOpacityControl;
import '../timeline/layer_rail_columns.dart' show layerRailEyeIsOn;

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
    final rows = _opacityRows(pressed);
    session.rowSelectionVerbs.pickAcross(pressed, (id) {
      if (rows.contains(id)) {
        session.opacityVerbs.commitLayerOpacity(id, opacity);
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

  /// The rows a slider press moves: those it acts on that carry an opacity
  /// slider of their own — the camera's is the view's dim, and stays out.
  Set<LayerId> _opacityRows(LayerId pressed) => {
    for (final id in session.rowSelectionVerbs.rowsActedOnBy(pressed))
      if (_hasOwnSlider(_row(id))) id,
  };

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
