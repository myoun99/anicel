import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/import/cut_folder_edits.dart';
import 'package:anicel/src/models/import/cut_folder_parse.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart'
    show createDefaultCut;
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
    /// The cut the project has open: 24 frames long.
    final open = createDefaultCut(
      cutId: const CutId('open'),
      name: 'open',
      layerId: const LayerId('open-drawing'),
      canvasSize: const CanvasSize(width: 640, height: 360),
    ).copyWith(duration: 24);

    CutFolderImportPlan planFor(
      String folderName,
      List<String> files, {
      CutFolderEdits edits = const CutFolderEdits(),
      bool cutOpen = true,
    }) => planCutFolderImport(
      parsed: parseCutFolder(
        folderName: folderName,
        entries: [for (final file in files) CutFolderEntry(file)],
      ),
      edits: edits,
      resolveFile: (relative) => 'C:/folder/$relative',
      openCut: cutOpen ? open : null,
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

      expect(plan.cuts.single.duration, 2, reason: 'longest layer = 2 cels');
      final layers = plan.cuts.single.layers;
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
      final [picture, base, correction, ...] = plan.cuts.single.layers;

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
      final base = plan.cuts.single.layers.firstWhere(
        (l) => l.name == 'A' && l.attachedToLayerId == null,
      );
      final correction = plan.cuts.single.layers.firstWhere(
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
        cutWithReconciledAttachedMirrors(plan.cuts.single),
        same(plan.cuts.single),
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
      final base = plan.cuts.single.layers.firstWhere(
        (l) => l.name == 'B' && l.attachedToLayerId == null,
      );
      final correction = plan.cuts.single.layers.firstWhere(
        (l) => l.attachedToLayerId == base.id,
      );

      expect(correction.attachedMode, AttachedMode.free);
      expect(correction.attachedPlacement, AttachedPlacement.above);
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

    test('two corrections of one symbol both ride the symbol\'s own layer '
        '— neither rides the other', () {
      final plan = planFor('csm_13_074_lo', ['A1.png', 'A1e.png', 'A1s.png']);
      final [base, direction, animationDirector, ...] = plan.cuts.single.layers;

      expect(base.attachedToLayerId, isNull);
      expect(
        [direction.attachedToLayerId, animationDirector.attachedToLayerId],
        [base.id, base.id],
      );
      expect(
        [direction.mark.revise, animationDirector.mark.revise],
        [LayerRevise.direction, LayerRevise.animationDirector],
      );
    });

    test('a correction with no layer of its symbol to ride is a layer of '
        'its own, still wearing its correction', () {
      final plan = planFor('csm_13_074_lo', ['B1s.png', 'B2s.png']);
      final b = plan.cuts.single.layers.singleWhere((l) => l.name == 'B');

      expect(b.attachedToLayerId, isNull);
      expect(b.mark.revise, LayerRevise.animationDirector);
      expect(b.frames.map((f) => f.name), ['1', '2']);
    });

    test('a multi-cut folder is ONE cut, named after its first number '
        '(F-429-Q3)', () {
      final plan = planFor('csm_13_069_077_086_loeks', ['A1.png']);
      expect(plan.cuts.single.name, '069');
    });

    group('as the import window answered it (F-429)', () {
      test('the cut takes the name typed for it', () {
        final plan = planFor('csm_13_069_loeks', [
          'A1.png',
        ], edits: const CutFolderEdits(cutName: '070'));
        expect(plan.cuts.single.name, '070');
      });

      test('a row wears the colour label picked for it, and its correction '
          'keeps its own', () {
        const layout = LayerMark(process: LayerProcess.layout);
        final plan = planFor('csm_13_074_gen', [
          'A1.png',
          'A1s.png',
        ], edits: const CutFolderEdits(marks: {'A': layout}));
        final [base, correction, ...] = plan.cuts.single.layers;

        expect(base.mark, layout);
        expect(correction.mark.revise, LayerRevise.animationDirector);
      });

      test('a layer of ONE cel picked an image is held over the cut; a layer '
          'of more stays an animation whatever is picked', () {
        final plan = planFor('csm_13_074_gen', [
          'A1.png',
          'B1.png',
          'B2.png',
        ], edits: const CutFolderEdits(
          kinds: {'A': LayerKind.image, 'B': LayerKind.image},
        ));
        final a = plan.cuts.single.layers.singleWhere((l) => l.name == 'A');
        final b = plan.cuts.single.layers.singleWhere((l) => l.name == 'B');

        expect(a.kind, LayerKind.image);
        expect(a.frames.single.name, isNull, reason: 'an image cel goes '
            'nameless');
        expect(a.timeline.keys, [0]);
        expect(a.timeline[0]!.length, 2, reason: 'held over the cut');
        expect(b.kind, LayerKind.animation);
        expect(b.timeline.keys, [0, 1]);
      });

      test('a correction is its symbol\'s kind, whatever is picked for it', () {
        final plan = planFor('csm_13_074_gen', [
          'A1.png',
          'A1s.png',
        ], edits: const CutFolderEdits(
          kinds: {
            'A': LayerKind.image,
            'A animation-director': LayerKind.animation,
          },
        ));
        final [base, correction, ...] = plan.cuts.single.layers;

        expect(base.kind, LayerKind.image);
        expect(correction.kind, LayerKind.image);
      });

      test('a picture picked an animation layer is one cel at one comma, '
          'born with that kind\'s label', () {
        final plan = planFor('csm_13_074_gen', [
          'A1.png',
          'A2.png',
          '_BG.png',
        ], edits: const CutFolderEdits(kinds: {'_BG': LayerKind.animation}));
        final bg = plan.cuts.single.layers.first;

        expect(bg.name, 'BG');
        expect(bg.kind, LayerKind.animation);
        expect(bg.mark, LayerMark.bornOfKind(LayerKind.animation));
        expect(bg.timeline.keys, [0]);
        expect(bg.timeline[0]!.length, 1);
      });

      test('each row lays its cels with the fit picked for it — contain until '
          'one is', () {
        final plan = planFor('csm_13_074_gen', [
          'A1.png',
          '_BG.png',
        ], edits: const CutFolderEdits(fits: {'A': MediaFitMode.none}));
        final [bg, a, ...] = plan.cuts.single.layers;

        expect(plan.fits, {a.id: MediaFitMode.none, bg.id: MediaFitMode.contain});
      });
    });

    test('a folder with no cel or picture lands nothing, and says so', () {
      final plan = planFor('csm_13_069_lo', ['_069_ts_lo.png']);

      expect(plan.cuts, isEmpty);
      expect(plan.openCutLayers, isEmpty);
      expect(
        plan.warnings.map((warning) => warning.key),
        contains('folderNothing'),
      );
    });

    group('「커스텀」 — each row where its own 넣을 곳 says (F-429-Q1)', () {
      String fileOf(PlannedCelBake bake) => bake.sourceFile.split('/').last;

      test('a row sent to a cut of its own is one — named as the row, as long '
          'as its layer, its correction riding along — and the rest join the '
          'open cut, a picture held over its length', () {
        final plan = planFor(
          'csm_13_069_lo',
          ['A1.png', 'A2.png', 'A1s.png', 'B1.png', '_BG.png'],
          edits: const CutFolderEdits(
            custom: true,
            into: {'A': ImportDestination.newCut},
          ),
        );

        final own = plan.cuts.single;
        expect(own.name, 'A');
        expect(own.duration, 2);
        expect(own.canvasSize, open.canvasSize, reason: 'the project\'s size');
        final [base, correction, ...] = own.layers;
        expect(base.name, 'A');
        expect(correction.attachedToLayerId, base.id);
        expect(correction.attachedMode, AttachedMode.synced);

        expect(plan.openCutLayers.map((l) => l.name), ['BG', 'B']);
        final bg = plan.openCutLayers.first;
        expect(bg.timeline[0]!.length, 24, reason: 'the open cut\'s length');
        expect({for (final bake in plan.bakes) fileOf(bake): bake.cutId}, {
          '_BG.png': open.id,
          'A1.png': own.id,
          'A2.png': own.id,
          'A1s.png': own.id,
          'B1.png': open.id,
        });
      });

      test('a correction sent somewhere of its own is a layer of its own — '
          'riding nothing, its kind its own to pick', () {
        final plan = planFor(
          'csm_13_069_lo',
          ['A1.png', 'A2.png', 'A1s.png'],
          edits: const CutFolderEdits(
            custom: true,
            into: {'A animation-director': ImportDestination.activeCutLayer},
            kinds: {'A animation-director': LayerKind.image},
          ),
        );
        final [base, correction] = plan.openCutLayers;

        expect(base.kind, LayerKind.animation);
        expect(correction.name, 'A');
        expect(correction.attachedToLayerId, isNull);
        expect(correction.kind, LayerKind.image, reason: 'one cel, an image');
        expect(correction.mark.revise, LayerRevise.animationDirector);
        expect(plan.cuts, isEmpty, reason: 'nothing asked for a cut');
      });

      test('with no cut open every row is a cut of its own, met from the '
          'bottom of the stack up', () {
        final plan = planFor(
          'csm_13_069_lo',
          ['A1.png', 'A2.png', 'B1.png', '_BG.png'],
          edits: const CutFolderEdits(custom: true),
          cutOpen: false,
        );

        expect(plan.cuts.map((cut) => cut.name), ['BG', 'A', 'B']);
        expect(plan.cuts.map((cut) => cut.duration), [1, 2, 1]);
        expect(plan.openCutLayers, isEmpty);
      });

      test('「컷」 leaves what 「커스텀」 picked aside — every row is a layer of '
          'the one cut, a correction riding its symbol', () {
        final plan = planFor(
          'csm_13_069_lo',
          ['A1.png', 'A1s.png', 'B1.png'],
          edits: const CutFolderEdits(
            into: {
              'A': ImportDestination.newCut,
              'A animation-director': ImportDestination.activeCutLayer,
            },
          ),
        );

        final [a, correction, b, ...] = plan.cuts.single.layers;
        expect([a.name, b.name], ['A', 'B']);
        expect(correction.attachedToLayerId, a.id);
        expect(plan.openCutLayers, isEmpty);
      });
    });
  });
}
