import 'dart:async';

/// The screen's turn between two stretches of work on the UI isolate:
/// whatever it has waiting — a frame to draw, a wait window's spinner its
/// next step, a press on Cancel — before the work takes the next stretch.
///
/// ⚠️A work whose stretches await nothing lets nothing else in: the
/// isolate goes from one to the next in the same turn, and the screen
/// stands still for the length of them all (F-304 · F-615).
///
/// ONE turn for every walk that takes the UI isolate a piece at a time —
/// a save's cels in RAM, an export's frames, a pixel verb's cels.
Future<void> theScreensTurn() => aScreensTurnToWithdraw().turn;

/// [theScreensTurn] that [withdraw] takes back — for a walk no one awaits,
/// which leaves nothing behind when it is let go of: the walk waiting on a
/// withdrawn turn never takes its next stretch.
({Future<void> turn, void Function() withdraw}) aScreensTurnToWithdraw() {
  final turn = Completer<void>();
  final timer = Timer(Duration.zero, turn.complete);
  return (turn: turn.future, withdraw: timer.cancel);
}
