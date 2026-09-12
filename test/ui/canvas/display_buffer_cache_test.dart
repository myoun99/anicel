import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/canvas/display_buffer_cache.dart';

/// 🚨(v) — the composite buffer is kept while nothing has changed.
///
/// Every paint used to rasterise the whole visible rect again, including
/// the paints where nothing had moved: a hover, a cursor blink, a
/// neighbouring panel rebuilding.
///
/// ⛔A MISS COSTS WHAT THE UNCACHED PATH COST, and that is the property
/// that makes this safe to try at all. The tiled buffer that came before
/// failed on the other side of that line — a cold tile cache rasterised the
/// composite once PER TILE, so the thing meant to make strokes cheap made
/// panning N times dearer and had to be reverted. One image cannot do that.
void main() {
  late DisplayBufferCache cache;

  Future<ui.Image> makeImage(int side) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
      Paint()..color = const Color(0xFF123456),
    );
    return recorder.endRecording().toImage(side, side);
  }

  setUp(() => cache = DisplayBufferCache());
  tearDown(() => cache.dispose());

  test('a hit returns the very same image, not a copy of it', () async {
    final image = await makeImage(4);
    const rect = Rect.fromLTWH(0, 0, 4, 4);
    cache.store('k', 'static', rect, image);

    expect(identical(cache.imageFor('k', rect), image), isTrue);
    expect(cache.isWarm, isTrue);
  });

  test('a different key misses', () async {
    final image = await makeImage(4);
    const rect = Rect.fromLTWH(0, 0, 4, 4);
    cache.store('k', 'static', rect, image);

    expect(cache.imageFor('other', rect), isNull);
  });

  test('the same key over a different RECT misses', () async {
    // The rect is where the buffer belongs on the canvas. A pan that moves
    // it has to re-raster even when nothing in the picture changed, because
    // the buffer covers a different part of the world.
    final image = await makeImage(4);
    cache.store('k', 'static', const Rect.fromLTWH(0, 0, 4, 4), image);

    expect(cache.imageFor('k', const Rect.fromLTWH(1, 0, 4, 4)), isNull);
  });

  test('storing a new image drops the old one and keeps the new', () async {
    final first = await makeImage(4);
    final second = await makeImage(4);
    const rect = Rect.fromLTWH(0, 0, 4, 4);
    cache.store('k', 'static', rect, first);
    cache.store('k2', 'static', rect, second);

    expect(identical(cache.imageFor('k2', rect), second), isTrue);
    expect(cache.imageFor('k', rect), isNull);
  });

  test('re-storing the SAME image does not dispose the thing it is keeping',
      () async {
    // ⛔The subtle one. `store` disposes what it is replacing, and a paint
    // that hands back the image it was just given would otherwise kill the
    // handle it is about to draw with.
    final image = await makeImage(4);
    const rect = Rect.fromLTWH(0, 0, 4, 4);
    cache.store('k', 'static', rect, image);
    cache.store('k', 'static', rect, image);

    expect(identical(cache.imageFor('k', rect), image), isTrue);
    // A disposed image throws when drawn; drawing it here is the assertion.
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImage(image, Offset.zero, Paint());
    recorder.endRecording().dispose();
  });

  test('invalidate empties it', () async {
    final image = await makeImage(4);
    const rect = Rect.fromLTWH(0, 0, 4, 4);
    cache.store('k', 'static', rect, image);
    cache.invalidate();

    expect(cache.isWarm, isFalse);
    expect(cache.imageFor('k', rect), isNull);
  });

  /// 🚨THE CHAIN THAT KILLED THE APP (2026-09-09) AND ATE 17GB (2026-09-12).
  /// A buffer drawn from the kept one retains it: a `toImageSync` image
  /// keeps its display list for its WHOLE LIFE (the engine re-rasterizes
  /// from it after a lost GPU context — read from
  /// `display_list_deferred_image_gpu_skia.cc`, there is no reset in it),
  /// and the list holds every image it drew. So the chain is exactly the
  /// run of derived stores, one whole canvas a link, and it is released
  /// only when the head is — RECURSIVELY on the raster thread. ~2,470 links
  /// took its 2MB stack down; 2,048 of a 1920×1080 canvas is 17GB.
  ///
  /// The cache is where that is stopped, because the cache is what hands
  /// the previous image out — and nothing else stops it: rasterization
  /// does not, a frame on screen does not. A test in this group used to
  /// assert the opposite ("a RASTERIZED frame collapses the chain"), and
  /// the counter it pinned was reset on every frame, which is exactly why
  /// the link budget never fired while the user's memory climbed.
  group('the derived chain is bounded', () {
    const rect = Rect.fromLTWH(0, 0, 4, 4);

    Future<void> derive(int times, {int side = 4}) async {
      for (var i = 0; i < times; i += 1) {
        cache.store(
          'k$i',
          'static',
          rect,
          await makeImage(side),
          derived: true,
        );
      }
    }

    test('a derived store deepens the chain; a fresh one starts it over',
        () async {
      await derive(3);
      expect(cache.derivedDepth, 3);

      cache.store('fresh', 'static', rect, await makeImage(4));
      expect(
        cache.derivedDepth,
        0,
        reason: 'a compose that started from nothing retains no ancestor',
      );
    });

    test('🚨NOTHING BUT a fresh store or an invalidate shortens it — there '
        'is no frame event to wait for', () async {
      await derive(5);

      // There is deliberately nothing to call here. The old design reset
      // the count on `FrameTiming`; the engine never released anything on
      // that event, so the reset only hid the chain from its own budget.
      expect(cache.derivedDepth, 5);
      expect(
        cache.heldBytes,
        5 * 4 * 4 * 4,
        reason: 'and every link is still pinned, so the census says five',
      );
    });

    test('🚨the BYTE budget refuses first when the image is big — the '
        'chain the user hit was 128 links of 8.3MB, not 128 of 64 bytes',
        () async {
      // 1024² × 4 = 4MB an image: fifteen links pin 60MB and are allowed,
      // the sixteenth reaches the 64MB budget and both doors close — at a
      // depth the 128-link budget would still wave through.
      await derive(15, side: 1024);
      expect(cache.patchBaseFor('static', rect), isNotNull);

      await derive(1, side: 1024);
      expect(cache.derivedDepth, 16);
      expect(cache.heldBytes, 16 * 1024 * 1024 * 4);
      expect(
        cache.patchBaseFor('static', rect),
        isNull,
        reason: 'sixteen 4MB links is the whole memory budget',
      );
      expect(
        cache.scrollBaseFor('static', const Rect.fromLTWH(1, 0, 4, 4)),
        isNull,
      );

      // A full compose lets the run go: one image pinned, both doors open.
      cache.store('fresh', 'static', rect, await makeImage(1024));
      expect(cache.heldBytes, 1024 * 1024 * 4);
      expect(cache.patchBaseFor('static', rect), isNotNull);
    });

    test('🚨past the budget BOTH doors refuse, so the next compose has to '
        'start from nothing', () async {
      await derive(200);

      expect(
        cache.patchBaseFor('static', rect),
        isNull,
        reason: 'the patch door is one of the two that hands the image out',
      );
      expect(
        cache.scrollBaseFor('static', const Rect.fromLTWH(1, 0, 4, 4)),
        isNull,
        reason: 'a PAN derives too — refusing only the patch door would let '
            'a drag rebuild the same chain',
      );
      // And the refusal is not a dead cache: the image is still there for a
      // plain hit, and one full compose reopens both doors.
      expect(cache.isWarm, isTrue);
      cache.store('fresh', 'static', rect, await makeImage(4));
      expect(cache.patchBaseFor('static', rect), isNotNull);
    });

    test('invalidate starts the chain over — nothing is kept to derive from',
        () async {
      await derive(200);
      cache.invalidate();

      expect(cache.derivedDepth, 0);
      expect(cache.heldBytes, 0);
    });
  });
}
