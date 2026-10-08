import 'dart:math' as math;

import '../../models/export_spec.dart';
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
/// (backlog-21-Q7: 「내보내기 「이미지」와 같은 깨끗한 한 장」).
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

/// Where [writeFrameImage] writes its one file — a folder and the name in
/// it — and, for a run that can be stopped and shows how far it has come,
/// what it asks and tells on the way.
typedef FrameImageFile = ({
  String directory,
  String name,
  bool Function()? isCancelled,
  void Function(int completed, int total)? onProgress,
});

/// Writes [task] as ONE still file under [spec] — its size, its layer FX,
/// its format's ground and bytes. True when the file was written.
///
/// 🚨The image tab's one picture and 「다른 이름으로 저장」's are THIS call
/// (backlog-21-Q7, 유저 2026-09-30: 「내보내기 「이미지」와 같은 깨끗한 한
/// 장」) — the same picture because it is the same code, never two
/// spellings that agree today.
Future<bool> writeFrameImage(
  EditorSessionManager session,
  ExportFrameTask task,
  ImageExportSpec spec,
  FrameImageFile file,
) async {
  final renderer = ExportFrameRenderer.forFormat(
    session: session,
    format: spec.format,
    applyLayerFx: spec.applyLayerFx,
  );
  final summary = await const PngSequenceExportService().exportImages(
    count: 1,
    renderImage: (_) => renderer.renderComposite(task, spec.sizeMode),
    fileNameFor: (_) => file.name,
    directoryPath: file.directory,
    encoderFor: (_) => stillEncoderFor(spec.format),
    isCancelled: file.isCancelled,
    onProgress: file.onProgress,
  );
  return summary.written == 1;
}
