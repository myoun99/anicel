/// 🚨★★★THE NEWEST ASKED FOR, LAID OFF SCREEN AND PUT UP WHOLE — and the
/// last one put up stands until the next is whole.
///
/// 🗣️I-69-Q4ⓒ (유저 2026-10-08), of a shape dragged: 「윤곽선은 손을
/// 따라오고, 실제 결과는 따라 그린다」 — the outline follows the hand every
/// frame and stays light; under it the result is laid at the pace the
/// device can manage, once more at the hand's newest each time the last is
/// done, and what was showing when the hand lets go is what stays.
///
/// 🗣️a-float-in-hand-draws-the-frame-as-it-stands-Q2 (유저 2026-11-12), of
/// a screen's picture under a box dragged: 「z로 직선 그을때나 같은 규칙. ui로서는
/// 바로 작동하지만 정확함을 요구하는 그림은 끝나는대로 준비함 … 구형기기라면 ui는
/// 바로바로 움직이고 ui랑 그림이랑 달라지는 결과가 됨. 어긋나는거 ok」 — the box,
/// its handles and the cursor follow the pen; the picture is put up as the
/// GPU finishes it.
///
/// ⛔ONE LAW, NOT ONE A HOLDER: the shape tool's area and its stroke (the
/// brush edit view's shape show) and a screen's texture (`ScreenTexture`)
/// are three holders of it. The shape show wrote it out twice, line for
/// line, until the screen made a third (2026-11-12) — kept apart, a fix to
/// one is a bug left in the others.
///
/// 🚨WHOLE OR NOT AT ALL. A piece half laid is a wrong picture, and the law
/// allows only a LATE one: nothing is put up until it is whole ([laid]).
///
/// How a piece is laid is its holder's: [ask] begins one where none is
/// being laid ([_begin]), and the holder says when it is whole — a share of
/// each frame for a shape, the GPU's word for a screen.
final class LaidWhole<W extends Object, L extends Object> {
  /// [begin] starts laying what is asked for, and [holds] says whether a
  /// piece laid is of what is asked for — what is up then needs nothing.
  LaidWhole({
    required L Function(W wanted) begin,
    required bool Function(L laid, W wanted) holds,
  }) : _begin = begin,
       _holds = holds;

  final L Function(W wanted) _begin;
  final bool Function(L laid, W wanted) _holds;

  /// What is asked for now — the hand's newest.
  W? get wanted => _wanted;
  W? _wanted;

  /// What is being laid, off screen.
  L? get laying => _laying;
  L? _laying;

  /// What is up, whole.
  L? get shown => _shown;
  L? _shown;

  /// Asks for [wanted], the newest: begun at once where nothing is being
  /// laid and what is up is not of it already. Answers whether it began.
  bool ask(W wanted) {
    _wanted = wanted;
    return layTheNewest();
  }

  /// What is being laid is whole: it is up in place of what stood, and is
  /// answered.
  L laid() {
    final whole = _laying!;
    _laying = null;
    _shown = whole;
    return whole;
  }

  /// 「앞의 것을 다 그리면 지금 손 위치로 한 번 더」: begins the newest asked
  /// for, where nothing is being laid and what is up is not of it. Answers
  /// whether it began.
  bool layTheNewest() {
    final wanted = _wanted;
    if (wanted == null || _laying != null) {
      return false;
    }
    if (_shown case final shown? when _holds(shown, wanted)) {
      return false;
    }
    _laying = _begin(wanted);
    return true;
  }

  /// What was being laid will never be whole: what is up stays, and the
  /// newest asked is begun next time it is laid ([layTheNewest]).
  void layingFailed() {
    _laying = null;
  }

  /// Nothing is asked for, laid or up any more.
  void drop() {
    _wanted = null;
    _laying = null;
    _shown = null;
  }
}
