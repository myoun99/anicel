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
import 'package:anicel/src/models/sheet_paint_layer.dart';
import 'package:anicel/src/models/envelope/cut_envelope_paper.dart';
import 'package:anicel/src/models/envelope/cut_envelope_presets.dart';
import 'package:anicel/src/models/envelope/cut_envelope_source.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_builder.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_envelope_render.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';

/// The Envelope export tab: the 컷봉투 as PNG — at the cut's own pixel size
/// so it drops into a working file as a layer, or at print size; flat, or
/// one file per stratum so whoever opens it can delete the filled-in
/// values without losing the printed form.
void main() {
  late Directory temp;

  setUp(() {
    AppExport.settings.value = AppExportSettings();
    temp = Directory.systemTemp.createTempSync('qa-export-envelope');
  });

  tearDown(() {
    AppExport.settings.value = AppExportSettings();
    try {
      temp.deleteSync(recursive: true);
    } on Object {
      // Windows may hold a handle a beat; leaking a temp dir beats failing.
    }
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

  group('spec', () {
    test('the default is the CUT\'s own pixels, every layer, one file', () {
      const spec = EnvelopeExportSpec();

      expect(spec.paperMode, CutEnvelopePaperMode.cut);
      expect(spec.layers, EnvelopeExportSpec.defaultLayers);
      expect(spec.orderedLayers, SheetPaintLayer.values);
      expect(spec.separateLayerFiles, isFalse);
      expect(
        spec.toJson(),
        isEmpty,
        reason: 'a default spec serializes to nothing, like its siblings',
      );
    });

    test('a chosen shape round-trips through JSON', () {
      const spec = EnvelopeExportSpec(
        formId: CutEnvelopePresets.digitalId,
        paperMode: CutEnvelopePaperMode.sheet,
        scope: ExportScopeKind.project,
        sheetWidth: 3508,
        layers: {SheetPaintLayer.form, SheetPaintLayer.ink},
        separateLayerFiles: true,
      );

      expect(EnvelopeExportSpec.fromJson(spec.toJson()), spec);
      expect(
        exportTabSpecFromJson(ExportTab.envelope, spec.toJson()),
        spec,
        reason: 'the tab discriminator reaches the envelope parser',
      );
    });

    test('turning the last layer off is refused — a blank page is not an '
        'export', () {
      const spec = EnvelopeExportSpec(layers: {SheetPaintLayer.form});

      expect(spec.withLayer(SheetPaintLayer.form, false).layers, {
        SheetPaintLayer.form,
      });
      expect(spec.withLayer(SheetPaintLayer.ink, true).layers, {
        SheetPaintLayer.form,
        SheetPaintLayer.ink,
      });
    });

    test('an empty layer list in a file reads as the default, not as a '
        'blank sheet', () {
      final spec = EnvelopeExportSpec.fromJson({'layers': <String>[]});

      expect(spec.layers, EnvelopeExportSpec.defaultLayers);
    });

    test('the whole tab-spec set carries the envelope through JSON', () {
      const specs = ExportTabSpecs(
        envelope: EnvelopeExportSpec(separateLayerFiles: true),
      );

      expect(
        ExportTabSpecs.fromJson(specs.toJson()).envelope.separateLayerFiles,
        isTrue,
      );
      expect(specs.specFor(ExportTab.envelope), specs.envelope);
      expect(
        specs.withSpec(const EnvelopeExportSpec(sheetWidth: 1240)).envelope,
        const EnvelopeExportSpec(sheetWidth: 1240),
      );
    });
  });

  group('paper', () {
    test('the cut mode takes the canvas verbatim, so the PNG drops in as a '
        'layer', () {
      final paper = cutEnvelopePaperSize(
        mode: CutEnvelopePaperMode.cut,
        cut: cut('39'),
        formAspectRatio: CutEnvelopePresets.analog.aspectRatio,
      );

      expect(paper, (width: 320, height: 240));
    });

    test('the sheet mode is the form\'s own shape at the chosen width', () {
      final paper = cutEnvelopePaperSize(
        mode: CutEnvelopePaperMode.sheet,
        cut: cut('39'),
        formAspectRatio: 2,
        sheetWidth: 1000,
      );

      expect(paper, (width: 1000, height: 500));
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
          layout: layout,
          source: const CutEnvelopeSource(),
        );
        addTearDown(full.dispose);
        final preview = await renderCutEnvelopeImage(
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

    testWidgets('a layer subset draws only that stratum — the form alone '
        'is transparent where the paper would be', (tester) async {
      await tester.runAsync(() async {
        final layout = analogOn(320, 240);
        final flat = await renderCutEnvelopeImage(
          layout: layout,
          source: const CutEnvelopeSource(),
        );
        addTearDown(flat.dispose);
        final formOnly = await renderCutEnvelopeImage(
          layout: layout,
          source: const CutEnvelopeSource(),
          layers: const {SheetPaintLayer.form},
        );
        addTearDown(formOnly.dispose);

        // Inside the form, away from any rule: kraft on the flat sheet,
        // nothing at all on the form layer.
        final flatPixel = await pixelAt(flat, 160, 130);
        expect(flatPixel.$4, 255, reason: 'the flat sheet is opaque paper');
        final formPixel = await pixelAt(formOnly, 160, 130);
        expect(
          formPixel.$4,
          0,
          reason: 'only the paper layer paints a background',
        );
      });
    });
  });

  group('dialog', () {
    Future<ExportDialogState> pumpDialog(
      WidgetTester tester,
      EditorSessionManager session,
    ) async {
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
      await tester.tap(
        find.byKey(const ValueKey<String>('export-tab-envelope')),
      );
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

    testWidgets('the Envelope tab writes one PNG for the active cut, at the '
        'cut\'s own size', (tester) async {
      final session = EditorSessionManager(initialProject: project());
      addTearDown(session.dispose);
      final state = await pumpDialog(tester, session);

      await tester.runAsync(state.export);
      await tester.pump();

      final file = File(
        '${temp.path}${Platform.pathSeparator}'
        'CUT39_envelope.png',
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
          '${temp.path}${Platform.pathSeparator}CUT40_envelope.png',
        ).existsSync(),
        isFalse,
      );
    });

    testWidgets('layered output writes one PNG per stratum, all the same '
        'size so they stack', (tester) async {
      final session = EditorSessionManager(initialProject: project());
      addTearDown(session.dispose);
      final state = await pumpDialog(tester, session);
      await tapSetting(tester, 'export-envelope-files-layered');

      await tester.runAsync(state.export);
      await tester.pump();

      for (final layer in SheetPaintLayer.values) {
        final file = File(
          '${temp.path}${Platform.pathSeparator}'
          'CUT39_envelope_${layer.jsonValue}.png',
        );
        expect(
          file.existsSync(),
          isTrue,
          reason: 'the ${layer.jsonValue} layer ships as its own PNG',
        );
        final image = await tester.runAsync(
          () => decodeImageFromList(file.readAsBytesSync()),
        );
        expect((image!.width, image.height), (320, 240));
        image.dispose();
      }
    });

    testWidgets('a 겸용 cut and its sibling are ONE envelope, so the whole '
        'project writes one file for the pair', (tester) async {
      final session = EditorSessionManager(initialProject: project());
      addTearDown(session.dispose);
      // Cut 40 becomes 39's 겸용 sibling: one folder in the studio, one
      // envelope here.
      session.selectCut(const CutId('39'));
      session.convertActiveCutToLinked(const CutId('40'));
      final state = await pumpDialog(tester, session);
      await tapSetting(tester, 'export-scope-project');

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
      session.envelopeInkStore.storeBakedSurface(
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
        '${temp.path}${Platform.pathSeparator}CUT39_envelope.png',
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
        coord: TileCoord(x: 0, y: 0),
        size: 8,
        pixels: pixels,
      ),
    },
  );
}
