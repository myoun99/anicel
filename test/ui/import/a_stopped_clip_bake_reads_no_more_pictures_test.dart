@TestOn('vm')
library;

import 'dart:async';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/native/tile_blocks.dart';
import 'package:anicel/src/services/import/clip_cel_raster.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart'
    show AnicelLaidCel, freeLaidCel;
import 'package:anicel/src/ui/session/clip_import_door.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../services/import/clip_test_builder.dart';

/// A stop is honoured after the picture in hand (card F-608 ④ — the .tvpp
/// door's law, `a_stopped_tvpp_bake_reads_no_more_records_test`): once a
/// picture has landed and [ClipImportDoor.decodeEach] hears the stop, no
/// picture more is read, and what a worker still hands back is given back
/// unlaid.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('🚨once a landed picture hears the stop, no picture more is '
      'read', () async {
    var read = 0;
    var landed = 0;
    await ClipImportDoor.decodeEach(
      [0, 1, 2, 3],
      atOnce: 1,
      decoded: (_) async {
        read += 1;
        return null;
      },
      landed: (_, _) async => landed += 1,
      stopped: () => landed > 0,
    );

    expect(landed, 1, reason: 'the picture in hand, then the stop');
    expect(read, 1, reason: 'no picture read past it');
  });

  test('🚨a picture that comes back after the stop gives its blocks back — '
      'a stored picture\'s, and a text layer\'s pictures\'', () async {
    // A tile side no other tile in this process wears, so the blocks
    // held of its size ([TileBlocks.debugHeld]) are these pictures' alone.
    const length = 20 * 20 * 4;
    AnicelLaidCel picture() => clipCelLaid(
      offscreenAttributeBytes(width: 300, height: 200, columns: 2, rows: 1),
      blockRecordsBytes({
        for (final n in [0, 1])
          n: colourBlock((x, y) => ((n * 256 + x) & 0xff, y & 0xff, 7, 255)),
      }),
      (
        left: 0,
        top: 0,
        wall: const CanvasSize(
          width: 60,
          height: 40,
        ).pasteboardAt(PasteboardReach.none),
        alpha: 1,
        tileSize: 20,
      ),
    )!;
    final first = picture();
    final stored = picture();
    final lettered = picture();
    final twins = [picture(), picture()];

    final heard = Completer<void>();
    final landed = <int>[];
    final before = TileBlocks.debugHeld(length);
    await ClipImportDoor.decodeEach(
      [0, 1, 2],
      atOnce: 3,
      decoded: (item) async {
        if (item == 0) {
          return first;
        }
        await heard.future;
        return item == 1 ? stored : [lettered];
      },
      landed: (item, _) async => landed.add(item),
      stopped: () {
        heard.complete();
        return true;
      },
    );
    final givenBack = before - TileBlocks.debugHeld(length);
    twins.forEach(freeLaidCel);
    final twinsFreed = before - givenBack - TileBlocks.debugHeld(length);
    freeLaidCel(first);

    expect(landed, [0], reason: 'the picture in hand, then the stop');
    expect(twinsFreed, greaterThan(0), reason: 'the pictures hold blocks');
    expect(
      givenBack,
      twinsFreed,
      reason: 'the two that came back after it are freed, not left unlaid',
    );
  });
}
