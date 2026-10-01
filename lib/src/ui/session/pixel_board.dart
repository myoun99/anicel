import 'package:flutter/foundation.dart';

import '../../models/cut_piece.dart';

/// 픽셀 복사's board (I-55): the pixels the last 픽셀 복사 read, at the cel
/// coordinates they were read from.
///
/// 🗣️유저 2026-10-01: 「이렇게 복사한건 커서 프리뷰로 등록하는게아니야. 프레임
/// 복사처럼 클립보드로 내부에서 들고있는느낌? 다만 프레임 복사랑 같은
/// 클립보드 기억하는게아니야 … 픽셀복사는 독립적인 기억영역」 — so a board of
/// its own on the app's clipboard, beside the frame and layer boards, and
/// ⛔NOT the cut tool's slot either: 「픽셀복사/붙여넣기랑 잘라내기도구의
/// 전체잘라내기는 로직적으론 비슷한거 사용할지라도 다른 버튼인건 인지」. The
/// two share the read (`PixelVerbs.standingPiece`) and nothing they hold.
///
/// Pasting leaves it full (유저 2026-08-12: 「붙여넣는다고 들고있는거
/// 삭제시키지않음 … 여기 붙여넣고 저기 또 붙여넣고」).
class PixelBoard extends ChangeNotifier {
  CutPiece? _piece;

  CutPiece? get piece => _piece;

  /// Replaces what the board holds — the whole of 「copy again」.
  void hold(CutPiece piece) {
    _piece = piece;
    notifyListeners();
  }

  /// What the held pixels cost resident — their straight RGBA.
  int get heldBytes => _piece?.image.rgba.lengthInBytes ?? 0;
}
