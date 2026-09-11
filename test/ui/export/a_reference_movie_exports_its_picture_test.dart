// A REFERENCE MOVIE EXPORTS ITS PICTURE (미디어 배치 라운드 6): export walks
// frames nobody is looking at, so it decodes each frame's movie pictures
// before it composes that frame — through the canvas bake and through the
// camera stack a video is baked with — and holds none of them itself.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';
import 'package:anicel/src/ui/import/import_file_settings.dart';

import '../../helpers/fake_video_backend.dart';
import '../../helpers/placed_sound_conform.dart';

/// Every frame of the take is red — where the paper is white.
Uint8List _red(int index) {
  final pixels = Uint8List(64 * 36 * 4);
  for (var i = 0; i < pixels.length; i += 4) {
    pixels[i] = 0xFF;
    pixels[i + 3] = 0xFF;
  }
  return pixels;
}

void main() {
  late Directory tempDir;
  late String moviePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-movie-exports');
    moviePath = '${tempDir.path}${Platform.pathSeparator}take3.mov';
    await File(moviePath).writeAsBytes(const [0, 0, 0, 24]);
  });

  tearDown(() async {
    debugVideoDecodeBackend = null;
    try {
      await tempDir.delete(recursive: true);
    } on Object {
      // Windows keeps handles briefly; leftovers live in systemTemp.
    }
  });

  /// A session with a red take placed as a reference. The warmer is held
  /// and the canvas stands on frame 0 — so whatever frame 5 shows, only the
  /// export can have decoded it.
  Future<EditorSessionManager> placed(WidgetTester tester) async {
    debugVideoDecodeBackend = FakeVideoBackend(frameCount: 24, paint: _red);
    final s = EditorSessionManager(
      initialProject: createDefaultProject(),
      audioConformStore: soundConformStore(),
    );
    addTearDown(s.dispose);
    s.playbackRig.prerenderScheduler.beginInputHold();
    await tester.runAsync(
      () => s.importDoors.importVideoFile(
        path: moviePath,
        settings: const ImportFileSettings(
          mode: ImportFileMode.reference,
          sound: false,
        ),
      ),
    );
    return s;
  }

  /// Whether [image]'s centre is the take's red rather than the paper.
  Future<bool> centreIsRed(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();
    final at = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
    return bytes[at] > 200 && bytes[at + 1] < 60 && bytes[at + 2] < 60;
  }

  testWidgets('the canvas bake decodes the frame it composes', (
    tester,
  ) async {
    final s = await placed(tester);

    await tester.runAsync(() async {
      final image = await ExportFrameRenderer(session: s).renderComposite(
        ExportFrameTask(cut: s.requireActiveCut, frameIndex: 5),
        ExportSizeMode.canvas,
      );
      expect(await centreIsRed(image), isTrue, reason: 'the take, not paper');
      image.dispose();
    });
    await tester.pumpAndSettle();
  });

  testWidgets('so does the camera stack a video is baked through', (
    tester,
  ) async {
    final s = await placed(tester);

    await tester.runAsync(() async {
      final image = await ExportFrameRenderer(session: s)
          .renderCompositeForVideo(
            ExportFrameTask(cut: s.requireActiveCut, frameIndex: 5),
            ExportSizeMode.camera,
          );
      expect(await centreIsRed(image), isTrue, reason: 'the take, not paper');
      image.dispose();
    });
    await tester.pumpAndSettle();
  });

  testWidgets('the export holds none of the take\'s pictures itself', (
    tester,
  ) async {
    final s = await placed(tester);

    await tester.runAsync(() async {
      final renderer = ExportFrameRenderer(session: s);
      for (var frame = 0; frame < 4; frame += 1) {
        final image = await renderer.renderComposite(
          ExportFrameTask(cut: s.requireActiveCut, frameIndex: frame),
          ExportSizeMode.canvas,
        );
        image.dispose();
      }
      expect(
        renderer.debugHeldSurfaceCount,
        0,
        reason: 'the store\'s budget decides how long a picture lives',
      );
    });
    await tester.pumpAndSettle();
  });
}
