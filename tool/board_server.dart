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
        _append({
          'kind': body['kind'] ?? 'decision',
          'id': body['id'],
          'answer': body['answer'] ?? '',
          'answerNote': body['memo'] ?? '',
          'ts': _now(),
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
        _append({
          'kind': 'item',
          'id': body['id'],
          'title': first.length > 70 ? '${first.substring(0, 70)}…' : first,
          'note': text,
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
  final (prefix, label) = switch (kind) {
    'idea' => ('I', '아이디어'),
    'draft' => ('M', '임시'),
    _ => ('F', '피드백'),
  };
  final id = _nextId(prefix);
  final firstLine = text.split('\n').first;
  _append({
    'kind': 'item',
    'id': id,
    'title': firstLine.isEmpty
        ? '(스크린샷만)'
        : (firstLine.length > 70 ? '${firstLine.substring(0, 70)}…' : firstLine),
    'note': text,
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

class _Entry {
  _Entry(this.id, this.kind);

  final String id;
  String kind;
  String title = '';
  List<String> tags = const [];
  String state = 'open';
  String note = '';

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
    if (json['title'] != null) e.title = json['title'] as String;
    if (json['state'] != null) e.state = json['state'] as String;
    if (json['note'] != null) e.note = json['note'] as String;
    if (json['care'] != null) e.care = json['care'] as String;
    if (json['tag'] != null) e.tag = json['tag'] as String;
    if (json['where'] != null) e.where = json['where'] as String;
    if (json['why'] != null) e.why = json['why'] as String;
    if (json['how'] != null) e.how = json['how'] as String;
    if (json['recommend'] != null) e.recommend = json['recommend'] as String;
    if (json['answer'] != null) e.answer = json['answer'] as String;
    if (json['answerNote'] != null) e.answerNote = json['answerNote'] as String;
    if (json['pr'] != null) e.pr = (json['pr'] as num).toInt();
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
  final alive = entries.where((e) => e.state != 'archived').toList();
  // Laws are not work: they never appear as a card of their own, they attach
  // to the cards whose tag they name. Set before anything renders.
  _laws = alive.where((e) => e.kind == 'law').toList();
  final inbox = alive.where((e) => e.state == 'inbox').toList();
  final asks = alive.where((e) => e.kind == 'decision' && e.answer == null).toList();
  final checks = alive.where((e) => e.kind == 'check' && e.answer == null).toList();
  // ANYTHING answered is settled, not just the two kinds that used to be
  // askable. A landed ITEM can now be answered too (a memo on a 확인할 것
  // row), and without this it would answer into silence.
  final settled = alive.where((e) => e.answer != null).toList();

  final claimed = {for (final e in alive) if (e.pr != null) e.pr!: e};
  final gone = entries.where((e) => e.state == 'archived').map((e) => e.id).toSet();

  final now = <String>[];
  final fresh = <_Pr>[];
  for (final pr in gh.prs) {
    final e = claimed[pr.number];
    if (e == null && gone.contains('pr-${pr.number}')) continue;
    // ⚠️An ANSWERED landing is done being looked at — it lives in 정해진 것
    // now and must not come back to the list every time the page opens.
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
  final toCheck = [
    for (final pr in fresh.skip((page - 1) * _landedPerPage).take(_landedPerPage))
      _checkRow(claimed[pr.number] ?? _prEntry(pr), pr: pr),
    for (final c in checks) _checkRow(c),
  ];

  final loose = alive
      .where((e) =>
          e.kind == 'item' &&
          e.state != 'inbox' &&
          // An answered item has been looked at and reported on; it belongs in
          // 정해진 것, not back in 착수 가능 claiming to be unstarted.
          e.answer == null &&
          (e.pr == null || !claimed.containsKey(e.pr)))
      .toList();
  // Work can be underway before there is a PR to point at -- an investigation,
  // a round mid-flight. Without this those items sat in 착수 가능 claiming to
  // be unstarted, which is the one thing they are not.
  final underway = loose.where((e) => e.state == 'wip').toList();
  final rest = loose.where((e) => e.state != 'wip').toList();
  final ready = rest.where((e) => !_waiting.contains(e.state)).toList();
  final waiting = rest.where((e) => _waiting.contains(e.state)).toList();
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
  b.write(_group('정해진 것', settled.length, '', settled.map(_settledPanel)));
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
<span class="right"><span class="chip run badge">여기에 던져두세요</span></span></summary>
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

String _head(String id, String title, List<String> tags, String badge, String cls,
    {String lead = ''}) {
  final chips = tags.map((t) => '<span class="chip">${_esc(t)}</span>').join();
  // An empty badge renders nothing: a ready item is already labelled by the
  // section it sits in, and repeating that on every row is noise, not news.
  final mark = badge.isEmpty
      ? ''
      : '<span class="chip $cls badge">${_esc(badge)}</span>';
  return '<summary>$lead<span class="k">${_esc(id)}</span>'
      '<span class="t">${_esc(title)}</span>'
      '<span class="right">$chips$mark</span></summary>';
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

String _askPanel(_Entry d) {
  final b = StringBuffer();
  b.writeln('<details class="p ask" id="c-${_esc(d.id)}" data-kind="decision">');
  b.writeln(_head(d.id, d.title, d.tags, '미제출', 'run'));
  b.writeln('<div class="body">');
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
/// ⇒ One panel, both affordances, and the DIFFERENCE says itself in a tag:
/// [_kMerged] for a row that came from a PR, [_kHandsOn] for one that did not.
///
/// The two answers stay distinct because they mean different things and cost
/// different amounts (유저 확정): the TICK is "봤고 문제 없음" and sweeps many
/// rows at once through 확인; the MEMO is "문제가 있다" and is written per row.
String _checkRow(_Entry c, {_Pr? pr}) {
  final landed = pr != null;
  // The TAG says what kind of row this is; the badge says WHICH PR. Saying
  // 「머지」 in both was the same word twice on one line. A hands-on row needs
  // no badge at all — every row in this section is unchecked by definition,
  // so 「미확인」 was labelling the section, not the row.
  final badge = landed ? '#${pr.number}' : '';
  final b = StringBuffer();
  // data-kind is what `send` writes back, and it is `check` on BOTH shapes:
  // the result of looking at a thing is a check result whatever put it on the
  // list. ⚠️It is also what makes an answered row land in 정해진 것.
  b.writeln('<details class="p chk" id="c-${_esc(c.id)}" data-kind="check">');
  b.writeln(_head(
    c.id,
    c.title,
    [landed ? _kMerged : _kHandsOn, ...c.tags],
    badge,
    landed ? 'ok' : 'run',
    lead: '<input type="checkbox" class="pick" value="${_esc(c.id)}" '
        'onclick="event.stopPropagation()">',
  ));
  b.writeln('<div class="body">');
  if (c.how.isNotEmpty) {
    b.writeln('<p class="d"><b>이렇게 본다</b> — ${_esc(c.how)}</p>');
  }
  // A landed row's note is what the work WAS — the same sentence that used to
  // sit in 최근 착지, kept because "무엇이 바뀌었나" is half of knowing what to
  // look at.
  if (landed && c.note.isNotEmpty) {
    b.writeln('<p class="d">${_esc(c.note)}</p>');
  }
  if (c.why.isNotEmpty) {
    b.writeln('<p class="d"><b>왜 중요한가</b> — ${_esc(c.why)}</p>');
  }
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
  b.writeln('</div></details>');
  return b.toString();
}

/// The tag that says where a 확인할 것 row came from. Two values, and the
/// board never invents a third: either a PR landed or it did not.
const String _kMerged = '머지';
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
  final badge =
      (e.state == 'open' || inbox) ? '' : (_stateLabels[e.state] ?? e.state);
  final b = StringBuffer();
  b.writeln('<details class="p${inbox ? ' box' : ''}" id="c-${_esc(e.id)}">');
  b.writeln(_head(e.id, e.title, e.tags, badge, ''));
  b.writeln('<div class="body">');
  if (inbox) {
    // Still editable, because a filing made mid-thought is usually wrong in
    // some small way and the moment to fix it is when you notice.
    b.writeln('<textarea rows="4">${_esc(e.note)}</textarea>');
    b.writeln(_shotStrip(e.id));
    b.writeln('<div class="foot">'
        '<button onclick="save(\'${_esc(e.id)}\')">저장</button>'
        '<button class="ghost" onclick="purge(\'${_esc(e.id)}\')">삭제</button>'
        '<span class="state"></span></div>');
  } else {
    b.writeln(e.note.isEmpty
        ? '<p class="d">메모 없음.</p>'
        : '<p class="d">${_esc(e.note)}</p>');
    b.writeln(_care(e));
    b.writeln(_shotStrip(e.id));
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
  b.writeln(_head(id, title, e?.tags ?? const [], badge, cls, lead: tick));
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

String _settledPanel(_Entry d) {
  final picked = d.options.firstWhere(
    (o) => o['key'] == d.answer,
    orElse: () => <String, dynamic>{'label': d.answer},
  );
  final label = d.kind == 'check'
      ? (d.answerNote.isEmpty ? 'OK' : '피드백')
      : '${picked['label']}';
  final b = StringBuffer();
  b.writeln('<details class="p" id="c-${_esc(d.id)}">');
  b.writeln(_head(d.id, d.title, d.tags, '정해짐', 'ok'));
  b.writeln('<div class="body"><p class="d"><b>→ ${_esc(label)}</b></p>');
  if (d.answerNote.isNotEmpty) {
    b.writeln('<p class="d">${_esc(d.answerNote)}</p>');
  }
  b.writeln(_shotStrip(d.id));
  b.writeln('<div class="foot"><button class="ghost" '
      'onclick="drop(\'${_esc(d.id)}\')">삭제</button>'
      '<span class="state"></span></div></div></details>');
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
  post('/submit', {id:id, kind:c.dataset.kind, answer:answer||'ok', memo:memo}, c)
    .then(()=>redraw(c.id))
    .catch(e=>stateOf(c).textContent = '실패: '+e.message);
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
