import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
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
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

/// 🚨F-300 (유저 2026-10-05): 「출력창은 현재컷을 기준으로 생각하긴한다만
/// 렌더에 현재컷 관련 로직 있는건 이상하니 근본/구조적으로 해결」.
///
/// The other half of that sentence: the PICTURE of a 겸용 group's cel is
/// composited in the cut that shows it, and the WINDOW still thinks in the
/// cut it stands on. Its list is that one cut's rows — every bundle there,
/// every sheet of each — however many siblings the pictures come from. The
/// plan's arithmetic is pinned in `export_cel_group_plan_test.dart`, the
/// pixels in `a_linked_cel_wears_the_paper_of_the_cut_that_shows_it_test`.
void main() {
  setUp(() => AppExport.settings.value = AppExportSettings());
  tearDown(() => AppExport.settings.value = AppExportSettings());

  Frame frame(String id, String name) =>
      Frame(id: FrameId(id), duration: 1, strokes: const [], name: name);

  /// One row of a 겸용 pair: the bank is the link group's, and each cut
  /// shows ONE of its two cels — [shownByC1] on C1, the other on C2.
  Layer rowOf(String cut, String row, {required String shownByC1}) {
    final other = shownByC1 == '1' ? '2' : '1';
    return Layer(
      id: LayerId('$cut-$row'),
      name: row.toUpperCase(),
      frames: [frame('${row}1', '1'), frame('${row}2', '2')],
      mark: const LayerMark(process: LayerProcess.key),
      isVisible: true,
      onTimesheet: true,
      timeline: {
        0: TimelineExposure.drawing(
          FrameId('$row${cut == 'c1' ? shownByC1 : other}'),
          length: 2,
        ),
      },
    );
  }

  /// C1 and C2 sharing rows A and B. C1 shows A 1 and B 2; C2 shows A 2
  /// and B 1 — so standing on either cut, each bundle's FIRST cel comes
  /// from a different cut than the other bundle's.
  EditorSessionManager linkedPair() => EditorSessionManager(
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
            for (final cut in ['c1', 'c2'])
              Cut(
                id: CutId(cut),
                name: cut.toUpperCase(),
                duration: 2,
                canvasSize: const CanvasSize(width: 8, height: 8),
                layers: [
                  rowOf(cut, 'a', shownByC1: '1'),
                  rowOf(cut, 'b', shownByC1: '2'),
                  createCameraLayer(cutId: CutId(cut)),
                ],
              ),
          ],
        ),
      ],
      linkRegistry: LayerLinkRegistry(
        groups: [
          for (final row in ['a', 'b'])
            LayerLinkGroup(
              id: 'group-$row',
              members: [
                for (final cut in ['c1', 'c2'])
                  LayerLinkMember(
                    trackId: const TrackId('track'),
                    cutId: CutId(cut),
                    layerId: LayerId('$cut-$row'),
                  ),
              ],
            ),
        ],
      ),
    ),
  );

  Future<void> pumpCels(
    WidgetTester tester,
    EditorSessionManager session, {
    required ExportScopeKind scope,
  }) async {
    AppExport.settings.value = AppExportSettings(
      lastSpecs: ExportTabSpecs(cels: CelsExportSpec(scope: scope)),
    );
    await tester.binding.setSurfaceSize(const Size(1120, 660));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session,
            formatAvailability: ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('export-tab-cels')));
    await tester.pump();
  }

  /// The bundle rows in the order they are DRAWN, read off the widget tree.
  List<String> listedIds(WidgetTester tester) => [
    for (final key in tester
        .widgetList<InkWell>(find.byType(InkWell))
        .map((ink) => ink.key)
        .whereType<ValueKey<String>>()
        .map((key) => key.value)
        .where((value) => value.startsWith('export-cels-bundle-')))
      key.substring('export-cels-bundle-'.length),
  ];

  PanelFlyoutButton picker(WidgetTester tester) =>
      tester.widget<PanelFlyoutButton>(
        find.byKey(const ValueKey<String>('export-cels-cut-picker')),
      );

  String transportLine(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey<String>('export-transport-line')))
      .data!;

  Future<void> tapRow(WidgetTester tester, String layerId) async {
    await tester.tap(
      find.byKey(ValueKey<String>('export-cels-bundle-$layerId')),
    );
    await tester.pump();
  }

  for (final standingOn in ['c1', 'c2']) {
    testWidgets('🎯standing on ${standingOn.toUpperCase()}: the list is that '
        'cut\'s rows — both bundles, each with BOTH its cels', (tester) async {
      final session = linkedPair();
      addTearDown(session.dispose);
      session.selectCut(CutId(standingOn));

      await pumpCels(tester, session, scope: ExportScopeKind.cut);

      expect(
        listedIds(tester),
        ['$standingOn-b', '$standingOn-a'],
        reason: 'a row whose first cel a sibling shows was dropped, and the '
            'rows of the cut the first cel is composited in were looked up '
            'instead',
      );
      expect(picker(tester).label, 'C1-C2');
      expect(picker(tester).enabled, isFalse);

      await tapRow(tester, '$standingOn-a');
      expect(transportLine(tester), 'A1.png · 1 / 2');
      await tapRow(tester, '$standingOn-b');
      expect(transportLine(tester), 'B1.png · 1 / 2');
      session.playbackRig.prerenderScheduler.cancel();
    });
  }

  testWidgets('🚨under the project scope the pair is still ONE cut to pick '
      '— the sibling its cels are composited in is not a second one', (
    tester,
  ) async {
    final session = linkedPair();
    addTearDown(session.dispose);
    session.selectCut(const CutId('c2'));

    await pumpCels(tester, session, scope: ExportScopeKind.project);

    expect(listedIds(tester), ['c1-b', 'c1-a']);
    expect(picker(tester).label, 'C1-C2');
    expect(
      picker(tester).enabled,
      isFalse,
      reason: 'the group exports once, as one cut: nothing to pick between',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });
}
