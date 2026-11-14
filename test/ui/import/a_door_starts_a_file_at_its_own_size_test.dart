// A DOOR STARTS A FILE AT ITS OWN SIZE (F-581). 🗣️유저 2026-11-10: 「파일
// 임포트시, 기본값 지금 비율유지 늘림 이건거같은데 기본값은 원본크기로」.
//
// The fit a file starts on is ONE name's ([MediaFitMode.born]) wherever it
// is not said. The window's rows read it (`import_file_settings_test.dart`)
// and a cut folder's rows do (`media_import_planner_test.dart`); so do the
// three doors that take a fit — asked here with none said, on a canvas
// twice the file's size, where 「비율 유지 늘림」 would stand it doubled.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/fake_pdf_document.dart';
import '../../helpers/psd_fixture.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-f581-door');
  });

  tearDown(() {
    PdfRenderService.debugResetForTests();
    deleteTempQuietly(tempDir);
  });

  /// A session whose warmer is held, as the placements below leave it.
  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.playbackRig.prerenderScheduler.beginInputHold();
    return s;
  }

  /// The row the placement left showing its file.
  Layer shown(EditorSessionManager s) => s.requireActiveCut.layers.firstWhere(
    (layer) => layer.mediaReference != null,
  );

  /// 1:1 in the middle of a 200×100 canvas: a 100×50 picture's own size,
  /// where 「비율 유지 늘림」 stands it at twice that.
  final itsOwnSize = TransformPose(center: CanvasPoint(x: 100, y: 50));

  testWidgets('a picture let in with no fit said stands at its own size', (
    tester,
  ) async {
    final s = session();
    await tester.runAsync(() async {
      s.cutVerbs.resizeActiveCutCanvas(
        const CanvasSize(width: 200, height: 100),
      );
      expect(
        await s.importDoors.importImageFile(
          path: await writeSolidPng(
            tempDir,
            'still.png',
            width: 100,
            height: 50,
          ),
          destination: ImportDestination.activeCutLayer,
          copyIntoProject: false,
        ),
        isTrue,
      );
    });

    expect(shown(s).mediaReference!.pose, itsOwnSize);
    s.playbackRig.prerenderScheduler.cancel();
    await tester.pump();
  });

  testWidgets('a PDF let in with no fit said stands at its page\'s own size', (
    tester,
  ) async {
    PdfRenderService.debugOpenerOverride = (_) async =>
        FakePdfDocument(pageSizes: const [ui.Size(100, 50)]);
    final s = session();
    await tester.runAsync(() async {
      s.cutVerbs.resizeActiveCutCanvas(
        const CanvasSize(width: 200, height: 100),
      );
      final path = '${tempDir.path}${Platform.pathSeparator}conte.pdf';
      await File(path).writeAsBytes(const [0x25, 0x50, 0x44, 0x46]);
      expect(
        await s.importDoors.importPdfFile(
          path: path,
          destination: ImportDestination.activeCutLayer,
          copyIntoProject: false,
        ),
        isTrue,
      );
    });

    expect(shown(s).mediaReference!.pose, itsOwnSize);
    s.playbackRig.prerenderScheduler.cancel();
    await tester.pump();
  });

  testWidgets('a PSD expanded with no fit said lays its layers at the '
      'document\'s own size', (tester) async {
    final s = session();
    final before = s.requireActiveCut.layers.map((layer) => layer.id).toSet();
    final warnings = await tester.runAsync(() async {
      s.cutVerbs.resizeActiveCutCanvas(const CanvasSize(width: 16, height: 16));
      final file = File('${tempDir.path}${Platform.pathSeparator}stack.psd');
      await file.writeAsBytes(
        buildPsd(
          width: 8,
          height: 8,
          layers: [
            PsdTestLayer(
              name: 'under',
              left: 0,
              top: 0,
              right: 8,
              bottom: 8,
              planes: psdSolidPlanes(8, 8, [10, 20, 30]),
            ),
            PsdTestLayer(
              name: 'over',
              left: 2,
              top: 2,
              right: 6,
              bottom: 6,
              planes: psdSolidPlanes(4, 4, [200, 100, 50]),
            ),
          ],
          compositePlanes: [Uint8List(64), Uint8List(64), Uint8List(64)],
        ),
      );
      return s.importDoors.importPsdExpanded(
        path: file.path,
        destination: ImportDestination.activeCutLayer,
      );
    });

    expect(warnings, isNotNull);
    final cut = s.requireActiveCut;
    final under = cut.layers.firstWhere(
      (layer) => !before.contains(layer.id) && layer.name == 'under',
    );
    final ink = bitmapSurfaceContentBounds(
      s.renderCaches.brushFrameStore.bakedSurfaceOrNull(
        s.brushFrameKeyForCut(cut, under.id, under.frames.single.id),
      )!,
    )!;
    expect(
      (ink.left, ink.top, ink.rightExclusive, ink.bottomExclusive),
      (4, 4, 12, 12),
      reason: 'the 8×8 document in the middle of the 16×16 canvas, 1:1',
    );
    s.playbackRig.prerenderScheduler.cancel();
    await tester.pump();
  });
}
