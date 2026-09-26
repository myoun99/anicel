// ROW BUTTONS ACT ON THE SELECTION (row-buttons-act-on-the-selection).
//
// 유저 2026-09-25, answering clear-all-marks-meaning-Q1: 「선택범위 선택하고
// 타임시트on off버튼이나 색라벨 변경,참조,fx,어니언,비지블,소리,불투명도,
// 블렌드 이런거 다 선택범위 내부 레이어 조절하면 선택범위 레이어 모두 적용.
// 언두하나. 바깥 레이어 조절하면 바깥 그 레이어만 조절」.
//
// Every button is pressed the way the rails and the SE mixer press it —
// through [SessionRowButtonPresses] — and each has its counter-case: the
// press OUTSIDE the selection, which must leave the selected rows alone.
// That the two hosts' rails reach this wiring at all is pinned on real
// widgets in `test/ui/timeline/row_buttons_act_on_the_selection_rails_test.dart`.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/session_row_button_presses.dart';

void main() {
  for (final button in _buttons) {
    group('the ${button.name}', () {
      test('pressed inside the selection, it sets every selected row — '
          'as one undo', () {
        final r = _Rig();
        final was = button.read(r, r.a);
        expect(
          [button.read(r, r.b), button.read(r, r.c)],
          [was, was],
          reason: 'the premise: three rows alike',
        );
        r.select([r.a, r.b]);
        final depth = r.s.historyManager.undoCount;

        button.press(r.presses, r.a);

        expect(button.read(r, r.a), !was);
        expect(
          button.read(r, r.b),
          !was,
          reason: '「선택범위 내부 레이어 조절하면 선택범위 레이어 모두 적용」',
        );
        expect(button.read(r, r.c), was, reason: 'C is outside the selection');
        if (!button.undoes) {
          expect(
            r.s.historyManager.undoCount,
            depth,
            reason: 'shown, not edited (F-162) — the spread leaves no step',
          );
          return;
        }
        r.s.undo();
        expect(
          [button.read(r, r.a), button.read(r, r.b)],
          [was, was],
          reason: '「언두하나」 — ONE undo takes back every row the press set',
        );
      });

      test('pressed outside the selection, it is that row\'s alone', () {
        final r = _Rig();
        final was = button.read(r, r.a);
        r.select([r.a, r.b]);

        button.press(r.presses, r.c);

        expect(button.read(r, r.c), !was);
        expect(
          [button.read(r, r.a), button.read(r, r.b)],
          [was, was],
          reason: '「바깥 레이어 조절하면 바깥 그 레이어만 조절」',
        );
      });

      test('a selected row already showing the new value keeps it', () {
        final r = _Rig();
        final was = button.read(r, r.a);
        r.select(const []);
        button.press(r.presses, r.b);
        expect(button.read(r, r.b), !was, reason: 'the premise: B alone');
        r.select([r.a, r.b]);

        button.press(r.presses, r.a);

        expect(
          [button.read(r, r.a), button.read(r, r.b)],
          [!was, !was],
          reason:
              'the press SETS the pressed row\'s new value on the selection '
              '(the column swipe\'s rule) — flipping B as well would have '
              'sent it back',
        );
      });
    });
  }

  test('the fx master reads a MIXED selected row as the tap does — on', () {
    final r = _Rig();
    // An effect that applies beside a transform that does not: a mix.
    r.s.selectLayer(r.b);
    r.s.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
    r.s.effectsAndFx.toggleLayerTransformFx(r.b);
    expect(
      [r.s.effectsAndFx.layerFxState(r.a), r.s.effectsAndFx.layerFxState(r.b)],
      [LayerFxState.on, LayerFxState.mixed],
      reason: 'the premise',
    );
    r.select([r.a, r.b]);

    r.presses.toggleFx(r.a);

    expect(
      [r.s.effectsAndFx.layerFxState(r.a), r.s.effectsAndFx.layerFxState(r.b)],
      [LayerFxState.off, LayerFxState.off],
      reason:
          'A showed on and B reads on — a tap on B turns it off — so the '
          'press that turned A off turns B off with it',
    );
  });

  group('the colour label and the take', () {
    const key = LayerMark(process: LayerProcess.key);

    test('a label picked inside the selection lands on every selected row '
        '— as one undo', () {
      final r = _Rig();
      final was = {for (final id in r.cels) id: r.row(id).mark};
      r.select([r.a, r.b]);

      r.presses.pickMark(r.a, (_) => key);

      expect([r.row(r.a).mark, r.row(r.b).mark], [key, key]);
      expect(r.row(r.c).mark, was[r.c], reason: 'C is outside the selection');
      r.s.undo();
      expect([r.row(r.a).mark, r.row(r.b).mark], [was[r.a], was[r.b]]);
    });

    test('a take picked inside the selection keeps each row\'s own label', () {
      final r = _Rig();
      r.select(const []);
      r.presses.pickMark(r.b, (_) => key);
      final labelOfA = r.row(r.a).mark.process;
      expect(labelOfA, isNot(LayerProcess.key), reason: 'the premise');
      r.select([r.a, r.b]);

      r.presses.pickMark(r.a, (current) => current.withTake(3));

      expect([r.row(r.a).mark.take, r.row(r.b).mark.take], [3, 3]);
      expect(
        [r.row(r.a).mark.process, r.row(r.b).mark.process],
        [labelOfA, LayerProcess.key],
        reason:
            'a take is an EDIT of each row\'s mark — handing B the pressed '
            'row\'s finished mark would have copied A\'s label onto it',
      );
    });

    test('picked outside the selection, it is that row\'s alone', () {
      final r = _Rig();
      final was = r.row(r.a).mark;
      r.select([r.a, r.b]);

      r.presses.pickMark(r.c, (_) => key);

      expect(r.row(r.c).mark, key);
      expect([r.row(r.a).mark, r.row(r.b).mark], [was, was]);
    });
  });

  group('the blend', () {
    test('picked inside the selection, it lands on every selected row — '
        'as one undo', () {
      final r = _Rig();
      r.select([r.a, r.b]);

      r.presses.pickBlendMode(r.a, LayerBlendMode.multiply);

      expect(
        [r.row(r.a).blendMode, r.row(r.b).blendMode, r.row(r.c).blendMode],
        [LayerBlendMode.multiply, LayerBlendMode.multiply, LayerBlendMode.normal],
      );
      r.s.undo();
      expect(
        [r.row(r.a).blendMode, r.row(r.b).blendMode],
        [LayerBlendMode.normal, LayerBlendMode.normal],
      );
    });

    test('picked outside the selection, it is that row\'s alone', () {
      final r = _Rig();
      r.select([r.a, r.b]);

      r.presses.pickBlendMode(r.c, LayerBlendMode.screen);

      expect(
        [r.row(r.a).blendMode, r.row(r.b).blendMode, r.row(r.c).blendMode],
        [LayerBlendMode.normal, LayerBlendMode.normal, LayerBlendMode.screen],
      );
    });
  });

  group('the opacity slider', () {
    test('dragged inside the selection, it previews and sets every selected '
        'row — as one undo', () {
      final r = _Rig();
      r.select([r.a, r.b]);

      r.presses.previewOpacity(r.a, 0.3);
      expect(r.s.opacityVerbs.dragPreview.value?.layerIds, {r.a, r.b});
      r.presses.commitOpacity(r.a, 0.3);

      expect(
        [r.row(r.a).opacity, r.row(r.b).opacity, r.row(r.c).opacity],
        [0.3, 0.3, 1.0],
      );
      r.s.undo();
      expect([r.row(r.a).opacity, r.row(r.b).opacity], [1.0, 1.0]);
    });

    test('dragged outside the selection, it is that row\'s alone', () {
      final r = _Rig();
      r.select([r.a, r.b]);

      r.presses.previewOpacity(r.c, 0.6);
      expect(r.s.opacityVerbs.dragPreview.value?.layerIds, {r.c});
      r.presses.commitOpacity(r.c, 0.6);

      expect(
        [r.row(r.a).opacity, r.row(r.b).opacity, r.row(r.c).opacity],
        [1.0, 1.0, 0.6],
      );
    });
  });

  group('the camera row', () {
    test('its eye and its slider still drive the camera view', () {
      final r = _Rig();
      final view = ValueNotifier<bool>(true);
      final dim = ValueNotifier<double>(0.5);
      addTearDown(view.dispose);
      addTearDown(dim.dispose);
      final presses = SessionRowButtonPresses(
        r.s,
        cameraView: view,
        cameraDim: dim,
      );
      final camera = r.row(r.camera);

      presses.toggleVisibility(r.camera);
      presses.commitOpacity(r.camera, 0.2);

      expect(view.value, isFalse);
      expect(dim.value, 0.2);
      expect(
        [r.row(r.camera).isVisible, r.row(r.camera).opacity],
        [camera.isVisible, camera.opacity],
        reason: 'the view, not the layer\'s own flags',
      );
    });

    test('a layer slider inside a selection that holds the camera leaves '
        'its dim alone — the master bar\'s rule', () {
      final r = _Rig();
      final dim = ValueNotifier<double>(0.5);
      addTearDown(dim.dispose);
      final presses = SessionRowButtonPresses(r.s, cameraDim: dim);
      final camera = r.row(r.camera).opacity;
      r.select([r.a, r.camera]);

      presses.commitOpacity(r.a, 0.4);

      expect(r.row(r.a).opacity, 0.4);
      expect(dim.value, 0.5, reason: 'its slider is the view\'s dim');
      expect(
        r.row(r.camera).opacity,
        camera,
        reason: 'nor the layer opacity its slider does not show',
      );
    });
  });

  group('the SE mixer', () {
    test('mute inside the selection mutes every selected SE row — as one '
        'undo; a drawing row in the selection is passed by', () {
      final r = _Rig();
      r.select([r.s1, r.s2, r.a]);

      r.presses.toggleMute(r.s1);

      expect(
        [r.row(r.s1).muted, r.row(r.s2).muted, r.row(r.a).muted],
        [true, true, false],
      );
      r.s.undo();
      expect([r.row(r.s1).muted, r.row(r.s2).muted], [false, false]);
    });

    test('the fader and the pan set every selected SE row — one undo each; '
        'a drawing row in the selection is passed by', () {
      final r = _Rig();
      r.select([r.s1, r.s2, r.a]);

      r.presses.setGain(r.s1, 0.5);
      r.presses.setPan(r.s1, -0.4);

      expect([r.row(r.s1).audioGain, r.row(r.s2).audioGain], [0.5, 0.5]);
      expect([r.row(r.s1).audioPan, r.row(r.s2).audioPan], [-0.4, -0.4]);
      expect(
        [r.row(r.a).audioGain, r.row(r.a).audioPan],
        [1.0, 0.0],
        reason: 'a cel has no speaker, so no fader to set',
      );
      r.s.undo();
      expect(
        [r.row(r.s1).audioPan, r.row(r.s2).audioPan],
        [0.0, 0.0],
        reason: 'an edit of what the film sounds like undoes, like mute',
      );
      expect([r.row(r.s1).audioGain, r.row(r.s2).audioGain], [0.5, 0.5]);
      r.s.undo();
      expect([r.row(r.s1).audioGain, r.row(r.s2).audioGain], [1.0, 1.0]);
    });

    test('solo inside the selection solos every selected SE row, and '
        'leaves nothing to undo', () {
      final r = _Rig();
      r.select([r.s1, r.s2]);
      final depth = r.s.historyManager.undoCount;

      r.presses.toggleSolo(r.s1);

      expect(r.s.visibilitySolo.soloedSeLayerIds.value, {r.s1, r.s2});
      expect(r.s.historyManager.undoCount, depth, reason: 'monitoring');
    });

    test('pressed outside the selection, it is that row\'s alone', () {
      final r = _Rig();
      r.select([r.s2, r.a]);

      r.presses.toggleMute(r.s1);
      r.presses.setGain(r.s1, 0.25);
      r.presses.toggleSolo(r.s1);

      expect([r.row(r.s1).muted, r.row(r.s2).muted], [true, false]);
      expect([r.row(r.s1).audioGain, r.row(r.s2).audioGain], [0.25, 1.0]);
      expect(r.s.visibilitySolo.soloedSeLayerIds.value, {r.s1});
    });
  });

  test('in a gap the tracks\' own rows still spread — no cut holds them', () {
    final r = _Rig()..parkInAGap();
    expect(r.s.layers, isEmpty, reason: 'the premise: a gap');
    r.select([r.s1, r.s2]);

    r.presses.toggleMute(r.s1);
    r.presses.toggleTimesheet(r.s1);

    expect([r.row(r.s1).muted, r.row(r.s2).muted], [true, true]);
    expect(
      r.row(r.s1).onTimesheet,
      r.row(r.s2).onTimesheet,
      reason: 'the sheet switch spread as well',
    );
  });
}

/// A button with two states, pressed and read as the rail does.
typedef _Button = ({
  String name,
  void Function(SessionRowButtonPresses presses, LayerId pressed) press,
  bool Function(_Rig rig, LayerId id) read,
  bool undoes,
});

final List<_Button> _buttons = [
  (
    name: 'eye',
    press: (p, id) => p.toggleVisibility(id),
    read: (r, id) => r.row(id).isVisible,
    undoes: true,
  ),
  (
    name: 'timesheet switch',
    press: (p, id) => p.toggleTimesheet(id),
    read: (r, id) => r.row(id).onTimesheet,
    undoes: true,
  ),
  (
    name: 'fill reference',
    press: (p, id) => p.toggleFillReference(id),
    read: (r, id) => r.row(id).isFillReference,
    undoes: true,
  ),
  (
    name: 'fx master',
    press: (p, id) => p.toggleFx(id),
    read: (r, id) => fxEnabledFromState(r.s.effectsAndFx.layerFxState(id)),
    undoes: true,
  ),
  (
    name: 'onion skin',
    press: (p, id) => p.toggleOnionSkin(id),
    read: (r, id) => r.s.onionSkin.isLayerOnionSkinEnabled(id),
    undoes: false,
  ),
];

/// Three cels — A and B are selected, C stands outside — the track's two SE
/// rows and the camera.
class _Rig {
  _Rig() : s = EditorSessionManager(initialProject: createDefaultProject()) {
    addTearDown(s.dispose);
    s.layerStack.addLayerOfKind(LayerKind.animation);
    s.layerStack.addLayerOfKind(LayerKind.animation);
    expect(cels, hasLength(3), reason: 'the premise: three cels');
  }

  final EditorSessionManager s;

  List<LayerId> get cels => [
    for (final layer in s.layers)
      if (layer.kind == LayerKind.animation) layer.id,
  ];
  LayerId get a => cels[0];
  LayerId get b => cels[1];
  LayerId get c => cels[2];

  List<LayerId> get _ses => [
    for (final layer in s.repository.requireProject().tracks.single.seLayers)
      layer.id,
  ];
  LayerId get s1 => _ses[0];
  LayerId get s2 => _ses[1];

  LayerId get camera =>
      s.layers.firstWhere((layer) => layer.kind == LayerKind.camera).id;

  SessionRowButtonPresses get presses => SessionRowButtonPresses(s);

  Layer row(LayerId id) =>
      requireLayerAnywhere(s.repository.requireProject(), id);

  void select(List<LayerId> ids) =>
      s.rowSelection.value = [for (final id in ids) LayerRowAddress(id)];

  /// Stands the playhead in a GAP — a second cut behind four empty frames,
  /// the playhead among them (`import_destination_gate_test`'s recipe).
  void parkInAGap() {
    s.cutVerbs.createCut();
    final track = s.repository.requireProject().tracks.single;
    s.repository.updateCutLeadingGap(
      cutId: track.cuts[1].id,
      leadingGapFrames: 4,
    );
    s.selectCut(track.cuts[0].id);
    s.selectGlobalFrame(track.cuts[0].duration + 1);
  }
}
