import 'package:anicel/src/ui/dialogs/app_progress_dialog.dart';
import 'package:anicel/src/ui/media/viewer_page_loading.dart';
import 'package:anicel/src/ui/widgets/app_spinner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🗣️F-617 (검증 2026-11-19): a page waited on in the import window showed
/// its ring as a 3 px dot — every spinner stood up at its own start, where
/// its arc is 0.001 rad, and a file opening handed its ring to the page's.
void main() {
  /// The arc [spinner] draws now: where it starts, and how far it sweeps.
  (double, double) arcOf(WidgetTester tester, Finder spinner) {
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: spinner,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.painter.runtimeType.toString().contains('Circular'),
        ),
      ),
    );
    // The arc is the SDK's painter's own (private class, public fields).
    final painter = paint.painter! as dynamic;
    // ignore: avoid_dynamic_calls
    final start = painter.arcStart as double;
    // ignore: avoid_dynamic_calls
    return (start, painter.arcSweep as double);
  }

  testWidgets('🚨a spinner put up late stands where one put up early is — '
      "mid-turn, and so do the page's wait ring and the wait window's", (
    tester,
  ) async {
    final progress = ValueNotifier<double?>(null);
    addTearDown(progress.dispose);
    var later = false;
    late StateSetter put;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              put = setState;
              return Column(
                children: [
                  const SizedBox.square(
                    dimension: 24,
                    child: AppSpinner(key: ValueKey<String>('early')),
                  ),
                  if (later) ...[
                    const SizedBox.square(
                      dimension: 24,
                      child: AppSpinner(key: ValueKey<String>('late')),
                    ),
                    const SizedBox(height: 48, child: ViewerPageLoading()),
                    AppProgressDialog(
                      title: 't',
                      runningLabel: 'r',
                      progress: progress,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
    // On until the early one is past the dot — a turn is 1.333 s.
    final standing = find.byKey(const ValueKey<String>('early'));
    for (var frame = 0; frame < 100; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
      if (arcOf(tester, standing).$2 > 0.5) {
        break;
      }
    }
    put(() => later = true);
    await tester.pump(const Duration(milliseconds: 16));

    final early = arcOf(tester, standing);
    expect(early.$2, greaterThan(0.28), reason: 'LIVENESS: past the dot');
    for (final (name, spinner) in [
      ('a spinner', find.byKey(const ValueKey<String>('late'))),
      ("a page's wait ring", find.byType(ViewerPageLoading)),
      ("the wait window's", find.byType(AppProgressDialog)),
    ]) {
      final arc = arcOf(tester, spinner);
      expect(arc.$1, closeTo(early.$1, 1e-9), reason: '$name turns as one');
      expect(arc.$2, closeTo(early.$2, 1e-9), reason: '$name sweeps as one');
    }
  });
}
