import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The onion ghosts a canvas standing on [session]'s cut at [frameIndex] —
/// the playhead where none is named — lays over the frame, as it draws them
/// (`EditingCanvas.ghostsOverAt`).
List<CanvasLayerImageRequest> ghostRequestsAt(
  EditorSessionManager session, {
  int? frameIndex,
}) => [
  for (final node in session.editingCanvas.ghostsOverAt(
    session.requireActiveCut,
    frameIndex ?? session.currentFrameIndex,
  ))
    (node as CompositeLeaf<CanvasStackRow>).payload as CanvasLayerImageRequest,
];
