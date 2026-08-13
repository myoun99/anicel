import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../helpers/psd_fixture.dart';

/// EXPAND, end to end: a real `.psd` on disk becomes a folder of layers
/// whose cels live in the brush-frame store like drawn ones, and ONE undo
/// takes the whole thing back out.
///
/// The real IO and codec work runs inside `tester.runAsync` — the fake-async
/// zone never completes a file future.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-psd-expand');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } on Object {
      // Windows keeps handles briefly; leftovers live in systemTemp.
    }
  });

  /// A two-layer document with a group around the upper one.
  Future<String> writePsd({String name = 'BG_a12.psd'}) async {
    final bytes = buildPsd(
      width: 8,
      height: 8,
      layers: [
        PsdTestLayer(
          name: 'under',
          left: 0,
          top: 0,
          right: 8,
          bottom: 8,
          planes: psdSolidPlanes(8, 8, [10, 20, 30]),
        ),
        PsdTestLayer(
          name: '</Layer group>',
          left: 0,
          top: 0,
          right: 0,
          bottom: 0,
          sectionType: 3,
          planes: const [],
        ),
        PsdTestLayer(
          name: 'inside',
          left: 2,
          top: 2,
          right: 6,
          bottom: 6,
          opacity: 128,
          planes: psdSolidPlanes(4, 4, [200, 100, 50]),
        ),
        PsdTestLayer(
          name: 'BOOK',
          left: 0,
          top: 0,
          right: 0,
          bottom: 0,
          sectionType: 1,
          planes: const [],
        ),
      ],
      compositePlanes: [
        Uint8List(64),
        Uint8List(64),
        Uint8List(64),
      ],
    );
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  testWidgets('a PSD expands into ONE folder of layers, cels baked, one undo '
      'takes it all back', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final cut = s.activeCutOrNull!;
    final layersBefore = cut.layers.length;

    final warnings = await tester.runAsync(() async {
      final path = await writePsd();
      return s.importPsdExpanded(
        path: path,
        destination: ImportDestination.activeCutLayer,
      );
    });

    expect(warnings, isNotNull);
    final after = s.activeCutOrNull!;
    final added = after.layers.where(
      (layer) => !cut.layers.any((before) => before.id == layer.id),
    );
    expect(added, hasLength(layersBefore == after.layers.length ? 0 : 4));

    final root = added.firstWhere((layer) => layer.name == 'BG_a12.psd');
    expect(root.kind, LayerKind.folder);
    final book = added.firstWhere((layer) => layer.name == 'BOOK');
    expect(book.folderId, root.id);
    final inside = added.firstWhere((layer) => layer.name == 'inside');
    expect(inside.folderId, book.id);
    expect(inside.opacity, closeTo(128 / 255, 0.01));
    final under = added.firstWhere((layer) => layer.name == 'under');
    expect(under.folderId, root.id);
    expect(under.kind, LayerKind.image);

    // The pixels are in the store, which is what makes an imported cel
    // indistinguishable from a drawn one everywhere downstream.
    expect(
      s.brushFrameStore.bakedSurfaceOrNull(
        s.brushFrameKeyForCut(after, under.id, under.frames.single.id),
      ),
      isNotNull,
    );

    s.undo();
    final undone = s.activeCutOrNull!;
    expect(undone.layers.length, layersBefore);
    expect(
      undone.layers.any((layer) => layer.name == 'BG_a12.psd'),
      isFalse,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('a flattened document has no stack to expand and says so',
      (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    final warnings = await tester.runAsync(() async {
      final bytes = buildPsd(
        width: 4,
        height: 4,
        compositePlanes: [
          Uint8List(16),
          Uint8List(16),
          Uint8List(16),
        ],
      );
      final file = File('${tempDir.path}${Platform.pathSeparator}flat.psd');
      await file.writeAsBytes(bytes);
      return s.importPsdExpanded(
        path: file.path,
        destination: ImportDestination.activeCutLayer,
      );
    });

    expect(warnings, isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('expanding into a NEW CUT lands a cut holding the stack',
      (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final cutsBefore = s.repository.requireProject().tracks.first.cuts.length;

    await tester.runAsync(() async {
      final path = await writePsd();
      return s.importPsdExpanded(
        path: path,
        destination: ImportDestination.newCut,
      );
    });

    final cuts = s.repository.requireProject().tracks.first.cuts;
    expect(cuts.length, cutsBefore + 1);
    final cut = cuts.firstWhere((c) => c.name == 'BG_a12.psd');
    expect(
      cut.layers.where((layer) => layer.kind == LayerKind.folder).length,
      2,
      reason: 'the document folder and the group inside it',
    );
    await tester.pumpAndSettle();
  });
}
