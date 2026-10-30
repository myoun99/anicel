import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
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
import 'package:anicel/src/services/project_lookup.dart' show rowTwirlsOf;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/lane_verbs.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/text/model_vocabulary.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectLaneId;
import 'package:anicel/src/ui/timeline/layer_name_commands.dart';
import 'package:anicel/src/ui/timeline/timeline_action_toolbar.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;
import '../flyout_test_helpers.dart' show readCommandEnabled;

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

Layer _row(String id, {LayerKind kind = LayerKind.animation}) => Layer(
  id: LayerId(id),
  name: id,
  kind: kind,
  frames: const [],
  timeline: const {},
);

/// A cut whose rows are x · y, bottom → top, [_both] on y — and [over]
/// above them, and the track's S rows [se].
EditorSessionManager _session({
  List<Layer> over = const [],
  List<Layer> se = const [],
}) {
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
              layers: [_row('x'), _row('y'), ...over],
            ),
          ],
          seLayers: se,
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
      LaneRowAddress(const LayerId('y'), effectLaneId(blur, 'blurriness')),
    ]);

    expect(lanesOf(session).effectsNamedBySelectedRows, isEmpty);
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

  testWidgets('a plugin\'s effect is listed by its plugin\'s name (I-132)', (
    tester,
  ) async {
    final session = _session();
    session.effectsAndFx.addEffectToActiveLayer(
      EffectKind.plugin,
      plugin: FxPluginDescription.fromJson({
        'spec': 1,
        'id': 'com.example.glow',
        'name': 'Glow',
        'vendor': 'Example',
        'version': '1',
        'can': ['cpu'],
        'params': [],
      }),
    );
    _select(session, [
      const LayerRowAddress(LayerId('x')),
      _header(session, EffectKind.plugin),
    ]);

    await pressDelete(tester, session);

    expect(find.text('y · Glow'), findsOneWidget);
  });

  /// 🗣️F-476-Q1 (유저 2026-10-27): 「b + 복제도」 — the pill's copy, cut,
  /// paste and duplicate take the effects the rail names as its delete does.
  group('copy · cut · paste · duplicate (F-476-Q1)', () {
    /// y's blur moved off its default, so a copy has a number to carry.
    void blurAtSeven(EditorSessionManager session) {
      final blur = _layer(session, 'y').effects.first;
      session.effectsAndFx.updateLayerEffects(const LayerId('y'), [
        blur.withParameter('blurriness', EffectParameter(value: 7)),
        ..._layer(session, 'y').effects.skip(1),
      ]);
    }

    test('「고른 fx 를 복사 … 다른 레이어에 서서 붙여넣으면 그 레이어의 fx '
        '끝에」: the copy takes the effect, the paste puts it on the row you '
        'stand on — the same numbers, an effect of its own, one undo', () {
      final session = _session();
      blurAtSeven(session);
      final pill = TimelineToolbarPanelContext(session);
      _select(session, [_header(session, EffectKind.blur)]);

      expect(pill.canCopyFrame, isTrue);
      pill.copyFrame();
      session.selectLayer(const LayerId('x'));
      final steps = session.historyManager.undoCount;
      expect(pill.canPasteIndependentFrame, isTrue);
      pill.pasteIndependentFrame();

      final pasted = _layer(session, 'x').effects.single;
      expect(pasted.kind, EffectKind.blur);
      expect(pasted.parameterOf('blurriness').value, 7);
      expect(pasted.id, isNot(_idOf(session, EffectKind.blur)));
      expect(_effectsOf(session, 'y'), _both, reason: 'a copy leaves them');
      expect(session.historyManager.undoCount, steps + 1, reason: 'ONE step');
      session.undo();
      expect(_effectsOf(session, 'x'), isEmpty);
    });

    test('pasted twice, they are two effects, each shown where it lands', () {
      final session = _session();
      final pill = TimelineToolbarPanelContext(session);
      _select(session, [
        _header(session, EffectKind.blur),
        _header(session, EffectKind.hueSaturation),
      ]);
      pill.copyFrame();
      session.selectLayer(const LayerId('x'));

      pill.pasteIndependentFrame();
      pill.pasteIndependentFrame();

      final pasted = _layer(session, 'x').effects;
      expect([for (final effect in pasted) effect.kind], [..._both, ..._both]);
      expect({for (final effect in pasted) effect.id}, hasLength(4));
      final twirls = rowTwirlsOf(
        session.repository.requireProject(),
        const LayerId('x'),
      )!;
      expect(twirls.lanesExpanded, isTrue);
      expect(twirls.expandedLaneGroups, {
        for (final effect in pasted) effectGroupLaneId(effect.id),
      }, reason: 'F-396: an effect that appears shows itself');
    });

    test('the cut takes it off its row and into the hand, in one undo', () {
      final session = _session();
      final pill = TimelineToolbarPanelContext(session);
      _select(session, [_header(session, EffectKind.hueSaturation)]);
      final steps = session.historyManager.undoCount;

      expect(pill.canCutRun, isTrue);
      pill.cutRun();
      expect(_effectsOf(session, 'y'), [EffectKind.blur]);
      expect(session.historyManager.undoCount, steps + 1, reason: 'ONE step');

      session.selectLayer(const LayerId('x'));
      pill.pasteIndependentFrame();
      expect(_effectsOf(session, 'x'), [EffectKind.hueSaturation]);
    });

    // ↩️It pinned the storyboard's paste dark here, as its fx menu's add
    // was on the V row it stands on. The add takes the V row now (-Q1), and
    // so does the paste: the_conte_panel_adds_fx_as_the_timeline_does_test.
    test('effects in hand light no link paste', () {
      final session = _session();
      _select(session, [_header(session, EffectKind.blur)]);
      TimelineToolbarPanelContext(session).copyFrame();
      session.selectLayer(const LayerId('x'));

      expect(TimelineToolbarPanelContext(session).canPasteLinkedFrame, isFalse);
    });

    test('one copy in hand: effects let the rows go, and rows the effects', () {
      final session = _session();
      final pill = TimelineToolbarPanelContext(session);
      _select(session, [const LayerRowAddress(LayerId('x'))]);
      pill.copyFrame();
      expect(session.layerClipboard.hasLayerClipboard, isTrue);

      _select(session, [_header(session, EffectKind.blur)]);
      pill.copyFrame();
      expect(session.effectClipboard.holdsEffects, isTrue);
      expect(session.layerClipboard.hasLayerClipboard, isFalse);

      _select(session, [const LayerRowAddress(LayerId('x'))]);
      pill.copyFrame();
      expect(session.effectClipboard.holdsEffects, isFalse);
    });

    test('⚠️rows beside another row\'s header: the copy takes the rows '
        '(F-476-Q3: 「지금대로 — 행이 먼저」)', () {
      final session = _session();
      _select(session, [
        const LayerRowAddress(LayerId('x')),
        _header(session, EffectKind.hueSaturation),
      ]);

      TimelineToolbarPanelContext(session).copyFrame();

      expect(session.layerClipboard.hasLayerClipboard, isTrue);
      expect(session.effectClipboard.holdsEffects, isFalse);
    });

    test('a paste puts down what the row takes, as an add would: a cel '
        'number fx stays off a folder, whose drawings carry none', () {
      final session = _session(over: [_row('f', kind: LayerKind.folder)]);
      session.effectsAndFx.addEffectToActiveLayer(EffectKind.celNumber);
      final celNumber = LaneRowAddress(
        const LayerId('y'),
        effectGroupLaneId(_idOf(session, EffectKind.celNumber)),
      );
      final pill = TimelineToolbarPanelContext(session);

      _select(session, [celNumber]);
      pill.copyFrame();
      session.selectLayer(const LayerId('f'));
      expect(pill.canPasteIndependentFrame, isFalse, reason: 'it takes none');

      _select(session, [_header(session, EffectKind.blur), celNumber]);
      pill.copyFrame();
      session.selectLayer(const LayerId('f'));
      expect(pill.canPasteIndependentFrame, isTrue, reason: 'it takes one');
      pill.pasteIndependentFrame();
      expect(_effectsOf(session, 'f'), [EffectKind.blur]);
    });

    test('a cut over two rows\' headers is ONE undo', () {
      final session = _session();
      session.effectsAndFx.addEffectToTrack(_track, EffectKind.blur);
      _select(session, [
        _header(session, EffectKind.blur),
        LaneRowAddress(
          trackTransformLaneCarrierId(_track),
          effectGroupLaneId(_trackEffects(session).single.id),
        ),
      ]);
      final steps = session.historyManager.undoCount;

      TimelineToolbarPanelContext(session).cutRun();

      expect(_effectsOf(session, 'y'), [EffectKind.hueSaturation]);
      expect(_trackEffects(session), isEmpty);
      expect(session.historyManager.undoCount, steps + 1, reason: 'ONE step');
      session.undo();
      expect(_effectsOf(session, 'y'), _both);
      expect(_trackEffects(session), hasLength(1));
    });

    test('standing on an S row — a row the duplicate never copies — its fx '
        'header is duplicated all the same', () {
      final session = _session(se: [_row('s1', kind: LayerKind.se)]);
      List<LayerEffect> seEffects() =>
          session.repository.requireProject().tracks.single.seLayers.single
              .effects;
      session.selectLayer(const LayerId('s1'));
      session.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
      _select(session, [
        LaneRowAddress(
          const LayerId('s1'),
          effectGroupLaneId(seEffects().single.id),
        ),
      ]);
      final pill = TimelineToolbarPanelContext(session);

      expect(pill.canDuplicate, isTrue);
      pill.duplicate();

      expect([for (final effect in seEffects()) effect.kind], [
        EffectKind.blur,
        EffectKind.blur,
      ]);
    });

    for (final (panel, contextOf) in <(String, ToolbarPanelContext Function(
      EditorSessionManager,
    ))>[
      ('timeline', TimelineToolbarPanelContext.new),
      ('storyboard', StoryboardToolbarPanelContext.new),
    ]) {
      test('「복제 … 같은 레이어에 하나 더(바로 아래에)」 on the $panel: a copy '
          'of each named effect right below it, in one undo', () {
        final session = _session();
        blurAtSeven(session);
        final source = _idOf(session, EffectKind.blur);
        final pill = contextOf(session);
        _select(session, [_header(session, EffectKind.blur)]);
        final steps = session.historyManager.undoCount;

        expect(pill.canDuplicate, isTrue);
        pill.duplicate();

        final chain = _layer(session, 'y').effects;
        expect([for (final effect in chain) effect.kind], [
          EffectKind.blur,
          EffectKind.blur,
          EffectKind.hueSaturation,
        ]);
        expect(chain.first.id, source);
        expect(chain[1].id, isNot(source));
        expect(chain[1].parameterOf('blurriness').value, 7);
        expect(
          rowTwirlsOf(
            session.repository.requireProject(),
            const LayerId('y'),
          )!.expandedLaneGroups,
          contains(effectGroupLaneId(chain[1].id)),
          reason: 'F-396: an effect that appears shows itself',
        );
        expect(_stack(session), ['x', 'y'], reason: 'no row is duplicated');
        expect(session.historyManager.undoCount, steps + 1, reason: 'ONE step');
        session.undo();
        expect(_effectsOf(session, 'y'), _both);
      });
    }

    test('the V row\'s header duplicates the TRACK\'s effect', () {
      final session = _session();
      session.effectsAndFx.addEffectToTrack(_track, EffectKind.blur);
      _select(session, [
        LaneRowAddress(
          trackTransformLaneCarrierId(_track),
          effectGroupLaneId(_trackEffects(session).single.id),
        ),
      ]);

      TimelineToolbarPanelContext(session).duplicate();

      expect([for (final effect in _trackEffects(session)) effect.kind], [
        EffectKind.blur,
        EffectKind.blur,
      ]);
      expect(_effectsOf(session, 'y'), _both);
    });

    test('parked in a gap, with no cut to duplicate, the storyboard '
        'duplicates the V row\'s fx its rail selected', () {
      final session = _session();
      session.effectsAndFx.addEffectToTrack(_track, EffectKind.blur);
      session.cutVerbs.createCut();
      final cuts = session.repository.requireProject().tracks.single.cuts;
      session.repository.updateCutLeadingGap(
        cutId: cuts[1].id,
        leadingGapFrames: 4,
      );
      session.selectCut(cuts[0].id);
      session.selectGlobalFrame(cuts[0].duration + 1);
      expect(session.activeCutOrNull, isNull, reason: '⛔전제: in the gap');
      _select(session, [
        LaneRowAddress(
          trackTransformLaneCarrierId(_track),
          effectGroupLaneId(_trackEffects(session).single.id),
        ),
      ]);
      final pill = StoryboardToolbarPanelContext(session);

      expect(pill.canDuplicate, isTrue);
      pill.duplicate();
      expect(_trackEffects(session), hasLength(2));
    });

    testWidgets('on the bar: a copy over the rail\'s fx header lights the '
        'paste beside it', (tester) async {
      final session = _session();
      await tester.binding.setSurfaceSize(const Size(2400, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Align(
              alignment: Alignment.topLeft,
              child: TimelineActionToolbar(
                session: session,
                panelContext: TimelineToolbarPanelContext(session),
                onAddLayer: () {},
                onRenameLayer: () {},
                onDeleteLayer: () {},
                onEditInstance: () {},
                onCreateInstance: () {},
              ),
            ),
          ),
        ),
      );
      _select(session, [_header(session, EffectKind.blur)]);
      await tester.pump();
      const paste = ValueKey<String>('shared-paste-independent-button');
      expect(await readCommandEnabled(tester, paste), isFalse, reason: '⛔전제');

      const copy = ValueKey<String>('shared-copy-button');
      await tester.tap(find.byKey(copy));
      await tester.pump();

      expect(await readCommandEnabled(tester, paste), isTrue);
    });
  });
}
