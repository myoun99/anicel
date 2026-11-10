// The first pass compiles the verbs' kernels and the pool's: tens of seconds
// on a machine this busy.
@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/services/cel_pixel_overwrite.dart';
import 'package:anicel/src/services/cel_source_effect_pass.dart';

/// 색 편집's verbs ON THE ENGINE (flip lane ⓒ): on the app's grid the pass is
/// the kernel's (rust/src/kernels/cel_pixel), over the tiles where the pool
/// has them — what it leaves, what undoes it and what the undo gives back
/// held byte for byte to the Dart pass, over every axis the law has.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const side = 128;
  const canvas = CanvasSize(width: 512, height: 512);
  final ledger = EngineTileLedger.instance;

  tearDown(() => debugCelPixelsInDart = false);

  /// Mixed artwork: empty, flat, the colour a selector names, near that
  /// colour, translucent, noise — every recipe shape and every arm.
  BitmapTile tileOf(int seed) {
    final bytes = Uint8List(side * side * 4);
    for (var i = 0; i < side * side; i += 1) {
      final o = i * 4;
      switch ((i ~/ 97 + seed) % 6) {
        case 0:
          break;
        case 1:
          bytes[o + 3] = 255;
        case 2:
          bytes
            ..[o] = 200
            ..[o + 1] = 40
            ..[o + 2] = 10
            ..[o + 3] = 255;
        case 3:
          bytes
            ..[o] = 201
            ..[o + 1] = 40
            ..[o + 2] = 10
            ..[o + 3] = 180;
        case 4:
          bytes
            ..[o] = 90
            ..[o + 1] = 90
            ..[o + 2] = 90
            ..[o + 3] = (i * 7 + seed) % 256;
        default:
          bytes
            ..[o] = (i * 31 + seed) % 256
            ..[o + 1] = (i * 17) % 256
            ..[o + 2] = (i * 13 + 5) % 256
            ..[o + 3] = 255;
      }
    }
    return BitmapTile(size: side, pixels: bytes);
  }

  BitmapSurface surfaceOf(Map<TileCoord, BitmapTile> tiles) =>
      BitmapSurface(canvasSize: canvas, tileSize: side, tiles: tiles);

  final origin = TileCoord(x: 0, y: 0);
  final beside = TileCoord(x: 1, y: 0);
  // Off the top-left of the canvas and a row down, with gaps in the box: a
  // cel's tiles are not a rectangle, and the pasteboard is drawing.
  final offStage = TileCoord(x: -2, y: 1);

  BitmapSurface artwork() => surfaceOf({
    origin: tileOf(0),
    beside: tileOf(3),
    offStage: tileOf(1),
  });

  Uint8List softMask() {
    final mask = Uint8List(side * side);
    for (var i = 0; i < mask.length; i += 1) {
      mask[i] = switch (i % 5) {
        0 => 0,
        1 => 255,
        _ => (i * 37) % 256,
      };
    }
    return mask;
  }

  /// The order the app walks them in ([celPixelWalkFor]).
  CelPixelWalk walkOf(Map<TileCoord, Uint8List?> masks) => (visit) {
    final coords = masks.keys.toList()
      ..sort((a, b) => a.y != b.y ? a.y - b.y : a.x - b.x);
    for (final coord in coords) {
      visit(coord, masks[coord]);
    }
  };

  Map<TileCoord, List<int>> bytesOf(BitmapSurface surface) => {
    for (final entry in surface.tiles.entries)
      entry.key: entry.value.readPixels((_, view) => List<int>.of(view)),
  };

  List<int>? recipeOf(CelPixelRestore? restore, int byteCount) => restore == null
      ? null
      : [restore.touchedPixelCount, ...restore.expand(byteCount)];

  ({
    Map<TileCoord, List<int>> forward,
    List<int>? recipe,
    Map<TileCoord, List<int>> undone,
  })
  run({
    required bool onEngine,
    required BitmapSurface surface,
    required CelPixelChannel channel,
    required Uint8List value,
    required CelPixelWalk walk,
    CelColorKey? selector,
    int threshold = 0,
  }) {
    debugCelPixelsInDart = !onEngine;
    final forward = overwriteCelPixels(
      surface: surface,
      channel: channel,
      walk: walk,
      value: value,
      selector: selector,
      threshold: threshold,
    );
    for (final entry in forward.surface.tiles.entries) {
      if (!identical(entry.value, surface.tileAt(entry.key))) {
        expect(
          entry.value.isOnEngine,
          onEngine,
          reason: 'or this compares a pass with itself',
        );
      }
    }
    final undone = forward.restore == null
        ? forward.surface
        : overwriteCelPixels(
            surface: forward.surface,
            channel: channel,
            walk: walk,
            restore: forward.restore,
            selector: selector,
          ).surface;
    return (
      forward: bytesOf(forward.surface),
      recipe: recipeOf(forward.restore, channel.byteCount),
      undone: bytesOf(undone),
    );
  }

  Uint8List bytes(List<int> values) => Uint8List.fromList(values);

  final colour = (
    channel: CelPixelChannel.colour,
    value: bytes([12, 140, 230]),
  );
  final empties = (channel: CelPixelChannel.alpha, value: bytes([0]));
  final hardens = (channel: CelPixelChannel.alpha, value: bytes([255]));

  final verbs = <String, _Verb>{
    '색 변환': (of: colour, selector: null, threshold: 0),
    '픽셀 비우기': (of: empties, selector: null, threshold: 0),
    '2치화 128': (of: hardens, selector: null, threshold: 128),
    '2치화 1': (of: hardens, selector: null, threshold: 1),
    '2치화 255': (of: hardens, selector: null, threshold: 255),
    '색 삭제': (
      of: empties,
      selector: CelPixelVerb.deleteColour.selectorFor(0xFFC8280A, tolerance: 0),
      threshold: 0,
    ),
    '색 삭제, 허용차 3': (
      of: empties,
      selector: CelPixelVerb.deleteColour.selectorFor(0xFFC8280A, tolerance: 3),
      threshold: 0,
    ),
    '색 유지': (
      of: empties,
      selector: CelPixelVerb.keepColour.selectorFor(0xFFC8280A, tolerance: 0),
      threshold: 0,
    ),
    '색 유지, 허용차 3': (
      of: empties,
      selector: CelPixelVerb.keepColour.selectorFor(0xFFC8280A, tolerance: 3),
      threshold: 0,
    ),
  };

  final soft = softMask();
  final regions = <String, Map<TileCoord, Uint8List?>>{
    'every tile whole': {origin: null, beside: null, offStage: null},
    'a soft mask on each': {origin: soft, beside: soft, offStage: soft},
    'one tile whole, the others masked': {
      origin: soft,
      beside: null,
      offStage: soft,
    },
    'one tile of them walked': {beside: soft},
    'one off the top-left, none of them at 0': {offStage: soft},
    'two a gap apart': {offStage: null, beside: soft},
  };

  // First here: every pass after it leaves pages a landing could find room
  // on.
  test('🚨a pool that fills in the middle of a landing goes on from the tile '
      'it stopped at, the pass not run again', () {
    final before = EngineTileLedger.appByteBudget;
    addTearDown(() => EngineTileLedger.appByteBudget = before);
    // Past what a page holds (128 MB, 2048 tiles), the same few tiles over
    // and over: this test's CPU copies stay small.
    const across = 46;
    final kinds = [
      for (var kind = 0; kind < 251; kind += 1)
        BitmapTile(
          size: side,
          pixels: Uint8List(side * side * 4)
            ..fillRange(0, side * side * 4, kind + 1),
        ),
    ];
    final tiles = <TileCoord, BitmapTile>{
      for (var at = 0; at < across * across; at += 1)
        TileCoord(x: at % across, y: at ~/ across): kinds[at % kinds.length],
    };
    final surface = BitmapSurface(
      canvasSize: const CanvasSize(width: side * across, height: side * across),
      tileSize: side,
      tiles: tiles,
    );
    // The landing's page made, a slot of it used.
    final first = overwriteCelPixels(
      surface: surfaceOf({origin: tileOf(0)}),
      channel: CelPixelChannel.alpha,
      walk: walkOf({origin: null}),
      value: bytes([255]),
    );
    expect(first.restore, isNotNull);
    EngineTileLedger.appByteBudget = ledger.pool.bytes;
    final made = overwriteCelPixels(
      surface: surface,
      channel: CelPixelChannel.alpha,
      walk: walkOf({for (final coord in tiles.keys) coord: null}),
      value: bytes([77]),
    );
    expect(
      ledger.pool.bytes,
      greaterThan(EngineTileLedger.appByteBudget!),
      reason: 'the landing has to have run out of room',
    );
    final coords = tiles.keys.toList();
    final left = [for (final coord in coords) made.surface.tileAt(coord)!];
    var next = 0;
    ledger.readEach(BrushFrameKey.noCel, left, (read) {
      final fill = coords[next].y * across + coords[next].x;
      expect(
        read.sublist(0, 4),
        [fill % 251 + 1, fill % 251 + 1, fill % 251 + 1, 77],
        reason: 'tile $next',
      );
      next += 1;
    });
    expect(next, across * across);
  });

  group('every verb over every region, as the Dart pass:', () {
    for (final MapEntry(key: verb, value: spec) in verbs.entries) {
      for (final MapEntry(key: region, value: masks) in regions.entries) {
        test('$verb, $region', () {
          final surface = artwork();
          final walk = walkOf(masks);
          final (:channel, :value) = spec.of;
          final (forward: inDart, recipe: inDartRecipe, undone: _) = run(
            onEngine: false,
            surface: surface,
            channel: channel,
            value: value,
            walk: walk,
            selector: spec.selector,
            threshold: spec.threshold,
          );
          final (:forward, :recipe, :undone) = run(
            onEngine: true,
            surface: surface,
            channel: channel,
            value: value,
            walk: walk,
            selector: spec.selector,
            threshold: spec.threshold,
          );
          expect(forward, inDart, reason: 'what the pass left');
          expect(recipe, inDartRecipe, reason: 'what undoes it');
          expect(undone, bytesOf(surface), reason: 'what the undo gives back');
        });
      }
    }
  });

  test('what a pass leaves is the engine\'s, its bytes not on this side', () {
    final surface = artwork();
    final result = overwriteCelPixels(
      surface: surface,
      channel: CelPixelChannel.alpha,
      walk: walkOf({origin: null}),
      value: bytes([0]),
    );
    expect(result.surface.tileAt(origin)!.isOnEngine, isTrue);
  });

  test('🚨a walk hands one buffer over from tile to tile, as the app\'s does: '
      'each tile keeps the coverage it was walked with', () {
    final surface = artwork();
    final coverage = Uint8List(side * side);
    final result = overwriteCelPixels(
      surface: surface,
      channel: CelPixelChannel.alpha,
      walk: (visit) {
        coverage.fillRange(0, coverage.length, 255);
        visit(offStage, coverage);
        coverage.fillRange(0, coverage.length, 0);
        visit(beside, coverage);
      },
      value: bytes([0]),
    );
    expect(identical(result.surface.tileAt(beside), surface.tileAt(beside)), isTrue);
    expect(identical(result.surface.tileAt(offStage), surface.tileAt(offStage)), isFalse);
  });

  test('a tile no pixel of took part in stays the very tile, and one the '
      'walk did not go to', () {
    final surface = artwork();
    final result = overwriteCelPixels(
      surface: surface,
      channel: CelPixelChannel.alpha,
      walk: walkOf({
        origin: Uint8List(side * side),
        beside: soft,
      }),
      value: bytes([0]),
    );
    expect(identical(result.surface.tileAt(origin), surface.tileAt(origin)), isTrue);
    expect(identical(result.surface.tileAt(offStage), surface.tileAt(offStage)), isTrue);
    expect(identical(result.surface.tileAt(beside), surface.tileAt(beside)), isFalse);
  });

  test('nothing taking part hands back the very surface and no recipe', () {
    final surface = artwork();
    final missed = overwriteCelPixels(
      surface: surface,
      channel: CelPixelChannel.alpha,
      walk: walkOf({origin: Uint8List(side * side)}),
      value: bytes([0]),
    );
    expect(identical(missed.surface, surface), isTrue);
    expect(missed.restore, isNull);
    final none = overwriteCelPixels(
      surface: surface,
      channel: CelPixelChannel.alpha,
      walk: (visit) {},
      value: bytes([0]),
    );
    expect(identical(none.surface, surface), isTrue);
    expect(none.restore, isNull);
  });

  test('a coordinate walked with no tile stays without one', () {
    final surface = artwork();
    final at = TileCoord(x: 5, y: 5);
    final result = overwriteCelPixels(
      surface: surface,
      channel: CelPixelChannel.alpha,
      walk: walkOf({origin: null, at: null}),
      value: bytes([0]),
    );
    expect(result.surface.tileAt(at), isNull);
    expect(result.restore, isNotNull);
  });

  test('🚨emptied whole, a tile keeps its colour under no alpha — what the '
      'undo reads a selector against', () {
    final black = Uint8List(side * side * 4);
    for (var i = 0; i < side * side; i += 1) {
      black
        ..[i * 4] = 200
        ..[i * 4 + 1] = 40
        ..[i * 4 + 2] = 10
        ..[i * 4 + 3] = 255;
    }
    final surface = surfaceOf({origin: BitmapTile(size: side, pixels: black)});
    final selector = CelPixelVerb.deleteColour.selectorFor(
      0xFFC8280A,
      tolerance: 0,
    );
    final walk = walkOf({origin: null});
    final forward = overwriteCelPixels(
      surface: surface,
      channel: CelPixelChannel.alpha,
      walk: walk,
      value: bytes([0]),
      selector: selector,
    );
    final left = forward.surface.tileAt(origin);
    expect(left, isNotNull, reason: 'a tile emptied is not a tile gone');
    expect(
      left!.readPixels((_, view) => view.sublist(0, 4)),
      [200, 40, 10, 0],
    );
    final undone = overwriteCelPixels(
      surface: forward.surface,
      channel: CelPixelChannel.alpha,
      walk: walk,
      restore: forward.restore,
      selector: selector,
    );
    expect(bytesOf(undone.surface), bytesOf(surface));
  });

  test('a recipe shorter than its walk is refused, nothing written', () {
    final surface = artwork();
    expect(
      () => overwriteCelPixels(
        surface: surface,
        channel: CelPixelChannel.alpha,
        walk: walkOf({origin: null}),
        restore: UniformCelPixelRestore(bytes([9]), touchedPixelCount: 3),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('the walk it replays goes past them'),
        ),
      ),
    );
  });

  test('a pass over what a pass left reads none of it back', () {
    final surface = artwork();
    final walk = walkOf({origin: null, beside: null, offStage: null});
    final forward = overwriteCelPixels(
      surface: surface,
      channel: CelPixelChannel.colour,
      walk: walk,
      value: bytes([1, 2, 3]),
    );
    final reads = ledger.debugTileReads;
    final again = overwriteCelPixels(
      surface: forward.surface,
      channel: CelPixelChannel.colour,
      walk: walk,
      value: bytes([4, 5, 6]),
    );
    overwriteCelPixels(
      surface: again.surface,
      channel: CelPixelChannel.colour,
      walk: walk,
      restore: again.restore,
    );
    expect(ledger.debugTileReads, reads);
  });

  test('the selector does not read alpha: a pixel emptied by a pass is named '
      'the same by the undo', () {
    final surface = artwork();
    final selector = CelPixelVerb.keepColour.selectorFor(
      0xFFC8280A,
      tolerance: 0,
    );
    final walk = walkOf({origin: soft, beside: null});
    final forward = overwriteCelPixels(
      surface: surface,
      channel: CelPixelChannel.alpha,
      walk: walk,
      value: bytes([0]),
      selector: selector,
    );
    final undone = overwriteCelPixels(
      surface: forward.surface,
      channel: CelPixelChannel.alpha,
      walk: walk,
      restore: forward.restore,
      selector: selector,
    );
    expect(bytesOf(undone.surface), bytesOf(surface));
  });
}

typedef _Verb = ({
  ({CelPixelChannel channel, Uint8List value}) of,
  CelColorKey? selector,
  int threshold,
});
