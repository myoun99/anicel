import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/conte_pdf_writer.dart';
import 'package:anicel/src/ui/export/export_conte_render.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';

/// The Conte export tab (work-order step 6): the picture conte as one
/// VECTOR PDF (embedded OFL fonts, per-run JP/KR fallback) or as page
/// images — driven end-to-end through the dialog.
void main() {
  late Directory temp;

  setUp(() {
    AppExport.settings.value = AppExportSettings();
    temp = Directory.systemTemp.createTempSync('qa-export-conte');
  });

  tearDown(() {
    AppExport.settings.value = AppExportSettings();
    try {
      temp.deleteSync(recursive: true);
    } on Object {
      // Windows may hold a handle a beat; leaking a temp dir beats failing.
    }
  });

  Layer storyboardLayer(String cutId, Map<int, int> divisions) => Layer(
    id: LayerId('$cutId-sb'),
    name: 'SB',
    kind: LayerKind.storyboard,
    frames: [
      for (final start in divisions.keys)
        Frame(id: FrameId('$cutId-$start'), duration: 1, strokes: const []),
    ],
    timeline: {
      for (final entry in divisions.entries)
        entry.key: TimelineExposure.drawing(
          FrameId('$cutId-${entry.key}'),
          length: entry.value,
        ),
    },
  );

  /// Two cuts with storyboard rows; the SE row carries mixed-script
  /// dialogue (Japanese speaker brackets + Hangul) so the PDF's per-run
  /// font fallback is exercised for real.
  Project project() => Project(
    id: const ProjectId('conte-export'),
    name: 'Conte Export',
    cameraSize: const CanvasSize(width: 32, height: 18),
    createdAt: DateTime.utc(2026, 7, 29),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('39'),
            name: '39',
            duration: 10,
            canvasSize: const CanvasSize(width: 64, height: 36),
            layers: [storyboardLayer('39', {0: 5, 5: 5})],
          ),
          Cut(
            id: const CutId('40'),
            name: '40',
            duration: 12,
            canvasSize: const CanvasSize(width: 64, height: 36),
            layers: [storyboardLayer('40', {0: 12})],
          ),
        ],
        seLayers: [
          Layer(
            id: const LayerId('se-1'),
            name: 'S1',
            kind: LayerKind.se,
            frames: [
              Frame(
                id: const FrameId('line-1'),
                duration: 3,
                name: 'いくぞ 가자',
                seName: 'ハヤト',
                strokes: const [],
              ),
            ],
            timeline: const {
              2: TimelineExposure.drawing(FrameId('line-1'), length: 3),
            },
          ),
        ],
      ),
    ],
  );

  bool isPdf(Uint8List bytes) =>
      bytes.length > 4 &&
      bytes[0] == 0x25 && // %
      bytes[1] == 0x50 && // P
      bytes[2] == 0x44 && // D
      bytes[3] == 0x46; // F

  testWidgets('writeContePdf produces a real multi-script PDF from the '
      'panel\'s own layout', (tester) async {
    final bytes = await tester.runAsync(() async {
      final source = buildConteSheetSource(project());
      final pages = layoutConteSheet(
        source,
        metrics: const ConteSheetMetrics(cameraAspect: 16 / 9),
      );
      expect(pages, isNotEmpty);
      final fonts = await ContePdfFonts.load();
      return writeContePdf(source: source, pages: pages, fonts: fonts);
    });

    expect(bytes, isNotNull);
    expect(isPdf(bytes!), isTrue, reason: 'starts with %PDF');
    // The embedded fonts SUBSET: only the used glyphs ship, so the file
    // stays kilobytes despite the 6MB font assets.
    expect(bytes.length, greaterThan(2000));
  });

  Future<ui.Image> solidInk(int width, int height) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFFFF0000),
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  Future<(int, int, int)> pixelAt(ui.Image image, int x, int y) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final offset = (y * image.width + x) * 4;
    return (
      data!.getUint8(offset),
      data.getUint8(offset + 1),
      data.getUint8(offset + 2),
    );
  }

  testWidgets('R5: cell ink draws on the page render inside its ROW BAND '
      'and is clipped to it — the PNG export inherits it from the same '
      'painter', (tester) async {
    await tester.runAsync(() async {
      final source = buildConteSheetSource(project());
      final pages = layoutConteSheet(
        source,
        metrics: const ConteSheetMetrics(cameraAspect: 16 / 9),
      );
      final page = pages.first;
      final metrics = page.metrics;
      final cell = page.cells.first;
      final band = cell.rowBandRect(metrics);
      final rowKey = conteInkRowKey(
        CutId(cell.cutId),
        cell.source.frameId!,
      );
      final ink = await solidInk(
        (band.width * 4).ceil(),
        (band.height * 4).ceil(),
      );
      try {
        final rendered = await renderContePageImage(
          page: page,
          source: source,
          inkImageFor: (key) => key == rowKey ? ink : null,
        );
        try {
          final inside = await pixelAt(
            rendered,
            band.center.dx.round(),
            band.center.dy.round(),
          );
          expect(inside.$1, greaterThan(200), reason: 'band center is inked');
          expect(inside.$2, lessThan(60));
          final above = await pixelAt(
            rendered,
            band.center.dx.round(),
            (metrics.margin + 4).round(),
          );
          expect(
            above,
            (255, 255, 255),
            reason: 'the header stays paper — the band clips its ink',
          );
        } finally {
          rendered.dispose();
        }
      } finally {
        ink.dispose();
      }
    });
  });

  testWidgets('R5: the PDF embeds the cell ink raster (the file grows by '
      'an image object and stays a PDF)', (tester) async {
    final (without, withInk) = (await tester.runAsync(() async {
      final source = buildConteSheetSource(project());
      final pages = layoutConteSheet(
        source,
        metrics: const ConteSheetMetrics(cameraAspect: 16 / 9),
      );
      final cell = pages.first.cells.first;
      final band = cell.rowBandRect(pages.first.metrics);
      final rowKey = conteInkRowKey(CutId(cell.cutId), cell.source.frameId!);
      final ink = await solidInk(
        (band.width * 4).ceil(),
        (band.height * 4).ceil(),
      );
      try {
        final fonts = await ContePdfFonts.load();
        final plain = await writeContePdf(
          source: source,
          pages: pages,
          fonts: fonts,
        );
        final inked = await writeContePdf(
          source: source,
          pages: pages,
          fonts: fonts,
          inkPictures: {rowKey: (await ContePdfPicture.fromImage(ink))!},
        );
        return (plain, inked);
      } finally {
        ink.dispose();
      }
    }))!;

    expect(isPdf(withInk), isTrue);
    expect(
      withInk.length,
      greaterThan(without.length),
      reason: 'the ink raster embeds as an image object',
    );
  });

  testWidgets('the dialog\'s Conte tab exports conte.pdf into the chosen '
      'location', (tester) async {
    final session = EditorSessionManager(initialProject: project());
    addTearDown(session.dispose);
    await tester.binding.setSurfaceSize(const Size(1120, 660));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session,
            exportDirectoryPicker: () async => temp.path,
            formatAvailability: ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.pump();
    final state = tester.state<ExportDialogState>(find.byType(ExportDialog));

    await tester.tap(find.byKey(const ValueKey<String>('export-tab-conte')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('export-browse-button')),
    );
    await tester.pump();
    await tester.pump();

    await tester.runAsync(state.export);
    await tester.pump();

    final pdf = File('${temp.path}${Platform.pathSeparator}conte.pdf');
    expect(pdf.existsSync(), isTrue);
    expect(isPdf(pdf.readAsBytesSync()), isTrue);
    final status = tester.widget<Text>(
      find.byKey(const ValueKey<String>('export-status')),
    );
    expect(status.data, contains('conte.pdf'));
  });

  testWidgets('the page-image format writes one PNG per page through the '
      'shared stream', (tester) async {
    final session = EditorSessionManager(initialProject: project());
    addTearDown(session.dispose);
    await tester.binding.setSurfaceSize(const Size(1120, 660));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session,
            exportDirectoryPicker: () async => temp.path,
            formatAvailability: ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.pump();
    final state = tester.state<ExportDialogState>(find.byType(ExportDialog));

    await tester.tap(find.byKey(const ValueKey<String>('export-tab-conte')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('export-conteformat-png')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('export-browse-button')),
    );
    await tester.pump();
    await tester.pump();

    await tester.runAsync(state.export);
    await tester.pump();

    final files = temp
        .listSync()
        .whereType<File>()
        .map((file) => file.path.split(Platform.pathSeparator).last)
        .toList();
    expect(files, contains('conte.png'));
  });

  test('the conte spec round-trips through the persisted tab specs', () {
    const specs = ExportTabSpecs(
      conte: ConteExportSpec(
        format: ExportConteFormat.pageImage,
        sheetScale: 3,
      ),
    );
    final restored = ExportTabSpecs.fromJson(specs.toJson());
    expect(restored.conte.format, ExportConteFormat.pageImage);
    expect(restored.conte.sheetScale, 3);
    expect(restored, specs);
    // Old persisted JSON without a conte entry stays readable.
    expect(
      ExportTabSpecs.fromJson(const {'sequence': <String, dynamic>{}}).conte,
      const ConteExportSpec(),
    );
  });
}
