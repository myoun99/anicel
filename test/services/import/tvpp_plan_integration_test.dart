import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/import/import_warning.dart';
import 'package:anicel/src/models/import/tvp_import_model.dart';
import 'package:anicel/src/models/import/tvpp_convert.dart';
import 'package:anicel/src/models/import/tvpp_parse.dart';
import 'package:anicel/src/models/inbetween_mark.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/import/tvp_import_planner.dart';
import 'package:flutter_test/flutter_test.dart';

/// The .tvpp pipeline end to end WITHOUT pixels: parse-model conversion
/// feeding the SAME planner the JSON export uses — folders arrive as
/// folder rows with members linked, and image marks land as the blocks'
/// inbetween dots.
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

  TvppSlot image() => const TvppSlot(
        kind: TvppSlotKind.image,
        chunkOffset: 0,
        chunkLength: 0,
        compressed: true,
      );

  TvppSlot hold() => const TvppSlot(
        kind: TvppSlotKind.hold,
        chunkOffset: 0,
        chunkLength: 0,
        compressed: true,
      );

  test('folders become folder rows and marks become inbetween dots', () {
    final clip = TvppClip(
      name: 'cut12',
      width: 320,
      height: 180,
      frameRate: 24,
      pixelAspectRatio: 1,
      layers: [
        const TvppLayer(
          kind: TvppLayerKind.camera,
          name: 'cam',
          layerId: 0,
          parentId: 0,
          start: 0,
          end: 0,
          opacity: 255,
          preBehavior: TvpEdgeBehavior.none,
          postBehavior: TvpEdgeBehavior.none,
          slots: [],
          ctgSecondStream: [],
          instanceNames: {},
        ),
        const TvppLayer(
          kind: TvppLayerKind.folder,
          name: 'F',
          layerId: 9,
          parentId: 0,
          start: 0,
          end: 0,
          opacity: 255,
          preBehavior: TvpEdgeBehavior.none,
          postBehavior: TvpEdgeBehavior.none,
          slots: [],
          ctgSecondStream: [],
          instanceNames: {},
          collapsed: true,
        ),
        TvppLayer(
          kind: TvppLayerKind.raster,
          name: 'A',
          layerId: 8,
          parentId: 9,
          start: 0,
          end: 3,
          opacity: 255,
          preBehavior: TvpEdgeBehavior.none,
          postBehavior: TvpEdgeBehavior.hold,
          slots: [image(), hold(), hold(), hold()],
          ctgSecondStream: const [],
          instanceNames: const {0: '1'},
        ),
      ],
      imageMarks: const [
        TvppImageMark(layerIndex: 2, frame: 2, colorIndex: 1),
      ],
      cameraPoints: const [],
      cameraDataText: '',
    );

    final conversion = convertTvppClip(clip, clipIndex: 0);
    final plan = planTvpImport(
      parsed: conversion.result,
      resolveFile: (key) => key,
      mint: mint(),
      unnamedMark: defaultUnnamedDrawingMark,
    );

    expect(plan.cut.name, 'cut12');

    final a = plan.cut.layers.singleWhere((l) => l.name == 'A');
    final folder = plan.cut.layers.singleWhere((l) => l.name == 'F');
    expect(
      plan.cut.layers.indexOf(folder),
      plan.cut.layers.indexOf(a) + 1,
      reason: '폴더 행은 멤버 바로 위(bottom-first에서 바로 뒤)에 선다',
    );
    expect(folder.kind, LayerKind.folder);
    expect(a.folderId, folder.id);
    expect(folder.folderId, isNull);
    expect(
      folder.collapsed,
      isTrue,
      reason: 'folded in TVPaint, folded here (F-306: 「접힌 폴더는 접힌상태로 '
          '들여오도록」)',
    );

    // One drawing held 4 frames, the mark as its inbetween dot.
    final exposure = a.timeline[0]!;
    expect(exposure.length, 4);
    expect(exposure.breakdownOffsets, const [2]);
    for (final pick in InbetweenMark.values) {
      final picked = planTvpImport(
        parsed: conversion.result,
        resolveFile: (key) => key,
        mint: mint(),
        unnamedMark: pick,
      ).cut.layers.singleWhere((l) => l.name == 'A');
      expect(
        picked.timeline[0]!.breakdownMarks,
        {2: pick},
        reason:
            'a TVPaint mark says no kind, so it wears the mark an unnamed '
            'drawing wears, whichever is picked — 🗣️F-489-Q1 (유저 '
            '2026-10-27) 「둘 다 따라간다」',
      );
    }

    // The bake carries the slot key the session resolves.
    expect(plan.bakes, hasLength(1));
    expect(conversion.slotsByFile.containsKey(plan.bakes.single.sourceFile),
        isTrue);
  });

  test('a sound track becomes an SE row: reference linked, blockized', () {
    const parsed = TvpImportClip(
      versionMajor: 0,
      versionMinor: 0,
      clipName: 'cut',
      width: 320,
      height: 180,
      frameRate: 24,
      pixelAspectRatio: 1,
      frameCount: 48,
      background: TvpColor(255, 255, 255),
      markIn: null,
      markOut: null,
      camera: TvpCamera(
        width: 320,
        height: 180,
        keyedOn: (position: [], zoom: [], rotation: []),
        positions: [],
      ),
      layers: [],
      warnings: [],
      audioTracks: [
        TvpAudioTrack(
          filePath: 'G:/sagyou/12.mp4',
          offsetSeconds: 0.5, // = 12 frames at 24fps
          volume: 0.51,
          muted: false,
        ),
      ],
    );
    final plan = planTvpImport(
      parsed: parsed,
      resolveFile: (key) => key,
      mint: mint(),
      unnamedMark: defaultUnnamedDrawingMark,
    );
    final se = plan.cut.layers.singleWhere((l) => l.kind == LayerKind.se);
    expect(se.name, '12.mp4');
    final block = se.timeline[12]!;
    expect(block.length, 36); // runs to the cut's end.
    expect(se.audioClips, hasLength(1));
    expect(se.audioClips.single.filePath, 'G:/sagyou/12.mp4');
    expect(se.audioClips.single.frameId, block.frameId);
    expect(se.audioClips.single.gain, closeTo(0.51, 1e-9));
    expect(plan.warnings, isEmpty);
  });

  test('a locked sound track comes in on an SE row, which has no lock — '
      'named by its file, as a muted one is; the track beside it, not '
      'locked, says nothing (보드 the-clip-import-leaves-masks-and-locks-'
      'unsaid)', () {
    // From the parse model, through the conversion: a planner fed the
    // import model directly passed with the conversion dropping the lock.
    const clip = TvppClip(
      name: 'cut',
      width: 320,
      height: 180,
      frameRate: 24,
      pixelAspectRatio: 1,
      layers: [
        TvppLayer(
          kind: TvppLayerKind.camera,
          name: 'cam',
          layerId: 0,
          parentId: 0,
          start: 0,
          end: 47,
          opacity: 255,
          preBehavior: TvpEdgeBehavior.none,
          postBehavior: TvpEdgeBehavior.none,
          slots: [],
          ctgSecondStream: [],
          instanceNames: {},
        ),
      ],
      imageMarks: [],
      cameraPoints: [],
      cameraDataText: '',
      audioTracks: [
        TvppAudioTrack(
          filePath: 'G:/sagyou/12.mp4',
          offsetSeconds: 0,
          volume: 1,
          muted: false,
          locked: true,
        ),
        TvppAudioTrack(
          filePath: 'G:/sagyou/13.wav',
          offsetSeconds: 0,
          volume: 1,
          muted: false,
        ),
      ],
    );
    final plan = planTvpImport(
      parsed: convertTvppClip(clip, clipIndex: 0).result,
      resolveFile: (key) => key,
      mint: mint(),
      unnamedMark: defaultUnnamedDrawingMark,
    );

    expect(plan.warnings, [lockNotImported('12.mp4')]);
    expect(
      [
        for (final layer in plan.cut.layers)
          if (layer.kind == LayerKind.se) layer.name,
      ],
      unorderedEquals(['12.mp4', '13.wav']),
    );
  });
}
