import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_paper.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_cels_board.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/widgets/boolean_dot.dart';
import 'package:anicel/src/ui/widgets/cursor_notice.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';

import '../../helpers/export_cels_board_probe.dart';
import '../../helpers/files_written_under.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🗣️F-289 (유저 2026-10-05): 「타임시트 탭을 그냥 셀 탭의 내부로 편입.
/// 컷봉투탭도 셀 내부로 편입. 위치는 추가버튼의 미술/디렉션/시트/컷봉투
/// 이렇게. 기존의 범위는 셀의 범위 규칙 따라가고, 형식만 타임시트 형식이라는
/// 항목 만들어서 법 통일해서 고를수있게. 그리고 기존 형식 항목은 구분하기위해
/// 셀 형식. 추가로 컷봉투용으로 컷봉투 형식도 만들기」.
///
/// The cut's timesheet and its cut envelope are KINDS the Cels tab writes:
/// a row each at the foot of the list, a block a file, turned off, stood on
/// and written by the one law every drawing of the list answers to.
void main() {
  setUp(() => AppExport.settings.value = AppExportSettings());
  tearDown(() => AppExport.settings.value = AppExportSettings());

  const cutId = CutId('cut');
  const size = CanvasSize(width: 8, height: 8);

  Frame frame(String id, String name) =>
      Frame(id: FrameId(id), duration: 1, strokes: const [], name: name);

  /// One cut, 301: a KEY row A with two cels.
  EditorSessionManager film() => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('project'),
      name: 'Project',
      cameraSize: const CanvasSize(width: 32, height: 18),
      createdAt: DateTime.utc(2026),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Track',
          cuts: [
            Cut(
              id: cutId,
              name: '301',
              duration: 2,
              canvasSize: size,
              layers: [
                Layer(
                  id: const LayerId('a'),
                  name: 'A',
                  frames: [frame('a1', '1'), frame('a2', '2')],
                  mark: const LayerMark(process: LayerProcess.key),
                ),
                createCameraLayer(cutId: cutId),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  /// A black dot on each of A's cels, so the run has pictures to write.
  void draw(EditorSessionManager session) {
    final cut = session.cutById(cutId)!;
    final pixels = Uint8List(8 * 8 * 4)..[3] = 255;
    for (final cel in ['a1', 'a2']) {
      session.renderCaches.brushFrameStore.storeBakedSurface(
        session.brushFrameKeyForCut(cut, const LayerId('a'), FrameId(cel)),
        BitmapSurface(
          canvasSize: size,
          tileSize: 8,
          tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: 8, pixels: pixels)},
        ),
      );
    }
  }

  Future<ExportDialogState> pumpCels(
    WidgetTester tester,
    EditorSessionManager session, {
    CelsExportSpec? spec,
    Directory? into,
  }) async {
    if (spec != null) {
      AppExport.settings.value = AppExportSettings(
        lastSpecs: ExportTabSpecs(cels: spec),
      );
    }
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session,
            exportDirectoryPicker: into == null ? null : () async => into.path,
            formatAvailability: ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('export-tab-cels')));
    await tester.pump();
    if (into != null) {
      await tester.tap(
        find.byKey(const ValueKey<String>('export-browse-button')),
      );
      await tester.pump();
      await tester.pump();
    }
    return tester.state<ExportDialogState>(find.byType(ExportDialog));
  }

  Finder keyed(String value) => find.byKey(ValueKey<String>(value));

  Future<void> press(WidgetTester tester, String key) async {
    await tester.ensureVisible(keyed(key));
    await tester.pump();
    await tester.tap(keyed(key), warnIfMissed: false);
    await tester.pump();
  }

  String count(WidgetTester tester) =>
      tester.widget<Text>(keyed('export-cels-count')).data!;

  String textOf(WidgetTester tester, String key) =>
      tester.widget<Text>(keyed(key)).data!;

  /// The files the list says it writes: its bright blocks', top to bottom.
  List<String> listed(WidgetTester tester) => [
    for (final row in tester.celsBoard.rows)
      for (final sheet in row.sheets)
        if (sheet.written) sheet.fileName,
  ];

  const everything = CelsExportSpec(
    kinds: {
      ExportCelKind.cel,
      ExportCelKind.timesheet,
      ExportCelKind.envelope,
    },
  );

  testWidgets('🗣️by default the list closes with the TIMESHEET\'s row — a '
      'block a file — and the envelope\'s comes with its pill (유저 '
      '2026-10-06: 「기본값은 셀/미술/시트 체크 나머진 해제」)', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    final state = await pumpCels(tester, session);

    expect(state.debugSpecs.cels.kinds, {
      ExportCelKind.cel,
      ExportCelKind.art,
      ExportCelKind.timesheet,
    });
    expect(tester.celsBoardRowIds, ['a', 'document-timesheet']);
    // One page: the block reads its cut, and its file is TS and the cut.
    expect(tester.celsBoardBlocksOf('document-timesheet'), [('301', true)]);
    expect(listed(tester), ['A1.png', 'A2.png', '_TS301.png']);
    expect(count(tester), '3 files');

    await press(tester, 'export-cels-kind-envelope');
    expect(tester.celsBoardRowIds, [
      'a',
      'document-timesheet',
      'document-envelope',
    ]);
    expect(tester.celsBoardBlocksOf('document-envelope'), [('301', true)]);
    expect(listed(tester).last, '_CUT301_envelope.png');
    expect(count(tester), '4 files');

    await press(tester, 'export-cels-kind-timesheet');
    expect(tester.celsBoardRowIds, ['a', 'document-envelope']);
    expect(count(tester), '3 files');
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a document\'s row is drawn with the rail\'s cells: its '
      'switch, no label plate, its panel\'s icon for a kind, its name — and '
      'its blocks are plain paper', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    await pumpCels(tester, session, spec: everything);
    final strings = AppText.strings;

    for (final (id, name, icon) in [
      ('document-timesheet', strings.panelTimesheet, Icons.table_chart_outlined),
      ('document-envelope', strings.panelEnvelope, Icons.mail_outline),
    ]) {
      final row = keyed('export-cels-row-$id');
      expect(textOf(tester, 'export-cels-name-$id'), name);
      expect(
        find.descendant(of: row, matching: find.byIcon(icon)),
        findsOneWidget,
        reason: '$id wears its panel\'s icon',
      );
      expect(
        find.descendant(of: row, matching: find.byType(LayerMarkPlates)),
        findsNothing,
        reason: 'a document wears no label',
      );
      expect(tester.celsBoardSwitchState(id), BooleanMix.on);
      final block = tester.widget<ExportCelBlock>(
        find.descendant(
          of: keyed('export-cels-board'),
          matching: find.byWidgetPredicate(
            (widget) => widget is ExportCelBlock && widget.rowId == id,
          ),
        ),
      );
      expect(block.mark, LayerMark.none);
    }
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('「내보낼 종류」: the kinds of the cut\'s rows in one strip, its '
      'documents in a strip under them', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    await pumpCels(tester, session);
    PillStrip stripOf(ExportCelKind kind) => tester.widget<PillStrip>(
      find.ancestor(
        of: keyed('export-cels-kind-${kind.jsonValue}'),
        matching: find.byType(PillStrip),
      ),
    );
    List<String> keysOf(PillStrip strip) => [
      for (final item in strip.items) item.keyValue,
    ];
    expect(keysOf(stripOf(ExportCelKind.cel)), [
      'export-cels-kind-cel',
      'export-cels-kind-conte',
      'export-cels-kind-art',
      'export-cels-kind-direction',
    ]);
    expect(keysOf(stripOf(ExportCelKind.timesheet)), [
      'export-cels-kind-timesheet',
      'export-cels-kind-envelope',
    ]);
    expect(
      tester.getTopLeft(keyed('export-cels-kind-timesheet')).dy,
      greaterThan(tester.getBottomLeft(keyed('export-cels-kind-cel')).dy),
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a document\'s row switched off writes none of its files — '
      'its blocks hollow, the label 「커스텀」 — and a block of it says why '
      'when pressed; 초기화 puts it back', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    await pumpCels(tester, session, spec: everything);
    final strings = AppText.strings;
    expect(count(tester), '4 files');

    await tester.pressInCelsBoard(
      tester.celsBoardSwitch('document-timesheet'),
    );
    expect(tester.celsBoardSwitchState('document-timesheet'), BooleanMix.off);
    expect(tester.celsBoardBlocksOf('document-timesheet'), [('301', false)]);
    expect(count(tester), '3 files');
    expect(textOf(tester, 'export-cels-label-text'), strings.exSelCustom);
    expect(
      session.repository
          .requireProject()
          .exportOverrides
          .deltaFor(cutId)!
          .documentsOff,
      {ExportCelKind.timesheet},
    );

    // The file is no file now: its block says why, and stays as it is.
    await tester.pressInCelsBoard(
      tester.celsBoardBlock('document-timesheet', 'timesheet-cut-0'),
    );
    expect(
      find.descendant(
        of: find.byType(CursorNoticeOverlay),
        matching: find.text(strings.noticeExportRowOff),
      ),
      findsOneWidget,
    );
    expect(tester.celsBoardBlocksOf('document-timesheet'), [('301', false)]);

    await press(tester, 'export-cels-reset');
    expect(tester.celsBoardSwitchState('document-timesheet'), BooleanMix.on);
    expect(count(tester), '4 files');
    expect(
      textOf(tester, 'export-cels-label-text'),
      isNot(strings.exSelCustom),
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a document\'s block is its file\'s switch: off it is hollow '
      'and out of the count — and that is no row exception', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    await pumpCels(tester, session, spec: everything);

    await tester.pressInCelsBoard(
      tester.celsBoardBlock('document-envelope', 'envelope-cut-0'),
    );
    expect(tester.celsBoardBlocksOf('document-envelope'), [('301', false)]);
    expect(tester.celsBoardSwitchState('document-envelope'), BooleanMix.on);
    expect(count(tester), '3 files');
    expect(listed(tester), ['A1.png', 'A2.png', '_TS301.png']);
    expect(
      textOf(tester, 'export-cels-label-text'),
      isNot(AppText.strings.exSelCustom),
    );
    expect(
      session.repository
          .requireProject()
          .exportOverrides
          .deltaFor(cutId)!
          .skippedPages,
      {(document: ExportCelKind.envelope, page: 0)},
    );

    await tester.pressInCelsBoard(
      tester.celsBoardBlock('document-envelope', 'envelope-cut-0'),
    );
    expect(count(tester), '4 files');
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('the list stands on a document as on any row: the preview is '
      'its page, the line under it its file — and no direction is laid '
      'over a document', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    final state = await pumpCels(tester, session, spec: everything);

    await press(tester, 'export-cels-stand-document-envelope');
    expect(tester.celsBoard.standing, 'document-envelope');
    expect(
      textOf(tester, 'export-transport-line'),
      '_CUT301_envelope.png · 1 / 1',
    );
    await tester.runAsync(state.debugFlushPreview);
    await tester.pump();
    final envelope = tester
        .widget<RawImage>(keyed('export-preview-image'))
        .image!;
    expect(
      (envelope.width, envelope.height),
      (8, 8),
      reason: 'the cut\'s own pixels, the envelope\'s default paper',
    );

    await press(tester, 'export-cels-stand-document-timesheet');
    expect(textOf(tester, 'export-transport-line'), '_TS301.png · 1 / 1');
    await tester.runAsync(state.debugFlushPreview);
    await tester.pump();
    final sheet = tester.widget<RawImage>(keyed('export-preview-image')).image!;
    expect(
      sheet.width / sheet.height,
      closeTo(1754 / 2480, 0.01),
      reason: 'a timesheet page, fitted to the pane',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('셀 형식 · 타임시트 형식 · 컷봉투 형식: three modules, there '
      'whatever kinds are written — the cels\' folded, the documents\' open',
      (tester) async {
    final session = film();
    addTearDown(session.dispose);
    final state = await pumpCels(
      tester,
      session,
      spec: const CelsExportSpec(kinds: {ExportCelKind.cel}),
    );
    final strings = AppText.strings;

    expect(find.text('${strings.exCelFormat} — PNG · RGBA'), findsOneWidget);
    expect(keyed('export-format-still-jpg'), findsNothing, reason: 'folded');
    expect(find.text(strings.exTimesheetFormat), findsOneWidget);
    expect(find.text(strings.exEnvelopeFormat), findsOneWidget);

    // 타임시트 형식: PNG · JPG · XDTS, and a quality while it is a JPG.
    Pill pill(String key) => tester.widget<Pill>(keyed(key));
    expect(pill('export-tsformat-png').selected, isTrue);
    expect(keyed('export-tsformat-quality'), findsNothing);
    await press(tester, 'export-tsformat-jpg');
    expect(state.debugSpecs.cels.sheetFormat, ExportTimesheetFormat.sheetImage);
    expect(state.debugSpecs.cels.sheetImage.stillFormat, ExportStillFormat.jpg);
    expect(keyed('export-tsformat-quality'), findsOneWidget);
    await press(tester, 'export-tsformat-xdts');
    expect(state.debugSpecs.cels.sheetFormat, ExportTimesheetFormat.xdts);
    expect(
      [
        for (final key in ['png', 'jpg', 'xdts'])
          pill('export-tsformat-$key').selected,
      ],
      [false, false, true],
      reason: 'a picture format is lit only while a picture is written',
    );
    expect(keyed('export-tsformat-quality'), findsNothing);
    await press(tester, 'export-tsformat-png');
    expect(state.debugSpecs.cels.sheetFormat, ExportTimesheetFormat.sheetImage);
    expect(state.debugSpecs.cels.sheetImage.stillFormat, ExportStillFormat.png);

    // 컷봉투 형식: its picture, and its paper.
    expect(pill('export-envelope-paper-cut').selected, isTrue);
    await press(tester, 'export-envelope-paper-sheet');
    expect(state.debugSpecs.cels.envelopePaper, CutEnvelopePaperMode.sheet);
    await press(tester, 'export-envelope-format-jpg');
    expect(
      state.debugSpecs.cels.envelopeImage.stillFormat,
      ExportStillFormat.jpg,
    );
    expect(
      state.debugSpecs.cels.sheetImage.stillFormat,
      ExportStillFormat.png,
      reason: 'each document keeps a format of its own',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🚨ONE run writes the cels and the documents, each in its own '
      'format', (tester) async {
    final temp = Directory.systemTemp.createTempSync('qa-cels-documents');
    deleteAfterSessionEnds(temp);
    final session = film();
    addTearDown(session.dispose);
    draw(session);
    final state = await pumpCels(
      tester,
      session,
      spec: everything.copyWith(
        sheetImage: paperDocumentFormat.copyWith(
          stillFormat: ExportStillFormat.jpg,
        ),
      ),
      into: temp,
    );

    await tester.runAsync(state.export);
    await tester.pump();

    expect(filesWrittenUnder(temp), [
      'A1.png',
      'A2.png',
      '_CUT301_envelope.png',
      '_TS301.jpg',
    ]);
    List<int> head(String name) =>
        File('${temp.path}/$name').readAsBytesSync().take(4).toList();
    expect(head('A1.png'), [0x89, 0x50, 0x4E, 0x47]);
    expect(head('_CUT301_envelope.png'), [0x89, 0x50, 0x4E, 0x47]);
    expect(head('_TS301.jpg').take(3), [0xFF, 0xD8, 0xFF]);
    expect(textOf(tester, 'export-status'), 'Exported 4 files.');
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('the digital sheet is ONE file of the same run — written, '
      'counted, and named TS and its cut', (tester) async {
    final temp = Directory.systemTemp.createTempSync('qa-cels-xdts');
    deleteAfterSessionEnds(temp);
    final session = film();
    addTearDown(session.dispose);
    draw(session);
    final state = await pumpCels(
      tester,
      session,
      spec: const CelsExportSpec(
        kinds: {ExportCelKind.cel, ExportCelKind.timesheet},
        sheetFormat: ExportTimesheetFormat.xdts,
      ),
      into: temp,
    );
    expect(listed(tester), ['A1.png', 'A2.png', '_TS301.xdts']);

    await tester.runAsync(state.export);
    await tester.pump();

    expect(filesWrittenUnder(temp), ['A1.png', 'A2.png', '_TS301.xdts']);
    expect(
      File('${temp.path}/_TS301.xdts').readAsStringSync(),
      contains('exchangeDigitalTimeSheet'),
    );
    expect(textOf(tester, 'export-status'), 'Exported 3 files.');
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a document turned off is not written — its row, or its file',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('qa-cels-documents-off');
    deleteAfterSessionEnds(temp);
    final session = film();
    addTearDown(session.dispose);
    draw(session);
    final state = await pumpCels(tester, session, spec: everything, into: temp);
    await tester.pressInCelsBoard(
      tester.celsBoardSwitch('document-timesheet'),
    );
    await tester.pressInCelsBoard(
      tester.celsBoardBlock('document-envelope', 'envelope-cut-0'),
    );

    await tester.runAsync(state.export);
    await tester.pump();

    expect(filesWrittenUnder(temp), ['A1.png', 'A2.png']);
    session.playbackRig.prerenderScheduler.cancel();
  });
}
