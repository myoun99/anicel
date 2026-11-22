import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/screen_texture.dart';

/// H66 · H67 (유저 2026-11-22, a Galaxy Tab out of this machine's reach,
/// card the-galaxy-tab-canvas-went-slow-on-build-1095): a frame's time was
/// one number there, and nothing said whose it was. A timed engine tells
/// how long each place of it took — the bodies on its thread, and each
/// submit on the GPU, waited out where it is made (rust/src/took.rs pins
/// how) — and a screen tells it frame by frame while anyone asks. Here,
/// what Dart reads of it, on an engine of the test's own.
void main() {
  late GpuEngine engine;
  late GpuPool pool;
  late Pointer<Uint8> tile;

  setUp(() {
    engine = GpuEngine.onFirstAdapter();
    pool = GpuPool(engine, 1 << 30);
    tile = calloc<Uint8>(gpuTileBytes);
  });
  tearDown(() {
    ScreenTexture.tookAsItWentUp = null;
    calloc.free(tile);
    pool.free();
    engine.close();
  });

  /// Work of the engine's: a body on its thread that submits.
  void stores() => pool.store(pool.cel(), [tile], (tile) => tile);

  test('what the engine tells is read a line a place, whose time it is '
      'and each figure in its place — and a line cut short is none', () {
    final took = GpuEngine.placesTook(
      'cpu src\\platform\\android.rs:334 times=3 micros=4100 longest=2500 '
      'groups=0\n'
      'gpu src/kernels/composite/screen.rs:412 times=2 micros=28000 '
      'longest=16000 groups=18000\n'
      'gpu src/device.rs:1040 times=1 mic',
    );

    expect(took, [
      (
        gpu: false,
        place: r'src\platform\android.rs:334',
        times: 3,
        micros: 4100,
        longest: 2500,
        groups: 0,
      ),
      (
        gpu: true,
        place: 'src/kernels/composite/screen.rs:412',
        times: 2,
        micros: 28000,
        longest: 16000,
        groups: 18000,
      ),
    ]);
    expect(GpuEngine.placesTook(''), isEmpty);
  });

  test('a timed engine tells the places that took anything, its bodies\' '
      'and its submits\', once — and an untimed one tells none', () async {
    stores();
    await engine.done();
    expect(engine.took(), isEmpty, reason: 'untimed till asked');

    engine.timesItsPlaces(true);
    stores();
    await engine.done();
    final took = engine.took();

    expect(took.where((place) => place.gpu), isNotEmpty, reason: '$took');
    expect(took.where((place) => !place.gpu), isNotEmpty, reason: '$took');
    for (final place in took) {
      expect(place.place, matches(RegExp(r'\.rs:\d+$')));
      expect(place.times, greaterThan(0), reason: '$place');
      expect(place.longest, lessThanOrEqualTo(place.micros), reason: '$place');
    }
    expect(engine.took(), isEmpty, reason: 'told once, taken');

    engine.timesItsPlaces(false);
    stores();
    await engine.done();
    expect(engine.took(), isEmpty, reason: 'untimed again');
  });

  test('a screen tells what its engine\'s places took of each frame as it '
      'goes up, while anyone asks — and its engine is timed no longer once '
      'no one does', () async {
    final surface = ScreenTexture.surfaceOf(engine, 4, 4);
    final screen = ScreenTexture.debugOnSurface(
      surface,
      done: engine.done,
      engine: engine,
    );
    addTearDown(() async {
      await screen.free();
      surface.free();
    });
    var ups = Completer<void>();
    screen.putUp = ({required behind}) => ups.complete();
    Future<void> aFrame() async {
      ups = Completer<void>();
      screen.present((_) => stores());
      await ups.future;
    }

    final told = <(ScreenUp, List<GpuPlaceTook>)>[];
    ScreenTexture.tookAsItWentUp = (up, took) => told.add((up, took));

    await aFrame();

    expect(told, hasLength(1));
    final (up, took) = told.single;
    expect(up, ScreenTexture.upMicros.last, reason: 'the frame that went up');
    expect(took.where((place) => place.gpu), isNotEmpty, reason: '$took');
    expect(took.where((place) => !place.gpu), isNotEmpty, reason: '$took');

    ScreenTexture.tookAsItWentUp = null;
    await aFrame();

    expect(told, hasLength(1), reason: 'nobody asks');
    engine.took();
    stores();
    await engine.done();
    expect(
      engine.took(),
      isEmpty,
      reason: 'the frame drawn with nobody asking left the engine untimed',
    );
  });

  test('a screen with no engine named draws as it did, anyone asking or '
      'not', () async {
    final surface = ScreenTexture.surfaceOf(engine, 4, 4);
    final screen = ScreenTexture.debugOnSurface(surface, done: engine.done);
    addTearDown(() async {
      await screen.free();
      surface.free();
    });
    final up = Completer<void>();
    screen.putUp = ({required behind}) => up.complete();
    final told = <List<GpuPlaceTook>>[];
    ScreenTexture.tookAsItWentUp = (_, took) => told.add(took);

    screen.present((_) => stores());
    await up.future;

    expect(told, isEmpty);
    expect(screen.showsAFrame, isTrue);
  });
}
