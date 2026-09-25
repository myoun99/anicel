// THE SE ROW'S MIXER: THE SPEAKER OPENS IT, AND ITS MUTE AND SOLO BUTTONS
// LAND ON THE SESSION AT ONCE.
//
// No test named this file (audit 2026-09-03) although every rail that
// mounts the speaker opens it. These pins open it on an SE row of the
// default project and press the two discrete controls.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/se_layer_mixer.dart';

void main() {
  testWidgets('mute and solo press through to the session', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.layerStack.addLayerOfKind(LayerKind.se);
    final se = session.layers.firstWhere((layer) => layer.kind == LayerKind.se);
    Layer current() =>
        requireLayerAnywhere(session.repository.requireProject(), se.id);
    expect(current().muted, isFalse, reason: 'fixture');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showSeLayerMixer(context, session: session, layerId: se.id),
              child: const Text('speaker'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('speaker'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('se-layer-mixer')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('se-mixer-mute')));
    await tester.pumpAndSettle();
    expect(current().muted, isTrue);

    await tester.tap(find.byKey(const ValueKey<String>('se-mixer-solo')));
    await tester.pumpAndSettle();
    expect(session.visibilitySolo.soloedSeLayerIds.value, contains(se.id));
  });
}
