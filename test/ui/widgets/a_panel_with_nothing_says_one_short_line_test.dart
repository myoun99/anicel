// A PANEL WITH NOTHING TO SHOW SAYS ONE SHORT LINE — in the program's
// language, in the one look, where its first row would be.
//
// 유저 2026-09-15: 「공용 위젯 하나 + 짧은 한 줄」 (empty-state-law-Q1) and
// 「내용이 올 자리에」 (empty-state-placement-Q1).
//
// ⚠️It pumps the panels, not the widget that draws the line: three of them
// said it in English whatever the language, each in a size of its own, and
// one said it in the middle with a usage sentence under it. Only a pump of
// the panel sees that.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tool_library_panel.dart';
import 'package:anicel/src/ui/export/export_job.dart';
import 'package:anicel/src/ui/export/export_preset_rail.dart';
import 'package:anicel/src/ui/export/export_queue_column.dart';
import 'package:anicel/src/ui/media/media_pool_panel.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

void main() {
  group('one line — no usage sentence under it, in any language', () {
    final lines = <String, String Function(AppStrings)>{
      'tlNoLayers': (s) => s.tlNoLayers,
      'noCutSelected': (s) => s.noCutSelected,
      'guideLibraryEmpty': (s) => s.guideLibraryEmpty,
      'mediaViewerEmpty': (s) => s.mediaViewerEmpty,
      'toolCutNothingHeld': (s) => s.toolCutNothingHeld,
    };
    for (final MapEntry(key: name, value: read) in lines.entries) {
      test(name, () {
        for (final strings in AppStrings.values) {
          expect(
            read(strings),
            isNot(contains('\n')),
            reason: '$name in ${strings.name}',
          );
        }
      });
    }
  });

  group('in Korean, where the first row would be, in the one look', () {
    setUp(
      () => AppText.settings.value = const AppLanguageSettings(
        programLanguage: AppLanguage.ko,
      ),
    );
    tearDown(() => AppText.settings.value = const AppLanguageSettings());

    Future<void> pumpPanel(WidgetTester tester, Widget panel) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(width: 260, height: 400, child: panel),
            ),
          ),
        );

    void expectTheLine(WidgetTester tester, String line) {
      final text = find.text(line);
      expect(text, findsOneWidget);
      final align = tester.widget<Align>(
        find.ancestor(of: text, matching: find.byType(Align)).first,
      );
      expect(align.alignment, Alignment.topLeft);
      final theme = Theme.of(tester.element(text));
      final style = tester.widget<Text>(text).style;
      expect(style?.fontSize, theme.textTheme.bodySmall?.fontSize);
      expect(style?.color, theme.colorScheme.onSurfaceVariant);
    }

    testWidgets('the render queue', (tester) async {
      final queue = ExportQueueModel();
      addTearDown(queue.dispose);
      await pumpPanel(tester, ExportQueueColumn(queue: queue, enabled: true));
      expectTheLine(tester, '큐에 작업이 없습니다');
    });

    testWidgets('the presets', (tester) async {
      await pumpPanel(
        tester,
        ExportPresetRail(
          tab: ExportTab.image,
          presets: const [],
          currentSpec: const ImageExportSpec(),
          enabled: true,
          onApply: (preset) {},
          onSaveCurrent: () {},
          onDelete: (preset) {},
        ),
      );
      expectTheLine(tester, '프리셋이 없습니다');
    });

    testWidgets('the media pool', (tester) async {
      await pumpPanel(
        tester,
        MediaPoolPanel(
          assets: const [],
          usesOf: (path) => const <String>[],
          onImportRequested: () {},
          onRenameAsset: (path, name) {},
          onRelinkAsset: (oldPath, newPath, grants) {},
          onRemoveAsset: (path) => true,
          onPromoteAsset: (path) async => true,
          onExportAssetWav: (asset) async => true,
        ),
      );
      expectTheLine(tester, '미디어가 없습니다');
    });

    testWidgets('the tool library, for a tool with no library', (tester) async {
      await pumpPanel(
        tester,
        const ToolLibraryPanel(
          tool: CanvasTool.eyedropper,
          brushLibrary: SizedBox.shrink(),
        ),
      );
      expectTheLine(tester, '표시할 것이 없습니다');
    });
  });
}
