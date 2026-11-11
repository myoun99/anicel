import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_frame_tools.dart';
import 'package:anicel/src/native/engine_stamp_pictures.dart';
import 'package:anicel/src/native/engine_strokes.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';

import '../helpers/tiles_on_the_engine.dart';

/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「RAM 에 사본을 두고 앱을
/// 유지한다」 — 「장치를 잃으면 앱은 꺼지지 않고 새 장치를 열어 사본으로
/// 되살린다」. The app lets go of an engine whose device is gone
/// ([letTheGoneAppGpuEngineGo]) and the next ask opens another; every
/// cache of what the engine made is kept for the engine it was made on
/// ([KeptOnTheAppsEngine]), so each is made again on the next one.
///
/// On the app's own engine, which each test loses: the one after it finds
/// the next.
void main() {
  // The frame's letters read their faces from the app's bundle.
  TestWidgetsFlutterBinding.ensureInitialized();

  // A cel, by the name a painter gives one.
  const cel = (1, 1);

  /// The engine that was the app's: its device gone, and let go.
  GpuEngine lostAndLetGo() {
    final gone = appGpuEngine..debugLose();
    // The word that a device is lost comes inside a wait: a read is one.
    expect(
      () => GpuStampPicture(gone, Uint8List(4), 1, 1).pixels(),
      throwsA(isA<GpuReadFailed>()),
    );
    letTheGoneAppGpuEngineGo();
    return gone;
  }

  /// A tile of [value] at every byte, its bytes here.
  BitmapTile tileOf(int value) => BitmapTile(
    size: gpuTileSide,
    pixels: Uint8List(gpuTileBytes)..fillRange(0, gpuTileBytes, value),
  );

  test('an engine whose device is not gone is not let go', () {
    final engine = appGpuEngine;

    letTheGoneAppGpuEngineGo();

    expect(identical(appGpuEngine, engine), isTrue);
  });

  test('let go, the app has no engine that is gone, and opens another the '
      'next time it is asked', () {
    final gone = lostAndLetGo();

    expect(appGpuEngineIsGone, isFalse, reason: 'none is open');
    final next = appGpuEngine;
    expect(identical(next, gone), isFalse);
    expect(next.isGone, isFalse);
    expect(isTheAppsEngine(next), isTrue);
    expect(isTheAppsEngine(gone), isFalse);
  });

  // ⛔What a closed engine answers is not this test's to ask: its memory is
  // given back. The tiles and stamps of the engine let go still read
  // through it (the ledger's and the stamps' pins below).
  test('the engine let go is not closed', () {
    final source = File(
      'lib/src/native/app_gpu_engine.dart',
    ).readAsStringSync();
    final from = source.indexOf('void letTheGoneAppGpuEngineGo() {');
    final body = source.substring(from, source.indexOf('\n}', from));
    expect(from, isNonNegative);
    expect(body, isNot(contains('close')));
  });

  test('no engine is said to be open from the letting go till the next is '
      'opened', () async {
    await openAppGpuEngine();
    final heard = <GpuEngine?>[];
    void hear() => heard.add(appGpuEngineOpen.value);
    appGpuEngineOpen.addListener(hear);
    addTearDown(() => appGpuEngineOpen.removeListener(hear));

    final gone = lostAndLetGo();
    expect(heard, [null]);

    final next = await openAppGpuEngine();
    expect(identical(next, gone), isFalse);
    expect(heard, [null, next]);
    expect(identical(appGpuEngine, next), isTrue);
  });

  group('a set of kernels', () {
    late List<GpuInk> freed;
    late AppKernels<GpuInk> kernels;

    setUp(() {
      freed = [];
      kernels = AppKernels<GpuInk>(GpuInk.new, GpuInk.opening, (ink) {
        freed.add(ink);
        ink.free();
      });
    });
    tearDown(() => kernels.debugForget());

    // ⛔Left with its engine: what else that engine made may hold it still
    // (`KeptOnTheAppsEngine`).
    test('is kept no longer once its engine is let go — and not freed — '
        'and is compiled again on the next', () {
      final first = kernels.kept;

      lostAndLetGo();

      expect(kernels.compiled, isNull);
      final next = kernels.kept;
      expect(identical(next, first), isFalse);
      expect(kernels.compiled, same(next));
      expect(freed, isEmpty);

      kernels.debugForget();
      expect(freed, [next], reason: 'asked to forget, it frees what it keeps');
    });

    test('compiled off this isolate on an engine let go meanwhile is not '
        'kept: the next engine is asked the same way', () async {
      AppKernels.debugCompileHere = false;
      addTearDown(() => AppKernels.debugCompileHere = true);
      final made = <GpuInk>[];
      final racing = AppKernels<GpuInk>(
        GpuInk.new,
        (engine) async {
          made.add(GpuInk(engine));
          if (made.length == 1) {
            // Its device goes, and the app lets it go, as it compiles.
            lostAndLetGo();
          }
          return made.last;
        },
        (ink) {
          freed.add(ink);
          ink.free();
        },
      );
      addTearDown(racing.debugForget);

      final warmed = await racing.warm();

      expect(made, hasLength(2));
      expect(warmed, same(made.last));
      expect(freed, [made.first]);
      expect(racing.compiled, same(made.last));
    });
  });

  test('a stroke at rest is not handed out on the next engine, and one '
      'given back from the last is not kept', () {
    final stroke = EngineStrokes.take();
    EngineStrokes.giveBack(stroke);
    expect(EngineStrokes.debugIdle, 1, reason: '⛔premise: it rests');
    final drawing = EngineStrokes.take();
    EngineStrokes.giveBack(EngineStrokes.take());
    expect(EngineStrokes.debugIdle, 1, reason: '⛔premise: one more rests');

    lostAndLetGo();

    expect(EngineStrokes.debugIdle, 0);
    EngineStrokes.giveBack(drawing);
    expect(EngineStrokes.debugIdle, 0, reason: 'of the engine let go');
    final next = EngineStrokes.take();
    expect(isTheAppsEngine(next.engine), isTrue);
    EngineStrokes.giveBack(next);
    expect(EngineStrokes.debugIdle, 1);
  });

  test('the next engine has a ledger of its own, which stores a tile of '
      'the last one as what that tile reads as', () {
    final ledger = EngineTileLedger.instance;
    final copied = landedOn(ledger, cel, [tileOf(7)], 9).single;
    ledger.copyHereABatch();
    final lost = landedOn(ledger, cel, [tileOf(3)], 4).single;
    expect(copied.isOnlyOnEngine, isFalse, reason: '⛔premise: copied');
    expect(lost.isOnlyOnEngine, isTrue, reason: '⛔premise: no copy yet');

    lostAndLetGo();

    expect(EngineTileLedger.opened, isNull);
    final next = EngineTileLedger.instance;
    expect(identical(next, ledger), isFalse);
    expect(EngineTileLedger.opened, same(next));
    final asked = [copied, lost];
    final into = calloc<Uint8>(asked.length * gpuTileBytes);
    addTearDown(() => calloc.free(into));
    next.held((hold) => next.pool.read(hold.slotsOf(cel, asked), into));
    final bytes = into.asTypedList(asked.length * gpuTileBytes);
    expect(
      [for (var at = 0; at < asked.length; at++) bytes[at * gpuTileBytes]],
      [9, 3],
      reason: 'its copy, and the picture the other landed on',
    );
    expect(bytes.toSet(), {9, 3});
  });

  test('a stamp is handed up again to the next engine', () {
    final stamp = BrushStampImage(
      id: 'a stamp',
      width: 2,
      height: 2,
      rgba: Uint8List(16)..fillRange(0, 16, 5),
    );
    final first = EngineStampPictures.of(stamp);
    final handedUp = EngineStampPictures.debugHandedUp;
    expect(EngineStampPictures.of(stamp), same(first), reason: '⛔premise');

    lostAndLetGo();

    final next = EngineStampPictures.of(stamp);
    expect(identical(next, first), isFalse);
    expect(EngineStampPictures.debugHandedUp, handedUp + 1);
    expect(next.pixels(), everyElement(5));
  });

  test('the tools a frame is laid with are opened again on the next '
      'engine', () async {
    final first = await appEngineFrameTools;
    expect(appEngineFrameToolsOpen, same(first), reason: '⛔premise');

    lostAndLetGo();

    expect(appEngineFrameToolsOpen, isNull);
    final next = await appEngineFrameTools;
    expect(identical(next.composite, first.composite), isFalse);
    expect(isTheAppsEngine(next.composite.engine), isTrue);
    expect(appEngineFrameToolsOpen, same(next));
  });
}
