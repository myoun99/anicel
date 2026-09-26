// THE SE ROW'S MIXER: THE SPEAKER OPENS IT, AND ITS MUTE AND SOLO BUTTONS
// LAND ON THE SESSION AT ONCE.
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
  testWidgets('opened on a selected row, all four controls set every '
      'selected SE row', (tester) async {
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
    tester
        .widget<FieldSlider>(find.byKey(const ValueKey<String>('se-mixer-gain')))
        .onChangeEnd!(0.5);
    tester
        .widget<FieldSlider>(find.byKey(const ValueKey<String>('se-mixer-pan')))
        .onChangeEnd!(-0.4);
    await tester.pumpAndSettle();

    for (final id in ses) {
      final row = _row(session, id);
      expect(
        [row.muted, row.audioGain, row.audioPan],
        [true, 0.5, -0.4],
        reason: '$id is selected',
      );
    }
    expect(session.visibilitySolo.soloedSeLayerIds.value, ses.toSet());
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
