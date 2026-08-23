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

Future<void> main(List<String> args) async {
  _recordsPath = _flag(args, '--records') ?? '';
  _ghPath = _flag(args, '--gh') ?? 'gh';
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
        _append({
          'kind': 'item',
          'id': body['id'],
          'state': 'archived',
          'ts': _now(),
        });
      case '/intake':
        newId = _intake(body);
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
  req.response
    ..headers.contentType = ContentType.html
    ..headers.set('Cache-Control', 'no-store')
    ..write(_render(_readRecords(File(_recordsPath)), await _prs()));
  await req.response.close();
}

String _now() => DateTime.now().toIso8601String();

void _append(Map<String, dynamic> line) {
  File(_recordsPath)
      .writeAsStringSync('${jsonEncode(line)}\n', mode: FileMode.append);
  stdout.writeln('board: recorded ${line['id']}');
}

/// Files a new idea or piece of feedback and hands back the id it was given.
///
/// The id is allocated here rather than asked for: the person filing it is
/// mid-thought, and "what should I call this" is exactly the friction that
/// makes people not write things down. Classification comes later -- it lands
/// in `inbox`, which is a section on the board and not a synonym for done.
String _intake(Map<String, dynamic> body) {
  final idea = body['kind'] == 'idea';
  final text = '${body['text'] ?? ''}'.trim();
  final tag = '${body['tag'] ?? ''}'.trim();
  final id = _nextId(idea ? 'I' : 'F');
  final firstLine = text.split('\n').first;
  _append({
    'kind': 'item',
    'id': id,
    'title': firstLine.length > 70 ? '${firstLine.substring(0, 70)}…' : firstLine,
    'note': text,
    'tags': [idea ? '아이디어' : '피드백', if (tag.isNotEmpty) tag],
    'state': 'inbox',
    'ts': _now(),
  });
  return id;
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
List<_Entry> _readRecords(File file) {
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
      continue;
    }
    final kind = json['kind'] as String? ?? '';
    if (kind == 'meta') continue;
    final id = json['id'] as String?;
    if (id == null) {
      stderr.writeln('board: line $lineNo has no id, skipped');
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
  return [for (final id in order) byId[id]!];
}

// --------------------------------------------------------------------- gh

class _Pr {
  _Pr(this.number, this.state, this.title, this.checks);

  final int number;
  final String state;
  final String title;
  final String checks;
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
        '--json', 'number,state,title,body,statusCheckRollup',
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
    prs.add(_Pr(
      (map['number'] as num).toInt(),
      map['state'] as String,
      _koOr(map['body'] as String? ?? '', map['title'] as String),
      checks,
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
  'ask': '답 기다림',
  'gate': '지시 대기',
  'queue': '순서 대기',
  'mine': '내가 정리 중',
  'inbox': '분류 전',
};

/// Item states that mean "not startable yet". Anything else with no PR is
/// ready to go.
const _waiting = <String>{'ask', 'gate', 'queue', 'mine'};

String _esc(String s) => const HtmlEscape().convert(s);

String _render(List<_Entry> entries, _Gh gh) {
  final alive = entries.where((e) => e.state != 'archived').toList();
  final inbox = alive.where((e) => e.state == 'inbox').toList();
  final asks = alive.where((e) => e.kind == 'decision' && e.answer == null).toList();
  final checks = alive.where((e) => e.kind == 'check' && e.answer == null).toList();
  final settled = alive
      .where((e) => (e.kind == 'decision' || e.kind == 'check') && e.answer != null)
      .toList();

  final claimed = {for (final e in alive) if (e.pr != null) e.pr!: e};
  final gone = entries.where((e) => e.state == 'archived').map((e) => e.id).toSet();

  final now = <String>[];
  final landed = <String>[];
  for (final pr in gh.prs) {
    final e = claimed[pr.number];
    if (e == null && gone.contains('pr-${pr.number}')) continue;
    final panel = _prPanel(pr, e);
    if (pr.state == 'OPEN') {
      now.add(panel);
    } else if (pr.state == 'MERGED' && landed.length < 8) {
      landed.add(panel);
    }
  }

  final loose = alive
      .where((e) =>
          e.kind == 'item' &&
          e.state != 'inbox' &&
          (e.pr == null || !claimed.containsKey(e.pr)))
      .toList();
  final ready = loose.where((e) => !_waiting.contains(e.state)).toList();
  final waiting = loose.where((e) => _waiting.contains(e.state)).toList();

  final b = StringBuffer();
  b.writeln('<!doctype html><html><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '<title>Anicel 보드</title><style>${_css()}</style></head><body>');
  b.writeln('<div class="wrap">');
  b.write('<h1>Anicel 보드</h1>');
  b.write('<p class="stamp">분류 전 <b>${inbox.length}</b> · 답할 것 <b>${asks.length}</b>'
      ' · 실기 확인 <b>${checks.length}</b> · 지금 <b>${now.length}</b>'
      ' · 착수 가능 <b>${ready.length}</b> · 대기 <b>${waiting.length}</b>');
  if (!gh.ok) {
    b.write(' · <span class="warn">gh 를 못 불렀습니다 — PR 칸은 비어 있습니다</span>');
  }
  b.writeln('</p>');
  b.writeln('<p class="rule">줄을 누르면 펼쳐집니다. 메모 칸에 <b>스크린샷을 그대로 붙여넣을 수</b> '
      '있습니다(Win+Shift+S → Ctrl+V).</p>');

  b.write(_intakeForm());
  b.write(_group('분류 전', inbox.length, '내가 읽고 분류한다', inbox.map(_itemPanel)));
  b.write(_group('답할 것', asks.length, '고르고 제출', asks.map(_askPanel)));
  b.write(_group('실기 확인', checks.length, '메모가 비면 OK', checks.map(_checkPanel)));
  b.write(_group('지금', now.length, 'GitHub 이 답한다', now));
  b.write(_group('착수 가능', ready.length, '명령만 내리면 착수', ready.map(_itemPanel)));
  b.write(_group('대기 중', waiting.length, '배지가 무엇을 기다리는지 말한다',
      waiting.map(_itemPanel)));
  b.write(_group('최근 착지', landed.length, '확인했으면 삭제', landed));
  b.write(_group('정해진 것', settled.length, '', settled.map(_settledPanel)));

  b.writeln('<script>${_js()}</script>');
  b.writeln('</div></body></html>');
  return b.toString();
}

String _group(String title, int n, String why, Iterable<String> panels) {
  if (n == 0) return '';
  final b = StringBuffer();
  b.writeln('<h2>${_esc(title)} <span class="n">$n</span>'
      '${why.isEmpty ? '' : '<span class="why">${_esc(why)}</span>'}</h2>');
  b.writeln('<div class="stack">');
  for (final p in panels) {
    b.writeln(p);
  }
  b.writeln('</div>');
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
<input id="intake-tag" placeholder="분야 (비워도 됩니다 — 제가 정리합니다)">
<div class="foot">
<button onclick="file('feedback')">피드백 — 지금 이게 잘못됐다</button>
<button class="alt" onclick="file('idea')">아이디어 — 이런 게 있으면 좋겠다</button>
<span class="state"></span></div>
</div></details>
''';
}

String _head(String id, String title, List<String> tags, String badge, String cls) {
  final chips = tags.map((t) => '<span class="chip">${_esc(t)}</span>').join();
  // An empty badge renders nothing: a ready item is already labelled by the
  // section it sits in, and repeating that on every row is noise, not news.
  final mark = badge.isEmpty
      ? ''
      : '<span class="chip $cls badge">${_esc(badge)}</span>';
  return '<summary><span class="k">${_esc(id)}</span>'
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

String _checkPanel(_Entry c) {
  final b = StringBuffer();
  b.writeln('<details class="p chk" id="c-${_esc(c.id)}" data-kind="check">');
  b.writeln(_head(c.id, c.title, c.tags, '미확인', 'run'));
  b.writeln('<div class="body">');
  if (c.how.isNotEmpty) {
    b.writeln('<p class="d"><b>이렇게 본다</b> — ${_esc(c.how)}</p>');
  }
  if (c.why.isNotEmpty) {
    b.writeln('<p class="d"><b>왜 중요한가</b> — ${_esc(c.why)}</p>');
  }
  b.writeln('<textarea rows="2" placeholder="문제가 있으면 적어 주세요 — 비워 두면 OK '
      '(스크린샷은 Ctrl+V)"></textarea>');
  b.writeln(_shotStrip(c.id));
  b.writeln('<div class="foot"><button onclick="send(\'${_esc(c.id)}\')">제출</button>'
      '<span class="state"></span></div>');
  b.writeln('</div></details>');
  return b.toString();
}

String _itemPanel(_Entry e) {
  // Ready items carry no state badge at all; only the inbox is coloured,
  // because it is the one state that is asking someone to do something.
  final badge = e.state == 'open' ? '' : (_stateLabels[e.state] ?? e.state);
  final cls = e.state == 'inbox' ? 'run' : '';
  final b = StringBuffer();
  b.writeln('<details class="p${e.state == 'inbox' ? ' box' : ''}" '
      'id="c-${_esc(e.id)}">');
  b.writeln(_head(e.id, e.title, e.tags, badge, cls));
  b.writeln('<div class="body">');
  b.writeln(e.note.isEmpty
      ? '<p class="d">메모 없음.</p>'
      : '<p class="d">${_esc(e.note)}</p>');
  b.writeln(_shotStrip(e.id));
  b.writeln('</div></details>');
  return b.toString();
}

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
  b.writeln(_head(id, title, e?.tags ?? const [], badge, cls));
  b.writeln('<div class="body">');
  if (e != null && e.note.isNotEmpty) {
    b.writeln('<p class="d">${_esc(e.note)}</p>');
  }
  b.writeln('<p class="d"><a href="https://github.com/$_repo/pull/${pr.number}" '
      'target="_blank">PR #${pr.number} 열기 →</a></p>');
  if (merged) {
    b.writeln('<div class="foot"><button class="ghost" '
        'onclick="drop(\'${_esc(id)}\')">확인했음 — 삭제</button>'
        '<span class="state"></span></div>');
  }
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
    .then(()=>location.reload())
    .catch(e=>stateOf(c).textContent = '실패: '+e.message);
}
function drop(id){
  const c = document.getElementById('c-'+id);
  post('/dismiss', {id:id}, c)
    .then(()=>location.reload())
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
      location.reload();
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
          .then(()=>location.reload())
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
h2 .n{font-family:var(--mono);color:var(--ink)}
h2 .why{text-transform:none;letter-spacing:0;font-size:12px}
.stamp{font-family:var(--mono);font-size:12px;color:var(--ink3);margin:0}
.warn{color:var(--bad)}
.rule{font-size:12.5px;color:var(--ink3);margin:8px 0 16px}
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
.opt{display:flex;gap:9px;align-items:flex-start;padding:8px 10px;
border:1px solid var(--line);border-radius:4px;cursor:pointer}
.opt.rec{border-color:var(--ok)}
.opt.other{border-style:dashed}
.opt input{margin-top:4px;flex:none}
.ob{display:flex;flex-direction:column;gap:2px;min-width:0}
.ob .chip{align-self:flex-start;margin-top:2px}
.what{font-size:12.5px;color:var(--ink2)}
.cost{font-size:12px;color:var(--ink3)}
textarea,input{width:100%;background:var(--bg);color:var(--ink);
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
button.ghost{border-color:var(--line2);background:transparent;color:var(--ink3)}
button.ghost:hover{border-color:var(--bad);color:var(--bad);background:transparent}
.state{font-size:12px;color:var(--ink3)}
a{color:var(--live)}
@media(max-width:560px){summary{flex-wrap:wrap}.k{min-width:0}
.t{flex:1 0 100%;order:3}}
''';
