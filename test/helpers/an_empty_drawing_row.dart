import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// A NEW DRAWING ROW WITH NOTHING ON IT, stood on.
///
/// 🗣️I-138 (유저 2026-10-28): an animation row Add Layer makes is born with
/// its first cel, as a new project's layer A is. A fixture that wants the
/// empty row it used to be born as makes the row the way a user does, then
/// takes that cel away — the playhead put back where it stood.
Layer addAnEmptyDrawingRow(EditorSessionManager session) {
  final at = session.currentFrameIndex;
  session.layerStack.addLayerOfKind(LayerKind.animation);
  session.selectFrameIndex(0);
  session.cells.deleteCellAtCurrentFrame();
  session.selectFrameIndex(at);
  return session.activeLayer!;
}
