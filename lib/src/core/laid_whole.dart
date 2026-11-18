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
/// brush edit view's shape show), a screen's texture (`ScreenTexture`),
/// the brush in hand drawn as a stroke (`BrushStrokeLivePreview`) and a
/// text in hand (`CelTextSession`) are holders of it. The shape show wrote
/// it out twice, line for line, until the screen made a third
/// (2026-11-12); the stroke and the text had each written it out again
/// (a-float-in-hand-draws-the-frame-as-it-stands ③④, 2026-11-12) — kept
/// apart, a fix to one is a bug left in the others: what [laid] lets go of
/// unseen was the text's alone.
///
/// 🚨WHOLE OR NOT AT ALL. A piece half laid is a wrong picture, and the law
/// allows only a LATE one: nothing is put up until it is whole ([laid]).
///
/// How a piece is laid is its holder's: [ask] begins one where none is
/// being laid ([_begin]), and the holder says when it is whole — a share of
/// each frame for a shape, the GPU's word for a screen, a worker's for a
/// stroke, the engine's for a text.
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
  /// answered — or null, where what is asked for went back meanwhile to
  /// what is up: it is let go of unseen.
  ///
  /// 🚨A PIECE WHOSE WANT WENT BACK TO WHAT IS UP IS NOT PUT UP: up, it
  /// would show for a frame before the screen went back — a step given up
  /// while it was being set (F-377, the text tool's own until it was a
  /// holder of this, 7abe6843a), and 「한 프레임 보이는 건 무조건 걸린다」.
  L? laid() {
    final whole = _laying!;
    _laying = null;
    final wanted = _wanted;
    if (_shown case final shown? when wanted != null && _holds(shown, wanted)) {
      return null;
    }
    _shown = whole;
    return whole;
  }

  /// Whether what is up is not of what is asked for and nothing is being
  /// laid: the newest is to be begun, where its holder begins it
  /// ([layTheNewest]).
  bool get behind {
    final wanted = _wanted;
    if (wanted == null || _laying != null) {
      return false;
    }
    return switch (_shown) {
      final shown? => !_holds(shown, wanted),
      null => true,
    };
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

  /// What was being laid will never be whole — it could not be made, or
  /// its holder gave it up for a newer ask before laying it: what is up
  /// stays. Answers whether something else was asked for meanwhile — that
  /// is begun next time it is laid ([layTheNewest]); what was given up is
  /// not asked of again till it is asked for again ([ask]), or a piece
  /// that cannot be made is begun again and again.
  bool layingGivenUp() {
    final givenUp = _laying!;
    _laying = null;
    final wanted = _wanted;
    return wanted != null && !_holds(givenUp, wanted);
  }

  /// [piece] is up, whole, as what is asked for — [wanted] — made without
  /// being laid here: a text carried by its very pixels, or taken back to
  /// what its cel carries (`CelTextSession`). What is being laid meanwhile
  /// goes on, and is let go of unseen once whole where nothing else is
  /// asked for by then ([laid]).
  void stand(L piece, W wanted) {
    assert(_holds(piece, wanted), 'what stands is what is asked for');
    _wanted = wanted;
    _shown = piece;
  }

  /// Nothing is asked for, laid or up any more.
  void drop() {
    _wanted = null;
    _laying = null;
    _shown = null;
  }
}
