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
  // 🚨A LAW IS ITS `care` AND NOTHING ELSE (law-notes-are-invisible, 실측
  // 2026-09-17). 「작업전 확인」 draws a law card's LAST `care` line and no
  // other field, so a law written as a `note` reached no screen at all —
  // timeline 8 lines, panel 7, structure 5, media 3 and rendering 1 were
  // found buried that way.
  if (kind == 'law' && json.containsKey('note')) {
    return '$lineNo번째 줄: 법 카드의 `note` 는 어디에도 안 나옵니다 — '
        '「작업전 확인」은 그 법 카드의 마지막 `care` 한 줄만 그립니다. 법은 '
        '`care` 에, 직전 `care` 전문에 덧붙인 누적본으로 쓰세요.';
  }
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

/// What a new law `care` would LOSE, as a warning — or null when it loses
/// nothing it can be measured to lose.
///
/// 🚨「작업전 확인」 keeps only a law card's LAST `care`, so a `care` written
/// as just the new law silently drops every law before it — rendering and
/// brush lost theirs that way on 2026-09-16·17 and were rebuilt by hand.
/// ⚠️A warning, not a refusal: a law can be retired, and a shorter
/// accumulated text is then exactly right. The two numbers say how much
/// went, so the writer can tell which of the two happened.
String? shrinkingCareWarning(
  Map<String, dynamic> json,
  Map<String, String> lawCare,
) {
  final care = json['care'];
  if (json['kind'] != 'law' || care is! String) return null;
  final id = '${json['id'] ?? ''}';
  final before = lawCare[id];
  if (before == null || care.length >= before.length) return null;
  return '⚠️「$id」의 care 가 직전보다 짧습니다(${before.length}자 → '
      '${care.length}자). 「작업전 확인」에는 이 줄만 남습니다 — 이전 법을 '
      '빠뜨린 것이 아닌지 보세요.';
}

/// Every law card's current `care` — what [shrinkingCareWarning] measures a
/// new one against.
Map<String, String> lawCares(List<BoardCard> cards) => {
  for (final c in cards)
    if (c.kind == 'law' && c.care.isNotEmpty) c.id: c.care,
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
({String? refusal, String? bytes, List<String> warnings}) boardSayAppend(
  List<String> lines,
  DateTime now, {
  Map<String, String> ended = const {},
  Map<String, String> lawCare = const {},
}) {
  final records = <Map<String, dynamic>>[];
  final warnings = <String>[];
  // A batch that writes one law twice is measured against its own last line.
  final cares = {...lawCare};
  var lineNo = 0;
  for (final raw in lines) {
    lineNo++;
    final t = raw.trim();
    if (t.isEmpty) continue;
    Map<String, dynamic> json;
    try {
      json = jsonDecode(t) as Map<String, dynamic>;
    } on Object catch (e) {
      return (
        refusal: '$lineNo번째 줄이 JSON 이 아닙니다 — $e',
        bytes: null,
        warnings: const <String>[],
      );
    }
    final why = recordRefusal(json, lineNo) ??
        endedCardRefusal(json, lineNo, ended);
    if (why != null) {
      return (refusal: why, bytes: null, warnings: const <String>[]);
    }
    if (shrinkingCareWarning(json, cares) case final warning?) {
      warnings.add('$lineNo번째 줄: $warning');
    }
    if (json['kind'] == 'law' && json['care'] is String) {
      cares['${json['id']}'] = json['care'] as String;
    }
    records.add(json);
  }
  if (records.isEmpty) {
    return (
      refusal: '적을 줄이 없습니다.',
      bytes: null,
      warnings: const <String>[],
    );
  }

  // Each record a millisecond after the last, so the story keeps the order
  // they were written in and no two collide.
  final out = StringBuffer();
  for (var i = 0; i < records.length; i++) {
    final r = records[i];
    r['ts'] = now.add(Duration(milliseconds: i)).toIso8601String();
    out.writeln(jsonEncode(r));
  }
  return (refusal: null, bytes: out.toString(), warnings: warnings);
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
  final cards = readBoard(File(args[0]));
  final result = boardSayAppend(
    File(args[1]).readAsLinesSync(),
    now,
    ended: endedCards(cards),
    lawCare: lawCares(cards),
  );
  if (result.refusal != null) {
    stderr.writeln('board_say: ${result.refusal}');
    exit(2);
  }
  File(args[0]).writeAsStringSync(result.bytes!, mode: FileMode.append);
  final n = '\n'.allMatches(result.bytes!).length;
  stdout.writeln('board_say: $n줄 추가 (${now.toIso8601String()})');
  for (final warning in result.warnings) {
    stderr.writeln('board_say: $warning');
  }
}
