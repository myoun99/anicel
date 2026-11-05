import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Color;

import '../../models/export_format_selection.dart';
import '../../models/export_spec.dart';
import '../../models/import/import_warning.dart' show ImportWarning;
import '../../models/project_background.dart';
import '../../services/straight_rgba_image.dart' show straightRgbaOf;
import '../editor_session_manager.dart';
import 'export_frame_renderer.dart';
import 'export_plan.dart';
import 'png_sequence_export_service.dart';
import 'still_image_encoders.dart';

/// The frame a picture of the film is taken of when nobody has turned to
/// another: the playhead's, in the cut an export stands on
/// (`ActiveCutSpan.exportAnchorCutOrNull`) — null when there is no cut.
///
/// ↩️The export window worked this out for itself, as the frame its image
/// tab opens on; 「다른 이름으로 저장」 takes that same frame
/// (backlog-21-Q7, and F-547 for what it shows).
ExportFrameTask? frameUnderThePlayhead(EditorSessionManager session) {
  final cut = session.activeCutSpan.exportAnchorCutOrNull;
  if (cut == null) {
    return null;
  }
  return ExportFrameTask(
    cut: cut,
    frameIndex: session.editingFrameCursor.value.clamp(
      0,
      math.max(1, cut.duration) - 1,
    ),
  );
}

/// What 「다른 이름으로 저장」 writes its picture as, in [format]: the image
/// tab's defaults at size = canvas, all but its ground (the why is at
/// `_pictureSaveAsWrites`).
ImageExportSpec saveAsPictureSpec(ExportStillFormat format) => ImageExportSpec(
  format: ExportFormatSelection(
    kind: ExportMediaKind.still,
    stillFormat: format,
    // A format that keeps no alpha makes its file RGB itself
    // ([ExportFormatSelection.effectiveChannels]).
    channels: ExportChannels.rgba,
    // ⚠️White where the paper lets the ground show in a file with no
    // alpha — not the window's default ground
    // ([defaultExportBackgroundArgb]), which answers what the export
    // window starts on and may change on its own.
    backgroundArgb: 0xFFFFFFFF,
  ),
  sizeMode: ExportSizeMode.canvas,
);

/// [task] as [renderer] draws what the canvas shows, at [spec]'s size, on
/// [paper] — the ONE render behind every picture this file hands out,
/// written or held ([writeFrameImage], [shownFramePicture]).
Future<ui.Image> _asShown(
  ExportFrameRenderer renderer,
  ExportFrameTask task,
  ImageExportSpec spec, {
  required Color guideInk,
  ProjectBackground? paper,
}) => renderer.renderAsShown(
  task,
  spec.sizeMode,
  guideInk: guideInk,
  paper: paper,
);

/// 「다른 이름으로 저장」's picture held in memory instead of written: the
/// frame under the playhead as its PNG is drawn ([saveAsPictureSpec]) —
/// straight RGBA at the canvas's size, so its pixels are the canvas's.
/// Null when there is no cut.
///
/// 🗣️I-163-Q1 (유저 2026-11-05): 「다른 이름으로 저장 한 장으로 통일
/// (스포이드도)」 — what the cut tool's 「표시」 reads is THAT picture, by
/// its code, not a second composite of what is shown.
///
/// ⚠️ON NO PAPER: the save as writes the paper under its rows, and over an
/// opaque paper every pixel of the canvas is ink — a cut would take the
/// box it was drawn as. Where the paper is clear, the PNG keeps nothing, and
/// this is that picture (I-163-Q4 asks whether 「표시」 reads the paper).
Future<({int width, int height, Uint8List rgba})?> shownFramePicture(
  EditorSessionManager session, {
  required Color guideInk,
}) async {
  final task = frameUnderThePlayhead(session);
  if (task == null) {
    return null;
  }
  final spec = saveAsPictureSpec(ExportStillFormat.png);
  final renderer = ExportFrameRenderer.forFormat(
    session: session,
    format: spec.format,
    layerFx: spec.layerFx,
  );
  try {
    final image = await _asShown(renderer, task, spec, guideInk: guideInk);
    try {
      return (
        width: image.width,
        height: image.height,
        rgba: await straightRgbaOf(image),
      );
    } finally {
      image.dispose();
    }
  } finally {
    renderer.dispose();
  }
}

/// Where [writeFrameImage] writes its one file — a folder and the name in
/// it — and, for a run that can be stopped and shows how far it has come,
/// what it asks and tells on the way; and who is told what the file, once
/// written, left out ([ExportFrameRenderer.leftOutOfRows]).
typedef FrameImageFile = ({
  String directory,
  String name,
  bool Function()? isCancelled,
  void Function(int completed, int total)? onProgress,
  void Function(List<ImportWarning> leftOut)? onLeftOut,
});

/// Writes [task] as ONE still file under [spec] — its size, its layer FX,
/// its format's ground and bytes; a PSD, the cut's rows apart
/// ([ExportFrameRenderer.frameRows]) with what is shown over them in a row
/// of its own ([ExportFrameRenderer.rowShownOver]) — as the canvas shows it,
/// with [paper] laid under its rows ([ExportFrameRenderer.renderAsShown]).
/// True when the file was written.
///
/// 🚨The image tab's one picture and 「다른 이름으로 저장」's are THIS call
/// (backlog-21-Q7, 유저 2026-09-30: 「내보내기 「이미지」와 같은 한 장」) —
/// the same picture because it is the same code, never two spellings that
/// agree today. What each asks of it differs only in what it hands in: the
/// spec, and the paper.
///
/// ↩️That one picture was 「깨끗한 한 장」, no mark of the screen on it, until
/// F-547 (유저 2026-11-03): 「화면 보이는 그대로 … 출력탭 이미지저장도 마찬가지」.
Future<bool> writeFrameImage(
  EditorSessionManager session,
  ExportFrameTask task,
  ImageExportSpec spec,
  FrameImageFile file, {
  required Color guideInk,
  ProjectBackground? paper,
}) async {
  final renderer = ExportFrameRenderer.forFormat(
    session: session,
    format: spec.format,
    layerFx: spec.layerFx,
  );
  // The run's pictures and rows are let go when the file is out, as every
  // run of the export window's lets go of its own.
  try {
    final summary = await const PngSequenceExportService().exportImages(
      count: 1,
      renderImage: (_) =>
          _asShown(renderer, task, spec, guideInk: guideInk, paper: paper),
      fileNameFor: (_) => file.name,
      directoryPath: file.directory,
      encoderFor: (_) => layeredEncoderFor(
        spec.format,
        () => [
          ...renderer.frameRows(task, spec.sizeMode, paper: paper),
          ?renderer.rowShownOver(task, spec.sizeMode, guideInk: guideInk),
        ],
      ),
      isCancelled: file.isCancelled,
      onProgress: file.onProgress,
    );
    final written = summary.written == 1;
    if (written) {
      file.onLeftOut?.call(renderer.leftOutOfRows(task));
    }
    return written;
  } finally {
    renderer.dispose();
  }
}
