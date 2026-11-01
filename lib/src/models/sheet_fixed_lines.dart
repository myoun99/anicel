import 'conte/conte_words.dart';

/// What a stretch of a cut writes of itself on a paper form, over the words
/// typed there: a conte cell in its ACTION column, a timesheet page in its
/// memo band (유저 2026-11-02, F-542: 「콘티용지패널에서 고정텍스트 보여주듯이.
/// 똑같이 법 재사용/통일하면서 타임시트 용지패널에서도 메모란에 표시」).
class SheetFixedLines {
  const SheetFixedLines({
    this.cutHead = const [],
    this.camera = const [],
    this.transitions = const [],
    this.linkedCuts = const [],
    this.cutTail = const [],
  });

  static const SheetFixedLines none = SheetFixedLines();

  /// The fades on the head of its cut and on its tail — `FI (0+6)`
  /// (`conteTransitionLine`) — on the cut's first stretch and its last,
  /// none on the others.
  final List<String> cutHead;
  final List<String> cutTail;

  /// What the camera does while the stretch is on — a line to each move and
  /// each stretch it stands still beside one, `6f-16f PAN (0+11)`
  /// (`conteCameraStretches`, I-93), and none where it does nothing.
  final List<String> camera;

  /// The transitions written there — `c1 × c2 カットO.L (1+0)`
  /// (`conteTransitionLine`, I-93-Q1).
  final List<String> transitions;

  /// The cuts its cut is 겸용 with, as a line writes them — on the cut's
  /// first stretch only, none on the others (유저 2026-11-01, F-531:
  /// 「해당 컷의 첫번째 패널에만 적어줌」).
  final List<String> linkedCuts;

  /// The lines as the paper writes them, in [words]: what the camera does,
  /// under it the transitions and under those the 겸용 cuts.
  ///
  /// 🗣️F-540 (유저 2026-11-02): 「FI나 FO같은건 컷 앞이랑 뒤에 고정적으로
  /// 붙는것임. 업계에서는 보통 カット頭 F.I (0+6) 이런식으로 컷 머리 라고 씀.
  /// 뒤는 カット尻 이렇게. 한국어는 컷 앞 컷 뒤」 · 「텍스트 위치는 고정적으로
  /// 고정텍스트 공간 내에서 맨 위나 맨 아래」 — a fade's target is the end of
  /// the cut it stands on, so it opens the lines or closes them.
  List<String> writtenIn(ConteWords words) => [
    for (final line in cutHead) '${words.cutHead} $line',
    ...camera,
    ...transitions,
    if (linkedCuts.isNotEmpty) '${words.linked} ${linkedCuts.join(',')}',
    for (final line in cutTail) '${words.cutTail} $line',
  ];
}
