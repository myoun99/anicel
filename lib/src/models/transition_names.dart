import 'camera_instruction.dart';
import 'cut.dart';
import 'layer.dart';
import 'track_transitions.dart';
import 'transition_geometry.dart';

/// 🗣️F-229 (유저 2026-09-29): 「트랜지션 레이어는 대상이 확실해서 시작이름
/// 끝이름 기호이름 이런거 정할 필요가 없으니 이쪽에서 등록. OL의 경우
/// 시작이름은 대상인 이전컷, 끝이름은 대상의 다음컷임. 다만 301 이렇게
/// 표기하면 컷인지 모르니 컷이름앞에 c를 붙여서 c301 이렇게되도록. 이름부분은
/// 그냥 컷O.L. 일본어론 カットO.L 이렇게. 타임시트패널에도 기존 디렉션 표기
/// 규칙 통일해서 따라서 적용」.
///
/// [row] — a track's transition row, on the track's axis — with every span's
/// writing read off where the span lies, never off what was typed into it:
///
/// * an O.L joins two cuts: it starts at the cut whose end it crosses and
///   ends at the cut whose start it crosses, each written as that cut's name
///   after a `c` ([transitionEndName]), and it is named [olWord] — the word
///   in the language the reader prints in;
/// * a one-sided fade's only target is its own cut (D26), which the sheet or
///   row it is read on already names — it writes no ends and goes by its
///   term's name.
///
/// A side with no cut — an O.L into a gap, 「갭도 상대다」 — writes nothing
/// there. The memo is the user's and stays.
///
/// ⛔Derived where it is read, never stored: an end follows a rename or a
/// move the moment it lands, and the name follows the reading language.
/// [row] itself comes back when every span already reads this way.
Layer transitionRowNamedByItsCuts({
  required Layer row,
  required Iterable<({Cut cut, int startFrame, int endFrame})> cuts,
  required CameraInstructionSet vocabulary,
  required String olWord,
}) {
  final placed = cuts.toList();
  final named = <int, InstructionEvent>{};
  var changed = false;
  for (final entry in row.instructions.entries) {
    final event = entry.value;
    final span = transitionSpanOfEvent(entry, vocabulary);
    final twoSided = transitionSidesOf(span.mark) == TransitionSides.both;
    final ends = twoSided
        ? _cutsJoined(placed, start: span.start, end: span.start + span.length)
        : null;
    final text = twoSided ? olWord : null;
    final from = ends?.leaving == null ? null : transitionEndName(ends!.leaving!);
    final to = ends?.entering == null
        ? null
        : transitionEndName(ends!.entering!);
    final same =
        event.text == text && event.valueA == from && event.valueB == to;
    named[entry.key] = same
        ? event
        : event.copyWith(text: () => text, valueA: () => from, valueB: () => to);
    changed = changed || !same;
  }
  return changed ? row.copyWith(instructions: named) : row;
}

/// How a cut is written at a transition's end: its name after a `c`, so
/// `301` reads as a cut (F-229).
String transitionEndName(Cut cut) => 'c${cut.name}';

/// The cut whose END `[start, end)` crosses and the cut whose START it
/// crosses — the crossing test [transitionSpanFires] makes for a cut's
/// boundaries.
({Cut? leaving, Cut? entering}) _cutsJoined(
  List<({Cut cut, int startFrame, int endFrame})> placed, {
  required int start,
  required int end,
}) {
  Cut? leaving;
  Cut? entering;
  for (final cut in placed) {
    if (leaving == null && cut.endFrame > start && cut.endFrame < end) {
      leaving = cut.cut;
    }
    if (entering == null && cut.startFrame > start && cut.startFrame < end) {
      entering = cut.cut;
    }
  }
  return (leaving: leaving, entering: entering);
}
