import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';

/// The export window's name bar holds a name, a destination and the two
/// destination buttons — 「찾아보기」 and 「끝나면 고르기」
/// (drive-folder-windows-Q1). In a narrow window the name gives way to the
/// destination rather than push the buttons off the bar: a name field of
/// fixed width, or a long file pattern, overflowed it at the 800-wide
/// default surface once the second button stood there.
void main() {
  tearDown(() => AppExport.settings.value = AppExportSettings());

  Future<void> open(WidgetTester tester, SequenceExportSpec sequence) async {
    AppExport.settings.value = AppExportSettings(
      lastSpecs: const ExportTabSpecs().withSpec(sequence),
    );
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: EditorSessionManager(
              initialProject: createDefaultProject(),
            ),
            formatAvailability: ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.pump();
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  }

  /// Whether [key]'s button stands wholly inside the name bar.
  bool standsInTheBar(WidgetTester tester, String key) {
    final bar = tester.getRect(
      find
          .ancestor(
            of: find.byKey(const ValueKey<String>('export-location-label')),
            matching: find.byType(Container),
          )
          .first,
    );
    final button = tester.getRect(find.byKey(ValueKey<String>(key)));
    return button.left >= bar.left && button.right <= bar.right;
  }

  testWidgets('a video\'s name field gives way, and both buttons stay on the '
      'bar', (tester) async {
    await open(tester, const SequenceExportSpec());

    expect(tester.takeException(), isNull);
    expect(standsInTheBar(tester, 'export-browse-button'), isTrue);
    expect(standsInTheBar(tester, 'export-hand-over-button'), isTrue);
  });

  testWidgets('a long file pattern ellipsizes, and both buttons stay on the '
      'bar', (tester) async {
    await open(
      tester,
      SequenceExportSpec(
        format: const ExportFormatSelection(kind: ExportMediaKind.still),
        naming: ExportSequenceNaming(baseName: 'a_very_long_shot_name' * 3),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(standsInTheBar(tester, 'export-browse-button'), isTrue);
    expect(standsInTheBar(tester, 'export-hand-over-button'), isTrue);
  });
}
