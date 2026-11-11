import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/ui/frame_shots.dart' show pictureOfLaid;

/// [picture] as a film's writer takes a frame — a frame the export makes,
/// [picture]'s premultiplied rows uploaded and laid over it, as the
/// renderer hands one (`ExportFrameRenderer.filmFrame`) — and [picture]
/// let go of.
///
/// The frame is the test's, freed when the test is done: a writer reads
/// what it writes of a frame and lets go of none (`VideoExportService`).
Future<GpuShown> filmFrameOf(ui.Image picture) async {
  final (width, height) = (picture.width, picture.height);
  try {
    final rows = await picture.toByteData();
    final uploaded = appGpuExport.upload(
      rows!.buffer.asUint8List(),
      width,
      height,
    );
    try {
      final frame = appGpuExport.blank(width, height);
      addTearDown(frame.free);
      appGpuExport.lay(frame, uploaded);
      return frame;
    } finally {
      uploaded.free();
    }
  } finally {
    picture.dispose();
  }
}

/// A [width] × [height] frame on the engine, all of it [colour]
/// ([filmFrameOf]).
Future<GpuShown> filmFrameIn(
  ui.Color colour, {
  int width = 4,
  int height = 2,
}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(colour, ui.BlendMode.src);
  final recorded = recorder.endRecording();
  try {
    return await filmFrameOf(await recorded.toImage(width, height));
  } finally {
    recorded.dispose();
  }
}

/// What a preview shows of a film's [frame] — the renderer's, on the
/// engine (`ExportRun.frame`) — read back once ([pictureOfLaid]): a
/// picture of the caller's own to dispose, of the frame its writer takes.
Future<ui.Image> pictureOfFilmFrame(Future<GpuShown> frame) async =>
    pictureOfLaid(appGpuExport, await frame);
