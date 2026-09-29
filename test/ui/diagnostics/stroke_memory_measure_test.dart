@Tags(['benchmark'])
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_memory_settings.dart';
import 'package:anicel/src/ui/diagnostics/memory_census.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';

import '../../helpers/collect_garbage.dart';
import '../../helpers/panel_finders.dart';

/// F-226 measurement (not a pin): the real app takes big zigzag strokes
/// across the whole canvas, and the census is read after each — whether
/// every row stops at its ceiling or grows with every stroke.
///
/// 🔬2026-09-30, allowance 600MB: tile pictures 8.8→45.3MB and the undo
/// history 6.6→36.5MB grew with each stroke and then did not move from the
/// 15th stroke to the 19th; the drawings, the playback frames and the
/// layer images were flat from the first. A stroke is ~30 s on the test VM,
/// hence the long timeout.
void main() {
  testWidgets('census rows per stroke across the whole canvas', (
    tester,
  ) async {
    const allowanceMb = int.fromEnvironment('ALLOWANCE_MB', defaultValue: 600);
    AppMemory.settings.value = const AppMemorySettings(
      allowanceBytes: allowanceMb * 1024 * 1024,
    );
    addTearDown(() => AppMemory.settings.value = const AppMemorySettings());
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    final addButton = find.byKey(const ValueKey<String>('new-frame-button'));
    await tester.ensureVisible(addButton);
    await tester.pumpAndSettle();
    await tester.tap(addButton);
    await tester.pumpAndSettle();
    final canvas = mainCanvasView();
    expect(canvas, findsOneWidget);
    final projects = tester
        .widget<EditorTopStrip>(find.byType(EditorTopStrip).first)
        .projects;

    String mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
    void report(String label) {
      final census = collectMemoryCensus(projects.sessions);
      final rows = [
        for (final item in census.items)
          if (item.bytes > 0) '${item.id}=${mb(item.bytes)}',
      ];
      // ignore: avoid_print
      print('MEASURE $label tracked=${mb(census.trackedBytes)} $rows');
    }

    report('before');
    const strokes = int.fromEnvironment('STROKES', defaultValue: 30);
    for (var stroke = 0; stroke < strokes; stroke += 1) {
      final rect = tester.getRect(canvas).deflate(12);
      final gesture = await tester.startGesture(
        rect.topLeft,
        kind: PointerDeviceKind.stylus,
      );
      const passes = 8;
      for (var pass = 0; pass < passes; pass += 1) {
        final y = rect.top + rect.height * pass / (passes - 1);
        final from = pass.isEven ? rect.left : rect.right;
        final to = pass.isEven ? rect.right : rect.left;
        for (var step = 0; step <= 12; step += 1) {
          await gesture.moveTo(Offset(from + (to - from) * step / 12, y));
          await tester.pump();
        }
      }
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.runAsync(collectGarbage);
      await tester.pump();
      report('after ${stroke + 1}');
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
