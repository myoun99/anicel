import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/core/sync_image_upload.dart';
import 'package:anicel/src/services/runtime_path_report.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/dialogs/system_status_section.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

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
      'PDF renderer',
      'Tile picture upload',
      'Pen tablet driver',
    ]);
    for (final entry in entries) {
      expect(entry.active, isNotEmpty, reason: entry.subsystem);
      expect(entry.detail, isNotEmpty, reason: entry.subsystem);
    }
  });

  test('an unloaded PDF renderer reports its absence honestly', () {
    // flutter_tester never loads PDFium (no Dart fallback exists for it),
    // so the report must show the disabled state, tinted as non-primary.
    final pdf = collectRuntimePathReport().singleWhere(
      (entry) => entry.subsystem == 'PDF renderer',
    );
    expect(pdf.isPrimary, isFalse);
    expect(pdf.active, contains('disabled'));
  });

  test('the tile picture upload follows the RENDERER, not the packaging', () {
    // The only row here whose non-primary state is normal rather than a
    // problem: `decodeImageFromPixelsSync` is Impeller-only and
    // `flutter_tester` has no synchronous upload, so the report says
    // "asynchronous" HERE.
    // ⚠️2026-09-16: that is no longer what a Windows user sees. Since 3.47
    // the desktop ships Impeller, so the shipped app reports the
    // synchronous row as primary — this test pins the HARNESS's answer,
    // and the detail still has to say why an amber row is not a broken
    // build, because a user with no GPU context still lands here.
    final upload = collectRuntimePathReport().singleWhere(
      (entry) => entry.subsystem == 'Tile picture upload',
    );
    expect(upload.isPrimary, syncImageUploadSupported);
    expect(upload.isPrimary, isFalse, reason: 'flutter_tester runs Skia');
    expect(upload.active, contains('Asynchronous'));
    expect(upload.detail, contains('Impeller'));
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
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SystemStatusSection(session: session),
          ),
        ),
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
