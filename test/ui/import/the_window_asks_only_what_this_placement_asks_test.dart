import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/core/path_names.dart' show fileNameOfPath;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/settle_async.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/wait_window.dart';

/// 🚨THE COLUMN LAW of the import/placement window (유저 2026-09-11, 미디어
/// 배치 라운드 5·6): a column stands only when some row of THIS window has
/// to answer it — 「즉 필요없는것들 안보이게 삭제해도됨」. Place, where the
/// window was opened from and the kinds in it decide that.
///
/// And the other half: a value the CONTEXT answered stays on screen, locked
/// — 「1:1로 고정시켜서 노출시키도록. 비활성화된상태로」. Only a question this
/// placement does not ask is gone.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-columns');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  Future<String> writePng(String name) =>
      writeSolidPng(tempDir, name, rgba: 0xAAAAAAAA);

  Future<String> writeWav(String name) async {
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(const [0x52, 0x49, 0x46, 0x46]);
    return file.path;
  }

  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  Future<void> open(
    WidgetTester tester,
    EditorSessionManager s,
    List<String> paths, {
    bool poolOnly = false,
    bool placeOnly = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(
            session: s,
            initialPaths: paths,
            poolOnly: poolOnly,
            placeOnly: placeOnly,
          ),
        ),
      ),
    );
    await settleLoadedPages(tester);
  }

  Finder column(String id) =>
      find.byKey(ValueKey<String>('import-column-$id'));
  Finder cell(String id, String path) =>
      find.byKey(ValueKey<String>('import-cell-$id-$path'));
  String cellWord(WidgetTester tester, String id, String path) {
    final widget = tester.widget(cell(id, path));
    if (widget is Text) {
      return widget.data!;
    }
    return tester
        .widget<Text>(
          find.descendant(of: cell(id, path), matching: find.byType(Text)),
        )
        .data!;
  }

  Set<String> openOptions() => {
    for (final element in find
        .byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'import-option-',
              ),
        )
        .evaluate())
      (element.widget.key! as ValueKey<String>).value,
  };

  testWidgets('🚨the pool asks ONE question and offers exactly two answers — '
      'carry or link (「팝오버의 래스터버튼을 아예 삭제해서 품기/참조 버튼만 '
      '있도록」)', (tester) async {
    final png = await tester.runAsync(() => writePng('a.png'));
    await open(tester, session(), [png!], poolOnly: true);

    expect(column('file'), findsOneWidget);
    // A pool's door asks no placement's questions — they cannot be asked
    // there at all (유저 2026-10-09: 「미디어패널의 경우엔 굽기 맞춤 옵션
    // 안넣어도되」).
    for (final id in ['bake', 'fit', 'option']) {
      expect(column(id), findsNothing, reason: id);
    }
    // Where it goes is said — the pool, locked (F-282: the strip's 「풀」
    // came down to the row).
    expect(column('into'), findsOneWidget);
    expect(cellWord(tester, 'into', png), AppText.strings.panelMedia);
    await tester.tap(cell('into', png), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(openOptions(), isEmpty, reason: 'the door answered it');

    await tester.tap(cell('file', png));
    await tester.pumpAndSettle();
    expect(openOptions(), {
      'import-option-file-reference',
      'import-option-file-keepInside',
    });
  });

  testWidgets('a NEW file placed on the timeline is asked how it is kept, '
      'whether it is baked, where it goes, how it fits and its kind\'s own '
      'question — a dash, for a plain picture', (tester) async {
    final png = await tester.runAsync(() => writePng('a.png'));
    await open(tester, session(), [png!]);

    for (final id in ['file', 'bake', 'into', 'fit', 'option']) {
      expect(column(id), findsOneWidget, reason: id);
    }
    expect(
      cellWord(tester, 'option', png),
      '—',
      reason: 'a plain picture is asked no kind\'s own question — the PSD '
          'column that stood for one kind is a cell of the 옵션 column now',
    );
    expect(
      cellWord(tester, 'bake', png),
      AppText.strings.commonOff,
      reason: 'a placed file is a reference until someone asks to bake it',
    );
  });

  testWidgets('🚨a file the pool already holds is not asked the pool\'s '
      'question, and the window will not turn back into the pool (「미디어풀에 '
      '있던걸 타임라인 등 드래그앤드롭할때는 플레이스의 풀을 비활성화하고 … '
      '품기/참조인 그 열 자체를 삭제」)', (tester) async {
    final png = await tester.runAsync(() => writePng('bg.png'));
    final s = session();
    await s.mediaPool.importMediaFiles([png!], copyIntoProject: true);
    await open(tester, s, [png], placeOnly: true);

    expect(column('file'), findsNothing);
    expect(column('bake'), findsOneWidget);

    await tester.ensureVisible(cell('into', png));
    await tester.pumpAndSettle();
    await tester.tap(cell('into', png));
    await tester.pumpAndSettle();
    expect(
      openOptions(),
      contains('import-option-into-pool'),
      reason: 'the pool is shown — dim: there is nothing left to register',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('import-option-into-pool')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(
      cellWord(tester, 'into', png),
      AppText.strings.imIntoNewLayer,
      reason: 'pressing it changed nothing: the row is still placed',
    );
  });

  testWidgets('🚨a NEW cut is made at the file\'s own size, so its fit shows '
      '1:1 — locked, not hidden (「1:1로 고정시켜서 노출시키도록. '
      '비활성화된상태로」)', (tester) async {
    final png = await tester.runAsync(() => writePng('a.png'));
    await open(tester, session(), [png!]);

    // The table scrolls sideways when its columns outgrow the window (the
    // test font's glyphs are wide), so a cell is brought into view first.
    await tester.ensureVisible(cell('into', png));
    await tester.pumpAndSettle();
    await tester.tap(cell('into', png));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('import-option-into-newCut')),
    );
    await tester.pumpAndSettle();

    expect(cellWord(tester, 'fit', png), AppText.strings.imFitOriginal);
    await tester.ensureVisible(cell('fit', png));
    await tester.pumpAndSettle();
    await tester.tap(cell('fit', png), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(openOptions(), isEmpty, reason: 'a locked cell opens nothing');
  });

  testWidgets('in a mixed batch the pooled file shows the POOL\'s answer, '
      'locked, while the new file is asked', (tester) async {
    final pooled = await tester.runAsync(() => writePng('pooled.png'));
    final fresh = await tester.runAsync(() => writePng('fresh.png'));
    final s = session();
    await s.mediaPool.importMediaFiles([pooled!], copyIntoProject: false);
    await open(tester, s, [pooled, fresh!]);

    expect(column('file'), findsOneWidget, reason: 'the new file needs it');
    expect(
      cellWord(tester, 'file', pooled),
      AppText.strings.imModeReference,
      reason: 'the pool linked it, and the window says so',
    );
    await tester.tap(cell('file', pooled), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(openOptions(), isEmpty, reason: 'and it is not the window\'s');
  });

  testWidgets('a sound among pictures answers only what a sound can: its one '
      'placement is the SE rows (「소리파일: 추천대로 통일」) — or the pool — '
      'and bake and fit are dashes on its row', (tester) async {
    final png = await tester.runAsync(() => writePng('a.png'));
    final wav = await tester.runAsync(() => writeWav('se.wav'));
    await open(tester, session(), [png!, wav!]);

    expect(cellWord(tester, 'into', wav), AppText.strings.imIntoSeRow);
    await tester.ensureVisible(cell('into', wav));
    await tester.pumpAndSettle();
    await tester.tap(cell('into', wav));
    await tester.pumpAndSettle();
    expect(openOptions(), {
      'import-option-into-se-rows',
      'import-option-into-pool',
    }, reason: 'no layer and no cut: a sound is placed on the SE rows');
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    for (final id in ['bake', 'fit']) {
      expect(cellWord(tester, id, wav), '—', reason: id);
    }
  });

  testWidgets('a batch of nothing but sound still shows the placement\'s '
      'questions, each a dash — they stand, every row or none (유저 '
      '2026-10-09: 「굽기/맞춤/옵션 다 보이는채로 ok」)', (tester) async {
    final wav = await tester.runAsync(() => writeWav('se.wav'));
    await open(tester, session(), [wav!]);

    for (final id in ['bake', 'fit']) {
      expect(column(id), findsOneWidget, reason: id);
      expect(cellWord(tester, id, wav), '—', reason: id);
    }
    expect(column('into'), findsOneWidget);
    expect(cellWord(tester, 'into', wav), AppText.strings.imIntoSeRow);
    expect(column('file'), findsOneWidget);
  });

  testWidgets('🎯a BAKED row is asked nothing about keeping its file — the '
      'file column is a dash, and the file stays out of the pool '
      '(F-282-Q6, 유저 2026-10-09: 구우면 풀에 안 남긴다)', (tester) async {
    final png = await tester.runAsync(() => writePng('baked.png'));
    final s = session();
    final layersBefore = s.requireActiveCut.layers.length;
    await open(tester, s, [png!]);
    expect(
      cellWord(tester, 'file', png),
      AppText.strings.imModeKeep,
      reason: 'CONTROL: a row the layer draws from is asked',
    );

    await tester.ensureVisible(cell('bake', png));
    await tester.pumpAndSettle();
    await tester.tap(cell('bake', png));
    await tester.pumpAndSettle();
    expect(cellWord(tester, 'bake', png), AppText.strings.commonOn);
    expect(cellWord(tester, 'file', png), '—');

    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);
    await tester.pumpAndSettle();

    expect(s.requireActiveCut.layers.length, layersBefore + 1);
    expect(
      s.mediaPool.mediaAssets,
      isEmpty,
      reason: 'the pixels are the layer\'s own — ↩️「구워도 풀에 남음」',
    );
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🎯one window places one file and registers another — each row '
      'as its 넣을 곳 says (F-282: 「풀/타임라인 이걸 하나로 합치는게 통일」)', (
    tester,
  ) async {
    final placed = await tester.runAsync(() => writePng('placed.png'));
    final kept = await tester.runAsync(() => writePng('kept.png'));
    final s = session();
    final layersBefore = s.requireActiveCut.layers.length;
    await open(tester, s, [placed!, kept!]);

    await tester.ensureVisible(cell('into', kept));
    await tester.pumpAndSettle();
    await tester.tap(cell('into', kept));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('import-option-into-pool')),
    );
    await tester.pumpAndSettle();
    expect(cellWord(tester, 'into', kept), AppText.strings.panelMedia);
    for (final id in ['bake', 'fit']) {
      expect(cellWord(tester, id, kept), '—', reason: id);
    }

    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);
    await tester.pumpAndSettle();

    expect(
      s.requireActiveCut.layers.length,
      layersBefore + 1,
      reason: 'one layer: the placed file\'s',
    );
    expect(
      {for (final asset in s.mediaPool.mediaAssets) fileNameOfPath(asset.path)},
      containsAll(['kept.png']),
      reason: 'the other only registered',
    );
    s.playbackRig.prerenderScheduler.cancel();
  });
}
