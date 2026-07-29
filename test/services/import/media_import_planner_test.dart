import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/import/cut_folder_parse.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';

/// The pure import planner: sequence folding, cut-folder structure, and
/// the invariants the models enforce downstream.
void main() {
  ImportIdMint mint() {
    var layers = 0;
    var frames = 0;
    var cuts = 0;
    return ImportIdMint(
      nextLayerId: () => LayerId('layer-${++layers}'),
      nextFrameId: (layerId) => FrameId('${layerId.value}-cel-${++frames}'),
      nextCutId: () => CutId('cut-${++cuts}'),
    );
  }

  test('planSequenceLayer folds consecutive duplicates into held exposure '
      'and every bake names its SOURCE frame index (not the bake ordinal)',
      () {
    final plan = planSequenceLayer(
      sourceFiles: List<String>.filled(5, 'anim.gif'),
      // A, A, B, C, C — twos with a single in the middle.
      frameFingerprints: const ['A', 'A', 'B', 'C', 'C'],
      displayName: 'anim.gif',
      cutId: const CutId('cut-1'),
      fit: MediaFitMode.contain,
      rasterize: true,
      mint: mint(),
    );

    expect(plan.layer.frames, hasLength(3), reason: '5 frames → 3 cels');
    expect(plan.layer.timeline.keys, [0, 2, 3]);
    expect(plan.layer.timeline[0]!.length, 2);
    expect(plan.layer.timeline[2]!.length, 1);
    expect(plan.layer.timeline[3]!.length, 2);
    expect(
      plan.bakes.map((b) => b.sourceFrameIndex),
      [0, 2, 3],
      reason: 'the bake list is compressed — the index must survive it',
    );
    expect(plan.assets, isEmpty, reason: 'rasterize registers nothing');
  });

  test('a sequence in REFERENCE mode registers one asset with the frame '
      'count and stamps the layer reference', () {
    final plan = planSequenceLayer(
      sourceFiles: const ['a.gif', 'a.gif'],
      frameFingerprints: const ['A', 'B'],
      displayName: 'a.gif',
      cutId: const CutId('cut-1'),
      fit: MediaFitMode.contain,
      rasterize: false,
      mint: mint(),
      referencePath: 'C:/media/a.gif',
    );
    expect(plan.layer.mediaReference!.assetPath, 'C:/media/a.gif');
    expect(plan.assets.single.frameCount, 2);
    expect(plan.assets.single.kind, MediaAssetKind.image);
  });

  test('planCutFolderImport builds a legal stack: pictures at the bottom, '
      'each symbol as [attach, organizer, base], fixtures last — and the '
      'folder structure validates', () {
    final parsed = parseCutFolder(
      folderName: 'csm_13_074_gen',
      entries: [
        const CutFolderEntry('A1.png'),
        const CutFolderEntry('A2.png'),
        const CutFolderEntry('B1.png'),
        const CutFolderEntry('_BG.png'),
        const CutFolderEntry('LO', isDirectory: true),
        const CutFolderEntry('LO/A1.png'),
        const CutFolderEntry('LO/B1.png'),
      ],
      config: const CutFolderParseConfig(includeProcessSubfolders: true),
    );
    final plan = planCutFolderImport(
      parsed: parsed,
      resolveFile: (relative) => 'C:/folder/$relative',
      canvasSize: const CanvasSize(width: 640, height: 360),
      fit: MediaFitMode.contain,
      mint: mint(),
    );

    expect(plan.cut.duration, 2, reason: 'longest layer = 2 cels');
    expect(
      folderStructureProblem(plan.cut.layers),
      isNull,
      reason: 'organizer folders sit directly above their member run',
    );

    final names = plan.cut.layers.map((l) => l.name).toList();
    expect(names.first, 'BG', reason: 'the picture is the bottom row');
    // Each symbol lays [attach, organizer, base].
    final aAttach = names.indexOf('A LO');
    expect(names[aAttach + 1], 'LO');
    expect(names[aAttach + 2], 'A');

    final base = plan.cut.layers.firstWhere((l) => l.name == 'A');
    final attach = plan.cut.layers.firstWhere((l) => l.name == 'A LO');
    expect(attach.attachedToLayerId, base.id);
    expect(base.frames.map((f) => f.name), ['1', '2']);
    expect(plan.bakes, hasLength(6), reason: '3 cels + 1 BG + 2 archived');
  });

  test('an archived-process symbol with no top-level layer WARNS instead '
      'of vanishing (§6-z21: nothing exits silently)', () {
    final parsed = parseCutFolder(
      folderName: 'csm_13_074_gen',
      entries: [
        const CutFolderEntry('A1.png'),
        const CutFolderEntry('LO', isDirectory: true),
        const CutFolderEntry('LO/C1.png'),
      ],
      config: const CutFolderParseConfig(includeProcessSubfolders: true),
    );
    final plan = planCutFolderImport(
      parsed: parsed,
      resolveFile: (relative) => relative,
      canvasSize: const CanvasSize(width: 640, height: 360),
      fit: MediaFitMode.contain,
      mint: mint(),
    );
    expect(
      plan.warnings.any((w) => w.contains('LO/C')),
      isTrue,
      reason: 'the skipped archived cels are named',
    );
  });

  test('a multi-cut folder reports the EXTRA cut numbers for the linked-cut '
      'follow-up, and names the cut after the first', () {
    final parsed = parseCutFolder(
      folderName: 'csm_13_069_077_086_loeks',
      entries: [const CutFolderEntry('A1.png')],
    );
    final plan = planCutFolderImport(
      parsed: parsed,
      resolveFile: (relative) => relative,
      canvasSize: const CanvasSize(width: 640, height: 360),
      fit: MediaFitMode.contain,
      mint: mint(),
    );
    expect(plan.cut.name, '069');
    expect(plan.extraCutNumbers, ['077', '086']);
  });
}
