import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// A NEW CUT WITH A DRAWING ROW TO STAND ON.
///
/// F-211 (유저 2026-09-28): 「새 컷 생성의 초기값은 프레임도 없고 나아가서
/// A라는 기본 레이어도 존재안하도록」 — a new cut is bare: DIR 1 and the
/// camera. A fixture that needs a cel row in its new cut makes one the way
/// a user does: the cut, then ＋ layer (which names it 「A」 there and
/// stands on it).
///
/// ↩️These fixtures stood on the blank layer A a new cut used to be born
/// with.
void createCutWithADrawingRow(EditorSessionManager session) {
  session.cutVerbs.createCut();
  session.layerStack.addLayerOfKind(LayerKind.animation);
}
