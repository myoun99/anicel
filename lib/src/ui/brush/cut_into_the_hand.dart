import '../../models/cut_piece.dart';
import '../text/app_strings.dart';
import '../widgets/cursor_notice.dart';

/// What every cut ends in — 전체 잘라내기, an outline on the canvas, an
/// outline on a viewer's page: what it found goes into [hand], and a cut
/// that found nothing says so where the user is looking, the hand keeping
/// what it held.
///
/// 🗣️유저 F-254 — 2026-10-01: 「전체 잘라내기, 지금 작동안하는 그림없는
/// 곳에선 아무메시지 안뜨는데 뜨도록. 내용은 잘라낼 대상이 존재하지
/// 않습니다.」 · 2026-10-08: 「잘라내기도구로 빈 곳에 그렸을때도 동일하게 법
/// 통일해서 적용」. Three doors put a piece in the cut tool's hand, and each
/// decided for itself what an empty cut did: the whole cut said so, the two
/// outlines said nothing.
///
/// ⛔The hand is never emptied by a cut that found nothing: it survives
/// frames, cuts and projects, so one stray scrape must not be able to throw
/// away what is in it (`readCutPiece`).
void cutIntoTheHand(CutPiece? piece, void Function(CutPiece piece) hand) {
  if (piece == null) {
    cursorNotices.show(AppText.strings.noticeNothingToCut);
    return;
  }
  hand(piece);
}
