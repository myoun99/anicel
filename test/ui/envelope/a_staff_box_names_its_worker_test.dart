import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_source.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_ink.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_paper.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_tab_host.dart';

/// 🗣️I-127-Q1 (유저 2026-10-25): 「봉투 용지 패널에도 넣고, 셀 출력은 그대로
/// 부른다」 — a box that prints a stage's worker is typed into as the
/// timesheet's name box is, and what is typed is that worker on the cut:
/// the name 컷 설정 shows.
void main() {
  const cutId = CutId('39');
  const key = LayerMark(process: LayerProcess.key);
  const inbetween = LayerMark(process: LayerProcess.inbetween);

  Project project() => Project(
    id: const ProjectId('envelope-project'),
    name: 'Envelope',
    createdAt: DateTime.utc(2026, 10, 27),
    tracks: [
      Track(
        id: const TrackId('t1'),
        name: 'Video',
        cuts: [
          Cut(
            id: cutId,
            name: '39',
            duration: 24,
            canvasSize: const CanvasSize(width: 640, height: 480),
            layers: [
              Layer(
                id: const LayerId('a'),
                name: 'A',
                kind: LayerKind.animation,
                frames: const [],
              ),
            ],
          ),
        ],
      ),
    ],
  );

  /// The envelope panel on the 39's envelope, its brush switch at
  /// [brushAllowed].
  Future<EditorSessionManager> pumpEnvelope(
    WidgetTester tester, {
    bool brushAllowed = false,
  }) async {
    final session = EditorSessionManager(initialProject: project());
    addTearDown(session.dispose);
    final ink = CutEnvelopeInkController();
    addTearDown(ink.dispose);
    final tool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    addTearDown(tool.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Built again when the project moves, as the workspace builds it
          // (`CutEnvelopeTabHost.printedBy`).
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => CutEnvelopeTabHost(
              session: session,
              inkController: ink,
              brushToolState: tool,
              brushAllowed: brushAllowed,
              onBrushAllowedChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  /// The worker [stage]'s box prints on the envelope shown.
  String? printed(WidgetTester tester, LayerMark stage) => tester
      .widget<CutEnvelopePaper>(find.byType(CutEnvelopePaper))
      .source
      .staff[stage.keySlug];

  final field = find.byKey(const ValueKey<String>('cut-envelope-edit-field'));
  final gengaBox = find.byKey(
    const ValueKey<String>('cut-envelope-staff-name-genga-edit'),
  );
  final dougaBox = find.byKey(
    const ValueKey<String>('cut-envelope-staff-name-douga-edit'),
  );

  String workerOf(EditorSessionManager session, LayerMark stage) =>
      session.cutById(cutId)!.metadata.staffNameFor(stage);

  /// Types [name] into [box] and lands it.
  Future<void> typeInto(WidgetTester tester, Finder box, String name) async {
    await tester.tap(box);
    await tester.pumpAndSettle();
    await tester.enterText(field, name);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  testWidgets('🎯a name typed into the 原画 box is the cut\'s key worker — '
      'the 動画 box\'s stays its own — and one undo takes it back', (
    tester,
  ) async {
    final session = await pumpEnvelope(tester);

    await typeInto(tester, gengaBox, '大川ユキ');

    expect(workerOf(session, key), '大川ユキ');
    expect(workerOf(session, inbetween), isEmpty);
    expect(printed(tester, key), '大川ユキ', reason: 'the envelope prints it');

    session.undo();
    await tester.pumpAndSettle();
    expect(workerOf(session, key), isEmpty);
    expect(printed(tester, key), isNull);
  });

  testWidgets('a box opens on the name it prints', (tester) async {
    final session = await pumpEnvelope(tester);
    session.cutVerbs.setCutStaffName(cutId, inbetween, '森 ハル');
    await tester.pumpAndSettle();

    await tester.tap(dougaBox);
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(field).controller!.text, '森 ハル');
  });

  testWidgets('with the brush on, a press on the box is the pen\'s', (
    tester,
  ) async {
    await pumpEnvelope(tester, brushAllowed: true);

    await tester.tap(gengaBox, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(field, findsNothing);
  });

  test('a box names the stage its binding prints the worker of', () {
    LayerMark? stageOf(String binding) =>
        switch (envelopeTypedValueOf(binding, const CutEnvelopeSource())) {
          EnvelopeTypedStaffName(:final stage) => stage,
          _ => null,
        };

    expect(stageOf('{staff.${key.keySlug}.name}'), key);
    expect(stageOf(' {staff.${inbetween.keySlug}.name} '), inbetween);
    expect(stageOf('{staff.nobody.name}'), isNull);
    expect(stageOf('{title}'), isNull);
    expect(stageOf('{cel[0].name}'), isNull);
  });
}
