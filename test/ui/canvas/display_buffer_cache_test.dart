import 'dart:async';
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

  /// 🎯THE REAL BASE (유저 결정 2026-09-13: 「사슬을 없앤다 — 파생 베이스를
  /// 실체 이미지로」). The head is only ever drawn; what the next paint
  /// derives from is a plain `toImage` snapshot of the same picture, which
  /// has no recipe behind it and so pins nothing. The chain cannot form —
  /// the budgets above become the net for the paints before the first
  /// snapshot lands and for a raster thread that never answers.
  group('the real base ends the chain', () {
    const rect = Rect.fromLTWH(0, 0, 4, 4);
    const tokens = (
      overlay: <Object, Object>{},
      tiles: <Object, Object>{'t': 'made-with-the-head'},
      ghost: null,
    );

    /// A head with a snapshot on its way — the shape `_composeMiss` makes.
    Future<Completer<ui.Image>> storeAndPromote({
      Object staticKey = 'static',
      Rect at = rect,
      bool derived = false,
    }) async {
      cache.store(
        'k',
        staticKey,
        at,
        await makeImage(4),
        derived: derived,
        tokens: tokens,
      );
      final landing = Completer<ui.Image>();
      cache.promote(landing.future);
      return landing;
    }

    test('🚨a landed snapshot is the patch base, and it is NOT deferred — '
        'so deriving from it forms no link', () async {
      final landing = await storeAndPromote();
      final real = await makeImage(4);
      landing.complete(real);
      await pumpEventQueue();

      final base = cache.patchBaseFor('static', rect);
      expect(base, isNotNull);
      expect(identical(base!.image, real), isTrue, reason: 'the snapshot');
      expect(base.deferred, isFalse);
      expect(
        base.tokens.tiles['t'],
        'made-with-the-head',
        reason: 'described by what the HEAD was stored with — one picture, '
            'rasterized twice',
      );
      expect(cache.promotedCount, 1);
      expect(
        cache.heldBytes,
        2 * 4 * 4 * 4,
        reason: 'the head AND the real base are both resident',
      );
    });

    test('🚨past both budgets the real base still answers — the budgets '
        'guard the head, and the head is no longer what is derived from',
        () async {
      for (var i = 0; i < 200; i += 1) {
        cache.store('k$i', 'static', rect, await makeImage(4), derived: true);
      }
      expect(cache.patchBaseFor('static', rect), isNull, reason: 'the head');
      final landing = Completer<ui.Image>();
      cache.promote(landing.future);
      landing.complete(await makeImage(4));
      await pumpEventQueue();

      final base = cache.patchBaseFor('static', rect);
      expect(base, isNotNull);
      expect(base!.deferred, isFalse);
    });

    test('one snapshot in flight at a time — the cost decision', () async {
      expect(cache.promotionSlotFree, isTrue);
      final landing = await storeAndPromote();
      expect(cache.promotionSlotFree, isFalse, reason: 'not before it lands');

      landing.complete(await makeImage(4));
      await pumpEventQueue();
      expect(cache.promotionSlotFree, isTrue);
    });

    test('a snapshot that fails frees the slot; the head stays the base',
        () async {
      final landing = await storeAndPromote();
      landing.completeError(StateError('lost GPU context'));
      await pumpEventQueue();

      expect(cache.promotionSlotFree, isTrue);
      expect(cache.promotedCount, 0);
      final base = cache.patchBaseFor('static', rect);
      expect(base?.deferred, isTrue, reason: 'derived from the head, under budget');
    });

    test('⛔a snapshot landing after the layer tree moved on is released, '
        'not adopted', () async {
      final landing = await storeAndPromote();
      cache.store('k2', 'other-static', rect, await makeImage(4));
      landing.complete(await makeImage(4));
      await pumpEventQueue();

      expect(cache.promotedCount, 0);
      expect(cache.patchBaseFor('other-static', rect)?.deferred, isTrue);
      expect(cache.heldBytes, 4 * 4 * 4, reason: 'only the head');
    });

    test('a snapshot landing after a PAN is kept with its own rect, and '
        'carries as the scroll base', () async {
      final landing = await storeAndPromote();
      const moved = Rect.fromLTWH(1, 0, 4, 4);
      cache.store('k2', 'static', moved, await makeImage(4), derived: true);
      landing.complete(await makeImage(4));
      await pumpEventQueue();

      expect(cache.promotedCount, 1);
      expect(
        cache.patchBaseFor('static', moved)?.deferred,
        isTrue,
        reason: 'the real base covers the OLD rect, so the patch door falls '
            'back to the head stored at the new one',
      );
      final scroll = cache.scrollBaseFor('static', moved);
      expect(scroll, isNotNull);
      expect(scroll!.deferred, isFalse);
      expect(scroll.rect, rect, reason: 'the rect ITS pixels cover');
    });

    test('invalidate drops the real base too, and a landing after dispose '
        'is released without an owner', () async {
      final landing = await storeAndPromote();
      landing.complete(await makeImage(4));
      await pumpEventQueue();
      expect(cache.heldBytes, 2 * 4 * 4 * 4);

      cache.invalidate();
      expect(cache.heldBytes, 0);
      expect(cache.patchBaseFor('static', rect), isNull);

      final late = await storeAndPromote();
      cache.dispose();
      late.complete(await makeImage(4));
      await pumpEventQueue();
      expect(cache.promotedCount, 1, reason: 'the one from before dispose');
      expect(cache.promotionSlotFree, isFalse, reason: 'disposed');
    });
  });

  /// 🚨A SNAPSHOT IS A FIXED PRICE WHATEVER ITS SIZE (2026-09-25, the real
  /// Windows app: 32×32 and 2448×1313 alike 1.6–2.0 ms of raster), and on a
  /// fast GPU the slot is free on every paint — so a stroke paid for the
  /// head AND its promotion on every step. A patch over the real base forms
  /// no chain however old the base is, so it promotes now and then.
  group('a patch over the real base promotes now and then', () {
    const rect = Rect.fromLTWH(0, 0, 64, 64);
    const tokens = (
      overlay: <Object, Object>{},
      tiles: <Object, Object>{'t': 'kept'},
      ghost: null,
    );
    const small = Rect.fromLTWH(0, 0, 2, 2);

    Future<void> land(Future<void> Function(Completer<ui.Image>) ask) async {
      final landing = Completer<ui.Image>();
      await ask(landing);
      landing.complete(await makeImage(64));
      await pumpEventQueue();
    }

    Future<void> landRealBase() async {
      cache.store('k', 'static', rect, await makeImage(64), tokens: tokens);
      await land((landing) async => cache.promote(landing.future));
    }

    /// One stroke step the way the paint asks: the dirty rect set, then the
    /// question, then the store and — when asked — a promotion that lands
    /// at once, as on a GPU that answers within the frame.
    Future<bool> patchStep(int i, {Rect dirty = small}) async {
      cache.lastDirtyRect = dirty;
      final asked = cache.wantsPromotionFor(patchedOverRealBase: true);
      cache.store(
        'k$i',
        'static',
        rect,
        await makeImage(64),
        patched: true,
        tokens: tokens,
      );
      if (asked) {
        await land((landing) async => cache.promote(landing.future));
      }
      return asked;
    }

    test('every ${DisplayBufferCache.promoteEvery}th patch asks, however '
        'fast the snapshots land', () async {
      await landRealBase();
      final asked = <bool>[];
      for (var i = 0; i < 12; i += 1) {
        asked.add(await patchStep(i));
      }
      expect(
        asked.where((a) => a).length,
        12 ~/ DisplayBufferCache.promoteEvery,
      );
      expect(
        asked.take(DisplayBufferCache.promoteEvery - 1),
        everyElement(isFalse),
      );
      expect(
        cache.patchBaseFor('static', rect)?.deferred,
        isFalse,
        reason: 'the patches between still draw from the real base',
      );
    });

    test('a patch that recomposed a large share of the buffer asks at once',
        () async {
      await landRealBase();
      expect(
        await patchStep(0, dirty: const Rect.fromLTWH(0, 0, 32, 32)),
        isTrue,
        reason: 'a quarter of the buffer is past '
            '${DisplayBufferCache.promoteAtDirtyShare} of it',
      );
    });

    test('a compose that is not a patch over the real base asks as soon as '
        'the slot is free', () async {
      await landRealBase();
      cache.lastDirtyRect = small;
      expect(cache.wantsPromotionFor(patchedOverRealBase: false), isTrue);
    });

    test('never while one is in flight', () async {
      cache.store('k', 'static', rect, await makeImage(64), tokens: tokens);
      cache.promote(Completer<ui.Image>().future);
      cache.lastDirtyRect = rect;
      expect(cache.wantsPromotionFor(patchedOverRealBase: false), isFalse);
      expect(cache.wantsPromotionFor(patchedOverRealBase: true), isFalse);
    });
  });
}
