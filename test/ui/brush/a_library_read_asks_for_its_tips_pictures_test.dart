import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/brush_tip_library_service.dart';
import 'package:anicel/src/services/brush_tip_thumbnails.dart';
import 'package:anicel/src/ui/brush/brush_tip_library.dart';

import '../../helpers/tip_pictures_asked_ahead.dart';

/// 🗣️tip-coverage-is-a-second-r1-Q1 (유저 2026-11-12): 「미리 만들어 둔다 —
/// 엔진이 열리면 기다리지 않고 받아 둔다」. A library read asks for the
/// picture of every tip it holds ([BrushTipThumbnails.want]), so a grid
/// opened after finds each one made — never asked first by the grid.
///
/// ⚠️The preset library's is a file of its own
/// (a_preset_library_read_asks_for_its_tips_pictures_test.dart): the
/// pictures are the process's, and its built-ins share this library's tips
/// — read here first, they were asked for by this read, not by its own
/// (🔬its want taken out survived beside this one, 11-13).
void main() {
  test('🚨the tip library asks for each tip\'s picture as it is read', () async {
    final folder = await aLibraryFolderWithTheEngineReady('tip_pictures');
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
    expectEachTipPictureMade(masks);
  });
}
