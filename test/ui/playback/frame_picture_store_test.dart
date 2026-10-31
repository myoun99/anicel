import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/rgba_image_bytes.dart';
import 'package:anicel/src/services/composite_effect_paint.dart'
    show resolveCompositeEffectPlan;
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart'
    show applyEffectSteps;
import 'package:anicel/src/ui/debug/input_inspector.dart';
import 'package:anicel/src/ui/playback/frame_picture_gpu.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/a_plugin_that_shifts.dart';
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
    test('answers to the new key only once its texels are in the picture, '
        'at every level — the old key shows what it was until then',
        () async {
      final gpu = _RecordingGpu()..holdWrites = true;
      final store = FramePictureStore<String>(gpu: gpu);
      final picture = await _layed(store, 'a', 1024);
      picture.readAt(_readsLevels);
      expect(
        store.patch(
          from: 'a',
          to: 'b',
          rect: const ui.Rect.fromLTWH(10, 10, 4, 4),
          draw: fill,
        ),
        isTrue,
      );
      final landing = store.landingOf('b')!;
      // A lay of the key a patch is moving to waits for the patch.
      final laid = store.lay('b', over(picture.extent));
      expect(await pollUntil(() => gpu.bases.isNotEmpty), isTrue);
      expect(gpu.bases.single.map(_baseDescribed), [(0, 8, 8, 8, 8)]);
      expect(
        gpu.levelWrites,
        hasLength(1),
        reason: 'the base and the levels under it in one write',
      );
      expect(
        store.peek('a'),
        same(picture),
        reason: 'the write is on its way, not done',
      );
      expect(store.peek('b'), isNull);
      gpu.releaseWrite();
      expect(await laid, same(picture));
      expect(await landing, isTrue, reason: 'in');
      expect(store.peek('a'), isNull);
      store.dispose();
    });

    test('draws what is there when it is asked for, not when its turn to '
        'render comes', () async {
      final gpu = _RecordingGpu()..holdWrites = true;
      final store = FramePictureStore<String>(gpu: gpu);
      await _layed(store, 'a', 1024);
      // A stroke's step draws tile pictures the next step replaces.
      var ink = red;
      store.patch(
        from: 'a',
        to: 'b',
        rect: const ui.Rect.fromLTWH(0, 0, 8, 8),
        draw: (canvas) => canvas.drawPaint(ui.Paint()..color = ink),
      );
      ink = white;
      expect(await pollUntil(() => gpu.bases.isNotEmpty), isTrue);
      final texels = await gpu.bases.single.single.source.toByteData();
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

    group('🗣️I-132-Q34 a 「결과가 올 때까지 … 머문다」: over a plugin\'s step', () {
      const paper = ui.Rect.fromLTWH(0, 0, 8, 8);

      /// What draws red at (0, 0) through a plugin moving it two to the
      /// right — a step only a recording that waits runs — and how often
      /// it was drawn.
      ({void Function(ui.Canvas) draw, int Function() draws, ShiftingFxPlugin
          runner}) throughAPlugin() {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawRect(
          const ui.Rect.fromLTWH(0, 0, 1, 1),
          ui.Paint()..color = red,
        );
        final dot = recorder.endRecording().toImageSync(8, 8);
        addTearDown(dot.dispose);
        final runner = ShiftingFxPlugin(by: 2);
        final steps = resolveCompositeEffectPlan([
          ResolvedLayerEffect(
            kind: EffectKind.plugin,
            plugin: shiftingFxPluginDescription,
            values: const [],
            run: fxPluginRunOf(runner),
          ),
        ], paper: paper).preSteps;
        var draws = 0;
        return (
          draw: (canvas) {
            draws += 1;
            final image = applyEffectSteps(
              source: dot,
              steps: steps,
              imageScale: 1,
              paper: paper,
            );
            canvas.drawImage(image, ui.Offset.zero, ui.Paint());
            if (!identical(image, dot)) {
              image.dispose();
            }
          },
          draws: () => draws,
          runner: runner,
        );
      }

      test('a frame laid is laid as its plugin made it, drawn again once '
          'that has run', () async {
        final store = FramePictureStore<String>(gpu: _RecordingGpu());
        final (:draw, :draws, :runner) = throughAPlugin();

        final picture = (await store.lay('a', (
          extent: paper,
          outside: const ui.Color(0xFFFFFFFF),
          draw: draw,
        )))!;

        expect((draws(), runner.renders), (2, 1));
        final texels = await picture.image.toByteData();
        expect(texels!.getUint32(2 * 4), 0xFF0000FF, reason: 'red, moved');
        expect(texels.getUint32(0), 0, reason: 'none where it was drawn');
        store.dispose();
      });

      test('it goes in as its plugin made it, drawn again once that has '
          'run', () async {
        final gpu = _RecordingGpu()..holdWrites = true;
        final store = FramePictureStore<String>(gpu: gpu);
        await _layed(store, 'a', 1024);
        final (:draw, :draws, :runner) = throughAPlugin();

        store.patch(from: 'a', to: 'b', rect: paper, draw: draw);
        expect(draws(), 1, reason: 'drawn as it is asked for');
        expect(await pollUntil(() => gpu.bases.isNotEmpty), isTrue);

        expect((draws(), runner.renders), (2, 1));
        final texels = await gpu.bases.single.single.source.toByteData();
        expect(texels!.getUint32(2 * 4), 0xFF0000FF, reason: 'red, moved');
        expect(texels.getUint32(0), 0, reason: 'none where it was drawn');
        await _landAll(gpu, store);
        expect(store.peek('b'), isNotNull);
        store.dispose();
      });

      test('where what it drew is gone before its plugin has run, it does '
          'not go in, and its picture goes', () async {
        final gpu = _RecordingGpu();
        final store = FramePictureStore<String>(gpu: gpu);
        await _layed(store, 'a', 1024);
        final (:draw, :draws, :runner) = throughAPlugin();
        var gone = false;

        store.patch(
          from: 'a',
          to: 'b',
          rect: paper,
          draw: draw,
          gone: () => gone,
        );
        gone = true;

        expect(await store.landingOf('b'), isFalse);
        expect(draws(), 1, reason: 'not drawn again');
        expect(runner.renders, 1, reason: '⛔premise: the round came');
        expect(store.peek('a'), isNull);
        expect(store.peek('b'), isNull);
        store.dispose();
      });
    });

    test('lets go of its texels once they are in its picture', () async {
      final gpu = _RecordingGpu()..holdWrites = true;
      final store = FramePictureStore<String>(gpu: gpu);
      await _layed(store, 'a', 128);
      store.patch(
        from: 'a',
        to: 'b',
        rect: const ui.Rect.fromLTWH(0, 0, 8, 8),
        draw: fill,
      );
      expect(await pollUntil(() => gpu.bases.isNotEmpty), isTrue);
      final texels = gpu.bases.single.single.source;
      expect(texels.debugDisposed, isFalse, reason: '⛔premise: on its way');
      await _landAll(gpu, store);
      expect(texels.debugDisposed, isTrue);
      expect(store.estimatedBytes, estimatedImageBytes(128, 128));
      store.dispose();
    });

    test('is widened outward to whole texels of the deepest level it '
        'writes, which it writes from its own halvings — and every deeper '
        'level whole after', () async {
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(gpu: gpu);
      // 1024 halves twice to 256: levels 1 and 2 from the patch, a grid
      // of 4; levels 3..10 made again whole.
      (await _layed(store, 'a', 1024)).readAt(_readsLevels);
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
      (await _layed(store, 'a', 1024)).readAt(_readsLevels);
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

    test('that render while a batch is written go in together, the base '
        'and the levels under it in one write', () async {
      final gpu = _RecordingGpu()..holdWrites = true;
      final store = FramePictureStore<String>(gpu: gpu);
      (await _layed(store, 'a', 1024)).readAt(_readsLevels);
      void patchAt(double left) => store.patch(
        from: 'a',
        to: 'a',
        rect: ui.Rect.fromLTWH(left, 0, 8, 8),
        draw: fill,
      );
      patchAt(0);
      expect(await pollUntil(() => gpu.bases.isNotEmpty), isTrue);
      patchAt(100);
      patchAt(200);
      expect(
        await pollUntil(
          () => gpu.rendered.where((size) => size == (8, 8)).length == 3,
        ),
        isTrue,
      );
      await _landAll(gpu, store);
      expect(gpu.bases, hasLength(2));
      expect(
        [for (final write in gpu.bases.last) write.x],
        [100, 200],
        reason: 'a later one after an earlier',
      );
      expect(
        [
          for (final write in gpu.levelWrites)
            [
              for (final span in write.spans)
                if (span.level == 1) span.x,
            ],
        ],
        [
          [0],
          [50, 100],
        ],
        reason: 'each batch\'s levels with its base, in the order asked',
      );
      store.dispose();
    });

    test('lays the levels it writes end to end, row after row, in one run '
        'the GPU copies out once', () async {
      final gpu = _RecordingGpu()..holdWrites = true;
      final store = FramePictureStore<String>(gpu: gpu);
      (await _layed(store, 'a', 1024)).readAt(_readsLevels);
      for (final left in [300.0, 0.0, 100.0]) {
        store.patch(
          from: 'a',
          to: 'a',
          rect: ui.Rect.fromLTWH(left, 0, 8, 8),
          draw: fill,
        );
        if (left == 300) {
          expect(await pollUntil(() => gpu.bases.isNotEmpty), isTrue);
        }
      }
      expect(
        await pollUntil(
          () => gpu.rendered.where((size) => size == (8, 8)).length == 3,
        ),
        isTrue,
      );
      await _landAll(gpu, store);
      final (:run, :spans) = gpu.levelWrites.last;
      expect(
        [
          for (final span in spans)
            if (span.level == 1) span.x,
        ],
        [0, 50],
        reason: '⛔premise: two patches in the one run',
      );
      var at = 0;
      for (final span in spans) {
        expect(span.start, at, reason: 'level ${span.level} at ${span.x}');
        at += span.width * span.height;
      }
      // The run wraps at 2048 a row: every texel, and no row more.
      expect(run, (2048, (at + 2047) ~/ 2048));
      store.dispose();
    });

    // 🚨In place, never over (`FramePictureStore.patch`) — under the patched
    // levels too: the levels below them are made from the deepest, the
    // picture's own with each patch drawn into its place there.
    test('that clears is clear under the patched levels too — its texels '
        'take the place of the picture\'s there', () async {
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(gpu: gpu);
      // Blue, 1024 a side: two levels patched, eight made from the deepest.
      (await _layed(store, 'a', 1024)).readAt(_readsLevels);
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

    test('of a key an earlier patch is still moving goes on from it',
        () async {
      final gpu = _RecordingGpu()..holdWrites = true;
      final store = FramePictureStore<String>(gpu: gpu);
      final picture = await _layed(store, 'a', 512);
      picture.readAt(_readsLevels);
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
      final laid = store.lay('c', over(picture.extent));
      await _landAll(gpu, store);
      expect(await laid, same(picture));
      expect(store.peek('a'), isNull);
      expect(store.peek('b'), isNull);
      expect(
        [
          for (final batch in gpu.bases)
            for (final write in batch) (write.x, write.y),
        ],
        [(0, 0), (100, 100)],
        reason: 'a later one over an earlier',
      );
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

    test('the GPU did not write lets go of the picture: no key answers with '
        'texels it does not hold', () async {
      final gpu = _RecordingGpu()..writesLand = false;
      final store = FramePictureStore<String>(gpu: gpu);
      final picture = await _layed(store, 'a', 256);
      store.patch(
        from: 'a',
        to: 'b',
        rect: const ui.Rect.fromLTWH(0, 0, 8, 8),
        draw: fill,
      );
      expect(await store.landingOf('b'), isFalse, reason: 'not in');
      expect(store.peek('a'), isNull);
      expect(store.peek('b'), isNull);
      expect(await pollUntil(() => picture.image.debugDisposed), isTrue);
      store.dispose();
    });

    test('the input inspector says how the writes went — ok, failed and '
        'threw, counted while it is hidden too (F-509)', () async {
      _reported();
      addTearDown(InputInspector.reset);
      List<int> tally() => [
        for (final number in RegExp(
          r'\d+',
        ).allMatches(InputInspector.pinned['picture writes']!))
          int.parse(number[0]!),
      ];
      Future<void> write(_RecordingGpu gpu) async {
        final store = FramePictureStore<String>(gpu: gpu);
        await _layed(store, 'a', 256);
        store.patch(
          from: 'a',
          to: 'b',
          rect: const ui.Rect.fromLTWH(0, 0, 8, 8),
          draw: fill,
        );
        await store.landingOf('b');
        store.dispose();
      }

      await write(_RecordingGpu());
      expect(InputInspector.pinned, isEmpty, reason: 'hidden, it pins nothing');

      InputInspector.visible.value = true;
      await write(_RecordingGpu());
      final [ok, failed, threw] = tally();
      expect(ok, greaterThanOrEqualTo(2), reason: 'the hidden one counts');

      await write(_RecordingGpu());
      expect(tally(), [ok + 1, failed, threw]);
      await write(_RecordingGpu()..writesLand = false);
      expect(tally(), [ok + 1, failed + 1, threw]);
      await write(_RecordingGpu()..writesThrow = StateError('unsized texels'));
      expect(tally(), [ok + 1, failed + 1, threw + 1]);
    });

    test('the GPU threw writing lets go of the picture and answers every '
        'patch on its way, none in — the throw reported (F-509)', () async {
      final reported = _reported();
      final gpu = _RecordingGpu()..writesThrow = StateError('unsized texels');
      final store = FramePictureStore<String>(gpu: gpu);
      final picture = await _layed(store, 'a', 256);
      final landings = <Future<bool>>[];
      // A stroke's two steps — the first no longer the last asked for to
      // its key — and its lift.
      for (final from in ['a', 'b']) {
        store.patch(
          from: from,
          to: 'b',
          rect: const ui.Rect.fromLTWH(0, 0, 8, 8),
          draw: fill,
        );
        landings.add(store.landingOf('b')!);
      }
      store.move(from: 'b', to: 'c');
      landings.add(store.landingOf('c')!);
      for (final landing in landings) {
        expect(await patiently(landing), isFalse, reason: 'not in');
      }
      expect(store.peek('a'), isNull);
      expect(store.peek('b'), isNull);
      expect(store.peek('c'), isNull);
      expect(await pollUntil(() => picture.image.debugDisposed), isTrue);
      expect(reported, [isA<StateError>()]);
      store.dispose();
    });

    test('that threw rendering lets go of the picture and is answered, none '
        'in — so is a patch behind it, and both throws reported', () async {
      final reported = _reported();
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(gpu: gpu);
      final picture = await _layed(store, 'a', 256);
      gpu.rendersThrow = StateError('no raster');
      final landings = <Future<bool>>[];
      for (final from in ['a', 'b']) {
        store.patch(
          from: from,
          to: 'b',
          rect: const ui.Rect.fromLTWH(0, 0, 8, 8),
          draw: fill,
        );
        landings.add(store.landingOf('b')!);
      }
      for (final landing in landings) {
        expect(await patiently(landing), isFalse, reason: 'not in');
      }
      expect(store.peek('a'), isNull);
      expect(store.peek('b'), isNull);
      expect(await pollUntil(() => picture.image.debugDisposed), isTrue);
      expect(reported, [isA<StateError>(), isA<StateError>()]);
      expect(gpu.bases, isEmpty, reason: 'nothing written');
      store.dispose();
    });

    test('of a picture let go while the levels under its base are drawn is '
        'not written at all', () async {
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(gpu: gpu);
      (await _layed(store, 'a', 1024)).readAt(_readsLevels);
      gpu.holdRenders = true;
      final asked = gpu.recorded.length;
      store.patch(
        from: 'a',
        to: 'a',
        rect: const ui.Rect.fromLTWH(0, 0, 8, 8),
        draw: fill,
      );
      expect(await pollUntil(() => gpu.recorded.length == asked + 1), isTrue);
      gpu.releaseRender();
      expect(
        await pollUntil(() => gpu.recorded.length == asked + 2),
        isTrue,
        reason: '⛔premise: a level under its base drawn',
      );
      store.dispose();
      for (var render = 0; render < 2; render += 1) {
        gpu.releaseRender();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await pumpEventQueue();
      }
      expect(gpu.recorded, hasLength(asked + 3), reason: '⛔premise: its run');
      expect(gpu.bases, isEmpty);
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

  // 🚨★★★F-512: a step's cost is its waits, and the levels take three more
  // of them than the base. The screen is the one reader that matters while a
  // pen moves, and a screen above 1/2 reads no level at all.
  group('a level no screen reads', () {
    const spot = ui.Rect.fromLTWH(96, 96, 32, 32);
    const pause = Duration(milliseconds: 260);
    final everyLevel = [for (var level = 1; level <= 10; level += 1) level];

    Iterable<int> levelsOf(({(int, int) run, List<RunSpan> spans}) write) =>
        write.spans.map((span) => span.level);

    test('is none for a screen above 1/2 and every one for a screen at or '
        'under it', () async {
      Future<List<int>> laidAt(double scale) async {
        final gpu = _RecordingGpu();
        final store = FramePictureStore<String>(gpu: gpu);
        (await _layed(store, 'a', 1024)).readAt(scale);
        store.patch(from: 'a', to: 'b', rect: spot, draw: fill);
        await store.landingOf('b');
        store.dispose();
        return [for (final write in gpu.levelWrites) ...levelsOf(write)];
      }

      expect(await laidAt(1), isEmpty);
      expect(await laidAt(0.75), isEmpty);
      expect(await laidAt(0.51), isEmpty);
      expect(await laidAt(0.5), everyLevel);
      expect(await laidAt(0.44), everyLevel);
      expect(await laidAt(0.2), everyLevel);
    });

    test('waits for the patches to pause, a step laying the base alone',
        () async {
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(gpu: gpu);
      final picture = await _layed(store, 'a', 1024);
      store.patch(from: 'a', to: 'b', rect: spot, draw: fill);
      expect(await store.landingOf('b'), isTrue);
      expect(store.peek('b'), same(picture));
      expect(gpu.bases.single.map(_baseDescribed), [(0, 96, 96, 32, 32)]);
      expect(gpu.levelWrites, isEmpty);
      expect(picture.readAt(1), isTrue, reason: 'the base holds it');

      expect(await pollUntil(() => gpu.levelWrites.isNotEmpty), isTrue);
      expect(levelsOf(gpu.levelWrites.single), everyLevel);
      expect(gpu.bases.last.map(_baseDescribed), [(0, 96, 96, 32, 32)]);
      expect(await pollUntil(() => picture.readAt(_readsLevels)), isTrue);
      store.dispose();
    });

    test('owes nothing where a screen reads any of them', () async {
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(gpu: gpu);
      final picture = await _layed(store, 'a', 1024);
      expect(picture.readAt(0.4), isTrue, reason: 'nothing is owed yet');
      store.patch(from: 'a', to: 'b', rect: spot, draw: fill);
      await store.landingOf('b');
      expect(levelsOf(gpu.levelWrites.single), everyLevel);
      expect(picture.readAt(0.2), isTrue);
      await store.settled();
      expect(gpu.levelWrites, hasLength(1));
      store.dispose();
    });

    test('goes in where one of the screens reads them', () async {
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(gpu: gpu);
      (await _layed(store, 'a', 1024))
        ..readAt(0.4)
        ..readAt(1);
      store.patch(from: 'a', to: 'b', rect: spot, draw: fill);
      await store.landingOf('b');
      expect(levelsOf(gpu.levelWrites.single), everyLevel);
      store.dispose();
    });

    test('a step owes is not paid by a deeper step after it', () async {
      final gpu = _RecordingGpu()..holdWrites = true;
      final store = FramePictureStore<String>(gpu: gpu);
      final picture = await _layed(store, 'a', 1024);
      store.patch(from: 'a', to: 'b', rect: spot, draw: fill);
      expect(await pollUntil(() => gpu.bases.length == 1), isTrue);
      store.patch(from: 'b', to: 'c', rect: spot, draw: fill);
      expect(await pollUntil(() => gpu.rendered.length == 3), isTrue);
      expect(picture.readAt(0.4), isTrue, reason: '⛔premise: nothing owed yet');

      gpu.holdWrites = false;
      gpu.releaseWrite();
      expect(await store.landingOf('c'), isTrue);
      expect(levelsOf(gpu.levelWrites.single), everyLevel);
      expect(picture.readAt(0.4), isFalse, reason: 'the first step owes them');
      store.dispose();
    });

    test('is written at once for a screen that comes to read it, which is '
        'told so until it is in', () async {
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(gpu: gpu);
      final picture = await _layed(store, 'a', 1024);
      var told = 0;
      picture.addListener(() => told += 1);
      store.patch(from: 'a', to: 'b', rect: spot, draw: fill);
      await store.landingOf('b');
      expect(told, 1);
      final behind = picture.image;

      expect(picture.readAt(0.4), isFalse);
      expect(picture.readAt(_readsLevels), isFalse, reason: 'asked once');
      expect(await pollUntil(() => picture.readAt(0.4)), isTrue);
      expect(gpu.levelWrites, hasLength(1));
      expect(levelsOf(gpu.levelWrites.single), everyLevel);
      expect(told, 2, reason: 'whoever draws it draws the one it is now');
      expect(picture.image, isNot(same(behind)));
      await Future<void>.delayed(pause);
      expect(gpu.levelWrites, hasLength(1), reason: 'nothing left to wait for');
      store.dispose();
    });

    test('is asked for by a screen that comes to read it with no pause in '
        'sight', () async {
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(gpu: gpu);
      final picture = await _layed(store, 'a', 1024);
      store.patch(from: 'a', to: 'b', rect: spot, draw: fill);
      await store.landingOf('b');
      gpu.holdRenders = true;
      final asked = gpu.recorded.length;
      store.patch(from: 'b', to: 'c', rect: spot, draw: fill);
      expect(await pollUntil(() => gpu.recorded.length == asked + 1), isTrue);

      expect(picture.readAt(0.4), isFalse);
      expect(
        await pollUntil(() => gpu.recorded.length == asked + 2),
        isTrue,
        reason: 'the base read for what the levels owe',
      );
      gpu
        ..holdRenders = false
        ..releaseRender()
        ..releaseRender();
      await store.settled();
      store.dispose();
    });

    test('owes every step of a stroke, as one patch over all of them',
        () async {
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(gpu: gpu);
      await _layed(store, 'a', 1024);
      store
        ..patch(
          from: 'a',
          to: 'b',
          rect: const ui.Rect.fromLTWH(16, 8, 4, 4),
          draw: fill,
        )
        ..patch(
          from: 'b',
          to: 'c',
          rect: const ui.Rect.fromLTWH(96, 196, 4, 4),
          draw: fill,
        );
      await store.landingOf('c');
      await store.settled();
      expect(gpu.bases.last.map(_baseDescribed), [(0, 16, 8, 84, 192)]);
      expect(gpu.levelWrites, hasLength(1));
      store.dispose();
    });

    group('more than one write should take', () {
      const stroke = ui.Rect.fromLTWH(0, 0, 1024, 128);
      final parts = [
        for (var x = 0; x < 1024; x += 128) (0, x, 0, 128, 128),
      ];

      Iterable<(int, int, int, int, int)> paid(_RecordingGpu gpu) =>
          gpu.bases.skip(1).map((base) => _baseDescribed(base.single));

      test('is cut along the long side of what is owed', () async {
        final gpu = _RecordingGpu();
        final store = FramePictureStore<String>(gpu: gpu);
        await _layed(store, 'a', 1024);
        store.patch(
          from: 'a',
          to: 'b',
          rect: const ui.Rect.fromLTWH(0, 0, 128, 1024),
          draw: fill,
        );
        await store.landingOf('b');
        expect(
          await pollUntil(() => gpu.levelWrites.length == parts.length),
          isTrue,
        );
        expect(paid(gpu), [
          for (var y = 0; y < 1024; y += 128) (0, 0, y, 128, 128),
        ]);
        store.dispose();
      });

      test('is cut in whole cells of the grid patches lie on', () async {
        Future<void> firstPartOf(ui.Rect owed, (int, int) size) async {
          final gpu = _RecordingGpu();
          final store = FramePictureStore<String>(gpu: gpu);
          await _layed(store, 'a', 1024);
          store.patch(from: 'a', to: 'b', rect: owed, draw: fill);
          await store.landingOf('b');
          expect(await pollUntil(() => gpu.levelWrites.isNotEmpty), isTrue);
          expect(paid(gpu).first, (0, 0, 0, size.$1, size.$2));
          store.dispose();
        }

        await firstPartOf(const ui.Rect.fromLTWH(0, 0, 1024, 120), (140, 120));
        await firstPartOf(const ui.Rect.fromLTWH(0, 0, 120, 1024), (120, 140));
      });

      test('takes a part what is owed fits in, at once', () async {
        final gpu = _RecordingGpu();
        final store = FramePictureStore<String>(gpu: gpu);
        await _layed(store, 'a', 1024);
        store.patch(
          from: 'a',
          to: 'b',
          rect: const ui.Rect.fromLTWH(32, 64, 128, 128),
          draw: fill,
        );
        await store.landingOf('b');
        expect(await pollUntil(() => gpu.levelWrites.isNotEmpty), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(paid(gpu), [(0, 32, 64, 128, 128)]);
        store.dispose();
      });

      test('is paid a part at a time once the patches pause, every part at '
          'every level', () async {
        final gpu = _RecordingGpu();
        final store = FramePictureStore<String>(gpu: gpu);
        final picture = await _layed(store, 'a', 1024);
        store.patch(from: 'a', to: 'b', rect: stroke, draw: fill);
        await store.landingOf('b');
        expect(
          await pollUntil(() => gpu.levelWrites.length == parts.length),
          isTrue,
        );
        expect(paid(gpu), parts);
        expect(
          gpu.levelWrites.map(levelsOf),
          everyElement(containsAll(everyLevel)),
        );
        expect(picture.readAt(_readsLevels), isTrue, reason: 'all paid');
        store.dispose();
      });

      test('tells no screen until the last, while none reads them: they '
          'change nothing a screen draws', () async {
        final gpu = _RecordingGpu();
        final store = FramePictureStore<String>(gpu: gpu);
        final picture = await _layed(store, 'a', 1024);
        store.patch(from: 'a', to: 'b', rect: stroke, draw: fill);
        await store.landingOf('b');
        var told = 0;
        picture.addListener(() => told += 1);
        expect(
          await pollUntil(() => gpu.levelWrites.length == parts.length),
          isTrue,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(told, 1, reason: 'the last part, and no other');
        store.dispose();
      });

      test('tells a screen every part, where one reads them', () async {
        final gpu = _RecordingGpu();
        final store = FramePictureStore<String>(gpu: gpu);
        final picture = await _layed(store, 'a', 1024);
        store.patch(from: 'a', to: 'b', rect: stroke, draw: fill);
        await store.landingOf('b');
        var told = 0;
        picture.addListener(() => told += 1);
        expect(picture.readAt(_readsLevels), isFalse);
        expect(
          await pollUntil(() => gpu.levelWrites.length == parts.length),
          isTrue,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(told, parts.length);
        store.dispose();
      });

      test('stops for a step, and the pause after it takes what is left',
          () async {
        final gpu = _RecordingGpu();
        final store = FramePictureStore<String>(gpu: gpu);
        await _layed(store, 'a', 1024);
        store.patch(from: 'a', to: 'b', rect: stroke, draw: fill);
        await store.landingOf('b');
        gpu.holdWrites = true;
        expect(await pollUntil(() => gpu.levelWrites.isNotEmpty), isTrue);
        store.patch(
          from: 'b',
          to: 'c',
          rect: const ui.Rect.fromLTWH(320, 32, 32, 32),
          draw: fill,
        );
        // The render of that step is done before the part it waits behind.
        await Future<void>.delayed(Duration.zero);
        gpu
          ..holdWrites = false
          ..releaseWrite();
        expect(await store.landingOf('c'), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(
          gpu.levelWrites,
          hasLength(1),
          reason: 'the step is in, the rest waits for its pause',
        );
        expect(
          await pollUntil(() => gpu.levelWrites.length == parts.length),
          isTrue,
        );
        store.dispose();
      });

      test('goes on through a step for a screen that waits for it', () async {
        final gpu = _RecordingGpu();
        final store = FramePictureStore<String>(gpu: gpu);
        final picture = await _layed(store, 'a', 1024);
        store.patch(from: 'a', to: 'b', rect: stroke, draw: fill);
        await store.landingOf('b');
        gpu.holdWrites = true;
        expect(picture.readAt(_readsLevels), isFalse);
        expect(await pollUntil(() => gpu.levelWrites.isNotEmpty), isTrue);
        store.patch(from: 'b', to: 'c', rect: spot, draw: fill);
        await Future<void>.delayed(Duration.zero);
        gpu
          ..holdWrites = false
          ..releaseWrite();
        expect(await store.landingOf('c'), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(
          gpu.levelWrites.length,
          greaterThan(parts.length),
          reason: 'its parts, and the step itself at every level',
        );
        expect(picture.readAt(_readsLevels), isTrue);
        store.dispose();
      });

      test('is all paid by the time the store has settled', () async {
        final gpu = _RecordingGpu();
        final store = FramePictureStore<String>(gpu: gpu);
        final picture = await _layed(store, 'a', 1024);
        store.patch(from: 'a', to: 'b', rect: stroke, draw: fill);
        await store.landingOf('b');
        await store.settled();
        expect(paid(gpu), parts);
        expect(picture.readAt(_readsLevels), isTrue);
        store.dispose();
      });
    });

    test('goes on waiting while a patch is on its way', () async {
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(gpu: gpu);
      await _layed(store, 'a', 1024);
      store.patch(from: 'a', to: 'b', rect: spot, draw: fill);
      await store.landingOf('b');
      gpu.holdRenders = true;
      store.patch(from: 'b', to: 'c', rect: spot, draw: fill);
      await Future<void>.delayed(pause);
      expect(gpu.levelWrites, isEmpty);
      gpu
        ..holdRenders = false
        ..releaseRender();
      expect(await store.landingOf('c'), isTrue);
      expect(await pollUntil(() => gpu.levelWrites.isNotEmpty), isTrue);
      store.dispose();
    });

    test('that a screen read is forgotten once the patches pause, with '
        'nothing owed to write: it says again with the next step it asks for',
        () async {
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(gpu: gpu);
      final picture = await _layed(store, 'a', 1024);
      picture.readAt(_readsLevels);
      store.patch(from: 'a', to: 'b', rect: spot, draw: fill);
      await store.landingOf('b');
      expect(levelsOf(gpu.levelWrites.single), everyLevel);
      await Future<void>.delayed(pause);
      expect(gpu.levelWrites, hasLength(1));

      store.patch(from: 'b', to: 'c', rect: spot, draw: fill);
      await store.landingOf('c');
      expect(gpu.levelWrites, hasLength(1));
      store.dispose();
    });

    test('is owed nothing by a move, which writes nothing', () async {
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(gpu: gpu);
      final picture = await _layed(store, 'a', 1024);
      expect(store.move(from: 'a', to: 'b'), isTrue);
      expect(await store.landingOf('b'), isTrue);
      expect(picture.readAt(_readsLevels), isTrue);
      await Future<void>.delayed(pause);
      expect(gpu.bases, isEmpty);
      store.dispose();
    });

    test('of a picture let go is never written', () async {
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(gpu: gpu);
      await _layed(store, 'a', 1024);
      store.patch(from: 'a', to: 'b', rect: spot, draw: fill);
      await store.landingOf('b');
      store.letGo('b');
      await Future<void>.delayed(pause);
      expect(gpu.levelWrites, isEmpty);
      store.dispose();
    });

    test('that the GPU did not write lets go of the picture', () async {
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(gpu: gpu);
      await _layed(store, 'a', 1024);
      store.patch(from: 'a', to: 'b', rect: spot, draw: fill);
      await store.landingOf('b');
      gpu.writesLand = false;
      expect(await pollUntil(() => store.peek('b') == null), isTrue);
      expect(gpu.levelWrites, hasLength(1));
      store.dispose();
    });

    test('that the GPU threw on lets go of the picture, and writes go on',
        () async {
      final reported = _reported();
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(gpu: gpu);
      await _layed(store, 'a', 1024);
      store.patch(from: 'a', to: 'b', rect: spot, draw: fill);
      await store.landingOf('b');
      gpu.writesThrow = StateError('the levels');
      expect(await pollUntil(() => store.peek('b') == null), isTrue);
      expect(reported, hasLength(1));
      store.dispose();
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

  // 🚨a-picture-lay-holds-the-raster-thread: a picture rastered at once was
  // one raster job the screen waited out — 2.2 s on the Surface Pro 11.
  group('a picture laid in pieces', () {
    // 1100 x 600 lies on 1152 x 640: three pieces across, two down, the
    // last of each what is left of it.
    const extent = ui.Rect.fromLTWH(0, 0, 1100, 600);
    const pieces = [
      (0, 0, 0, 512, 512),
      (0, 512, 0, 512, 512),
      (0, 1024, 0, 128, 512),
      (0, 0, 512, 512, 128),
      (0, 512, 512, 512, 128),
      (0, 1024, 512, 128, 128),
    ];

    test('is rastered a piece at a time into one texture made whole, every '
        'level of each written — its key answering once the last is in, '
        'none before', () async {
      final gpu = _RecordingGpu()
        ..allocates = true
        ..holdWrites = true;
      final store = FramePictureStore<String>(gpu: gpu, pieceSide: 512);
      FramePicture? laid;
      unawaited(store.lay('a', over(extent)).then((done) => laid = done));
      await pollUntil(() => gpu.bases.isNotEmpty);

      expect(gpu.allocated, [(1152, 640)]);
      // Then the write's own: the deepest level whole, and the halvings'
      // run.
      expect(gpu.rendered.take(pieces.length), [
        for (final (_, _, _, width, height) in pieces) (width, height),
      ]);
      expect(gpu.rendered, isNot(contains((1152, 640))));
      expect(gpu.bases.single.map(_baseDescribed), pieces);
      expect(
        [
          for (final span in gpu.levelWrites.single.spans)
            if (span.level == 1) _spanDescribed(span),
        ],
        [
          for (final (_, x, y, width, height) in pieces)
            (1, x ~/ 2, y ~/ 2, width ~/ 2, height ~/ 2),
        ],
        reason: 'each piece writes its own halvings',
      );
      expect(store.holds('a'), isFalse);
      expect(store.peek('a'), isNull);

      gpu.releaseWrite();
      await pollUntil(() => laid != null);
      expect(laid!.extent, const ui.Rect.fromLTWH(0, 0, 1152, 640));
      expect(store.peek('a'), same(laid));
      store.dispose();
    });

    test('goes a million texels a write', () async {
      final gpu = _RecordingGpu()..allocates = true;
      final store = FramePictureStore<String>(gpu: gpu, pieceSide: 512);
      await store.lay('a', over(const ui.Rect.fromLTWH(0, 0, 2048, 1024)));
      expect(
        [for (final base in gpu.bases) base.length],
        [4, 4],
        reason: 'eight pieces of 512 a side, four to a million',
      );
      store.dispose();
    });

    test('of one piece is its raster', () async {
      final gpu = _RecordingGpu()..allocates = true;
      final store = FramePictureStore<String>(gpu: gpu, pieceSide: 512);
      final picture = await store.lay(
        'a',
        over(const ui.Rect.fromLTWH(0, 0, 500, 300)),
      );
      expect(picture!.extent, const ui.Rect.fromLTWH(0, 0, 512, 384));
      expect(gpu.allocated, isEmpty);
      expect(gpu.rendered, [(512, 384)]);
      expect(gpu.bases, isEmpty);
      store.dispose();
    });

    test('in the app is laid at once up to 4096 a side, in pieces past it '
        '(framePictureSide)', () async {
      final gpu = _RecordingGpu()..allocates = true;
      final store = FramePictureStore<String>(gpu: gpu);
      await store.lay('a', over(const ui.Rect.fromLTWH(0, 0, 4096, 8)));
      expect(
        gpu.allocated,
        isEmpty,
        reason: '🚨in pieces, an S5 picture took twice as long to lay',
      );
      expect(gpu.rendered, [(4096, 128)]);

      await store.lay('b', over(const ui.Rect.fromLTWH(0, 0, 4097, 8)));
      expect(
        gpu.allocated,
        [(4224, 128)],
        reason: '🚨at once, a 3840² picture held the raster thread seconds',
      );
      store.dispose();
    });

    test('where no texture can be made is rastered at once', () async {
      final gpu = _RecordingGpu();
      final store = FramePictureStore<String>(gpu: gpu, pieceSide: 512);
      final picture = await store.lay('a', over(extent));
      expect(picture, isNotNull);
      expect(gpu.allocated, isEmpty);
      expect(gpu.rendered, [(1152, 640)]);
      store.dispose();
    });

    test('asked for again while it is laid is laid once', () async {
      final gpu = _RecordingGpu()
        ..allocates = true
        ..holdWrites = true;
      final store = FramePictureStore<String>(gpu: gpu, pieceSide: 512);
      final first = store.lay('a', over(extent));
      await pollUntil(() => gpu.bases.isNotEmpty);
      final again = store.lay('a', over(extent), shownNow: true);
      gpu.releaseWrite();
      expect(await again, same(await first));
      expect(gpu.allocated, hasLength(1));
      store.dispose();
    });

    test('whose write the GPU did not do is none — its key answers with '
        'nothing', () async {
      final gpu = _RecordingGpu()
        ..allocates = true
        ..writesLand = false;
      final store = FramePictureStore<String>(gpu: gpu, pieceSide: 512);
      expect(await store.lay('a', over(extent)), isNull);
      expect(store.holds('a'), isFalse);
      store.dispose();
    });

    test('whose store is disposed while it is written is none — nothing is '
        'held after the write', () async {
      final gpu = _RecordingGpu()
        ..allocates = true
        ..holdWrites = true;
      final store = FramePictureStore<String>(gpu: gpu, pieceSide: 512);
      final laid = store.lay('a', over(extent));
      await pollUntil(() => gpu.bases.isNotEmpty);
      store.dispose();
      expect(await laid, isNull);

      gpu.releaseWrite();
      await pumpEventQueue();
      expect(store.holds('a'), isFalse, reason: 'laid into a store let go');
    });

    test('whose piece threw rendering answers with the throw, and the next '
        'lay goes on', () async {
      final gpu = _RecordingGpu()..allocates = true;
      final store = FramePictureStore<String>(gpu: gpu, pieceSide: 512);
      var drawn = 0;
      final throwing = store.lay('a', (
        extent: extent,
        outside: white,
        draw: (canvas) {
          drawn += 1;
          gpu.rendersThrow = drawn == 2 ? StateError('a piece') : null;
          fill(canvas);
        },
      ));
      await expectLater(throwing, throwsStateError);
      expect(store.holds('a'), isFalse);
      gpu.rendersThrow = null;
      expect(await store.lay('b', over(extent)), isNotNull);
      store.dispose();
    });
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

/// A display scale at which a screen reads a picture's levels.
const double _readsLevels = 0.4;

/// What the store reports as it goes on ([FlutterError.onError]) from here
/// to the end of the test.
List<Object> _reported() {
  final reported = <Object>[];
  final was = FlutterError.onError;
  FlutterError.onError = (details) => reported.add(details.exception);
  addTearDown(() => FlutterError.onError = was);
  return reported;
}

/// Lets every held write go until the store has nothing left to write.
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

  /// What every write answers: whether the GPU did it.
  bool writesLand = true;

  /// What every write throws as it is asked, where anything.
  Error? writesThrow;

  /// What every render throws as it is asked, where anything.
  Error? rendersThrow;

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
      _heldWrites.removeAt(0).complete(writesLand);
    }
  }

  @override
  Future<ui.Image> render(ui.Picture picture, int width, int height) {
    if (rendersThrow case final thrown?) {
      throw thrown;
    }
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

  /// The texture behind [image], held as a handle of its own: the store
  /// lets go of the picture's image once a write gives it another.
  @override
  Object? hold(ui.Image image) => gpu ? image.clone() : null;

  /// Whether a texture can be made for a picture laid a piece at a time —
  /// its texels clear, a write taking none ([allocated]).
  bool allocates = false;

  /// The sizes of the textures made.
  final List<(int, int)> allocated = [];

  @override
  Object? allocate(int width, int height) {
    if (!gpu || !allocates) {
      return null;
    }
    allocated.add((width, height));
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    return image;
  }

  @override
  int levelsOf(Object held) {
    final image = held as ui.Image;
    return levels ?? math.max(image.width, image.height).bitLength;
  }

  @override
  ui.Image imageOf(Object held) => (held as ui.Image).clone();

  @override
  Future<bool> write(Object held, List<BaseWrite> base, LevelWrites? levels) {
    if (writesThrow case final thrown?) {
      throw thrown;
    }
    bases.add(base);
    if (levels case (:final run, :final spans)) {
      levelWrites.add((run: (run.width, run.height), spans: spans));
      runs.add(run.toByteData());
    }
    return _written();
  }

  Future<bool> _written() {
    if (!holdWrites) {
      return Future.value(writesLand);
    }
    final done = Completer<bool>();
    _heldWrites.add(done);
    return done.future;
  }
}
