import 'dart:math' as math;

import '../camera_instruction.dart';
import '../camera_moves.dart';
import '../project_frame_rate.dart' show secondsPlusFramesLabel;

/// A stretch of a conte cell's frames as its ACTION column names it: the
/// [move] the camera makes there — or null where it stands still, FIX —
/// and how many of the cell's frames it lasts.
typedef ConteCameraStretch = ({CameraMove? move, int frames});

/// WHAT THE CAMERA DOES WHILE A CONTE CELL IS ON (I-93): the cut's frames
/// [from] to [to], in order, as each of [moves] ([cameraMoves]) where it
/// moves and a FIX where none does — a line each on the cell's ACTION
/// column ([conteCameraLine]). A cell no move reaches has none: its FIX
/// says nothing the blank does not.
///
/// 🗣️I-93 (유저 2026-10-12): 「콘티용지패널 내용란에 고정텍스트로 PAN이나
/// TU나 추가로 콘티엔 시간정보가 같은 칸내에선 없으니 FIX부분 도
/// 적어주도록 … PAN이나 TU가 되는지는 상담해서 정해진 모아트참고하는
/// 방식으로 정해진 규칙대로 통일하고, FIX부분은 추가로 카메라가
/// 멈춰있는부분(값이 동일해서 안움직이고 있거나 키가 없는 부분)을 FIX로
/// 표시하도록. 예를들어 1f부터 5f까지 키가 없고, 6f에 키가있고, 16f에
/// 작아지는 키가 있고, 24f가 컷의 끝이라면, FIX (0+5), PAN (0+11),
/// FIX (0+8) 이런식 … 편집할때마다 바뀌는. 각 FIX PAN 이런거마다
/// 개행되고」.
///
/// 🗣️I-93 (유저 2026-10-30): 「지금보면 FIX도 매 패널마다 적어주는데 그게
/// 아님. 카메라움직임 발생해서 그게 기록되고 그 다음에 픽스인부분이 있으면
/// 적어주는것임. 즉 패널중간에 움직이기 시작하면 해당패널에서 픽스적어주고,
/// PAN같은거적어줌. 패널내에서 끝나고 멈춰있는 카메라일때도 PAN같은거 적고
/// 다음 FIX. 패널에서 카메라 아무것도 안했으면 안적는다」. ↩️Every cell wrote
/// its FIX, the whole cell long where the camera stood still.
///
/// ⚠️Mine: a move holds its frames from its first key to the frame before
/// the next move starts — and its end key too where no move starts there,
/// so the PAN from 6f to 16f is the user's 11 frames, and the stretches of
/// a cell a move reaches add up to the cell. Every frame of it no move
/// holds is FIX, a stretch to each run of them.
///
/// ⚠️Mine: a cell writes its own frames only — a move two cells share is a
/// stretch in each, as long as each holds it.
List<ConteCameraStretch> conteCameraStretches(
  List<CameraMove> moves, {
  required int from,
  required int to,
}) {
  final stretches = <ConteCameraStretch>[];
  void add(CameraMove? move, int start, int end) {
    if (end > start) {
      stretches.add((move: move, frames: end - start));
    }
  }

  var at = from;
  for (final (index, move) in moves.indexed) {
    final next = index + 1 < moves.length ? moves[index + 1] : null;
    final start = math.max(move.from, at);
    final end = math.min(next?.from == move.to ? move.to : move.to + 1, to);
    if (start >= end) {
      continue;
    }
    add(null, at, start);
    add(move, start, end);
    at = end;
  }
  add(null, at, to);
  return stretches.any((stretch) => stretch.move != null)
      ? stretches
      : const [];
}

/// [stretch] as its line reads: its move's word ([cameraMoveWord]) or the
/// glossary's FIX ([cameraFixTerm]) — each in the glossary [defById]
/// reads, so a term renamed there is written renamed — and how long it
/// lasts in seconds and frames ([secondsPlusFramesLabel]): `FIX (0+5)`.
String conteCameraLine(
  ConteCameraStretch stretch, {
  required CameraInstructionDef? Function(String id) defById,
  required int framesPerSecond,
}) {
  final move = stretch.move;
  final word = move == null
      ? instructionTermName(cameraFixTerm, defById(cameraFixTerm))
      : cameraMoveWord(move, defById);
  final length = secondsPlusFramesLabel(stretch.frames, framesPerSecond);
  return '$word ($length)';
}

/// What a conte line writes between the two cuts an O.L joins: a cross,
/// as the conte draws an O.L across the line between two cut panels.
///
/// ⚠️Mine: 「컷이름사이에 ol처럼 보이는 특수문자 넣으면 좋고」 (I-93-Q1) —
/// `×`, which both of the app's typefaces carry, so the sheet and its PDF
/// print the same glyph.
const conteTransitionCross = '×';

/// A TRANSITION as its cut's ACTION column writes it: the cuts it joins,
/// crossed ([conteTransitionCross]), what it says ([InstructionEvent
/// .displayLabel] — the O.L's word, or a fade's term in the glossary
/// [defById] reads) and how long it lasts, whole — `c1 × c2 カットO.L (1+0)`.
/// A fade joins no cuts: `FO (0+12)`.
///
/// 🗣️I-93-Q1 (유저 2026-10-30): 「앞 컷에만, 전체 길이로」 + 「대상도
/// 적어주는거 잊지말고. c1 c2 カットO.L (1+0) 이런식」. [event] is the one
/// its row names by its cuts (`transitionRowNamedByItsCuts`), as the sheet
/// prints it.
String conteTransitionLine(
  InstructionEvent event, {
  required CameraInstructionDef? Function(String id) defById,
  required int framesPerSecond,
}) {
  final ends = [
    for (final end in [event.valueA, event.valueB])
      if (end != null && end.isNotEmpty) end,
  ];
  final word = event.displayLabel(event.defIn(defById));
  final length = secondsPlusFramesLabel(event.length, framesPerSecond);
  return [
    if (ends.isNotEmpty) ends.join(' $conteTransitionCross '),
    '$word ($length)',
  ].join(' ');
}
