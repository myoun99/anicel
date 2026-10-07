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
//   dart run tool/board_say.dart <http://host:4321> <lines.jsonl>
//
// 🆕The second form (유저 2026-10-07, card
// the-board-is-one-server-for-both-machines) is for a machine that holds no
// records file: the lines go to the server of the one that does, which runs
// [sayToRecords] on them — the same refusals, the same clock, the same file.
//
// Each line of <lines.jsonl> is one record WITHOUT `ts`. They are appended in
// order, each a millisecond after the last, so the story keeps the order they
// were written in.
//
// 🆕A LINE LEFT FOR ANOTHER SESSION names that session's 담당 in `to`
// (「모두」 for every one): `{"id":"<card>","to":"타임라인/콘티","note":…}`.
// It is an ordinary line of that card, shown to the session it names at the
// start and the end of its turn, and signed here with the 담당 THIS session
// registered (`dart run tool/board_me.dart <담당>`). See [BoardLog.to].
//
// ⛔It refuses rather than writes: an unknown field, an unknown `kind`, a
// missing `id`, or a `ts` of your own. Refusing costs one message; a bad line
// in an append-only file cannot be taken back.
import 'dart:convert';
import 'dart:io';

import 'board_door.dart';
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
  if (args.first.trim().isEmpty) {
    return 'board_say: 보드 자리가 비었습니다 — 첫 인자는 board.jsonl 의 '
        '경로이거나 보드 서버의 주소(http://…)입니다.';
  }
  // A server is asked, not looked for on this disk.
  final files = boardPlaceOf(args.first, environment: const {}) is BoardServer
      ? args.skip(1)
      : args;
  for (final p in files) {
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
  return letterRefusal(json, lineNo);
}

/// What is wrong with the SHAPE of a letter's line or of a reader's mark, or
/// null — for a line that is neither, null unless it borrows their words.
///
/// 유저 2026-10-07 (the-board-is-one-server-for-both-machines-Q2): one
/// session's word to another is a line of a card that names a 담당 in `to`
/// ([BoardLog.to]). ⚠️Everything a reader will need is asked for HERE, when
/// the line is written: a letter with no writer cannot be told from its
/// reader's own notes, one with no words reaches a session as an empty
/// notice, and a line that is half a letter is delivered to nobody while
/// looking sent.
String? letterRefusal(Map<String, dynamic> json, int lineNo) {
  String said(String key) => '${json[key] ?? ''}'.trim();
  if (said('at') == kReadMark) {
    if (said('ref').isEmpty || said('from').isEmpty) {
      return '$lineNo번째 줄: 「$kReadMark」 은 어느 전달을(`ref` = 그 '
          '전달의 ts) 누가(`from` = 읽은 담당) 읽었는지입니다 — 둘 다 '
          '있어야 합니다.';
    }
    const ofAMark = {'kind', 'id', 'at', 'ref', 'from'};
    for (final key in json.keys) {
      if (ofAMark.contains(key)) continue;
      return '$lineNo번째 줄: 「$kReadMark」 줄은 표식입니다 — 「$key」 는 '
          '실을 수 없습니다. 읽고 나서 할 말은 따로 한 줄로 적으세요.';
    }
    return null;
  }
  final to = said('to');
  if (to.isEmpty) {
    if (json.containsKey('to')) {
      return '$lineNo번째 줄: `to` 가 비었습니다 — 받는 담당의 이름이나 '
          '「$kEveryone」 를 적으세요.';
    }
    if (json.containsKey('from')) {
      return '$lineNo번째 줄: `from` 은 전달(`to`)과 「$kReadMark」 에만 '
          '씁니다 — 혼자서는 아무도 안 읽습니다.';
    }
    return null;
  }
  // A question is folded into the card that asked it, and what is written
  // on the question's own id is drawn nowhere in that card's story.
  final asked = kQName.firstMatch(said('id'));
  if (asked != null) {
    return '$lineNo번째 줄: 전달은 질문(「${said('id')}」)이 아니라 그 질문을 '
        '낸 카드(「${asked.group(1)}」)에 적습니다 — 질문에 적은 줄은 카드를 '
        '펼쳐도 보이지 않습니다.';
  }
  final from = said('from');
  if (from.isEmpty) {
    return '$lineNo번째 줄: 전달에 보낸 담당(`from`)이 없습니다 — 세션이 '
        '담당 이름을 등록해 두면 이 도구가 채웁니다: '
        'dart run tool/board_me.dart <담당>';
  }
  if (from == to) {
    return '$lineNo번째 줄: 「$to」 가 자기 앞으로 보내는 전달입니다 — 자기 '
        '카드에는 `to` 없이 그냥 적으면 됩니다.';
  }
  if (said('note').isEmpty) {
    return '$lineNo번째 줄: 전달에는 글(`note`)이 있어야 합니다 — 빈 '
        '전달은 받는 세션에 빈 알림으로 뜹니다.';
  }
  return null;
}

/// What is wrong with a reader's mark AGAINST THE BOARD it would go onto, or
/// null. [letters] is every letter there is: card id → the letter's stamp →
/// the letter.
///
/// ⚠️A mark that names nothing would be accepted by the fold in silence —
/// it marks nothing — and the session that wrote it would believe the letter
/// answered. So the three ways a mark can miss are said when it is written.
String? readMarkRefusal(
  Map<String, dynamic> json,
  int lineNo,
  Map<String, Map<String, BoardLog>> letters,
) {
  if ('${json['at'] ?? ''}'.trim() != kReadMark) return null;
  final id = '${json['id'] ?? ''}';
  final ref = '${json['ref'] ?? ''}';
  final reader = '${json['from'] ?? ''}'.trim();
  final letter = letters[id]?[ref];
  if (letter == null) {
    return '$lineNo번째 줄: 「$id」 에 ts 가 $ref 인 전달이 없습니다.';
  }
  final readAt = letter.readBy[reader];
  if (readAt != null) {
    return '$lineNo번째 줄: 「$reader」 는 이 전달을 이미 읽었습니다($readAt).';
  }
  if (!letterWaitsFor(letter, reader)) {
    return '$lineNo번째 줄: 이 전달은 「${letter.from}」 이 「${letter.to}」 '
        '앞으로 남긴 것입니다 — 「$reader」 가 읽음으로 표시할 수 없습니다.';
  }
  return null;
}

/// Every letter of [cards], by the card and the stamp a mark names it with.
Map<String, Map<String, BoardLog>> lettersByStamp(List<BoardCard> cards) {
  final found = <String, Map<String, BoardLog>>{};
  for (final letter in lettersOf(cards)) {
    (found[letter.card.id] ??= {})[letter.entry.ts] = letter.entry;
  }
  return found;
}

/// A letter left for a name no card on the board is held by — as a warning,
/// or null. ⚠️A warning and not a refusal: a session on a machine that has
/// just joined answers to a 담당 before any card names it, and its first
/// letter has to get through. What it catches is the spelling: a letter to
/// 「타임라인」 waits for a session that calls itself 「타임라인/콘티」 for
/// ever.
String? unknownReaderWarning(Map<String, dynamic> json, Set<String> holders) {
  final to = '${json['to'] ?? ''}'.trim();
  if (to.isEmpty || to == kEveryone || holders.contains(to)) return null;
  if (holders.isEmpty) return null;
  final known = holders.toList()..sort();
  return '⚠️「$to」 는 지금 보드의 어느 카드도 맡고 있지 않은 이름입니다 — '
      '받는 담당의 이름이 맞는지 보세요(카드를 맡은 담당: '
      '${known.join(' · ')}).';
}

/// The 담당 that hold a card still open — the names a letter is usually for.
Set<String> cardHolders(List<BoardCard> cards) {
  final ended = endedCards(cards);
  return {
    for (final card in cards)
      if (card.owner.isNotEmpty && !ended.containsKey(card.id)) card.owner,
  };
}

/// [lines] with [sender] written into every letter and every reader's mark
/// that names no writer — the tool signs for the session, so a letter cannot
/// be sent unsigned by forgetting a field.
///
/// ⚠️A line that already says who wrote it is left as it is, and so is a
/// line that is not JSON: the append refuses that one by its number, and a
/// signer that swallowed it would hide which line it was.
List<String> signedBy(String? sender, List<String> lines) {
  if (sender == null) return lines;
  return [
    for (final raw in lines) _signed(raw, sender),
  ];
}

String _signed(String raw, String sender) {
  Map<String, dynamic> json;
  try {
    json = jsonDecode(raw.trim()) as Map<String, dynamic>;
  } on Object catch (_) {
    return raw;
  }
  String said(String key) => '${json[key] ?? ''}'.trim();
  final needsAWriter = said('to').isNotEmpty || said('at') == kReadMark;
  if (!needsAWriter || said('from').isNotEmpty) return raw;
  return jsonEncode({...json, 'from': sender});
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
  Map<String, Map<String, BoardLog>> letters = const {},
  Set<String> holders = const {},
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
        endedCardRefusal(json, lineNo, ended) ??
        readMarkRefusal(json, lineNo, letters);
    if (why != null) {
      return (refusal: why, bytes: null, warnings: const <String>[]);
    }
    if (shrinkingCareWarning(json, cares) case final warning?) {
      warnings.add('$lineNo번째 줄: $warning');
    }
    if (unknownReaderWarning(json, holders) case final warning?) {
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

/// What became of one telling: how many lines went onto the records and at
/// what time, or why none did.
typedef BoardSaid = ({
  String? refusal,
  int lines,
  String at,
  List<String> warnings,
});

/// Tells [lines] to [records], stamped [now] — refused whole or written
/// whole.
///
/// ⚠️ONE FUNCTION FOR BOTH ROADS. `board_say` runs it when it is pointed at
/// the records file, and the server runs it when a tool on another machine
/// posts the same lines to `/say`. What a card refuses, what a law warns
/// about and whose clock stamps the line cannot differ between the two,
/// because there is nothing else to run.
BoardSaid sayToRecords(File records, List<String> lines, DateTime now) {
  final cards = readBoard(records);
  final result = boardSayAppend(
    lines,
    now,
    ended: endedCards(cards),
    lawCare: lawCares(cards),
    letters: lettersByStamp(cards),
    holders: cardHolders(cards),
  );
  final bytes = result.bytes;
  if (bytes == null) {
    return (
      refusal: result.refusal,
      lines: 0,
      at: now.toIso8601String(),
      warnings: const <String>[],
    );
  }
  records.writeAsStringSync(bytes, mode: FileMode.append);
  return (
    refusal: null,
    lines: '\n'.allMatches(bytes).length,
    at: now.toIso8601String(),
    warnings: result.warnings,
  );
}

/// The letters that wait for [reader], as the text a hook puts in front of
/// its session — and marked read by the same act. Empty when none wait.
///
/// ⚠️TAKEN, NOT PEEKED AT. A hook runs at the start and at the end of every
/// turn, so a letter that was only shown would be shown at each of them for
/// ever; and two steps — show, then mark — would be two requests a hook has
/// to get right in bash. The moment a letter is handed to the session it is
/// for IS the reading of it, and the mark is written by the very function
/// every other line of the board goes through ([sayToRecords]).
String takeLetters(File records, String reader, DateTime now) {
  if (reader.trim().isEmpty) return '';
  final waiting = [
    for (final letter in lettersOf(readBoard(records)))
      if (letterWaitsFor(letter.entry, reader.trim())) letter,
  ]..sort((a, b) => a.entry.ts.compareTo(b.entry.ts));
  if (waiting.isEmpty) return '';
  // ⚠️No `kind` on a mark: a line's kind is its CARD's kind, and a mark
  // must not turn a question into an item by passing over it.
  final marked = sayToRecords(records, [
    for (final letter in waiting)
      jsonEncode({
        'id': letter.card.id,
        'at': kReadMark,
        'ref': letter.entry.ts,
        'from': reader.trim(),
      }),
  ], now);
  return lettersText(waiting, reader.trim(), unmarked: marked.refusal);
}

/// [letters] as a session reads them: who wrote each, on which card, when,
/// and the words — then how to answer.
String lettersText(
  List<BoardLetter> letters,
  String reader, {
  String? unmarked,
}) {
  final out = StringBuffer()
    ..writeln('📨 보드에 「$reader」 앞으로 남은 전달 ${letters.length}건'
        '${unmarked == null ? ' — 읽음으로 표시했습니다.' : ''}');
  for (final letter in letters) {
    final card = letter.card;
    final when = letter.entry.ts.length >= 16
        ? letter.entry.ts.substring(5, 16).replaceFirst('T', ' ')
        : letter.entry.ts;
    out
      ..writeln()
      ..writeln('━ ${letter.entry.from} → ${letter.entry.to} · 카드 ${card.id}'
          '${card.title.isEmpty ? '' : ' 「${card.title}」'} · $when')
      ..writeln(letter.entry.text);
  }
  out
    ..writeln()
    ..write('답은 그 카드에 `to` 를 적은 줄로 남깁니다: '
        '{"id":"<카드>","to":"<보낸 담당>","note":"…"}');
  if (unmarked != null) {
    out
      ..writeln()
      ..write('⚠️읽음 표시는 적지 못했습니다($unmarked) — 다음 턴에 다시 '
          '보입니다.');
  }
  return out.toString();
}

/// The same telling, asked of the server that holds the records.
///
/// A server that could not be reached, or that would not let this tool in,
/// is a refusal like any other: nothing was written, and the reason is said.
Future<BoardSaid> sayToServer(BoardServer server, List<String> lines) async {
  final answer = await askBoard(
    server,
    'POST',
    '/say',
    body: '${lines.join('\n')}\n',
  );
  BoardSaid refused(String why) =>
      (refusal: why, lines: 0, at: '', warnings: const <String>[]);
  if (answer.status == 0) return refused(answer.body);
  if (answer.status == HttpStatus.unauthorized) {
    return refused('보드 서버가 들여보내지 않았습니다(${server.base}) — '
        '${turnedAwayAdvice(server)}');
  }
  Map<String, dynamic> said;
  try {
    said = jsonDecode(answer.body) as Map<String, dynamic>;
  } on Object catch (_) {
    return refused('보드 서버의 대답을 읽지 못했습니다(${answer.status}) — '
        '이 도구와 서버의 판이 다를 수 있습니다.');
  }
  return (
    refusal: said['refusal'] as String? ??
        (answer.status == HttpStatus.ok
            ? null
            : '보드 서버가 ${answer.status} 로 답했습니다.'),
    lines: (said['lines'] as num?)?.toInt() ?? 0,
    at: '${said['at'] ?? ''}',
    warnings: [for (final w in (said['warnings'] as List?) ?? const []) '$w'],
  );
}

Future<void> main(List<String> args) async {
  final refusal = boardSayRefusal(args);
  if (refusal != null) {
    stderr.writeln(refusal);
    exit(2);
  }
  // A letter is signed with the 담당 this session registered — here, on the
  // machine the session runs on, which is the only place that knows it.
  final lines = signedBy(
    sessionNameOf(Platform.environment),
    File(args[1]).readAsLinesSync(),
  );
  final said = switch (boardPlaceOf(args[0])) {
    // 🚨THE CLOCK, ONCE, HERE — the only place this program asks what time
    // it is, and the only place it was ever possible to get wrong. (Through
    // a server it is the server's clock, read once there.)
    BoardFile(:final path) => sayToRecords(File(path), lines, DateTime.now()),
    final BoardServer server => await sayToServer(server, lines),
  };
  if (said.refusal != null) {
    stderr.writeln('board_say: ${said.refusal}');
    exit(2);
  }
  stdout.writeln('board_say: ${said.lines}줄 추가 (${said.at})');
  for (final warning in said.warnings) {
    stderr.writeln('board_say: $warning');
  }
}
