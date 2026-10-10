import '../../native/qa_native_engine.dart';
import 'media_run.dart';
import 'page_rasters.dart';
import 'viewer_raster_budget.dart';
import 'viewer_sound.dart';

/// A DOCUMENT'S PAGES ON SHOW AND THE RUN THAT TURNS THEM — wired once.
///
/// 🚨The media viewer, the export window's preview and the import window's
/// each built this pair for themselves, line for line; the third made it a
/// copy (F-282 ④, 2026-10-09). The cache asks the run here, once, when a
/// page is next wanted (`wantedAt:` — the canvas's order since the board's
/// `viewer-plays-by-the-one-playback-law` ②, which changed it in this one
/// place).
///
/// What stays each surface's own: the census key its pages are counted
/// under ([report]), the memory warnings it listens to, and what it lets go
/// of in what order. Those differ between the three, and an answer shared
/// here would decide them for each.
final class ViewerPagesAndRun {
  ViewerPagesAndRun({
    required MediaRunSurface surface,
    required ViewerSound sound,
    required void Function(int bytes) report,
  }) : _surface = surface,
       _sound = sound,
       _report = report;

  final MediaRunSurface _surface;
  final ViewerSound _sound;
  final void Function(int bytes) _report;

  /// The document's pages as rasters, under this device's budget — see
  /// [PageRasters].
  ///
  /// ⚠️Built with the surface, so a test that wants a tight budget sets
  /// [ViewerRasterBudget.debugPageBytesOverride] BEFORE the panel mounts;
  /// pumping the same widget again reuses this budget.
  late final PageRasters rasters = PageRasters(
    budget: ViewerRasterBudget(
      physicalMemoryBytes: QaNativeEngine.instance?.physicalMemoryBytes,
    ),
    document: () => _surface.document,
    wantedAt: (page) => run.wantedAt(page),
    rebuild: _surface.setState,
    mounted: () => _surface.mounted,
    report: _report,
  );

  /// The run: the timer turning pages, the sound beside them, and the law
  /// that the whole transport waits — see [MediaRun].
  late final MediaRun run = MediaRun(
    surface: _surface,
    rasters: rasters,
    sound: _sound,
  );
}
