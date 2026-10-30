// THE SE ROW'S MIXER: THE SPEAKER OPENS IT, ITS MUTE AND SOLO BUTTONS LAND
// ON THE SESSION AT ONCE, AND ITS BAR WRITES THE ROW'S TOTAL AT THE RELEASE.
//
// No test named this file (audit 2026-09-03) although every rail that
// mounts the speaker opens it. These pins open it on an SE row of the
// default project and press its controls.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/se_layer_mixer.dart';
import 'package:anicel/src/ui/timeline/se_sound_lane_policy.dart'
    show seSoundTotalVolumeLaneId;
import 'package:anicel/src/ui/widgets/field_slider.dart';

void main() {
  testWidgets('mute and solo press through to the session', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.layerStack.addLayerOfKind(LayerKind.se);
    final se = session.layers.firstWhere((layer) => layer.kind == LayerKind.se);
    Layer current() => _row(session, se.id);
    expect(current().muted, isFalse, reason: 'fixture');

    await _openMixer(tester, session, se.id);

    await tester.tap(find.byKey(const ValueKey<String>('se-mixer-mute')));
    await tester.pumpAndSettle();
    expect(current().muted, isTrue);

    await tester.tap(find.byKey(const ValueKey<String>('se-mixer-solo')));
    await tester.pumpAndSettle();
    expect(session.visibilitySolo.soloedSeLayerIds.value, contains(se.id));
  });

  // row-buttons-act-on-the-selection (유저 2026-09-25: 「… 소리 … 선택범위
  // 내부 레이어 조절하면 선택범위 레이어 모두 적용」): the speaker is a rail
  // button, and the window it opens presses as it does.
  testWidgets('opened on a selected row, both controls set every selected '
      'SE row', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final ses = [
      for (final layer
          in session.repository.requireProject().tracks.single.seLayers)
        layer.id,
    ];
    session.rowSelection.value = [for (final id in ses) LayerRowAddress(id)];

    await _openMixer(tester, session, ses.first);
    await tester.tap(find.byKey(const ValueKey<String>('se-mixer-mute')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('se-mixer-solo')));
    await tester.pumpAndSettle();

    for (final id in ses) {
      expect(_row(session, id).muted, isTrue, reason: '$id is selected');
    }
    expect(session.visibilitySolo.soloedSeLayerIds.value, ses.toSet());
  });

  // 🗣️I-145 (유저 2026-10-30): 「위치는 전처럼 스피커버튼안에 볼륨. 즉
  // 오디오fx에서도 조절하고 스피커버튼에서도 총 볼륨 조절」 — Q1 「따로 한 값
  // — 두 입구」.
  group('the bar is the row\'s Total — the 「오디오」 group\'s lane', () {
    late EditorSessionManager session;
    late List<LayerId> ses;

    setUp(() {
      session = EditorSessionManager(initialProject: createDefaultProject());
      ses = [
        for (final layer
            in session.repository.requireProject().tracks.single.seLayers)
          layer.id,
      ];
    });
    tearDown(() => session.dispose());

    final bar = find.byKey(const ValueKey<String>('se-mixer-total-volume'));

    double total(LayerId id) => _row(session, id).seSound.totalVolume;

    String lane(LayerId id) => session.laneVerbs.laneValueAt(
      id,
      seSoundTotalVolumeLaneId,
      0,
      frameIsGlobal: true,
    )!;

    testWidgets('🎯released, it writes the Total of every selected SE row '
        'as one undo, and the lane reads what it wrote', (tester) async {
      session.rowSelection.value = [for (final id in ses) LayerRowAddress(id)];
      await _openMixer(tester, session, ses.first);
      expect(tester.widget<FieldSlider>(bar).value, 1.0, reason: 'CONTROL');

      tester.widget<FieldSlider>(bar).onChangeEnd!(0.5);
      await tester.pumpAndSettle();

      for (final id in ses) {
        expect(total(id), 0.5, reason: '$id is selected');
        expect(lane(id), '50.00%', reason: 'one field, two doors');
      }
      session.undo();
      for (final id in ses) {
        expect(total(id), 1.0, reason: 'one undo for the whole press');
      }
    });

    testWidgets('a drag moves the bar and writes at the release alone', (
      tester,
    ) async {
      final se = ses.first;
      await _openMixer(tester, session, se);
      final drag = await tester.startGesture(tester.getCenter(bar));
      await drag.moveBy(const Offset(-30, 0));
      await drag.moveBy(const Offset(-30, 0));
      await tester.pump();
      expect(
        tester.widget<FieldSlider>(bar).value,
        lessThan(1.0),
        reason: 'CONTROL: the bar follows the hand',
      );
      expect(total(se), 1.0, reason: 'nothing written while it moves');

      await drag.up();
      await tester.pumpAndSettle();
      expect(total(se), lessThan(1.0));
      expect(tester.widget<FieldSlider>(bar).value, total(se));
    });

    testWidgets('a value typed into the lane stands on the bar', (
      tester,
    ) async {
      final se = ses.first;
      await _openMixer(tester, session, se);
      session.laneVerbs.setLaneValueAt(
        se,
        seSoundTotalVolumeLaneId,
        3,
        '30',
        frameIsGlobal: true,
        description: 'Type',
        scaleLinked: false,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FieldSlider>(bar).value, closeTo(0.3, 1e-9));
    });
  });
}

Layer _row(EditorSessionManager session, LayerId id) =>
    requireLayerAnywhere(session.repository.requireProject(), id);

Future<void> _openMixer(
  WidgetTester tester,
  EditorSessionManager session,
  LayerId layerId,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showSeLayerMixer(context, session: session, layerId: layerId),
            child: const Text('speaker'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('speaker'));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey<String>('se-layer-mixer')), findsOneWidget);
}
