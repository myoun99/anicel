/// The list a launch compiles ahead is compiled here on a second engine,
/// beside a busy line: the bound is this file's own
/// (`the_app_compiles_its_kernels_ahead_test.dart`).
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/app_kernels_ahead.dart';
import 'package:anicel/src/native/engine_frame_tools.dart';
import 'package:anicel/src/native/engine_refusals.dart';
import 'package:anicel/src/native/engine_strokes.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import '../../helpers/opened_session.dart';
import '../../helpers/project_scratch_folder.dart';
import '../../helpers/tiles_on_the_engine.dart';

/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「RAM 에 사본을 두고 앱을
/// 유지한다」 — 「장치를 잃으면 앱은 꺼지지 않고 새 장치를 열어 사본으로
/// 되살린다. 잃는 것은 그리던 획 정도다」 — the whole of it, through the
/// door the app hears a refusal at ([EngineRefusals]) and by the launch's
/// own path ([openTheAppsEngineAgain]): what each thing that stands on the
/// engine does as it goes is pinned where that thing is.
///
/// ⚠️ONE TEST, and the app's own engine: a device that is gone is gone for
/// its process. The cel's tiles are landed as a stroke lands them, with no
/// stroke (`a_save_after_the_device_is_gone_keeps_the_work_test.dart` says
/// why).
void main() {
  // The frame's letters read their faces from the app's bundle.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a session whose device went goes on: the first refusal heard '
      'opens another engine by the launch\'s path, the app held from '
      'before the one that is gone is let go till what a hand needs is '
      'compiled on the next — and the app says once that the device '
      'started again, and why. What the session had lands on from there, '
      'and a save keeps it: a tile as its copy, one landed since as the '
      'picture it landed on, one landed after as itself', () async {
    // As the app compiles: off this isolate.
    AppKernels.debugCompileHere = false;
    final reported = FlutterError.onError;
    final uncaught = PlatformDispatcher.instance.onError;
    var tellings = 0;
    void countATelling() => tellings += 1;
    final startedAgain = Completer<void>();
    // ⛔Completed twice, it throws: the app says so once.
    void started() => startedAgain.complete();
    bool? heldAsItWasLetGo;
    bool? heldAsTheNextOpened;
    final standing = StandsOnTheAppsEngine(
      letGo: () => heldAsItWasLetGo = appEngineGetsReady.value,
      opened: (_) => heldAsTheNextOpened = appEngineGetsReady.value,
    );
    addTearDown(() {
      AppKernels.debugCompileHere = true;
      FlutterError.onError = reported;
      PlatformDispatcher.instance.onError = uncaught;
      EngineRefusals.told.removeListener(countATelling);
      EngineRefusals.openedAnother.removeListener(started);
      EngineRefusals.debugForget();
      standing.stop();
    });
    FlutterError.onError = (_) {};
    PlatformDispatcher.instance.onError = (_, _) => true;
    EngineRefusals.install();
    EngineRefusals.told.addListener(countATelling);
    EngineRefusals.openedAnother.addListener(started);

    final folder = Directory.systemTemp.createTempSync('anicel-device-back');
    deleteAfterSessionEnds(folder);
    final path = '${folder.path.replaceAll('\\', '/')}/project.anicel';
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final cut = s.requireActiveCut;
    s.createDrawingAtCurrentFrame();
    final selection = s.editingCanvas.activeBrushEditorSelection!;
    final cel = s.brushFrameKeyForCut(
      cut,
      selection.layerId,
      selection.frameId,
    );

    // One tile of 7s, its copy come, and one of 9s landed on a tile of 3s.
    final ledger = EngineTileLedger.instance;
    final copied = landedOn(ledger, cel.cel, [null], 7).single;
    expect(await ledger.copyHereABatch(), isFalse);
    expect(copied.isOnlyOnEngine, isFalse, reason: '⛔premise: its copy came');
    final under = BitmapTile(
      size: gpuTileSide,
      pixels: Uint8List(gpuTileBytes)..fillRange(0, gpuTileBytes, 3),
    );
    final landed = landedOn(ledger, cel.cel, [under], 9).single;
    expect(landed.isOnlyOnEngine, isTrue, reason: '⛔premise: no copy yet');

    standing.start();
    final gone = appGpuEngine..debugLose(forMemory: true);
    // What the session next asks of its device is refused, and reported
    // by what caught it.
    Object? refused;
    try {
      GpuStampPicture(gone, Uint8List(4), 1, 1).pixels();
    } on GpuRefused catch (error) {
      refused = error;
    }
    expect(refused, isNotNull, reason: '⛔premise: the device refuses');
    FlutterError.reportError(FlutterErrorDetails(exception: refused!));
    expect(appEngineGetsReady.value, isFalse, reason: 'after the turn');

    await startedAgain.future;
    expect(heldAsItWasLetGo, isTrue, reason: 'held from before it is let go');
    expect(heldAsTheNextOpened, isTrue, reason: 'and as the next opens');
    expect(appEngineGetsReady.value, isFalse, reason: 'let go by now');
    final next = appGpuEngineOpen.value;
    expect(next, isNotNull);
    expect(identical(next, gone), isFalse);
    expect(next!.isGone, isFalse);
    expect(
      EngineStrokes.debugBlursCompiled,
      isTrue,
      reason: 'the last of what a hand needs, compiled on the next',
    );
    expect(EngineRefusals.wentBy, GpuDeviceWent.memory);
    expect(tellings, 0, reason: 'no refusal is told');

    // The session goes on: a landing after, on the next engine's ledger.
    final after = landedOn(
      EngineTileLedger.instance,
      cel.cel,
      [null],
      5,
    ).single;
    expect(after.isOnlyOnEngine, isTrue, reason: '⛔premise: on the engine');
    final (first, second, third) = (
      TileCoord(x: 0, y: 0),
      TileCoord(x: 1, y: 0),
      TileCoord(x: 2, y: 0),
    );
    s.renderCaches.brushFrameStore.storeBakedSurface(
      cel,
      BitmapSurface(
        canvasSize: cut.canvasSize,
        tileSize: gpuTileSide,
        tiles: {first: copied, second: landed, third: after},
      ),
    );
    await s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);
    expect(s.projectFile.hasUnsavedChanges, isFalse);
    final opened = await openedSession(path);
    addTearDown(opened.dispose);
    final saved = opened.renderCaches.brushFrameStore.bakedSurfaceOrNull(cel)!;
    expect(saved.tileAt(first)!.pixels, everyElement(7));
    expect(saved.tileAt(second)!.pixels, everyElement(3));
    expect(saved.tileAt(third)!.pixels, everyElement(5));

    // The rest of the list a launch compiles goes on behind the app let
    // go: through before the test is, on the engine it was asked on.
    await appGpuGridKernels.warm();
    await (await appEngineFrameTools).composite.compileChains();
    await EngineStrokes.warmBlurStrips();
    await appGpuExportKernels.warm();
    await pumpEventQueue();
    expect(isTheAppsEngine(next), isTrue);
  });
}
