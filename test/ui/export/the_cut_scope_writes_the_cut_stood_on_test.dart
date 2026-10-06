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

import '../../helpers/export_cels_board_probe.dart';
import '../../helpers/files_written_under.dart';
import '../../helpers/project_scratch_folder.dart';
import '../../helpers/export_scope_pick.dart';

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
/// The three asked one function then (`exportCutsInScope`): the cut scope
/// is the cut stood on, the project scope the ticked cuts.
///
/// They are ONE tab now (F-289, 유저 2026-10-05: 「타임시트 탭을 그냥 셀
/// 탭의 내부로 편입. 컷봉투탭도 셀 내부로 편입 … 기존의 범위는 셀의 범위
/// 규칙 따라가고」): a cut's timesheet and its cut envelope are kinds the
/// Cels tab writes, under the cels' one scope — and the answer above is
/// the same.
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

  /// The Cels tab writing its cels, the timesheet and the cut envelope.
  const threeKinds = {
    ExportCelKind.cel,
    ExportCelKind.timesheet,
    ExportCelKind.envelope,
  };

  Future<ExportDialogState> pumpExport(
    WidgetTester tester,
    EditorSessionManager session, {
    required ExportScopeKind scope,
    Directory? into,
  }) async {
    AppExport.settings.value = AppExportSettings(
      lastSpecs: ExportTabSpecs(
        cels: CelsExportSpec(scope: scope, kinds: threeKinds),
      ),
    );
    await tester.binding.setSurfaceSize(const Size(1280, 660));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session,
            exportDirectoryPicker: into == null ? null : () async => into.path,
            formatAvailability: ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('export-tab-cels')));
    await tester.pump();
    if (into != null) {
      await tester.tap(
        find.byKey(const ValueKey<String>('export-browse-button')),
      );
      await tester.pump();
      await tester.pump();
    }
    return tester.state<ExportDialogState>(find.byType(ExportDialog));
  }

  /// What the list of the cut it shows says it writes: its bright blocks'
  /// files, top to bottom.
  List<String> listed(WidgetTester tester) => [
    for (final row in tester.celsBoard.rows)
      for (final sheet in row.sheets)
        if (sheet.written) sheet.fileName,
  ];

  String count(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey<String>('export-cels-count')))
      .data!;

  // The 겸용 pair places both of A's cels between its two cuts; C3 places
  // the first alone, and a cel a cut never places is no cel of its export
  // (F-289 ⑥, 유저 2026-10-06: 「애초에 타임라인에 안놓은 셀은 출력에
  // 포함하지않음」). The timesheet is the cut's own; the envelope is the
  // pair's, which is its first cut's.
  for (final (standingOn, files) in [
    ('c1', ['A1.png', 'A2.png', '_TSC1.png', '_CUTC1_envelope.png']),
    ('c2', ['A1.png', 'A2.png', '_TSC2.png', '_CUTC1_envelope.png']),
    ('c3', ['A1.png', '_TSC3.png', '_CUTC3_envelope.png']),
  ]) {
    testWidgets('🎯the cut scope, standing on ${standingOn.toUpperCase()} '
        'with its tick OFF: the cels, the sheet and the envelope are that '
        'cut\'s all the same', (tester) async {
      final session = film(unticked: {'c1', 'c2', 'c3'});
      addTearDown(session.dispose);
      session.selectCut(CutId(standingOn));

      await pumpExport(tester, session, scope: ExportScopeKind.cut);

      expect(
        listed(tester),
        files,
        reason: '「시트 0페이지」 · 「컷 없음」 — the tick no one could see '
            'under this scope emptied the sheet and the envelope',
      );
      expect(count(tester), '${files.length} files');
      session.playbackRig.prerenderScheduler.cancel();
    });
  }

  testWidgets('…and the RUN writes them: standing on C2 with its tick off, '
      'its sheet and the pair\'s envelope land on disk', (
    tester,
  ) async {
    final temp = Directory.systemTemp.createTempSync('qa-cut-scope');
    deleteAfterSessionEnds(temp);
    final session = film(unticked: {'c1', 'c2', 'c3'});
    addTearDown(session.dispose);
    session.selectCut(const CutId('c2'));

    final state = await pumpExport(
      tester,
      session,
      scope: ExportScopeKind.cut,
      into: temp,
    );
    await tester.runAsync(state.export);
    await tester.pump();

    // (The fixture's cels are drawn on nothing, and a cel with no picture
    // is no file.)
    expect(filesWrittenUnder(temp), ['_CUTC1_envelope.png', '_TSC2.png']);
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('the project scope writes the TICKED cuts — their cels, a '
      'sheet a cut and an envelope a 겸용 group', (tester) async {
    final temp = Directory.systemTemp.createTempSync('qa-project-scope');
    deleteAfterSessionEnds(temp);
    final all = film();
    addTearDown(all.dispose);
    final state = await pumpExport(
      tester,
      all,
      scope: ExportScopeKind.project,
      into: temp,
    );
    expect(count(tester), '8 files');
    await tester.runAsync(state.export);
    await tester.pump();
    expect(filesWrittenUnder(temp), [
      '_CUTC1_envelope.png',
      '_CUTC3_envelope.png',
      '_TSC1.png',
      '_TSC2.png',
      '_TSC3.png',
    ]);
    all.playbackRig.prerenderScheduler.cancel();

    final pairOut = film(unticked: {'c1', 'c2'});
    addTearDown(pairOut.dispose);
    await pumpExport(tester, pairOut, scope: ExportScopeKind.project);
    expect(listed(tester), ['A1.png', '_TSC3.png', '_CUTC3_envelope.png']);
    expect(count(tester), '3 files');
    pairOut.playbackRig.prerenderScheduler.cancel();
  });

  group('the documents follow the cels\' scope — one switch, one grid (유저 '
      '2026-10-05: 「기존의 범위는 셀의 범위 규칙 따라가고」)', () {
    final grid = find.byKey(const ValueKey<String>('export-cut-grid'));

    testWidgets('a tick in the grid takes the pair\'s cels, its sheets and '
        'its envelope out together', (tester) async {
      final session = film();
      addTearDown(session.dispose);
      await pumpExport(tester, session, scope: ExportScopeKind.project);
      expect(count(tester), '8 files');
      await tester.openExportScope();
      expect(grid, findsOneWidget);

      final pair = find.byKey(const ValueKey<String>('export-cut-cell-1'));
      await tester.ensureVisible(pair);
      await tester.tap(pair);
      await tester.pump();

      expect(
        session.repository.requireProject().exportOverrides.excludedCutIds,
        {const CutId('c1'), const CutId('c2')},
      );
      expect(count(tester), '3 files');
      expect(listed(tester), ['A1.png', '_TSC3.png', '_CUTC3_envelope.png']);
      session.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('under the cut scope there is no grid', (tester) async {
      final session = film();
      addTearDown(session.dispose);
      await pumpExport(tester, session, scope: ExportScopeKind.cut);
      await tester.openExportScope();
      expect(
        find.byKey(const ValueKey<String>('export-scope-project')),
        findsOneWidget,
        reason: 'LIVENESS — the module is open',
      );
      expect(grid, findsNothing);
      session.playbackRig.prerenderScheduler.cancel();
    });
  });
}
