import 'frame_clipboard.dart' show FrameBoard;
import 'layer_clipboard.dart' show LayerBoard;

/// THE APP'S CLIPBOARD — what the last copy of each kind put in hand, ONE
/// for every open project (I-7).
///
/// 🚨★★유저 2026-09-26: 「탭사이에 복사나 붙여넣기 뭐든 가능. 앱 전체에
/// 하나. 레이어 id가 다른거?라던가 id늘리게한다던가 알아서 조심하고.」 The
/// answer they picked: the last copy pastes in any open project; into
/// ANOTHER project it pastes independent — cels of its own, ids that project
/// mints, the pictures with them — and a LINKED paste stays in the project
/// it came from, because a link is 「the same cel」 and no cel of one
/// project is a cel of another.
///
/// It is the SHELL's (「프로젝트를 넘어 사는 것은 앱」, I-7's first law): the
/// home page holds one and hands it to every session it opens; a session
/// made on its own — a test, a tool — gets one of its own.
///
/// ⛔Two boards, not one: a frame copy and a layer copy are two payloads
/// answering two sets of verbs (G0-2). The cut tool's piece is a third
/// holder, kept by the workspace the app has one of ([CutPieceSlot]) — it
/// crossed projects before any of this (유저 2026-08-12: 「다른 프로젝트에
/// 붙여넣고 싶을 수 있으니」).
class AppClipboard {
  final FrameBoard frames = FrameBoard();
  final LayerBoard layers = LayerBoard();
}
