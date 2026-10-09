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
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/boolean_dot.dart';
import 'package:anicel/src/ui/widgets/transport_bar.dart';

import '../../helpers/settle_async.dart';
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

  /// Places what the window holds, and answers the layers that brought —
  /// by id: the default project has an `A` of its own.
  Future<List<Layer>> place(WidgetTester tester, EditorSessionManager s) async {
    final before = {for (final layer in s.requireActiveCut.layers) layer.id};
    List<Layer> added() => [
      for (final layer in s.requireActiveCut.layers)
        if (!before.contains(layer.id)) layer,
    ];
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);
    for (var tries = 0; tries < 100 && added().isEmpty; tries += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    return added();
  }

  testWidgets('the row says the run it would bring, and a picture alone in '
      'its symbol says nothing', (tester) async {
    final files = await writeFolder(tester);
    await open(tester, [files['A1']!, files['B1']!]);

    expect(
      cellText(tester, 'option', files['A1']!),
      AppText.strings.imRunSpan('A1', 'A3', 3),
    );
    expect(cellText(tester, 'option', files['B1']!), '—');
  });

  testWidgets('a run\'s word is never cut — its column is as wide as the '
      'widest word a row says, not only its answers\'', (tester) async {
    final paths = (await tester.runAsync(
      () async => [
        await writeSolidPng(tempDir, 'ABCD1.png'),
        await writeSolidPng(tempDir, 'ABCD123.png'),
      ],
    ))!;
    await open(tester, [paths.first]);
    final cell = find.byKey(ValueKey<String>('import-cell-option-${paths.first}'));
    expect(
      cellText(tester, 'option', paths.first),
      AppText.strings.imRunSpan('ABCD1', 'ABCD123', 2),
      reason: '⛔전제: a word longer than either answer\'s',
    );

    final word = tester.renderObject<RenderParagraph>(
      find.descendant(of: cell, matching: find.byType(RichText)),
    );
    expect(word.didExceedMaxLines, isFalse, reason: 'the word fits its line');
  });

  testWidgets('🚨together, the run is ONE layer named by its symbol, its '
      'frames by their numbers — the same picture twice is one cel held '
      'twice, and baked, no file of it is in the pool', (tester) async {
    final files = await writeFolder(tester);
    final s = await open(tester, [files['A1']!]);

    final added = await place(tester, s);

    expect(added, hasLength(1), reason: 'one layer for the whole run');
    final run = added.single;
    expect(run.name, 'A');
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
        isNull,
        reason: '$name is baked into the run — a baked placement registers '
            'nothing (F-282-Q6; ↩️each registered on its own)',
      );
    }
  });

  /// Stands the preview's IN on picture [from] and its OUT on [to] — one-
  /// based, as the transport shows them — for the row it previews.
  Future<void> span(WidgetTester tester, int from, int to) async {
    await settleLoadedPages(tester);
    for (final (end, at) in [('in', from), ('out', to)]) {
      await tester.tap(find.byKey(ValueKey<String>('transport-$end')));
      await tester.pump();
      await tester.enterText(
        find.byKey(ValueKey<String>('transport-$end-input')),
        '$at',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settleLoadedPages(tester);
    }
  }

  // 🗣️F-282 (유저 2026-10-09, 시안 ③ · ④): 「연번은 들어갈 범위만(A2–A3) —
  // 미리보기의 IN/OUT, 동영상과 같은 법」 · 한 장만 = IN 과 OUT 이 같은 장.
  // ↩️「함께 / 이 파일만」 in the cell.
  int previewPages(WidgetTester tester) =>
      tester.widget<TransportBar>(find.byType(TransportBar)).frameCount;

  String? plate(WidgetTester tester) => tester
      .widget<BrushCanvasPanel>(find.byType(BrushCanvasPanel))
      .documentName;

  testWidgets('the preview pages through the run — its transport counts the '
      'run\'s pictures, and its plate names the one stood on',
      (tester) async {
    final files = await writeFolder(tester);
    await open(tester, [files['A1']!]);
    await settleLoadedPages(tester);

    expect(previewPages(tester), 3, reason: 'A1 · A2 · A3, a page each');
    expect(plate(tester), 'A1.png');

    await tester.tap(
      find.byKey(const ValueKey<String>('transport-step-forward')),
    );
    await settleLoadedPages(tester);

    expect(plate(tester), 'A2.png', reason: '시안: 「A2.png · 2 / 3」');
  });

  testWidgets('a row that only registers is no run: the preview shows its '
      'own file', (tester) async {
    final files = await writeFolder(tester);
    await open(tester, [files['A1']!]);
    final into = find.byKey(
      ValueKey<String>('import-cell-into-${files['A1']}'),
    );
    await tester.ensureVisible(into);
    await settleLoadedPages(tester);
    expect(previewPages(tester), 3, reason: '⛔전제: placed, it is its run');

    await tester.tap(into);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('import-option-into-pool')),
    );
    await settleLoadedPages(tester);

    expect(previewPages(tester), 1, reason: 'registering brings the file in '
        'as it is');
    expect(cellText(tester, 'option', files['A1']!), '—');
  });

  testWidgets('IN and OUT keep a span of the run: A2–A3 come in as one '
      'layer of those two', (tester) async {
    final files = await writeFolder(tester);
    final s = await open(tester, [files['A1']!]);
    await span(tester, 2, 3);

    expect(
      cellText(tester, 'option', files['A1']!),
      AppText.strings.imRunSpan('A2', 'A3', 2),
    );
    final added = await place(tester, s);

    expect(added, hasLength(1));
    expect(added.single.name, 'A');
    expect([for (final frame in added.single.frames) frame.name], ['2', '3']);
  });

  testWidgets('OUT walked back to the run\'s last picture keeps to its end',
      (tester) async {
    final files = await writeFolder(tester);
    await open(tester, [files['A1']!]);
    await span(tester, 2, 2);
    expect(cellText(tester, 'option', files['A1']!), 'A2');

    await span(tester, 2, 3);

    expect(
      cellText(tester, 'option', files['A1']!),
      AppText.strings.imRunSpan('A2', 'A3', 2),
    );
  });

  testWidgets('IN and OUT on ONE picture: that picture comes in alone, as a '
      'picture always did — whichever one they stood on', (tester) async {
    final files = await writeFolder(tester);
    final s = await open(tester, [files['A1']!]);
    await span(tester, 2, 2);

    expect(cellText(tester, 'option', files['A1']!), 'A2');
    expect(
      cellText(tester, 'bake', files['A1']!),
      AppText.strings.commonOff,
      reason: 'one picture answers its own bake',
    );
    final added = await place(tester, s);

    expect(added, hasLength(1));
    expect(added.single.name, 'A2', reason: 'the picture\'s own layer');
    expect(added.single.frames, hasLength(1));
    final project = s.repository.requireProject();
    expect(
      project.mediaAssetByPath(normalizedMediaPath(files['A2']!)),
      isNotNull,
      reason: 'drawn from its file, it is kept — as any picture placed',
    );
    expect(
      project.mediaAssetByPath(normalizedMediaPath(files['A1']!)),
      isNull,
      reason: 'nothing of the run but that picture came in',
    );
  });

  testWidgets('IN and OUT on one picture leave its bake to the row — two or '
      'more always bake', (tester) async {
    final files = await writeFolder(tester);
    await open(tester, [files['A1']!]);
    final bake = find.byKey(
      ValueKey<String>('import-cell-bake-${files['A1']}'),
    );
    bool answerable() => tester
        .widget<BooleanDot>(
          find.descendant(of: bake, matching: find.byType(BooleanDot)),
        )
        .enabled;
    await tester.ensureVisible(bake);
    await settleLoadedPages(tester);
    expect(
      cellText(tester, 'bake', files['A1']!),
      AppText.strings.commonOn,
      reason: '⛔전제: the whole run bakes',
    );
    expect(answerable(), isFalse, reason: 'locked: the run has one answer');
    await span(tester, 2, 2);

    expect(answerable(), isTrue);
    await tester.tap(bake);
    await tester.pumpAndSettle();
    expect(cellText(tester, 'bake', files['A1']!), AppText.strings.commonOn);
    await tester.tap(bake);
    await tester.pumpAndSettle();
    expect(cellText(tester, 'bake', files['A1']!), AppText.strings.commonOff);
  });

  testWidgets('two pictures of one run picked together bring it once',
      (tester) async {
    final files = await writeFolder(tester);
    final s = await open(tester, [files['A1']!, files['A3']!]);

    final added = await place(tester, s);

    expect(added, hasLength(1));
    expect(added.single.frames, hasLength(2));
  });

  /// Answers [option] in [column] for [path]'s row alone.
  Future<void> answer(
    WidgetTester tester,
    String column,
    String path,
    String option,
  ) async {
    final cell = find.byKey(ValueKey<String>('import-cell-$column-$path'));
    await tester.ensureVisible(cell);
    await settleLoadedPages(tester);
    await tester.tap(cell);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey<String>('import-option-$column-$option')),
    );
    await tester.pumpAndSettle();
  }

  // A row brings what its cells say: two rows of one run bring one layer
  // only when they would hand the run's door the same — the span, where it
  // goes, how it fits (`importPictureRun` reads those two answers).
  for (final (differs, answerOtherwise) in <(
    String,
    Future<void> Function(WidgetTester, Map<String, String> files),
  )>[
    ('span\'s start', (tester, _) => span(tester, 2, 3)),
    ('span\'s end', (tester, _) => span(tester, 1, 2)),
    (
      'place',
      (tester, files) async {
        // A new cut takes its picture 1:1 (`importFitLocked`), so the other
        // row is answered 1:1 too: the rows differ in where they go alone.
        await answer(tester, 'fit', files['A3']!, 'none');
        await answer(tester, 'into', files['A1']!, 'newCut');
      },
    ),
    ('fit', (tester, files) => answer(tester, 'fit', files['A1']!, 'none')),
  ]) {
    testWidgets('two pictures of one run whose rows answer otherwise — '
        'another $differs — bring a layer each', (tester) async {
      final files = await writeFolder(tester);
      final s = await open(tester, [files['A1']!, files['A3']!]);
      List<Object> runLayers() => [
        for (final track in s.repository.requireProject().tracks)
          for (final cut in track.cuts)
            for (final layer in cut.layers)
              if (layer.name == 'A') layer.id,
      ];
      final before = runLayers().toSet();
      // The preview shows the first row while none is picked: A1's.
      await answerOtherwise(tester, files);

      await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
      await pumpPastTheWaitWindow(tester);
      List<Object> brought() => [
        for (final id in runLayers())
          if (!before.contains(id)) id,
      ];
      for (var tries = 0; tries < 100 && brought().length < 2; tries += 1) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(brought(), hasLength(2), reason: 'each row brings its own');
    });
  }
}
