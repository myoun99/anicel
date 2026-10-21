import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/import/cut_folder_parse.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import '../../helpers/reference_to.dart';

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
    expect(plan.assets, isEmpty, reason: 'no file was named to register');
  });

  // I-76: a numbered run names its cels by their numbers, as the cut folder
  // does — a folded duplicate keeps the first one's.
  test('planSequenceLayer names each cel by its position\'s name', () {
    final plan = planSequenceLayer(
      sourceFiles: const ['A1.png', 'A2.png', 'A3a.png'],
      frameFingerprints: const ['A', 'A', 'B'],
      displayName: 'A',
      cutId: const CutId('cut-1'),
      mint: mint(),
      frameNames: const ['1', '2', '3a'],
    );

    expect([for (final frame in plan.layer.frames) frame.name], ['1', '3a']);
    expect(
      plan.bakes.map((bake) => bake.sourceFile),
      ['A1.png', 'A3a.png'],
      reason: 'each cel bakes from its own file',
    );
  });

  test('🚨a BAKED placement registers nothing — the pixels are the layer\'s '
      'own (F-282-Q6, 유저 2026-10-09: 구우면 풀에 안 남긴다)', () {
    // Baked = no reference handed in (I-68: the door makes one only for a
    // row that is to SHOW its file).
    final sequence = planSequenceLayer(
      sourceFiles: const ['C:/media/a.gif', 'C:/media/a.gif'],
      frameFingerprints: const ['A', 'B'],
      displayName: 'a.gif',
      cutId: const CutId('cut-1'),
      mint: mint(),
    );
    expect(
      sequence.layer.mediaReference,
      isNull,
      reason: 'baked: nothing points at the file',
    );
    expect(sequence.assets, isEmpty);

    final still = planStillImageLayer(
      sourceFile: 'C:/media/b.png',
      displayName: 'b.png',
      cutId: const CutId('cut-1'),
      duration: 24,
      fit: MediaFitMode.contain,
      reference: null,
      mint: mint(),
    );
    expect(still.layer.mediaReference, isNull);
    expect(still.assets, isEmpty);

    // ↩️「구워도 풀에 남음」 (09-11): both registered their file.
  });

  test('the law: a placement registers when the layer draws from the file, '
      'or when a sound placed beside a baked picture still reads it', () {
    expect(placementRegisters(baked: false), isTrue);
    expect(placementRegisters(baked: true), isFalse);
    expect(placementRegisters(baked: true, soundReadsIt: true), isTrue);
    expect(placementRegisters(baked: false, soundReadsIt: true), isTrue);
  });

  test('a sequence in REFERENCE mode registers one asset with the frame '
      'count and stamps the layer reference', () {
    final reference = referenceTo('C:/media/a.gif');
    final plan = planSequenceLayer(
      sourceFiles: const ['a.gif', 'a.gif'],
      frameFingerprints: const ['A', 'B'],
      displayName: 'a.gif',
      cutId: const CutId('cut-1'),
      mint: mint(),
      reference: reference,
      fit: MediaFitMode.none,
    );
    expect(
      plan.layer.mediaReference,
      same(reference),
      reason: 'the reference the door made — where it stands included',
    );
    expect(plan.assets.single.path, 'C:/media/a.gif');
    expect(plan.assets.single.frameCount, 2);
    expect(plan.assets.single.kind, MediaAssetKind.image);
    expect(
      plan.assets.single.fitMode,
      MediaFitMode.none,
      reason: 'the fit it was placed with, the entry\'s placement default',
    );
  });

  // I-68 「가」 (유저 2026-10-10): a row that shows its file says by cel
  // which picture of the FILE each is, so each can be laid again from it.
  test('🎯a row that shows its file says by cel which picture of the FILE '
      'each is — from the span\'s first, past a folded hold — and a baked '
      'one says nothing', () {
    List<int?> sequence({required bool shows}) => [
      for (final frame in planSequenceLayer(
        sourceFiles: List<String>.filled(5, 'C:/media/a.gif'),
        // A, A, B, C, C — from the file's frame 3 on.
        frameFingerprints: const ['A', 'A', 'B', 'C', 'C'],
        displayName: 'a.gif',
        cutId: const CutId('cut-1'),
        mint: mint(),
        reference: shows ? referenceTo('C:/media/a.gif') : null,
        firstPicture: 3,
      ).layer.frames)
        frame.filePicture,
    ];
    expect(sequence(shows: true), [3, 5, 6]);
    expect(sequence(shows: false), [null, null, null]);

    int? still({required bool shows}) => planStillImageLayer(
      sourceFile: 'C:/media/conte.pdf',
      displayName: 'conte.pdf',
      cutId: const CutId('cut-1'),
      duration: 24,
      fit: MediaFitMode.contain,
      reference: shows ? referenceTo('C:/media/conte.pdf') : null,
      mint: mint(),
      assetKind: MediaAssetKind.pdf,
      pageCount: 20,
      picture: 12,
    ).layer.frames.single.filePicture;
    expect(still(shows: true), 12, reason: 'page 13 of the conte');
    expect(still(shows: false), isNull);
  });

  test('a PDF plan (assetKind: pdf) registers pageCount instead of '
      'frameCount, on both the sequence and the still shapes', () {
    final sequence = planSequenceLayer(
      sourceFiles: List<String>.filled(3, 'C:/media/conte.pdf'),
      frameFingerprints: const [0, 1, 2],
      displayName: 'conte.pdf',
      cutId: const CutId('cut-1'),
      mint: mint(),
      reference: referenceTo('C:/media/conte.pdf'),
      assetKind: MediaAssetKind.pdf,
      pageCount: 3,
    );
    expect(sequence.assets.single.kind, MediaAssetKind.pdf);
    expect(sequence.assets.single.pageCount, 3);
    expect(sequence.assets.single.frameCount, isNull);
    expect(sequence.bakes, hasLength(3), reason: 'indexes never fold');

    final still = planStillImageLayer(
      sourceFile: 'C:/media/page.pdf',
      displayName: 'page.pdf',
      cutId: const CutId('cut-1'),
      duration: 24,
      fit: MediaFitMode.contain,
      reference: referenceTo('C:/media/page.pdf'),
      mint: mint(),
      assetKind: MediaAssetKind.pdf,
      pageCount: 1,
    );
    expect(still.assets.single.kind, MediaAssetKind.pdf);
    expect(still.assets.single.pageCount, 1);
  });

  group('planCutFolderImport', () {
    CutFolderImportPlan planFor(String folderName, List<String> files) =>
        planCutFolderImport(
          parsed: parseCutFolder(
            folderName: folderName,
            entries: [for (final file in files) CutFolderEntry(file)],
          ),
          resolveFile: (relative) => 'C:/folder/$relative',
          canvasSize: const CanvasSize(width: 640, height: 360),
          mint: mint(),
        );

    test('stacks the picture at the bottom, each symbol\'s own layer, and '
        'its correction RIGHT ABOVE it as its attach row (F-429-Q2)', () {
      final plan = planFor('csm_13_074_gen', [
        'A1.png',
        'A2.png',
        'A1s.png',
        'B1.png',
        '_BG.png',
        'LO/A1.png',
      ]);

      expect(plan.cut.duration, 2, reason: 'longest layer = 2 cels');
      final layers = plan.cut.layers;
      expect(layers.take(4).map((l) => l.name), ['BG', 'A', 'A', 'B']);
      final base = layers[1];
      final correction = layers[2];
      expect(base.attachedToLayerId, isNull);
      expect(correction.attachedToLayerId, base.id);
      expect(correction.attachedPlacement, AttachedPlacement.above);
      expect(correction.onTimesheet, isFalse, reason: 'born off the sheet');
      expect(layers[3].attachedToLayerId, isNull);
      expect(base.frames.map((f) => f.name), ['1', '2']);
      expect(
        plan.bakes.map((b) => b.sourceFile),
        unorderedEquals([
          for (final file in ['_BG', 'A1', 'A2', 'A1s', 'B1'])
            'C:/folder/$file.png',
        ]),
        reason: 'the archived LO/A1 is listed, never baked (F-429-Q3)',
      );
    });

    test('every layer comes in wearing its colour label — the stage, and '
        'the correction its letters name; a picture is born an image', () {
      final plan = planFor('csm_13_074_gen', ['A1.png', 'A1s.png', '_BG.png']);
      final [picture, base, correction, ...] = plan.cut.layers;

      expect(picture.kind, LayerKind.image);
      expect(picture.mark, LayerMark.bornOfKind(LayerKind.image));
      expect(base.mark.process, LayerProcess.key);
      expect(base.mark.revise, isNull);
      expect(correction.mark.process, LayerProcess.key);
      expect(correction.mark.revise, LayerRevise.animationDirector);
    });

    test('a correction of cels the base has is SYNCED: one mirror per base '
        'cel, in the base\'s order, the corrected ones baked', () {
      final plan = planFor('csm_13_074_lo', [
        'A1.png',
        'A2.png',
        'A3.png',
        'A2s.png',
      ]);
      final base = plan.cut.layers.firstWhere(
        (l) => l.name == 'A' && l.attachedToLayerId == null,
      );
      final correction = plan.cut.layers.firstWhere(
        (l) => l.attachedToLayerId == base.id,
      );

      expect(correction.attachedMode, AttachedMode.synced);
      expect(correction.timeline, isEmpty, reason: 'it rides the base');
      final mirrors = [
        for (final cel in base.frames)
          attachedMirrorCelId(correction.id, cel.id),
      ];
      expect(correction.frames.map((f) => f.id), mirrors);
      expect(correction.baseFrameLinks, {
        for (final (index, cel) in base.frames.indexed) cel.id: mirrors[index],
      });
      expect(
        cutWithReconciledAttachedMirrors(plan.cut),
        same(plan.cut),
        reason: 'the always-mirror shape is born whole, as .clip\'s is',
      );
      final bake = plan.bakes.singleWhere(
        (b) => b.sourceFile.endsWith('A2s.png'),
      );
      expect(bake.layerId, correction.id);
      expect(bake.frameId, mirrors[1], reason: 'A2s is A2\'s mirror');
    });

    test('a correction that draws a cel the base lacks is FREE, laid one '
        'comma each like every layer of the folder (07-29)', () {
      final plan = planFor('csm_13_074_lo', ['B1.png', 'B1e.png', 'B2e.png']);
      final base = plan.cut.layers.firstWhere(
        (l) => l.name == 'B' && l.attachedToLayerId == null,
      );
      final correction = plan.cut.layers.firstWhere(
        (l) => l.attachedToLayerId == base.id,
      );

      expect(correction.attachedMode, AttachedMode.free);
      expect(correction.mark.revise, LayerRevise.direction);
      expect(correction.onTimesheet, isFalse);
      expect(correction.frames.map((f) => f.name), ['1', '2']);
      expect(correction.timeline.keys, [0, 1]);
      expect(
        [for (final exposure in correction.timeline.values) exposure.frameId],
        correction.frames.map((f) => f.id),
      );
      expect(
        [
          for (final bake in plan.bakes)
            if (bake.layerId == correction.id) bake.frameId,
        ],
        correction.frames.map((f) => f.id),
      );
    });

    test('a correction with no layer of its symbol to ride is a layer of '
        'its own, still wearing its correction', () {
      final plan = planFor('csm_13_074_lo', ['B1s.png', 'B2s.png']);
      final b = plan.cut.layers.singleWhere((l) => l.name == 'B');

      expect(b.attachedToLayerId, isNull);
      expect(b.mark.revise, LayerRevise.animationDirector);
      expect(b.frames.map((f) => f.name), ['1', '2']);
    });

    test('a multi-cut folder is ONE cut, named after its first number '
        '(F-429-Q3)', () {
      final plan = planFor('csm_13_069_077_086_loeks', ['A1.png']);
      expect(plan.cut.name, '069');
    });
  });
}
