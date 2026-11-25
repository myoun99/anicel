import '../../helpers/screens_left_of_the_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/export_cels_alone.dart';
import '../../helpers/export_preview_probe.dart';
import '../../helpers/the_tree_goes_first.dart';

/// 🐞F-594 ② (유저 2026-11-15: 「용지 색라벨 바꾸거나 하면 셀 탭 내보내기에서
/// 적용안되있어서 … 코드대로 작동해야하는 상황에서 그러지 않았음」) — a 용지-작감
/// rides the 용지-LO it corrects as a SYNCED attach row (F-578: 「용지lo레이어에
/// … 어태치레이어만들어서 작감용지 얹는다」), whose stored timeline is empty:
/// it shows its base's blocks through its cell links. The Cels tab laid such
/// a paper as nothing, reading the row's own timeline.
void main() {
  itsTestsLeaveScreensOfTheEngine({ScreensLeft.ofALay});
  opensTheEnginesScreens();
  tearDown(() => AppExport.settings.value = AppExportSettings());

  const lo = LayerMark(process: LayerProcess.layout);
  const loCorrected = LayerMark(
    process: LayerProcess.layout,
    revise: LayerRevise.animationDirector,
  );

  Frame frame(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const [], name: '1');

  EditorSessionManager session() => inkEveryCel(
    EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'Project',
        cameraSize: const CanvasSize(width: 32, height: 18),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [
              Cut(
                id: const CutId('cut'),
                name: 'CUT1',
                duration: 2,
                canvasSize: const CanvasSize(width: 8, height: 8),
                layers: [
                  Layer(
                    id: const LayerId('paper-lo'),
                    name: 'Paper',
                    frames: [frame('pl1')],
                    mark: const LayerMark.paper(LayerProcess.layout),
                  ),
                  Layer(
                    id: const LayerId('paper-ad'),
                    name: 'Paper',
                    frames: [frame('pa1')],
                    mark: const LayerMark.paper(
                      LayerRevise.animationDirector,
                    ),
                    attachedToLayerId: const LayerId('paper-lo'),
                    attachedMode: AttachedMode.synced,
                    baseFrameLinks: {
                      const FrameId('pl1'): const FrameId('pa1'),
                    },
                    // As the app keeps a synced attach row: no blocks of its
                    // own — it shows its base's.
                    timeline: const {},
                  ),
                  Layer(
                    id: const LayerId('a'),
                    name: 'A',
                    frames: [frame('f1')],
                    mark: loCorrected,
                  ),
                  createCameraLayer(cutId: const CutId('cut')),
                ],
              ),
            ],
          ),
        ],
        createdAt: DateTime.utc(2026),
      ),
    ),
  );

  Future<String> lookUnder(WidgetTester tester, LayerMark label) async {
    AppExport.settings.value = AppExportSettings(
      lastSpecs: ExportTabSpecs(
        cels: CelsExportSpec(kinds: celKindsAlone, label: label),
      ),
    );
    await tester.binding.setSurfaceSize(const Size(1400, 660));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    theTreeGoesFirst(tester);
    final s = session();
    // The row the label leaves its picture: A wears LO 작감 — under the LO
    // filter it is in by hand, as the list's switch puts it.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: s,
            formatAvailability: ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('export-tab-cels')));
    await tester.pump();
    if (label != loCorrected) {
      await tester.tap(
        find.byKey(const ValueKey<String>('export-cels-switch-a')),
      );
      await tester.pump();
    }
    return '${tester.exportPreviewDocument?.look}';
  }

  testWidgets('🚨the LO 작감 filter lays the 용지-작감 riding 용지-LO — its '
      'cel through its link, and the 용지-LO under it not (F-594-Q1 (나): '
      '「용지-작감 한 장만」)', (tester) async {
    final look = await lookUnder(tester, loCorrected);
    expect(look, contains('a=f1'), reason: 'fixture: A1 under preview');
    expect(look, contains('paper-ad=pa1'));
    expect(look, isNot(contains('paper-lo=')));
  });

  testWidgets('the LO filter lays the 용지-LO, and not what rides it', (
    tester,
  ) async {
    final look = await lookUnder(tester, lo);
    expect(look, contains('a=f1'), reason: 'fixture: A1 under preview');
    expect(look, contains('paper-lo=pl1'));
    expect(look, isNot(contains('paper-ad=')));
  });
}
