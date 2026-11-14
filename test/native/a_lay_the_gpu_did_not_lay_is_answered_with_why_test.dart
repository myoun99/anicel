import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/ui/playback/engine_frame_picture_store.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

import '../helpers/engine_screen_pins.dart';
import '../helpers/the_apps_engine_let_go.dart';

/// 🚨A LAY THE GPU DID NOT LAY IS ANSWERED WITH WHY, AND NOTHING IS KEPT
/// UNDER ITS KEY (the-ui-thread-never-enters-the-driver B1-a, 2026-11-15):
/// a picture's compose is handed to the engine unwaited (`GpuScreen
/// .compose`), so where it fails — the device gone as it lays, memory
/// short — is told by its done, not where it was asked. The store answers
/// once that has come (`EngineFramePictureStore._lay`): kept as laid, it
/// would be a wrong picture no one would lay again. 🗣️관제 2026-11-15
/// 05:09: 「메모리가 없을 때는 드물지 않다」.
///
/// ⚠️Its own file: a device that is gone is gone for its process.
void main() {
  // The letters read their faces from the bundle.
  TestWidgetsFlutterBinding.ensureInitialized();
  final engine = EngineScreenPins('a lay the GPU did not lay');

  // A page alone: nothing of it waits for the GPU before its compose.
  final page = stackedFrameOf(
    const [],
    page: (
      canvasSize: const CanvasSize(width: 64, height: 64),
      pasteboardReach: PasteboardReach.whole,
      paintPaper: true,
      paperBackground: const ProjectBackground.color(0xFF30A060),
    ),
    surfaceOf: (_) => null,
  );

  test('🚨a lay whose device went as the GPU laid it is answered with why, '
      'and nothing is kept under its key', () async {
    final store = EngineFramePictureStore<String>(
      tools: () async => (
        composite: engine.composite,
        letters: engine.letters,
      ),
    );
    addTearDown(store.dispose);
    expect(await store.lay('before', page), isNotNull, reason: 'LIVENESS');

    theAppsEngineLost();

    await expectLater(store.lay('after', page), throwsStateError);
    expect(store.holds('after'), isFalse);
  });
}
