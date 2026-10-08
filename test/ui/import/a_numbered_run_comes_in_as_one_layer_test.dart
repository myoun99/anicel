// A PICTURE'S NUMBERED RUN COMES IN AS ONE LAYER (I-76).
//
// 🗣️유저 2026-10-06: 「A1 임포트하면 A2,A3같은 파일들 인식해서 다 새 레이어가
// 아니라 새 레이어의 새 프레임으로서? 동영상이나 뭐 그런거에서 쓰는거 법
// 통일」 · I-76-Q1 (10-08): 「창의 그 파일 줄에서 고른다(기본: 함께)」 —
// 「A1-A3 이렇게 한 레이어의 세 프레임으로 인식하는 느낌」.
//
// The run is read with the cut folder's grammar, and it lands the way an
// animated picture does: one layer, a picture the one before it showed
// folding into that one's exposure.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/wait_window.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-numbered-run');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  /// `A1` and `A2` the same picture, `A3` another, and `B1` alone.
  Future<Map<String, String>> writeFolder(WidgetTester tester) async =>
      (await tester.runAsync(() async {
        return {
          'A1': await writeSolidPng(tempDir, 'A1.png', rgba: 0x112233FF),
          'A2': await writeSolidPng(tempDir, 'A2.png', rgba: 0x112233FF),
          'A3': await writeSolidPng(tempDir, 'A3.png', rgba: 0x445566FF),
          'B1': await writeSolidPng(tempDir, 'B1.png', rgba: 0x778899FF),
        };
      }))!;

  Future<EditorSessionManager> open(
    WidgetTester tester,
    List<String> paths,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: s, initialPaths: paths),
        ),
      ),
    );
    await tester.pump();
    return s;
  }

  /// What a cell reads — a button's word, or the dash of a question that
  /// does not apply.
  String cellText(WidgetTester tester, String column, String path) {
    final cell = find.byKey(ValueKey<String>('import-cell-$column-$path'));
    final widget = tester.widget(cell);
    if (widget is Text) {
      return widget.data!;
    }
    return tester
        .widget<Text>(find.descendant(of: cell, matching: find.byType(Text)))
        .data!;
  }

  Future<void> place(
    WidgetTester tester,
    EditorSessionManager s, {
    required int layersAfter,
  }) async {
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);
    for (var tries = 0; tries < 100; tries += 1) {
      if (s.requireActiveCut.layers.length >= layersAfter) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Layer layerNamed(EditorSessionManager s, String name) =>
      s.requireActiveCut.layers.singleWhere((layer) => layer.name == name);

  testWidgets('the row says the run it would bring, and a picture alone in '
      'its symbol says nothing', (tester) async {
    final files = await writeFolder(tester);
    await open(tester, [files['A1']!, files['B1']!]);

    expect(
      cellText(tester, 'run', files['A1']!),
      AppText.strings.imRunSpan('A1', 'A3', 3),
    );
    expect(cellText(tester, 'run', files['B1']!), '—');
  });

  testWidgets('a folder with no run asks nothing about one', (tester) async {
    final path = (await tester.runAsync(
      () => writeSolidPng(tempDir, 'A1.png'),
    ))!;
    await open(tester, [path]);

    expect(
      find.byKey(const ValueKey<String>('import-column-run')),
      findsNothing,
      reason: 'a column stands only when some row has to answer it',
    );
  });

  testWidgets('🚨together, the run is ONE layer named by its symbol, its '
      'frames by their numbers — the same picture twice is one cel held '
      'twice, and every file is in the pool', (tester) async {
    final files = await writeFolder(tester);
    final s = await open(tester, [files['A1']!]);
    final layersBefore = s.requireActiveCut.layers.length;

    await place(tester, s, layersAfter: layersBefore + 1);

    expect(s.requireActiveCut.layers.length, layersBefore + 1);
    final run = layerNamed(s, 'A');
    expect([for (final frame in run.frames) frame.name], ['1', '3']);
    expect(
      {
        for (final entry in run.timeline.entries)
          entry.key: entry.value.length,
      },
      {0: 2, 2: 1},
      reason: 'A2 is A1 again: held, not drawn twice',
    );
    final project = s.repository.requireProject();
    for (final name in ['A1', 'A2', 'A3']) {
      expect(
        project.mediaAssetByPath(normalizedMediaPath(files[name]!)),
        isNotNull,
        reason: '$name registers on its own',
      );
    }
  });

  testWidgets('this file only: the picture comes in alone, as it always '
      'did', (tester) async {
    final files = await writeFolder(tester);
    final s = await open(tester, [files['A1']!]);
    final layersBefore = s.requireActiveCut.layers.length;
    final cell = find.byKey(ValueKey<String>('import-cell-run-${files['A1']}'));
    await tester.ensureVisible(cell);
    await tester.pumpAndSettle();
    await tester.tap(cell);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('import-option-run-alone')),
    );
    await tester.pumpAndSettle();
    expect(
      cellText(tester, 'run', files['A1']!),
      AppText.strings.imRunAlone,
    );

    await place(tester, s, layersAfter: layersBefore + 1);

    expect(s.requireActiveCut.layers.length, layersBefore + 1);
    expect(
      s.requireActiveCut.layers.where((layer) => layer.name == 'A'),
      isEmpty,
    );
    expect(
      s.repository.requireProject().mediaAssetByPath(
        normalizedMediaPath(files['A2']!),
      ),
      isNull,
      reason: 'nothing of the run but this file came in',
    );
  });

  testWidgets('two pictures of one run picked together bring it once',
      (tester) async {
    final files = await writeFolder(tester);
    final s = await open(tester, [files['A1']!, files['A3']!]);
    final layersBefore = s.requireActiveCut.layers.length;

    await place(tester, s, layersAfter: layersBefore + 1);

    expect(s.requireActiveCut.layers.length, layersBefore + 1);
    expect(layerNamed(s, 'A').frames, hasLength(2));
  });
}
