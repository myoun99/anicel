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
  DateTime now,
) {
  final records = <Map<String, dynamic>>[];
  var lineNo = 0;
  for (final raw in lines) {
    lineNo++;
    final t = raw.trim();
    if (t.isEmpty) continue;
    Map<String, dynamic> json;
    try {
      json = jsonDecode(t) as Map<String, dynamic>;
    } catch (e) {
      return (refusal: '$lineNo번째 줄이 JSON 이 아닙니다 — $e', bytes: null);
    }
    final why = recordRefusal(json, lineNo);
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
  final result = boardSayAppend(File(args[1]).readAsLinesSync(), now);
  if (result.refusal != null) {
    stderr.writeln('board_say: ${result.refusal}');
    exit(2);
  }
  File(args[0]).writeAsStringSync(result.bytes!, mode: FileMode.append);
  final n = '\n'.allMatches(result.bytes!).length;
  stdout.writeln('board_say: $n줄 추가 (${now.toIso8601String()})');
}
