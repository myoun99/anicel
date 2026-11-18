import 'dart:io';

import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/services/brush_tip_thumbnails.dart';
import 'package:flutter_test/flutter_test.dart';

import 'project_scratch_folder.dart';

/// A folder of [name] for a library to read, with the engine and its
/// kernels ready first: what is asked is made at once, so a picture
/// missing after the read was never asked for
/// ([expectEachTipPictureMade]).
Future<Directory> aLibraryFolderWithTheEngineReady(String name) async {
  await openAppGpuEngine();
  await appGpuStampLandingKernels.ready;
  final folder = await Directory.systemTemp.createTemp(name);
  addTearDown(() => deleteAfterSessionEnds(folder));
  return folder;
}

/// Each of [masks]' pictures there the moment a grid would first ask
/// ([BrushTipThumbnails.of]).
void expectEachTipPictureMade(List<BrushTipMask> masks) {
  for (final mask in masks) {
    expect(
      BrushTipThumbnails.instance.of(mask).value,
      isNotNull,
      reason: '${mask.id} was not asked for ahead of its grid',
    );
  }
}
