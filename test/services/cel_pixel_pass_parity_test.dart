import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/cel_pixel_overwrite.dart';
import 'package:anicel/src/services/cel_source_effect_pass.dart';

import '../helpers/native_engine_path.dart';

/// 🚨★★★THE C PASS AND THE DART PASS ARE ONE PASS (ABI 34).
///
/// `qa_cel_pixel_pass_tile` is a transcription of `overwriteCelPixels`'
/// per-pixel loop, and the Dart loop stays — it is the reference and the
/// no-engine path. Two transcriptions of one law only stay one law if
/// something compares them, byte for byte, over every axis the law has:
/// the channel, the mask's coverage, the colour selector, and BOTH
/// directions — the forward pass builds a recipe and the undo reads one,
/// and they share the participation walk that makes the recipe line up.
///
/// ⚠️The native route asserts the engine actually LOADED. A path that
/// exists but fails to load would quietly run the Dart loop twice, and two
/// identical routes agreeing is the shape of a green that measures nothing
/// — the lesson the dab parity suite already paid for.
void main() {
  const tileSize = defaultCelTileSize;
  const canvas = CanvasSize(width: 256, height: 256);
  final libraryPath = nativeEngineLibraryPathOrNull();

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

  /// Two tiles of mixed artwork: several colours, some fully transparent
  /// pixels, partial alphas, and a repeating stretch — so every recipe
  /// shape and every participation arm is reachable.
  BitmapSurface artwork() {
    BitmapTile tileAt(int seed) {
      final bytes = Uint8List(tileSize * tileSize * 4);
      for (var i = 0; i < tileSize * tileSize; i += 1) {
        final o = i * 4;
        final band = (i ~/ 97 + seed) % 6;
        switch (band) {
          case 0: // empty
            break;
          case 1: // flat black line art
            bytes[o + 3] = 255;
          case 2: // the colour the selector names
            bytes[o] = 200;
            bytes[o + 1] = 40;
            bytes[o + 2] = 10;
            bytes[o + 3] = 255;
          case 3: // near that colour, outside tolerance 0
            bytes[o] = 201;
            bytes[o + 1] = 40;
            bytes[o + 2] = 10;
            bytes[o + 3] = 180;
          case 4: // translucent grey
            bytes[o] = 90;
            bytes[o + 1] = 90;
            bytes[o + 2] = 90;
            bytes[o + 3] = (i * 7 + seed) % 256;
          default: // noise
            bytes[o] = (i * 31 + seed) % 256;
            bytes[o + 1] = (i * 17) % 256;
            bytes[o + 2] = (i * 13 + 5) % 256;
            bytes[o + 3] = 255;
        }
      }
      return BitmapTile(size: tileSize, pixels: bytes);
    }

    return BitmapSurface(
      canvasSize: canvas,
      tileSize: tileSize,
      tiles: {
        TileCoord(x: 0, y: 0): tileAt(0),
        TileCoord(x: 1, y: 0): tileAt(3),
      },
    );
  }

  /// A soft mask with zeros, partial coverage and full coverage.
  Uint8List softMask() {
    final mask = Uint8List(tileSize * tileSize);
    for (var i = 0; i < mask.length; i += 1) {
      mask[i] = switch (i % 5) {
        0 => 0,
        1 => 255,
        _ => (i * 37) % 256,
      };
    }
    return mask;
  }

  CelPixelWalk walkOver(BitmapSurface surface, Uint8List? mask) =>
      (visit) {
        for (final coord in surface.tiles.keys) {
          visit(coord, mask);
        }
      };

  List<int> bytesOf(BitmapSurface surface) => [
    for (final coord in surface.tiles.keys.toList()
      ..sort((a, b) => a.x != b.x ? a.x - b.x : a.y - b.y))
      ...surface.tileAt(coord)!.readPixels((_, view) => List<int>.of(view)),
  ];

  List<int> recipeBytes(CelPixelRestore? restore, int byteCount) {
    if (restore == null) {
      return const [];
    }
    final one = Uint8List(byteCount);
    return [
      restore.touchedPixelCount,
      for (var i = 0; i < restore.touchedPixelCount; i += 1) ...[
        ...(() {
          restore.readInto(one, i);
          return List<int>.of(one);
        })(),
      ],
    ];
  }

  ({List<int> forward, List<int> recipe, List<int> undone}) run({
    required bool native,
    required CelPixelChannel channel,
    required Uint8List? mask,
    required CelColorKey? selector,
  }) {
    QaNativeEngine.debugResetForTests();
    QaNativeEngine.debugForceDartFallback = !native;
    debugQaEngineLibraryPathOverride = native ? libraryPath : null;
    if (native) {
      expect(
        QaNativeEngine.instance,
        isNotNull,
        reason: 'the native route must really load, or this compares the '
            'Dart loop with itself',
      );
    } else {
      expect(QaNativeEngine.instance, isNull);
    }
    final surface = artwork();
    final value = Uint8List.fromList(
      channel == CelPixelChannel.colour ? [12, 140, 230] : [0],
    );
    final forward = overwriteCelPixels(
      surface: surface,
      channel: channel,
      walk: walkOver(surface, mask),
      value: value,
      selector: selector,
    );
    final undone = forward.restore == null
        ? forward.surface
        : overwriteCelPixels(
            surface: forward.surface,
            channel: channel,
            walk: walkOver(forward.surface, mask),
            restore: forward.restore,
            selector: selector,
          ).surface;
    return (
      forward: bytesOf(forward.surface),
      recipe: recipeBytes(forward.restore, channel.byteCount),
      undone: bytesOf(undone),
    );
  }

  final selectorNamesTheColour = CelPixelVerb.deleteColour.selectorFor(
    0xFFC8280A, // (200, 40, 10)
  );
  final selectorKeepsTheColour = CelPixelVerb.keepColour.selectorFor(
    0xFFC8280A,
  );
  // The button's selector is tolerance 0 by design, and 0 cannot tell a
  // per-channel box from any other distance — so the kernel's reading of
  // the tolerance the key ADMITS is pinned with a key the button never makes.
  final selectorNearTheColour = CelColorKey(
    red: 200,
    green: 40,
    blue: 10,
    tolerance: 3,
    amount: 1,
    keepsMatches: false,
  );

  final cases =
      <({String name, CelPixelChannel channel, bool masked, CelColorKey? key})>[
        (name: '색 변환, full', channel: CelPixelChannel.colour, masked: false, key: null),
        (name: '색 변환, soft mask', channel: CelPixelChannel.colour, masked: true, key: null),
        (name: '픽셀 비우기, full', channel: CelPixelChannel.alpha, masked: false, key: null),
        (name: '픽셀 비우기, soft mask', channel: CelPixelChannel.alpha, masked: true, key: null),
        (name: '색 삭제', channel: CelPixelChannel.alpha, masked: false, key: selectorNamesTheColour),
        (name: '색 삭제, soft mask', channel: CelPixelChannel.alpha, masked: true, key: selectorNamesTheColour),
        (name: '색 남기기', channel: CelPixelChannel.alpha, masked: false, key: selectorKeepsTheColour),
        (name: '색 삭제, tolerance 3', channel: CelPixelChannel.alpha, masked: true, key: selectorNearTheColour),
      ];

  test('🚨a recipe SHORTER than its walk is refused by both passes — the C '
      'one must not read past the stream', () {
    if (libraryPath == null) {
      if (nativeEngineRequired) {
        fail(nativeEngineMissingSkipReason);
      }
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }
    for (final native in [false, true]) {
      QaNativeEngine.debugResetForTests();
      QaNativeEngine.debugForceDartFallback = !native;
      debugQaEngineLibraryPathOverride = native ? libraryPath : null;
      expect(QaNativeEngine.instance, native ? isNotNull : isNull);
      final surface = artwork();
      expect(
        () => overwriteCelPixels(
          surface: surface,
          channel: CelPixelChannel.alpha,
          walk: walkOver(surface, null),
          // Five pixels' worth, over a walk that takes every pixel of two
          // tiles: the undo reaches index 5 on its sixth pixel.
          restore: UniformCelPixelRestore(
            Uint8List(1),
            touchedPixelCount: 5,
          ),
        ),
        throwsStateError,
        reason: native ? 'the C pass' : 'the Dart pass',
      );
    }
  });

  for (final c in cases) {
    test('🚨${c.name}: the C pass is the Dart pass, both directions', () {
      if (libraryPath == null) {
        if (nativeEngineRequired) {
          fail(nativeEngineMissingSkipReason);
        }
        markTestSkipped(nativeEngineMissingSkipReason);
        return;
      }
      final mask = c.masked ? softMask() : null;
      final reference = run(
        native: false,
        channel: c.channel,
        mask: mask,
        selector: c.key,
      );
      final native = run(
        native: true,
        channel: c.channel,
        mask: mask,
        selector: c.key,
      );
      expect(
        reference.recipe,
        isNotEmpty,
        reason: 'fixture premise: the pass touched something',
      );
      expect(native.forward, reference.forward, reason: 'forward pixels');
      expect(native.recipe, reference.recipe, reason: 'the undo recipe');
      expect(native.undone, reference.undone, reason: 'the undone pixels');
      expect(
        native.undone,
        bytesOf(artwork()),
        reason: 'and undo is exact — the recipe puts back what was there',
      );
    });
  }
}
