import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/rgba_image_bytes.dart';
import 'package:anicel/src/ui/playback/frame_picture_gpu.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/quiet_turns.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/poll_until.dart';

/// The store's logic — keys, the patch grid, which levels a patch writes,
/// when, the order, the budget — on a GPU that only records what it is
/// asked. Whether the writes SHOW is `frame_picture_store_gpu_test.dart`'s,
/// on a runner with Impeller.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const red = ui.Color(0xFFFF0000);
  const white = ui.Color(0xFFFFFFFF);
  void fill(ui.Canvas canvas) => canvas.drawPaint(ui.Paint()..color = red);
  FrameDrawing over(ui.Rect extent) =>
      (extent: extent, outside: white, draw: fill);
  // A pause no test sits through: the levels land at the cap or when asked.
  const never = Duration(days: 1);

  test('a picture is laid over its extent widened out to the grid of the '
      'world every level a canvas reads halves on', () async {
    final gpu = _RecordingGpu();
    final store = FramePictureStore<String>(gpu: gpu);
    // A canvas reads down to the level of 128 texels a side at its least
    // zoom (frameGridOutward), deeper than 1001 x 300's patches write.
    final picture = await store.lay(
      'a',
      over(const ui.Rect.fromLTRB(0.5, 0.5, 1000.7, 300.5)),
    );
    expect(picture!.extent, const ui.Rect.fromLTWH(0, 0, 1024, 384));
    expect(picture.outside, white);
    expect(gpu.rendered, [(1024, 384)]);
    expect(store.peek('a'), same(picture));
    expect(store.peek('b'), isNull);
    final past = await store.lay(
      'b',
      over(const ui.Rect.fromLTRB(-5, -5, 10, 10)),
    );
    expect(past!.extent, const ui.Rect.fromLTRB(-128, -128, 128, 128));
    expect(
      pictureExtentOf(const ui.Rect.fromLTRB(-5, -5, 10, 10)),
      past.extent,
    );
    store.dispose();
  });

  group('a patch', () {
    test('answers to the new key only once it has texels — the old key '
        'shows what it was until then', () async {
      final gpu = _RecordingGpu()..holdWrites = true;
      final store = FramePictureStore<String>(gpu: gpu);
      final picture = await _layed(store, 'a', 1024);
      expect(
        store.patch(
          from: 'a',
          to: 'b',
          rect: const ui.Rect.fromLTWH(10, 10, 4, 4),
          draw: fill,
        ),
        isTrue,
      );
      expect(store.peek('a'), same(picture));
      expect(store.peek('b'), isNull);
      // A lay of the key a patch is moving to waits for the patch.
      expect(await store.lay('b', over(picture.extent)), same(picture));
      expect(store.peek('a'), isNull);
      expect(picture.landing.map((p) => p.rect), [
        const ui.Rect.fromLTWH(8, 8, 8, 8),
      ]);
      await _landAll(gpu, store);
      expect(picture.landing, isEmpty);
      store.dispose();
    });

    test('draws what is there when it is asked for, not when its turn to '
        'render comes', () async {
      final gpu = _RecordingGpu()..holdWrites = true;
      final store = FramePictureStore<String>(gpu: gpu);
      final picture = await _layed(store, 'a', 1024);
      // A stroke's step draws tile pictures the next step replaces.
      var ink = red;
      store.patch(
        from: 'a',
        to: 'b',
        rect: const ui.Rect.fromLTWH(0, 0, 8, 8),
        draw: (canvas) => canvas.drawPaint(ui.Paint()..color = ink),
      );
      ink = white;
      expect(await pollUntil(() => store.peek('b') != null), isTrue);
      final texels = await picture.landing.single.image.toByteData();
      expect(texels!.getUint32(0), 0xFF0000FF, reason: 'red, as RGBA');
      await _landAll(gpu, store);
      store.dispose();
    });

    test('lets go of every drawing it records once rastered', () async {
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(gpu: gpu);
      await _layed(store, 'a', 1024);
      store.patch(
        from: 'a',
        to: 'a',
        rect: const ui.Rect.fromLTWH(0, 0, 8, 8),
        draw: fill,
      );
      await store.settled();
      // The lay, the patch, and the halvings its levels are read from.
      expect(gpu.recorded, hasLength(greaterThan(2)));
      expect(gpu.recorded.every((picture) => picture.debugDisposed), isTrue);
      store.dispose();
    });

    test('is widened outward to whole texels of the deepest level it '
        'writes, which it writes from its own halvings — and every deeper '
        'level whole after', () async {
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(gpu: gpu);
      // 1024 halves twice to 256: levels 1 and 2 from the patch, a grid
      // of 4; levels 3..10 made again whole.
      await _layed(store, 'a', 1024);
      store.patch(
        from: 'a',
        to: 'a',
        rect: const ui.Rect.fromLTRB(10.5, 20.2, 40.5, 27.2),
        draw: fill,
      );
      await store.settled();
      expect(gpu.bases.single.map(_baseDescribed), [(0, 8, 20, 36, 8)]);
      expect(gpu.levelWrites.single.spans.map(_spanDescribed), [
        (1, 4, 10, 18, 4),
        (2, 2, 5, 9, 2),
        for (var level = 3; level <= 10; level += 1)
          (level, 0, 0, 1024 >> level, 1024 >> level),
      ]);
      store.dispose();
    });

    test('of a picture no deeper than the grid writes no level whole',
        () async {
      final gpu = _RecordingGpu(levels: 3);
      final store = FramePictureStore<String>(gpu: gpu);
      await _layed(store, 'a', 1024);
      store.patch(
        from: 'a',
        to: 'a',
        rect: const ui.Rect.fromLTWH(0, 0, 4, 4),
        draw: fill,
      );
      await store.settled();
      expect(gpu.levelWrites.single.spans.map((span) => span.level), [1, 2]);
      store.dispose();
    });

    test('lays the levels it writes end to end, row after row, in one run '
        'the GPU copies out once', () async {
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(gpu: gpu);
      await _layed(store, 'a', 1024);
      for (final left in [0.0, 100.0]) {
        store.patch(
          from: 'a',
          to: 'a',
          rect: ui.Rect.fromLTWH(left, 0, 8, 8),
          draw: fill,
        );
      }
      await store.settled();
      final (:run, :spans) = gpu.levelWrites.single;
      var at = 0;
      for (final span in spans) {
        expect(span.start, at, reason: 'level ${span.level} at ${span.x}');
        at += span.width * span.height;
      }
      // The run wraps at 2048 a row: every texel, and no row more.
      expect(run, (2048, (at + 2047) ~/ 2048));
      store.dispose();
    });

    test('is off the picture only once the write of every level of it is '
        'done', () async {
      final gpu = _RecordingGpu()..holdWrites = true;
      final store = FramePictureStore<String>(gpu: gpu, levelsQuiet: never);
      final picture = await _layed(store, 'a', 1024);
      store.patch(
        from: 'a',
        to: 'a',
        rect: const ui.Rect.fromLTWH(0, 0, 8, 8),
        draw: fill,
      );
      expect(await pollUntil(() => gpu.bases.isNotEmpty), isTrue);
      gpu.releaseWrite();
      final settling = store.settled();
      expect(await pollUntil(() => gpu.levelWrites.isNotEmpty), isTrue);
      expect(picture.landing, hasLength(1), reason: 'the base is in, the '
          'levels under it are not');
      gpu.releaseWrite();
      await settling;
      expect(picture.landing, isEmpty);
      store.dispose();
    });

    test('that render while a batch lands land together, in one write',
        () async {
      final gpu = _RecordingGpu()..holdWrites = true;
      final store = FramePictureStore<String>(gpu: gpu);
      final picture = await _layed(store, 'a', 1024);
      store.patch(
        from: 'a',
        to: 'a',
        rect: const ui.Rect.fromLTWH(0, 0, 8, 8),
        draw: fill,
      );
      expect(await pollUntil(() => gpu.bases.isNotEmpty), isTrue);
      for (final left in [100.0, 200.0]) {
        store.patch(
          from: 'a',
          to: 'a',
          rect: ui.Rect.fromLTWH(left, 0, 8, 8),
          draw: fill,
        );
      }
      expect(await pollUntil(() => picture.landing.length == 3), isTrue);
      await _landAll(gpu, store);
      expect(gpu.bases, hasLength(2));
      expect(
        [for (final write in gpu.bases.last) write.x],
        [100, 200],
        reason: 'a later one after an earlier',
      );
      expect(
        [
          for (final span in gpu.levelWrites.single.spans)
            if (span.level == 1) span.x,
        ],
        [0, 50, 100],
        reason: 'the levels of all three in one write, in the order made',
      );
      store.dispose();
    });

    test('of a key an earlier patch is still moving goes on from it',
        () async {
      final gpu = _RecordingGpu()..holdWrites = true;
      final store = FramePictureStore<String>(gpu: gpu);
      final picture = await _layed(store, 'a', 512);
      expect(
        store.patch(
          from: 'a',
          to: 'b',
          rect: const ui.Rect.fromLTWH(0, 0, 8, 8),
          draw: fill,
        ),
        isTrue,
      );
      expect(
        store.patch(
          from: 'b',
          to: 'c',
          rect: const ui.Rect.fromLTWH(100, 100, 8, 8),
          draw: fill,
        ),
        isTrue,
      );
      expect(await store.lay('c', over(picture.extent)), same(picture));
      expect(store.peek('a'), isNull);
      expect(store.peek('b'), isNull);
      // A later one over an earlier, each until its own texels are in.
      expect(picture.landing.map((p) => p.rect.topLeft), [
        ui.Offset.zero,
        const ui.Offset(100, 100),
      ]);
      await _landAll(gpu, store);
      expect(picture.landing, isEmpty);
      store.dispose();
    });

    test('that cannot be taken lets go of the picture and answers false',
        () async {
      final store = FramePictureStore<String>(gpu: _RecordingGpu());
      final picture = await _layed(store, 'a', 256);
      expect(
        store.patch(
          from: 'nothing',
          to: 'b',
          rect: const ui.Rect.fromLTWH(0, 0, 8, 8),
          draw: fill,
        ),
        isFalse,
      );
      expect(store.peek('a'), same(picture));
      // A picture does not grow: ink past its extent is a new lay.
      expect(
        store.patch(
          from: 'a',
          to: 'b',
          rect: const ui.Rect.fromLTWH(250, 0, 8, 8),
          draw: fill,
        ),
        isFalse,
      );
      expect(store.peek('a'), isNull);
      expect(store.peek('b'), isNull);

      final noGpu = FramePictureStore<String>(gpu: _RecordingGpu(gpu: false));
      await _layed(noGpu, 'a', 256);
      expect(noGpu.peek('a'), isNotNull, reason: 'laid, but not writable');
      expect(
        noGpu.patch(
          from: 'a',
          to: 'b',
          rect: const ui.Rect.fromLTWH(0, 0, 8, 8),
          draw: fill,
        ),
        isFalse,
      );
      expect(noGpu.peek('a'), isNull);
      store.dispose();
      noGpu.dispose();
    });

    test('or move still on its way when its picture is let go answers once '
        '— whoever waited, and nothing when its turn comes', () async {
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(gpu: gpu);
      await _layed(store, 'a', 256);
      gpu.holdRenders = true;
      store.patch(
        from: 'a',
        to: 'b',
        rect: const ui.Rect.fromLTWH(0, 0, 8, 8),
        draw: fill,
      );
      store.move(from: 'b', to: 'c');
      final waited = [store.landingOf('b')!, store.landingOf('c')!];
      // Ink past the picture: a new lay, the picture let go.
      expect(
        store.patch(
          from: 'b',
          to: 'd',
          rect: const ui.Rect.fromLTWH(250, 0, 8, 8),
          draw: fill,
        ),
        isFalse,
      );
      await Future.wait(waited);
      gpu.releaseRender();
      await pumpEventQueue();
      expect(store.peek('c'), isNull);
      store.dispose();
    });
  });

  group('the levels under the base', () {
    test('wait for the patches to pause, and land once they do', () async {
      final gpu = _RecordingGpu();
      final waiting = FramePictureStore<String>(gpu: gpu, levelsQuiet: never);
      final picture = await _layed(waiting, 'a', 1024);
      waiting.patch(
        from: 'a',
        to: 'a',
        rect: const ui.Rect.fromLTWH(0, 0, 8, 8),
        draw: fill,
      );
      expect(await pollUntil(() => gpu.bases.isNotEmpty), isTrue);
      await pumpEventQueue();
      expect(gpu.levelWrites, isEmpty);
      expect(picture.landing, hasLength(1), reason: 'drawn over the levels '
          'it is not in yet');
      waiting.dispose();

      final paused = _RecordingGpu();
      final store = FramePictureStore<String>(
        gpu: paused,
        levelsQuiet: Duration.zero,
      );
      final laid = await _layed(store, 'a', 1024);
      store.patch(
        from: 'a',
        to: 'a',
        rect: const ui.Rect.fromLTWH(0, 0, 8, 8),
        draw: fill,
      );
      expect(await pollUntil(() => paused.levelWrites.isNotEmpty), isTrue);
      expect(await pollUntil(() => laid.landing.isEmpty), isTrue);
      expect(paused.levelWrites, hasLength(1));
      store.dispose();
    });

    test('wait for the patches to STOP: each that comes puts the pause off',
        () async {
      final gpu = _RecordingGpu();
      // Margins of half a second each way, for a loaded machine.
      final store = FramePictureStore<String>(
        gpu: gpu,
        levelsQuiet: const Duration(seconds: 2),
      );
      await _layed(store, 'a', 1024);
      for (final left in [0.0, 100.0]) {
        store.patch(
          from: 'a',
          to: 'a',
          rect: ui.Rect.fromLTWH(left, 0, 8, 8),
          draw: fill,
        );
        expect(
          await pollUntil(() => gpu.bases.length == (left == 0 ? 1 : 2)),
          isTrue,
        );
        await Future<void>.delayed(
          Duration(milliseconds: left == 0 ? 1000 : 1500),
        );
      }
      expect(gpu.levelWrites, isEmpty, reason: '2.5 s after the first, '
          '1.5 s after the second');
      expect(await pollUntil(() => gpu.levelWrites.isNotEmpty), isTrue);
      expect(
        [
          for (final span in gpu.levelWrites.single.spans)
            if (span.level == 1) span.x,
        ],
        [0, 50],
      );
      store.dispose();
    });

    test('of as many patches as are drawn over the picture at most are laid '
        'as one over their bounds, read from the base — none written', () async {
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(
        gpu: gpu,
        levelsQuiet: never,
        levelsWaitAtMost: 3,
      );
      final picture = await _layed(store, 'a', 1024);
      final laidAsOne = <ui.Image>[];
      for (var i = 0; i < 3; i += 1) {
        store.patch(
          from: 'a',
          to: 'a',
          rect: ui.Rect.fromLTWH(i * 100.0, 0, 8, 8),
          draw: fill,
        );
        expect(await pollUntil(() => gpu.bases.length == i + 1), isTrue);
        if (i < 2) {
          laidAsOne.add(picture.landing.last.image);
        }
      }
      expect(
        await pollUntil(
          () => picture.landing.length == 1 && laidAsOne.first.debugDisposed,
        ),
        isTrue,
      );
      expect(picture.landing.single.rect, const ui.Rect.fromLTWH(0, 0, 208, 8));
      expect(gpu.rendered.last, (208, 8));
      expect(laidAsOne.every((image) => image.debugDisposed), isTrue);
      await pumpEventQueue();
      expect(gpu.levelWrites, isEmpty);
      // A caller that waits for the levels has them with the rest.
      await store.settled();
      expect(picture.landing, isEmpty);
      expect(gpu.levelWrites.single.spans.first, (
        start: 0,
        width: 104,
        height: 4,
        x: 0,
        y: 0,
        level: 1,
      ));
      store.dispose();
    });

    test('of as many texels as wait at most are laid as one, and land once '
        'as many wait all the same', () async {
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(
        gpu: gpu,
        levelsQuiet: never,
        levelsWaitTexelsAtMost: 128,
      );
      final picture = await _layed(store, 'a', 1024);
      Future<void> patchAt(double left) async {
        final bases = gpu.bases.length;
        store.patch(
          from: 'a',
          to: 'a',
          rect: ui.Rect.fromLTWH(left, 0, 8, 8),
          draw: fill,
        );
        expect(await pollUntil(() => gpu.bases.length == bases + 1), isTrue);
      }

      // 64 and 64 texels, the most, lay as one of 96: under it, it waits.
      await patchAt(0);
      await patchAt(4);
      expect(
        await pollUntil(
          () =>
              picture.landing.length == 1 &&
              picture.landing.single.rect.width == 12,
        ),
        isTrue,
      );
      await pumpEventQueue();
      expect(gpu.levelWrites, isEmpty);
      // 96 and 64, one of them left to lay as one: they land.
      await patchAt(100);
      expect(await pollUntil(() => picture.landing.isEmpty), isTrue);
      expect(
        [
          for (final span in gpu.levelWrites.single.spans)
            if (span.level == 1) span.x,
        ],
        [0, 50],
      );
      expect(
        gpu.rendered.where((size) => size == (8, 8)),
        hasLength(3),
        reason: 'the three patches, the one left not rastered again as one',
      );
      // 64 and 64 laid as one of 864, more than the most: they land.
      await patchAt(200);
      await patchAt(300);
      expect(await pollUntil(() => gpu.levelWrites.length == 2), isTrue);
      expect(await pollUntil(() => picture.landing.isEmpty), isTrue);
      expect(gpu.levelWrites.last.spans.first.width, 54);
      store.dispose();
    });

    test('of patches laid as one wait under the patches that came after '
        'them', () async {
      final gpu = _RecordingGpu()..holdWrites = true;
      final store = FramePictureStore<String>(
        gpu: gpu,
        levelsQuiet: never,
        levelsWaitAtMost: 2,
      );
      final picture = await _layed(store, 'a', 1024);
      void patchAt(double left) => store.patch(
        from: 'a',
        to: 'a',
        rect: ui.Rect.fromLTWH(left, 0, 8, 8),
        draw: fill,
      );
      patchAt(0);
      expect(await pollUntil(() => gpu.bases.length == 1), isTrue);
      gpu.releaseWrite();
      patchAt(100);
      expect(await pollUntil(() => gpu.bases.length == 2), isTrue);
      // Its base not in yet when the two before it are laid as one.
      patchAt(200);
      expect(await pollUntil(() => picture.landing.length == 3), isTrue);
      gpu.releaseWrite();
      expect(
        await pollUntil(() => picture.landing.first.rect.width == 108),
        isTrue,
      );
      expect(picture.landing.map((patch) => patch.rect.left), [0, 200]);
      await _landAll(gpu, store);
      store.dispose();
    });

    test('land with the last of them once every patch drawn over the picture '
        'at most is one laid so, the pause or not', () async {
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(
        gpu: gpu,
        levelsQuiet: never,
        levelsWaitAtMost: 2,
      );
      final picture = await _layed(store, 'a', 1024);
      for (final (index, left) in [0.0, 100.0].indexed) {
        store.patch(
          from: 'a',
          to: 'a',
          rect: ui.Rect.fromLTWH(left, 0, 8, 8),
          draw: fill,
        );
        expect(await pollUntil(() => gpu.bases.length == index + 1), isTrue);
      }
      expect(
        await pollUntil(
          () =>
              picture.landing.length == 1 &&
              picture.landing.single.rect.width == 108,
        ),
        isTrue,
      );
      await pumpEventQueue();
      expect(gpu.levelWrites, isEmpty, reason: 'one is left to lay as one');
      store.patch(
        from: 'a',
        to: 'a',
        rect: const ui.Rect.fromLTWH(200, 0, 8, 8),
        draw: fill,
      );
      expect(await pollUntil(() => picture.landing.isEmpty), isTrue);
      expect(
        [
          for (final span in gpu.levelWrites.single.spans)
            if (span.level == 1) span.x,
        ],
        [0, 100],
      );
      // The count starts again from none.
      store.patch(
        from: 'a',
        to: 'a',
        rect: const ui.Rect.fromLTWH(300, 0, 8, 8),
        draw: fill,
      );
      expect(await pollUntil(() => gpu.bases.length == 4), isTrue);
      await pumpEventQueue();
      expect(gpu.levelWrites, hasLength(1));
      store.dispose();
    });

    // 🚨In place, never over (`FramePictureStore.patch`) — under the patched
    // levels too: the levels below them are made from the deepest, the
    // picture's own with each patch drawn into its place there.
    test('of a patch that clears are clear under it — its texels take the '
        'place of the picture\'s there, below the patched levels too',
        () async {
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(
        gpu: gpu,
        levelsQuiet: Duration.zero,
      );
      // Blue, 1024 a side: two levels patched, eight made from the deepest.
      await _layed(store, 'a', 1024);
      store.patch(
        from: 'a',
        to: 'a',
        rect: const ui.Rect.fromLTWH(0, 0, 64, 64),
        draw: (_) {},
      );
      expect(await pollUntil(() => gpu.runs.isNotEmpty), isTrue);
      final run = (await gpu.runs.single)!;
      final below = gpu.levelWrites.single.spans.firstWhere(
        (span) => span.level == 3,
      );
      expect(
        (below.x, below.y),
        (0, 0),
        reason: '⛔premise: the first level made from the deepest',
      );
      expect(
        run.getUint8(below.start * 4 + 3),
        0,
        reason: 'the patch drew nothing there and the level under it still '
            'holds the picture — the patch was drawn OVER the deepest level, '
            'not in its place',
      );
      store.dispose();
    });

    test('are background GPU work: they take their turn in the quiet '
        'between held frames', () async {
      final turns = _turnsInAQuiet();
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(
        gpu: gpu,
        quietTurns: turns,
        levelsQuiet: Duration.zero,
      );
      final picture = await _layed(store, 'a', 1024);
      final other = await turns.inAQuiet(QuietSpan(), gone: () => false);
      store.patch(
        from: 'a',
        to: 'a',
        rect: const ui.Rect.fromLTWH(0, 0, 8, 8),
        draw: fill,
      );
      expect(await pollUntil(() => gpu.bases.isNotEmpty), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await pumpEventQueue();
      expect(gpu.levelWrites, isEmpty, reason: 'another job holds the turn');
      await other!.landed();
      expect(await pollUntil(() => picture.landing.isEmpty), isTrue);
      expect(gpu.levelWrites, hasLength(1));
      store.dispose();
    });

    test('that a caller waits for are not background work: settled writes '
        'them past the turn another job holds', () async {
      final turns = _turnsInAQuiet();
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(
        gpu: gpu,
        quietTurns: turns,
        levelsQuiet: never,
      );
      final picture = await _layed(store, 'a', 1024);
      final other = await turns.inAQuiet(QuietSpan(), gone: () => false);
      store.patch(
        from: 'a',
        to: 'a',
        rect: const ui.Rect.fromLTWH(0, 0, 8, 8),
        draw: fill,
      );
      await store.settled();
      expect(gpu.levelWrites, hasLength(1));
      expect(picture.landing, isEmpty);
      await other!.landed();
      store.dispose();
    });

    test('go back to taking their turn once the caller is answered', () async {
      final turns = _turnsInAQuiet();
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(
        gpu: gpu,
        quietTurns: turns,
        levelsQuiet: Duration.zero,
      );
      final picture = await _layed(store, 'a', 1024);
      // Answered with nothing to write, then with something.
      await store.settled();
      for (final asked in [false, true, false]) {
        final other = await turns.inAQuiet(QuietSpan(), gone: () => false);
        final written = gpu.levelWrites.length;
        final based = gpu.bases.length;
        store.patch(
          from: 'a',
          to: 'a',
          rect: const ui.Rect.fromLTWH(0, 0, 8, 8),
          draw: fill,
        );
        expect(await pollUntil(() => gpu.bases.length == based + 1), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await pumpEventQueue();
        expect(gpu.levelWrites, hasLength(written), reason: 'asked: $asked');
        // A job that holds the turn runs; the caller waits for it alone.
        final answered = asked ? store.settled() : Future<void>.value();
        await other!.landed();
        await answered;
        expect(await pollUntil(() => picture.landing.isEmpty), isTrue);
      }
      store.dispose();
    });

    test('written for a caller leave the next ones to their turn', () async {
      final turns = _turnsInAQuiet();
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(
        gpu: gpu,
        quietTurns: turns,
        levelsQuiet: never,
        levelsWaitAtMost: 2,
      );
      final picture = await _layed(store, 'a', 1024);
      store.patch(
        from: 'a',
        to: 'a',
        rect: const ui.Rect.fromLTWH(0, 0, 8, 8),
        draw: fill,
      );
      // Nothing else waits: the caller's own write is the one that lands.
      await store.settled();
      expect(gpu.levelWrites, hasLength(1));
      final other = await turns.inAQuiet(QuietSpan(), gone: () => false);
      // Two at the most are laid as one, the third finds none left to.
      for (final left in [100.0, 200.0, 300.0]) {
        store.patch(
          from: 'a',
          to: 'a',
          rect: ui.Rect.fromLTWH(left, 0, 8, 8),
          draw: fill,
        );
      }
      expect(await pollUntil(() => picture.landing.length == 3), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await pumpEventQueue();
      expect(picture.landing, hasLength(3), reason: 'the two at the most '
          'wait for the turn another job holds to be laid as one');
      expect(gpu.levelWrites, hasLength(1));
      await other!.landed();
      expect(await pollUntil(() => picture.landing.isEmpty), isTrue);
      expect(gpu.levelWrites, hasLength(2));
      store.dispose();
    });

    test('waiting for a quiet with room become due once a caller waits for '
        'them', () async {
      final moves = <Completer<void>>[];
      final turns = QuietTurns(
        clock: QuietClock(
          // A run's quiet with no room at all: background work waits on.
          quiet: () => (fromMicros: 0, untilMicros: 0),
          now: () => 0,
          wait: (_) async {},
          moved: () {
            moves.add(Completer<void>());
            return moves.last.future;
          },
          held: () => true,
          gpuDone: () async {},
        ),
      );
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(
        gpu: gpu,
        quietTurns: turns,
        levelsQuiet: Duration.zero,
      );
      await _layed(store, 'a', 1024);
      store.patch(
        from: 'a',
        to: 'a',
        rect: const ui.Rect.fromLTWH(0, 0, 8, 8),
        draw: fill,
      );
      expect(await pollUntil(() => moves.isNotEmpty), isTrue);
      expect(gpu.levelWrites, isEmpty, reason: '⛔premise: it waits on');
      final settling = store.settled();
      moves.last.complete();
      await settling;
      expect(gpu.levelWrites, hasLength(1));
      store.dispose();
    });

    test('of a picture let go while they wait their turn are never read for '
        'or written', () async {
      final turns = _turnsInAQuiet();
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(
        gpu: gpu,
        quietTurns: turns,
        levelsQuiet: Duration.zero,
      );
      await _layed(store, 'a', 1024);
      final other = await turns.inAQuiet(QuietSpan(), gone: () => false);
      store.patch(
        from: 'a',
        to: 'a',
        rect: const ui.Rect.fromLTWH(0, 0, 8, 8),
        draw: fill,
      );
      expect(await pollUntil(() => gpu.bases.isNotEmpty), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final rendered = gpu.rendered.length;
      store.dispose();
      await other!.landed();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await pumpEventQueue();
      expect(gpu.levelWrites, isEmpty);
      expect(gpu.rendered, hasLength(rendered));
    });
  });

  test('a lay waits its turn, the frame shown now before those asked ahead '
      'of it', () async {
    final gpu = _RecordingGpu()..holdRenders = true;
    final store = FramePictureStore<String>(gpu: gpu);
    final laid = <Future<FramePicture?>>[
      for (final (index, key) in ['a', 'b', 'c'].indexed)
        store.lay(key, over(ui.Rect.fromLTWH(0, 0, 128.0 * (index + 1), 8))),
      store.lay(
        'shown',
        over(const ui.Rect.fromLTWH(0, 0, 512, 8)),
        shownNow: true,
      ),
    ];
    var allLaid = false;
    unawaited(Future.wait(laid).then((_) => allLaid = true));
    while (!allLaid) {
      gpu.releaseRender();
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    // 'a' was already rastering; the frame on screen goes next.
    expect(gpu.rendered.map((size) => size.$1), [128, 512, 256, 384]);
    store.dispose();
  });

  test('the budget lets go of the picture wanted latest, never a pinned '
      'one, and counts each by the app\'s one image estimate', () async {
    final store = FramePictureStore<String>(gpu: _RecordingGpu());
    for (final key in ['soon', 'late', 'pinned']) {
      await _layed(store, key, 128);
    }
    final one = estimatedImageBytes(128, 128);
    expect(store.estimatedBytes, 3 * one);
    store.retainPin('pinned');
    expect(store.pinnedBytes, one);
    final wanted = {'soon': 1, 'late': 9, 'pinned': 20};
    expect(
      store.enforceBudget(maxBytes: 2 * one, wantedAt: (key) => wanted[key]),
      isTrue,
    );
    expect(store.peek('late'), isNull);
    expect(store.peek('soon'), isNotNull);
    expect(
      store.enforceBudget(maxBytes: 0, wantedAt: (key) => wanted[key]),
      isFalse,
    );
    expect(store.peek('pinned'), isNotNull);
    store.releasePin('pinned');
    store.dispose();
  });

  test('a patch on its way in is billed with its picture until it lands',
      () async {
    final gpu = _RecordingGpu()..holdWrites = true;
    final store = FramePictureStore<String>(gpu: gpu);
    final picture = await _layed(store, 'a', 128);
    store.patch(
      from: 'a',
      to: 'b',
      rect: const ui.Rect.fromLTWH(0, 0, 8, 8),
      draw: fill,
    );
    expect(await pollUntil(() => picture.landing.isNotEmpty), isTrue);
    expect(
      store.estimatedBytes,
      estimatedImageBytes(128, 128) + estimatedImageBytes(8, 8),
    );
    await _landAll(gpu, store);
    expect(store.estimatedBytes, estimatedImageBytes(128, 128));
    store.dispose();
  });

  test('dispose lets every picture go and answers a waiting lay with none',
      () async {
    final gpu = _RecordingGpu()..holdRenders = true;
    final store = FramePictureStore<String>(gpu: gpu);
    final first = store.lay('a', over(const ui.Rect.fromLTWH(0, 0, 8, 8)));
    final waiting = store.lay('b', over(const ui.Rect.fromLTWH(0, 0, 8, 8)));
    await pumpEventQueue();
    store.dispose();
    expect(await waiting, isNull);
    gpu.releaseRender();
    expect(await first, isNull, reason: 'it came back after the dispose');
  });
}

Future<FramePicture> _layed(
  FramePictureStore<String> store,
  String key,
  int side,
) async => (await store.lay(key, (
  extent: ui.Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
  outside: const ui.Color(0xFFFFFFFF),
  draw: (canvas) =>
      canvas.drawPaint(ui.Paint()..color = const ui.Color(0xFF0000FF)),
)))!;

/// Turns in a quiet that is now and long: one job at a time, none waited
/// for longer than the one before it takes.
QuietTurns _turnsInAQuiet() => QuietTurns(
  clock: QuietClock(
    quiet: () => (fromMicros: 0, untilMicros: 1000000),
    now: () => 0,
    wait: (_) async {},
    moved: () => Completer<void>().future,
    held: () => false,
    gpuDone: () async {},
  ),
);

/// Lets every held write go until the store has nothing left to land.
Future<void> _landAll(
  _RecordingGpu gpu,
  FramePictureStore<String> store,
) async {
  var settled = false;
  unawaited(store.settled().then((_) => settled = true));
  while (!settled) {
    gpu.releaseWrite();
    // A real raster comes back through the engine, not the microtasks.
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

(int, int, int, int, int) _baseDescribed(BaseWrite write) => (
  0,
  write.x,
  write.y,
  write.source.width,
  write.source.height,
);

(int, int, int, int, int) _spanDescribed(RunSpan span) =>
    (span.level, span.x, span.y, span.width, span.height);

class _RecordingGpu implements FramePictureGpu {
  _RecordingGpu({this.gpu = true, this.levels});

  /// Whether there is a GPU to write with.
  final bool gpu;

  /// The levels a held texture has; by default, a whole chain.
  final int? levels;

  bool holdRenders = false;
  bool holdWrites = false;

  final List<(int, int)> rendered = [];
  final List<ui.Picture> recorded = [];
  final List<List<BaseWrite>> bases = [];
  final List<({(int, int) run, List<RunSpan> spans})> levelWrites = [];

  /// The texels of each run [levelWrites] was handed, RGBA row after row.
  final List<Future<ByteData?>> runs = [];
  final List<void Function()> _heldRenders = [];
  final List<Completer<bool>> _heldWrites = [];

  void releaseRender() {
    if (_heldRenders.isNotEmpty) {
      _heldRenders.removeAt(0)();
    }
  }

  void releaseWrite() {
    if (_heldWrites.isNotEmpty) {
      _heldWrites.removeAt(0).complete(true);
    }
  }

  @override
  Future<ui.Image> render(ui.Picture picture, int width, int height) {
    recorded.add(picture);
    if (!holdRenders) {
      rendered.add((width, height));
      return picture.toImage(width, height);
    }
    final done = Completer<ui.Image>();
    _heldRenders.add(() {
      rendered.add((width, height));
      done.complete(picture.toImage(width, height));
    });
    return done.future;
  }

  @override
  Object? hold(ui.Image image) => gpu ? image : null;

  @override
  int levelsOf(Object held) {
    final image = held as ui.Image;
    return levels ?? math.max(image.width, image.height).bitLength;
  }

  @override
  Future<bool> writeBase(Object held, List<BaseWrite> writes) {
    bases.add(writes);
    return _written();
  }

  @override
  Future<bool> writeLevels(Object held, ui.Image run, List<RunSpan> spans) {
    levelWrites.add((run: (run.width, run.height), spans: spans));
    runs.add(run.toByteData());
    return _written();
  }

  Future<bool> _written() {
    if (!holdWrites) {
      return Future.value(true);
    }
    final done = Completer<bool>();
    _heldWrites.add(done);
    return done.future;
  }
}
