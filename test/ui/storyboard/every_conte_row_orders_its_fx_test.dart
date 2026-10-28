import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId;

import '../../helpers/named_finders.dart';
import '../../helpers/storyboard_host.dart';

/// **I-89 ①ⓓ — every row the conte panel twirls down orders its fx there.**
///
/// 🗣️유저 2026-10-13: 「지금 타임라인패널에만 그래프버튼있는데 다시 말하지만
/// 이런건 다 콘티패널에도 동일하게 있어야해. 같은 법으로」. On the timeline's
/// rail a layer's fx headers are grabbed and dropped to re-order its chain;
/// the conte panel did it for the V row alone. An S row's chain — on any
/// track — and a conte row's, its layer's in the cut the session stands in,
/// are ordered here by the same drag.
///
/// Track t1: cuts a [0, 24) and b [24, 48), each with a conte wearing Blur
/// then Hue, and S1 wearing the same. Track t2: cut c, and S2 wearing them.
void main() {
  const t1 = TrackId('t1');
  const t2 = TrackId('t2');
  const blur = EffectId('blur');
  const hue = EffectId('hue');
  final conteRow = trackConteRowId(t1);

  List<LayerEffect> chain() => [
    LayerEffect.defaults(id: blur, kind: EffectKind.blur),
    LayerEffect.defaults(id: hue, kind: EffectKind.hueSaturation),
  ];

  Layer seLayer(String id) => Layer(
    id: LayerId(id),
    name: id,
    kind: LayerKind.se,
    frames: [Frame(id: FrameId('$id-f'), duration: 8, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('$id-f'), length: 8)},
    effects: chain(),
  );

  Cut cutOf(String id, {bool conte = false}) => Cut(
    id: CutId(id),
    name: id,
    duration: 24,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [
      Layer(id: LayerId('$id-cel'), name: 'A', frames: const []),
      if (conte)
        Layer(
          id: LayerId('$id-conte'),
          name: 'Conte',
          kind: LayerKind.storyboard,
          frames: [
            Frame(id: FrameId('$id-panel'), duration: 24, strokes: const []),
          ],
          timeline: {
            0: TimelineExposure.drawing(FrameId('$id-panel'), length: 24),
          },
          effects: chain(),
        ),
    ],
  );

  Project film() => Project(
    id: const ProjectId('conte-fx-order'),
    name: 'Conte fx order',
    createdAt: DateTime.utc(2026, 10, 18),
    tracks: [
      Track(
        id: t1,
        name: 'V1',
        cuts: [cutOf('a', conte: true), cutOf('b', conte: true)],
        seLayers: [seLayer('s1')],
      ),
      Track(
        id: t2,
        name: 'V2',
        cuts: [cutOf('c')],
        seLayers: [seLayer('s2')],
      ),
    ],
  );

  /// The host over a session holding [film], standing in [standIn], with
  /// [twirl]'s lanes open — wired as the workspace wires it, the row drags
  /// the host's own.
  Future<EditorSessionManager> pumpHost(
    WidgetTester tester, {
    required String twirl,
    CutId standIn = const CutId('a'),
  }) async {
    final session = EditorSessionManager(initialProject: film());
    addTearDown(session.dispose);
    session.selectCut(standIn);
    await pumpStoryboardHostOn(
      tester,
      session,
      surface: const Size(1600, 1200),
      pixelsPerFrame: 12,
    );
    await tester.tap(find.named('storyboard-lane-toggle-$twirl'));
    await tester.pumpAndSettle();
    return session;
  }

  Finder header(Object rowId, EffectId effect) => find.byKey(
    ValueKey<String>(
      'storyboard-lane-label-$rowId-${effectGroupLaneId(effect)}',
    ),
  );

  List<EffectId> chainOf(EditorSessionManager session, LayerId layerId) {
    for (final track in session.repository.requireProject().tracks) {
      for (final layer in [
        ...track.seLayers,
        for (final cut in track.cuts) ...cut.layers,
      ]) {
        if (layer.id == layerId) {
          return [for (final effect in layer.effects) effect.id];
        }
      }
    }
    throw StateError('no $layerId');
  }

  /// [rowId]'s Blur header dragged down past its Hue — one lane row of
  /// travel, the step the layer rail commits on — TWICE, as the host's own
  /// hooks have it: the first drag SELECTS and moves nothing (⑨'s law,
  /// `storyboard_track_reorder_test`), the second, started inside the
  /// selection, moves. [layerId]'s chain is read between the two.
  Future<void> dragPastTheNext(
    WidgetTester tester,
    EditorSessionManager session,
    Object rowId,
    LayerId layerId,
  ) async {
    final from = header(rowId, blur);
    final past = header(rowId, hue);
    await tester.ensureVisible(from);
    await tester.pumpAndSettle();
    expect(from, findsOneWidget, reason: '⛔전제: $rowId shows its Blur');
    expect(past, findsOneWidget, reason: '⛔전제: $rowId shows its Hue');
    final step = tester.getCenter(past).dy - tester.getCenter(from).dy;
    await tester.drag(from, Offset(0, step));
    await tester.pumpAndSettle();
    expect(
      chainOf(session, layerId),
      [blur, hue],
      reason: 'the first drag selected and moved nothing',
    );
    await tester.drag(from, Offset(0, step));
    await tester.pumpAndSettle();
  }

  /// Drains the prerender scheduler's debounced warming — the established
  /// idiom for a test that commits through the session.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('an S row\'s fx header re-orders its chain, as the timeline\'s '
      'rail does', (tester) async {
    final session = await pumpHost(tester, twirl: 's1');
    await dragPastTheNext(tester, session, 's1', const LayerId('s1'));
    expect(chainOf(session, const LayerId('s1')), [hue, blur]);
    session.undo();
    expect(chainOf(session, const LayerId('s1')), [blur, hue]);
    await settle(tester);
  });

  testWidgets('and an S row on a track the session does not stand on — the '
      'row is the track\'s, wherever the session stands', (tester) async {
    final session = await pumpHost(tester, twirl: 's2');
    await dragPastTheNext(tester, session, 's2', const LayerId('s2'));
    expect(chainOf(session, const LayerId('s2')), [hue, blur]);
    await settle(tester);
  });

  testWidgets('a conte row\'s fx header re-orders the chain of its conte in '
      'the cut the session stands in — and the head every conte of the '
      'track wears takes the order (I-73)', (tester) async {
    final session = await pumpHost(tester, twirl: 'a-conte');
    await dragPastTheNext(
      tester,
      session,
      conteRow,
      const LayerId('a-conte'),
    );
    expect(chainOf(session, const LayerId('a-conte')), [hue, blur]);
    expect(chainOf(session, const LayerId('b-conte')), [hue, blur]);
    session.undo();
    expect(chainOf(session, const LayerId('a-conte')), [blur, hue]);
    await settle(tester);
  });

  testWidgets('⛔where the session stands in no cut of the conte row\'s '
      'track, its fx headers move nothing — nothing there is edited '
      '(I-73 ④)', (tester) async {
    final session = await pumpHost(
      tester,
      twirl: 'a-conte',
      standIn: const CutId('c'),
    );
    await dragPastTheNext(
      tester,
      session,
      conteRow,
      const LayerId('a-conte'),
    );
    expect(chainOf(session, const LayerId('a-conte')), [blur, hue]);
    expect(chainOf(session, const LayerId('b-conte')), [blur, hue]);
    await settle(tester);
  });
}
