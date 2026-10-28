import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/ui/export/export_settings_modules.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';

/// A document's format list ([ExportPaperFormatModule]) — the pictures its
/// pages can be written as, and the format of its own that is no picture
/// (the timesheet's XDTS, the conte's PDF), in one list (I-117, 유저
/// 2026-10-21: 「형식 고르는건 기본적으로 출력창에서 코덱 고르듯이
/// 리스트팝오버로」).
///
/// The rows are the app's one value picker's; what they are fed is the
/// module's own, and two of its answers survived mutation (2026-10-21):
/// which row is marked while the document's own format is written, and a
/// pill the window has made dead.
void main() {
  /// The module's rows as its list would show them now, its own format
  /// listed [after] the pictures — where the timesheet lists its XDTS.
  Future<List<PanelFlyoutItem>> rowsOf(
    WidgetTester tester, {
    required bool pictured,
    required PillItem after,
    bool Function(ExportStillFormat format)? stillEnabled,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportPaperFormatModule(
            keyPrefix: 'paper',
            caption: ExportCaption.format,
            image: paperDocumentFormat,
            stillEnabled: stillEnabled ?? (_) => true,
            pictured: pictured,
            onImageChanged: (_) {},
            after: [after],
          ),
        ),
      ),
    );
    return tester
        .widget<PanelFlyoutButton>(
          find.byKey(const ValueKey<String>('paper-file')),
        )
        .entriesBuilder()
        .whereType<PanelFlyoutItem>()
        .toList();
  }

  final pictureRows = [
    for (final format in ExportStillFormat.values) 'paper-${format.jsonValue}',
  ];

  testWidgets('while the document\'s own format is written, its row is the '
      'one marked — not the picture it would be written as', (tester) async {
    final rows = await rowsOf(
      tester,
      pictured: false,
      after: PillItem(
        keyValue: 'paper-xdts',
        label: 'XDTS',
        selected: true,
        onTap: () {},
      ),
    );
    expect({for (final row in rows) row.keyValue: row.selected}, {
      for (final picture in pictureRows) picture: false,
      'paper-xdts': true,
    });
  });

  testWidgets('a pill the window has made dead is listed dim, the pictures '
      'beside it live', (tester) async {
    final rows = await rowsOf(
      tester,
      pictured: true,
      after: const PillItem(
        keyValue: 'paper-xdts',
        label: 'XDTS',
        selected: false,
      ),
    );
    expect({for (final row in rows) row.keyValue: row.enabled}, {
      for (final picture in pictureRows) picture: true,
      'paper-xdts': false,
    });
  });

  testWidgets('every still is listed, a PSD among them (I-117), and one this '
      'machine cannot write is off and says why — as the Format module\'s '
      'list is', (tester) async {
    final rows = await rowsOf(
      tester,
      pictured: true,
      after: PillItem(
        keyValue: 'paper-xdts',
        label: 'XDTS',
        selected: false,
        onTap: () {},
      ),
      stillEnabled: (format) => format != ExportStillFormat.jpg,
    );
    final jpg = 'paper-${ExportStillFormat.jpg.jsonValue}';
    expect(
      {for (final row in rows) row.keyValue: (row.enabled, row.warning)},
      {
        for (final picture in pictureRows)
          picture: picture == jpg
              ? (false, AppText.strings.exNotInThisBuild)
              : (true, null),
        'paper-xdts': (true, null),
      },
    );
  });
}
