import 'dart:ui' as ui;

import 'package:gpu_engine/gpu_engine.dart' show GpuShown;

import '../../native/app_gpu_engine.dart'
    show KeptOnTheAppsEngine, appGpuExportKernels;
import '../frame_shots.dart' show frameOfPicture;

/// The pictures a run of files draws for itself — a sheet's page, an
/// envelope, a conte's — each laid on a frame of the export's for its
/// writer to take ([frameOfPicture]), and held till the next is asked: a
/// writer reads what it writes of a frame before it asks the next
/// (`PngSequenceExportService.exportImages`), as the renderer's frames are
/// held for it (`ExportFrameRenderer`).
///
/// Held while the engine it was made on is the app's
/// ([KeptOnTheAppsEngine]): one the app let go of is left with it.
final class FramesOfPictures {
  final KeptOnTheAppsEngine<GpuShown> _held = KeptOnTheAppsEngine(
    (frame) => frame.free(),
  );

  /// [picture]'s frame — none where there is no picture — the one held
  /// before let go. [picture] is let go once it is laid.
  Future<GpuShown?> of(Future<ui.Image?> picture) async {
    final drawn = await picture;
    _held.forget();
    if (drawn == null) {
      return null;
    }
    try {
      final frame = await frameOfPicture(
        await appGpuExportKernels.ready,
        drawn,
      );
      return _held.of(() => frame);
    } finally {
      drawn.dispose();
    }
  }

  /// Lets go of the frame held: the run is over.
  void dispose() => _held.forget();
}
