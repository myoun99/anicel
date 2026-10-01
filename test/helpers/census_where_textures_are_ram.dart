import 'package:flutter/foundation.dart';
import 'package:anicel/src/ui/diagnostics/memory_census.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The census as it reads where the GPU shares the RAM (Apple) — the one
/// place every texture row is counted ([texturesAreInTheRamFigure]). For a
/// test that pins what a texture holder puts on the books; everywhere else
/// those rows are not RAM and are left out (F-226-Q1).
///
/// ⚠️Only the census is read as Apple: the platform flips around this one
/// call, so nothing else the test drives changes platform under it.
MemoryCensus collectMemoryCensusWhereTexturesAreRam(
  Iterable<EditorSessionManager> sessions,
) {
  final was = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  try {
    return collectMemoryCensus(sessions);
  } finally {
    debugDefaultTargetPlatformOverride = was;
  }
}
