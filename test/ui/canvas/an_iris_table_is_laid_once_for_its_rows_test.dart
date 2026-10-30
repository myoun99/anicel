@Tags(['impeller'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/shaded_passes.dart';
import 'package:anicel/src/ui/canvas/iris_blur_shader.dart';
import 'package:anicel/src/ui/canvas/raster_picture.dart';

import '../../helpers/census_where_textures_are_ram.dart';

/// A camera lens blur's table of its iris's rows is its [IrisRows] alone,
/// and every gather laid its own — a stroke's every patch, a playback's
/// every frame (🔬Surface Pro 11, 2026-10-31: 1.2ms a table at a radius of
/// 150, 11–14ms at 1500). The table last laid is kept for the next gather
/// of the same rows, one at a time, and counted where the memory census
/// reads it ([IrisBlurShader.tableBytes]).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(IrisBlurShader.load);

  const width = 24;
  const height = 12;

  const shape = (
    sides: 6,
    roundness: 0.3,
    aspect: 1.2,
    rotation: 0.2,
    fringe: 0.0,
  );

  IrisGatherPass passOf({
    double radius = 8,
    IrisProperties iris = shape,
    IrisMap? map,
    Rect? paper,
    LensLight? light,
  }) => IrisGatherPass(
    radius: radius,
    iris: iris,
    paper: paper,
    light: light,
    map: map,
  );

  Future<ui.Image> imageOf(WidgetTester tester) async {
    final rgba = Uint8List(width * height * 4);
    for (var i = 0; i < width * height; i += 1) {
      rgba
        ..[i * 4] = (i * 37) % 256
        ..[i * 4 + 1] = (i * 91) % 256
        ..[i * 4 + 2] = (i * 13) % 256
        ..[i * 4 + 3] = 255;
    }
    final image = (await tester.runAsync(() async {
      final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      return (await codec.getNextFrame()).image;
    }))!;
    addTearDown(image.dispose);
    return image;
  }

  /// [pass] gathered over [source] — the source standing in for its sums,
  /// and for its map where it reads one: what it draws, read back.
  Future<Uint8List> gathered(
    WidgetTester tester,
    ui.Image source,
    IrisGatherPass pass,
  ) async {
    final shader = IrisBlurShader.gatherFor(
      sums: source,
      input: source,
      pass: pass,
      map: pass.map == null ? null : source,
    );
    final drawn = shadedRaster(shader, width, height);
    shader.dispose();
    addTearDown(drawn.dispose);
    return (await tester.runAsync(
      () => drawn.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!.buffer.asUint8List();
  }

  testWidgets('a gather of the rows the last laid reads the table kept — '
      'its fringe, paper, light and the map\'s channel are the gather\'s, '
      'not the table\'s', (tester) async {
    final source = await imageOf(tester);
    const map = (
      channel: IrisMapChannel.luminance,
      focal: 128.0,
      inverts: false,
    );
    for (final (first, again) in [
      (passOf(), passOf()),
      (
        passOf(),
        passOf(
          iris: (
            sides: shape.sides,
            roundness: shape.roundness,
            aspect: shape.aspect,
            rotation: shape.rotation,
            fringe: 200,
          ),
          paper: const Rect.fromLTWH(2, 1, 20, 10),
          light: (gain: 2, threshold: 0.5, saturation: 0.3, linear: true),
        ),
      ),
      (
        passOf(map: map),
        passOf(map: (channel: IrisMapChannel.red, focal: 128, inverts: false)),
      ),
    ]) {
      await gathered(tester, source, first);
      final kept = IrisBlurShader.debugKeptTable!;
      await gathered(tester, source, again);
      expect(
        IrisBlurShader.debugKeptTable,
        same(kept),
        reason: '$again reads the rows $first laid',
      );
      expect(kept.debugDisposed, isFalse);
    }
  });

  testWidgets('a gather of other rows lays its own and lets go of the one '
      'kept — and draws as a gather of them with none kept before', (
    tester,
  ) async {
    final source = await imageOf(tester);
    const map = (
      channel: IrisMapChannel.luminance,
      focal: 128.0,
      inverts: false,
    );
    IrisProperties turned({
      int sides = 6,
      double roundness = 0.3,
      double aspect = 1.2,
      double rotation = 0.2,
    }) => (
      sides: sides,
      roundness: roundness,
      aspect: aspect,
      rotation: rotation,
      fringe: 0,
    );
    final base = passOf(map: map);
    for (final other in [
      passOf(radius: 5, map: map),
      passOf(iris: turned(sides: 4), map: map),
      passOf(iris: turned(roundness: 0.8), map: map),
      passOf(iris: turned(aspect: 0.6), map: map),
      passOf(iris: turned(rotation: 1.1), map: map),
      passOf(map: (channel: map.channel, focal: 40, inverts: false)),
      passOf(map: (channel: map.channel, focal: 128, inverts: true)),
      passOf(),
    ]) {
      final alone = await gathered(tester, source, other);
      // The two draw apart: a table of the wrong rows shows.
      expect(await gathered(tester, source, base), isNot(alone));
      final kept = IrisBlurShader.debugKeptTable!;
      expect(
        await gathered(tester, source, other),
        alone,
        reason: '$other drawn after $base was kept',
      );
      expect(IrisBlurShader.debugKeptTable, isNot(same(kept)));
      expect(kept.debugDisposed, isTrue, reason: 'one table kept at a time');
    }
  });

  testWidgets('what the table kept weighs — a float a channel — is the '
      'memory census\'s', (tester) async {
    final source = await imageOf(tester);
    await gathered(tester, source, passOf());
    final kept = IrisBlurShader.debugKeptTable!;
    // Radius 8, no map: 17 rows two texels each, a line of them and a line
    // of the level's head.
    expect((kept.width, kept.height), (34, 2));
    expect(IrisBlurShader.tableBytes, 34 * 2 * 16);
    expect(
      collectMemoryCensusWhereTexturesAreRam(const []).items
          .singleWhere((item) => item.id == 'lensBlurTables')
          .bytes,
      IrisBlurShader.tableBytes,
    );
  });
}
