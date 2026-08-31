// The board's own gate. Prints one complaint per problem and nothing at all
// when the file is clean; `board_gate.sh` blocks the turn on any output.
//
// Compiled to an exe by `board_up.sh` beside `board_server.exe` — a `dart run`
// here costs 1.8s of JIT on EVERY turn, which is what retired the last
// gate-side dart check. An exe starts in tens of milliseconds.
//
// 🚨★★★IT JUDGES THE BOARD BY THE BOARD'S OWN MODEL. Every question about
// where a card sits is asked through `board_model.dart`, the same file the
// server renders from. ⛔It may never answer 「어느 칸인가」 for itself: a
// gate with its own copy of the rules is a second reader of the one question
// this redesign existed to unify, sitting inside the thing that is supposed
// to catch second readers.
import 'dart:convert';
import 'dart:io';

import 'board_model.dart';

/// Matches a PR named in prose — 「#1302」, 「PR #1302」 — which the board
/// cannot file by. Four digits only: three-digit issue numbers and 「#1」
/// style round tags are not PRs.
final _prInProse = RegExp(r'#\d{4}\b');

/// Words that describe a CHECK rather than work. Used on `rest` only.
final _checkWords = RegExp('실기|재확인|확인한다|확인해|검증|눌러 ?본|봐야');

/// When `<원본id>-Q<번호>` became the way to name a question. Questions
/// raised before it are not defects.
const _questionNamingSince = '2026-08-27';

/// How long a card may sit waiting for me before it is not triage any more.
const _staleAfter = Duration(hours: 24);

/// The gate's whole judgement, as a STRING rather than as stdout.
///
/// 🚨★★★EXTRACTED SO THE TEST CAN STOP SPAWNING PROCESSES. The suite used to
/// run `dart run tool/board_check.dart` once per case; under the full
/// affected run the process contention alone made it fail — 실측 2026-08-27:
/// **nine red in a bulk run, 13/13 green alone**. A gate that goes red for
/// reasons that have nothing to do with the board is a gate people learn to
/// re-run instead of read.
/// 🚨★★★BOTH CUTOFFS ARE ARGUMENTS, because a test that compares its fixtures
/// against a hardcoded date is a test that depends on what day the machine
/// thinks it is. 🧪CI proved it: green here, red on a Windows shard, and
/// nothing about the board had changed — only the clock.
///
/// [since] is when the MODEL changed (a card written before it was correct
/// under the rules it was written for). [linesSince] is when the two LINE
/// rules landed — 「state 를 손으로 쓰지 말라」와 「미래 시각을 쓰지 말라」 —
/// which is later, because lines cannot be fixed by appending.
///
/// ⚠️`now` too: the future-stamp check needs one, and taking it from the
/// clock inside a test makes the fixture's meaning depend on when it runs.
String boardCheckComplaints(
  File file, {
  String since = kGateSince,
  String linesSince = kLinesSince,
  DateTime? now,
}) {
  final cards = readBoard(file, now: now);
  final acks = _acks(file);
  final complaints = <String>[
    ..._brokenLines(),
    ..._wordsNobodyReads(acks),
    ..._pointersToNothing(cards, acks),
    ..._stampsTheFileContradicts(file, cards, acks),
    ..._cardsOffTheBoard(cards, acks, since),
    ..._sectionsTheStoryCannotName(file, acks, since, now, linesSince),
    ..._workThatShipped(cards, acks, since),
    ..._questionsNobodyCanAnswer(cards, acks, since),
    ..._answersNobodyRead(cards, acks, since),
    ..._deadAcks(cards, acks),
    ..._drawnNowhere(cards, acks),
  ];
  return complaints.join('\n');
}

/// 🚨★★★A GATE THAT CANNOT SAY 「나는 아무것도 안 읽었다」 IS WORSE THAN NO
/// GATE — it reports all-clear on a board it never opened.
///
/// ⛔It used to `return` on no arguments and on a missing file. Both look
/// exactly like 「문제 없음」 from the outside. 🧪2026-08-31: I ran
/// `board_check.exe --records <path>` — `args.first` was `--records`, which
/// is not a file, so it read nothing and exited 0. I believed it, and the
/// board had **five** complaints waiting, including two cards I had written
/// twenty minutes earlier.
///
/// ⚠️This is the same defect the checks below are about, committed by the
/// checker itself: an input it did not understand, silently dropped.
/// ⇒ It takes ONE positional path. Anything else is said out loud on stderr
/// and exits 2, which no amount of squinting reads as green.
///
/// 🚨EXIT CODES: 0 clear · 1 complaints (they are on stdout) · 2 could not
/// run. ⚠️`board_gate.sh` reads stdout and ignores the code, so 1 changes
/// nothing there — it is for every other caller, and for me.
/// Why this run cannot happen, or null if it can.
///
/// ⚠️SEPARATE FROM [main] so a test can see it. The old refusals were three
/// bare `return`s inside `main`, which is precisely why nothing caught them:
/// there was no value to assert on, and the only observable behaviour was
/// silence — the same silence a clean board produces.
String? boardCheckRefusal(List<String> args, {bool Function(String)? exists}) {
  final there = exists ?? (p) => File(p).existsSync();
  if (args.length != 1) {
    return 'board_check: 인자는 board.jsonl 경로 하나입니다 '
        '(${args.length}개 받음: ${args.join(' ')})\n'
        '⛔옵션은 없습니다. `--records <경로>` 로 부르면 `--records` 를 '
        '파일 이름으로 읽고 아무것도 검사하지 못합니다.';
  }
  if (args.first.startsWith('-')) {
    return 'board_check: 「${args.first}」 는 옵션처럼 보입니다 — 이 도구는 '
        '옵션을 받지 않습니다. 경로 하나만 주세요.';
  }
  if (!there(args.first)) {
    return 'board_check: 파일이 없습니다 — ${args.first}';
  }
  return null;
}

void main(List<String> args) {
  final refusal = boardCheckRefusal(args);
  if (refusal != null) {
    stderr.writeln(refusal);
    exit(2);
  }
  final out = boardCheckComplaints(File(args.first));
  if (out.isEmpty) return;
  stdout.write(out);
  exit(1);
}

// ─────────────────────────────────────────────────────── 1. 읽히지 않는 줄

/// A line the reader could not use. The renderer SKIPS one and carries on —
/// the right call for a board (30 items beat none) and the wrong one for a
/// gate, since a skipped item just quietly stops existing.
///
/// ⚠️Reads [badLines], which `readBoard` fills. That is deliberate: the gate
/// learns what could not be read from the same parse the screen used.
Iterable<String> _brokenLines() sync* {
  if (badLines.isEmpty) return;
  yield '${badLines.length}개 줄이 깨졌습니다 (줄 ${badLines.join(', ')})\n'
      '보드는 못 읽은 줄을 건너뛰고 나머지를 그립니다 — 그 항목은 화면에 '
      '아예 없습니다.';
}

// ──────────────────────────────── 1b. 적어 놓았는데 아무도 안 읽는 말

/// 🚨★★★A WORD THE WRITER HAD TO REMEMBER IS THE DEFECT THIS BOARD KEEPS
/// HAVING. Every one of them looked like this: the data was there, no reader
/// looked at it, and nothing anywhere said so.
///
/// 🧪The actual history, all of it this shape:
/// · `kind` forgotten on six questions ⇒ they drew as ordinary rows with the
///   question missing, on the board, in the right section, right title.
/// · a PR written into the note body instead of `pr` ⇒ 「카드 없음」.
/// · `item` + `ask` ⇒ the card does not appear at all.
/// · `state:"done"` ⇒ 77 cards fell into 착수 가능 (2026-08-30).
///
/// ⛔The old answer was to write the rule down somewhere and remember it.
/// That is not an answer — [kReadFields] is the set of keys any reader looks
/// at, so anything else in a record is **provably** unread, and saying so
/// costs one pass over keys already parsed.
///
/// ⚠️Baseline measured before shipping: the live 1839-line file reports ZERO.
/// That is why this needs no history cutoff, unlike the rules below it — a
/// complaint here is always about a line somebody just wrote.
Iterable<String> _wordsNobodyReads(Set<String> acks) sync* {
  final live =
      unreadFields.where((u) => !acks.contains(u.id)).toList(growable: false);
  if (live.isEmpty) return;
  final shown = live.take(12).map((u) => '${u.line}:${u.id}(${u.field})');
  final more = live.length > 12 ? ' … 외 ${live.length - 12}개' : '';
  yield '아무도 안 읽는 말이 적힌 줄: ${shown.join(', ')}$more\n'
      '보드는 아는 키만 읽습니다 — 모르는 키는 **조용히 버려집니다.** '
      '데이터는 파일에 있고 화면에는 없습니다.\n'
      '⇒ 읽는 키: ${kReadFields.join(' · ')}\n'
      '⇒ 읽는 kind: ${kKinds.join(' · ')}';
}

// ────────────────────────────────── 1c. 가리키는 곳이 없는 값

/// 🚨★★★A POINTER THAT POINTS AT NOTHING.
///
/// The same law as [_wordsNobodyReads], one level in: the key WAS read and
/// the value WAS used — and it resolved to nothing, silently. 🧪All four
/// measured on fixtures before this was written; every one produced a
/// plausible-looking board and no complaint at all.
///
/// · `ref` on a 확인 완료 that clears no check ⇒ the tick button stays on
///   screen and the card never leaves 실기 확인. (I shipped a one-line
///   version of this on 2026-08-31 and had to probe `waiting=1` to see it.)
/// · `of` — or a `<원본>-Q<번호>` name — whose origin is not in the file ⇒
///   the question stands alone and the answer has nowhere to go back to.
///   ⚠️Standing alone is CORRECT for a question that names no origin at all;
///   the defect is naming one that does not exist.
/// · a `law`'s `tag` that no card carries ⇒ 「손대기 전에」 is written and
///   appears on nothing, while the law itself sits in 착수 가능 as work.
/// ⛔NOT `answer`, though it looks like the fourth of these and I wrote it
/// that way first. 🧪The live file produced 25 hits and every one of them was
/// correct: the panel renders a radio with `value="other"` for a free answer,
/// and `_askPanel` falls back to `{'label': d.answer}` ON PURPOSE so an
/// answer naming no option still shows. An answer is the USER's word, not a
/// key I get to constrain. **The baseline is what caught it** — the check was
/// written, plausible, and would have complained about 25 correct records.
///
/// ⚠️Baseline measured on the live file before shipping, exactly as for
/// [_wordsNobodyReads]. A complaint here is about a line somebody just wrote.
Iterable<String> _pointersToNothing(
  List<BoardCard> cards,
  Set<String> acks,
) sync* {
  final byId = {for (final c in cards) c.id: c};
  // ⚠️A law's own `tag` is not use — it is the thing being pointed WITH.
  final tagsInUse = <String>{
    for (final c in cards)
      if (c.kind != 'law') ...c.tags,
  };
  final dangling = <String>[];
  for (final c in cards) {
    if (acks.contains(c.id)) continue;
    final stamps = {for (final l in c.log) l.ts};
    for (final l in c.log) {
      if (l.ref.isEmpty || stamps.contains(l.ref)) continue;
      dangling.add('${c.id}: ref→${l.ref}');
    }
    if (cardAsks(c)) {
      final (of, _) = asksOf(c);
      if (of.isNotEmpty && !byId.containsKey(of)) {
        dangling.add('${c.id}: of→$of');
      }
    }
    if (c.kind == 'law' && c.tag.isNotEmpty && !tagsInUse.contains(c.tag)) {
      dangling.add('${c.id}: tag→${c.tag}');
    }
  }
  if (dangling.isEmpty) return;
  final shown = dangling.take(12).join(', ');
  final more =
      dangling.length > 12 ? ' … 외 ${dangling.length - 12}개' : '';
  yield '가리키는 곳이 없는 값: $shown$more\n'
      '키는 읽혔고 값도 쓰였는데 **가리킨 자리에 아무것도 없습니다** — '
      '화면은 멀쩡해 보이고 그 값만 아무 일도 안 합니다.\n'
      '⇒ ref = 지울 실기 확인 항목의 `ts` · of = 원본 카드 id · '
      'tag = 카드가 실제로 쓰는 태그';
}

// ────────────────────── 1d. 파일 순서가 부정하는 시각

/// 🚨★★★A LATER LINE WITH AN EARLIER STAMP. The file is append-only, so its
/// ORDER is a fact — and a `ts` that disagrees with it is a lie the clock
/// cannot expose.
///
/// ⛔THE FUTURE-STAMP RULE GOES BLIND. It asks 「is this later than now」, so
/// a stamp of 14:10 written at 01:36 is caught for eight hours and then
/// becomes ordinary history. 🧪Exactly what happened: I stamped `C-t11` and
/// `C-t12` 실기 확인 at 14:10 while the clock read 01:36; 유저 ticked them
/// 완료 at 01:34 and 01:39; their real completions sorted BEFORE my invented
/// stamp, so the last 대분류 stayed 실기 확인 and the cards would not leave
/// the board. 유저 found them today and asked why 「내용은 완료인 상태인데
/// 왜 실기확인으로 옮긴건지」. The future check had long since stopped
/// looking.
///
/// ⚠️This one never stops looking, because it reads no clock at all: it
/// compares the card's last 대분류 BY FILE ORDER against its last 대분류 BY
/// STAMP. Those are the same question asked two ways, and the board answers
/// with the second.
///
/// ⛔Only cards that are still DRAWN. A finished card is off the board
/// whichever way it is read, and complaining about history is how a gate
/// stops being read.
Iterable<String> _stampsTheFileContradicts(
  File file,
  List<BoardCard> cards,
  Set<String> acks,
) sync* {
  final byId = {for (final c in cards) c.id: c};
  final byFile = <String, String>{};
  final stamped = <String, List<List<String>>>{};
  for (final line in file.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty) continue;
    Map<String, dynamic> json;
    try {
      json = jsonDecode(t) as Map<String, dynamic>;
    } catch (_) {
      continue;
    }
    final id = '${json['id'] ?? ''}';
    final at = '${json['at'] ?? ''}'.trim();
    if (id.isEmpty || at.isEmpty || !kSection.containsKey(at)) continue;
    byFile[id] = at;
    (stamped[id] ??= []).add(['${json['ts'] ?? ''}', at]);
  }
  final wrong = <String>[];
  for (final e in stamped.entries) {
    if (acks.contains(e.key)) continue;
    final c = byId[e.key];
    if (c == null || !_live(c) || c.foldedInto != null) continue;
    final sorted = [...e.value]..sort((x, y) => x[0].compareTo(y[0]));
    final byStamp = sorted.last[1];
    if (byStamp == byFile[e.key]) continue;
    wrong.add('${e.key}(파일은 「${byFile[e.key]}」, 시각으로는 「$byStamp」)');
  }
  if (wrong.isEmpty) return;
  yield '적힌 순서와 시각이 다른 카드: ${wrong.join(', ')}\n'
      '파일은 추가 전용이라 **줄 순서가 곧 사실**입니다 — 시각이 그것과 '
      '다르면 그 카드는 화면에서 엉뚱한 칸에 앉습니다.\n'
      '🧪C-t11·C-t12 가 그랬습니다: 제가 14:10 을 지어냈고 유저는 01:34 에 '
      '완료를 눌렀는데, 완료가 앞으로 정렬돼 **카드가 안 사라졌습니다.**\n'
      '⇒ 그 줄의 `ts` 를 이웃 줄 사이의 값으로 고치세요. '
      '⛔그리고 앞으로는 `dart run tool/board_say.dart` 로 적으세요 — '
      '`ts` 를 직접 쓰지 않으면 이 일이 아예 안 생깁니다.';
}

// ─────────────────────────────────────── 2. 어느 칸에도 못 서는 카드

/// 🚨★★★A CARD WHOSE STORY NAMES NO SECTION.
///
/// ⛔THE OLD RULE ASKED SOMETHING ELSE ENTIRELY — `kind == item && answered
/// && state != inbox && !pr` — because sections came from a `state` field.
/// They come from the story now, so the way to fall off the board is to have
/// never written a 대분류 at all. Such a card lands in 바로 가능 by default
/// and claims to be startable work, whatever it actually is.
///
/// ⚠️A card with NO entries is not this: it is a bare `{"id":…,"pr":N}` and
/// [_workThatShipped] has a better complaint for it.
Iterable<String> _cardsOffTheBoard(
  List<BoardCard> cards,
  Set<String> acks,
  String since,
) sync* {
  final lost = <String>[];
  for (final c in cards) {
    if (!_live(c) || acks.contains(c.id)) continue;
    if (c.log.isEmpty || !_recent(c, since)) continue;
    if (lastSection(c).isNotEmpty) continue;
    lost.add(c.id);
  }
  if (lost.isEmpty) return;
  yield '어느 칸도 말하지 않는 카드: ${lost.join(', ')}\n'
      '카드의 칸은 **이야기의 마지막 대분류**가 정합니다 — 하나도 없으면 '
      '기본값인 「바로 가능」에 앉아 착수할 일인 척합니다.\n'
      '⇒ 한 줄 적으세요: {"id":…, "at":"<대분류>", "note":…}. '
      '대분류는 ${kSection.keys.take(8).join(' · ')} …';
}

// ─────────────────────────────── 3. 이야기가 이름을 모르는 칸 · state 손대기

/// 🚨★★★A STAGE NAME THE MODEL DOES NOT KNOW MOVES NOTHING.
///
/// ⛔The old rule watched `state` for this, and it was right for its time:
/// an invented state name silently filed the card under 「착수 가능」. The
/// hazard MOVED. `state` is computed now, so the way to file a card nowhere
/// is to invent an `at` — and it fails exactly as silently.
///
/// 🚨AND `state` WRITTEN BY HAND IS ITSELF THE DEFECT NOW. It is folded out
/// of the story; a line that sets it is either dead weight or a second
/// answer to a question the story already answered. ⚠️Two survive, because
/// they are ENDINGS rather than sections and no stage word produces them:
/// `archived` and `deleted`.
///
/// ⚠️Judged LINE BY LINE, not on the merged card: the file is append-only,
/// so the offending word is in a line, and naming the line is what lets it be
/// found. ⛔But only lines written since this rule existed — a gate that
/// complains about corrected history forever is a gate nobody reads.
Iterable<String> _sectionsTheStoryCannotName(
  File file,
  Set<String> acks,
  String since,
  DateTime? now,
  String linesSince,
) sync* {
  const knownEndings = {'archived', 'deleted'};
  final unknownStage = <String>[];
  final future = <String>[];
  final handWrittenState = <String>[];
  var n = 0;
  for (final line in file.readAsLinesSync()) {
    n++;
    final t = line.trim();
    if (t.isEmpty) continue;
    Map<String, dynamic> json;
    try {
      json = jsonDecode(t) as Map<String, dynamic>;
    } catch (_) {
      continue;
    }
    if (json['kind'] == 'law' || json['kind'] == 'meta') continue;
    final id = '${json['id'] ?? ''}';
    if (acks.contains(id)) continue;
    // ⚠️ASKED BEFORE the history cutoff below: a stamp in the future is
    // wrong whenever it was written, and gating it would have hidden every
    // one made before the rule existed — including the 39 that caused it.
    // 🚨★★★A STAMP THAT HAS NOT HAPPENED YET.
    //
    // ⛔I wrote 39 of them on 2026-08-31 — clock times of 02·03·04·06·09·11·
    // 12·14시 while the actual clock read 01:36, plausible-looking numbers I
    // made up instead of reading. 유저 hit it mid-test: they ticked `C-t11`
    // at 01:34 and the card did not leave, because my 실기 확인 stamped 14:10
    // sorted AFTER their tick and stayed the last 대분류.
    //
    // `ts` is the story's ORDER now, not just a date on a panel. A stamp in
    // the future reorders somebody else's work around a time that never was.
    final when = DateTime.tryParse('${json['ts'] ?? ''}');
    final clock = now ?? DateTime.now();
    if (when != null &&
        when.isAfter(clock) &&
        '${json['ts']}'.compareTo(linesSince) >= 0) {
      future.add('$n:$id(${json['ts']})');
    }
    if ('${json['ts'] ?? ''}'.compareTo(linesSince) < 0) continue;
    final at = '${json['at'] ?? ''}'.trim();
    if (at.isNotEmpty && !kSection.containsKey(at) && !_kSubStage.contains(at)) {
      unknownStage.add('$n:$id($at)');
    }
    final state = '${json['state'] ?? ''}'.trim();
    if (state.isNotEmpty && !knownEndings.contains(state)) {
      handWrittenState.add('$n:$id($state)');
    }
  }
  if (unknownStage.isNotEmpty) {
    yield '모르는 항목 이름: ${unknownStage.join(', ')}\n'
        '보드는 아는 이름만 칸으로 읽습니다 — 모르는 이름은 칸을 바꾸지 '
        '못하고, 그 카드는 **조용히 「바로 가능」에 남습니다.**\n'
        '⇒ 대분류: ${kSection.keys.join(' · ')}\n'
        '⇒ 소분류: ${_kSubStage.join(' · ')}';
  }
  if (future.isNotEmpty) {
    yield '아직 오지 않은 시각이 찍힌 줄: ${future.join(', ')}\n'
        '`ts` 는 이제 **이야기의 순서**입니다 — 미래 시각은 남의 일을 자기 '
        '뒤로 밀어냅니다. 🧪08-31에 39줄을 그렇게 써서, 유저가 체크한 완료가 '
        '제가 지어낸 실기 확인보다 앞으로 정렬돼 **카드가 안 사라졌습니다.**\n'
        '⇒ 시계를 읽고 쓰세요. 지어내지 마세요.';
  }
  if (handWrittenState.isNotEmpty) {
    yield 'state 를 손으로 쓴 줄: ${handWrittenState.join(', ')}\n'
        '`state` 는 이제 **이야기에서 계산되는 값**입니다 — 손으로 쓰면 다음 '
        '줄에 덮이거나, 이야기와 다른 말을 하게 됩니다.\n'
        '⇒ 카드를 옮기려면 `at` 에 대분류를 적으세요. '
        '⚠️예외는 끝을 뜻하는 archived · deleted 둘뿐입니다.';
  }
}

/// Stage names that are entries but NOT sections. ⚠️Kept here rather than in
/// the model on purpose: the model needs to know which words MOVE a card,
/// and this is the gate's separate business — which words it recognises at
/// all. A name in neither list is a typo.
const _kSubStage = <String>{
  '작업 기록',
  '확인 완료',
  '코드 확인',
  'AI 판단',
  '구현',
  '정정',
  '유저 메모',
  '유저 피드백',
  '유저 대답',
  '유저 아이디어',
  '유저 지시',
  '유저 정정',
  '유저 결정',
  '임시 메모',
  '작업전 확인',
  '착지 후 점검',
  '검토 대기',
  '확인함',
  '확인할 것',
  '착수 근거',
  '확정',
};

/// When these rules started applying. ⛔Not retroactive: 1500 lines of
/// history were written under the old model and re-firing them all in one
/// turn is the wall this file's own doc warns about.
/// ⛔A CUTOFF THAT IS ITSELF IN THE FUTURE JUDGES NOTHING. The first value
/// here was 2026-08-31T12:00 — picked while I believed it was afternoon and
/// the clock read 01:36, so every new rule sat idle for ten hours and the
/// test fixtures had to be stamped TOMORROW to clear it. The overhaul landed
/// on the evening of 08-30; that is the honest line.
/// ⚠️The moment the model actually changed: PR 1398 merged 2026-08-30T12:48Z.
/// Anything older was written under a model where it was correct.
const kGateSince = '2026-08-30T21:48:00';

/// ⚠️A SECOND LINE, for the two rules that judge a LINE rather than a card.
///
/// 「state 를 손으로 쓰지 말라」와 「미래 시각을 쓰지 말라」는 **이 게이트가
/// 생기면서** 규칙이 됐다. 모델이 바뀐 시각(08-30 21:48)부터 재면, 그 사이에
/// 쓰인 줄들이 영영 불평으로 남는다 — 덧붙여서는 고칠 수 없는 줄들이라
/// 「고쳐라」가 아니라 「영원히 시끄럽다」가 된다. ⛔그것이 이 파일이
/// 스스로 경고하는 「아무도 안 읽는 게이트」다.
/// ⚠️AFTER THE LAST BOGUS STAMP I WROTE (14:10 today). Those lines cannot be
/// unwritten and cannot be fixed by appending, so judging them would be a
/// complaint that never clears — the 「아무도 안 읽는 게이트」 this file warns
/// about. The rules start where my mistakes stop.
const kLinesSince = '2026-08-31T15:00:00';


// ──────────────────────────────────────────── 4. 착지했는데 실기로 안 간 일

/// 🚨★★★A MERGE NO LONGER MOVES A CARD, SO NOTHING MOVES IT BUT ME.
///
/// 유저 확정 2026-08-31: 「머지는 PR마다 여러 번 되는데 실기 확인은 다르잖아
/// … 작업 완료되면 실기 확인만 대분류로서 존재하게」. That is the right
/// model and it opens a hole the old board did not have: a card can ship and
/// then sit in 바로 가능 for ever because I never wrote 실기 확인 on it.
///
/// ⚠️Only when nothing is still owed — a card with leftovers belongs where
/// the work is, which is exactly what `stillOwed` answers.
Iterable<String> _workThatShipped(
  List<BoardCard> cards,
  Set<String> acks,
  String since,
) sync* {
  final shipped = <String>[];
  final bare = <String>[];
  final prose = <String>[];
  // ⚠️LOCAL. It was a top-level list once and the test caught it in one run:
  // complaints from an earlier board leaked into the next, because a gate
  // called twice in one process kept adding to the same list.
  final restIsACheck = <String>[];
  for (final c in cards) {
    if (!_live(c) || acks.contains(c.id)) continue;
    if (c.prs.isNotEmpty && _recent(c, since)) {
      // ⚠️ONLY WHERE IT IS A LIE. A shipped card sitting in 바로 가능 or
      // 나중에 says 「이건 아직 할 일」 while the work already landed. One in
      // 분류 전 · 답할 것 · 대화 중 · 하는 중 is not lying — somebody is on
      // it, and the card says so. 🧪Without this it named ten cards I had
      // moved to 분류 전 minutes earlier, which is exactly where they belong.
      // ⚠️`c.state` IS the section — `placeByStory` already folded it out of
      // the story. Deriving it again from the stage word missed a card with
      // NO 대분류 at all, which defaults to 바로 가능 and is the loudest case.
      final idle = c.state == 'open' || c.state == 'queue';
      if (idle && !stillOwed(c)) {
        shipped.add(c.id);
      }
      if (!_saysSomething(c)) bare.add(c.id);
    } else if (_recent(c, since) &&
        c.log.any((l) =>
            !l.byUser && l.pr == null && _prInProse.hasMatch(l.text))) {
      // 🚨★★★THE STORY, NOT THE HEAD — the last piece of `board-one-stream`
      // (「note·said·title 은 아직 마지막값이 이기는 필드다 — 항목으로 접는
      // 것이 이 개편의 마지막 조각이다」).
      //
      // ⛔This read `c.note`, which is LAST-WINS, so a PR written into an
      // EARLIER note was invisible the moment any later line carried a note.
      // 🧪Measured before changing it: the same card, same prose, complained
      // when the PR line was last and went silent when one more note
      // followed it. That is not a gate, that is a coin toss on ordering.
      //
      // ⚠️`!l.byUser` keeps the meaning it always had: the complaint is 「내가
      // 본문에 적었다」, and the user quoting a number in their own feedback
      // is not that. `l.pr == null` says the same thing the branch already
      // says — an entry that CLAIMS its PR properly is the correct shape.
      prose.add(c.id);
    }
    final rest = c.rest.trim();
    if (rest.isNotEmpty && _checkWords.hasMatch(rest)) restIsACheck.add(c.id);
  }
  if (shipped.isNotEmpty) {
    yield '착지했는데 실기 확인으로 안 올라온 카드: ${shipped.join(', ')}\n'
        '머지는 카드를 옮기지 않습니다 — 그게 이 모델의 요점입니다(머지는 '
        '사건이고 칸은 자리). 그래서 **내가 안 적으면 아무도 안 옮깁니다.**\n'
        '⇒ 한 줄: {"id":…, "at":"실기 확인", "note":"기기에서 무엇을 볼지"}';
  }
  if (bare.isNotEmpty) {
    yield '제목만 있고 내용이 없는 카드: ${bare.join(', ')}\n'
        'PR을 물었다는 것과 그 PR에 대해 뭐라도 말했다는 것은 다릅니다.\n'
        '⇒ 최소한 하나: how(이렇게 본다) · note(무엇을 왜 바꿨나) · '
        'think(판단) · said(유저 원문)';
  }
  if (prose.isNotEmpty) {
    yield 'PR을 본문에만 적은 카드: ${prose.join(', ')}\n'
        '⛔옛 이유(「pr 필드가 없으면 착수 가능에 남는다」)는 이제 무효입니다 — '
        '머지는 카드를 안 옮깁니다. **새 이유**: `구현` 항목에 PR이 안 붙으면 '
        '이야기에 링크가 없고, 「착지했는데 실기로 안 갔다」를 아예 못 봅니다.\n'
        '⚠️여러 장이면 줄마다 pr 하나로 나눠 적으세요.';
  }
  if (restIsACheck.isNotEmpty) {
    yield '「남은 것」에 확인 방법이 들어 있는 카드: ${restIsACheck.join(', ')}\n'
        '⛔옛 이유(「확인할 것에서 빠진다」)는 그 칸이 없어져 무효입니다. '
        '**새 이유**: `rest` 는 곧 「바로 가능」이라, 확인 방법을 거기 쓰면 '
        '실기 확인이 아니라 **바로 가능**에 앉습니다.\n'
        '⇒ 확인 방법은 `실기 확인` 항목이나 구현의 `how` 에 씁니다.';
  }
}


// ────────────────────────────────────────────── 5. 답할 수 없는 질문

/// A question a person is meant to answer must actually be answerable.
///
/// Added 2026-08-26 because the user could not answer three cards in a row:
/// 「지금 답할것 질문이 자세하게 안써있고 **대답칸도 없어서** 뭘 말하는 건지
/// 모르겠어. **계속 그러는데** … **규칙으로 강제해줘**」. The cause was
/// mechanical: the panel renders `where`, `why` and `options` and never
/// renders `note`, so a card written as one blob arrived as a bare title with
/// no way to answer.
///
/// 🆕AND THE OTHER HALF, which the overhaul opened: a question is an entry on
/// its card now, so an unanswered one must leave the card IN 답할 것. Answer
/// one of three and the card comes back to 분류 전 with two still open and
/// nothing saying so.
Iterable<String> _questionsNobodyCanAnswer(
  List<BoardCard> cards,
  Set<String> acks,
  String since,
) sync* {
  final unanswerable = <String>[];
  final thin = <String>[];
  final misdirected = <String>[];
  final orphan = <String>[];
  final byOrigin = <String, List<BoardCard>>{};
  for (final q in cards) {
    if (q.kind != 'decision') continue;
    final (of, _) = asksOf(q);
    if (of.isNotEmpty) (byOrigin[of] ??= []).add(q);
    if (!_notEnded(q) || acks.contains(q.id) || q.answer != null) continue;

    if (of.isEmpty && q.updated.compareTo(_questionNamingSince) >= 0) {
      orphan.add(q.id);
    }
    final options = q.options;
    if (options.length < 2) {
      unanswerable.add(q.id);
      continue;
    }
    final labelled = options.every((o) => '${o['label'] ?? ''}'.trim().isNotEmpty);
    if (q.where.trim().isEmpty || q.why.trim().isEmpty || !labelled) {
      thin.add(q.id);
    }
    final recommend = q.recommend?.trim() ?? '';
    if (recommend.isNotEmpty) {
      var index = 0;
      final keys = options.map((o) => '${o['key'] ?? ++index}').toSet();
      if (!keys.contains(recommend)) misdirected.add(q.id);
    }
  }

  // 🆕The card that owns an unanswered question must be IN 답할 것.
  final hidden = <String>[];
  for (final c in cards) {
    if (!_live(c) || acks.contains(c.id)) continue;
    final open = (byOrigin[c.id] ?? const <BoardCard>[])
        .where((q) => q.answer == null && _notEnded(q));
    if (open.isEmpty) continue;
    // ⚠️By SECTION, not by the word: 질문 and 답할 것 are two stage names for
    // one column, and comparing the word missed a card I had already moved.
    if (kSection[lastSection(c)] == 'ask') continue;
    hidden.add('${c.id}(${open.map((q) => q.id).join('·')})');
  }

  if (unanswerable.isNotEmpty) {
    yield '답할 수 없는 결정 카드: ${unanswerable.join(', ')}\n'
        '답변 라디오는 options 로 그려집니다 — 없으면 제목과 「다른 안」 칸만 '
        '뜹니다. 2개 이상 넣으세요.';
  }
  if (thin.isNotEmpty) {
    yield '내용이 안 보이는 결정 카드: ${thin.join(', ')}\n'
        'where(화면에서 뭔지) + why(왜 막혔나) + 각 option 의 label 이 '
        '필요합니다. ⛔note 는 이 패널에 안 그려집니다.';
  }
  if (misdirected.isNotEmpty) {
    yield '추천이 안 보이는 결정 카드: ${misdirected.join(', ')}\n'
        '`recommend` 는 **선택지의 키**를 적는 칸입니다 — 문장을 적으면 화면에 '
        '아무것도 안 나옵니다.';
  }
  if (orphan.isNotEmpty) {
    yield '어느 카드의 질문인지 모르는 결정: ${orphan.join(', ')}\n'
        '질문은 이제 **카드 안의 항목**입니다 — 이름이 `<원본id>-Q<번호>` 면 '
        '이름이 곧 연결이고, 아니면 `of` 로 원본을 적습니다. 없으면 그 질문은 '
        '자기 혼자 카드로 서고, 답이 돌아갈 카드가 없습니다.';
  }
  if (hidden.isNotEmpty) {
    yield '미답 질문이 있는데 답할 것에 없는 카드: ${hidden.join(', ')}\n'
        '질문 셋 중 하나만 답하면 카드는 분류 전으로 오고 **남은 둘은 조용해집니다.** '
        '아직 답을 기다린다면 그 카드의 마지막 대분류는 `질문` 이어야 합니다.\n'
        '⇒ {"id":…, "at":"질문", "note":"무엇이 아직 미답인지"} 또는 남은 질문을 '
        '다시 올리세요.';
  }
}

// ────────────────────────────────────────── 6. 유저 답을 안 읽고 넘어감

/// 🚨★★★AN ANSWER NOBODY READ IS THE SAME AS NO ANSWER.
///
/// 유저 2026-08-27: 「세션에서 대답 완료해서 작업끝났것이 답할것에 아직
/// 올라와있고 그런데 확인해줄래? **그런일 발생안하도록 작업흐름 개선하고
/// 싶고**」 — measured that day: TEN cards sat in 분류 전 with an answer on
/// them, and EIGHT more sat there unclassified.
///
/// 분류 전 means 「내가 읽고 분류한다」. A card that stays there is not
/// waiting for the user, it is waiting for ME.
///
/// ⚠️AGE, not presence: feedback arriving this turn belongs in 분류 전 and
/// blocking on it would make the section useless.
Iterable<String> _answersNobodyRead(
  List<BoardCard> cards,
  Set<String> acks,
  String since,
) sync* {
  final untriaged = <String>[];
  final waiting = <String>[];
  final now = DateTime.now();
  for (final c in cards) {
    if (!_live(c) || acks.contains(c.id)) continue;
    final section = lastSection(c);
    if (section != '유저' && section != '분류 전' && section != '질문') continue;
    final at = DateTime.tryParse(c.updated);
    if (at != null && now.difference(at) < _staleAfter) continue;
    (section == '질문' ? waiting : untriaged).add(c.id);
  }
  if (untriaged.isNotEmpty) {
    yield '분류 전에 하루 넘게 남은 카드: ${untriaged.join(', ')}\n'
        '분류 전은 「내가 읽고 분류한다」는 뜻입니다 — 그대로 두면 유저가 쓴 '
        '것을 아무도 안 읽은 것이 됩니다.\n'
        '⇒ 읽고 한 줄 적어 옮기세요: {"id":…, "at":"<대분류>", "note":…}';
  }
  if (waiting.isNotEmpty) {
    yield '하루 넘게 답을 기다리는 질문: ${waiting.join(', ')}\n'
        '이 대화에서 이미 답이 나오지 않았는지 확인하세요 — 채팅으로 온 답은 '
        '보드가 모릅니다. 아직 진짜로 열려 있으면 그 id 를 .gate-ack 에 '
        '한 줄로 적으세요.';
  }
}

// ──────────────────────────── 8. 끝난 것도 아닌데 어디에도 안 그려지는 카드

/// 🚨★★★EVERY CARD IS IN EXACTLY ONE PLACE: a column, an ending, or inside
/// another card. Anything else is a hole, and a hole looks EXACTLY like a
/// finish from the outside.
///
/// 유저 2026-08-31: 「**끝난 것을 등장 안 한다고 오해 안 하도록** 잘 구조적으로
/// 해 줄 수 있나」 — after ten hands-on checks vanished by riding an archived
/// host into the void. From the screen there was no way to tell those from
/// the seventeen that had genuinely been ticked.
///
/// ⇒ The invariant is stated here instead of being eyeballed: take every
/// card, drop the ones that ENDED and the ones FOLDED into another, and every
/// survivor must land in a column the board draws. One that does not is named
/// — and 「사라졌다」 stops being ambiguous, because a finish is now the only
/// silent way to leave.
Iterable<String> _drawnNowhere(List<BoardCard> cards, Set<String> acks) sync* {
  final byId = {for (final c in cards) c.id: c};
  final lost = <String>[];
  for (final c in cards) {
    if (c.kind == 'law' || c.kind == 'meta') continue;
    if (acks.contains(c.id)) continue;
    // Two of the three legitimate ways to be off the board.
    if (c.state == 'archived' || c.state == 'deleted') continue;
    final host = c.foldedInto;
    if (host == null) continue;
    // The third: 「접힘」 means 「drawn INSIDE that card」. If that card is not
    // drawn, the sentence is false and this one is nowhere at all.
    final into = byId[host];
    final shown = into != null &&
        into.state != 'archived' &&
        into.state != 'deleted' &&
        into.foldedInto == null;
    if (!shown) lost.add('${c.id}→$host');
  }
  if (lost.isEmpty) return;
  yield '끝나지도 않았는데 어느 칸에도 안 그려지는 카드: ${lost.join(', ')}\n'
      '카드가 있을 수 있는 자리는 셋뿐입니다 — **칸 하나 · 끝(완료·삭제) · '
      '다른 카드 안(접힘)**. 접혔는데 그 카드가 안 그려지면 셋 중 어디에도 '
      '없는 것이고, 화면에서는 **끝난 것과 똑같이 보입니다.**\n'
      '⇒ 호스트가 끝났으면 접지 말고 자기 카드로 세우세요.';
}

// ────────────────────────────────────────────────────── 7. 죽은 ack

/// 🚨★★★AN ACK THAT SILENCES NOTHING IS A LINE TO DELETE.
///
/// `.gate-ack` is where 「this landing goes past without a card」 is written
/// down. The moment a card DOES carry that PR the sentence stops being true,
/// and the line becomes one more bare number nobody can account for — which
/// is how seventeen of thirty-four got there by 2026-08-29.
///
/// ⛔It NAMES the line rather than dropping it: the file is the user's record
/// of decisions, and a gate that edits it would be deciding on their behalf.
///
/// ⚠️Every card, whatever its section. A landing whose card was archived
/// still HAS a card — that is the point of archiving it.
Iterable<String> _deadAcks(List<BoardCard> cards, Set<String> acks) sync* {
  final claimed = <int>{for (final c in cards) ...c.prs};
  final settled = <String>[];
  for (final key in acks) {
    final pr = int.tryParse(key);
    if (pr != null && claimed.contains(pr)) settled.add(key);
  }
  if (settled.isEmpty) return;
  yield '카드가 생긴 착지의 ack: ${settled.join(', ')}\n'
      'ack 는 「이 착지는 카드 없이 지나간다」는 뜻인데 그 PR을 든 카드가 이제 '
      '있습니다 — `.gate-ack` 에서 그 줄을 지우세요.';
}
/// Drawn on the board as a card at all.
///
/// ⚠️Three ways to not be one: an ENDING (`archived` · `deleted`), a record
/// folded INTO another card — reachable through the entry that holds it, and
/// asking 「어느 칸이냐」 of it asks about something that no longer has one —
/// and a `law`, which is not work and never appears as a card.
bool _live(BoardCard c) =>
    c.kind != 'law' &&
    c.kind != 'meta' &&
    c.state != 'archived' &&
    c.state != 'deleted' &&
    c.foldedInto == null;

/// 🚨★★★JUDGED ONLY SINCE THE RULE EXISTED.
///
/// ⛔Without this the two checks the overhaul ADDED fired on the whole file:
/// 30 cards with no 대분류 and 18 that shipped without reaching 실기 확인 —
/// and every one of them was CORRECT under the model it was written for.
/// Before the overhaul a card with no `at` and `state: open` really was
/// startable work, and a merge really did move a card by itself.
///
/// A gate that opens with thirty complaints about history is the gate this
/// file's own doc warns about: one people learn to scroll past. The backlog
/// is a card on the board, which is where a list of work belongs; this is a
/// gate, and a gate watches what happens next.
bool _recent(BoardCard c, String since) => c.updated.compareTo(since) >= 0;

/// Not an ENDING. ⚠️Weaker than [_live] on purpose: a question folded into
/// another card is still a question, and whether it can be ANSWERED has
/// nothing to do with where it is drawn. Using [_live] here skipped every
/// folded question, which the test caught in one run.
bool _notEnded(BoardCard c) => c.state != 'archived' && c.state != 'deleted';

/// Whether the card ever said anything beyond its title.
///
/// ⚠️A bare move entry does not count. `readBoard` writes 「실기 확인으로
/// 옮김」 for a line that names a section and says nothing else — that is the
/// board narrating the move, not me describing the work, and counting it let
/// a card claim a PR and say nothing while passing.
bool _saysSomething(BoardCard c) => c.log.any((l) {
      final t = l.text.trim();
      return t.isNotEmpty && t != 'PR #${l.pr}' && !t.endsWith(' 옮김');
    });

/// 🚨ONE ack file, EVERY complaint. It used to exempt only the checks added
/// last, so acking a card the gate named did nothing and the same line came
/// back every turn — an ack that does not silence is worse than none.
///
/// ⚠️What it means is 「I have decided to leave this card alone」, and that
/// decision is the same decision whichever complaint prompted it.
///
/// 🚨AN ACK CARRIES ITS REASON. A bare number is indistinguishable from every
/// other bare number, and by 2026-08-29 thirty-four had piled up. ⛔Bare
/// lines still silence: rejecting them outright would have re-fired
/// thirty-four complaints in one turn.
Set<String> _acks(File records) {
  final file = File('${records.parent.path}/.gate-ack');
  if (!file.existsSync()) return const {};
  final out = <String>{};
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final gap = line.indexOf(RegExp(r'\s'));
    out.add(gap < 0 ? line : line.substring(0, gap));
  }
  return out;
}
