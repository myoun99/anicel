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
    cache.store('k', rect, image);

    expect(identical(cache.imageFor('k', rect), image), isTrue);
    expect(cache.isWarm, isTrue);
  });

  test('a different key misses', () async {
    final image = await makeImage(4);
    const rect = Rect.fromLTWH(0, 0, 4, 4);
    cache.store('k', rect, image);

    expect(cache.imageFor('other', rect), isNull);
  });

  test('the same key over a different RECT misses', () async {
    // The rect is where the buffer belongs on the canvas. A pan that moves
    // it has to re-raster even when nothing in the picture changed, because
    // the buffer covers a different part of the world.
    final image = await makeImage(4);
    cache.store('k', const Rect.fromLTWH(0, 0, 4, 4), image);

    expect(cache.imageFor('k', const Rect.fromLTWH(1, 0, 4, 4)), isNull);
  });

  test('storing a new image drops the old one and keeps the new', () async {
    final first = await makeImage(4);
    final second = await makeImage(4);
    const rect = Rect.fromLTWH(0, 0, 4, 4);
    cache.store('k', rect, first);
    cache.store('k2', rect, second);

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
    cache.store('k', rect, image);
    cache.store('k', rect, image);

    expect(identical(cache.imageFor('k', rect), image), isTrue);
    // A disposed image throws when drawn; drawing it here is the assertion.
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImage(image, Offset.zero, Paint());
    recorder.endRecording().dispose();
  });

  test('invalidate empties it', () async {
    final image = await makeImage(4);
    const rect = Rect.fromLTWH(0, 0, 4, 4);
    cache.store('k', rect, image);
    cache.invalidate();

    expect(cache.isWarm, isFalse);
    expect(cache.imageFor('k', rect), isNull);
  });
}
