@Tags(['benchmark'])
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../helpers/panel_finders.dart';

/// Full-pipeline accumulation microbenchmark (not a correctness test): the
/// REAL app (HomePage — session, history, caches, prerender scheduler,
/// thumbnails, timeline all wired) takes hundreds of stylus strokes and the
/// UI-thread cost is measured per bucket:
///
/// - move-pump: one frame while the pointer is down (the live-draw path);
/// - settle: everything a pen-up fans out (commit, display-cache donation,
///   invalidation consumers, thumbnail/warm kicks) until the app is idle.
///
/// The coordinator-only benchmark proved the commit COMPUTE stays flat; this
/// one watches the whole wiring for anything that grows with accumulated
/// strokes — "draws fine, then gradually lags" measured at the app level.
void main() {
  testWidgets(
    'per-stroke UI-thread cost as strokes accumulate (full app)',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();

      // The default project has no cel at the playhead — author one.
      final addButton = find.byKey(const ValueKey<String>('new-frame-button'));
      await tester.ensureVisible(addButton);
      await tester.pumpAndSettle();
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      // PANEL-SCOPED (R26 #31): the docked timesheet's ink planes are
      // interactive views too — the benchmark strokes the DRAWING canvas.
      final canvas = mainCanvasView();
      expect(canvas, findsOneWidget, reason: 'authored cel must be drawable');

      const strokesPerBucket = 30;
      const buckets = 6;
      const movesPerStroke = 8;

      for (var bucket = 0; bucket < buckets; bucket += 1) {
        final moveWatch = Stopwatch();
        final settleWatch = Stopwatch();
        var movePumps = 0;

        for (var s = 0; s < strokesPerBucket; s += 1) {
          final strokeIndex = bucket * strokesPerBucket + s;
          final rect = tester.getRect(canvas);
          final start = Offset(
            rect.left + 24 + (strokeIndex * 13.0) % (rect.width - 120),
            rect.top + 24 + (strokeIndex * 7.0) % (rect.height - 80),
          );
          final gesture = await tester.startGesture(
            start,
            kind: PointerDeviceKind.stylus,
          );
          for (var move = 0; move < movesPerStroke; move += 1) {
            await gesture.moveBy(const Offset(7, 4));
            moveWatch.start();
            await tester.pump();
            moveWatch.stop();
            movePumps += 1;
          }
          await gesture.up();
          settleWatch.start();
          await tester.pumpAndSettle();
          settleWatch.stop();
        }

        // ignore: avoid_print
        print(
          '[full-pipeline] strokes ${(bucket + 1) * strokesPerBucket}: '
          'move-pump ${(moveWatch.elapsedMicroseconds / 1000.0 / movePumps).toStringAsFixed(2)}ms '
          '| settle ${(settleWatch.elapsedMicroseconds / 1000.0 / strokesPerBucket).toStringAsFixed(2)}ms/stroke',
        );
      }

      // Drain the prerender scheduler's debounced warming (a pending timer
      // at teardown fails the test harness's invariants).
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
