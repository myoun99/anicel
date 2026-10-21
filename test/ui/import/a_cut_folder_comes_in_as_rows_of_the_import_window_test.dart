import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/import/import_file_settings.dart';
import 'package:anicel/src/ui/import/import_file_table.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/layer_rail_columns.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

import '../../helpers/carried_media_fixture.dart';
import '../../helpers/import_warnings.dart';
import '../../helpers/named_finders.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/staged_carry.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/wait_window.dart';

/// F-429 (유저 2026-10-21: 「일반 임포트창 거의 그대로」): a cut folder comes
/// in through the window every file comes in through — its layers rows of
/// the table in the timeline's order, wearing the rail's own cells; its
/// scans and movie files of their own; what it leaves out a row of its own.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-folder-window');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  /// A delivery folder [root] of [files] — a picture each `.png`, a few
  /// bytes each of the rest.
  Future<String> aFolder(
    WidgetTester tester,
    String root,
    List<String> files,
  ) async => (await tester.runAsync(() async {
    final sep = Platform.pathSeparator;
    for (final file in files) {
      final name = '$root$sep${file.replaceAll('/', sep)}';
      if (file.endsWith('.png')) {
        await writeSolidPng(tempDir, name);
      } else {
        final written = File('${tempDir.path}$sep$name');
        await written.parent.create(recursive: true);
        await written.writeAsBytes(const [0, 0, 0, 24]);
      }
    }
    return '${tempDir.path}$sep$root';
  }))!;

  EditorSessionManager aSession() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
      mediaStagingStore: MediaStagingStore(
        directoryPath: '${tempDir.path}/Staged',
      ),
      audioConformStore: soundConformStore(),
    );
    addTearDown(session.dispose);
    return session;
  }

  /// The window, opened on [folder] as the one door opens it — in an app
  /// of its own, so a second window is a fresh one.
  Future<void> openOn(
    WidgetTester tester,
    EditorSessionManager session,
    String folder,
  ) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: session, initialPaths: [folder]),
        ),
      ),
    );
    await settleLoadedPages(tester);
  }

  ImportFileTable table(WidgetTester tester) =>
      tester.widget<ImportFileTable>(find.byType(ImportFileTable));

  ImportColumn<Object?> column(WidgetTester tester, String id) =>
      table(tester).columns.singleWhere((column) => column.id == id);

  Future<void> importAll(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);
    session.playbackRig.prerenderScheduler.cancel();
  }

  Cut cutNamed(EditorSessionManager session, String name) => session
      .repository
      .requireProject()
      .tracks
      .first
      .cuts
      .singleWhere((cut) => cut.name == name);

  testWidgets('its layers are rows in the timeline\'s order — the top one '
      'first, a correction right above its symbol, named as it — then its '
      'scan and movie, and last what it leaves out', (tester) async {
    final folder = await aFolder(tester, 'csm_13_069_loeks', [
      'A1.png',
      'A2.png',
      'A1s.png',
      'B1.png',
      '_BG.png',
      '_069_ts_loe.png',
      'mov069.mp4',
      'memo.txt',
      'LO/A1.png',
    ]);
    await openOn(tester, aSession(), folder);

    final rows = table(tester).rows;
    final scan = '$folder/_069_ts_loe.png';
    final movie = '$folder/mov069.mp4';
    expect([for (final row in rows) row.path], [
      'folder:B',
      'folder:A animation-director',
      'folder:A',
      'folder:_BG',
      scan,
      movie,
      'folder-left-out',
    ]);
    expect(
      [for (final row in rows.take(4)) row.name],
      ['B', 'A', 'A', 'BG'],
      reason: 'A1s is A — its colour label tells it apart (F-429-Q2)',
    );
    expect(rows.last.name.split(' · '), unorderedEquals(['memo.txt', 'LO/']));
    expect(
      find.named('import-layer-attach-arrow-folder:A animation-director'),
      findsOneWidget,
    );
    expect(find.named('import-layer-attach-arrow-folder:A'), findsNothing);
  });

  testWidgets('a layer row answers as the cut it lands in: a new layer of '
      'it, locked; baked, locked; no pool question; any fit; the cels it '
      'brings — and its kind is an image only with one cel', (tester) async {
    final folder = await aFolder(tester, 'csm_13_069_loeks', [
      'A1.png',
      'A2.png',
      'A1s.png',
      '_BG.png',
      '_069_ts_loe.png',
      'memo.txt',
    ]);
    await openOn(tester, aSession(), folder);
    final scan = '$folder/_069_ts_loe.png';
    const a = 'folder:A';

    final into = column(tester, 'into');
    expect(into.answersFor(a), [ImportDestination.activeCutLayer]);
    expect(into.cellWordOf(a), AppText.strings.imIntoNewLayer);
    expect(
      [for (final answer in into.answersFor(scan)) into.labelOf(answer)],
      [AppText.strings.imIntoNewLayer, AppText.strings.panelMedia],
      reason: 'F-429-Q4: 미디어 행만 넣을 곳을 고를 수 있게',
    );
    expect(into.cellWordOf(scan), AppText.strings.panelMedia);
    expect(into.answersFor('folder-left-out'), hasLength(1));
    expect(into.cellWordOf('folder-left-out'), AppText.strings.imExcluded);

    final bake = column(tester, 'bake');
    expect(bake.answersFor(a), [true]);
    expect(bake.appliesTo('folder-left-out'), isFalse);

    final file = column(tester, 'file');
    expect(file.appliesTo(a), isFalse, reason: 'a baked row leaves no entry');
    expect(file.appliesTo(scan), isTrue);
    expect(file.help, contains(AppText.strings.imKeepExplain));

    final fit = column(tester, 'fit');
    expect(fit.answersFor(a), MediaFitMode.values);
    expect(fit.cellWordOf(a), importFitLabel(MediaFitMode.contain));
    expect(fit.appliesTo(scan), isFalse, reason: 'registered, not placed');

    final option = column(tester, 'option');
    expect(option.cellWordOf(a), AppText.strings.imRunSpan('A1', 'A2', 2));
    expect(option.cellWordOf('folder:A animation-director'), 'A1s');
    expect(option.appliesTo('folder:_BG'), isFalse);

    expect(
      tester
          .widget<LayerTypeButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is LayerTypeButton &&
                  widget.idValue == 'folder:A animation-director',
            ),
          )
          .onTap,
      isNull,
      reason: 'a correction is its symbol\'s kind',
    );
    await tester.tap(find.named('import-layer-type-button-$a'));
    await tester.pumpAndSettle();
    PopupMenuItem<PanelFlyoutItem> kind(LayerKind kind) => tester.widget(
      find.byKey(ValueKey<String>('import-kind-${kind.jsonValue}')),
    );
    expect(kind(LayerKind.image).enabled, isFalse, reason: 'two cels');
    expect(kind(LayerKind.animation).value!.selected, isTrue);
  });

  testWidgets('Import lands the cut as the window answered it — the name '
      'typed, a label picked across the selected rows, a kind picked on one '
      '— and registers its scan, carried', (tester) async {
    final folder = await aFolder(tester, 'csm_13_069_loeks', [
      'A1.png',
      'A2.png',
      'B1.png',
      'B2.png',
      '_BG.png',
      '_069_ts_loe.png',
    ]);
    final session = aSession();
    await openOn(tester, session, folder);

    for (final row in ['folder:A', 'folder:B']) {
      await tester.tap(find.byKey(ValueKey<String>('import-name-$row')));
      await tester.pump();
    }
    // The preview stands on the row picked last, and pages through its cels.
    await settleLoadedPages(tester);
    await tester.tap(find.named('import-layer-mark-folder:A'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('layer-mark-option-none')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.named('import-layer-type-button-folder:_BG'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('import-kind-animation')));
    await tester.pumpAndSettle();
    // Typed last: a field with the caret in it never settles.
    await tester.enterText(
      find.byKey(const ValueKey<String>('import-cut-name-field')),
      '070',
    );
    await importAll(tester, session);

    final cut = cutNamed(session, '070');
    Layer layer(String name) => cut.layers.singleWhere((l) => l.name == name);
    expect(layer('A').mark, LayerMark.none);
    expect(layer('B').mark, LayerMark.none, reason: 'the selection spoke');
    expect(layer('BG').kind, LayerKind.animation);
    expect(layer('A').kind, LayerKind.animation, reason: 'BG alone was asked');
    final [registered] = session.mediaPool.mediaAssets;
    expect(registered.path, normalizedMediaPath('$folder/_069_ts_loe.png'));
    expect(registered.carried, isTrue);
    expect(
      cut.layers.where((l) => l.name.contains('ts')),
      isEmpty,
      reason: 'registered, not placed',
    );
  });

  testWidgets('a folder brought in again places nothing it was not asked '
      'to: the scan the pool holds stays there, and nothing is copied '
      'again', (tester) async {
    final folder = await aFolder(tester, 'csm_13_069_loeks', [
      'A1.png',
      '_069_ts_loe.png',
    ]);
    final scan = normalizedMediaPath('$folder/_069_ts_loe.png');
    final session = aSession();
    await openOn(tester, session, folder);
    await importAll(tester, session);
    expect(stagedCopyIn(session, scan), isNotNull, reason: 'the premise');
    await saveProject(tester, session, tempDir);
    expect(
      session.mediaStagingStore.holdsAnyCopyOf(scan),
      isFalse,
      reason: 'the premise: the save absorbed the staged copy',
    );

    await openOn(tester, session, folder);
    expect(
      column(tester, 'into').cellWordOf('$folder/_069_ts_loe.png'),
      AppText.strings.panelMedia,
    );
    await importAll(tester, session);

    expect(session.mediaStagingStore.holdsAnyCopyOf(scan), isFalse);
    expect(session.mediaPool.mediaAssets, hasLength(1));
    final cuts = session.repository.requireProject().tracks.first.cuts;
    expect(
      cuts.where((cut) => cut.name == '069').last.layers.map((l) => l.name),
      isNot(contains('_069_ts_loe')),
    );
  });

  testWidgets('what the folder says of itself is the status line\'s from the '
      'first frame; once its cut has landed its rows leave, and a second '
      'press brings in no second cut', (tester) async {
    final folder = await aFolder(tester, 'scans', ['A1.png']);
    final session = aSession();
    await openOn(tester, session, folder);
    expect(importWarningsButton, findsOneWidget, reason: 'no cut number');

    // Left empty, the name is the folder's own again.
    await tester.enterText(
      find.byKey(const ValueKey<String>('import-cut-name-field')),
      '',
    );
    await importAll(tester, session);
    expect(table(tester).rows, isEmpty);
    await importAll(tester, session);

    final cuts = session.repository.requireProject().tracks.first.cuts;
    expect(cuts.where((cut) => cut.name == 'scans'), hasLength(1));
  });
}
