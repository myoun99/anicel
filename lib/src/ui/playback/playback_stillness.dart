import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

/// Whether a run is moving the playhead — what a bar or a rail's row holds
/// still for.
///
/// 🗣️F-587 (유저 2026-11-13): 「타임라인 버튼들, 프레임알약이나 그런거 전부.
/// 재생할때 프레임 상태에 따라 갱신되서 바뀌는데 그냥 구조 변경. **재생중에는
/// 바꾸지않고 재생전 마지막 상태 유지**하도록. 왜냐하면 재생중 어차피
/// 쓸데없는데 매번바꾸니 조금이라도 가볍게 하기위함이고, 재생중 깜빡이는게
/// 심해서 방해됨」
///
/// ★What answers for THE FRAME THE PLAYHEAD STANDS ON keeps the answer it
/// had when the run began, and is asked again as the run ends: the command
/// bars' groups and their shift pair, and on a lane's row the key buttons,
/// the value, a group's preview and its presses. Each hands [of] to the one
/// law they are all built again by ([SlicedListenableBuilder.stillWhile]) —
/// so the answer is not asked at all while the run plays, whichever way the
/// news reaches it (the cursor, a notify, a pass from above as a film
/// crosses into its next cut).
///
/// ⛔The run's own display never asks here: the playhead and its column,
/// the ruler's frame, the canvas, the meter. They are what is playing.
///
/// ⛔Nor does a plugin's ⚠ and the grey of its header's name: a warning,
/// lit the moment a plugin fails under the run. 🗣️유저 11-14 F-587-Q1:
/// 「전부 멈추되 ⚠ 만 재생 중에도 켠다」 — it turns only where a failure
/// does, so it hardly flickers. ↩️It was held with the rest when F-587
/// landed (the decision's 「전부 멈춘다」, recommended and not chosen).
///
/// No press is lost to a held answer. The first actuation while a run
/// plays stops it and does nothing else (T28-c, [PlaybackActuationGate]),
/// so a button that still shows the frame the run left is never pressed
/// for the frame it stands on.
///
/// ↩️「A bar cannot start re-deriving 24 times a second because the film is
/// playing」 was already the law, kept by the channel
/// (`EditorSessionManager.playheadMoved`, #10 2026-08-21): no run moved the
/// editing cursor. A run of the cut plays on the editing canvas since
/// F-296-Q6 (2026-10-09) and takes that cursor with it, frame by frame.
/// 🔬2026-11-13, sixteen frames of such a run: the bars' gates were asked
/// on all sixteen and their groups built again on five, a lane's value on
/// thirteen. The channel cannot keep the law now — the playhead it moves
/// IS the run's display — so the ones who answer keep it.
///
/// ⚠️PLAYING is the canvas's run alone, not every transport
/// ([PlaybackActuationGate]'s question): it is the one that moves the
/// playhead.
class PlaybackStillness extends InheritedWidget {
  const PlaybackStillness({
    super.key,
    required this.playing,
    required super.child,
  });

  final ValueListenable<bool> playing;

  /// Null when no scope is present — a bar or a row mounted bare in a
  /// focused widget test is never held still.
  static ValueListenable<bool>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlaybackStillness>()?.playing;

  @override
  bool updateShouldNotify(PlaybackStillness oldWidget) =>
      !identical(oldWidget.playing, playing);
}
