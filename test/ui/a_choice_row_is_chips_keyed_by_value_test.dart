import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_settings_modules.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';

import '../helpers/solid_png_fixture.dart';
import '../helpers/temp_dir.dart';

/// A picker ROW in this app is one law spelled once per value: a chip
/// keyed `<row>-<value>`, labelled from a per-value table, shown selected
/// by comparing it with the current value, and selecting it on tap. A
/// value the row refuses gets no tap at all.
///
/// This pins that law where it is USED — the key strings a hand and a test
/// reach for, the selected chip, and the refused one — so the rows can be
/// written once without any of them changing what the window offers.
void main() {
  ExportPill chipAt(WidgetTester tester, String key) =>
      tester.widget<ExportPill>(find.byKey(ValueKey<String>(key)));

  /// The chip of [row] that is drawn selected, by its key suffix.
  String selectedIn(WidgetTester tester, String row, List<String> values) {
    final on = [
      for (final value in values)
        if (chipAt(tester, '$row-$value').selected) value,
    ];
    expect(on.length, 1, reason: '$row shows exactly one selection: $on');
    return on.single;
  }

  group('the import window', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('anicel-choice-row');
    });

    tearDown(() => deleteTempQuietly(tempDir));

    Future<String> writePng(String name) =>
        writeSolidPng(tempDir, name, rgba: 0xAAAAAAAA);

    Future<void> openOn(
      WidgetTester tester,
      EditorSessionManager session,
      String path,
    ) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportDialog(session: session, initialPaths: [path]),
          ),
        ),
      );
      // A loose file is probed (identity, size) before the window can say
      // what it is offering; real IO runs in runAsync and its awaits are
      // fake-zone microtasks that only pump() drains.
      for (var i = 0; i < 8; i += 1) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
    }

    /// A delivery folder — the settings column is the FOLDER column (a
    /// loose file answers per row in the file table instead).
    Future<String> writeFolder(WidgetTester tester) async =>
        (await tester.runAsync(() async {
          const root = 'upn_02_063_lo';
          final sep = Platform.pathSeparator;
          await writePng('$root${sep}A1.png');
          await writePng('$root${sep}A2.png');
          return '${tempDir.path}$sep$root';
        }))!;

    testWidgets('Files, Fit and Revisions each offer one chip per value, '
        'keyed by the value', (tester) async {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      await openOn(tester, s, await writeFolder(tester));

      for (final key in [
        'import-media-reference',
        'import-media-copy',
        'import-fit-stretch',
        'import-fit-contain',
        'import-fit-none',
        'import-revision-latestOnly',
        'import-revision-all',
        'import-revision-originalOnly',
      ]) {
        expect(
          find.byKey(ValueKey<String>(key)),
          findsOneWidget,
          reason: 'chip $key',
        );
      }
      expect(chipAt(tester, 'import-media-copy').label, 'Keep');
      expect(chipAt(tester, 'import-fit-contain').label, 'Keep aspect');
      expect(chipAt(tester, 'import-revision-originalOnly').label, 'Originals');
    });

    testWidgets('the selected chip is the one holding the answer, and '
        'tapping another moves it', (tester) async {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      await openOn(tester, s, await writeFolder(tester));

      // Carrying is the default on every platform (2026-08-14).
      expect(selectedIn(tester, 'import-media', ['reference', 'copy']), 'copy');
      expect(
        selectedIn(tester, 'import-fit', ['stretch', 'contain', 'none']),
        'contain',
      );
      expect(
        selectedIn(tester, 'import-revision', [
          'latestOnly',
          'all',
          'originalOnly',
        ]),
        'latestOnly',
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('import-media-reference')),
      );
      await tester.pump();
      expect(
        selectedIn(tester, 'import-media', ['reference', 'copy']),
        'reference',
      );

      await tester.tap(find.byKey(const ValueKey<String>('import-fit-none')));
      await tester.pump();
      expect(
        selectedIn(tester, 'import-fit', ['stretch', 'contain', 'none']),
        'none',
      );
    });
  });

  group('the export format module', () {
    Future<void> pumpChannels(WidgetTester tester, {required bool on}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExportFormatModule(
              selection: const ExportFormatSelection(
                kind: ExportMediaKind.still,
                stillFormat: ExportStillFormat.png,
              ),
              capabilities: const ExportFormatCapabilities(
                stills: ExportStillFormat.values,
              ),
              enabled: on,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('the channel chips are keyed by value and follow the '
        'selection', (tester) async {
      await pumpChannels(tester, on: true);
      for (final channels in ExportChannels.values) {
        expect(
          find.byKey(
            ValueKey<String>('export-format-channels-${channels.jsonValue}'),
          ),
          findsOneWidget,
        );
      }
      expect(
        selectedIn(tester, 'export-format-channels', [
          for (final channels in ExportChannels.values) channels.jsonValue,
        ]),
        ExportChannels.rgba.jsonValue,
      );
    });

    testWidgets('a disabled module still SHOWS every channel chip; none of '
        'them answers', (tester) async {
      await pumpChannels(tester, on: false);
      for (final channels in ExportChannels.values) {
        final chip = chipAt(
          tester,
          'export-format-channels-${channels.jsonValue}',
        );
        expect(
          chip.onTap,
          isNull,
          reason:
              'a refused value keeps its place and loses its tap '
              '(⛔없다가 생기는 UI 금지)',
        );
      }
      expect(
        selectedIn(tester, 'export-format-channels', [
          for (final channels in ExportChannels.values) channels.jsonValue,
        ]),
        ExportChannels.rgba.jsonValue,
        reason: 'refusing to CHANGE is not refusing to show the answer',
      );
    });
  });
}
