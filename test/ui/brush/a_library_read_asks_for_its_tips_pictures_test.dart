import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/services/brush_preset_file_service.dart';
import 'package:anicel/src/services/brush_tip_library_service.dart';
import 'package:anicel/src/services/brush_tip_thumbnails.dart';
import 'package:anicel/src/ui/brush/brush_preset_library.dart';
import 'package:anicel/src/ui/brush/brush_tip_library.dart';

import '../../helpers/project_scratch_folder.dart';

/// 🗣️tip-coverage-is-a-second-r1-Q1 (유저 2026-11-12): 「미리 만들어 둔다 —
/// 엔진이 열리면 기다리지 않고 받아 둔다」. A library read asks for the
/// picture of every tip it holds ([BrushTipThumbnails.want]), so a grid
/// opened after finds each one made — never asked first by the grid.
void main() {
  late Directory folder;

  setUp(() async {
    // The engine and its kernels ready first: what is asked is made at
    // once, so a picture missing below was never asked for.
    await openAppGpuEngine();
    await appGpuStampLandingKernels.ready;
    folder = await Directory.systemTemp.createTemp('tip_pictures_ahead');
    addTearDown(() => deleteAfterSessionEnds(folder));
  });

  test('🚨the tip library asks for each tip\'s picture as it is read', () async {
    final library = BrushTipLibrary(
      service: BrushTipLibraryService(directoryPath: folder.path),
    );
    addTearDown(library.dispose);
    await library.load();
    await pumpEventQueue();

    final masks = [
      for (final tip in library.tips)
        if (tip.thumbnail == null) ?tip.mask,
    ];
    expect(masks, isNotEmpty, reason: '⛔premise: the built-ins have masks');
    _expectEachMade(masks);
  });

  test('🚨the preset library asks for each preset\'s tip picture as it is '
      'read', () async {
    final library = BrushPresetLibrary(
      fileService: BrushPresetFileService(
        filePath: '${folder.path}/brush_presets.json',
      ),
    );
    addTearDown(library.dispose);
    await library.load();
    await pumpEventQueue();

    final masks = [
      for (final preset in library.presets) ?preset.settings.tipMask,
    ];
    expect(masks, isNotEmpty, reason: '⛔premise: a built-in has a tip');
    _expectEachMade(masks);
  });
}

/// Each of [masks]' pictures there the moment a grid would first ask.
void _expectEachMade(List<BrushTipMask> masks) {
  for (final mask in masks) {
    expect(
      BrushTipThumbnails.instance.of(mask).value,
      isNotNull,
      reason: '${mask.id} was not asked for ahead of its grid',
    );
  }
}
