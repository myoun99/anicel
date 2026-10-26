import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/pill_subject.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/track_transform_lane_carrier.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/lane_verbs.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/text/model_vocabulary.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectLaneId;
import 'package:anicel/src/ui/timeline/layer_name_commands.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

/// 🗣️F-476 (유저 2026-10-26): 「레이어쪽에서 fx를 선택범위로 선택하고
/// 삭제한다는거, 몇번을 말하는건지 … 레이어쪽 fx 선택범위로 선택하고
/// 삭제할수있게하라고. 물론 기본fx는 삭제못하는데 fx 추가해서 넣은거
/// 삭제하는기능 … 삭제같은 공용버튼도 선택범위로 대상 인식하는거 fx만
/// 빠져있는거같은데 법 통일」.
///
/// A selection swept down the RAIL names an fx by its header row, and the
/// shared delete takes it — by the law a range over the header already took
/// it on the frame side (F-87). ↩️The delete's rows rung counted layer rows
/// alone, so a rail selection of fx headers fell through to the frame axis.
///
/// The collaborator the effects are named in — named so
/// `tool/mutation_run.dart` runs this file for it.
LaneVerbs lanesOf(EditorSessionManager session) => session.laneVerbs;

const _track = TrackId('f476-track');

/// The two effects y carries, as the rail lists them under it.
const _both = [EffectKind.blur, EffectKind.hueSaturation];

List<LayerEffect> _trackEffects(EditorSessionManager session) =>
    session.repository.requireProject().tracks.single.effects;

Layer _row(String id) => Layer(
  id: LayerId(id),
  name: id,
  kind: LayerKind.animation,
  frames: const [],
  timeline: const {},
);

/// A cut whose rows are x · y, bottom → top, [_both] on y.
EditorSessionManager _session() {
  final session = EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('f476'),
      name: 'F-476',
      createdAt: DateTime.utc(2026, 10, 27),
      tracks: [
        Track(
          id: _track,
          name: 'Video',
          cuts: [
            Cut(
              id: const CutId('f476-cut'),
              name: 'c1',
              duration: 24,
              canvasSize: const CanvasSize(width: 320, height: 180),
              layers: [_row('x'), _row('y')],
            ),
          ],
        ),
      ],
    ),
  );
  addTearDown(session.dispose);
  session.selectLayer(const LayerId('y'));
  session.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
  session.effectsAndFx.addEffectToActiveLayer(EffectKind.hueSaturation);
  return session;
}

Layer _layer(EditorSessionManager session, String id) => session
    .requireActiveCut
    .layers
    .firstWhere((layer) => layer.id == LayerId(id));

List<EffectKind> _effectsOf(EditorSessionManager session, String id) => [
  for (final effect in _layer(session, id).effects) effect.kind,
];

EffectId _idOf(EditorSessionManager session, EffectKind kind) => _layer(
  session,
  'y',
).effects.firstWhere((effect) => effect.kind == kind).id;

LaneRowAddress _header(EditorSessionManager session, EffectKind kind) =>
    LaneRowAddress(const LayerId('y'), effectGroupLaneId(_idOf(session, kind)));

void _select(EditorSessionManager session, List<TimelineRowAddress> rows) {
  session.rowSelectionVerbs.beginRowSelection(rows.first);
  session.rowSelectionVerbs.rowSelection.value = rows;
}

List<String> _stack(EditorSessionManager session) => [
  for (final layer in session.requireActiveCut.layers) layer.id.value,
];

void main() {
  test('⛔전제: y carries the two effects the rail lists under it', () {
    final session = _session();
    expect(_effectsOf(session, 'y'), _both);
    expect(_effectsOf(session, 'x'), isEmpty);
  });

  test('「fx 선택범위로 선택하고 삭제」: a rail selection of an fx header lights '
      'the delete as ROWS, and the press takes that effect alone', () {
    final session = _session();
    _select(session, [_header(session, EffectKind.blur)]);

    expect(session.deleteSubject, PillSubject.layers);
    session.deleteSelectionSubject();

    expect(_effectsOf(session, 'y'), [EffectKind.hueSaturation]);
    expect(_stack(session), ['x', 'y'], reason: 'no row goes');
  });

  test('every header selected goes, in ONE undo that brings them back', () {
    final session = _session();
    final steps = session.historyManager.undoCount;
    _select(session, [
      _header(session, EffectKind.blur),
      _header(session, EffectKind.hueSaturation),
    ]);

    session.deleteSelectionSubject();
    expect(_effectsOf(session, 'y'), isEmpty);
    expect(session.historyManager.undoCount, steps + 1, reason: 'ONE step');

    session.undo();
    expect(_effectsOf(session, 'y'), _both);
  });

  test('a layer row beside another row\'s header: the layer goes and the '
      'effect goes, in one step', () {
    final session = _session();
    final steps = session.historyManager.undoCount;
    _select(session, [
      const LayerRowAddress(LayerId('x')),
      _header(session, EffectKind.hueSaturation),
    ]);

    session.deleteSelectionSubject();

    expect(_stack(session), ['y']);
    expect(_effectsOf(session, 'y'), [EffectKind.blur]);
    expect(session.historyManager.undoCount, steps + 1, reason: 'ONE step');
    session.undo();
    expect(_stack(session), ['x', 'y']);
    expect(_effectsOf(session, 'y'), _both);
  });

  test('a header whose row goes too is that row\'s: nothing is taken off a '
      'row on its way out', () {
    final session = _session();
    _select(session, [
      const LayerRowAddress(LayerId('y')),
      _header(session, EffectKind.blur),
    ]);

    expect(session.effectsToDeleteOfRows(), isEmpty);
    session.deleteSelectionSubject();
    expect(_stack(session), ['x']);

    session.undo();
    expect(
      _effectsOf(session, 'y'),
      _both,
      reason: 'the row comes back with its chain whole',
    );
  });

  test('「기본fx는 삭제못하는데」: the Transform header and a parameter row name '
      'no effect', () {
    final session = _session();
    final blur = _idOf(session, EffectKind.blur);
    _select(session, [
      LaneRowAddress(const LayerId('y'), transformGroupHeaderLane.laneId),
      LaneRowAddress(const LayerId('y'), effectLaneId(blur, 'blurX')),
    ]);

    expect(lanesOf(session).effectsNamedByRows(
      session.rowSelectionVerbs.rowSelection.value,
    ), isEmpty);
    expect(session.deleteSubject, isNot(PillSubject.layers));
  });

  test('the V row\'s fx header in the rail takes the TRACK\'s effect by the '
      'same law', () {
    final session = _session();
    session.effectsAndFx.addEffectToTrack(_track, EffectKind.blur);
    final trackBlur = _trackEffects(session).single.id;
    _select(session, [
      LaneRowAddress(
        trackTransformLaneCarrierId(_track),
        effectGroupLaneId(trackBlur),
      ),
    ]);

    expect(session.deleteSubject, PillSubject.layers);
    session.deleteSelectionSubject();

    expect(_trackEffects(session), isEmpty);
    expect(
      _effectsOf(session, 'y'),
      _both,
      reason: 'the cut\'s rows keep theirs',
    );
  });

  for (final (panel, contextOf) in <(String, ToolbarPanelContext Function(
    EditorSessionManager,
  ))>[
    ('timeline', TimelineToolbarPanelContext.new),
    ('storyboard', StoryboardToolbarPanelContext.new),
  ]) {
    test('the $panel\'s pill asks the same rows rung', () {
      final session = _session();
      _select(session, [_header(session, EffectKind.blur)]);
      final pill = contextOf(session);

      expect(pill.deleteSubject, PillSubject.layers);
      pill.deleteSelectionSubject();

      expect(_effectsOf(session, 'y'), [EffectKind.hueSaturation]);
    });
  }

  Future<void> pressDelete(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => deleteRowSelectionWithDialog(context, session),
              child: const Text('delete'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('delete'));
    await tester.pumpAndSettle();
  }

  testWidgets('effects alone go unasked, as a range over their headers takes '
      'them — the window asks before ROWS go', (tester) async {
    final session = _session();
    _select(session, [_header(session, EffectKind.blur)]);

    await pressDelete(tester, session);

    expect(find.text(AppText.strings.deleteLayersMessage), findsNothing);
    expect(_effectsOf(session, 'y'), [EffectKind.hueSaturation]);
  });

  testWidgets('beside a row that goes, the window lists the effect under a '
      'heading of its own, and nothing goes before Yes', (tester) async {
    final session = _session();
    _select(session, [
      const LayerRowAddress(LayerId('x')),
      _header(session, EffectKind.hueSaturation),
    ]);

    await pressDelete(tester, session);

    final strings = AppText.strings;
    expect(find.text('${strings.deleteLayersHeading} (1)'), findsOneWidget);
    expect(find.text('${strings.deleteEffectsHeading} (1)'), findsOneWidget);
    expect(
      find.text('y · ${EffectKind.hueSaturation.labelFor(AppText.language)}'),
      findsOneWidget,
    );
    expect(_effectsOf(session, 'y'), _both);

    await tester.tap(
      find.byKey(const ValueKey<String>('delete-layer-confirm-button')),
    );
    await tester.pumpAndSettle();

    expect(_stack(session), ['y']);
    expect(_effectsOf(session, 'y'), [EffectKind.blur]);
  });
}
