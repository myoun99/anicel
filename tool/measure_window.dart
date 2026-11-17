// THE MACHINE'S MEASUREMENT WINDOW. While it is open, nothing new starts
// on this machine: no `flutter test` in its line (test_queue.dart,
// [Turn.take]), no cargo in a shared target (tool/cargo_turn.sh) and no
// land's gates (tool/lane.sh, room_first). Whatever already runs runs to
// its end. It closes when it is closed, or by itself at the deadline it
// was opened with.
//
//   bash tool/run.sh test_queue --window <minutes> <who…>   open it
//   bash tool/run.sh test_queue --window close              close it
//   bash tool/run.sh test_queue --window                    is it open?
//
// 🗣️WHY (card a-quiet-window-drains-in-minutes, 관제 2026-11-17 on 유저
// 「정한것들 좋고 그런 효율적으로 하는방식 좋아. 할수있는거 최대한하자」): a
// window was a message to each session, 「새 실행 금지」, and then a wait for
// every lane's run to end whole — an affected run, a land's gates, a crate
// gate. The brush's window that day took 84 minutes to fall quiet (17:58
// to 19:22) for a measurement of a few minutes, and held the landing chain
// all the while. But a run's tests already pass through the line, and the
// line decides again at every batch: standing there, a window falls quiet
// within one batch.
//
// ⏰A DEADLINE, ALWAYS (a measuring chain has one — 11-02): a window its
// opener forgets would stop the machine for good. Past its deadline it is
// closed, whether or not its file is still there.
//
// ⚠️WHAT IT CANNOT STOP, to be written down with the measurement rather
// than waited for: what runs outside the line — what the user starts (the
// IDE's `flutter run`, Android Studio), a session's build — and the
// engine's build hook (cargo_turn.sh --hold), which builds inside a
// `flutter` command already under way: a batch that runs has to be able
// to end.
//
// ⚠️TWO READERS, NOT THREE: tool/measure_window.sh reads the same file for
// the shell, and says the same words.
import 'dart:io';

/// The window's file in the machine's line folder (`queueFolder`): its
/// deadline in whole seconds since the epoch, a tab, and who opened it.
const kWindowFile = 'window';

/// An open window: who opened it, and when it closes by itself.
typedef MeasureWindow = ({String who, DateTime until});

/// The window open on the line at [line] at [now], or null when there is
/// none — no file, one that cannot be read, or one past its deadline.
MeasureWindow? openWindow(Directory line, {DateTime? now}) {
  final String text;
  try {
    text = File('${line.path}/$kWindowFile').readAsStringSync();
  } on FileSystemException {
    return null;
  }
  final tab = text.indexOf('\t');
  final seconds = tab < 0 ? null : int.tryParse(text.substring(0, tab));
  if (seconds == null) return null;
  final until = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  if (!(now ?? DateTime.now()).isBefore(until)) return null;
  return (who: text.substring(tab + 1).trim(), until: until);
}

/// What a run that waits for [window] says — the shell's words as well
/// (tool/measure_window.sh, `window_words`).
String waitingFor(MeasureWindow window) =>
    '기다리는 중 — 측정 창(${window.who} · ${_clock(window.until)}까지)';

/// Opens the window on [line] for [lasting] from [now], as [who]'s.
MeasureWindow openTheWindow(
  Directory line, {
  required String who,
  required Duration lasting,
  DateTime? now,
}) {
  final seconds =
      (now ?? DateTime.now()).add(lasting).millisecondsSinceEpoch ~/ 1000;
  final named = who.replaceAll(RegExp(r'\s+'), ' ').trim();
  line.createSync(recursive: true);
  // Written whole and then put in place: a reader never reads half of it.
  File('${line.path}/$kWindowFile.$pid.part')
    ..writeAsStringSync('$seconds\t$named\n')
    ..renameSync('${line.path}/$kWindowFile');
  return (
    who: named,
    until: DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
  );
}

/// Closes the window on [line], open or not.
void closeTheWindow(Directory line) {
  try {
    File('${line.path}/$kWindowFile').deleteSync();
  } on FileSystemException {
    // No window was open.
  }
}

/// `test_queue --window …` ([args] after the flag) on the line at [line]:
/// its exit code. [describe] says what runs in the line as the window
/// opens, for its opener to watch fall quiet.
int windowCommand(
  Directory? line,
  List<String> args, {
  required List<String> Function(Directory line) describe,
  void Function(String) say = print,
}) {
  if (line == null) {
    say('(this machine names no folder for the line)');
    return 2;
  }
  if (args.isEmpty) {
    final open = openWindow(line);
    say(open == null
        ? 'test_queue: no measurement window is open'
        : windowIsOpen(open));
    return 0;
  }
  if (args.length == 1 && args.first == 'close') {
    closeTheWindow(line);
    say('test_queue: the measurement window is closed');
    return 0;
  }
  final minutes = int.tryParse(args.first);
  final who = args.skip(1).join(' ').trim();
  if (minutes == null || minutes <= 0 || who.isEmpty) {
    say('usage: bash tool/run.sh test_queue --window <minutes> <who…> | '
        '--window close | --window');
    return 2;
  }
  final open = openTheWindow(
    line,
    who: who,
    lasting: Duration(minutes: minutes),
  );
  say('test_queue: the measurement window is open till ${_clock(open.until)} '
      '(${open.who}) — what runs runs to its end, and nothing new starts. '
      'In the line now:');
  describe(line).forEach(say);
  return 0;
}

/// What `--list` and `--window` say of [window], open.
String windowIsOpen(MeasureWindow window) =>
    'test_queue: the measurement window is open — ${window.who}, till '
    '${_clock(window.until)}; nothing new starts';

String _clock(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:'
    '${at.minute.toString().padLeft(2, '0')}';
