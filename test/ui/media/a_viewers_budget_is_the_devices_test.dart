import 'dart:ui' as ui;

import 'package:anicel/src/native/qa_memory.dart';
import 'package:anicel/src/ui/media/media_run.dart';
import 'package:anicel/src/ui/media/viewer_pages_and_run.dart';
import 'package:anicel/src/ui/media/viewer_raster_budget.dart';
import 'package:anicel/src/ui/media/viewer_sound.dart';
import 'package:anicel/src/ui/sheet/sheet_image_cache.dart';
import 'package:anicel/src/ui/storyboard_cut_thumbnail_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🚨EVERY VIEWER'S BUDGET IS THIS DEVICE'S — the pages on show, the
/// sheets' pictures and the storyboard's panels, each one viewer's share
/// ([ViewerRasterBudget]).
///
/// ⚠️Read under 6GB of RAM, where no test machine stands: there a quarter
/// of the RAM clamps to 1536MB, the same as no RAM at all, so a viewer that
/// read none passed every pin (관제 2026-11-08 16:21 — three such mutants
/// lived through the memory move). A 4GB tablet is where the two part.
void main() {
  const tablet = 4 * 1024 * 1024 * 1024;

  setUp(() => QaMemory.debugPhysicalMemoryBytes = () => tablet);
  tearDown(() => QaMemory.debugPhysicalMemoryBytes = null);

  int tabletShare() =>
      ViewerRasterBudget(physicalMemoryBytes: tablet).byteBudget;

  test('fixture: the tablet\'s share is not a desktop\'s', () {
    expect(
      tabletShare(),
      isNot(ViewerRasterBudget(physicalMemoryBytes: null).byteBudget),
    );
  });

  test('the pages on show', () {
    final pages = ViewerPagesAndRun(
      surface: _NoSurface(),
      sound: _NoSound(),
      report: (_) {},
    );
    expect(pages.rasters.budget.byteBudget, tabletShare());
  });

  test('the sheets\' pictures', () {
    final cache = SheetImageCache(read: (_, _) async => null);
    addTearDown(cache.dispose);
    expect(cache.debugByteBudget, tabletShare());
  });

  test('the storyboard\'s panels', () {
    final store = StoryboardCutThumbnailStore(
      render: (_, _, _, _) => throw UnimplementedError('nothing is shown'),
      originalSize: () => const ui.Size(1920, 1080),
    );
    addTearDown(store.dispose);
    expect(store.debugByteBudget, tabletShare());
  });
}

/// The pages' budget asks nothing of the surface it shows on.
class _NoSurface implements MediaRunSurface {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Nor of the sound beside them.
class _NoSound implements ViewerSound {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
