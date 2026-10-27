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

/// 🗣️I-127-Q2 (유저 2026-10-27): 「같은 값을 찍는 칸은 전부 — 타임시트
/// 머리와 같은 길」 — the envelope's episode and title boxes are the work's,
/// the values the timesheet's header prints and its settings show, and
/// each CUT line's box is that line's cut's name. What is typed lands
/// where the timesheet's header writes it ([PaperWrites]).
void main() {
  const cutId = CutId('39');

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

  /// The envelope panel on the active cut's envelope, its brush off.
  Future<EditorSessionManager> pumpEnvelope(WidgetTester tester) async {
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
              brushAllowed: false,
              onBrushAllowedChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  /// What the envelope shown prints.
  CutEnvelopeSource printed(WidgetTester tester) =>
      tester.widget<CutEnvelopePaper>(find.byType(CutEnvelopePaper)).source;

  final field = find.byKey(const ValueKey<String>('cut-envelope-edit-field'));
  Finder box(String id) => find.byKey(ValueKey<String>('cut-envelope-$id-edit'));

  /// Types [words] into [target] and lands them.
  Future<void> typeInto(
    WidgetTester tester,
    Finder target,
    String words,
  ) async {
    await tester.tap(target);
    await tester.pumpAndSettle();
    await tester.enterText(field, words);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  testWidgets('🎯the episode and the title typed into the envelope are the '
      'work\'s — and one undo takes each back', (tester) async {
    final session = await pumpEnvelope(tester);

    await typeInto(tester, box('episode'), '#07');
    await typeInto(tester, box('title'), 'アニセル');

    expect(session.timesheetInfo.episode, '#07');
    expect(session.timesheetInfo.title, 'アニセル');
    expect(printed(tester).episode, '#07', reason: 'the envelope prints it');
    expect(printed(tester).title, 'アニセル');

    session.undo();
    await tester.pumpAndSettle();
    expect(session.timesheetInfo.title, isEmpty);
    expect(session.timesheetInfo.episode, '#07');
  });

  testWidgets('🎯a 겸용 envelope\'s CUT lines each name their own cut', (
    tester,
  ) async {
    final session = await pumpEnvelope(tester);
    session.cutVerbs.createLinkedCutFromActiveCut();
    await tester.pumpAndSettle();
    final cuts = [for (final cut in session.activeTrack.cuts) cut.id];
    expect(cuts, hasLength(2), reason: '⛔premise: two cuts share a folder');
    expect(printed(tester).cuts, hasLength(2), reason: '⛔premise');

    await typeInto(tester, box('cut-1-number'), '40');

    expect(session.cutById(cuts[1])!.name, '40');
    expect(session.cutById(cuts[0])!.name, '39', reason: 'the other line\'s');

    // Both lines, whichever cut the envelope is shown for: a line that
    // named the envelope's own cut would pass one of the two.
    await typeInto(tester, box('cut-0-number'), '38');

    expect(session.cutById(cuts[0])!.name, '38');
    expect(session.cutById(cuts[1])!.name, '40', reason: 'the other line\'s');
    expect(printed(tester).cuts.map((line) => line.name), ['38', '40']);
    expect(
      box('cut-2-number'),
      findsNothing,
      reason: 'a line past the last cut names none',
    );
  });

  testWidgets('an empty cut name is refused — the box keeps the name it '
      'prints', (tester) async {
    final session = await pumpEnvelope(tester);

    await typeInto(tester, box('cut-0-number'), '');

    expect(session.cutById(cutId)!.name, '39');
  });

  testWidgets('a box that prints what is counted prints only', (
    tester,
  ) async {
    await pumpEnvelope(tester);

    expect(box('cut-0-number'), findsOneWidget, reason: '⛔premise');
    expect(box('cut-0-seconds'), findsNothing);
    expect(box('cut-0-frames'), findsNothing);
  });

  test('a box prints what someone typed by its binding', () {
    const stage = LayerMark(process: LayerProcess.key);
    const source = CutEnvelopeSource(
      cuts: [
        CutEnvelopeCutLine(
          cut: CutId('20'),
          name: '20',
          durationFrames: 120,
          fps: 24,
        ),
      ],
    );
    EnvelopeTypedValue? of(String binding) =>
        envelopeTypedValueOf(binding, source);

    expect(of('{episode}'), isA<EnvelopeTypedEpisode>());
    expect(of(' {title} '), isA<EnvelopeTypedTitle>());
    expect(
      of('{cut[0].name}'),
      isA<EnvelopeTypedCutName>().having(
        (value) => value.cut,
        'cut',
        const CutId('20'),
      ),
    );
    expect(
      of('{staff.${stage.keySlug}.name}'),
      isA<EnvelopeTypedStaffName>().having(
        (value) => value.stage,
        'stage',
        stage,
      ),
    );
    for (final counted in [
      '{cut[1].name}',
      '{cut[0].seconds}',
      '{cut[0].length}',
      '{cel[0].name}',
      '{cel[0].genga}',
      '{total.genga}',
      '{canvas.width}',
      '{logo}',
      '{staff.nobody.name}',
      'title',
    ]) {
      expect(of(counted), isNull, reason: counted);
    }
  });
}
