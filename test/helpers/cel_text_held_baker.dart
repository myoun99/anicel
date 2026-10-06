import 'dart:async';

import 'package:anicel/src/core/floor_math.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/text/cel_text_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cel_text_fixture.dart';

/// THE ENGINE, HELD BY THE TEST (R9-rest): a baker whose every answer waits
/// until the test gives it — so a test can stand in the frames BETWEEN a
/// text being wanted and its pixels existing, which is where the text
/// tool's hardest promises live (what is on screen is a whole text; the
/// newest want wins; a text let go of mid-bake still lands).
///
/// ⚠️It stands in for the engine's TIMING, not for its pixels — what the
/// engine draws is pinned against the engine (`cel_text_bake_test.dart`).
class HeldBaker {
  /// Every bake asked for, in order.
  final List<HeldBake> asked = [];

  Future<Map<TileCoord, BitmapTile>> call(
    CelTextLayout layout, {
    required CanvasSize canvasSize,
    required int tileSize,
    Map<TileCoord, BitmapTile> previous = const {},
  }) {
    final bake = HeldBake._(layout.content, previous);
    asked.add(bake);
    return bake._answer.future;
  }

  /// The bake asked for last, which no answer has been given to yet.
  HeldBake get pending => asked.lastWhere((bake) => !bake.answered);
}

/// One bake the engine was asked for and has not answered.
class HeldBake {
  HeldBake._(this.content, this.previous);

  /// The text it was asked to set.
  final CelTextContent content;

  /// The plate the text had before, as the baker was handed it.
  final Map<TileCoord, BitmapTile> previous;

  final Completer<Map<TileCoord, BitmapTile>> _answer = Completer();

  bool get answered => _answer.isCompleted;

  /// The engine answers — with [plate], or with what [plateOf] makes of the
  /// text — and everything waiting on it runs.
  Future<void> answer([Map<TileCoord, BitmapTile>? plate]) async {
    _answer.complete(plate ?? plateOf(content));
    await pumpEventQueue();
  }

  /// The engine refuses.
  Future<void> refuse(Object error) async {
    _answer.completeError(error);
    await pumpEventQueue();
  }
}

/// The plate the stand-in makes of [content]: ONE tile, the one its anchor
/// is in, every pixel saying how many letters the text has and what colour
/// its first one is — enough for a test to tell which text a plate is of,
/// and where it stands.
Map<TileCoord, BitmapTile> plateOf(CelTextContent content) {
  final argb = content.spans.first.style.color;
  return {
    tileOfAnchor(content): tileFilledWith([
      content.text.length,
      (argb >> 16) & 0xFF,
      argb & 0xFF,
      255,
    ]),
  };
}

/// The tile [content]'s anchor is in, on the test grid.
TileCoord tileOfAnchor(CelTextContent content) => TileCoord(
  x: floorDiv(content.anchor.x.floor(), celTextTestTileSize),
  y: floorDiv(content.anchor.y.floor(), celTextTestTileSize),
);
