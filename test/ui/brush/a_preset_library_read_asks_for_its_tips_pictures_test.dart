import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/brush_preset_file_service.dart';
import 'package:anicel/src/services/brush_tip_thumbnails.dart';
import 'package:anicel/src/ui/brush/brush_preset_library.dart';

import '../../helpers/tip_pictures_asked_ahead.dart';

/// 🗣️tip-coverage-is-a-second-r1-Q1 (유저 2026-11-12): 「미리 만들어 둔다 —
/// 엔진이 열리면 기다리지 않고 받아 둔다」. The preset library's read asks
/// for the picture of each preset's tip ([BrushTipThumbnails.want]), so its
/// list finds each one made.
///
/// ⚠️A file of its own: its built-ins share the tip library's tips, and a
/// tip library read in this process before it would have asked for them
/// (a_library_read_asks_for_its_tips_pictures_test.dart).
void main() {
  test('🚨the preset library asks for each preset\'s tip picture as it is '
      'read', () async {
    final folder = await aLibraryFolderWithTheEngineReady('preset_pictures');
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
    expectEachTipPictureMade(masks);
  });
}
