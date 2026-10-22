import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_cels_board.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/widgets/app_window.dart';

/// F-337 (유저 2026-10-10): 「익스포트/임포트 창이 너무 큼. 앱 화면의
/// 절반정도로」 — by area (F-337-Q1, 유저 2026-10-13: 「면적얘기야」), and
/// then two thirds of it (F-337-Q2, the same day: 「앱 화면의 절반은 좀
/// 작은거같고 2/3정도 면적으로」). Both windows read the one law,
/// [AppWindow.screenShare]. ↩️Both took all the room the screen leaves
/// (유저 2026-09-16 · F-282-Q7), and the import window stood at 760 × 520
/// before that, whatever the screen.
void main() {
  Future<void> screenOf(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// The window as it is laid out. ⚠️The key is on the Material `Dialog`,
  /// which lays out over the whole screen; the window is the box inside it.
  Size windowSize(WidgetTester tester, String key) => tester.getSize(
    find
        .descendant(
          of: find.byKey(ValueKey<String>(key)),
          matching: find.byType(ConstrainedBox),
        )
        .first,
  );

  testWidgets('the import window takes two thirds of the screen', (
    tester,
  ) async {
    await screenOf(tester, const Size(1600, 1000));
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ImportDialog(session: session))),
    );
    await tester.pump();

    final size = windowSize(tester, 'import-dialog');
    expect(size.width, closeTo(1306.4, 0.1));
    expect(size.height, closeTo(816.5, 0.1));
  });

  group('the export window', () {
    setUp(() => AppExport.settings.value = AppExportSettings());
    tearDown(() => AppExport.settings.value = AppExportSettings());

    const cutId = CutId('cut');

    EditorSessionManager film() => EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'Film',
        cameraSize: const CanvasSize(width: 32, height: 18),
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [
              Cut(
                id: cutId,
                name: '301',
                duration: 2,
                canvasSize: const CanvasSize(width: 8, height: 8),
                layers: [
                  Layer(
                    id: const LayerId('a'),
                    name: 'A',
                    frames: [
                      Frame(
                        id: const FrameId('a1'),
                        duration: 1,
                        strokes: const [],
                      ),
                    ],
                  ),
                  createCameraLayer(cutId: cutId),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    Future<void> pumpOn(WidgetTester tester, Size screen) async {
      await screenOf(tester, screen);
      final session = film();
      addTearDown(session.dispose);
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
    }

    Finder keyed(String value) => find.byKey(ValueKey<String>(value));

    testWidgets('takes two thirds of the screen, its drawers open where they '
        'fit', (tester) async {
      await pumpOn(tester, const Size(1920, 1200));

      final size = windowSize(tester, 'export-dialog');
      expect(size.width, closeTo(1567.7, 0.1));
      expect(size.height, closeTo(979.8, 0.1));
      expect(keyed('export-presets-collapse'), findsOneWidget);
      expect(keyed('export-queue-collapse'), findsOneWidget);
    });

    testWidgets('is never narrower than its four columns with both drawers '
        'folded — its share yields before the preview does', (tester) async {
      await pumpOn(tester, const Size(1200, 720));

      final size = windowSize(tester, 'export-dialog');
      expect(
        size.width,
        // ↩️1018 while the cel list stood 184 wide (F-395 widened it).
        1018 - 184 + ExportCelsBoard.stackWidth,
        reason: 'two thirds of 1200 by area is 980 wide; the columns with '
            'both drawers folded lay out wider',
      );
      expect(size.height, closeTo(587.9, 0.1));
      expect(keyed('export-presets-strip'), findsOneWidget);
      expect(keyed('export-queue-strip'), findsOneWidget);
    });
  });
}
