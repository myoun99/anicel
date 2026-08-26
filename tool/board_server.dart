// The work board, served from this machine.
//
// It replaces a published page that had to be regenerated and re-uploaded by
// hand every time anything changed. Three of the four steps in that loop were
// pure mechanics with no judgement in them, and mechanics that a person has to
// remember are mechanics that eventually get skipped -- the old board went
// stale constantly.
//
// So there is no publish step any more. The page is rendered ON REQUEST from
// two inputs:
//
//   1. a records file (JSONL) -- one line per fact, append-only, later lines
//      win. It lives beside the memory notes: recording a fact and updating
//      the board are the same act.
//   2. `gh` -- pull requests, live. Anything GitHub already knows is never
//      written down: an open PR IS an in-flight item, a merged PR IS a landed
//      one, and neither needs a record to exist.
//
// NO FILE WATCHER. A watcher costs something every second of every day to
// answer a question nobody is asking; rendering on request costs nothing when
// the tab is closed and single-digit milliseconds when it is open. `gh` is the
// only slow input, so it is cached for a few seconds and shared by every
// request in that window.
//
// THE PAGE WRITES BACK. Submitting an answer, filing feedback, pasting a
// screenshot, dismissing a landed item -- each POSTs here and lands in the
// records file (or the shots folder) before the page redraws. Nothing is
// copied by hand and there is nothing to forget.
//
// It is an instrument, so here is what it looks like when it lies:
//   - `gh` unreachable (offline, not logged in) -> the header says so and PR
//     sections render empty. It never invents a state, and it never shows an
//     empty "지금" as if that were good news.
//   - a malformed JSONL line -> the line number is printed to the console and
//     the line is skipped. The page still renders; silence would be worse.
//   - the records file missing -> refuses to start rather than serving an
//     empty board that looks like "nothing to do".
//
//   dart run tool/board_server.dart --records <file.jsonl> [--port 4321]
//
// Localhost only, on purpose: the board is not published anywhere and the
// records file is not in this repository, because the repository is public.
import 'dart:convert';
import 'dart:io';

const _repo = 'myoun99/anicel';
const _ghCacheSeconds = 20;

/// A PR body line that carries the Korean one-liner for the board.
///
/// PR titles stay English: a squash merge turns the title into the commit
/// subject, so it is git history in a public repository, and history that
/// disagrees in language with the code it describes is worse than history
/// nobody can skim. This trailer puts the readable line where the board can
/// find it without anyone writing a second record.
const _koTrailer = 'Board-ko:';

late final String _recordsPath;
late final String _shotsDir;
late final String _ghPath;
late final String _gitRoot;

Future<void> main(List<String> args) async {
  _recordsPath = _flag(args, '--records') ?? '';
  _ghPath = _flag(args, '--gh') ?? 'gh';
  _gitRoot = _flag(args, '--git') ?? Directory.current.path;
  final port = int.tryParse(_flag(args, '--port') ?? '4321') ?? 4321;

  if (_recordsPath.isEmpty || !File(_recordsPath).existsSync()) {
    stderr.writeln('records file not found. '
        'usage: dart run tool/board_server.dart --records <file.jsonl>');
    exit(2);
  }
  _shotsDir = '${File(_recordsPath).parent.path}/board-shots';
  Directory(_shotsDir).createSync(recursive: true);

  HttpServer server;
  try {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  } on SocketException catch (e) {
    stderr.writeln('port $port is not available (${e.osError?.message}). '
        'Another board server is probably already running.');
    exit(2);
  }

  stdout.writeln('board  ->  http://localhost:$port');
  stdout.writeln('records:   $_recordsPath');
  stdout.writeln('shots:     $_shotsDir');

  await for (final request in server) {
    try {
      await _handle(request);
    } catch (e) {
      stderr.writeln('board: request failed: $e');
      request.response.statusCode = 500;
      await request.response.close();
    }
  }
}

String? _flag(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

// ----------------------------------------------------------------- routes

Future<void> _handle(HttpRequest req) async {
  final path = req.uri.path;

  if (path.startsWith('/shot/') && req.method == 'GET') {
    final file = File('$_shotsDir/${Uri.decodeComponent(path.substring(6))}');
    if (!file.existsSync() || !file.path.endsWith('.png')) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    req.response.headers.contentType = ContentType('image', 'png');
    await req.response.addStream(file.openRead());
    await req.response.close();
    return;
  }

  if (req.method == 'POST') {
    final body =
        jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
    String? newId;
    switch (path) {
      case '/submit':
        // 🚨★★★EVERYTHING THE USER SUBMITS COMES BACK TO 분류 전, EXCEPT A
        // CLEAN TICK, WHICH ENDS THE CARD (유저 2026-08-26).
        //
        //  · 확인 with no memo → `deleted`. It was looked at and it was fine;
        //    a card that says so forever is a card nobody opens again. 정해진
        //    것 was a graveyard with a scrollbar and is gone.
        //  · 확인 with a memo → 분류 전. The work is not finished, so the card
        //    comes BACK for me to judge (「작업이 예상되면 다시 대기중이나
        //    착수가능으로 올려」).
        //  · 답할 것, answered → 분류 전 too (유저: 「답할것 답한것도 그럼
        //    제출태그로 바꾸는게아니라 분류전으로 옮기고 대답 태그 붙이면
        //    좋을거같은데」). Right, and for the reason that makes the whole
        //    section make sense: 분류 전 means 「내가 읽고 분류한다」, and an
        //    answer is precisely something the user said that I must read and
        //    act on. ⛔ONE inbox, not one inbox plus a tag to remember to scan
        //    somewhere else.
        //
        // ⚠️`deleted` is a state, not a rewrite. The records file is
        // append-only and that is what makes it the record; the panel stops
        // being DRAWN, the line stays. No undo, by the user's own call
        // (「되돌리기못해도되니까」).
        final kind = '${body['kind'] ?? 'decision'}';
        final memo = '${body['memo'] ?? ''}'.trim();
        final ticked = kind == 'check' && memo.isEmpty;
        _append({
          'kind': kind,
          'id': body['id'],
          'answer': body['answer'] ?? '',
          'answerNote': memo,
          'ts': _now(),
          'state': ticked ? 'deleted' : 'inbox',
        });
      case '/dismiss':
        for (final id in (body['ids'] as List?) ?? [body['id']]) {
          _append({
            'kind': 'item',
            'id': id,
            'state': 'archived',
            'ts': _now(),
          });
        }
      case '/intake':
        newId = _intake(body);
      case '/edit':
        final text = '${body['text'] ?? ''}'.trim();
        final first = text.split('\n').first;
        // The user fixing their own filing — still their words, so still
        // `said`. ⚠️This overwrites rather than appending a second entry: a
        // typo corrected a minute later is not a new stage in the story.
        _append({
          'kind': 'item',
          'id': body['id'],
          'title': first.length > 70 ? '${first.substring(0, 70)}…' : first,
          'said': text,
          'ts': _now(),
        });
      case '/purge':
        _purge('${body['id']}');
      case '/refresh':
        _ghAt = DateTime.fromMillisecondsSinceEpoch(0);
      case '/shot':
        _saveShot(body);
      default:
        req.response.statusCode = 404;
        await req.response.close();
        return;
    }
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'ok': true, 'id': ?newId}));
    await req.response.close();
    return;
  }

  if (path != '/') {
    req.response.statusCode = 404;
    await req.response.close();
    return;
  }
  // Order matters: reading the records is what loads the 최근 착지 mark, and
  // the baseline write needs to know whether one is already there.
  final entries = _readRecords(File(_recordsPath));
  final gh = await _prs();
  _markLandedBaseline(gh);
  req.response
    ..headers.contentType = ContentType.html
    ..headers.set('Cache-Control', 'no-store')
    ..write(_render(entries, gh, await _checkouts(),
        landedPage: int.tryParse(req.uri.queryParameters['landed'] ?? '') ?? 1));
  await req.response.close();
}

/// Writes the 최근 착지 mark once, the first time a board ever draws.
///
/// This is the only place the board writes without being asked. The
/// alternative is a first visit that dumps every merge within reach and asks
/// the reader to confirm history they watched happen.
///
/// A FAILED LOOKUP MUST NEVER SET THE BASELINE. gh returns an empty list when
/// it cannot answer, and an empty list looks exactly like "nothing has landed
/// yet" -- mark on that and every merge in the repo is silently older than the
/// mark, so the section stays empty forever and nobody finds out. `ok` is the
/// only field that can tell those two apart.
///
/// An empty list from a gh that DID answer needs no guard of its own: marking
/// a repo with no merges yet is harmless, since everything that lands after
/// still lands after. A guard for it was here and was removed -- it made the
/// `ok` check untestable by shadowing it on every path a test could reach.
void _markLandedBaseline(_Gh gh) {
  if (_landedSince != null) return;
  if (!gh.ok) return;

  final at = DateTime.now().toUtc().toIso8601String();
  _append({
    'kind': 'meta',
    'landedSince': at,
    'note': '최근 착지의 기준선 — 이 시각까지 머지된 것은 이미 본 것으로 친다. '
        '보드가 생기기 전에 머지된 PR을 다시 확인하라고 물을 이유가 없다.',
  });
  _landedSince = DateTime.parse(at);
}

String _now() => DateTime.now().toIso8601String();

void _append(Map<String, dynamic> line) {
  File(_recordsPath)
      .writeAsStringSync('${jsonEncode(line)}\n', mode: FileMode.append);
  stdout.writeln('board: recorded ${line['id'] ?? line['kind']}');
}

/// Files a new idea or piece of feedback and hands back the id it was given.
///
/// The id is allocated here rather than asked for: the person filing it is
/// mid-thought, and "what should I call this" is exactly the friction that
/// makes people not write things down. Classification comes later -- it lands
/// in `inbox`, which is a section on the board and not a synonym for done.
String _intake(Map<String, dynamic> body) {
  final kind = '${body['kind']}';
  final text = '${body['text'] ?? ''}'.trim();
  final tag = '${body['tag'] ?? ''}'.trim();
  // 임시 is its own filing, not a lesser feedback: it says the thought is not
  // finished yet, so whoever reads it should expect to ask rather than act.
  final (prefix, label, stage) = switch (kind) {
    'idea' => ('I', '아이디어', '유저 아이디어'),
    'draft' => ('M', '임시', '임시 메모'),
    _ => ('F', '피드백', '유저 피드백'),
  };
  final id = _nextId(prefix);
  final firstLine = text.split('\n').first;
  _append({
    'kind': 'item',
    'id': id,
    'title': firstLine.isEmpty
        ? '(스크린샷만)'
        : (firstLine.length > 70 ? '${firstLine.substring(0, 70)}…' : firstLine),
    // 🚨`said`, and NOT also `note`. This is the user's own writing; the panel
    // labels it as theirs. The whole redesign turns on never letting my words
    // and theirs share a field — and writing both would print the same
    // paragraph twice, once under each name.
    'said': text,
    'at': stage,
    'tags': [label, if (tag.isNotEmpty) tag],
    'state': 'inbox',
    'ts': _now(),
  });
  return id;
}

/// Rewrites the records without a given id — a real delete, not an `archived`
/// line, so the number goes back into the pool.
///
/// Only an inbox item may be purged. Everything else is history someone
/// reasoned from, and an append-only log that quietly loses entries is worse
/// than one that keeps a few dead ones.
bool _purge(String id) {
  final entry = _readRecords(File(_recordsPath)).where((e) => e.id == id);
  if (entry.isEmpty || entry.first.state != 'inbox') return false;
  final kept = File(_recordsPath).readAsLinesSync().where((line) {
    final t = line.trim();
    if (t.isEmpty) return false;
    try {
      return (jsonDecode(t) as Map<String, dynamic>)['id'] != id;
    } catch (_) {
      return true; // unreadable lines are somebody else's problem, not ours
    }
  });
  File(_recordsPath).writeAsStringSync('${kept.join('\n')}\n');
  for (final f in Directory(_shotsDir).listSync()) {
    final name = f.path.split(RegExp(r'[\\/]')).last;
    if (name.startsWith('$id-')) f.deleteSync();
  }
  stdout.writeln('board: purged $id');
  return true;
}

/// Next free number for a prefix, read from the records themselves so two
/// filings in a row cannot collide and nothing has to remember a counter.
String _nextId(String prefix) {
  final used = <int>{};
  final pattern = RegExp('^$prefix-([0-9]+)\$');
  for (final e in _readRecords(File(_recordsPath))) {
    final m = pattern.firstMatch(e.id);
    if (m != null) used.add(int.parse(m.group(1)!));
  }
  var n = 1;
  while (used.contains(n)) {
    n++;
  }
  return '$prefix-$n';
}

/// Screenshots are stored as files named after the item, so the folder IS the
/// index -- there is no second place that can disagree about which shots an
/// item has, and deleting the file is deleting the attachment.
void _saveShot(Map<String, dynamic> body) {
  final id = '${body['id']}'.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  final data = '${body['data']}';
  final comma = data.indexOf(',');
  if (comma < 0) return;
  final bytes = base64Decode(data.substring(comma + 1));
  final name = '$id-${DateTime.now().millisecondsSinceEpoch}.png';
  File('$_shotsDir/$name').writeAsBytesSync(bytes);
  stdout.writeln('board: shot $name (${(bytes.length / 1024).round()} KB)');
}

List<String> _shotsFor(String id) {
  final dir = Directory(_shotsDir);
  if (!dir.existsSync()) return const [];
  final out = <String>[];
  for (final f in dir.listSync()) {
    final name = f.path.split(RegExp(r'[\\/]')).last;
    if (name.startsWith('$id-') && name.endsWith('.png')) out.add(name);
  }
  out.sort();
  return out;
}

// ---------------------------------------------------------------- records

/// One entry in a card's history: what was written, when, and — for records
/// written after the field existed — which 공정 wrote it.
///
/// `at` is deliberately optional and deliberately free text. The board's
/// stages are a story people tell, not an enum the server enforces; a card
/// that goes 접수 → 대기중 → 답변 → 착수 → 실기확인 and one that goes 접수 →
/// 삭제 are both legitimate, and a fixed list would only invite a lie on the
/// day some card does neither.
/// ONE STAGE, ONE VOICE (유저 2026-08-26: 「그냥 한 항목에 원문/판단 넣는게
/// 아니라 제대로 공정마다나누자. 공정적으로는 원문이 있고, 그 다음이
/// 판단이잖아」).
///
/// 🎯The stages ARE the sequence, so an entry never has to say who is talking
/// twice: 「유저 피드백」 is the user, 「AI 판단」 is me, and they are separate
/// rows because they happened at separate times. Cramming both into one entry
/// was me modelling the RECORD (which happens to carry several fields) instead
/// of the PROCESS (which is one thing after another).
///
/// A record carrying more than one of `said`/`note`/`think` therefore becomes
/// more than one entry, always in that order — what was said, then what I made
/// of it, then what I worked out.
class _Log {
  _Log(this.ts, this.at, this.text, {this.byUser = false});
  final String ts;

  /// The 공정 this entry belongs to — 유저 피드백 · 대기중 · AI 판단 · 실기확인.
  final String at;
  final String text;

  /// Whose words these are. Drives nothing but the tint: the stage name
  /// already says it, and saying it twice is the 「설명 문구」 habit.
  final bool byUser;
}

class _Entry {
  _Entry(this.id, this.kind);

  final String id;
  String kind;
  String title = '';
  List<String> tags = const [];
  String state = 'open';
  String note = '';

  /// The user's own current words on this card — what the inbox editor edits.
  /// Kept apart from [note] (mine) so a status line can never overwrite a
  /// filing, which is the bug this whole board grew out of.
  String said = '';

  /// 🚨When this card last moved — the date the head row shows, at the far
  /// right after the tags (유저 2026-08-26).
  ///
  /// ONE number, not two. A 「생김 · 갱신」 pair was the first shape and the
  /// user cut it: 「생김갱신 구분두지말고 갱신하나로 퉁치고」. The birth date
  /// is still in the file — the first line carrying an id — and is left
  /// there rather than surfaced, because two dates on one row is a
  /// comparison the reader has to make before learning anything.
  ///
  /// ⚠️Empty when no record for this card carried a `ts` — older lines
  /// predate the field, and a made-up date is worse than none.
  String updated = '';

  /// 🚨★★★EVERY WORD THIS CARD HAS EVER CARRIED, oldest first (유저
  /// 2026-08-26: 「각 공정마다 원문을 무조건 남길것. 패널내용이 길어지는건
  /// 감수하고, 대신 내부에 진행된 공정마다 항목만들어서 접기펼치기가능하게」).
  ///
  /// ⛔The renderer used to show `note` and nothing else, and `note` is
  /// last-wins — so every time I wrote a status line onto a card, the
  /// **user's original words were overwritten on screen**. That is why a card
  /// could reach 확인할 것 as a bare 「T14」 with nothing saying what T14 ever
  /// was: 「원문이 안남아있어서 T14라고해도 뭐 말하는지 모르겠고」.
  ///
  /// 🎯The fix needed no new record kind, because nothing was ever lost — the
  /// records file is append-only, so every earlier `note` is still sitting in
  /// it. The merge was throwing them away on the way to the screen. This list
  /// stops the throwing away; the file did its job all along.
  final List<_Log> log = [];

  /// 🚨THE LANDING THIS CHECK BELONGS TO — the field that makes 확인할 것 one
  /// row per SUBJECT (유저 2026-08-26: 「실기확인이랑 머지된거랑 겹치는부분
  /// 있으면 병합하는건 확인한거맞아?」).
  ///
  /// It exists because the answer was no. Six checks (C-tp1..C-tp6) were the
  /// hands-on half of the tool-preset round, and that round's PR was sitting
  /// on the SAME list as its own row — seven rows for one thing. Nothing in
  /// the data said so, so nothing could merge them.
  ///
  /// ⚠️NOT `pr`, and the difference is the whole point. `pr` means 「this card
  /// IS that PR's work」 and only one card can hold it (`claimed` is a map).
  /// `under` means 「this is something to look at ON that landing」 and many
  /// can share one. One field answering both questions is how the map would
  /// silently keep the last check and drop five.
  int? under;

  /// On a `decision`: the card that raised this question. Not the same as
  /// [under] (a PR number) — this is a board id, and it points the other way:
  /// [under] says 「my parent owns me」, `of` says 「I came out of that one and
  /// my answer goes back into it」.
  String of = '';

  /// 🚨★★★WHAT IS STILL LEFT — and the reason this card is not in 확인할 것
  /// (유저 2026-08-26: 「애초에 남은게 존재하면 확인할것에 있으면 안되는거
  /// 아니냐? 다 끝난줄알았는데」).
  ///
  /// A card that claimed a PR used to land in 확인할 것 the moment that PR
  /// merged, whether or not the CARD was finished. F-17 was five items; one
  /// merged as #1242 and two were already true, so it appeared as a landing
  /// with two items still unwritten — and a tick there DELETES the card, which
  /// would have buried them.
  ///
  /// ⛔Deliberately not a bool and not a state. It has to say WHAT is left,
  /// because 「this is unfinished」 with no list is the same dead end as a row
  /// that says only 「T14」.
  String rest = '';

  /// On a `law` record: what to read first in this area, and what must not be
  /// done. Separate from `note` because a caution outlives the status line it
  /// would otherwise be buried in.
  String care = '';

  /// On a `law` record: the tag whose cards this law governs.
  String tag = '';
  String where = '';
  String why = '';
  String how = '';
  int? pr;
  List<Map<String, dynamic>> options = const [];
  String? recommend;
  String? answer;
  String answerNote = '';
}

/// Folds the append-only log into current state: a later line with the same id
/// overwrites only the fields it names, so "this now has an answer" is one
/// short line rather than a restatement of the whole record.
/// Lines the reader could not use. The board still draws -- thirty items beat
/// none -- but it says so at the top, because an item that silently stops
/// existing is the one failure this format can still have. This replaces a
/// Stop hook that cost 2.4s of every turn to answer the same question.
List<int> _badLines = const [];

/// 최근 착지 reports only what landed AFTER this moment.
///
/// Without it the section was a window onto all of git history: it showed the
/// eight newest merges, and ticking those eight revealed the next eight, and
/// so on for as far back as `gh pr list` would reach -- each tick also costing
/// a permanent `pr-N archived` line. But a PR that merged before this board
/// existed was watched as it merged. It is not news, and asking for it to be
/// confirmed is asking twice.
///
/// So the section is bounded by a mark instead of a count: everything at or
/// before the mark is already seen. The mark is written once, by the board
/// itself, the first time it runs -- which is what removed the cap. The list
/// is short now because it is genuinely short.
DateTime? _landedSince;

/// Did this land after the mark?
bool _isNews(_Pr pr) {
  final since = _landedSince;
  if (since == null) return true;
  final at = pr.mergedAt;
  // A merge gh gave no timestamp for cannot be placed against the mark. Show
  // it: 확인 can dismiss a row, nothing can recover one that was never drawn.
  return at == null || at.isAfter(since);
}

List<_Entry> _readRecords(File file) {
  // Reset, not update: the file is the state. A mark that survived a read of a
  // file that no longer carries one would be a mark nobody can remove.
  _landedSince = null;
  final bad = <int>[];
  final byId = <String, _Entry>{};
  final order = <String>[];
  var lineNo = 0;
  for (final line in file.readAsLinesSync()) {
    lineNo++;
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    Map<String, dynamic> json;
    try {
      json = jsonDecode(trimmed) as Map<String, dynamic>;
    } catch (_) {
      stderr.writeln('board: line $lineNo is not valid JSON, skipped');
      bad.add(lineNo);
      continue;
    }
    final kind = json['kind'] as String? ?? '';
    if (kind == 'meta') {
      // meta lines are notes to self and carry no id, with one exception: the
      // 최근 착지 mark. A later line wins, same as every other field here.
      final since = json['landedSince'] as String?;
      if (since != null) _landedSince = DateTime.tryParse(since);
      continue;
    }
    final id = json['id'] as String?;
    if (id == null) {
      stderr.writeln('board: line $lineNo has no id, skipped');
      bad.add(lineNo);
      continue;
    }
    final e = byId.putIfAbsent(id, () {
      order.add(id);
      return _Entry(id, kind);
    });
    if (kind.isNotEmpty) e.kind = kind;
    // Last line wins: the head shows when this card last moved.
    final ts = '${json['ts'] ?? ''}';
    if (ts.isNotEmpty) e.updated = ts;
    // ⚠️Recorded BEFORE `note` is merged, so the list keeps what each line
    // said rather than what the card ended up saying. A line that repeats the
    // note verbatim adds nothing and is skipped — amendments that touch only
    // `state` or `pr` often carry the old note along for readability.
    // ⚠️`at` names the FIRST stage this record opens. A record normally
    // carries one of the three; when it carries several they are several
    // stages and the later ones take their own names.
    var at = '${json['at'] ?? ''}'.trim();
    void stage(String text, String fallback, {bool byUser = false}) {
      if (text.isEmpty) return;
      final label = at.isEmpty ? fallback : at;
      at = '';
      if (e.log.any((l) => l.text == text)) return;
      e.log.add(_Log(ts, label, text, byUser: byUser));
    }

    stage('${json['said'] ?? ''}'.trim(), '유저 메모', byUser: true);
    stage('${json['note'] ?? ''}'.trim(), '작업 기록');
    stage('${json['think'] ?? ''}'.trim(), 'AI 판단');
    // An answer is the user's own words and belongs in the same story — it is
    // the one kind of entry the board itself writes on their behalf.
    final ansNote = '${json['answerNote'] ?? ''}'.trim();
    final ans = '${json['answer'] ?? ''}'.trim();
    if (ans.isNotEmpty || ansNote.isNotEmpty) {
      final said = [
        if (ans.isNotEmpty && ans != 'ok') '고른 것: $ans',
        if (ansNote.isNotEmpty) ansNote,
        if (ans == 'ok' && ansNote.isEmpty) '확인 — 문제 없음',
      ].join('\n');
      if (!e.log.any((l) => l.text == said)) {
        e.log.add(_Log(ts, '유저 대답', said, byUser: true));
      }
    }
    if (json['title'] != null) e.title = json['title'] as String;
    if (json['state'] != null) e.state = json['state'] as String;
    if (json['note'] != null) e.note = json['note'] as String;
    if (json['said'] != null) e.said = json['said'] as String;
    if (json['care'] != null) e.care = json['care'] as String;
    if (json['tag'] != null) e.tag = json['tag'] as String;
    if (json['where'] != null) e.where = json['where'] as String;
    if (json['why'] != null) e.why = json['why'] as String;
    if (json['how'] != null) e.how = json['how'] as String;
    if (json['recommend'] != null) e.recommend = json['recommend'] as String;
    if (json['answer'] != null) e.answer = json['answer'] as String;
    if (json['answerNote'] != null) e.answerNote = json['answerNote'] as String;
    if (json['pr'] != null) e.pr = (json['pr'] as num).toInt();
    if (json['under'] != null) e.under = (json['under'] as num).toInt();
    if (json['of'] != null) e.of = '${json['of']}';
    if (json['rest'] != null) e.rest = '${json['rest']}';
    if (json['tags'] != null) {
      e.tags = (json['tags'] as List).map((t) => '$t').toList();
    }
    if (json['options'] != null) {
      e.options = (json['options'] as List)
          .map((o) => Map<String, dynamic>.from(o as Map))
          .toList();
    }
  }
  _badLines = bad;
  return [for (final id in order) byId[id]!];
}

// --------------------------------------------------------------------- gh

class _Pr {
  _Pr(this.number, this.state, this.title, this.checks, this.mergedAt);

  final int number;
  final String state;
  final String title;
  final String checks;

  /// When it landed, or null while it is still open. Not the PR number: those
  /// run in the order work STARTED, and a branch opened last week can land
  /// after one opened this morning. 최근 착지 means recently landed.
  final DateTime? mergedAt;
}

class _Gh {
  _Gh(this.prs, {required this.ok});

  final List<_Pr> prs;
  final bool ok;
}

_Gh? _ghCache;
DateTime _ghAt = DateTime.fromMillisecondsSinceEpoch(0);

/// One `gh` call shared by every request inside the cache window. It is the
/// only input slow enough to be worth caching, and a few seconds of staleness
/// on a PR list is not a staleness anyone can act on.
Future<_Gh> _prs() async {
  if (_ghCache != null &&
      DateTime.now().difference(_ghAt).inSeconds < _ghCacheSeconds) {
    return _ghCache!;
  }
  ProcessResult result;
  try {
    result = await Process.run(
      _ghPath,
      [
        'pr', 'list', '--repo', _repo, '--state', 'all', '--limit', '40',
        '--json', 'number,state,title,body,statusCheckRollup,mergedAt',
      ],
      // Windows decodes a subprocess with the system codepage unless told
      // otherwise, which turns every Korean character in a PR body into
      // mojibake and the whole response into unparseable JSON. Titles are
      // English, so this stayed invisible until bodies were read.
      stdoutEncoding: utf8,
    );
  } catch (_) {
    return _cache(_Gh(const [], ok: false));
  }
  if (result.exitCode != 0) return _cache(_Gh(const [], ok: false));

  final List<dynamic> rows;
  try {
    rows = jsonDecode(result.stdout as String) as List;
  } catch (e) {
    // A response we cannot read is a failed lookup, not a failed page: the
    // board still has work to show, and saying "gh 를 못 불렀습니다" is both
    // true and better than a 500 that shows nothing at all.
    stderr.writeln('board: could not parse gh output: $e');
    return _cache(_Gh(const [], ok: false));
  }

  final prs = <_Pr>[];
  for (final row in rows) {
    final map = row as Map<String, dynamic>;
    final rollup = (map['statusCheckRollup'] as List?) ?? const [];
    var checks = 'none';
    if (rollup.isNotEmpty) {
      final all = rollup.cast<Map<String, dynamic>>();
      final pending = all.any((c) => c['status'] != 'COMPLETED');
      final bad = all.any((c) => const {
            'FAILURE', 'CANCELLED', 'TIMED_OUT', 'ACTION_REQUIRED',
          }.contains(c['conclusion']));
      checks = bad ? 'red' : (pending ? 'pending' : 'green');
    }
    final merged = map['mergedAt'] as String?;
    prs.add(_Pr(
      (map['number'] as num).toInt(),
      map['state'] as String,
      _koOr(map['body'] as String? ?? '', map['title'] as String),
      checks,
      merged == null ? null : DateTime.tryParse(merged),
    ));
  }
  return _cache(_Gh(prs, ok: true));
}

/// The Korean line from the PR body if it carries one, else the English title.
String _koOr(String body, String title) {
  for (final line in body.split('\n')) {
    final t = line.trim();
    if (t.startsWith(_koTrailer)) {
      final ko = t.substring(_koTrailer.length).trim();
      if (ko.isNotEmpty) return ko;
    }
  }
  return title;
}

_Gh _cache(_Gh gh) {
  _ghCache = gh;
  _ghAt = DateTime.now();
  return gh;
}

// -------------------------------------------------------------------- git

/// One checkout: where it is, what branch it holds, how far it has drifted
/// from origin/master, and whether anything is uncommitted in it.
class _Checkout {
  _Checkout(this.path, this.branch, this.ahead, this.behind, this.dirty);

  final String path;
  final String branch;
  final int ahead;
  final int behind;
  final int dirty;

  /// Empty when there is nothing to say — an aligned, clean checkout needs no
  /// sentence, and printing one anyway is how a status line stops being read.
  String get trouble => [
        if (behind > 0) '$behind 뒤',
        if (ahead > 0) '$ahead 앞',
        if (dirty > 0) '커밋 안 된 파일 $dirty',
      ].join(' · ');
}

List<_Checkout>? _gitCache;
DateTime _gitAt = DateTime.fromMillisecondsSinceEpoch(0);

/// Reads every worktree of the repository, so "which checkout am I looking at
/// and is it current" stops being something you find out by being told it is
/// five commits behind.
Future<List<_Checkout>> _checkouts() async {
  if (_gitCache != null &&
      DateTime.now().difference(_gitAt).inSeconds < _ghCacheSeconds) {
    return _gitCache!;
  }
  String run(String dir, List<String> args) {
    try {
      final r = Process.runSync('git', ['-C', dir, ...args],
          stdoutEncoding: utf8);
      return r.exitCode == 0 ? (r.stdout as String).trim() : '';
    } catch (_) {
      return '';
    }
  }

  final list = run(_gitRoot, ['worktree', 'list', '--porcelain']);
  final out = <_Checkout>[];
  String? path;
  for (final line in const LineSplitter().convert(list)) {
    if (line.startsWith('worktree ')) {
      path = line.substring(9).trim();
    } else if (line.startsWith('branch ') && path != null) {
      final branch = line.substring(7).replaceFirst('refs/heads/', '').trim();
      final counts = run(path, [
        'rev-list', '--left-right', '--count', 'origin/master...HEAD',
      ]).split(RegExp(r'\s+'));
      final dirty = run(path, ['status', '--porcelain']);
      out.add(_Checkout(
        path,
        branch,
        counts.length > 1 ? (int.tryParse(counts[1]) ?? 0) : 0,
        counts.isNotEmpty ? (int.tryParse(counts[0]) ?? 0) : 0,
        dirty.isEmpty ? 0 : const LineSplitter().convert(dirty).length,
      ));
      path = null;
    }
  }
  _gitCache = out;
  _gitAt = DateTime.now();
  return out;
}

// ------------------------------------------------------------------ render

/// The only thing a waiting item's badge has to say is WHAT IT WAITS ON.
///
/// It used to say 「나중」 and 「게이트」 side by side, which are the same news
/// (not now) told two ways, and 「열림」 on everything else, which is the
/// section's name repeated on every row. What was missing is the one fact that
/// changes what to do about it: whose move is it.
///
/// `open` is deliberately absent — a ready item wears no badge at all, because
/// the section it sits in already said so.
const _stateLabels = <String, String>{
  'wip': '진행 중',
  'ask': '답 기다림',
  // 유저 2026-08-25: 「대기중의 지시대기는 사실상 상담대기니까 이름 상담대기로
  // 바꾸자」. 「지시 대기」는 유저가 명령을 안 내려서 멈춰 있다고 읽히는데,
  // 실제로 멈춰 있는 이유는 아직 이야기가 안 끝나서다 — 참고 사진을 기다리거나,
  // 상세를 더 듣기로 했거나, 별도 라운드로 미뤄 뒀거나.
  'gate': '상담 대기',
  'queue': '순서 대기',
  'mine': '내가 정리 중',
  'inbox': '분류 전',
};

/// Item states that mean "not startable yet". Anything else with no PR is
/// ready to go.
const _waiting = <String>{'ask', 'gate', 'queue', 'mine'};

String _esc(String s) => const HtmlEscape().convert(s);

String _render(List<_Entry> entries, _Gh gh, List<_Checkout> gits,
    {int landedPage = 1}) {
  // `deleted` joins `archived` as a state that stops a card being drawn. Two
  // words for two different endings, kept apart on purpose: 「archived」 is I
  // put this away, 「deleted」 is the user ticked it and it is finished. The
  // file keeps both lines either way.
  final alive =
      entries.where((e) => e.state != 'archived' && e.state != 'deleted').toList();
  // Laws are not work: they never appear as a card of their own, they attach
  // to the cards whose tag they name. Set before anything renders.
  _laws = alive.where((e) => e.kind == 'law').toList();
  // The question index, before anything renders — see [_byOrigin] for why it
  // reads `entries` and not `alive`.
  final byOrigin = <String, List<_Entry>>{};
  for (final e in entries) {
    if (e.kind != 'decision') continue;
    final (of, _) = _asks(e);
    if (of.isEmpty) continue;
    (byOrigin[of] ??= []).add(e);
  }
  for (final list in byOrigin.values) {
    list.sort((a, b) {
      final (_, x) = _asks(a);
      final (_, y) = _asks(b);
      return x.compareTo(y);
    });
  }
  _byOrigin = byOrigin;
  // ⚠️An ARCHIVED question no longer blocks — I put it away because it was
  // dealt with. Only a live, unanswered one holds the card.
  _asking = {
    for (final entry in byOrigin.entries)
      if (entry.value.any((q) =>
          q.answer == null && q.state != 'archived' && q.state != 'deleted'))
        entry.key,
  };
  final inbox = alive.where((e) => e.state == 'inbox').toList();
  // 답할 것 holds only what is still unanswered. An answered question leaves
  // for 분류 전 — see `/submit` for why that is the same section and not a
  // second one.
  final asks = alive
      .where((e) => e.kind == 'decision' && e.answer == null)
      .toList();
  final checks = alive.where((e) => e.kind == 'check' && e.answer == null).toList();

  final claimed = {for (final e in alive) if (e.pr != null) e.pr!: e};
  // 🚨A PR WHOSE CARD IS DEAD MUST NOT COME BACK AS A PLACEHOLDER.
  //
  // ⚠️Read from `entries`, not `alive` — the dead cards are precisely the ones
  // `alive` filtered out, so looking there finds nothing and the row returns
  // on the very next render. Measured, not reasoned: ticking a landing left
  // it on screen, which would have read as 「the tick does nothing」.
  //
  // Two ways to die and both count. `archived` is I put it away; `deleted` is
  // the user ticked it. And two ways to be named: a landing nobody claimed is
  // remembered by its `pr-N` id, a claimed one by the number its card holds.
  final buriedIds = <String>{};
  final buriedPrs = <int>{};
  for (final e in entries) {
    if (e.state != 'archived' && e.state != 'deleted') continue;
    buriedIds.add(e.id);
    if (e.pr != null) buriedPrs.add(e.pr!);
  }

  final now = <String>[];
  final fresh = <_Pr>[];
  for (final pr in gh.prs) {
    if (buriedPrs.contains(pr.number)) continue;
    final e = claimed[pr.number];
    if (e == null && buriedIds.contains('pr-${pr.number}')) continue;
    // 🚨A MERGE IS NOT A FINISH. If the card still lists something left, it
    // stays where the work is and never reaches 확인할 것 — a tick there
    // deletes the card, and the leftovers would go with it.
    if (e != null && e.rest.isNotEmpty && pr.state == 'MERGED') continue;
    // ⚠️A landing that was ticked is finished (its card carries `deleted` and
    // never reached `alive`); one that got a memo went back to 분류 전. Either
    // way it must not return to 확인할 것 every time the page opens.
    if (e?.answer != null) continue;
    if (pr.state == 'OPEN') {
      now.add(_prPanel(pr, e));
    } else if (pr.state == 'MERGED' && _isNews(pr)) {
      fresh.add(pr);
    }
  }
  fresh.sort((a, b) {
    final x = a.mergedAt, y = b.mergedAt;
    if (x == null) return y == null ? 0 : -1;
    if (y == null) return 1;
    return y.compareTo(x);
  });
  final pages = fresh.isEmpty ? 1 : (fresh.length + _landedPerPage - 1) ~/ _landedPerPage;
  final page = landedPage.clamp(1, pages);
  // 확인할 것 = the landings on this page, then the checks that have no PR.
  // The hand-written ones go LAST and are never paged away: there are few of
  // them, they are the ones that need a device, and a page-2 that hides them
  // is how a check waits a month.
  //
  // 🚨ONE SUBJECT, ONE ROW. Two different ways a row could double up, and both
  // are closed here rather than left to luck:
  //
  //  1. A record that is BOTH a `check` and the claimer of a PR would render
  //     once as a landing and again out of `checks` — `shown` stops that.
  //  2. A check written as the hands-on half of a landing would sit BESIDE the
  //     landing it belongs to. That one was real: C-tp1..C-tp6 are the device
  //     checks for the tool-preset round, whose PR was on this very list.
  //     `under` nests them inside it.
  //
  // ⚠️A check whose landing is on ANOTHER page falls through to standalone,
  // deliberately: it then shows exactly once on every page instead of
  // vanishing whenever its parent pages away. Never hide a check.
  final onPage = fresh.skip((page - 1) * _landedPerPage).take(_landedPerPage);
  final here = {for (final pr in onPage) pr.number};
  final subs = <int, List<_Entry>>{};
  for (final c in checks) {
    final u = c.under;
    if (u != null && here.contains(u)) (subs[u] ??= []).add(c);
  }
  final shown = <String>{};
  final toCheck = <String>[];
  for (final pr in onPage) {
    final e = claimed[pr.number] ?? _prEntry(pr);
    shown.add(e.id);
    final mine = subs[pr.number] ?? const <_Entry>[];
    shown.addAll(mine.map((s) => s.id));
    toCheck.add(_checkRow(e, pr: pr, subs: mine));
  }
  for (final c in checks) {
    if (shown.contains(c.id)) continue;
    toCheck.add(_checkRow(c));
  }

  final loose = alive
      .where((e) =>
          e.kind == 'item' &&
          e.state != 'inbox' &&
          // An answered item has been looked at and reported on; it belongs in
          // its own story now, not back in 착수 가능 claiming to be unstarted.
          e.answer == null &&
          // A claimed PR normally means the card is being CHECKED, not
          // started. Unless it still has leftovers — then this is exactly
          // where it belongs, with the merged part already in its story.
          (e.pr == null || !claimed.containsKey(e.pr) || e.rest.isNotEmpty))
      .toList();
  // Work can be underway before there is a PR to point at -- an investigation,
  // a round mid-flight. Without this those items sat in 착수 가능 claiming to
  // be unstarted, which is the one thing they are not.
  final underway = loose.where((e) => e.state == 'wip').toList();
  final rest = loose.where((e) => e.state != 'wip').toList();
  final ready = rest
      .where((e) => !_waiting.contains(e.state) && !_asking.contains(e.id))
      .toList();
  final waiting = rest
      .where((e) => _waiting.contains(e.state) || _asking.contains(e.id))
      .toList();
  now.addAll(underway.map(_itemPanel));

  final b = StringBuffer();
  b.writeln('<!doctype html><html><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '<title>Anicel 보드</title><style>${_css()}</style></head><body>');
  b.writeln('<div class="wrap">');
  b.write('<h1>Anicel 보드</h1>');
  b.write('<p class="stamp">분류 전 <b>${inbox.length}</b> · 답할 것 <b>${asks.length}</b>'
      ' · 확인할 것 <b>${fresh.length + checks.length}</b> · 지금 <b>${now.length}</b>'
      ' · 착수 가능 <b>${ready.length}</b> · 대기 <b>${waiting.length}</b>');
  if (!gh.ok) {
    b.write(' · <span class="warn">gh 를 못 불렀습니다 — PR 칸은 비어 있습니다</span>');
  }
  b.writeln('</p>');
  b.writeln('<p class="rule" id="ruleline">줄을 누르면 펼쳐집니다. '
      '메모 칸에 <b>스크린샷을 그대로 붙여넣을 수</b> 있습니다'
      '(Win+Shift+S → Ctrl+V).</p>');
  if (_badLines.isNotEmpty) {
    b.writeln('<p class="alarm">⚠️ 기록 파일에서 <b>${_badLines.length}줄</b>을 '
        '읽지 못했습니다 — 그 항목은 이 화면에 <b>없습니다</b>. '
        '줄 ${_badLines.join(', ')}</p>');
  }

  b.write(_intakeForm());
  b.write(_group('분류 전', inbox.length, '내가 읽고 분류한다', inbox.map(_itemPanel)));
  b.write(_group('답할 것', asks.length, '고르고 제출', asks.map(_askPanel)));
  // The refresh lives here because this is the only section it changes, and a
  // control parked away from what it affects is a control you have to remember
  // the meaning of.
  b.write(_group('지금', now.length, '', now,
      control: _ctl('<button class="ghost sm" title="PR 상태는 페이지를 열 때만 읽습니다. '
          '지금 다시 읽으려면 누르세요 — 이 칸만 갱신됩니다." '
          'onclick="refresh(event)">↻</button>')));
  b.write(_group('착수 가능', ready.length, '명령만 내리면 착수', ready.map(_itemPanel)));
  b.write(_group('대기 중', waiting.length, '배지가 무엇을 기다리는지 말한다',
      waiting.map(_itemPanel)));
  // ONE list (유저 2026-08-26). The count is the whole thing, not the page:
  // this section used to show a number that was really a cap, and that is
  // exactly what made it lie.
  b.write(_group('확인할 것', fresh.length + checks.length,
      '체크 = 문제 없음 · 메모 = 문제', toCheck,
      footer: _pager(fresh.length, page),
      control: _ctl('<button class="ghost sm" title="이 페이지의 모든 항목을 체크합니다" '
          'onclick="pickAll(event)">전체선택</button>'
          '<button class="ghost sm" title="체크한 항목을 목록에서 치웁니다" '
          'onclick="confirmPicked(event)">확인</button>')));
  b.write(_group('로컬 상태', gits.length, '', gits.map(_checkoutPanel)));

  b.writeln('<script>${_js()}</script>');
  b.writeln('</div></body></html>');
  return b.toString();
}

/// A section is always drawn, even empty.
///
/// Hiding it when the count is zero made the board's shape change under you --
/// 지금 vanished when nothing was in flight, and an empty PR section looked
/// identical to a broken `gh`. A heading that says 0 is information; a heading
/// that is absent is a question.
String _group(String title, int n, String why, Iterable<String> panels,
    {String control = '', String footer = ''}) {
  final b = StringBuffer();
  b.writeln('<details class="grp" open id="g-${_esc(title)}">'
      '<summary class="gh">'
      '<span class="gt">${_esc(title)}</span><span class="n">$n</span>'
      '${why.isEmpty ? '' : '<span class="why">${_esc(why)}</span>'}'
      '$control</summary>');
  b.writeln('<div class="stack">');
  if (n == 0) {
    b.writeln('<p class="none">없음</p>');
  }
  for (final p in panels) {
    b.writeln(p);
  }
  b.writeln(footer);
  b.writeln('</div></details>');
  return b.toString();
}

/// A group header's control cluster: STATUS FIRST, then the buttons.
///
/// The order is the whole point. `.ctl` is pushed to the right edge by
/// `margin-left:auto`, so the cluster grows leftward -- put the status text
/// after the buttons and every message ("1개 선택", "읽는 중…", "실패: …")
/// shoves them sideways under the reader's cursor. Put it first and the
/// buttons never move.
///
/// It is a function rather than two more string literals because both control
/// rows had the wrong order, written the same way twice. A law that lives in
/// one place cannot be half-applied by the next row that gets added.
String _ctl(String buttons) =>
    '<span class="ctl"><span class="state"></span>$buttons</span>';

/// How many landed rows fit on one page.
const _landedPerPage = 20;

/// The pager for the LANDED half of 확인할 것.
///
/// It is drawn even when there is only one page, and the count it shows is the
/// TOTAL rather than the page: a section that hides its own size is the thing
/// the eight-row cap was, and a control that appears only once the list is long
/// enough is a control nobody knows exists.
String _pager(int total, int page) {
  final pages = total <= _landedPerPage ? 1 : (total + _landedPerPage - 1) ~/ _landedPerPage;
  final b = StringBuffer('<div class="pager"><span class="pgn">$page / $pages</span>');
  for (var i = 1; i <= pages; i++) {
    final cls = i == page ? 'ghost sm on' : 'ghost sm';
    b.write('<a class="$cls" href="?landed=$i">$i</a>');
  }
  b.write('</div>');
  return b.toString();
}

/// The intake. Two buttons rather than a type dropdown, because the choice is
/// the whole classification a person can make while still mid-thought: this is
/// broken (feedback) or this would be good (idea). Everything else -- number,
/// title, which area it belongs to -- is sorted out later, on the board.
String _intakeForm() {
  return '''
<details class="p intake" id="c-intake">
<summary><span class="k">＋</span><span class="t">새 피드백 · 아이디어</span>
</summary>
<div class="body">
<textarea id="intake-text" rows="4"
 placeholder="떠오른 대로 적으세요. 번호와 제목은 제가 붙입니다.&#10;스크린샷은 Ctrl+V 로 그대로 붙여넣기."></textarea>
<div id="intake-shots" class="shots"></div>
<input type="text" id="intake-tag" placeholder="분야 (비워도 됩니다 — 제가 정리합니다)">
<div class="foot">
<button onclick="file('feedback')">피드백 — 지금 이게 잘못됐다</button>
<button class="alt" onclick="file('idea')">아이디어 — 이런 게 있으면 좋겠다</button>
<button class="ghost" onclick="file('draft')">임시저장 — 아직 정리 전</button>
<span class="state"></span></div>
</div></details>
''';
}

/// The chips that say something about STATE rather than subject, and the tint
/// each one gets (유저 2026-08-26: 「태그구분만 알기쉽게 잘 하자」).
///
/// 분류 전 is where this earns its keep: five different things arrive there —
/// new feedback, an idea, a draft, an answer to a question, and a hands-on
/// check that came back with a problem — and they need different work from
/// me. Read as a traffic light: red is broken, amber was reported, green is
/// answered, plain is a thought.
///
/// ⛔Subject tags (저장 · 렌더링 · 브러시 …) stay untinted on purpose. If
/// everything is coloured then nothing is, and the subject is the one thing
/// the section header cannot tell you.
const _chipTint = <String, String>{
  '실기 피드백': 'bad',
  '유저 피드백': 'bad',
  '피드백': 'run',
  '대답': 'ok',
};

String _head(String id, String title, List<String> tags, String badge, String cls,
    {String lead = '', String date = ''}) {
  final chips = tags.map((t) {
    final tint = _chipTint[t];
    return '<span class="chip${tint == null ? '' : ' $tint'}">'
        '${_esc(t)}</span>';
  }).join();
  final when = _day(date);
  // An empty badge renders nothing: a ready item is already labelled by the
  // section it sits in, and repeating that on every row is noise, not news.
  final mark = badge.isEmpty
      ? ''
      : '<span class="chip${cls.isEmpty ? '' : ' $cls'} badge">'
          '${_esc(badge)}</span>';
  return '<summary>$lead<span class="k">${_esc(id)}</span>'
      '<span class="t">${_esc(title)}</span>'
      '<span class="right">$chips$mark'
      '${when.isEmpty ? '' : '<span class="when">${_esc(when)}</span>'}'
      '</span></summary>';
}

/// `2026-08-26T00:36:17.5` → `08-26`. The year is dropped because every
/// record in this file shares it; the day is what anyone is actually asking.
String _day(String ts) {
  if (ts.length < 10) return '';
  return ts.substring(5, 10);
}

String _shotStrip(String id) {
  final shots = _shotsFor(id);
  if (shots.isEmpty) return '';
  final b = StringBuffer('<div class="shots">');
  for (final s in shots) {
    b.write('<a href="/shot/$s" target="_blank">'
        '<img src="/shot/$s" alt="${_esc(s)}"></a>');
  }
  b.write('</div>');
  return b.toString();
}

/// A decision id shaped `<원본>-Q<번호>` — the naming the user asked for
/// (2026-08-26: 「Q-layer-name이 아니라 패널이름-질문넘버. 예를들어 T14-Q1」).
///
/// 🎯Parsing it is what makes the link impossible to forget. A question named
/// `T14-Q1` IS bound to T14; there is no second field to fill in and no way
/// for the name and the binding to disagree. [_Entry.of] stays as the
/// override for the cards named before this convention existed.
final _qName = RegExp(r'^(.+)-Q(\d+)$');

/// Which card a question belongs to, and where it sits in that card's list.
(String, int) _asks(_Entry e) {
  final m = _qName.firstMatch(e.id);
  if (m != null) return (e.of.isEmpty ? m.group(1)! : e.of, int.parse(m.group(2)!));
  return (e.of, 0);
}

/// Every question, filed under the card that raised it.
///
/// ⚠️Built from ALL entries, archived ones included. A question I have already
/// acted on and put away is still part of its card's story, and dropping it
/// would take the ANSWER out of the panel the moment the answer got used —
/// which is the one moment it starts mattering. (Same shape as the bug where
/// a ticked landing came back: `alive` filters out precisely what you need.)
Map<String, List<_Entry>> _byOrigin = const {};

/// 🚨★★★Cards with a question still unanswered — they are NOT 착수 가능
/// (유저 2026-08-26: 「결정대기가 남아있으면 대기중항목인게 맞지않냐?」).
///
/// The law was already written — CLAUDE.md: 「⛔미결이 남은 칸은 착수 가능이
/// 아니다」 — and F-17 broke it the moment I raised F-17-Q1, because nothing
/// moved the card. **A law nobody can forget is one the code applies**, so
/// this is derived from the questions themselves rather than kept as a state
/// I would have to remember to set and, worse, remember to unset.
Set<String> _asking = const {};

/// 🚨THE WAY BACK TO THE CARD THAT ASKED (유저 2026-08-26: 「그 답할것패널에
/// 포인터? 내부에 태그같은거로서 질문이 생성된 패널을 표시해줌」).
///
/// A question torn out of its card is a question with no subject — that is
/// the same disease as a 확인할 것 row saying only 「T14」, one section over.
/// The link jumps to the origin AND opens it, because an anchor that lands on
/// a folded `<details>` looks like it did nothing.
String _origin(_Entry e) {
  final (of, _) = _asks(e);
  if (of.isEmpty) return '';
  return '<p class="d"><a class="chip link" href="#c-${_esc(of)}" '
      'onclick="jump(\'${_esc(of)}\');return false;">↑ ${_esc(of)} 에서 나온 질문</a></p>';
}

/// 🚨★★★THE OTHER HALF OF THE LINK — the card's own list of its questions
/// (유저 2026-08-26: 「답할것 발생할때마다 대기중 패널에 Q1 Q2 이렇게 항목
/// 만들어서 그거누르면 해당패널로 이동하게. 대답하면 그 항목에 대답 이식되고」).
///
/// ⛔NOT transplanted, and that is the improvement on the ask. Copying the
/// answer into the origin would put one fact in two records, and the day one
/// of them is edited they disagree — the failure this whole board keeps being
/// redesigned around. Rendered by reference, the card cannot show a stale
/// answer, because it is not holding one.
String _questions(_Entry e) {
  final mine = _byOrigin[e.id];
  if (mine == null || mine.isEmpty) return '';
  final b = StringBuffer();
  for (var i = 0; i < mine.length; i++) {
    final q = mine[i];
    final (_, n) = _asks(q);
    final label = 'Q${n == 0 ? i + 1 : n}';
    final answered = q.answer != null;
    final picked = answered
        ? q.options.firstWhere((o) => o['key'] == q.answer,
            orElse: () => <String, dynamic>{'label': q.answer})
        : const <String, dynamic>{};
    b.writeln('<details class="lg q">');
    b.writeln('<summary><span class="lgk">$label</span>'
        '<span class="lgp">${_esc(q.title)}</span>'
        '<span class="chip ${answered ? 'ok' : 'run'}">'
        '${answered ? '답함' : '대기'}</span></summary>');
    if (answered) {
      final said = '${picked['label'] ?? q.answer}';
      if (said.isNotEmpty && said != 'ok') {
        b.writeln('<p class="d"><b>→ ${_esc(said)}</b></p>');
      }
      if (q.answerNote.isNotEmpty) {
        b.writeln('<p class="d">${_esc(q.answerNote)}</p>');
      }
    } else if (q.why.isNotEmpty) {
      b.writeln('<p class="d">${_esc(q.why)}</p>');
    }
    // ⛔No link once the question is put away: its panel is no longer drawn,
    // and a link to a row that is not on the page does nothing when clicked,
    // which reads as broken rather than as finished. The row above already
    // carries the whole question and its answer, so nothing is lost by
    // dropping the link — that is the point of rendering by reference.
    final reachable = q.state != 'archived' && q.state != 'deleted';
    b.writeln(reachable
        ? '<p class="d"><a class="chip link" href="#c-${_esc(q.id)}" '
            'onclick="jump(\'${_esc(q.id)}\');return false;">'
            '${_esc(q.id)} 로 이동 →</a></p>'
        : '<p class="d mono">${_esc(q.id)} · 처리 완료</p>');
    b.writeln('</details>');
  }
  return b.toString();
}

String _askPanel(_Entry d) {
  final b = StringBuffer();
  b.writeln('<details class="p ask" id="c-${_esc(d.id)}" data-kind="decision">');
  // ⛔No 미제출 badge. Every card in this section is unanswered by
  // construction now — an answered one leaves for 분류 전 — so the badge was
  // labelling the section on every row (유저 2026-08-26: 「답할것도 미제출태그
  // 필요없어질테니」).
  b.writeln(_head(d.id, d.title, d.tags, '', '', date: d.updated));
  b.writeln('<div class="body">');
  b.writeln(_origin(d));
  if (d.where.isNotEmpty) {
    b.writeln('<p class="d"><b>화면에서</b> — ${_esc(d.where)}</p>');
  }
  if (d.why.isNotEmpty) {
    b.writeln('<p class="d"><b>왜 막혔나</b> — ${_esc(d.why)}</p>');
  }
  // A decision about an area is bound by that area's laws too -- an option
  // that a law already forbids is not an option, and finding that out after
  // the answer is submitted wastes the round.
  b.writeln(_care(d));
  for (final o in d.options) {
    final key = '${o['key']}';
    final rec = d.recommend == key;
    b.write('<label class="opt${rec ? ' rec' : ''}">');
    b.write('<input type="radio" name="ans-${_esc(d.id)}" value="${_esc(key)}">');
    b.write('<span class="ob"><b>${_esc(key)}. ${_esc('${o['label']}')}</b>');
    if (rec) b.write('<span class="chip ok">추천</span>');
    if (o['what'] != null) b.write('<span class="what">${_esc('${o['what']}')}</span>');
    if (o['cost'] != null) {
      b.write('<span class="cost">대가 — ${_esc('${o['cost']}')}</span>');
    }
    b.writeln('</span></label>');
  }
  b.write('<label class="opt other">');
  b.write('<input type="radio" name="ans-${_esc(d.id)}" value="other">');
  b.writeln('<span class="ob"><b>다른 안 / 더 물어볼 것</b>'
      '<span class="what">아래 칸에 적어 주세요</span></span></label>');
  b.writeln('<textarea rows="2" placeholder="메모 — 왜 그렇게 정했는지 '
      '(스크린샷은 Ctrl+V)"></textarea>');
  b.writeln(_shotStrip(d.id));
  b.writeln('<div class="foot"><button onclick="send(\'${_esc(d.id)}\')">제출</button>'
      '<span class="state"></span></div>');
  b.writeln('</div></details>');
  return b.toString();
}

/// ONE row of 확인할 것, whether it arrived as a landed PR or as a check
/// somebody wrote (유저 2026-08-26: 「그런것도 싹 하나의 확인목록으로 병합.
/// 다만 pr인지아닌지는 구분하고싶으니 태그로」).
///
/// 🚨The two lists were the same list wearing two costumes. 최근 착지 came from
/// `gh` for free but had NOWHERE to report a result; 실기 확인 had the memo box
/// but had to be hand-written — so one change got written twice, once as an
/// item note and again as a check card. 유저: 「둘다 뭐가 작업됬는지 하나하나
/// 확인하는용이라서. 그래서 너가 두군데 써넣는것도 힘들거고」.
///
/// ⇒ One panel, both affordances, and the DIFFERENCE says itself without a
/// word for it: a landing carries its `#1236` badge, a hand-written one
/// carries [_kHandsOn] and no badge.
///
/// The two answers stay distinct because they mean different things and cost
/// different amounts (유저 확정): the TICK is "봤고 문제 없음" and sweeps many
/// rows at once through 확인; the MEMO is "문제가 있다" and is written per row.
String _checkRow(_Entry c, {_Pr? pr, List<_Entry> subs = const []}) {
  final landed = pr != null;
  // The badge says WHICH PR; nothing needs to say THAT it is a PR. A
  // hands-on row needs no badge at all — every row in this section is
  // unchecked by definition,
  // so 「미확인」 was labelling the section, not the row.
  final badge = landed ? '#${pr.number}' : '';
  final b = StringBuffer();
  // The sub-count goes in the HEAD because a nested check is invisible until
  // the row is opened, and a check nobody can see is a check nobody does.
  // ⛔No 머지 chip on a landed row: the `#1236` badge beside it already says
  // it came from a PR, and the number says WHICH (유저 2026-08-26: 「머지태그도
  // 솔직히 #1236 이런 pr태그있으니까 필요없을듯」). Only the hand-written half
  // needs naming, because it is the half with no badge.
  //
  // ⛔And no 공정 N count. It was a number nobody acts on — the story is right
  // there when the row opens, and a chip that only says 「there is some」 is
  // the same noise as a badge repeating its section.
  final tags = [
    if (!landed) _kHandsOn,
    if (subs.isNotEmpty) '실기 ${subs.length}',
    ...c.tags,
  ];
  // data-kind is what `send` writes back, and it is `check` on BOTH shapes:
  // the result of looking at a thing is a check result whatever put it on the
  // list. ⚠️It is also what routes the submit: a tick deletes the card, a
  // memo sends it back to 분류 전 (see `/submit`).
  b.writeln('<details class="p chk" id="c-${_esc(c.id)}" data-kind="check">');
  b.writeln(_head(
    c.id,
    c.title,
    tags,
    badge,
    landed ? 'ok' : 'run',
    lead: '<input type="checkbox" class="pick" value="${_esc(c.id)}" '
        'onclick="event.stopPropagation()">',
    date: c.updated,
  ));
  b.writeln('<div class="body">');
  if (c.how.isNotEmpty) {
    b.writeln('<p class="d"><b>이렇게 본다</b> — ${_esc(c.how)}</p>');
  }
  if (c.why.isNotEmpty) {
    b.writeln('<p class="d"><b>왜 중요한가</b> — ${_esc(c.why)}</p>');
  }
  // 🚨THE WHOLE POINT OF THIS SECTION IS HERE. A row reaches 확인할 것 knowing
  // only its own id, and 「T14」 tells nobody what T14 was — the feedback that
  // started it, the answers along the way, what the fix turned out to be. All
  // of that is what the card carried on its way here, so all of it comes with.
  b.writeln(_story(c));
  // Its questions come with it to 확인할 것 — 「무엇을 물었고 무엇으로 정했나」
  // is half of knowing whether the thing in front of you is right.
  b.writeln(_questions(c));
  b.writeln(_care(c));
  if (landed) {
    b.writeln('<p class="d"><a href="https://github.com/$_repo/pull/'
        '${pr.number}" target="_blank">PR #${pr.number} 열기 →</a></p>');
  }
  b.writeln('<textarea rows="2" placeholder="문제가 있으면 적어 주세요 — 비워 두면 OK '
      '(스크린샷은 Ctrl+V)"></textarea>');
  b.writeln(_shotStrip(c.id));
  b.writeln('<div class="foot"><button onclick="send(\'${_esc(c.id)}\')">제출</button>'
      '<span class="state"></span></div>');
  // The hands-on checks that belong to this landing, nested inside it. Each
  // keeps its own id, its own box and its own 제출 — the merge is about where
  // a row SITS, not about answering six things with one click.
  for (final s in subs) {
    b.writeln(_checkRow(s));
  }
  b.writeln('</div></details>');
  return b.toString();
}

/// The tag for a 확인할 것 row that no PR produced. Its opposite needs no tag:
/// a landing already wears the PR number, and 「머지」 beside 「#1236」 was the
/// same fact twice on one line.
const String _kHandsOn = '실기';

/// A stand-in for a PR that no board item ever claimed — a landing the records
/// know nothing about. It has the PR's own title and nothing else, which is
/// exactly what 최근 착지 showed for those before.
_Entry _prEntry(_Pr pr) => _Entry('pr-${pr.number}', 'item')..title = pr.title;

String _itemPanel(_Entry e) {
  // No badge for a ready item, and none for the inbox either: both are already
  // named by the section they sit in. The tag (피드백 / 아이디어 / 임시) is the
  // part that actually differs between rows.
  final inbox = e.state == 'inbox';
  // 대기 중 promises that 「배지가 무엇을 기다리는지 말한다」, and an unanswered
  // question outranks whatever the state says: it is the thing actually
  // holding the card, and it is the one the user can clear.
  final badge = _asking.contains(e.id)
      ? '답 대기'
      : (e.state == 'open' || inbox) ? '' : (_stateLabels[e.state] ?? e.state);
  // 분류 전 now receives three different arrivals, and which one a row is
  // decides what I do with it. The chip says so on the row (유저 2026-08-26:
  // 「분류전으로 옮기고 대답 태그 붙이면」). ⚠️Plain feedback and ideas already
  // carry their own tag from intake, so only the returning kinds need one.
  final arrival = switch (e.kind) {
    'decision' => '대답',
    'check' => '실기 피드백',
    // An item only 「arrives」 if the user wrote on it — a plain working card
    // has nothing new to announce.
    _ => e.answer != null ? '유저 피드백' : '',
  };
  // The user's own writing is not editable once it is an ANSWER — editing it
  // would rewrite what they said, which is the one thing this whole redesign
  // exists to stop.
  // ⚠️`answer == null` too: an item that came BACK carrying feedback is not a
  // half-finished filing to correct, it is something to read. Showing it in an
  // edit box would offer to rewrite what the user just said.
  final editable = inbox && e.kind == 'item' && e.answer == null;
  final b = StringBuffer();
  // data-kind drives what `send` writes back. `item` so a memo on a working
  // card is filed as feedback and lands in 분류 전, exactly like one left on
  // a 확인할 것 row — ⛔and NOT as `check`, which would delete the card if the
  // box were submitted empty.
  b.writeln('<details class="p${inbox ? ' box' : ''}" id="c-${_esc(e.id)}"'
      ' data-kind="item">');
  b.writeln(_head(
      e.id,
      e.title,
      [
        if (arrival.isNotEmpty) arrival,
        // ⚠️Says the PR landed AND that the card did not finish with it —
        // without this the row looks unstarted while its branch is merged.
        if (e.rest.isNotEmpty && e.pr != null) '#${e.pr} 일부',
        ...e.tags,
      ],
      badge,
      '',
      date: e.updated));
  b.writeln('<div class="body">');
  b.writeln(_origin(e));
  if (editable) {
    // Still editable, because a filing made mid-thought is usually wrong in
    // some small way and the moment to fix it is when you notice.
    b.writeln('<textarea rows="4">'
        '${_esc(e.said.isEmpty ? e.note : e.said)}</textarea>');
    b.writeln(_shotStrip(e.id));
    b.writeln('<div class="foot">'
        '<button onclick="save(\'${_esc(e.id)}\')">저장</button>'
        '<button class="ghost" onclick="purge(\'${_esc(e.id)}\')">삭제</button>'
        '<span class="state"></span></div>');
  } else {
    // First thing in the panel, above the history: what is still owed. It is
    // why this card is here and not in 확인할 것.
    if (e.rest.isNotEmpty) {
      b.writeln('<p class="d rest"><b>남은 것</b> — ${_esc(e.rest)}</p>');
    }
    b.writeln(_story(e));
    b.writeln(_questions(e));
    b.writeln(_care(e));
    b.writeln(_shotStrip(e.id));
    // 🚨EVERY CARD TAKES FEEDBACK, not just the ones in 확인할 것 (유저
    // 2026-08-26, looking at a card that had just moved OUT of that section:
    // 「이거 해당칸에 피드백첨부하면되겟지?」).
    //
    // The memo box used to live only where the board happened to be asking a
    // question. But a card is an organism the whole way down — noticing
    // something about work that has not shipped yet is the CHEAPEST moment to
    // say so, and making that depend on which list the card is in is the same
    // 「write it in two places」 problem in a different coat.
    b.writeln('<textarea rows="2" placeholder="여기에 피드백 — 원문 그대로 '
        '남습니다 (스크린샷은 Ctrl+V)"></textarea>');
    b.writeln('<div class="foot">'
        '<button onclick="send(\'${_esc(e.id)}\')">피드백 제출</button>'
        '<span class="state"></span></div>');
  }
  b.writeln('</div></details>');
  return b.toString();
}

/// Laws in force for this card, found by tag.
///
/// KEYED BY TAG, NOT COPIED ONTO CARDS. The same law governs every card in its
/// area -- eleven of them carry 렌더링 -- and writing it onto each one would
/// rebuild the exact problem this move was meant to end: one fact kept in
/// several places, drifting apart the first time one of them is edited. A law
/// is one record; the cards it governs name it by tag.
///
/// It is also not `note`. `note` says why this card sits where it sits; a law
/// says what breaks if you start without knowing. Merged, the status line
/// disappears under a caution several times its length.
String _care(_Entry e) {
  final hits = _laws.where((l) => e.tags.contains(l.tag) && l.care.isNotEmpty);
  if (hits.isEmpty) return '';
  final b = StringBuffer();
  for (final l in hits) {
    b.write('<div class="care"><span class="carelabel">손대기 전에</span>'
        '<span>${_esc(l.care)}</span></div>');
  }
  return b.toString();
}

/// Area laws, refreshed on every render from the records file.
List<_Entry> _laws = const [];

String _prPanel(_Pr pr, _Entry? e) {
  final id = e?.id ?? 'pr-${pr.number}';
  final title = e == null || e.title.isEmpty ? pr.title : e.title;
  final merged = pr.state == 'MERGED';
  final badge = merged
      ? '머지 #${pr.number}'
      : switch (pr.checks) {
          'pending' => 'CI 중 #${pr.number}',
          'red' => 'CI 빨강 #${pr.number}',
          _ => 'CI 초록 #${pr.number}',
        };
  final cls = merged || pr.checks == 'green'
      ? 'ok'
      : (pr.checks == 'red' ? 'bad' : 'run');
  final b = StringBuffer();
  b.writeln('<details class="p" id="c-${_esc(id)}">');
  // A landed item is confirmed by ticking it, not by opening it: the whole
  // point of the row is that you already know what it was.
  final tick = merged
      ? '<input type="checkbox" class="pick" value="${_esc(id)}" '
          'onclick="event.stopPropagation()">'
      : '';
  b.writeln(_head(id, title, e?.tags ?? const [], badge, cls,
      lead: tick, date: e?.updated ?? ''));
  b.writeln('<div class="body">');
  if (e != null && e.note.isNotEmpty) {
    b.writeln('<p class="d">${_esc(e.note)}</p>');
  }
  b.writeln('<p class="d"><a href="https://github.com/$_repo/pull/${pr.number}" '
      'target="_blank">PR #${pr.number} 열기 →</a></p>');
  b.writeln('</div></details>');
  return b.toString();
}

/// One checkout, said plainly enough to decide from.
///
/// The badge is the branch, because that is the thing you are choosing between;
/// the trouble line only appears when there IS trouble. A checkout that is
/// aligned and clean says 정렬됨 and nothing else — "깨끗하다" and "최신이다" are
/// different claims, and conflating them is how a main checkout sat five
/// commits behind while looking fine.
String _checkoutPanel(_Checkout c) {
  final name = c.path.split(RegExp(r'[\\/]')).last;
  final trouble = c.trouble;
  final b = StringBuffer();
  b.writeln('<details class="p" id="c-git-${_esc(name)}">');
  b.writeln(_head(name, trouble.isEmpty ? '정렬됨 · 깨끗' : trouble,
      const [], c.branch, trouble.isEmpty ? 'ok' : 'run'));
  b.writeln('<div class="body">');
  b.writeln('<p class="d mono">${_esc(c.path)}</p>');
  b.writeln('<p class="d">브랜치 <b>${_esc(c.branch)}</b> · '
      'origin/master 기준 <b>${c.behind}</b> 뒤 / <b>${c.ahead}</b> 앞 · '
      '커밋 안 된 파일 <b>${c.dirty}</b></p>');
  b.writeln('</div></details>');
  return b.toString();
}

/// 🚨★★★THE CARD'S OWN STORY — every word it has ever carried, oldest first,
/// one collapsible entry each (유저 2026-08-26).
///
/// The newest entry stands OPEN and the rest are folded. That is the whole
/// trick: a card reads exactly as it used to at a glance — current status,
/// nothing else in the way — and the history is one click down instead of
/// gone. 「패널내용이 길어지는건 감수하고」 does not have to mean the panel is
/// long on arrival.
///
/// ⛔The summary line carries a preview of the entry, not just its date. A
/// row of eight 「08-24」 buttons is a filing cabinet with no labels; you would
/// have to open all of them to find the one you wanted, which is the same
/// problem as having none.
/// What to call an entry that never named its own 공정.
///
/// ⛔A row labelled 「·」 is worse than an unlabelled one — it looks like a
/// rendering fault (유저 2026-08-26: 「접기펼치기행이 . 으로 표시될떄가 많아서」).
/// Two honest fallbacks and no dot: the FIRST entry of a card that came in
/// through the intake form is the user filing it, and its intake tag already
/// says which kind of filing it was. Everything else with no stage is my own
/// working note.
String _stageName(_Entry e, int i) {
  final at = e.log[i].at;
  if (at.isNotEmpty) return at;
  if (i == 0) {
    if (e.tags.contains('피드백')) return '유저 피드백';
    if (e.tags.contains('아이디어')) return '유저 아이디어';
    if (e.tags.contains('임시')) return '임시 메모';
  }
  return '작업 기록';
}

String _story(_Entry e) {
  if (e.log.isEmpty) return '<p class="d">메모 없음.</p>';
  final b = StringBuffer();
  for (var i = 0; i < e.log.length; i++) {
    final entry = e.log[i];
    final newest = i == e.log.length - 1;
    final flat = entry.text.replaceAll('\n', ' ');
    final peek = flat.length > 44 ? '${flat.substring(0, 44)}…' : flat;
    final mine = _stageName(e, i);
    b.writeln('<details class="lg'
        '${entry.byUser || mine.startsWith('유저') ? ' says' : ''}'
        '${newest ? ' open' : ''}">');
    b.writeln('<summary><span class="lgk">${_esc(mine)}</span>'
        '<span class="lgp">${_esc(peek)}</span>'
        '<span class="when">${_esc(_day(entry.ts))}</span></summary>');
    b.writeln('<p class="d">${_esc(entry.text)}</p>');
    b.writeln('</details>');
  }
  return b.toString();
}

/// Paste-to-attach is wired at the document, not per textarea, so every memo
/// box on the page gets it -- including ones added later. A screenshot is the
/// cheapest thing a person can give and the most expensive thing to describe
/// in words, so it should never be the box that does not take one.
String _js() => r'''
var queued = [];
function stateOf(el){ return el.querySelector('.state'); }

async function post(url, body, el){
  stateOf(el).textContent = '저장 중…';
  const r = await fetch(url, {method:'POST', body: JSON.stringify(body)});
  if(!r.ok) throw new Error(r.status);
  return r.json();
}
function send(id){
  const c = document.getElementById('c-'+id);
  const r = c.querySelector('input[name="ans-'+id+'"]:checked');
  const t = c.querySelector('textarea');
  const answer = r ? r.value : '';
  const memo = t ? (t.value||'').trim() : '';
  if(c.dataset.kind === 'decision' && !answer && !memo){
    stateOf(c).textContent = '고르거나 메모를 적어 주세요'; return;
  }
  // ⛔An empty memo on a working card is not a tick — there is nothing here to
  // tick. Only 확인할 것 rows carry that meaning.
  if(c.dataset.kind === 'item' && !memo){
    stateOf(c).textContent = '적을 내용이 있어야 제출됩니다'; return;
  }
  post('/submit', {id:id, kind:c.dataset.kind, answer:answer||'ok', memo:memo}, c)
    .then(()=>redraw(c.id))
    .catch(e=>stateOf(c).textContent = '실패: '+e.message);
}
// An anchor onto a folded <details> scrolls to a closed row and looks like a
// dead link. Open it first, then scroll, then flash it so the eye lands.
function jump(id){
  const c = document.getElementById('c-'+id);
  // ⚠️Silence here reads as a broken link. Say so instead — the row is not on
  // the page, which is information, not a failure.
  if(!c){ alert(id + ' 는 지금 화면에 없습니다 (보관됐거나 다른 페이지).'); return; }
  c.open = true;
  c.scrollIntoView({behavior:'smooth', block:'center'});
  c.classList.add('lit');
  setTimeout(()=>c.classList.remove('lit'), 1400);
}
function drop(id){
  const c = document.getElementById('c-'+id);
  post('/dismiss', {id:id}, c)
    .then(()=>redraw())
    .catch(e=>stateOf(c).textContent = '실패: '+e.message);
}
function save(id){
  const c = document.getElementById('c-'+id);
  post('/edit', {id:id, text:(c.querySelector('textarea').value||'')}, c)
    .then(()=>redraw(c.id))
    .catch(e=>stateOf(c).textContent = '실패: '+e.message);
}
function purge(id){
  const c = document.getElementById('c-'+id);
  if(!confirm(id + ' 을(를) 완전히 지웁니다. 번호도 다시 쓰입니다.')) return;
  post('/purge', {id:id}, c)
    .then(()=>redraw())
    .catch(e=>stateOf(c).textContent = '실패: '+e.message);
}
// Redraws every section from the server WITHOUT reloading the page.
//
// There is no auto-refresh on this board and never was -- no timer, no meta
// refresh. What there was is worse: every action called location.reload(), and
// a reload empties every textarea on the page. Paste a screenshot into a card
// while writing a note and the note is gone, which is exactly the thing you
// least want a notes board to do. Measured before the fix: type into the
// intake box, reload, both the text and the tag come back empty.
//
// It also felt like the scroll position was lost. The browser does restore
// scrollY -- but every open panel closes on reload, the page collapses to a
// fraction of its height, and the restored offset lands nowhere near what you
// were reading.
//
// So: fetch the page, swap the sections, and put back the three things a
// person had invested in it -- what they typed, what they had open, where they
// were. Nothing here is a timer; it runs only when an action asks for it.
// `skipId` is the card whose fields must NOT be restored -- the one whose own
// submit caused this redraw. Everywhere else the person's text wins, including
// over a value the server rendered: an inbox card arrives with its saved note
// already in the box, and someone halfway through rewriting it holds the newer
// version. Letting the server win there silently reverted their edit, which a
// first attempt at this did.
function redraw(skipId, done){
  const typed = {}, opened = [];
  // Open state covers groups AND cards; fields are read from cards only.
  // A group is a <details> too, so scanning every <details> for fields picked
  // up each card's box a second time under the GROUP's key -- and that copy
  // ignored skipId, so it wrote the stale draft straight back over the value
  // the server had just returned.
  document.querySelectorAll('details').forEach(function(d){
    if(d.id && d.open) opened.push(d.id);
  });
  document.querySelectorAll('details.p').forEach(function(d){
    if(!d.id || d.id === skipId) return;
    d.querySelectorAll('textarea, input[type=text]').forEach(function(f, i){
      if(f.value) typed[d.id + '#' + i] = f.value;
    });
  });
  const y = window.scrollY;
  return fetch('/', {cache:'no-store'})
    .then(r=>r.text())
    .then(html=>{
      const doc = new DOMParser().parseFromString(html, 'text/html');
      doc.querySelectorAll('.grp').forEach(function(fresh){
        const live = document.getElementById(fresh.id);
        if(live) live.replaceWith(fresh);
      });
      const s = doc.querySelector('.stamp');
      if(s && document.querySelector('.stamp')){
        document.querySelector('.stamp').replaceWith(s);
      }
      opened.forEach(function(id){
        const d = document.getElementById(id);
        if(d) d.open = true;
      });
      document.querySelectorAll('details.p').forEach(function(d){
        if(!d.id) return;
        d.querySelectorAll('textarea, input[type=text]').forEach(function(f, i){
          const v = typed[d.id + '#' + i];
          if(v) f.value = v;
        });
      });
      // Thumbnails of shots pasted but not yet submitted live only in `queued`.
      const strip = document.getElementById('intake-shots');
      if(strip && queued.length){
        queued.forEach(function(d){
          const img = document.createElement('img');
          img.src = d;
          strip.appendChild(img);
        });
      }
      window.scrollTo(0, y);
      if(done) done();
    });
}
// Swaps just the 지금 section rather than reloading: everything else on the
// page is unaffected by a PR lookup, and a full reload throws away every panel
// you had open to read.
function swapSection(id, done){
  return fetch('/', {cache:'no-store'})
    .then(r=>r.text())
    .then(html=>{
      const doc = new DOMParser().parseFromString(html, 'text/html');
      const fresh = doc.getElementById(id);
      const live = document.getElementById(id);
      if(fresh && live){ live.replaceWith(fresh); }
      const s = doc.querySelector('.stamp');
      if(s){ document.querySelector('.stamp').replaceWith(s); }
      if(done) done();
    });
}
function refresh(ev){
  // The button lives inside a <summary>, so without this the click also folds
  // the section it was meant to update.
  ev.preventDefault(); ev.stopPropagation();
  const c = ev.target.closest('.ctl');
  stateOf(c).textContent = '읽는 중…';
  fetch('/refresh', {method:'POST', body:'{}'})
    .then(()=>swapSection('g-지금'))
    .catch(e=>stateOf(c).textContent = '실패: '+e.message);
}
function pickAll(ev){
  ev.preventDefault(); ev.stopPropagation();
  const c = ev.target.closest('.ctl');
  // This page only -- the other pages are not in the document, so there is
  // nothing here that could tick a row the reader has not seen.
  const boxes = [...c.closest('.grp').querySelectorAll('.pick')];
  const turnOn = boxes.some(b => !b.checked);
  boxes.forEach(b => b.checked = turnOn);
  stateOf(c).textContent = turnOn ? boxes.length + '개 선택' : '';
}
function confirmPicked(ev){
  ev.preventDefault(); ev.stopPropagation();
  const c = ev.target.closest('.ctl');
  const ids = [...c.closest('.grp').querySelectorAll('.pick:checked')].map(x=>x.value);
  if(ids.length === 0){ stateOf(c).textContent = '체크한 게 없습니다'; return; }
  post('/dismiss', {ids:ids}, c)
    .then(()=>redraw())
    .catch(e=>stateOf(c).textContent = '실패: '+e.message);
}
function file(kind){
  const c = document.getElementById('c-intake');
  const text = (document.getElementById('intake-text').value||'').trim();
  if(!text && queued.length === 0){
    stateOf(c).textContent = '내용을 적거나 스크린샷을 붙여넣어 주세요'; return;
  }
  post('/intake', {kind:kind, text:text,
                   tag:(document.getElementById('intake-tag').value||'').trim()}, c)
    .then(async res => {
      for(const data of queued){
        await fetch('/shot', {method:'POST',
          body: JSON.stringify({id:res.id, data:data})});
      }
      queued = [];
      // The intake card is not inside any group, so a redraw cannot reset it.
      // What was just filed has to be cleared here or it sits there looking
      // unfiled and gets typed over or submitted twice.
      document.getElementById('intake-text').value = '';
      document.getElementById('intake-tag').value = '';
      document.getElementById('intake-shots').innerHTML = '';
      redraw('c-intake');
    })
    .catch(e=>stateOf(c).textContent = '실패: '+e.message);
}

document.addEventListener('paste', function(e){
  const ta = e.target;
  if(!ta || ta.tagName !== 'TEXTAREA') return;
  const items = (e.clipboardData && e.clipboardData.items) || [];
  for(const it of items){
    if(it.type.indexOf('image/') !== 0) continue;
    e.preventDefault();
    const reader = new FileReader();
    reader.onload = function(){
      const card = ta.closest('details');
      const id = card.id.replace(/^c-/, '');
      if(id === 'intake'){
        queued.push(reader.result);
        const strip = document.getElementById('intake-shots');
        const img = document.createElement('img');
        img.src = reader.result;
        strip.appendChild(img);
        stateOf(card).textContent = '스크린샷 ' + queued.length + '장 — 제출하면 같이 올라갑니다';
      } else {
        stateOf(card).textContent = '스크린샷 올리는 중…';
        fetch('/shot', {method:'POST',
          body: JSON.stringify({id:id, data:reader.result})})
          .then(()=>redraw())
          .catch(err=>stateOf(card).textContent = '실패: '+err.message);
      }
    };
    reader.readAsDataURL(it.getAsFile());
  }
});
''';

String _css() => '''
:root{--ink:#16181d;--ink2:#3d434f;--ink3:#6b7280;--bg:#f7f6f3;--card:#fff;
--line:#e2e0da;--line2:#cfccc4;--ok:#0f6f5c;--okbg:#eaf5f2;--run:#8a5a10;
--runbg:#f6edd9;--bad:#9a3412;--badbg:#fdeee7;--live:#1d4ed8;
--mono:ui-monospace,"Cascadia Mono",Menlo,monospace;
--sans:"Segoe UI",-apple-system,"Noto Sans KR",system-ui,sans-serif}
@media(prefers-color-scheme:dark){:root{
--ink:#eceef2;--ink2:#b9bfcb;--ink3:#838b99;--bg:#14161a;--card:#1c1f25;
--line:#2b2f37;--line2:#3a3f49;--ok:#5fc9ae;--okbg:#142824;--run:#e0b25e;
--runbg:#332912;--bad:#e08a63;--badbg:#2c1a12;--live:#86aaf5}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font-family:var(--sans);
font-size:15px;line-height:1.55;word-break:keep-all}
.wrap{max-width:820px;margin:0 auto;padding:28px 16px 72px}
h1{font-size:22px;margin:0 0 3px;letter-spacing:-.02em}
h2{font-size:11.5px;text-transform:uppercase;letter-spacing:.1em;
color:var(--ink3);margin:26px 0 7px;display:flex;align-items:baseline;gap:8px}
.gh .n{font-family:var(--mono);color:var(--ink);font-size:13px}
.gh .why{font-size:12px;color:var(--ink3)}
.stamp{font-family:var(--mono);font-size:12px;color:var(--ink3);margin:0}
.warn{color:var(--bad)}
.rule{font-size:12.5px;color:var(--ink3);margin:8px 0 16px;
display:flex;align-items:center;gap:8px;flex-wrap:wrap}
.grp{margin:22px 0 0}
.gh{display:flex;align-items:baseline;gap:8px;cursor:pointer;list-style:none;
padding:4px 0 8px;user-select:none}
.gh::-webkit-details-marker{display:none}
.gt{font-size:11.5px;text-transform:uppercase;letter-spacing:.1em;
color:var(--ink3);font-weight:700}
.grp[open] .gt{color:var(--ink2)}
.none{font-size:12.5px;color:var(--ink3);margin:0;padding:6px 2px}
.alarm{background:var(--badbg);color:var(--bad);border:1px solid var(--bad);
border-radius:5px;padding:9px 12px;font-size:13px;margin:0 0 14px}
.ctl{margin-left:auto;display:flex;align-items:center;gap:7px;flex:none}
.pick{flex:none;margin:0}
.pager{display:flex;align-items:center;gap:6px;flex-wrap:wrap;padding:8px 2px 2px}
.pgn{font-size:12px;color:var(--ink3);margin-right:4px}
.pager a{text-decoration:none;min-width:26px;text-align:center}
.pager a.on{border-color:var(--live);color:var(--live)}
.mono{font-family:var(--mono);font-size:11.5px;word-break:break-all}
.stack{display:flex;flex-direction:column;gap:5px}
.p{background:var(--card);border:1px solid var(--line);border-radius:5px}
.p[open]{border-color:var(--line2)}
.ask{border-left:3px solid var(--run)}
.chk{border-left:3px solid var(--live)}
.box{border-left:3px solid var(--run)}
.intake{border:1px dashed var(--line2)}
summary{display:flex;align-items:center;gap:10px;padding:10px 13px;
cursor:pointer;list-style:none;user-select:none}
summary::-webkit-details-marker{display:none}
summary:hover{background:var(--bg)}
.k{font-family:var(--mono);font-size:11.5px;color:var(--ink3);flex:none;
min-width:74px}
.t{font-weight:600;flex:1;min-width:0}
.right{display:flex;gap:5px;align-items:center;flex:none}
.chip{font-family:var(--mono);font-size:10.5px;padding:2px 7px;border-radius:3px;
white-space:nowrap;border:1px solid var(--line2);color:var(--ink3)}
.chip.ok{background:var(--okbg);color:var(--ok);border-color:transparent}
.chip.run{background:var(--runbg);color:var(--run);border-color:transparent}
.chip.bad{background:var(--badbg);color:var(--bad);border-color:transparent}
.body{padding:2px 14px 13px;border-top:1px solid var(--line);
display:flex;flex-direction:column;gap:7px}
.body>*:first-child{margin-top:10px}
.d{font-size:13px;color:var(--ink2);margin:0;white-space:pre-wrap}
/* The date rides the HEAD row, last of everything on the right (유저
   2026-08-26: 「패널내부가아니라 타이틀쪽 제일오른쪽, 태그오른쪽에」). Mono and
   fixed-width so the column of dates stays straight down a list whose chips
   are all different widths, and quiet enough to read as a margin note. */
.when{font-family:var(--mono);font-size:10.5px;color:var(--ink3);
white-space:nowrap;flex:none;min-width:38px;text-align:right}
/* One entry of a card's story. Indented under a hairline so a long history
   reads as one thing rather than as many panels; the summary carries the
   stage, the date and a preview so the row is findable while folded. */
.lg{border-left:2px solid var(--line2);padding-left:9px;margin:0}
.lg+.lg{margin-top:5px}
.lg>summary{display:flex;gap:8px;align-items:baseline;padding:2px 0;
cursor:pointer;list-style:none}
.lg>summary::-webkit-details-marker{display:none}
.lg>summary:hover{background:var(--bg)}
/* The stage name leads and is wide enough for 「유저 아이디어」 without
   wrapping; the date sits hard right so the dates line up down an open card
   whatever the stage names are (유저 2026-08-26: 「날짜는 ... 오른쪽정렬로」). */
.lgk{font-size:11px;color:var(--ink2);font-weight:600;flex:none;min-width:82px}
.lgp{font-size:12px;color:var(--ink3);overflow:hidden;text-overflow:ellipsis;
white-space:nowrap;flex:1;min-width:0}
.lg>summary>.when{margin-left:auto}
/* 「누가 말한거고 어떤 문장인지」 — the user's own stages carry a warmer rail
   and darker text so the eye can drop down an open card and find their words
   without reading the labels. ⛔The stage name already says who; this only
   makes it scannable. */
/* 남은 것 leads the panel and is the reason the card is not in 확인할 것, so
   it reads as a claim on attention rather than as another note. */
.rest{color:var(--run)}
.lg.says{border-left-color:var(--run)}
.lg.says>summary>.lgk{color:var(--run)}
.lg.says>.d{color:var(--ink)}
.lg[open]>summary .lgp{visibility:hidden}
.lg>.d{margin:3px 0 7px}
/* A question row: same rail as a story entry because it IS part of the
   story, tinted so the two kinds of entry do not read as one list. */
.lg.q{border-left-color:var(--run)}
.lg.q>summary .chip{flex:none;margin-left:auto}
a.chip.link{text-decoration:none;color:var(--ink2)}
a.chip.link:hover{background:var(--bg)}
/* The flash a jump leaves behind, so the eye finds where it landed. */
.p.lit{outline:2px solid var(--run);outline-offset:1px}
.care{display:flex;gap:8px;align-items:flex-start;background:var(--runbg);
border-left:3px solid var(--run);border-radius:0 5px 5px 0;padding:8px 10px;
font-size:12.5px;color:var(--ink2);white-space:pre-wrap}
.carelabel{flex:none;font-weight:600;color:var(--run)}
.opt{display:flex;gap:9px;align-items:flex-start;padding:8px 10px;
border:1px solid var(--line);border-radius:4px;cursor:pointer}
.opt.rec{border-color:var(--ok)}
.opt.other{border-style:dashed}
.opt input{margin-top:4px;flex:none}
.ob{display:flex;flex-direction:column;gap:2px;min-width:0}
.ob .chip{align-self:flex-start;margin-top:2px}
.what{font-size:12.5px;color:var(--ink2)}
.cost{font-size:12px;color:var(--ink3)}
/* type-scoped on purpose: a bare `input` selector also hits the radios, and
   width:100% + padding turned every option into a full-width box with its
   label crushed into a one-character column. */
textarea,input[type="text"]{width:100%;background:var(--bg);color:var(--ink);
border:1px solid var(--line);border-radius:4px;padding:7px 9px;
font-family:var(--sans);font-size:13px}
textarea{resize:vertical}
.shots{display:flex;gap:6px;flex-wrap:wrap}
.shots img{max-height:120px;border:1px solid var(--line2);border-radius:4px;
cursor:zoom-in}
.foot{display:flex;align-items:center;gap:8px;flex-wrap:wrap}
button{font-family:var(--sans);font-size:13px;font-weight:600;padding:6px 14px;
border-radius:4px;border:1px solid var(--ok);background:var(--okbg);
color:var(--ok);cursor:pointer}
button:hover{background:var(--ok);color:var(--card)}
button.alt{border-color:var(--live);background:transparent;color:var(--live)}
button.alt:hover{background:var(--live);color:var(--card)}
button.sm{padding:2px 9px;font-size:11.5px;font-weight:500}
button.ghost{border-color:var(--line2);background:transparent;color:var(--ink3)}
button.ghost:hover{border-color:var(--bad);color:var(--bad);background:transparent}
.state{font-size:12px;color:var(--ink3)}
a{color:var(--live)}
@media(max-width:560px){summary{flex-wrap:wrap}.k{min-width:0}
.t{flex:1 0 100%;order:3}}
''';
