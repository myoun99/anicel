import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';

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
    await tester.pump();
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
    for (final id in ['bake', 'into', 'fit', 'psd']) {
      expect(column(id), findsNothing, reason: id);
    }

    await tester.tap(cell('file', png));
    await tester.pumpAndSettle();
    expect(openOptions(), {
      'import-option-file-reference',
      'import-option-file-keepInside',
    });
  });

  testWidgets('a NEW file placed on the timeline is asked how it is kept, '
      'whether it is baked, where it goes and how it fits — and PSD only when '
      'a PSD is in the batch (「PSD가 아닌파일은 PSD열 삭제」)', (tester) async {
    final png = await tester.runAsync(() => writePng('a.png'));
    await open(tester, session(), [png!]);

    for (final id in ['file', 'bake', 'into', 'fit']) {
      expect(column(id), findsOneWidget, reason: id);
    }
    expect(column('psd'), findsNothing);
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

    await tester.tap(
      find.byKey(const ValueKey<String>('import-place-pool')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(
      column('bake'),
      findsOneWidget,
      reason: 'the pool pill is disabled here: the window is still placing',
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

    expect(cellWord(tester, 'fit', png), '1:1');
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

  testWidgets('a sound among pictures answers only what a sound can: its '
      'place is the SE rows, locked (「소리파일: 추천대로 통일」), and bake '
      'and fit are dashes on its row', (tester) async {
    final png = await tester.runAsync(() => writePng('a.png'));
    final wav = await tester.runAsync(() => writeWav('se.wav'));
    await open(tester, session(), [png!, wav!]);

    expect(cellWord(tester, 'into', wav), AppText.strings.imIntoSeRow);
    await tester.ensureVisible(cell('into', wav));
    await tester.pumpAndSettle();
    await tester.tap(cell('into', wav), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(openOptions(), isEmpty, reason: 'the SE rows\' rule answered it');
    for (final id in ['bake', 'fit']) {
      expect(cellWord(tester, id, wav), '—', reason: id);
    }
  });

  testWidgets('a batch of nothing but sound asks no picture question at all '
      '— its one placement answer, the SE rows, is shown', (tester) async {
    final wav = await tester.runAsync(() => writeWav('se.wav'));
    await open(tester, session(), [wav!]);

    for (final id in ['bake', 'fit', 'psd']) {
      expect(column(id), findsNothing, reason: id);
    }
    expect(column('into'), findsOneWidget);
    expect(cellWord(tester, 'into', wav), AppText.strings.imIntoSeRow);
    expect(column('file'), findsOneWidget);
  });
}
