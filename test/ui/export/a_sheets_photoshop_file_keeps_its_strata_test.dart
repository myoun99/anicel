import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/path_names.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/envelope/cut_envelope_layout.dart';
import 'package:anicel/src/models/envelope/cut_envelope_presets.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/sheet_paint_layer.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/services/persistence/move_into_folder.dart';
import 'package:anicel/src/services/photoshop/psd_reader.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/ui/dialogs/folder_pick_flow.dart'
    show debugOperatingSystemOverride;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/export/sheet_strata_rows.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

import '../../helpers/export_format_pick.dart';
import '../../helpers/export_preview_probe.dart';
import '../../helpers/temp_dir.dart';

/// A paper document written as a Photoshop document keeps its strata apart
/// (I-117 — 🗣️유저 2026-10-21): 「타임시트는 알듯이 층 나눠져있는대로 출력.
/// 컷봉투도 마찬가지. 밑 흰색 용지, 서식, 텍스트들, 잉크 이런식으로」 — and
/// the conte's pages are folders of ONE file: 「콘티용지탭 psd 출력시
/// 페이지별로 하나의 그룹으로 묶어서 … 한 파일안에 여러 페이지 그룹」.
///
/// Each file is held to the picture its PNG is: the rows, laid one over the
/// next as Photoshop lays them, ARE that picture, and the document's own
/// composite is it to the byte.
void main() {
  late Directory temp;

  setUp(() {
    AppExport.settings.value = AppExportSettings();
    temp = Directory.systemTemp.createTempSync('qa-sheet-psd');
  });

  tearDown(() {
    AppExport.settings.value = AppExportSettings();
    deleteTempQuietly(temp);
  });

  final strings = AppText.strings;

  /// The rows of a timesheet or an envelope, as the file names them.
  final paperRows = [
    strings.exStratumPaper,
    strings.exStratumForm,
    strings.exStratumContent,
    strings.exStratumInk,
  ];

  File written(String name) =>
      File('${temp.path}${Platform.pathSeparator}$name');

  Future<Uint8List> pngPixels(WidgetTester tester, String name) async =>
      (await tester.runAsync(() async {
        final image = await decodeImageFromList(written(name).readAsBytesSync());
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        image.dispose();
        return data!.buffer.asUint8List();
      }))!;

  PsdDocument psd(String name) =>
      readPsdDocument(written(name).readAsBytesSync());

  /// The window on [tab] — asking its place of [temp] before a run, or
  /// where a place [asksAfter] what is made, as iOS asks it, of no window
  /// a test stands in for.
  Future<ExportDialogState> pumpDialog(
    WidgetTester tester,
    EditorSessionManager session, {
    required String tab,
    ExportFormatAvailability? availability,
    bool asksAfter = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session,
            exportDirectoryPicker: asksAfter ? null : () async => temp.path,
            formatAvailability:
                availability ?? ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(ValueKey<String>('export-tab-$tab')));
    await tester.pump();
    return tester.state<ExportDialogState>(find.byType(ExportDialog));
  }

  /// [state]'s run, and how many of a sheet's costly parts it made.
  Future<int> partsOfRun(WidgetTester tester, ExportDialogState state) async {
    final before = state.debugSheetPartsMade;
    await tester.runAsync(state.export);
    await tester.pump();
    return state.debugSheetPartsMade - before;
  }

  String status(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey<String>('export-status')))
      .data!;

  test('a sheet\'s rows are its strata, bottom-up — each named as it is, at '
      'full strength in no blend, and drawn alone when the file comes to it',
      () {
    final asked = <Set<SheetPaintLayer>>[];
    Future<ui.Image> draw(Set<SheetPaintLayer> layers) {
      asked.add(layers);
      return Completer<ui.Image>().future;
    }

    final rows = sheetStrataRows(paperSheetStrata, draw);
    expect(
      [for (final row in rows) (row.name, row.opacity, row.blendMode)],
      [for (final name in paperRows) (name, 1.0, LayerBlendMode.normal)],
    );
    expect(asked, isEmpty);
    for (final row in rows) {
      unawaited(row.draw());
    }
    expect(asked, [
      {SheetPaintLayer.paper},
      {SheetPaintLayer.form},
      {SheetPaintLayer.content},
      {SheetPaintLayer.ink},
    ]);
    expect(
      [for (final row in sheetStrataRows(SheetPaintLayer.values, draw)) row.name],
      [...paperRows.take(3), strings.exStratumPicture, strings.exStratumInk],
      reason: 'the conte\'s pictures between its words and its ink',
    );
  });

  group('the cut envelope', () {
    Cut cut(String id) => Cut(
      id: CutId(id),
      name: id,
      duration: 24,
      canvasSize: const CanvasSize(width: 320, height: 240),
      layers: [
        Layer(
          id: LayerId('$id-a'),
          name: 'A',
          kind: LayerKind.animation,
          frames: const [],
        ),
      ],
    );

    testWidgets('its strata are the rows — 「밑 흰색 용지, 서식, 텍스트들, '
        '잉크」 — which lay up into the picture its PNG is, each row making '
        'only the parts it draws', (tester) async {
      final session = EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('envelope'),
          name: 'Envelope',
          createdAt: DateTime.utc(2026, 10, 22),
          tracks: [
            Track(
              id: const TrackId('track'),
              name: 'Video',
              cuts: [cut('39')],
            ),
          ],
        ),
      );
      addTearDown(session.dispose);
      final inkBox = CutEnvelopePresets.analog.inkBoxes.first;
      session.renderCaches.envelopeInkStore.storeBakedSurface(
        envelopeInkBoxKey(const CutId('39'), inkBox.id),
        _redSurface(),
      );
      AppExport.settings.value = AppExportSettings(
        lastSpecs: const ExportTabSpecs(
          cels: CelsExportSpec(kinds: {ExportCelKind.envelope}),
        ),
      );
      final state = await pumpDialog(tester, session, tab: 'cels');

      final madeForPng = await partsOfRun(tester, state);
      final png = await pngPixels(tester, '_CUT39_envelope.png');
      await pickPaperFormat(tester, 'export-envelope-format', 'psd');
      final madeForPsd = await partsOfRun(tester, state);
      final read = psd('_CUT39_envelope.psd');

      expect((read.width, read.height), (320, 240));
      expect(
        [
          for (final row in read.layers)
            (row.name, row.role, row.opacity, row.blendKey, row.visible),
        ],
        [
          for (final name in paperRows)
            (name, PsdLayerRole.raster, 255, 'norm', true),
        ],
      );
      expect(read.composite, png, reason: 'the picture its PNG is');
      expect(_offBy(_laidUp(read.layers, 320, 240), png), 0);

      final paper = read.layers.first;
      expect((paper.left, paper.top, paper.right, paper.bottom), (
        0,
        0,
        320,
        240,
      ));
      expect(
        _colours(paper.pixels!),
        hasLength(1),
        reason: 'the paper alone: one colour, edge to edge',
      );
      final ink = read.layers.last;
      final box = CutEnvelopeLayout.fit(
        form: CutEnvelopePresets.analog,
        paperWidth: 320,
        paperHeight: 240,
      ).placedBoxes.firstWhere((placed) => placed.box.id == inkBox.id);
      expect(ink.hasPixels, isTrue, reason: 'the ink, from the store');
      expect(
        Rect.fromLTRB(
          box.x - 1,
          box.y - 1,
          box.x + box.width + 1,
          box.y + box.height + 1,
        ).contains(Offset(ink.left.toDouble(), ink.top.toDouble())),
        isTrue,
        reason: 'in the box it was written in',
      );

      expect(madeForPng, 1, reason: 'the box\'s ink, read once');
      expect(
        madeForPsd,
        2 * madeForPng,
        reason:
            'the ink is made for the picture and for its own row — not for '
            'the paper\'s, the form\'s or the words\'',
      );
    });
  });

  const cutId = CutId('cut');

  /// One cut, 「Cut」: a row with one cel.
  EditorSessionManager sheetFilm() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('sheet'),
        name: 'Sheet',
        cameraSize: const CanvasSize(width: 32, height: 18),
        createdAt: DateTime.utc(2026, 10, 22),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [
              Cut(
                id: cutId,
                name: 'Cut',
                duration: 2,
                canvasSize: const CanvasSize(width: 8, height: 8),
                layers: [
                  Layer(
                    id: const LayerId('a'),
                    name: 'A',
                    frames: [
                      Frame(
                        id: const FrameId('a1'),
                        duration: 1,
                        strokes: const [],
                        name: '1',
                      ),
                    ],
                  ),
                  createCameraLayer(cutId: cutId),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  testWidgets('a still this machine cannot write is off in every document\'s '
      'list, saying why, and the PSD beside it on — the Format module\'s law',
      (tester) async {
    // A binary with no JPG encoder.
    final noJpg = ExportFormatAvailability(
      encoderResolver: () => null,
      ffmpegCheck: () async => true,
      jpgSupported: false,
    );
    addTearDown(noJpg.dispose);
    AppExport.settings.value = AppExportSettings(
      lastSpecs: const ExportTabSpecs(
        cels: CelsExportSpec(
          kinds: {ExportCelKind.timesheet, ExportCelKind.envelope},
        ),
      ),
    );
    await pumpDialog(tester, sheetFilm(), tab: 'cels', availability: noJpg);

    /// The pictures [prefix]'s list offers, each as whether it takes a pick
    /// and what it says.
    Future<Map<String, (bool, String?)>> pictures(String prefix) async {
      final list = find.byKey(ValueKey<String>('$prefix-file'));
      await tester.ensureVisible(list);
      await tester.pump();
      return {
        for (final row
            in tester
                .widget<PanelFlyoutButton>(list)
                .entriesBuilder()
                .whereType<PanelFlyoutItem>())
          if (ExportStillFormat.values.any(
            (format) => row.keyValue == '$prefix-${format.jsonValue}',
          ))
            row.keyValue: (row.enabled, row.warning),
      };
    }

    Map<String, (bool, String?)> offered(String prefix) => {
      for (final format in ExportStillFormat.values)
        '$prefix-${format.jsonValue}': format == ExportStillFormat.jpg
            ? (false, strings.exNotInThisBuild)
            : (true, null),
    };

    for (final prefix in ['export-tsformat', 'export-envelope-format']) {
      expect(await pictures(prefix), offered(prefix), reason: prefix);
    }
    await tester.tap(find.byKey(const ValueKey<String>('export-tab-conte')));
    await tester.pump();
    expect(
      await pictures('export-conteformat'),
      offered('export-conteformat'),
    );
  });

  group('the timesheet', () {
    testWidgets('its strata are the rows, laying up into the picture its PNG '
        'is, each row making only the parts it draws', (tester) async {
      final session = sheetFilm();
      session.renderCaches.timesheetInkStore.storeBakedSurface(
        timesheetInkPageKey(cutId, 0),
        _redSurface(),
      );
      AppExport.settings.value = AppExportSettings(
        lastSpecs: const ExportTabSpecs(
          cels: CelsExportSpec(kinds: {ExportCelKind.timesheet}),
        ),
      );
      final state = await pumpDialog(tester, session, tab: 'cels');

      final madeForPng = await partsOfRun(tester, state);
      final png = await pngPixels(tester, '_TSCut.png');
      await pickPaperFormat(tester, 'export-tsformat', 'psd');
      final madeForPsd = await partsOfRun(tester, state);
      final read = psd('_TSCut.psd');

      expect(
        [
          for (final row in read.layers)
            (row.name, row.role, row.opacity, row.blendKey, row.visible),
        ],
        [
          for (final name in paperRows)
            (name, PsdLayerRole.raster, 255, 'norm', true),
        ],
      );
      expect(read.composite, png, reason: 'the picture its PNG is');
      expect(_offBy(_laidUp(read.layers, read.width, read.height), png), 0);
      expect(
        _colours(read.layers.first.pixels!),
        hasLength(1),
        reason: 'the paper alone: one colour, edge to edge',
      );
      final ink = read.layers.last;
      expect(
        (ink.left, ink.top),
        (0, 0),
        reason: 'the page\'s ink, from the page\'s corner',
      );
      final [red, green, _, alpha, ...] = ink.pixels!;
      expect(red, greaterThan(200), reason: 'red, from the store');
      expect((green < 80, alpha > 200), (true, true));

      expect(madeForPng, 1, reason: 'the page\'s ink, read once');
      expect(madeForPsd, 2 * madeForPng);
    });
  });

  group('the conte', () {
    const sheet = 'Conte';

    /// One cut with a storyboard row written on, so its page has a picture
    /// and a band of ink; the book without its cover — a blank back, and
    /// the body.
    EditorSessionManager film() {
      final session = EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('conte'),
          name: sheet,
          cameraSize: const CanvasSize(width: 32, height: 18),
          createdAt: DateTime.utc(2026, 10, 22),
          tracks: [
            Track(
              id: const TrackId('track'),
              name: 'Video',
              cuts: [
                Cut(
                  id: const CutId('39'),
                  name: '39',
                  duration: 6,
                  canvasSize: const CanvasSize(width: 64, height: 36),
                  layers: [
                    Layer(
                      id: const LayerId('39-sb'),
                      name: 'SB',
                      kind: LayerKind.storyboard,
                      frames: [
                        Frame(
                          id: const FrameId('39-0'),
                          duration: 1,
                          strokes: const [],
                        ),
                      ],
                      timeline: const {
                        0: TimelineExposure.drawing(
                          FrameId('39-0'),
                          length: 6,
                          memo: ExposureMemo(inkId: 'ink-39-0'),
                        ),
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      addTearDown(session.dispose);
      session.updateTimesheetInfo(
        session.timesheetInfo.copyWith(conteCover: false),
      );
      final book = layoutConteBook(
        buildConteSheetSource(session.repository.requireProject()),
        metrics: ConteSheetMetrics.ofWork(
          session.timesheetInfo,
          cameraAspect: session.camera.cameraFrameAspect,
        ),
      );
      expect(
        [for (final page in book) page.cells.isNotEmpty],
        [false, true],
        reason: 'the blank back, then the body',
      );
      final cell = book.last.cells.single;
      session.renderCaches.conteInkRowStore.storeBakedSurface(
        conteInkRowKey(CutId(cell.cutId), cell.source.inkId!),
        _redSurface(),
      );
      return session;
    }

    /// The rows of [read]'s folder [name], bottom-up.
    List<PsdLayer> folder(PsdDocument read, String name) {
      final rows = read.layers;
      final head = rows.indexWhere(
        (row) => row.role == PsdLayerRole.groupOpen && row.name == name,
      );
      final foot = rows.lastIndexWhere(
        (row) => row.role == PsdLayerRole.groupClose,
        head,
      );
      return rows.sublist(foot + 1, head);
    }

    testWidgets('its pages are folders of ONE file, the first at the bottom '
        'and alone shown (I-117-Q4: 「1페이지가 맨 아래, 눈 1페이지만 켬」) — '
        'each its strata, laying up into the page its PNG is — over the '
        'first page whole, laid a page at a time', (tester) async {
      final session = film();
      final state = await pumpDialog(tester, session, tab: 'conte');

      await pickPaperFormat(tester, 'export-conteformat', 'png');
      final madeForPngs = await partsOfRun(tester, state);
      final pages = [
        await pngPixels(tester, '${sheet}_p1.png'),
        await pngPixels(tester, '${sheet}_p2.png'),
      ];
      for (final page in ['${sheet}_p1.png', '${sheet}_p2.png']) {
        written(page).deleteSync();
      }
      await pickPaperFormat(tester, 'export-conteformat', 'psd');
      expect(
        tester.exportPreviewName,
        '$sheet.psd',
        reason: 'the plate names the one file every page is written in',
      );
      final steps = <(int, int)>[];
      state.debugOnProgress = (done, total) => steps.add((done, total));
      final madeForPsd = await partsOfRun(tester, state);

      expect(
        temp.listSync().map((file) => file.uri.pathSegments.last),
        ['$sheet.psd'],
        reason: 'one file, not a file a page',
      );
      final read = psd('$sheet.psd');
      final strata = [
        ...paperRows.take(3),
        strings.exStratumPicture,
        strings.exStratumInk,
      ];
      expect(
        [
          for (final row in read.layers)
            if (row.role != PsdLayerRole.groupClose)
              (row.name, row.role, row.blendKey, row.visible),
        ],
        [
          for (final page in ['p1', 'p2']) ...[
            for (final name in strata)
              (name, PsdLayerRole.raster, 'norm', true),
            (page, PsdLayerRole.groupOpen, 'pass', page == 'p1'),
          ],
        ],
        reason: 'bottom-up: the first page\'s folder, the only one shown, '
            'then the next over it — every row inside each shown, so a '
            'folder whose eye is put on shows its page whole',
      );
      expect(read.composite, pages.first, reason: 'the first page whole');
      for (final (index, page) in pages.indexed) {
        final rows = folder(read, 'p${index + 1}');
        expect(
          _offBy(_laidUp(rows, read.width, read.height), page),
          0,
          reason: 'p${index + 1}',
        );
        expect(
          _colours(rows.first.pixels!),
          hasLength(1),
          reason: 'p${index + 1}\'s paper alone: one colour, edge to edge',
        );
      }
      final ink = folder(read, 'p2').last;
      expect(ink.hasPixels, isTrue, reason: 'the band\'s ink, from the store');

      expect(steps, [(0, 3), (1, 3), (2, 3), (3, 3)]);
      expect(
        status(tester),
        strings.exDoneConteDocument('$sheet.psd', strings.exPageCount(2)),
      );
      expect(
        madeForPngs,
        2,
        reason: 'the cell\'s picture and its band\'s ink, once each',
      );
      expect(
        madeForPsd,
        madeForPngs,
        reason:
            'a picture is made for its row and the ink for its own — and '
            'the first page, whole, is the blank back',
      );
    });

    testWidgets('handed over once it is made — iOS asks its place of what is '
        'made — it is the one file the window named: a PSD by its name, '
        'not the PDF\'s', (tester) async {
      debugOperatingSystemOverride = 'ios';
      FolderPicker.debugOperatingSystem = 'ios';
      final handed = <String>[];
      FolderPicker.debugFilesExporter = (sources) async {
        for (final source in sources) {
          handed.add(fileNameOfPath(source));
          moveIntoFolder(source, temp.path);
        }
        return FolderGrant.granted(path: temp.path);
      };
      addTearDown(() {
        debugOperatingSystemOverride = null;
        FolderPicker.debugOperatingSystem = null;
        FolderPicker.debugFilesExporter = null;
      });
      final state = await pumpDialog(
        tester,
        film(),
        tab: 'conte',
        asksAfter: true,
      );
      await pickPaperFormat(tester, 'export-conteformat', 'psd');

      await tester.runAsync(state.export);
      await tester.pump();

      expect(handed, ['$sheet.psd']);
      expect(psd('$sheet.psd').layers, isNotEmpty);
    });

    testWidgets('stopped between pages, it writes nothing', (tester) async {
      final session = film();
      final state = await pumpDialog(tester, session, tab: 'conte');
      await pickPaperFormat(tester, 'export-conteformat', 'psd');
      state.debugOnProgress = (done, _) {
        if (done == 1) {
          state.cancelExport();
        }
      };

      await tester.runAsync(state.export);
      await tester.pump();

      expect(temp.listSync(), isEmpty);
      expect(status(tester), strings.exCancelled);
    });
  });
}

/// A 16px surface whose first tile is solid red — a stroke a store holds.
BitmapSurface _redSurface() {
  final pixels = Uint8List(8 * 8 * 4);
  for (var i = 0; i < pixels.length; i += 4) {
    pixels[i] = 0xFF;
    pixels[i + 3] = 0xFF;
  }
  return BitmapSurface(
    canvasSize: const CanvasSize(width: 16, height: 16),
    tileSize: 8,
    tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: 8, pixels: pixels)},
  );
}

/// [rows] laid one over the next, bottom-up, as Photoshop lays a row at full
/// strength in no blend: straight RGBA over a [width]×[height] nothing.
Uint8List _laidUp(List<PsdLayer> rows, int width, int height) {
  final colour = Float64List(width * height * 3);
  final cover = Float64List(width * height);
  for (final row in rows) {
    final pixels = row.pixels;
    if (pixels == null) {
      continue;
    }
    for (var y = 0; y < row.height; y += 1) {
      for (var x = 0; x < row.width; x += 1) {
        final from = (y * row.width + x) * 4;
        final alpha = pixels[from + 3] / 255;
        if (alpha == 0) {
          continue;
        }
        final to = (row.top + y) * width + row.left + x;
        for (var c = 0; c < 3; c += 1) {
          colour[to * 3 + c] =
              pixels[from + c] / 255 * alpha +
              colour[to * 3 + c] * (1 - alpha);
        }
        cover[to] = alpha + cover[to] * (1 - alpha);
      }
    }
  }
  final laid = Uint8List(width * height * 4);
  for (var p = 0; p < width * height; p += 1) {
    final alpha = cover[p];
    for (var c = 0; c < 3; c += 1) {
      laid[p * 4 + c] = alpha == 0
          ? 0
          : (colour[p * 3 + c] / alpha * 255).round().clamp(0, 255);
    }
    laid[p * 4 + 3] = (alpha * 255).round();
  }
  return laid;
}

/// How many channels of [laid] stand more than a rounding off [picture].
int _offBy(Uint8List laid, Uint8List picture) {
  expect(laid.length, picture.length);
  var off = 0;
  for (var i = 0; i < laid.length; i += 1) {
    if ((laid[i] - picture[i]).abs() > 2) {
      off += 1;
    }
  }
  return off;
}

/// Every colour [rgba] holds.
Set<int> _colours(Uint8List rgba) {
  final pixels = ByteData.sublistView(rgba);
  return {for (var i = 0; i < rgba.length; i += 4) pixels.getUint32(i)};
}
