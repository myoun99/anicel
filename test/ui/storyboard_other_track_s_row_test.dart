// ANOTHER TRACK'S S ROW ANSWERS ITS BUTTONS (other-track-s-row-fx-and-mixer).
//
// The storyboard rail carries every track's S rows, and the eye and the
// sheet switch reached all of them. The fx button and the speaker did not:
// both found their row through the ACTIVE track alone. Measured on this
// rail on 2026-09-25 — two tracks, the first active: the second track's fx
// press changed nothing and its speaker opened no mixer.
//
// Each case presses the SECOND track's row; the first track's is the
// control that always worked.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';

void main() {
  tearDown(debugClearValueControlPointers);

  testWidgets('its fx button switches its whole row — transform and effects',
      (tester) async {
    final s = await _rail(tester);
    expect(s.activeTrack.id, const TrackId('t1'), reason: 'the premise');
    expect(
      s.effectsAndFx.layerFxState(_other),
      LayerFxState.on,
      reason: 'the premise',
    );

    await tester.tap(
      find.byKey(ValueKey<String>('storyboard-layer-fx-${_other.value}')),
    );
    await tester.pumpAndSettle();

    final row = _row(s, _other);
    expect(row.transformEnabled, isFalse);
    expect(row.effects.single.enabled, isFalse);
    expect(
      s.effectsAndFx.layerFxState(_other),
      LayerFxState.off,
      reason: 'and the button reads what it did — it read 「on」 forever',
    );
  });

  testWidgets('its speaker opens its mixer, and the mixer mutes it', (
    tester,
  ) async {
    final s = await _rail(tester);

    await tester.tap(
      find.byKey(ValueKey<String>('storyboard-layer-mute-${_other.value}')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('se-layer-mixer')),
      findsOneWidget,
      reason: 'it opened blank',
    );

    await tester.tap(find.byKey(const ValueKey<String>('se-mixer-mute')));
    await tester.pumpAndSettle();

    expect(_row(s, _other).muted, isTrue);
  });
}

/// The second track's S row — on a track that is not the active one.
const _other = LayerId('t2-s1');

Layer _row(EditorSessionManager s, LayerId id) =>
    requireLayerAnywhere(s.repository.requireProject(), id);

/// The storyboard tab over two tracks; the second's S row carries an
/// effect, so the master has a chain to switch as well as the transform.
Future<EditorSessionManager> _rail(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  Track track(String id, {List<LayerEffect> effects = const []}) => Track(
    id: TrackId(id),
    name: id,
    seLayers: [
      Layer(
        id: LayerId('$id-s1'),
        name: 'S1',
        kind: LayerKind.se,
        frames: const [],
        timeline: const {},
        effects: effects,
      ),
    ],
    cuts: [
      Cut(
        id: CutId('$id-cut'),
        name: '$id cut',
        duration: 12,
        canvasSize: const CanvasSize(width: 640, height: 360),
        layers: [
          Layer(
            id: LayerId('$id-cel'),
            name: 'A',
            frames: const [],
            timeline: const {},
          ),
        ],
      ),
    ],
  );
  final s = EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('two-tracks'),
      name: 'Two tracks',
      createdAt: DateTime.utc(2026, 9, 25),
      tracks: [
        track('t1'),
        track(
          't2',
          effects: [
            LayerEffect(id: const EffectId('glow'), kind: EffectKind.blur),
          ],
        ),
      ],
    ),
  );
  addTearDown(s.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: s,
          builder: (context, _) => StoryboardTabHost(
            session: s,
            pixelsPerFrame: 12,
            onPixelsPerFrameChanged: (_) {},
            showSeconds: false,
            onShowSecondsChanged: (_) {},
            thumbnails: null,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return s;
}
