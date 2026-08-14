import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/canvas/static_composite_bake.dart';

/// 🚨★★★ (v) 1단계의 계약 — 실측①이 없애려던 것이 실제로 사라지는가.
///
/// 실측①: a stroke step re-runs the WHOLE composite tree. What this file
/// counts is how many times the body that walks that tree actually RUNS —
/// which is the Dart-side cost, and the axis the debug bar is measured on
/// (유저 2026-08-14: 「내가 실기하는건 디버그야. 윈도우는 특히. 렉 기준도
/// 디버그고」).
///
/// ⚠️계측기를 먼저 의심하라 — [[canvas-raster-perf-round]]·
/// [[stale-tile-flicker-program]] 둘 다 계측기가 거짓말한 기록이 정본이다.
/// So the counter here is the record callback itself: it cannot report a
/// saving that did not happen, because the only way the number stays flat
/// is for the body genuinely not to have been invoked.
void main() {
  late StaticCompositeBake bake;
  late int recordings;

  /// One paint pass: replay or record two slots, the way the split walk
  /// does at depth 0 with the active layer between them.
  void paintOnce(Canvas canvas) {
    for (final slot in const ['d0:before', 'd0:after']) {
      bake.draw(canvas, slot, (into) {
        recordings += 1;
        into.drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint());
      });
    }
  }

  Canvas scratch() => Canvas(ui.PictureRecorder());

  setUp(() {
    bake = StaticCompositeBake();
    recordings = 0;
    bake.keepFor('key-a');
  });

  tearDown(() => bake.dispose());

  test('the first paint records; every paint after it replays', () {
    paintOnce(scratch());
    expect(recordings, 2, reason: 'one recording per slot');

    // Ten stroke steps. Under the old walk this was ten more full runs of
    // the tree body — that is exactly 실측①.
    for (var step = 0; step < 10; step += 1) {
      paintOnce(scratch());
    }

    expect(
      recordings,
      2,
      reason: 'the stroke re-ran the static tree zero times',
    );
    expect(bake.slotCount, 2);
  });

  test('a changed key throws the recordings away', () {
    paintOnce(scratch());
    expect(recordings, 2);

    bake.keepFor('key-b');
    expect(bake.slotCount, 0, reason: 'dropped at the moment the key moved');

    paintOnce(scratch());
    expect(recordings, 4, reason: 're-recorded against the new key');
  });

  test('the same key twice is not a reason to re-record', () {
    paintOnce(scratch());
    bake.keepFor('key-a');
    paintOnce(scratch());

    expect(recordings, 2);
  });

  test('invalidate() drops everything, and the next paint rebuilds it', () {
    paintOnce(scratch());
    bake.invalidate();
    expect(bake.slotCount, 0);

    // ⛔After an invalidate the key is gone too, so the owner must set one
    // again — otherwise the first `keepFor` after it would look like a
    // change and throw away what was just recorded.
    bake.keepFor('key-a');
    paintOnce(scratch());
    expect(recordings, 4);
    expect(bake.slotCount, 2);
  });

  /// 🚨★★★ (v) 2단계 후반부 — the bottom of the stack is RASTERISED, and a
  /// stroke step must not pay for it again.
  ///
  /// A picture already stopped the Dart walk; what it cannot stop is the
  /// engine replaying every draw inside it, so 500 layers below the active
  /// one still cost 500 draws and 500 paints per step. This counts the only
  /// thing that can honestly report the saving: how many times the body
  /// that walks those layers actually runs.
  group('the backdrop raster', () {
    const rect = Rect.fromLTWH(0, 0, 4, 4);

    void rasterOnce(Canvas canvas) {
      bake.drawRaster(canvas, 'd0:backdrop', rect, (into) {
        recordings += 1;
        into.drawRect(rect, Paint());
      });
    }

    test('three stroke steps walk the stack once', () {
      rasterOnce(scratch());
      rasterOnce(scratch());
      rasterOnce(scratch());

      expect(
        recordings,
        1,
        reason: 'that is the whole difference between a raster and a picture '
            'down here — the picture replays, the raster is one blit',
      );
      expect(bake.rasterCount, 1);
    });

    test('a new key re-rasterises, because the stack really did change', () {
      rasterOnce(scratch());
      bake.keepFor('key-b');
      rasterOnce(scratch());

      expect(recordings, 2);
      expect(
        bake.rasterCount,
        1,
        reason: 'the old raster was dropped rather than accumulated — the '
            'key IS the invalidation, and a raster that outlived its images '
            'would be replaying dead handles',
      );
    });

    test('invalidate() drops the raster too', () {
      rasterOnce(scratch());
      bake.invalidate();

      expect(bake.rasterCount, 0);
    });

    test('an empty rect is a no-op, not a zero-sized image', () {
      bake.drawRaster(scratch(), 'd0:backdrop', Rect.zero, (into) {
        recordings += 1;
      });

      expect(recordings, 0);
      expect(bake.rasterCount, 0);
    });
  });
}
