// THE PLACE COLUMN KEEPS ONE ROOM (F-582-Q1).
//
// 🗣️유저 2026-11-10: 「넣을 곳도 같은 법으로 — 고정 길이 · 넘치면 생략 ·
// 호버로 전체」. The import window's 「넣을 곳」 said a layer's name — the row
// a drop aimed at, the symbol a folder's correction rides — and was laid
// out for whatever its rows said, so a long name widened the window. It
// keeps one room now, as the option column does (F-582), by the same
// declaration (`ImportColumn.keepsRoomFor`).
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/services/import/import_layer_spot.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/import/import_file_table.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/app_tooltip.dart';

import '../../helpers/settle_async.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/text_finders.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-place-room');
  });

  tearDown(() => deleteTempQuietly(tempDir));
  tearDown(SummonedTooltip.dismiss);
  tearDown(() => AppText.settings.value = const AppLanguageSettings());

  void speak(AppLanguage language) => AppText.settings.value =
      AppLanguageSettings(programLanguage: language);

  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  /// The open cut's drawing row, named [name].
  Layer rowNamed(EditorSessionManager s, String name) {
    final row = s.requireActiveCut.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .copyWith(name: name);
    s.repository.replaceLayer(layer: row);
    return row;
  }

  /// The window on [paths], in a view with room for what its list asks —
  /// in a narrower one the list is as wide as the window lets it.
  Future<void> open(
    WidgetTester tester,
    EditorSessionManager s,
    List<String> paths, {
    ImportLayerSpot? spot,
  }) async {
    tester.view.physicalSize = const Size(3000, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(
            session: s,
            initialPaths: paths,
            placeOnly: spot != null,
            spot: spot,
          ),
        ),
      ),
    );
    await settleLoadedPages(tester);
  }

  /// A pool picture let go on [row]'s frames at [cell], as a drop opens the
  /// window.
  Future<String> dropOn(
    WidgetTester tester,
    EditorSessionManager s,
    Layer row, {
    int cell = 9,
  }) async {
    final png = (await tester.runAsync(() async {
      final path = await writeSolidPng(tempDir, 'a.png');
      await s.mediaPool.importMediaFiles([path], copyIntoProject: false);
      return path;
    }))!;
    await open(
      tester,
      s,
      [png],
      spot: RowFramesSpot(layerId: row.id, frameIndex: cell - 1),
    );
    return png;
  }

  final list = find.byType(ImportFileTable);
  ImportFileTable table(WidgetTester tester) =>
      tester.widget<ImportFileTable>(list);

  /// What the place column alone asks of the list, as it stands.
  double placeAsks(WidgetTester tester) => ImportFileTable.minimumWidth(
    tester.element(list),
    rows: table(tester).rows,
    columns: [table(tester).columns.singleWhere((c) => c.id == 'into')],
    leadWidth: table(tester).leadWidth,
  );

  Finder place(String key) =>
      find.byKey(ValueKey<String>('import-cell-into-$key'));

  String wordOf(WidgetTester tester, String key) => tester
      .widget<Text>(find.descendant(of: place(key), matching: find.anyText()))
      .data!;

  bool isCut(WidgetTester tester, String key) => tester
      .renderObject<RenderParagraph>(
        find.descendant(of: place(key), matching: find.anyRichText()),
      )
      .didExceedMaxLines;

  testWidgets('🚨a long layer\'s name widens nothing: the row and the cell a '
      'drop aimed at are cut where the room ends and say their whole on a '
      'hover — and a short one is whole', (tester) async {
    final short = session();
    final png = await dropOn(tester, short, rowNamed(short, 'A'));
    expect(wordOf(tester, png), AppText.strings.imIntoRowCell('A', 9));
    expect(isCut(tester, png), isFalse);
    final asked = placeAsks(tester);

    const name = 'background_street_night_take_two';
    final long = session();
    final again = await dropOn(tester, long, rowNamed(long, name));
    final whole = AppText.strings.imIntoRowCell(name, 9);
    expect(wordOf(tester, again), whole, reason: 'the word is the whole');
    expect(placeAsks(tester), asked, reason: 'no wider for the name');
    expect(isCut(tester, again), isTrue, reason: 'cut at the room');

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(place(again)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(SummonedTooltip.debugShownMessage, whole);
  });

  testWidgets('a window nothing was dropped in keeps the same room — the '
      'column is as wide whatever the window was opened for', (tester) async {
    final dropped = session();
    await dropOn(tester, dropped, rowNamed(dropped, 'A'));
    final asked = placeAsks(tester);

    final png = (await tester.runAsync(
      () => writeSolidPng(tempDir, 'b.png'),
    ))!;
    await open(tester, session(), [png]);

    expect(wordOf(tester, png), AppText.strings.imIntoNewLayer);
    expect(placeAsks(tester), asked);
  });

  // The room is of each shape a place's word takes, since which is the
  // widest is the language's to say: in Korean the row and its cell, in
  // French the ride.
  testWidgets('🚨the room holds a row of eight letters and a three-digit '
      'cell, where that is the widest word a place says (Korean)', (
    tester,
  ) async {
    speak(AppLanguage.ko);
    final s = session();
    final png = await dropOn(tester, s, rowNamed(s, 'ABCDEFGH'), cell: 999);

    expect(wordOf(tester, png), 'ABCDEFGH · 999번 칸');
    expect(isCut(tester, png), isFalse);
  });

  testWidgets('🚨the room holds a folder\'s correction riding its symbol, '
      'where that is the widest word a place says (French)', (tester) async {
    speak(AppLanguage.fr);
    final folder = (await tester.runAsync(() async {
      final sep = Platform.pathSeparator;
      for (final file in const ['A1.png', 'A2.png', 'A1s.png']) {
        await writeSolidPng(tempDir, 'zz_01_005_loeks$sep$file');
      }
      return '${tempDir.path}${sep}zz_01_005_loeks';
    }))!;
    await open(tester, session(), [folder]);

    const correction = 'folder:A animation-director';
    expect(
      wordOf(tester, correction),
      AppText.strings.tlDropAttach('A', synced: true),
      reason: '⛔전제: the correction rides A',
    );
    expect(wordOf(tester, correction), 'attacher à A (synchronisé)');
    expect(isCut(tester, correction), isFalse);
  });
}
