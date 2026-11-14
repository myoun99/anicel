// A PICTURE'S NUMBERED RUN COMES IN AS ONE LAYER (I-76).
//
// 🗣️유저 2026-10-06: 「A1 임포트하면 A2,A3같은 파일들 인식해서 다 새 레이어가
// 아니라 새 레이어의 새 프레임으로서? 동영상이나 뭐 그런거에서 쓰는거 법
// 통일」 · I-76-Q1 (10-08): 「창의 그 파일 줄에서 고른다(기본: 함께)」 —
// 「A1-A3 이렇게 한 레이어의 세 프레임으로 인식하는 느낌」.
//
// F-392 (10-17): 「그냥 A면 이라는거 없이 숫자면 연속되도록」 · 「중간에
// 해상도 다른거만나면 항목으로서 독립시키도록」 — a run is the pictures named
// the same but for their last number (`pictureRunOf`), as far as they hold
// one size, and it lands the way an animated picture does: one layer, a
// picture the one before it showed folding into that one's exposure.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/import/import_file_table.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/app_tooltip.dart';
import 'package:anicel/src/ui/widgets/boolean_dot.dart';
import 'package:anicel/src/ui/widgets/transport_bar.dart';

import '../../helpers/import_warnings.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/wait_window.dart';
import '../../helpers/import_span.dart';
import '../../helpers/text_finders.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-numbered-run');
  });

  tearDown(() => deleteTempQuietly(tempDir));
  tearDown(SummonedTooltip.dismiss);

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

  /// What a cell reads — a button's word, or the dash of a question that
  /// does not apply.
  String cellText(WidgetTester tester, String column, String path) {
    final cell = find.byKey(ValueKey<String>('import-cell-$column-$path'));
    final widget = tester.widget(cell);
    if (widget is Text) {
      return widget.data!;
    }
    return tester
        .widget<Text>(find.descendant(of: cell, matching: find.anyText()))
        .data!;
  }

  /// The window on [paths], once the pictures each of [runs] runs with are
  /// measured — every picked path, unless the test names fewer: a run is
  /// known when its sizes are (F-392). The window is [width] wide: past
  /// what its two zones ask together, the list is laid out as wide as it
  /// asks to be rather than as wide as the window lets it.
  Future<EditorSessionManager> open(
    WidgetTester tester,
    List<String> paths, {
    List<String>? runs,
    double width = 1400,
  }) async {
    tester.view.physicalSize = Size(width, 1600);
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
    expect(
      await settleAsync(
        tester,
        () => (runs ?? paths).every(
          (path) => cellText(tester, 'option', path) != '—',
        ),
        step: const Duration(milliseconds: 50),
      ),
      isTrue,
      reason: '⛔fixture: each run is measured',
    );
    return s;
  }

  /// Places what the window holds, and answers the layers that brought —
  /// by id: the default project has an `A` of its own. It waits out the
  /// wait window, so it ends by stopping playback's warmer
  /// (`pumpPastTheWaitWindow`) — for every test that places through it.
  Future<List<Layer>> place(WidgetTester tester, EditorSessionManager s) async {
    final before = {for (final layer in s.requireActiveCut.layers) layer.id};
    List<Layer> added() => [
      for (final layer in s.requireActiveCut.layers)
        if (!before.contains(layer.id)) layer,
    ];
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);
    await settleAsync(tester, () => added().isNotEmpty);
    await tester.pumpAndSettle();
    s.playbackRig.prerenderScheduler.cancel();
    return added();
  }

  testWidgets('the row says the run it would bring, and a picture alone in '
      'its symbol says nothing', (tester) async {
    final files = await writeFolder(tester);
    await open(
      tester,
      [files['A1']!, files['B1']!],
      runs: [files['A1']!],
    );

    expect(
      cellText(tester, 'option', files['A1']!),
      AppText.strings.imRunSpan('A1', 'A3', 3),
    );
    expect(cellText(tester, 'option', files['B1']!), '—');
  });

  testWidgets('numbers alone run too: `1` · `2` come in as one layer named by '
      'their folder, its frames by their numbers (F-392)', (tester) async {
    final files = (await tester.runAsync(() async {
      final folder = await Directory(
        '${tempDir.path}${Platform.pathSeparator}walk',
      ).create();
      return [
        await writeSolidPng(folder, '1.png', rgba: 0x112233FF),
        await writeSolidPng(folder, '2.png', rgba: 0x445566FF),
      ];
    }))!;
    final s = await open(tester, [files.first]);
    expect(
      cellText(tester, 'option', files.first),
      AppText.strings.imRunSpan('1', '2', 2),
    );

    final added = await place(tester, s);

    expect(added, hasLength(1));
    expect(added.single.name, 'walk');
    expect([for (final frame in added.single.frames) frame.name], ['1', '2']);
  });

  testWidgets('🚨a picture of another size stops the run: each side of it '
      'comes in as its own layer, and it alone (F-392: 「중간에 해상도 '
      '다른거만나면 항목으로서 독립시키도록」)', (tester) async {
    final files = (await tester.runAsync(() async {
      return {
        for (final (index, name) in ['A1', 'A2', 'A3', 'A4', 'A5'].indexed)
          name: await writeSolidPng(
            tempDir,
            '$name.png',
            width: name == 'A3' ? 16 : 8,
            rgba: 0x10203000 + index * 0x10 + 0xF,
          ),
      };
    }))!;
    final s = await open(
      tester,
      [files['A1']!, files['A3']!, files['A5']!],
      runs: [files['A1']!, files['A5']!],
    );
    expect(
      cellText(tester, 'option', files['A1']!),
      AppText.strings.imRunSpan('A1', 'A2', 2),
    );
    expect(
      cellText(tester, 'option', files['A5']!),
      AppText.strings.imRunSpan('A4', 'A5', 2),
    );
    expect(cellText(tester, 'option', files['A3']!), '—');

    final added = await place(tester, s);

    expect(
      [for (final layer in added) (layer.name, layer.frames.length)],
      unorderedEquals([('A', 2), ('A', 2), ('A3', 1)]),
    );
    expect(
      [
        for (final layer in added)
          if (layer.name == 'A') [for (final frame in layer.frames) frame.name],
      ],
      unorderedEquals([
        ['1', '2'],
        ['4', '5'],
      ]),
    );
  });

  // ↩️「a run's word is never cut — its column is as wide as the widest word
  // a row says」 (I-76). 🗣️F-582, 유저 2026-11-10: 「옵션행이 길이에 따라
  // 커져서 임포트창이 커지는데, 해당 옵션행은 고정길이로 둬서 길어지면 …
  // 생략. 풀네임은 호버해서 툴팁으로 알도록」 — the option column keeps one
  // room whatever the files are named.
  testWidgets('🚨a run of long names widens nothing: its span is cut where '
      'the option column\'s room ends and says its whole on a hover, and a '
      'span the room holds is whole (F-582)', (tester) async {
    const long = 'background_street_night_take';
    final (short, wide) = (await tester.runAsync(() async {
      await writeSolidPng(tempDir, 'ABCD123.png');
      await writeSolidPng(tempDir, '${long}0002.png');
      return (
        await writeSolidPng(tempDir, 'ABCD1.png'),
        await writeSolidPng(tempDir, '${long}0001.png'),
      );
    }))!;
    RenderParagraph spanOf(String path) => tester.renderObject(
      find.descendant(
        of: find.byKey(ValueKey<String>('import-cell-option-$path')),
        matching: find.anyRichText(),
      ),
    );
    final list = find.byType(ImportFileTable);
    double listWidth() => tester.getSize(list).width;
    // What the list asks to be, of the rows and columns it was given.
    double asked() {
      final table = tester.widget<ImportFileTable>(list);
      return ImportFileTable.preferredWidth(
        tester.element(list),
        rows: table.rows,
        columns: table.columns,
        leadWidth: table.leadWidth,
      );
    }

    // A window with room for what the list asks: in a narrower one the
    // list is as wide as the window lets it, whatever its rows say.
    const roomy = 3000.0;
    await open(tester, [short], width: roomy);
    expect(
      cellText(tester, 'option', short),
      AppText.strings.imRunSpan('ABCD1', 'ABCD123', 2),
      reason: '⛔전제: a word longer than either answer\'s',
    );
    expect(listWidth(), asked(), reason: '⛔전제: as wide as it asks to be');
    expect(spanOf(short).didExceedMaxLines, isFalse, reason: 'it fits');
    final width = listWidth();

    await tester.pumpWidget(const SizedBox());
    await open(tester, [short, wide], width: roomy);
    final whole = AppText.strings.imRunSpan('${long}0001', '${long}0002', 2);
    expect(cellText(tester, 'option', wide), whole);
    expect(listWidth(), asked(), reason: '⛔전제: as wide as it asks to be');
    expect(listWidth(), width, reason: 'the list is no wider for the run');
    expect(spanOf(short).didExceedMaxLines, isFalse);
    expect(spanOf(wide).didExceedMaxLines, isTrue, reason: 'cut at the room');

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await tester.pump();
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(ValueKey<String>('import-cell-option-$wide')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(SummonedTooltip.debugShownMessage, whole);
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
    await keepImportSpan(tester, 2, 3);

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
    await keepImportSpan(tester, 2, 2);
    expect(cellText(tester, 'option', files['A1']!), 'A2');

    await keepImportSpan(tester, 2, 3);

    expect(
      cellText(tester, 'option', files['A1']!),
      AppText.strings.imRunSpan('A2', 'A3', 2),
    );
  });

  testWidgets('IN and OUT on ONE picture: that picture comes in alone, as a '
      'picture always did — whichever one they stood on', (tester) async {
    final files = await writeFolder(tester);
    final s = await open(tester, [files['A1']!]);
    await keepImportSpan(tester, 2, 2);

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
    await keepImportSpan(tester, 2, 2);

    expect(answerable(), isTrue);
    await tester.tap(bake);
    await tester.pumpAndSettle();
    expect(cellText(tester, 'bake', files['A1']!), AppText.strings.commonOn);
    await tester.tap(bake);
    await tester.pumpAndSettle();
    expect(cellText(tester, 'bake', files['A1']!), AppText.strings.commonOff);
  });

  testWidgets('Import pressed before the run is measured waits for it — two '
      'of its pictures picked together still bring it once', (tester) async {
    final files = await writeFolder(tester);
    final s = await open(
      tester,
      [files['A1']!, files['A3']!],
      runs: const [],
    );
    expect(
      cellText(tester, 'option', files['A1']!),
      '—',
      reason: '⛔fixture: its pictures are not measured yet',
    );

    final added = await place(tester, s);

    expect(added, hasLength(1), reason: 'the run, once');
    expect([for (final frame in added.single.frames) frame.name], ['1', '3']);
  });

  testWidgets('two pictures of one run picked together bring it once',
      (tester) async {
    final files = await writeFolder(tester);
    final s = await open(tester, [files['A1']!, files['A3']!]);

    final added = await place(tester, s);

    expect(added, hasLength(1));
    expect(added.single.frames, hasLength(2));
  });

  testWidgets('a picture of the run gone by the time Import is pressed is '
      'named in the warnings the status line opens — and the rest of the run '
      'still comes in', (tester) async {
    final files = await writeFolder(tester);
    final s = await open(tester, [files['A1']!]);
    await tester.runAsync(() => File(files['A2']!).delete());

    final added = await place(tester, s);

    expect(added, hasLength(1), reason: 'the run, short of what is gone');
    final notice = await openImportWarnings(tester);
    expect(
      find.descendant(
        of: notice,
        matching: find.text('Could not read the file. (1)'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: notice, matching: find.text('A2.png')),
      findsOneWidget,
    );
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
    ('span\'s start', (tester, _) => keepImportSpan(tester, 2, 3)),
    ('span\'s end', (tester, _) => keepImportSpan(tester, 1, 2)),
    (
      'place',
      // A new cut takes its picture 1:1 (`importFitLocked`) and the other
      // row starts 1:1 ([MediaFitMode.born]): the rows differ in where they
      // go alone.
      (tester, files) => answer(tester, 'into', files['A1']!, 'newCut'),
    ),
    ('fit', (tester, files) => answer(tester, 'fit', files['A1']!, 'stretch')),
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
      await settleAsync(tester, () => brought().length >= 2);
      await tester.pumpAndSettle();

      expect(brought(), hasLength(2), reason: 'each row brings its own');
      s.playbackRig.prerenderScheduler.cancel();
    });
  }
}
