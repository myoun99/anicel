import '../../models/bitmap_surface.dart';
import 'frame_clipboard.dart' show FrameBoard;
import 'key_clipboard.dart' show KeyBoard;
import 'layer_clipboard.dart' show LayerBoard;
import 'pixel_board.dart';
import 'text_clipboard.dart' show TextBoard;

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
/// ⛔Separate boards, not one: a frame copy and a layer copy are two
/// payloads (G0-2), and 픽셀 복사 is a third ([PixelBoard], I-55). The cut
/// tool's piece is yet another holder, kept by the workspace the app has
/// one of ([CutPieceSlot]) — it crossed projects before any of this (유저
/// 2026-08-12: 「다른 프로젝트에 붙여넣고 싶을 수 있으니」).
///
/// 🗣️I-77 (유저 2026-10-06): 「복사/붙여넣기버튼 레이어도 연결」. ↩️The frame
/// board and the layer board answered 「two sets of verbs」 — the pill's and
/// the layer menu's. They answer ONE now, the shared pill's copy and its
/// two pastes, so ONE of them is in hand at a time: taking a copy of rows
/// lets the frames go, and the other way round. That is F-161's sentence at
/// the pill's scale — 「복사는 언제나 하나 들고있음. 보통 프로그램이
/// 그러니까」 — and it is what lets a paste need no second question: it
/// puts down what is in hand.
///
/// 🗣️F-388 (유저 2026-10-17): 「키도 복붙기능 제대로 만들고 기존것들이랑 법
/// 통일하고」 — the KEY board is the pill's third, and the hand holds one of
/// the three. ↩️The two let each other go by name, a pair; a third made the
/// rule a list.
///
/// 🗣️I-101 (유저 2026-10-15): 「텍스트를 선택한 상태(변형박스로 변한
/// 상태)에서 복사 가능」 — the TEXT board is the pill's fourth, on the list.
class AppClipboard {
  AppClipboard() {
    final letGoes = [frames.letGo, layers.letGo, keys.letGo, texts.letGo];
    void Function() lettingGoAllBut(void Function() own) => () {
      for (final letGo in letGoes) {
        if (letGo != own) {
          letGo();
        }
      }
    };
    frames.onTake = lettingGoAllBut(frames.letGo);
    layers.onTake = lettingGoAllBut(layers.letGo);
    keys.onTake = lettingGoAllBut(keys.letGo);
    texts.onTake = lettingGoAllBut(texts.letGo);
  }

  final FrameBoard frames = FrameBoard();
  final LayerBoard layers = LayerBoard();

  /// The keys a copy on a lane row took ([KeyBoard], F-388).
  final KeyBoard keys = KeyBoard();

  /// The text a copy of one held by its box took ([TextBoard], I-101).
  final TextBoard texts = TextBoard();

  /// 픽셀 복사's board (I-55) — a third payload with a third set of verbs,
  /// which the frame copy neither reads nor overwrites (유저 2026-10-01:
  /// 「프레임 복사한다고해서 픽셀복사 내역이 사라지지않아」).
  final PixelBoard pixels = PixelBoard();

  /// Every picture the two boards hold — by value, so they stay in memory
  /// for as long as the copy does (`collectMemoryCensus` weighs them).
  Iterable<BitmapSurface> get heldPictures => [
    ...frames.heldPictures,
    ...layers.heldPictures,
  ];
}
