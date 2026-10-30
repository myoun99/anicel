import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/rgba_image_bytes.dart';
import 'package:anicel/src/ui/playback/frame_picture_gpu.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:flutter/foundation.dart' show FlutterError;
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

    test('that render while a batch is written go in together, the base '
        'and the levels under it in one write', () async {
      final gpu = _RecordingGpu()..holdWrites = true;
      final store = FramePictureStore<String>(gpu: gpu);
      await _layed(store, 'a', 1024);
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
      await _layed(store, 'a', 1024);
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
        expect(await landing.timeout(_answered), isFalse, reason: 'not in');
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
        expect(await landing.timeout(_answered), isFalse, reason: 'not in');
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
      await _layed(store, 'a', 1024);
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

/// How long a patch may take to be answered before it never will be.
const _answered = Duration(seconds: 5);

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
