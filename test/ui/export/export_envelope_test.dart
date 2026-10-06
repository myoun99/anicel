import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/envelope/cut_envelope_layout.dart';
import 'package:anicel/src/models/envelope/cut_envelope_paper.dart';
import 'package:anicel/src/models/envelope/cut_envelope_presets.dart';
import 'package:anicel/src/models/envelope/cut_envelope_source.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_builder.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_envelope_render.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import '../../helpers/export_scope_pick.dart';
import '../../helpers/temp_dir.dart';

/// The cut envelope (컷 봉투) as the Cels tab writes it (F-289, 유저
/// 2026-10-05: 「컷봉투탭도 셀 내부로 편입 … 기존의 컷봉투탭에 있던 용지는
/// 컷크기/실측용지 이거는 컷봉투 형식안에 넣고, 레이어 항목 버튼? 용지 서식
/// 내용 선화 고르는거 싹 다 필요없어보이니 삭제」): one picture a sheet —
/// at the cut's own pixel size, so it drops into a working file as a layer,
/// or on the real envelope's paper — behind its kind's prefix.
void main() {
  late Directory temp;

  setUp(() {
    AppExport.settings.value = AppExportSettings();
    temp = Directory.systemTemp.createTempSync('qa-export-envelope');
  });

  tearDown(() {
    AppExport.settings.value = AppExportSettings();
    deleteTempQuietly(temp);
  });

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

  Project project() => Project(
    id: const ProjectId('envelope-export'),
    name: 'Envelope Export',
    createdAt: DateTime.utc(2026, 8, 6),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Video',
        cuts: [cut('39'), cut('40')],
      ),
    ],
  );

  Future<(int, int, int, int)> pixelAt(ui.Image image, int x, int y) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final offset = (y * image.width + x) * 4;
    return (
      data!.getUint8(offset),
      data.getUint8(offset + 1),
      data.getUint8(offset + 2),
      data.getUint8(offset + 3),
    );
  }

  CutEnvelopeLayout analogOn(int width, int height) => CutEnvelopeLayout.fit(
    form: CutEnvelopePresets.analog,
    paperWidth: width.toDouble(),
    paperHeight: height.toDouble(),
  );

  group('paper', () {
    test('the cut mode takes the canvas verbatim, so the PNG drops in as a '
        'layer', () {
      final paper = cutEnvelopePaperSize(
        mode: CutEnvelopePaperMode.cut,
        cut: cut('39'),
      );

      expect(paper, (width: 320, height: 240));
    });
  });

  group('render', () {
    testWidgets('the render is the paper, at paper size — and a preview '
        'size scales the same drawing rather than misplacing it', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final layout = analogOn(320, 240);
        final full = await renderCutEnvelopeImage(
          face: const TextStyle(),
          layout: layout,
          source: const CutEnvelopeSource(),
        );
        addTearDown(full.dispose);
        final preview = await renderCutEnvelopeImage(
          face: const TextStyle(),
          layout: layout,
          source: const CutEnvelopeSource(),
          outputSize: (width: 160, height: 120),
        );
        addTearDown(preview.dispose);

        expect((full.width, full.height), (320, 240));
        expect((preview.width, preview.height), (160, 120));
        // The same point of the sheet is the same colour in both: the
        // fit-to-size path scales, it does not crop.
        final fullPaper = await pixelAt(full, 8, 8);
        final previewPaper = await pixelAt(preview, 4, 4);
        expect(previewPaper, fullPaper);
      });
    });

    testWidgets('a box of another shape than the paper holds the paper '
        'centred — the one contain, not a paper laid from the box\'s corner '
        '(F-294)', (tester) async {
      await tester.runAsync(() async {
        // A 320×240 paper in a box twice as tall: it lies in the middle
        // half, rows 120 to 360.
        final tall = await renderCutEnvelopeImage(
          face: const TextStyle(),
          layout: analogOn(320, 240),
          source: const CutEnvelopeSource(),
          outputSize: (width: 320, height: 480),
        );
        addTearDown(tall.dispose);

        expect((await pixelAt(tall, 160, 60)).$4, 0, reason: 'over it');
        expect((await pixelAt(tall, 8, 128)).$4, 255, reason: 'the paper');
        expect((await pixelAt(tall, 8, 352)).$4, 255, reason: 'the paper');
        expect((await pixelAt(tall, 160, 420)).$4, 0, reason: 'under it');
      });
    });

  });

  group('dialog', () {
    Future<ExportDialogState> pumpDialog(
      WidgetTester tester,
      EditorSessionManager session,
    ) async {
      // The envelope alone, so a folder's files are the envelope's.
      AppExport.settings.value = AppExportSettings(
        lastSpecs: const ExportTabSpecs(
          cels: CelsExportSpec(kinds: {ExportCelKind.envelope}),
        ),
      );
      await tester.binding.setSurfaceSize(const Size(1280, 660));
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
      await tester.tap(find.byKey(const ValueKey<String>('export-tab-cels')));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('export-browse-button')),
      );
      await tester.pump();
      await tester.pump();
      return state;
    }

    /// The settings column scrolls; a chip below the fold has to be
    /// brought into view before it can be tapped.
    Future<void> tapSetting(WidgetTester tester, String key) async {
      final finder = find.byKey(ValueKey<String>(key));
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.tap(finder);
      await tester.pump();
    }

    testWidgets('the envelope kind writes one PNG for the active cut, at '
        'the cut\'s own size, behind its prefix', (tester) async {
      final session = EditorSessionManager(initialProject: project());
      addTearDown(session.dispose);
      final state = await pumpDialog(tester, session);

      await tester.runAsync(state.export);
      await tester.pump();

      final file = File(
        '${temp.path}${Platform.pathSeparator}'
        '_CUT39_envelope.png',
      );
      expect(file.existsSync(), isTrue);
      final image = await tester.runAsync(
        () => decodeImageFromList(file.readAsBytesSync()),
      );
      expect((image!.width, image.height), (320, 240));
      image.dispose();
      // The other cut stays out of it: the scope is the ACTIVE cut.
      expect(
        File(
          '${temp.path}${Platform.pathSeparator}_CUT40_envelope.png',
        ).existsSync(),
        isFalse,
      );
    });

    testWidgets('a 겸용 cut and its sibling are ONE envelope, so the whole '
        'project writes one file for the pair', (tester) async {
      final session = EditorSessionManager(initialProject: project());
      addTearDown(session.dispose);
      // Cut 40 becomes 39's 겸용 sibling: one folder in the studio, one
      // envelope here.
      session.selectCut(const CutId('39'));
      session.cutVerbs.convertActiveCutToLinked(const CutId('40'));
      final state = await pumpDialog(tester, session);
      await tester.pickExportProjectScope();

      await tester.runAsync(state.export);
      await tester.pump();

      final written = temp
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last)
          .toList();
      expect(
        written,
        hasLength(1),
        reason: 'two cuts, one shared sheet — not one file each',
      );
      // Drain the prerender scheduler's zero-delay warming loop, woken by
      // the cut edit (its timers outlive dispose).
      await tester.pumpAndSettle();
    });

    testWidgets('what was written on the sheet rides the export, in the box '
        'it was written in', (tester) async {
      final session = EditorSessionManager(initialProject: project());
      addTearDown(session.dispose);
      final inkBox = CutEnvelopePresets.analog.inkBoxes.first;
      session.renderCaches.envelopeInkStore.storeBakedSurface(
        envelopeInkBoxKey(const CutId('39'), inkBox.id),
        _inkSurface(),
      );
      final state = await pumpDialog(tester, session);
      // The real-sheet size, so the 8px ink tile is several output pixels
      // wide rather than a fraction of one.
      await tapSetting(tester, 'export-envelope-paper-sheet');

      await tester.runAsync(state.export);
      await tester.pump();

      final file = File(
        '${temp.path}${Platform.pathSeparator}_CUT39_envelope.png',
      );
      expect(file.existsSync(), isTrue);
      final image = (await tester.runAsync(
        () => decodeImageFromList(file.readAsBytesSync()),
      ))!;
      addTearDown(image.dispose);

      // The ink lands at the box's TOP-LEFT — the surface origin.
      final layout = analogOn(image.width, image.height);
      final placed = layout.placedBoxes.firstWhere(
        (box) => box.box.id == inkBox.id,
      );
      final inked = await tester.runAsync(
        () => pixelAt(image, placed.x.round() + 1, placed.y.round() + 1),
      );
      expect(inked!.$1, greaterThan(200), reason: 'red ink, from the store');
      expect(inked.$2, lessThan(80));
    });

    testWidgets('ink PARKED on a sheet nobody has open rides the export and '
        'stays parked — the export looks, it does not thaw '
        '(render-reads-thaw-into-hot)', (tester) async {
      final session = EditorSessionManager(initialProject: project());
      addTearDown(session.dispose);
      final store = session.renderCaches.envelopeInkStore;
      final inkBox = CutEnvelopePresets.analog.inkBoxes.first;
      final key = envelopeInkBoxKey(const CutId('39'), inkBox.id);
      store.restoreBaked({
        key: AnicelCelBlob.encode(
          AnicelCelEntry.fromSurface(key, _inkSurface()),
        ),
      });
      final state = await pumpDialog(tester, session);
      await tapSetting(tester, 'export-envelope-paper-sheet');

      await tester.runAsync(state.export);
      await tester.pump();

      final image = (await tester.runAsync(
        () => decodeImageFromList(
          File(
            '${temp.path}${Platform.pathSeparator}_CUT39_envelope.png',
          ).readAsBytesSync(),
        ),
      ))!;
      addTearDown(image.dispose);
      final placed = analogOn(image.width, image.height).placedBoxes
          .firstWhere((box) => box.box.id == inkBox.id);
      final inked = await tester.runAsync(
        () => pixelAt(image, placed.x.round() + 1, placed.y.round() + 1),
      );
      expect(inked!.$1, greaterThan(200), reason: 'LIVENESS: the ink printed');
      expect(store.hotBakedBytes, 0, reason: 'nothing thawed into the budget');
      expect(store.isCelCold(key), isTrue, reason: 'the ink stays parked');
    });

    testWidgets('the export prints the WORK\'s form, and the window has '
        'no form picker of its own', (tester) async {
      // 유저 답 envelope-form-in-export: 「출력은 작품의 서식을 따른다
      // (출력 창의 고르기는 뺀다)」.
      final session = EditorSessionManager(
        initialProject: project().copyWith(
          timesheetInfo: TimesheetInfo.empty.copyWith(
            envelopeFormId: CutEnvelopePresets.digitalId,
          ),
        ),
      );
      addTearDown(session.dispose);
      final state = await pumpDialog(tester, session);
      for (final form in CutEnvelopePresets.all) {
        expect(
          find.byKey(ValueKey<String>('export-envelope-form-${form.id}')),
          findsNothing,
        );
      }
      // The real sheet is the envelope's own paper whichever form prints
      // (F-294 — A4 on its side at 300dpi, the panel's), so the PAPER'S
      // COLOUR says which did: the two bundled forms print on different
      // papers.
      await tapSetting(tester, 'export-envelope-paper-sheet');
      expect(state.debugSpecs.cels.envelopePaper, CutEnvelopePaperMode.sheet);

      await tester.runAsync(state.export);
      await tester.pump();

      final file = File(
        '${temp.path}${Platform.pathSeparator}_CUT39_envelope.png',
      );
      final image = (await tester.runAsync(
        () => decodeImageFromList(file.readAsBytesSync()),
      ))!;
      addTearDown(image.dispose);
      expect(
        (image.width, image.height),
        (3508, 2480),
        reason: 'the real sheet is its paper\'s own pixels',
      );
      (int, int, int) rgbOf(int argb) =>
          ((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF);
      final digital = rgbOf(CutEnvelopePresets.digital.paperArgb);
      expect(digital, isNot(rgbOf(CutEnvelopePresets.analog.paperArgb)));
      // The paper's corner, in the margin the form leaves.
      final corner = (await tester.runAsync(() => pixelAt(image, 2, 2)))!;
      expect((corner.$1, corner.$2, corner.$3), digital);
    });

    testWidgets('the real sheet is the envelope\'s paper at its own pixels '
        '— there is no scale to pick — and as a JPG it is a JPG', (
      tester,
    ) async {
      final session = EditorSessionManager(initialProject: project());
      addTearDown(session.dispose);
      final state = await pumpDialog(tester, session);
      await tapSetting(tester, 'export-envelope-paper-sheet');
      expect(
        find.byKey(const ValueKey<String>('export-envelopescale-2')),
        findsNothing,
        reason: '유저 2026-10-06: 「시트 이미지는 배율 없앰. 늘 용지 그대로」',
      );
      // Folded, the module's head says what it writes.
      final head = find.text(AppText.strings.exEnvelopeFormat);
      await tester.ensureVisible(head);
      await tester.pump();
      await tester.tap(head);
      await tester.pump();
      expect(
        find.text(
          '${AppText.strings.exEnvelopeFormat} — '
          'PNG · ${AppText.strings.exRealSheet}',
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.textContaining('${AppText.strings.exEnvelopeFormat} — '),
      );
      await tester.pump();

      await tester.runAsync(state.export);
      await tester.pump();
      final png = File(
        '${temp.path}${Platform.pathSeparator}_CUT39_envelope.png',
      ).readAsBytesSync();
      // A PNG's size from its IHDR — the first chunk, big-endian at 16.
      final header = ByteData.sublistView(png);
      expect((header.getUint32(16), header.getUint32(20)), (3508, 2480));

      await tapSetting(tester, 'export-envelope-format-jpg');
      expect(
        state.debugSpecs.cels.envelopeImage.stillFormat,
        ExportStillFormat.jpg,
      );
      expect(
        find.byKey(const ValueKey<String>('export-envelope-format-quality')),
        findsOneWidget,
        reason: 'a JPG has a quality',
      );
      await tester.runAsync(state.export);
      await tester.pump();
      final jpg = File(
        '${temp.path}${Platform.pathSeparator}_CUT39_envelope.jpg',
      );
      expect(jpg.existsSync(), isTrue);
      expect(
        jpg.readAsBytesSync().take(3),
        [0xFF, 0xD8, 0xFF],
        reason: 'a JPG by its bytes, not by its name alone',
      );
    });
  });
}

BitmapSurface _inkSurface() {
  final pixels = Uint8List(8 * 8 * 4);
  for (var i = 0; i < pixels.length; i += 4) {
    pixels[i] = 0xFF;
    pixels[i + 3] = 0xFF;
  }
  return BitmapSurface(
    canvasSize: const CanvasSize(width: 16, height: 16),
    tileSize: 8,
    tiles: {
      TileCoord(x: 0, y: 0): BitmapTile(
        size: 8,
        pixels: pixels,
      ),
    },
  );
}
