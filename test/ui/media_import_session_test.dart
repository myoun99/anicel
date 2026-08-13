import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/import/cut_folder_parse.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../helpers/fake_pdf_document.dart';

/// The R3b import verbs end to end: a real PNG on disk becomes a layer /
/// cut whose cels live in the brush-frame store like drawn ones, with
/// reference registration, rasterize, undo and the folder import's
/// 겸용 follow-up. All real IO/codec work runs inside tester.runAsync
/// (the fake-async zone never completes file futures).
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-import-test');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } on Object {
      // Windows keeps handles briefly; leftovers live in systemTemp.
    }
  });

  Future<String> writePng(
    String name, {
    int width = 8,
    int height = 8,
    int seed = 0xFF3366FF,
  }) async {
    final pixels = Uint8List(width * height * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = (seed >> 16) & 0xFF;
      pixels[i + 1] = (seed >> 8) & 0xFF;
      pixels[i + 2] = seed & 0xFF;
      pixels[i + 3] = 0xFF;
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    return file.path;
  }

  testWidgets('importImageFile as a NEW CUT (reference mode): image layer '
      'born covering, asset registered, cel pixels in the store; ONE undo '
      'removes cut and registration together', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final cutsBefore = s.repository.requireProject().tracks.first.cuts.length;

    final imported = await tester.runAsync(() async {
      final path = await writePng('bg.png');
      return s.importImageFile(
        path: path,
        destination: ImportDestination.newCut,
        lengthFrames: 12,
        copyIntoProject: false,
      );
    });
    expect(imported, isTrue);

    final track = s.repository.requireProject().tracks.first;
    expect(track.cuts.length, cutsBefore + 1);
    final cut = track.cuts.last;
    expect(s.activeCutId, cut.id, reason: 'the import selects its cut');
    expect(cut.duration, 12);
    final layer = cut.layers.firstWhere(
      (layer) => layer.kind == LayerKind.image,
    );
    expect(layer.mediaReference, isNotNull);
    expect(layer.timeline[0]!.length, 12, reason: 'born covering');
    expect(
      s.celHasContentForLayer(layer, 0),
      isTrue,
      reason: 'the baked cel reads as drawn (store content signal)',
    );
    expect(
      s.mediaAssets.any((asset) => asset.kind == MediaAssetKind.image),
      isTrue,
      reason: 'reference mode registers the asset',
    );

    s.undo();
    final afterUndo = s.repository.requireProject();
    expect(afterUndo.tracks.first.cuts.length, cutsBefore);
    expect(
      afterUndo.mediaAssets.any((a) => a.kind == MediaAssetKind.image),
      isFalse,
      reason: 'the registration rides the same undo',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('importImageFile into the ACTIVE cut with rasterize: layer '
      'added with NO reference and NO registration (§3: absorbed pixels '
      'register nothing)', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final layersBefore = s.requireActiveCut.layers.length;

    final imported = await tester.runAsync(() async {
      final path = await writePng('ref.png', seed: 0xFF22AA44);
      return s.importImageFile(
        path: path,
        destination: ImportDestination.activeCutLayer,
        rasterize: true,
        copyIntoProject: false,
      );
    });
    expect(imported, isTrue);

    final cut = s.requireActiveCut;
    expect(cut.layers.length, layersBefore + 1);
    final layer = cut.layers.firstWhere(
      (layer) => layer.kind == LayerKind.image,
    );
    expect(layer.mediaReference, isNull);
    expect(
      layer.timeline[0]!.length,
      cut.duration,
      reason: 'the covering normalization holds it to the cut length',
    );
    expect(s.mediaAssets, isEmpty);
    expect(s.celHasContentForLayer(layer, 0), isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('rasterizeActiveLayer nulls the reference, keeps the pixels '
      'and unregisters the orphaned asset; undo restores both', (
    tester,
  ) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    await tester.runAsync(() async {
      final path = await writePng('paper.png');
      await s.importImageFile(
        path: path,
        destination: ImportDestination.activeCutLayer,
        copyIntoProject: false,
      );
    });
    final layer = s.requireActiveCut.layers.firstWhere(
      (layer) => layer.kind == LayerKind.image,
    );
    s.selectLayer(layer.id);
    expect(s.canRasterizeActiveLayer, isTrue);
    expect(s.mediaAssets, hasLength(1));

    s.rasterizeActiveLayer();
    final after = s.requireActiveCut.layers.firstWhere(
      (l) => l.id == layer.id,
    );
    expect(after.mediaReference, isNull);
    expect(after.kind, LayerKind.image, reason: 'kind never changes');
    expect(s.mediaAssets, isEmpty, reason: 'orphaned asset unregisters');
    expect(
      s.celHasContentForLayer(after, 0),
      isTrue,
      reason: 'the pixels were always the cels',
    );

    s.undo();
    final restored = s.requireActiveCut.layers.firstWhere(
      (l) => l.id == layer.id,
    );
    expect(restored.mediaReference, isNotNull);
    expect(s.mediaAssets, hasLength(1));
    await tester.pumpAndSettle();
  });

  testWidgets('importCutFolder: symbol layers with NAMED cels one comma '
      'each, _BG picture at the bottom, and a multi-cut folder creates '
      '겸용 linked cuts per extra number', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    final warnings = await tester.runAsync(() async {
      const root = 'csm_13_069_077_loeks';
      final sep = Platform.pathSeparator;
      await writePng('$root${sep}A1.png', seed: 0xFF111111);
      await writePng('$root${sep}A2.png', seed: 0xFF222222);
      await writePng('$root${sep}A3.png', seed: 0xFF333333);
      await writePng('$root${sep}B1.png', seed: 0xFF444444);
      await writePng('$root${sep}_BG.png', seed: 0xFF555555);
      return s.importCutFolder(
        folderPath: '${tempDir.path}$sep$root',
        copyIntoProject: false,
      );
    });
    expect(warnings, isNotNull);

    final track = s.repository.requireProject().tracks.first;
    final imported = track.cuts.firstWhere((cut) => cut.name == '069');
    expect(imported.duration, 3, reason: 'longest layer = 3 cels');

    final bg = imported.layers.first;
    expect(bg.kind, LayerKind.image);
    expect(bg.name, 'BG');

    final a = imported.layers.firstWhere((l) => l.name == 'A');
    expect(a.kind, LayerKind.animation);
    expect(
      a.frames.map((f) => f.name),
      ['1', '2', '3'],
      reason: 'cel numbers become frame names',
    );
    expect(a.timeline.length, 3, reason: 'one comma each');
    // The linked-cut follow-up moved the active cut; content checks read
    // the ACTIVE cut, so come back to the imported one first.
    s.selectCut(imported.id);
    expect(s.celHasContentForLayer(a, 0), isTrue);

    final b = imported.layers.firstWhere((l) => l.name == 'B');
    expect(b.frames, hasLength(1));

    // Rule H: the second number became a LINKED cut sharing the cels.
    final linked = track.cuts.firstWhere((cut) => cut.name == '077');
    expect(linked.id, isNot(imported.id));
    final group = s.repository.requireProject().linkRegistry.groupOf(
      cutId: imported.id,
      layerId: a.id,
    );
    expect(group, isNotNull, reason: 'the extra cut links the cel banks');
    expect(group!.members, hasLength(2));
    await tester.pumpAndSettle();
  });

  testWidgets('importCutFolder stamps the CARRY answer on its reference '
      'registrations, under the kind ceiling', (tester) async {
    // 🚨 The planner is handed a folder, not a window, so it cannot know
    // the answer — and the session used to express it by copying the file
    // into `.assets/Media` and nothing else. The pool entry itself still
    // said `carried: false`, which is the one thing the save reads, so
    // the first save after a folder import left every timesheet scan
    // OUTSIDE the archive. It only came right on a reopen, through the
    // older `sourcePath` spelling of the same answer.
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    final warnings = await tester.runAsync(() async {
      const root = 'csm_13_069_loeks';
      final sep = Platform.pathSeparator;
      await writePng('$root${sep}A1.png', seed: 0xFF111111);
      await writePng('$root${sep}_TS_a.png', seed: 0xFF222222);
      final movie = File('${tempDir.path}$sep$root${sep}참고.mp4');
      await movie.writeAsBytes(const [0, 0, 0, 24]);
      return s.importCutFolder(
        folderPath: '${tempDir.path}$sep$root',
        copyIntoProject: true,
      );
    });
    expect(warnings, isNotNull);

    final assets = {
      for (final asset in s.mediaAssets) asset.kind: asset,
    };
    expect(
      assets[MediaAssetKind.image]?.carried,
      isTrue,
      reason: 'the timesheet scan was asked for and can be carried',
    );
    expect(
      assets[MediaAssetKind.video]?.carried,
      isTrue,
      reason: 'the answer is recorded as given at every registration site',
    );
    expect(
      projectArchivedMediaPaths(s.repository.requireProject()),
      {assets[MediaAssetKind.image]!.path},
      reason: 'the kind ceiling keeps the 참고영상 out — that is where it '
          'is applied, not by rewriting what the user asked for',
    );
    expect(
      Directory('${tempDir.path}/csm_13_069_loeks.assets').existsSync(),
      isFalse,
      reason: 'carrying copies nothing',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('importPdfFile as a NEW CUT: pages become cels 1:1 on an '
      'animation reference layer, the asset registers as pdf with its '
      'page count, pages render at placement resolution; one undo removes '
      'everything', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    addTearDown(PdfRenderService.debugResetForTests);
    final fake = FakePdfDocument(
      // A4 portrait in points; three pages = three frames (§6-k).
      pageSizes: const [ui.Size(595, 842), ui.Size(595, 842), ui.Size(595, 842)],
    );
    PdfRenderService.debugOpenerOverride = (path) async => fake;
    final cutsBefore = s.repository.requireProject().tracks.first.cuts.length;

    final progress = <(int, int)>[];
    final imported = await tester.runAsync(() async {
      final file = File('${tempDir.path}${Platform.pathSeparator}conte.pdf');
      await file.writeAsBytes(const [0x25, 0x50, 0x44, 0x46]);
      return s.importPdfFile(
        path: file.path,
        destination: ImportDestination.newCut,
        onRenderProgress: (done, total) => progress.add((done, total)),
        copyIntoProject: false,
      );
    });
    expect(imported, isTrue);
    expect(fake.disposed, isTrue, reason: 'the document handle releases');
    expect(progress, [(1, 3), (2, 3), (3, 3)]);

    final track = s.repository.requireProject().tracks.first;
    expect(track.cuts.length, cutsBefore + 1);
    final cut = track.cuts.last;
    expect(cut.duration, 3, reason: '1 page = 1 frame');
    final layer = cut.layers.firstWhere(
      (layer) => layer.mediaReference != null,
    );
    expect(layer.kind, LayerKind.animation, reason: '§6-z23: PDF rides the '
        'animation kind; the reference field is the second axis');
    expect(layer.frames, hasLength(3), reason: 'pages never fold');
    for (var frame = 0; frame < 3; frame += 1) {
      expect(
        s.celHasContentForLayer(layer, frame),
        isTrue,
        reason: 'page ${frame + 1} baked into the store',
      );
    }
    final asset = s.mediaAssets.single;
    expect(asset.kind, MediaAssetKind.pdf);
    expect(asset.pageCount, 3);
    expect(asset.frameCount, isNull, reason: 'pageCount is the pdf slot');

    // §6-m pre-conversion: the render request is the CONTAIN placement of
    // an A4 page on the default canvas, not the page's 72dpi point size.
    final canvas = cut.canvasSize;
    final scale = (canvas.width / 595) < (canvas.height / 842)
        ? canvas.width / 595
        : canvas.height / 842;
    expect(fake.renderRequests, hasLength(3));
    expect(fake.renderRequests.first.$2, (595 * scale).round());
    expect(fake.renderRequests.first.$3, (842 * scale).round());

    s.undo();
    final afterUndo = s.repository.requireProject();
    expect(afterUndo.tracks.first.cuts.length, cutsBefore);
    expect(afterUndo.mediaAssets, isEmpty);
    await tester.pumpAndSettle();
  });

  testWidgets('importPdfFile: a ONE-page PDF lands as an image-kind still, '
      'and rasterize mode registers nothing', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    addTearDown(PdfRenderService.debugResetForTests);
    PdfRenderService.debugOpenerOverride = (path) async =>
        FakePdfDocument(pageSizes: const [ui.Size(595, 842)]);

    final imported = await tester.runAsync(() async {
      final file = File('${tempDir.path}${Platform.pathSeparator}page.pdf');
      await file.writeAsBytes(const [0x25, 0x50, 0x44, 0x46]);
      return s.importPdfFile(
        path: file.path,
        destination: ImportDestination.activeCutLayer,
        rasterize: true,
        copyIntoProject: false,
      );
    });
    expect(imported, isTrue);

    final cut = s.requireActiveCut;
    final layer = cut.layers.firstWhere(
      (layer) => layer.kind == LayerKind.image,
    );
    expect(layer.mediaReference, isNull, reason: 'rasterize = no reference');
    expect(s.mediaAssets, isEmpty, reason: 'absorbed pixels register nothing');
    expect(s.celHasContentForLayer(layer, 0), isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('importPdfFile with NO renderer refuses honestly: false, no '
      'cut, no asset, no leftover undo step', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    addTearDown(PdfRenderService.debugResetForTests);
    // No override: under flutter_tester the probe reports absent.
    final cutsBefore = s.repository.requireProject().tracks.first.cuts.length;
    final canUndoBefore = s.canUndo;

    final imported = await tester.runAsync(() async {
      final file = File('${tempDir.path}${Platform.pathSeparator}none.pdf');
      await file.writeAsBytes(const [0x25, 0x50, 0x44, 0x46]);
      return s.importPdfFile(
        path: file.path,
        destination: ImportDestination.newCut,
        copyIntoProject: false,
      );
    });
    expect(imported, isFalse);
    expect(PdfRenderService.availability, isFalse);
    expect(s.repository.requireProject().tracks.first.cuts.length, cutsBefore);
    expect(s.mediaAssets, isEmpty);
    expect(s.canUndo, canUndoBefore);
    await tester.pumpAndSettle();
  });

  testWidgets('importCutFolder with archived-process subfolders opted in '
      'builds the R2 attach-folder structure: FREE attach rows below the '
      'base inside a per-process organizer', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    await tester.runAsync(() async {
      const root = 'csm_13_074_gen';
      final sep = Platform.pathSeparator;
      await writePng('$root${sep}A1.png');
      await writePng('$root${sep}LO${sep}A1.png', seed: 0xFF0000FF);
      await s.importCutFolder(
        folderPath: '${tempDir.path}$sep$root',
        config: const CutFolderParseConfig(includeProcessSubfolders: true),
        copyIntoProject: false,
      );
    });

    final cut = s.repository
        .requireProject()
        .tracks
        .first
        .cuts
        .firstWhere((cut) => cut.name == '074');
    final base = cut.layers.firstWhere(
      (l) => l.name == 'A' && l.attachedToLayerId == null,
    );
    final attach = cut.layers.firstWhere(
      (l) => l.attachedToLayerId == base.id,
    );
    expect(attach.name, 'A LO');
    final organizer = cut.layers.firstWhere((l) => l.id == attach.folderId);
    expect(organizer.kind, LayerKind.folder);
    expect(organizer.name, 'LO');
    expect(s.celHasContentForLayer(attach, 0), isTrue);
    await tester.pumpAndSettle();
  });
}
