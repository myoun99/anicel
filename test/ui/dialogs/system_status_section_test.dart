import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/runtime_path_report.dart';
import 'package:anicel/src/ui/dialogs/system_status_section.dart';

/// Preferences ▸ System (user rule 07-22): every runtime-selected
/// implementation path is REPORTED — the report's subsystem roster is a
/// contract (forgetting to list a new switchable path is the regression
/// this file exists to catch), and fallback states must render as
/// visible states, not vanish.
void main() {
  tearDown(() {
    QaNativeEngine.debugResetForTests();
    QaNativeEngine.debugForceDartFallback = false;
  });

  test('the report covers every switchable subsystem', () {
    final entries = collectRuntimePathReport();
    expect(entries.map((entry) => entry.subsystem), [
      'Raster engine',
      'Audio engine',
      'Audio import decoder',
      'Video export encoder',
      'Pen tablet driver',
    ]);
    for (final entry in entries) {
      expect(entry.active, isNotEmpty, reason: entry.subsystem);
      expect(entry.detail, isNotEmpty, reason: entry.subsystem);
    }
  });

  test('a missing raster engine reports the Dart fallback honestly', () {
    QaNativeEngine.debugResetForTests();
    QaNativeEngine.debugForceDartFallback = true;
    final raster = collectRuntimePathReport().singleWhere(
      (entry) => entry.subsystem == 'Raster engine',
    );
    expect(raster.isPrimary, isFalse);
    expect(raster.active, contains('Dart fallback'));
  });

  testWidgets('the section renders one row per subsystem', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: SystemStatusSection())),
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('system-status-section')),
      findsOneWidget,
    );
    for (final entry in collectRuntimePathReport()) {
      expect(
        find.byKey(ValueKey<String>('system-status-${entry.subsystem}')),
        findsOneWidget,
      );
      expect(find.text(entry.subsystem), findsOneWidget);
    }
  });
}
