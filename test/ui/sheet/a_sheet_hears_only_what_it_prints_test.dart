// A SHEET HEARS THE SESSION ONLY WHEN WHAT IT PRINTS CHANGED
// (session-news-rebuilds-unsliced, 2026-10-20): every sheet rebuilt on
// every session notify — the timesheet its shell, 50 elements round a
// document its memo handed back unchanged, and the conte and the envelope
// their whole hosts, 107 and 108 — for a guide picked on the canvas or the
// onion switched on.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_frame_grid_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_tab_host.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timesheet/timesheet_strata.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';

void main() {
  Future<EditorSessionManager> pumpSheet(
    WidgetTester tester, {
    Project? project,
  }) async {
    final session = EditorSessionManager(
      initialProject: project ?? createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TimesheetTabHost(session: session)),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  TimesheetStrata strata(WidgetTester tester) =>
      tester.widget<TimesheetStrata>(find.byType(TimesheetStrata));

  /// How many times [session] notified while [act] ran.
  int notifiesOf(EditorSessionManager session, void Function() act) {
    var heard = 0;
    void count() => heard += 1;
    session.addListener(count);
    try {
      act();
    } finally {
      session.removeListener(count);
    }
    return heard;
  }

  testWidgets('news the sheet does not print rebuilds none of it', (
    tester,
  ) async {
    final session = await pumpSheet(tester);
    final before = strata(tester);

    final heard = notifiesOf(
      session,
      () => session.cutVerbs.selectedGuideId = const GuideId('picked'),
    );
    await tester.pump();

    expect(heard, greaterThan(0), reason: '⛔premise: the session notified');
    expect(
      identical(strata(tester), before),
      isTrue,
      reason: 'a guide picked on the canvas is nothing the sheet prints',
    );

    // Drain the prerender scheduler's debounced warming.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets('news it prints reprints it', (tester) async {
    final session = await pumpSheet(tester);
    final before = strata(tester);

    session.updateTimesheetInfo(
      session.timesheetInfo.copyWith(title: 'A title of its own'),
    );
    await tester.pump();

    expect(
      identical(strata(tester).layout, before.layout),
      isFalse,
      reason: 'the sheet\'s title is printed on it',
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  // 🗣️F-489 — the unnamed head's mark is an app pick, not the session's:
  // a pick in Preferences is printed on the sheet all the same.
  testWidgets('a mark picked for the unnamed head reprints it', (
    tester,
  ) async {
    addTearDown(
      () => AppFrameGridSettings.settings.value = const AppFrameGridSettings(),
    );
    final base = createDefaultProject();
    final track = base.tracks.first;
    final cut = track.cuts.first;
    final unnamed = Frame(
      id: const FrameId('u'),
      duration: 1,
      strokes: const [],
    );
    await pumpSheet(
      tester,
      project: base.copyWith(
        tracks: [
          track.copyWith(
            cuts: [
              cut.copyWith(
                layers: [
                  Layer(
                    id: const LayerId('a'),
                    name: 'A',
                    frames: [unnamed],
                    timeline: const {
                      0: TimelineExposure.drawing(FrameId('u'), length: 3),
                    },
                  ),
                  ...cut.layers,
                ],
              ),
            ],
          ),
        ],
      ),
    );
    final before = strata(tester);
    Set<InbetweenMark> marks(TimesheetStrata strata) => {
      for (final column in strata.layout.document.columns)
        for (final cell in column.cells) ?cell.mark,
    };
    expect(marks(before), {InbetweenMark.two}, reason: '⛔premise');

    AppFrameGridSettings.settings.value = const AppFrameGridSettings(
      unnamedMark: InbetweenMark.one,
    );
    await tester.pump();

    expect(identical(strata(tester).layout, before.layout), isFalse);
    expect(marks(strata(tester)), {InbetweenMark.one});

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  // The conte and the envelope hear the session where the workspace hosts
  // them, so they are asked there — both in one app.
  testWidgets('in the app, the conte and the envelope rebuild for what they '
      'print and for nothing else', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();

    for (final (tab, host) in [
      ('timeline-mode-conte-button', find.byType(ConteTabHost)),
      ('timeline-mode-envelope-button', find.byType(CutEnvelopeTabHost)),
    ]) {
      await tester.tap(find.byKey(ValueKey<String>(tab)));
      await tester.pumpAndSettle();
      final before = tester.widget(host);
      final session = switch (before) {
        ConteTabHost(:final session) => session,
        CutEnvelopeTabHost(:final session) => session,
        _ => fail('⛔premise: $tab shows its sheet'),
      };

      final heard = notifiesOf(
        session,
        () => session.cutVerbs.selectedGuideId = GuideId('picked by $tab'),
      );
      await tester.pump();
      expect(heard, greaterThan(0), reason: '⛔premise: the session notified');
      expect(
        identical(tester.widget(host), before),
        isTrue,
        reason: '$tab: a guide picked on the canvas is nothing it prints',
      );

      session.updateTimesheetInfo(
        session.timesheetInfo.copyWith(title: 'Titled by $tab'),
      );
      await tester.pump();
      expect(
        identical(tester.widget(host), before),
        isFalse,
        reason: '$tab: the work it prints is a new one',
      );
      await tester.pumpAndSettle();
    }

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets('the conte prints the active cut\'s canvas as well — the next '
      'cut a stroke makes is planned from it', (tester) async {
    Cut cut(String id, CanvasSize canvas) => Cut(
      id: CutId(id),
      name: id,
      duration: 6,
      canvasSize: canvas,
      layers: const [],
    );
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('two-canvases'),
        name: 'Two canvases',
        createdAt: DateTime.utc(2026, 10, 20),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'Video',
            cuts: [
              cut('wide', const CanvasSize(width: 640, height: 360)),
              cut('tall', const CanvasSize(width: 360, height: 640)),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);

    session.selectCut(const CutId('wide'));
    final wide = ConteTabHost.printedBy(session);
    session.selectCut(const CutId('tall'));

    expect(
      ConteTabHost.printedBy(session),
      isNot(wide),
      reason: 'the work is the same, the canvas a new cut takes is not',
    );
  });
}
