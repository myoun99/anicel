import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/import/import_layer_spot.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/fake_pdf_document.dart';
import '../../helpers/solid_png_fixture.dart';

/// 🚨THE DROP PLACE DECIDES (유저 2026-09-11, 미디어 배치 라운드: 「떨어뜨린
/// 자리가 곧 답」). A file let go on a picture row's frame area becomes new
/// frames there, baked — 「그림 행의 프레임 영역 → 그 칸부터 새 프레임, 항상
/// 굽기」 — and what is in the way moves the way it moves for a block dragged
/// in from another row (「새로 만든 규칙이 아니라 … 지금 쓰는 계산
/// 그대로다」). Let go on the canvas, it becomes a new layer directly above
/// the active one. Image and reference rows take nothing on their frames.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-drop-spot');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } on Object {
      // Windows keeps handles briefly.
    }
  });

  Future<String> writePng(String name) =>
      writeSolidPng(tempDir, name, rgba: 0xAAAAAAAA);

  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  Layer drawingRow(EditorSessionManager s) => s.requireActiveCut.layers
      .firstWhere((layer) => layer.kind == LayerKind.animation);

  /// A row's authored blocks as (start, length, cel) — ghosts are derived.
  List<(int, int?, FrameId?)> blocksOf(Layer layer) => [
    for (final entry in layer.timeline.entries)
      if (!entry.value.ghost)
        (entry.key, entry.value.length, entry.value.frameId),
  ];

  /// [row] holding exactly one drawn block, [start, start + length).
  Layer seedBlock(EditorSessionManager s, Layer row, int start, int length) {
    final seeded = row.copyWith(
      frames: [Frame(id: const FrameId('held'), duration: 1, strokes: const [])],
      timeline: {start: TimelineExposure.drawing(const FrameId('held'), length: length)},
    );
    s.repository.replaceLayer(layer: seeded);
    return seeded;
  }

  testWidgets('a still dropped on a row\'s frame lands as ONE cell there, '
      'baked into that row, and registered — and one undo takes it all '
      'back', (tester) async {
    final s = session();
    final row = seedBlock(s, drawingRow(s), 0, 1);
    final layerCount = s.requireActiveCut.layers.length;

    final landed = await tester.runAsync(() async {
      final path = await writePng('a.png');
      return s.importDoors.importImageFile(
        path: path,
        destination: ImportDestination.activeCutLayer,
        copyIntoProject: false,
        spot: RowFramesSpot(layerId: row.id, frameIndex: 3),
      );
    });

    expect(landed, isTrue);
    final after = s.layerById(row.id)!;
    expect(after.timeline[3]?.length, 1, reason: '「한 장이면 한 칸」');
    expect(after.frames, hasLength(2));
    expect(
      s.layerStack.celHasContentForLayer(after, 3),
      isTrue,
      reason: 'the pixels are keyed under the ROW, not the planned layer',
    );
    expect(
      s.requireActiveCut.layers,
      hasLength(layerCount),
      reason: 'frames on a row are not a new layer',
    );
    expect(
      s.mediaPool.mediaAssets,
      hasLength(1),
      reason: '「구워도 풀에 남음」 — the material of a placement is a pool entry',
    );

    s.undo();
    expect(blocksOf(s.layerById(row.id)!), blocksOf(row));
    expect(s.mediaPool.mediaAssets, isEmpty);
    // A landing wakes the playback pre-render; let it finish its turn.
    await tester.pumpAndSettle();
  });

  testWidgets('what is in the way moves exactly as it moves for a block '
      'dragged in from another row — pages land from the dropped cell, the '
      'block they met goes after them', (tester) async {
    addTearDown(PdfRenderService.debugResetForTests);
    PdfRenderService.debugOpenerOverride = (path) async => FakePdfDocument(
      pageSizes: const [ui.Size(8, 8), ui.Size(8, 8), ui.Size(8, 8)],
    );
    final s = session();
    final row = seedBlock(s, drawingRow(s), 5, 3);

    final landed = await tester.runAsync(() async {
      final path = '${tempDir.path}${Platform.pathSeparator}conte.pdf';
      await File(path).writeAsBytes(const [0x25, 0x50, 0x44, 0x46]);
      return s.importDoors.importPdfFile(
        path: path,
        destination: ImportDestination.activeCutLayer,
        copyIntoProject: false,
        spot: RowFramesSpot(layerId: row.id, frameIndex: 4),
      );
    });

    expect(landed, isTrue);
    final after = s.layerById(row.id)!;
    final blocks = blocksOf(after);
    expect(
      [for (final block in blocks) (block.$1, block.$2)],
      [(4, 1), (5, 1), (6, 1), (7, 3)],
      reason: 'three pages from cell 4; the held block pushed to 7, whole',
    );
    expect(blocks.last.$3, const FrameId('held'));
    for (final frame in [4, 5, 6]) {
      expect(s.layerStack.celHasContentForLayer(after, frame), isTrue);
    }

    s.undo();
    expect(blocksOf(s.layerById(row.id)!), blocksOf(row));
    await tester.pumpAndSettle();
  });

  testWidgets('a single page is one cell on a row too — never a hold over '
      'the cut', (tester) async {
    addTearDown(PdfRenderService.debugResetForTests);
    PdfRenderService.debugOpenerOverride = (path) async =>
        FakePdfDocument(pageSizes: const [ui.Size(8, 8)]);
    final s = session();
    final row = seedBlock(s, drawingRow(s), 0, 1);

    final landed = await tester.runAsync(() async {
      final path = '${tempDir.path}${Platform.pathSeparator}page.pdf';
      await File(path).writeAsBytes(const [0x25, 0x50, 0x44, 0x46]);
      return s.importDoors.importPdfFile(
        path: path,
        destination: ImportDestination.activeCutLayer,
        copyIntoProject: false,
        spot: RowFramesSpot(layerId: row.id, frameIndex: 2),
      );
    });

    expect(landed, isTrue);
    final after = s.layerById(row.id)!;
    expect(after.timeline[2]?.length, 1);
    expect(s.layerStack.celHasContentForLayer(after, 2), isTrue);
    await tester.pumpAndSettle();
  });

  /// A three-frame GIF, one pixel a frame, black · white · black — no two
  /// neighbours alike, because the import folds a repeated frame into a
  /// hold and three equal frames would land as ONE cel.
  Future<String> writeGif(String name) async {
    // [lzw] is the pixel's LZW code: 0x44 for palette 0, 0x4C for 1.
    List<int> frame(int lzw) => [
      0x21, 0xF9, 0x04, 0x00, 0x0A, 0x00, 0x00, 0x00, // graphic control
      0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, // image
      0x02, 0x02, lzw, 0x01, 0x00, // its one pixel
    ];
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes([
      ...'GIF89a'.codeUnits,
      0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00, // 1×1, two colours
      0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF,
      ...frame(0x44), ...frame(0x4C), ...frame(0x44),
      0x3B,
    ]);
    return file.path;
  }

  testWidgets('a GIF\'s IN/OUT lands only the frames it keeps — a cell '
      'each, from the drop cell', (tester) async {
    final s = session();
    final row = seedBlock(s, drawingRow(s), 0, 1);

    final landed = await tester.runAsync(() async {
      final path = await writeGif('walk.gif');
      return s.importDoors.importImageFile(
        path: path,
        destination: ImportDestination.activeCutLayer,
        copyIntoProject: false,
        inFrame: 1,
        outFrame: 2,
        spot: RowFramesSpot(layerId: row.id, frameIndex: 3),
      );
    });

    expect(landed, isTrue);
    final after = s.layerById(row.id)!;
    expect(after.timeline[3]?.length, 1);
    expect(after.timeline[4]?.length, 1);
    expect(after.timeline[5], isNull, reason: 'its first frame is outside');
    expect(after.frames, hasLength(3), reason: 'the held cel and the two');
    await tester.pumpAndSettle();
  });

  testWidgets('a PDF\'s IN/OUT lands only the pages it keeps — and renders '
      'only those', (tester) async {
    final pdf = FakePdfDocument(pageSizes: List.filled(4, const ui.Size(8, 8)));
    addTearDown(PdfRenderService.debugResetForTests);
    PdfRenderService.debugOpenerOverride = (path) async => pdf;
    final s = session();
    final row = seedBlock(s, drawingRow(s), 0, 1);

    final landed = await tester.runAsync(() async {
      final path = '${tempDir.path}${Platform.pathSeparator}conte.pdf';
      await File(path).writeAsBytes(const [0x25, 0x50, 0x44, 0x46]);
      return s.importDoors.importPdfFile(
        path: path,
        destination: ImportDestination.activeCutLayer,
        copyIntoProject: false,
        inFrame: 1,
        outFrame: 2,
        spot: RowFramesSpot(layerId: row.id, frameIndex: 2),
      );
    });

    expect(landed, isTrue);
    final after = s.layerById(row.id)!;
    expect(after.timeline[2]?.length, 1);
    expect(after.timeline[3]?.length, 1);
    expect(after.timeline[4], isNull);
    expect(
      pdf.renderRequests.map((request) => request.$1).toSet(),
      {1, 2},
      reason: 'the second and third pages — the span, from its first page',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('an image row and a reference row take nothing on their '
      'frames — and a drop aimed at one lands nothing and registers '
      'nothing', (tester) async {
    final s = session();
    final cut = s.requireActiveCut;
    final drawing = drawingRow(s);
    final image = Layer(
      id: const LayerId('drop-image-row'),
      name: 'BG',
      frames: const [],
      timeline: const {},
      kind: LayerKind.image,
    );
    s.repository.insertLayer(cutId: cut.id, layer: image);
    final reference = drawing.copyWith(
      mediaReference: const MediaReference(assetPath: 'take.png'),
    );

    expect(s.acceptsPlacedFrames(drawing.id), isTrue);
    expect(s.acceptsPlacedFrames(image.id), isFalse);
    expect(s.frameDropSpot(image.id, 0, 'a.png'), isNull);
    s.repository.replaceLayer(layer: reference);
    expect(s.acceptsPlacedFrames(reference.id), isFalse);
    expect(s.frameDropSpot(reference.id, 0, 'a.png'), isNull);

    final landed = await tester.runAsync(() async {
      final path = await writePng('a.png');
      return s.importDoors.importImageFile(
        path: path,
        destination: ImportDestination.activeCutLayer,
        copyIntoProject: false,
        spot: RowFramesSpot(layerId: image.id, frameIndex: 0),
      );
    });
    expect(landed, isFalse);
    expect(s.mediaPool.mediaAssets, isEmpty);
  });

  testWidgets('a row\'s frames take a file with pixels to bake — a sound '
      'lands nowhere there (「그림 행 → 받지 않는다」)', (tester) async {
    final s = session();
    final row = drawingRow(s);

    expect(
      s.frameDropSpot(row.id, 4, 'a.png'),
      RowFramesSpot(layerId: row.id, frameIndex: 4),
    );
    expect(s.frameDropSpot(row.id, 4, 'conte.pdf'), isNotNull);
    expect(s.frameDropSpot(row.id, 4, 'door.wav'), isNull);
    expect(
      s.frameDropSpot(row.id, 4, 'take.mov'),
      RowFramesSpot(layerId: row.id, frameIndex: 4),
      reason:
          'a movie has pictures: its span bakes into the row\'s cels '
          '(「그림 행의 프레임 영역 → 그림만, 구간을 셀로 굽는다」)',
    );
  });

  testWidgets('a canvas drop\'s new layer sits directly above the ACTIVE '
      'layer — Add Layer\'s own slot — not on top of the stack', (
    tester,
  ) async {
    final s = session();
    final cut = s.requireActiveCut;
    final row = drawingRow(s);
    final top = Layer(
      id: const LayerId('drop-top-row'),
      name: 'TOP',
      frames: const [],
      timeline: const {},
    );
    s.repository.insertLayer(cutId: cut.id, layer: top);
    s.standOnRow(LayerRowAddress(row.id), frameIndex: 0);
    final before = {for (final layer in s.requireActiveCut.layers) layer.id};

    final landed = await tester.runAsync(() async {
      final path = await writePng('b.png');
      return s.importDoors.importImageFile(
        path: path,
        destination: ImportDestination.activeCutLayer,
        copyIntoProject: false,
        spot: const AboveActiveLayerSpot(),
      );
    });

    expect(landed, isTrue);
    final layers = s.requireActiveCut.layers;
    final added = layers.indexWhere((layer) => !before.contains(layer.id));
    expect(added, layers.indexWhere((layer) => layer.id == row.id) + 1);
    expect(layers.last.id, top.id, reason: 'the top stays the top');
    await tester.pumpAndSettle();
  });

  group('the window shows what the drop answered, locked', () {
    Finder cell(String id, String path) =>
        find.byKey(ValueKey<String>('import-cell-$id-$path'));

    String word(WidgetTester tester, String id, String path) {
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

    bool anOptionIsOpen() => find
        .byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'import-option-',
              ),
        )
        .evaluate()
        .isNotEmpty;

    Future<void> open(
      WidgetTester tester,
      EditorSessionManager s,
      String path,
      ImportLayerSpot spot,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportDialog(
              session: s,
              initialPaths: [path],
              placeOnly: true,
              spot: spot,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> press(WidgetTester tester, String id, String path) async {
      await tester.ensureVisible(cell(id, path));
      await tester.pumpAndSettle();
      await tester.tap(cell(id, path), warnIfMissed: false);
      await tester.pumpAndSettle();
    }

    testWidgets('a row\'s frames: the row and the cell, and the bake on — '
        'neither opens', (tester) async {
      final png = await tester.runAsync(() => writePng('a.png'));
      final s = session();
      final row = drawingRow(s);
      await open(tester, s, png!, RowFramesSpot(layerId: row.id, frameIndex: 8));

      expect(word(tester, 'into', png), AppText.strings.imIntoRowCell(row.name, 9));
      await press(tester, 'into', png);
      expect(anOptionIsOpen(), isFalse, reason: 'the drop answered it');

      expect(word(tester, 'bake', png), AppText.strings.commonOn);
      await press(tester, 'bake', png);
      expect(
        word(tester, 'bake', png),
        AppText.strings.commonOn,
        reason: 'a row\'s cells are its pixels — 「셀에 떨어뜨리면 항상 굽기」',
      );
    });

    testWidgets('pressing Import lands the file where the drop said — on the '
        'row\'s frames, not as a new layer', (tester) async {
      final png = await tester.runAsync(() => writePng('a.png'));
      final s = session();
      final row = seedBlock(s, drawingRow(s), 0, 1);
      final layerCount = s.requireActiveCut.layers.length;
      await open(tester, s, png!, RowFramesSpot(layerId: row.id, frameIndex: 6));

      await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
      for (var tries = 0; tries < 40; tries += 1) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (s.layerById(row.id)!.timeline[6] != null) {
          break;
        }
      }

      expect(s.layerById(row.id)!.timeline[6]?.length, 1);
      expect(s.requireActiveCut.layers, hasLength(layerCount));
      await tester.pumpAndSettle();
    });

    testWidgets('🚨the canvas: a new layer by default, and a new cut on '
        'offer — 「새 레이어/새 컷 고를수있게」 (유저 2026-09-12)', (
      tester,
    ) async {
      final png = await tester.runAsync(() => writePng('a.png'));
      final s = session();
      await open(tester, s, png!, const AboveActiveLayerSpot());

      expect(word(tester, 'into', png), AppText.strings.imIntoNewLayer);
      await press(tester, 'into', png);
      expect(
        anOptionIsOpen(),
        isTrue,
        reason: 'the canvas spot was a default, not an answer about the cut',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('import-option-into-newCut')),
      );
      await tester.pumpAndSettle();
      expect(word(tester, 'into', png), AppText.strings.imIntoNewCut);
    });

    testWidgets('the canvas with no cut in hand: a new cut, its one answer '
        '— 「액티브 컷이 없는 상태에서 캔버스 떨구면 새 컷 고정」', (tester) async {
      final png = await tester.runAsync(() => writePng('a.png'));
      // No cut in hand the way the app gets there — the playhead parked in
      // the gap between two cuts (a session cannot start with no cut at all:
      // `defaultActiveCutIdFor` refuses one).
      final base = createDefaultProject();
      final track = base.tracks.first;
      final first = track.cuts.first;
      final s = EditorSessionManager(
        initialProject: base.copyWith(
          tracks: [
            track.copyWith(
              cuts: [
                first,
                createDefaultCut(
                  cutId: const CutId('after-the-gap'),
                  name: '2',
                  layerId: const LayerId('after-the-gap-layer'),
                ).copyWith(leadingGapFrames: 4),
              ],
            ),
          ],
        ),
      );
      addTearDown(s.dispose);
      s.selectGlobalFrame(first.duration + 2);
      expect(
        s.activeCutOrNull,
        isNull,
        reason: 'fixture premise: parked in the gap between the two cuts',
      );
      await open(tester, s, png!, const AboveActiveLayerSpot());

      expect(word(tester, 'into', png), AppText.strings.imIntoNewCut);
      await press(tester, 'into', png);
      expect(anOptionIsOpen(), isFalse, reason: 'one answer is shown locked');
    });

    testWidgets('the layer area: a new layer too, locked — the rail\'s '
        'caret already showed where', (tester) async {
      final png = await tester.runAsync(() => writePng('a.png'));
      final s = session();
      await open(tester, s, png!, const LayerSlotSpot(1));

      expect(word(tester, 'into', png), AppText.strings.imIntoNewLayer);
      await press(tester, 'into', png);
      expect(anOptionIsOpen(), isFalse);
    });

    testWidgets('the storyboard\'s frames: a new cut, locked — the frame it '
        'was let go on already said where', (tester) async {
      final png = await tester.runAsync(() => writePng('a.png'));
      final s = session();
      await open(
        tester,
        s,
        png!,
        const NewCutSpot(index: 1, leadingGapFrames: 0),
      );

      expect(word(tester, 'into', png), AppText.strings.imIntoNewCut);
      await press(tester, 'into', png);
      expect(anOptionIsOpen(), isFalse);
    });
  });

  group('🚨a new row joins the stack by ONE answer (`newRowPlacement`) — the '
      'rail\'s gap and the canvas alike', () {
    const folderId = LayerId('drop-folder');

    /// [s]'s drawing row made the one member of a folder, the folder row
    /// directly above it (the folder invariant).
    Layer foldAround(EditorSessionManager s) {
      final member = drawingRow(s).copyWith(folderId: folderId);
      s.repository.replaceLayer(layer: member);
      final at = s.requireActiveCut.layers.indexWhere(
        (layer) => layer.id == member.id,
      );
      s.repository.insertLayer(
        cutId: s.requireActiveCut.id,
        layer: Layer(
          id: folderId,
          name: 'F',
          frames: const [],
          timeline: const {},
          kind: LayerKind.folder,
        ),
        index: at + 1,
      );
      expect(
        folderStructureProblem(s.requireActiveCut.layers),
        isNull,
        reason: 'the premise: a well-formed folder',
      );
      return member;
    }

    /// Imports one still with [spot] and returns the rows it added.
    Future<List<Layer>> land(
      WidgetTester tester,
      EditorSessionManager s,
      ImportLayerSpot spot,
    ) async {
      final before = {for (final layer in s.requireActiveCut.layers) layer.id};
      final landed = await tester.runAsync(() async {
        final path = await writePng('a.png');
        return s.importDoors.importImageFile(
          path: path,
          destination: ImportDestination.activeCutLayer,
          copyIntoProject: false,
          spot: spot,
        );
      });
      expect(landed, isTrue);
      return [
        for (final layer in s.requireActiveCut.layers)
          if (!before.contains(layer.id)) layer,
      ];
    }

    testWidgets('a picture let go between two rail rows lands at that gap, '
        'inside the folder of the row below it', (tester) async {
      final s = session();
      final member = foldAround(s);
      final gap =
          s.requireActiveCut.layers.indexWhere(
            (layer) => layer.id == member.id,
          ) +
          1;

      final added = (await land(tester, s, LayerSlotSpot(gap))).single;

      final layers = s.requireActiveCut.layers;
      expect(layers.indexOf(added), gap);
      expect(added.folderId, folderId);
      expect(folderStructureProblem(layers), isNull);
      await tester.pumpAndSettle();
    });

    testWidgets('🚨the canvas drop with a folder member active joins that '
        'folder — it used to land inside the run without belonging to it', (
      tester,
    ) async {
      final s = session();
      final member = foldAround(s);
      s.selectLayer(member.id);

      final added = (await land(tester, s, const AboveActiveLayerSpot()))
          .single;

      expect(added.folderId, folderId);
      expect(folderStructureProblem(s.requireActiveCut.layers), isNull);
      await tester.pumpAndSettle();
    });

    testWidgets('🚨the canvas drop on an attach base lands past its rider — '
        'the group is indivisible, as Add Layer keeps it', (tester) async {
      final s = session();
      final base = drawingRow(s);
      final at = s.requireActiveCut.layers.indexWhere(
        (layer) => layer.id == base.id,
      );
      final rider = Layer(
        id: const LayerId('drop-rider'),
        name: 'R',
        frames: const [],
        timeline: const {},
        attachedToLayerId: base.id,
      );
      s.repository.insertLayer(
        cutId: s.requireActiveCut.id,
        layer: rider,
        index: at + 1,
      );
      s.selectLayer(base.id);

      final added = (await land(tester, s, const AboveActiveLayerSpot()))
          .single;

      final layers = s.requireActiveCut.layers;
      expect(
        layers.indexOf(added),
        layers.indexWhere((layer) => layer.id == rider.id) + 1,
        reason: 'above the rider, never between it and its base',
      );
      await tester.pumpAndSettle();
    });
  });
}
