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

  /// 🚨THE CHAIN THAT KILLED THE APP (2026-09-09). A buffer drawn from the
  /// kept one retains it — `toImageSync` hands back an image the engine has
  /// not rasterized, holding the display list that would draw it — so
  /// deriving without end builds a list that is released RECURSIVELY on the
  /// raster thread. ~2,470 links took its 2MB stack down with no frame of
  /// ours on it.
  ///
  /// The cache is where that is stopped, because the cache is what hands
  /// the previous image out.
  group('the derived chain is bounded', () {
    const rect = Rect.fromLTWH(0, 0, 4, 4);

    Future<void> derive(int times) async {
      for (var i = 0; i < times; i += 1) {
        cache.store('k$i', 'static', rect, await makeImage(4), derived: true);
      }
    }

    test('a derived store deepens the chain; a fresh one starts it over',
        () async {
      await derive(3);
      expect(cache.debugDerivedDepth, 3);

      cache.store('fresh', 'static', rect, await makeImage(4));
      expect(
        cache.debugDerivedDepth,
        0,
        reason: 'a compose that started from nothing retains no ancestor',
      );
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

      expect(cache.debugDerivedDepth, 0);
    });

    test('🎯a RASTERIZED frame collapses the chain, so the count follows it '
        'instead of climbing forever', () async {
      await derive(5);
      expect(cache.debugDerivedDepth, 5);

      // What the engine did at that moment: drawing the newest buffer
      // snapshots it, which releases the display list behind it, all the
      // way down. Nothing is left to recurse over.
      cache.noteFrameRasterized();

      expect(cache.debugDerivedDepth, 0);
      expect(
        cache.patchBaseFor('static', rect),
        isNotNull,
        reason: 'and the fast path is open again — a frame that reached the '
            'screen must not cost the next compose anything',
      );
    });

    test('🚨but composes with NO frame in between still reach the budget — '
        'that is the case the app died in', () async {
      // No `noteFrameRasterized` anywhere in here on purpose: an offscreen
      // bake, or a raster thread left behind, produces no frame timing.
      await derive(200);

      expect(cache.patchBaseFor('static', rect), isNull);
    });
  });
}
