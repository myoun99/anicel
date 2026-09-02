// Append records to the board, stamped by the clock.
//
// 🚨★★★I DO NOT GET TO TYPE `ts`. That is the whole tool.
//
// ⛔A stamp I write by hand is a value I have to compute correctly every
// time, and the record of me doing it is: 39 invented stamps on 2026-08-31
// (02·03·04·06·09·11·12·14시 while the clock read 01:36), and twice more the
// same day AFTER the gate existed to catch it — I read the clock in one
// command and wrote a later time in the next. The gate caught both. A rule
// that has to be obeyed 41 times is not a rule, it is a missing mechanism.
//
// ⚠️`ts` is the STORY'S ORDER now, not a date on a panel. A stamp in the
// future reorders somebody else's work around a time that never was: 유저
// ticked `C-t11` at 01:34 and the card did not leave, because a 실기 확인 I
// stamped 14:10 sorted after their tick and stayed the last 대분류.
//
// Usage:
//   dart run tool/board_say.dart <board.jsonl> <lines.jsonl>
//
// Each line of <lines.jsonl> is one record WITHOUT `ts`. They are appended in
// order, each a millisecond after the last, so the story keeps the order they
// were written in.
//
// ⛔It refuses rather than writes: an unknown field, an unknown `kind`, a
// missing `id`, or a `ts` of your own. Refusing costs one message; a bad line
// in an append-only file cannot be taken back.
import 'dart:convert';
import 'dart:io';

import 'board_model.dart';

/// Why this run cannot happen, or null if it can.
///
/// ⚠️SEPARATE FROM [main] so a test can see it — the same reason
/// `boardCheckRefusal` is a function. A refusal that only exists as an early
/// `return` is a refusal no test can assert on.
String? boardSayRefusal(List<String> args, {bool Function(String)? exists}) {
  final there = exists ?? (p) => File(p).existsSync();
  if (args.length != 2) {
    return 'board_say: 인자는 두 개입니다 — <board.jsonl> <lines.jsonl> '
        '(${args.length}개 받음: ${args.join(' ')})';
  }
  for (final p in args) {
    if (!there(p)) return 'board_say: 파일이 없습니다 — $p';
  }
  return null;
}

/// What is wrong with one record, or null if it can be appended.
///
/// ⚠️Reads [kReadFields] and [kKinds] — the same sets the board itself reads
/// by, so this cannot drift into accepting something the board would drop.
String? recordRefusal(Map<String, dynamic> json, int lineNo) {
  final kind = '${json['kind'] ?? ''}';
  if (json.containsKey('ts')) {
    return '$lineNo번째 줄: `ts` 를 직접 쓰지 마세요 — 이 도구가 시계를 '
        '읽어서 찍습니다. 지어낸 시각이 이야기의 순서를 망가뜨립니다.';
  }
  if (kind != 'meta' && '${json['id'] ?? ''}'.trim().isEmpty) {
    return '$lineNo번째 줄: `id` 가 없습니다 — 보드는 id 없는 줄을 '
        '건너뜁니다(meta 는 예외).';
  }
  if (kind.isNotEmpty && !kKinds.contains(kind)) {
    return '$lineNo번째 줄: 모르는 kind 「$kind」 — 아는 것: '
        '${kKinds.join(' · ')}';
  }
  // ⛔meta carries whatever its note needs and is not read by this file
  // alone — `board_gate.sh` greps `landedSince` straight out of it.
  if (kind == 'meta') return null;
  for (final k in json.keys) {
    if (kReadFields.contains(k)) continue;
    return '$lineNo번째 줄: 「$k」 는 아무도 안 읽습니다 — 읽는 키: '
        '${kReadFields.join(' · ')}';
  }
  return null;
}

/// What is wrong with writing this record onto a card that ALREADY EXISTS,
/// or null if there is nothing wrong.
///
/// 🚨★★★A CARD THAT HAS ENDED DOES NOT TAKE A NEW SUBJECT.
///
/// ⛔I did this twice in one hour on 2026-09-01, and both times the words
/// landed somewhere nobody could see:
/// · `board-exe-goes-stale` had finished at 03:20 and carried an explicit
///   `state:"archived"`, which the story cannot overturn. Three lines about
///   #1434 went onto an invisible card.
/// · `memory-usage-panel-Q1` was a question from 08-28 that 유저 HAD ALREADY
///   ANSWERED. My new question merged onto an answered card, so it never
///   reached 답할 것 — 유저 found it: 「메모리는 질문으로 안올라와있어」.
///   ⚠️And the answer had been there all along, so the question was never
///   needed.
///
/// ⚠️AMENDING an ended card is legitimate — a correction, a pointer to where
/// the subject moved. That is what `정정` is for, and saying it is the whole
/// difference between 「I know this card is finished」 and 「I did not look」.
/// ⛔So this is not an escape hatch bolted on: it is the one word that makes
/// the intent explicit, and the refusal names it.
String? endedCardRefusal(
  Map<String, dynamic> json,
  int lineNo,
  Map<String, String> endedWhy,
) {
  final id = '${json['id'] ?? ''}';
  final why = endedWhy[id];
  if (why == null) return null;
  final at = '${json['at'] ?? ''}'.trim();
  if (at == '정정') return null;
  return '$lineNo번째 줄: 「$id」 는 이미 끝난 카드입니다 ($why).\n'
      '  거기 적은 말은 화면에 안 뜹니다 — 끝난 카드는 보드가 안 그립니다.\n'
      '  ⇒ 새 주제면 **새 id** 를 쓰세요. 정말 이 카드를 고치는 것이면 '
      '`"at":"정정"` 을 붙이세요.';
}

/// Which cards have ended, and why — read once, in [main], from the board.
///
/// ⚠️A question that already carries an ANSWER counts as ended too. It is not
/// archived by state, but writing a NEW question onto it is the same mistake:
/// the panel shows the old answer and the new words never become a question.
Map<String, String> endedCards(List<BoardCard> cards) => {
      for (final c in cards)
        if (c.state == 'archived')
          c.id: '완료'
        else if (c.state == 'deleted')
          c.id: '삭제됨'
        // 🚨★★★A QUESTION, not merely a card carrying an `answer`.
        // ⛔`R27-rest` is an ordinary work card whose old `/submit` left
        // `answer:"ok"` on it, and the first version of this guard read that
        // as 「answered question」 and refused to let me record findings on
        // live work. Measured within the hour of shipping it.
        // ⚠️`cardAsks` is the same reader the board draws by, so this cannot
        // drift into a second opinion about what a question is.
        else if (cardAsks(c) && c.answer != null)
          c.id: '이미 답이 나온 질문',
    };

/// The bytes to append, or the reason there are none — NEVER both.
///
/// 🚨★★★THE SHAPE IS THE INVARIANT. 「a bad line writes nothing」 is not a
/// rule anyone has to follow here: a refusal hands back no bytes, so the
/// caller has nothing to write even if it wanted to. ⛔The alternative — write
/// as you go and stop on the first bad line — leaves half an append in a file
/// that cannot take it back.
///
/// ⚠️`now` is an argument so a test can pin it. The CLOCK is read once, in
/// [main], and nowhere else.
({String? refusal, String? bytes}) boardSayAppend(
  List<String> lines,
  DateTime now, {
  Map<String, String> ended = const {},
}) {
  final records = <Map<String, dynamic>>[];
  var lineNo = 0;
  for (final raw in lines) {
    lineNo++;
    final t = raw.trim();
    if (t.isEmpty) continue;
    Map<String, dynamic> json;
    try {
      json = jsonDecode(t) as Map<String, dynamic>;
    } on Object catch (e) {
      return (refusal: '$lineNo번째 줄이 JSON 이 아닙니다 — $e', bytes: null);
    }
    final why = recordRefusal(json, lineNo) ??
        endedCardRefusal(json, lineNo, ended);
    if (why != null) return (refusal: why, bytes: null);
    records.add(json);
  }
  if (records.isEmpty) return (refusal: '적을 줄이 없습니다.', bytes: null);

  // Each record a millisecond after the last, so the story keeps the order
  // they were written in and no two collide.
  final out = StringBuffer();
  for (var i = 0; i < records.length; i++) {
    final r = records[i];
    r['ts'] = now.add(Duration(milliseconds: i)).toIso8601String();
    out.writeln(jsonEncode(r));
  }
  return (refusal: null, bytes: out.toString());
}

void main(List<String> args) {
  final refusal = boardSayRefusal(args);
  if (refusal != null) {
    stderr.writeln(refusal);
    exit(2);
  }
  // 🚨THE CLOCK, ONCE, HERE — the only place this program asks what time it
  // is, and the only place it was ever possible to get wrong.
  final now = DateTime.now();
  final result = boardSayAppend(
    File(args[1]).readAsLinesSync(),
    now,
    ended: endedCards(readBoard(File(args[0]))),
  );
  if (result.refusal != null) {
    stderr.writeln('board_say: ${result.refusal}');
    exit(2);
  }
  File(args[0]).writeAsStringSync(result.bytes!, mode: FileMode.append);
  final n = '\n'.allMatches(result.bytes!).length;
  stdout.writeln('board_say: $n줄 추가 (${now.toIso8601String()})');
}
