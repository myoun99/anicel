import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/widgets/overflow_scrollers.dart';

/// 🗣️I-153-Q3 (유저 2026-11-04): 「창 전체가 가로로 스크롤」 — a screen
/// narrower than the export window's four columns stands them at their
/// width and scrolls the window's body sideways. The window never grows
/// past the screen, so the columns overflowed and were cut where it ended:
/// the Cels list's rules, its rail, the folder columns, the settings.
void main() {
  setUp(() => AppExport.settings.value = AppExportSettings());
  tearDown(() => AppExport.settings.value = AppExportSettings());

  /// The window on a [screen], standing on the Cels tab — and how far its
  /// body scrolls sideways.
  Future<ScrollPosition> sidewaysAt(WidgetTester tester, Size screen) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    AppExport.settings.value = AppExportSettings(
      lastSpecs: const ExportTabSpecs(
        cels: CelsExportSpec(kinds: {ExportCelKind.cel}),
      ),
    );
    await tester.binding.setSurfaceSize(screen);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session,
            formatAvailability: ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('export-tab-cels')));
    await tester.pump();
    final body = find.descendant(
      of: find.byKey(const ValueKey<String>('export-dialog')),
      matching: find.byType(OverflowScrollers),
    );
    // The outer of its two scrollers is the sideways one.
    return tester
        .state<ScrollableState>(
          find.descendant(of: body, matching: find.byType(Scrollable)).first,
        )
        .position;
  }

  testWidgets('🗣️on a screen narrower than the columns, the window scrolls '
      'sideways — nothing overflows and nothing is cut', (tester) async {
    final sideways = await sidewaysAt(tester, const Size(1000, 800));

    expect(
      tester.takeException(),
      isNull,
      reason: 'the columns overflowed the window and were cut',
    );
    expect(sideways.axis, Axis.horizontal);
    expect(sideways.maxScrollExtent, greaterThan(0));
  });

  testWidgets('on a screen that holds them there is nothing to scroll', (
    tester,
  ) async {
    final sideways = await sidewaysAt(tester, const Size(1920, 1080));

    expect(tester.takeException(), isNull);
    expect(sideways.maxScrollExtent, 0);
  });
}
