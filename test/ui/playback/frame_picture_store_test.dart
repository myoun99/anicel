import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:anicel/src/models/rgba_image_bytes.dart';
import 'package:anicel/src/ui/playback/frame_picture_gpu.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// The store's logic — keys, the patch grid, which levels a patch writes,
/// the order, the budget — on a GPU that only records what it is asked.
/// Whether the writes SHOW is `frame_picture_store_gpu_test.dart`'s, on a
/// runner with Impeller.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const red = ui.Color(0xFFFF0000);
  const white = ui.Color(0xFFFFFFFF);
  void fill(ui.Canvas canvas) => canvas.drawPaint(ui.Paint()..color = red);
  FrameDrawing over(ui.Rect extent) =>
      (extent: extent, outside: white, draw: fill);

  test('a picture is laid over its extent widened out to the patch grid '
      'of the world', () async {
    final gpu = _RecordingGpu();
    final store = FramePictureStore<String>(gpu: gpu);
    // 1001 x 300 halves twice to come under 256 a side: a grid of 4.
    final picture = await store.lay(
      'a',
      over(const ui.Rect.fromLTRB(0.5, 0.5, 1000.7, 300.5)),
    );
    expect(picture!.extent, const ui.Rect.fromLTWH(0, 0, 1004, 304));
    expect(picture.outside, white);
    expect(gpu.rendered, [(1004, 304)]);
    expect(store.peek('a'), same(picture));
    expect(store.peek('b'), isNull);
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
      expect(gpu.writes, hasLength(2));
      expect(gpu.writes.first.map(_described), [
        (0, 8, 20, 36, 8),
        (1, 4, 10, 18, 4),
        (2, 2, 5, 9, 2),
      ]);
      expect(gpu.writes.last.map(_described), [
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
      expect(gpu.writes, hasLength(1));
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
      gpu.releaseWrite();
      await pumpEventQueue();
      expect(picture.landing.map((p) => p.rect.topLeft), [
        ui.Offset.zero,
        const ui.Offset(100, 100),
      ], reason: 'the first one is in only once its deep levels are');
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
  });

  test('a lay waits its turn, the frame shown now before those asked ahead '
      'of it', () async {
    final gpu = _RecordingGpu()..holdRenders = true;
    final store = FramePictureStore<String>(gpu: gpu);
    final laid = <Future<FramePicture?>>[
      for (final (index, key) in ['a', 'b', 'c'].indexed)
        store.lay(key, over(ui.Rect.fromLTWH(0, 0, 8.0 + index, 8))),
      store.lay(
        'shown',
        over(const ui.Rect.fromLTWH(0, 0, 32, 8)),
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
    expect(gpu.rendered.map((size) => size.$1), [8, 32, 9, 10]);
    store.dispose();
  });

  test('the budget lets go of the picture wanted latest, never a pinned '
      'one, and counts each by the app\'s one image estimate', () async {
    final store = FramePictureStore<String>(gpu: _RecordingGpu());
    for (final key in ['soon', 'late', 'pinned']) {
      await _layed(store, key, 64);
    }
    final one = estimatedImageBytes(64, 64);
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

(int, int, int, int, int) _described(LevelWrite write) => (
  write.level,
  write.x,
  write.y,
  write.from.width.toInt(),
  write.from.height.toInt(),
);

class _RecordingGpu implements FramePictureGpu {
  _RecordingGpu({this.gpu = true, this.levels});

  /// Whether there is a GPU to write with.
  final bool gpu;

  /// The levels a held texture has; by default, a whole chain.
  final int? levels;

  bool holdRenders = false;
  bool holdWrites = false;

  final List<(int, int)> rendered = [];
  final List<List<LevelWrite>> writes = [];
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
  Future<bool> write(Object held, List<LevelWrite> writes) {
    this.writes.add(writes);
    if (!holdWrites) {
      return Future.value(true);
    }
    final done = Completer<bool>();
    _heldWrites.add(done);
    return done.future;
  }
}
