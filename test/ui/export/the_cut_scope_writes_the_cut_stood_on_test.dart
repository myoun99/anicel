import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_overrides.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';

/// 🗣️유저 2026-10-05: 「출력은 정상적으로 됬는데 같은 겸용컷에서 타임시트랑
/// 컷봉투 출력하려니 컷 없다고 뜨는데 이거뭐지? 겸용컷 문제 넓게 확인안한거
/// 맞지?」
///
/// Measured over every tab × the cut stood on (a 겸용 pair's first, its
/// second, a cut alone) × both scopes × the cut's tick: with every tick on
/// all six tabs wrote from any of the three. With the cut's tick OFF — the
/// scope grid, which only the PROJECT scope shows — the Timesheet and the
/// Envelope wrote nothing under the CUT scope, 「컷 없음」, while the Cels
/// tab wrote the cut. A 겸용 cut had nothing to do with it: the cut alone
/// did the same.
///
/// The three tabs that list cuts ask one function now
/// (`exportCutsInScope`): the cut scope is the cut stood on, the project
/// scope the ticked cuts.
void main() {
  setUp(() => AppExport.settings.value = AppExportSettings());
  tearDown(() => AppExport.settings.value = AppExportSettings());

  Frame frame(String id, String name) =>
      Frame(id: FrameId(id), duration: 1, strokes: const [], name: name);

  Cut cutOf(String id, {required String shown}) => Cut(
    id: CutId(id),
    name: id.toUpperCase(),
    duration: 2,
    canvasSize: const CanvasSize(width: 8, height: 8),
    layers: [
      Layer(
        id: LayerId('$id-a'),
        name: 'A',
        frames: [frame('a1', '1'), frame('a2', '2')],
        mark: const LayerMark(process: LayerProcess.key),
        isVisible: true,
        onTimesheet: true,
        timeline: {0: TimelineExposure.drawing(FrameId('a$shown'), length: 2)},
      ),
      createCameraLayer(cutId: CutId(id)),
    ],
  );

  /// C1 and C2 a 겸용 pair, C3 a cut alone; [unticked] are the cuts the
  /// scope grid has out.
  EditorSessionManager film({Set<String> unticked = const {}}) =>
      EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('project'),
          name: 'Project',
          cameraSize: const CanvasSize(width: 32, height: 18),
          createdAt: DateTime.utc(2026),
          tracks: [
            Track(
              id: const TrackId('track'),
              name: 'Track',
              cuts: [
                cutOf('c1', shown: '1'),
                cutOf('c2', shown: '2'),
                cutOf('c3', shown: '1'),
              ],
            ),
          ],
          linkRegistry: LayerLinkRegistry(
            groups: [
              LayerLinkGroup(
                id: 'group-a',
                members: [
                  for (final cut in ['c1', 'c2'])
                    LayerLinkMember(
                      trackId: const TrackId('track'),
                      cutId: CutId(cut),
                      layerId: LayerId('$cut-a'),
                    ),
                ],
              ),
            ],
          ),
          exportOverrides: ExportProjectOverrides(
            excludedCutIds: {for (final id in unticked) CutId(id)},
          ),
        ),
      );

  Future<void> pumpExport(
    WidgetTester tester,
    EditorSessionManager session, {
    required ExportScopeKind scope,
    ExportScopeKind? timesheetScope,
    ExportDirectoryPicker? picker,
  }) async {
    AppExport.settings.value = AppExportSettings(
      lastSpecs: ExportTabSpecs(
        cels: CelsExportSpec(scope: scope),
        timesheet: TimesheetExportSpec(scope: timesheetScope ?? scope),
        envelope: EnvelopeExportSpec(scope: scope),
      ),
    );
    await tester.binding.setSurfaceSize(const Size(1120, 660));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session,
            exportDirectoryPicker: picker,
            formatAvailability: ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// What [tab] says it writes: the headline's count, and the first file
  /// on the transport line (null where it writes nothing).
  Future<(String, String?)> written(WidgetTester tester, String tab) async {
    await tester.tap(find.byKey(ValueKey<String>('export-tab-$tab')));
    await tester.pump();
    final headline = tester
        .widget<Text>(find.byKey(const ValueKey<String>('export-plan-headline')))
        .data!;
    final transport = find.byKey(
      const ValueKey<String>('export-transport-line'),
    );
    return (
      // The count is the sentence up to its 「 as 」.
      headline.substring(0, headline.indexOf(' as ')),
      transport.evaluate().isEmpty
          ? null
          : tester.widget<Text>(transport).data,
    );
  }

  for (final (standingOn, owner) in [('c1', 'C1'), ('c2', 'C1'), ('c3', 'C3')]) {
    testWidgets('🎯the cut scope, standing on ${standingOn.toUpperCase()} '
        'with its tick OFF: the cels, the sheet and the envelope are that '
        'cut\'s all the same', (tester) async {
      final session = film(unticked: {'c1', 'c2', 'c3'});
      addTearDown(session.dispose);
      session.selectCut(CutId(standingOn));

      await pumpExport(tester, session, scope: ExportScopeKind.cut);

      expect(await written(tester, 'cels'), ('1 label · 2 files', 'A1.png · 1 / 2'));
      expect(
        await written(tester, 'timesheet'),
        ('1 sheet page', 'CUT${standingOn.toUpperCase()} · p1/1 · 1 page'),
        reason: '「시트 0페이지」 · 「컷 없음」 — the tick no one could see '
            'under this scope emptied the sheet',
      );
      expect(
        await written(tester, 'envelope'),
        ('1 envelope', 'CUT$owner · 1 / 1 · 1 file'),
        reason: 'the envelope of the cut stood on (a 겸용 pair\'s is its '
            'first cut\'s)',
      );
      session.playbackRig.prerenderScheduler.cancel();
    });
  }

  testWidgets('…and the RUN writes them: standing on C2 with its tick off, '
      'the sheet and the pair\'s envelope land on disk', (tester) async {
    final temp = Directory.systemTemp.createTempSync('qa-cut-scope');
    addTearDown(() => temp.deleteSync(recursive: true));
    final session = film(unticked: {'c1', 'c2', 'c3'});
    addTearDown(session.dispose);
    session.selectCut(const CutId('c2'));

    await pumpExport(
      tester,
      session,
      scope: ExportScopeKind.cut,
      picker: () async => temp.path,
    );
    final state = tester.state<ExportDialogState>(find.byType(ExportDialog));
    await tester.tap(
      find.byKey(const ValueKey<String>('export-browse-button')),
    );
    await tester.pump();
    await tester.pump();
    for (final tab in ['timesheet', 'envelope']) {
      await written(tester, tab);
      await tester.runAsync(state.export);
      await tester.pump();
    }

    expect(
      [
        for (final file in temp.listSync(recursive: true).whereType<File>())
          file.uri.pathSegments.last,
      ]..sort(),
      ['CUTC1_envelope.png', 'CUTC2.png'],
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('the project scope writes the TICKED cuts — in each of the '
      'three tabs', (tester) async {
    final all = film();
    addTearDown(all.dispose);
    await pumpExport(tester, all, scope: ExportScopeKind.project);

    expect((await written(tester, 'cels')).$1, '2 labels · 4 files');
    expect((await written(tester, 'timesheet')).$1, '3 sheet pages');
    expect((await written(tester, 'envelope')).$1, '2 envelopes');

    final pairOut = film(unticked: {'c1', 'c2'});
    addTearDown(pairOut.dispose);
    await pumpExport(tester, pairOut, scope: ExportScopeKind.project);

    expect((await written(tester, 'cels')).$1, '1 label · 2 files');
    expect(
      await written(tester, 'timesheet'),
      ('1 sheet page', 'CUTC3 · p1/1 · 1 page'),
    );
    expect(
      await written(tester, 'envelope'),
      ('1 envelope', 'CUTC3 · 1 / 1 · 1 file'),
    );
  });

  testWidgets('each tab reads its OWN scope switch', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    await pumpExport(
      tester,
      session,
      scope: ExportScopeKind.project,
      timesheetScope: ExportScopeKind.cut,
    );

    expect((await written(tester, 'cels')).$1, '2 labels · 4 files');
    expect((await written(tester, 'timesheet')).$1, '1 sheet page');
    expect((await written(tester, 'envelope')).$1, '2 envelopes');
  });

  group('the envelope tab shows the cut checks its project scope obeys '
      '(envelope-export-cut-grid-Q1)', () {
    final grid = find.byKey(const ValueKey<String>('export-cut-grid'));

    testWidgets('a tick in its grid takes the pair\'s envelope out', (
      tester,
    ) async {
      final session = film();
      addTearDown(session.dispose);
      await pumpExport(tester, session, scope: ExportScopeKind.project);

      expect((await written(tester, 'envelope')).$1, '2 envelopes');
      expect(
        grid,
        findsOneWidget,
        reason: 'the tab obeyed ticks only another tab could show',
      );

      final pair = find.byKey(const ValueKey<String>('export-cut-cell-1'));
      await tester.ensureVisible(pair);
      await tester.tap(pair);
      await tester.pump();

      expect(
        session.repository.requireProject().exportOverrides.excludedCutIds,
        {const CutId('c1'), const CutId('c2')},
      );
      expect(
        await written(tester, 'envelope'),
        ('1 envelope', 'CUTC3 · 1 / 1 · 1 file'),
      );
    });

    testWidgets('under the cut scope there is no grid, as in the other two '
        'tabs', (tester) async {
      final session = film();
      addTearDown(session.dispose);
      await pumpExport(tester, session, scope: ExportScopeKind.cut);

      for (final tab in ['cels', 'timesheet', 'envelope']) {
        await written(tester, tab);
        expect(grid, findsNothing, reason: tab);
      }
    });
  });
}
