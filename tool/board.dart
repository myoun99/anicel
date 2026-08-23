// The work board is a RENDERING, not a document.
//
// It used to be a hand-edited page, which meant every fact lived twice: once
// where the work happened, once on the board. The second copy is the one that
// goes stale, and it went stale constantly -- chips saying "next" for work
// that had already merged, a count of 48 unverified items that was really 10.
//
// So the board stopped being written. It is now derived from two inputs and
// nothing else:
//
//   1. a records file (JSONL) -- one line per fact, append-only, later lines
//      win. It lives beside the memory notes, so recording a fact and
//      updating the board are the same act.
//   2. `gh` -- the live state of any PR a record names. Nobody types
//      "merged" anywhere; the chip is whatever GitHub says right now.
//
// It is an instrument, so here is what it looks like when it lies:
//   - a record with a `pr` GitHub has never heard of  -> the chip renders as
//     the raw state string instead of a colour, which reads as broken
//   - `gh` unavailable (offline, not logged in)       -> every PR chip falls
//     back to "PR #n" with no state, and the header says so. It never
//     invents a state.
//   - a malformed JSONL line                          -> the line number is
//     printed to stderr and the line is skipped; the page still renders.
//     Silence would be the dangerous outcome here, so it is never silent.
//
// Usage:
//   dart run tool/board.dart --records <file.jsonl> --out <file.html>
//   dart run tool/board.dart --records <f> --out <f> --no-gh   # offline
//
// The records file is deliberately NOT in this repository: the repository is
// public and the board is not.
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final records = _flag(args, '--records');
  final out = _flag(args, '--out');
  if (records == null || out == null) {
    stderr.writeln(
      'usage: dart run tool/board.dart --records <file.jsonl> --out <file.html>',
    );
    exit(2);
  }

  final entries = _readRecords(File(records));
  final prs = args.contains('--no-gh')
      ? const <int, _Pr>{}
      : await _pullPrStates(_flag(args, '--gh') ?? 'gh');

  File(out).writeAsStringSync(_render(entries, prs, ghRan: !args.contains('--no-gh')));

  final decisions = entries.where((e) => e.kind == 'decision' && e.answer == null).length;
  stdout.writeln('board: ${entries.length} records, $decisions awaiting an answer -> $out');
}

String? _flag(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
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
  int? pr;
  List<Map<String, dynamic>> options = const [];
  String? recommend;
  String? answer;
  String answerNote = '';
  String ts = '';
}

/// Folds the append-only log into current state: a later line with the same id
/// overwrites only the fields it names, so "this item now has a PR" is one
/// short line rather than a restatement of the whole record.
List<_Entry> _readRecords(File file) {
  if (!file.existsSync()) {
    stderr.writeln('records file not found: ${file.path}');
    exit(2);
  }
  final byId = <String, _Entry>{};
  final order = <String>[];
  var lineNo = 0;
  for (final line in file.readAsLinesSync()) {
    lineNo++;
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    Map<String, dynamic> json;
    try {
      json = jsonDecode(trimmed) as Map<String, dynamic>;
    } catch (_) {
      stderr.writeln('board: line $lineNo is not valid JSON, skipped');
      continue;
    }
    final kind = json['kind'] as String? ?? '';
    if (kind == 'meta') {
      continue;
    }
    final id = json['id'] as String?;
    if (id == null) {
      stderr.writeln('board: line $lineNo has no id, skipped');
      continue;
    }
    final entry = byId.putIfAbsent(id, () {
      order.add(id);
      return _Entry(id, kind);
    });
    if (kind.isNotEmpty) {
      entry.kind = kind;
    }
    if (json['title'] != null) entry.title = json['title'] as String;
    if (json['state'] != null) entry.state = json['state'] as String;
    if (json['note'] != null) entry.note = json['note'] as String;
    if (json['where'] != null) entry.where = json['where'] as String;
    if (json['why'] != null) entry.why = json['why'] as String;
    if (json['ts'] != null) entry.ts = json['ts'] as String;
    if (json['recommend'] != null) entry.recommend = json['recommend'] as String;
    if (json['answer'] != null) entry.answer = json['answer'] as String;
    if (json['answerNote'] != null) entry.answerNote = json['answerNote'] as String;
    if (json['pr'] != null) entry.pr = (json['pr'] as num).toInt();
    if (json['tags'] != null) {
      entry.tags = (json['tags'] as List).map((t) => '$t').toList();
    }
    if (json['options'] != null) {
      entry.options = (json['options'] as List)
          .map((o) => Map<String, dynamic>.from(o as Map))
          .toList();
    }
  }
  return [for (final id in order) byId[id]!];
}

// --------------------------------------------------------------------- gh

class _Pr {
  _Pr(this.state, this.checks);

  /// OPEN / MERGED / CLOSED, verbatim from GitHub.
  final String state;

  /// green / red / pending / none — folded from the check rollup.
  final String checks;
}

Future<Map<int, _Pr>> _pullPrStates(String gh) async {
  ProcessResult result;
  try {
    result = await Process.run(gh, [
      'pr',
      'list',
      '--repo',
      'myoun99/anicel',
      '--state',
      'all',
      '--limit',
      '100',
      '--json',
      'number,state,statusCheckRollup',
    ]);
  } catch (_) {
    stderr.writeln('board: could not run `$gh` — PR chips will have no state');
    return const {};
  }
  if (result.exitCode != 0) {
    stderr.writeln('board: gh exited ${result.exitCode} — PR chips will have no state');
    return const {};
  }
  final out = <int, _Pr>{};
  for (final row in jsonDecode(result.stdout as String) as List) {
    final map = row as Map<String, dynamic>;
    final rollup = (map['statusCheckRollup'] as List?) ?? const [];
    var checks = 'none';
    if (rollup.isNotEmpty) {
      final any = rollup.cast<Map<String, dynamic>>();
      final pending = any.any((c) => c['status'] != 'COMPLETED');
      final bad = any.any((c) => const {
            'FAILURE',
            'CANCELLED',
            'TIMED_OUT',
            'ACTION_REQUIRED',
          }.contains(c['conclusion']));
      checks = bad ? 'red' : (pending ? 'pending' : 'green');
    }
    out[(map['number'] as num).toInt()] = _Pr(map['state'] as String, checks);
  }
  return out;
}

// ------------------------------------------------------------------ render

const _stateLabels = <String, String>{
  'open': '열림',
  'wip': '진행',
  'blocked': '결정 대기',
  'idea': '아이디어',
  'later': '나중',
  'gate': '유저 게이트',
  'mine': '내가 정리 중',
  'done': '착지',
};

String _esc(String s) => const HtmlEscape().convert(s);

String _render(List<_Entry> entries, Map<int, _Pr> prs, {required bool ghRan}) {
  final decisions = entries.where((e) => e.kind == 'decision').toList();
  final open = decisions.where((e) => e.answer == null).toList();
  final answered = decisions.where((e) => e.answer != null).toList();
  final items = entries.where((e) => e.kind == 'item').toList();

  bool live(_Entry e) {
    if (e.state != 'wip') return false;
    final pr = e.pr == null ? null : prs[e.pr];
    return pr == null || pr.state == 'OPEN';
  }

  final now = items.where(live).toList();
  final landed = items
      .where((e) => e.state == 'wip' && !live(e) || e.state == 'done')
      .toList();
  final rest = items
      .where((e) => !now.contains(e) && !landed.contains(e))
      .toList();

  final b = StringBuffer();
  b.writeln('<title>Anicel 보드</title>');
  b.writeln('<style>${_css()}</style>');
  b.writeln('<div class="wrap">');
  b.writeln('<header>');
  b.writeln('<h1>Anicel 보드</h1>');
  b.write('<p class="stamp">');
  b.write('답할 것 <b>${open.length}</b> · 지금 <b>${now.length}</b> · 열린 것 <b>${rest.length}</b>');
  if (!ghRan) {
    b.write(' · <span class="warn">PR 상태 못 읽음 (오프라인 렌더)</span>');
  }
  b.writeln('</p>');
  b.writeln(
    '<p class="rule">이 페이지는 <b>손으로 고치지 않습니다.</b> 기록 한 줄이 원본이고 '
    'PR 상태는 GitHub이 답합니다. <b>여기서 찍으면 그게 결정입니다.</b></p>',
  );
  b.writeln('</header>');

  if (open.isNotEmpty) {
    b.writeln('<h2>답할 것 <span class="n">${open.length}</span>'
        '<span class="why">여기서 찍으면 끝난다</span></h2>');
    for (final d in open) {
      b.writeln(_decisionCard(d));
    }
  }

  b.writeln(_section('지금', now, prs, empty: '굴러가는 PR이 없습니다.'));
  b.writeln(_section('열린 것', rest, prs, empty: '없습니다.'));
  if (landed.isNotEmpty) {
    b.writeln('<h2>최근 착지 <span class="n">${landed.length}</span></h2>');
    b.writeln('<div class="card">');
    for (final e in landed) {
      b.writeln(_row(e, prs));
    }
    b.writeln('</div>');
  }
  if (answered.isNotEmpty) {
    b.writeln('<h2>정해진 것 <span class="n">${answered.length}</span></h2>');
    b.writeln('<div class="card">');
    for (final d in answered) {
      final picked = d.options.firstWhere(
        (o) => o['key'] == d.answer,
        orElse: () => <String, dynamic>{'label': d.answer},
      );
      b.writeln(
        '<div class="row"><div class="k">${_esc(d.id)}</div>'
        '<div class="v"><div class="t">${_esc(d.title)}</div>'
        '<div class="d">→ <b>${_esc('${picked['label']}')}</b>'
        '${d.answerNote.isEmpty ? '' : ' — ${_esc(d.answerNote)}'}</div></div>'
        '<div><span class="chip done">정해짐</span></div></div>',
      );
    }
    b.writeln('</div>');
  }

  b.writeln('</div>');
  return b.toString();
}

String _section(String title, List<_Entry> rows, Map<int, _Pr> prs,
    {required String empty}) {
  final b = StringBuffer();
  b.writeln('<h2>$title <span class="n">${rows.length}</span></h2>');
  b.writeln('<div class="card">');
  if (rows.isEmpty) {
    b.writeln('<div class="row"><div class="k"></div><div class="v">'
        '<div class="d">${_esc(empty)}</div></div><div></div></div>');
  }
  for (final e in rows) {
    b.writeln(_row(e, prs));
  }
  b.writeln('</div>');
  return b.toString();
}

String _row(_Entry e, Map<int, _Pr> prs) {
  final chips = StringBuffer();
  for (final tag in e.tags) {
    chips.write('<span class="chip tag">${_esc(tag)}</span>');
  }
  if (e.pr != null) {
    final pr = prs[e.pr];
    final cls = pr == null
        ? 'plain'
        : pr.state == 'MERGED'
            ? 'done'
            : pr.checks == 'red'
                ? 'bad'
                : pr.checks == 'pending'
                    ? 'run'
                    : 'ok';
    final label = pr == null
        ? 'PR #${e.pr}'
        : pr.state == 'MERGED'
            ? '머지 #${e.pr}'
            : pr.state == 'CLOSED'
                ? '닫힘 #${e.pr}'
                : pr.checks == 'pending'
                    ? 'CI 중 #${e.pr}'
                    : pr.checks == 'red'
                        ? 'CI 빨강 #${e.pr}'
                        : 'CI 초록 #${e.pr}';
    chips.write(
      '<a class="chip $cls" href="https://github.com/myoun99/anicel/pull/${e.pr}">'
      '${_esc(label)}</a>',
    );
  } else {
    chips.write(
      '<span class="chip ${e.state == 'gate' ? 'bad' : 'plain'}">'
      '${_esc(_stateLabels[e.state] ?? e.state)}</span>',
    );
  }
  return '<div class="row"><div class="k">${_esc(e.id)}</div>'
      '<div class="v"><div class="t">${_esc(e.title)}</div>'
      '${e.note.isEmpty ? '' : '<div class="d">${_esc(e.note)}</div>'}</div>'
      '<div class="chips">$chips</div></div>';
}

String _decisionCard(_Entry d) {
  final b = StringBuffer();
  b.writeln('<div class="ask">');
  b.writeln('<div class="ask-head"><span class="k">${_esc(d.id)}</span>'
      '<h3>${_esc(d.title)}</h3></div>');
  if (d.where.isNotEmpty) {
    b.writeln('<p class="d"><b>화면에서</b> — ${_esc(d.where)}</p>');
  }
  if (d.why.isNotEmpty) {
    b.writeln('<p class="d"><b>왜 막혔나</b> — ${_esc(d.why)}</p>');
  }
  for (final o in d.options) {
    final key = '${o['key']}';
    final recommended = d.recommend == key;
    b.writeln('<label class="opt${recommended ? ' rec' : ''}">');
    b.writeln('<input type="radio" name="ans-${_esc(d.id)}" value="${_esc(key)}">');
    b.writeln('<span class="opt-body">');
    b.write('<b>${_esc(key)}. ${_esc('${o['label']}')}</b>');
    if (recommended) {
      b.write('<span class="chip ok">추천</span>');
    }
    if (o['what'] != null) {
      b.write('<span class="what">${_esc('${o['what']}')}</span>');
    }
    if (o['cost'] != null) {
      b.write('<span class="cost">대가 — ${_esc('${o['cost']}')}</span>');
    }
    b.writeln('</span></label>');
  }
  b.writeln('<label class="opt other"><input type="radio" '
      'name="ans-${_esc(d.id)}" value="other">'
      '<span class="opt-body"><b>다른 안 / 더 물어볼 것</b>'
      '<span class="what">아래 칸에 적어 주세요</span></span></label>');
  b.writeln('<textarea rows="2" placeholder="한 줄 메모 (왜 그렇게 정했는지 — '
      '이게 없으면 나중에 이유를 못 찾습니다)"></textarea>');
  b.writeln('</div>');
  return b.toString();
}

String _css() => '''
:root{--ink:#16181d;--ink2:#3d434f;--ink3:#6b7280;--bg:#f7f6f3;--card:#fff;
--line:#e2e0da;--line2:#cfccc4;--ok:#0f6f5c;--okbg:#eaf5f2;--run:#8a5a10;
--runbg:#f6edd9;--bad:#9a3412;--badbg:#fdeee7;--live:#1d4ed8;--livebg:#eaf0fe;
--mono:ui-monospace,"Cascadia Mono",Menlo,monospace;
--sans:"Segoe UI",-apple-system,"Noto Sans KR",system-ui,sans-serif}
@media(prefers-color-scheme:dark){:root:not([data-theme="light"]){
--ink:#eceef2;--ink2:#b9bfcb;--ink3:#838b99;--bg:#14161a;--card:#1c1f25;
--line:#2b2f37;--line2:#3a3f49;--ok:#5fc9ae;--okbg:#142824;--run:#e0b25e;
--runbg:#332912;--bad:#e08a63;--badbg:#2c1a12;--live:#86aaf5;--livebg:#17203a}}
:root[data-theme="dark"]{--ink:#eceef2;--ink2:#b9bfcb;--ink3:#838b99;
--bg:#14161a;--card:#1c1f25;--line:#2b2f37;--line2:#3a3f49;--ok:#5fc9ae;
--okbg:#142824;--run:#e0b25e;--runbg:#332912;--bad:#e08a63;--badbg:#2c1a12;
--live:#86aaf5;--livebg:#17203a}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font-family:var(--sans);
font-size:15px;line-height:1.6;word-break:keep-all}
.wrap{max-width:900px;margin:0 auto;padding:32px 18px 80px;
display:flex;flex-direction:column;gap:22px}
h1{font-size:24px;margin:0 0 4px;letter-spacing:-.02em}
h2{font-size:12px;text-transform:uppercase;letter-spacing:.1em;color:var(--ink3);
margin:14px 0 -6px;display:flex;align-items:baseline;gap:9px;flex-wrap:wrap}
h2 .n{font-family:var(--mono);color:var(--ink)}
h2 .why{text-transform:none;letter-spacing:0;font-size:12.5px}
h3{margin:0;font-size:15.5px;letter-spacing:-.01em}
.stamp{font-family:var(--mono);font-size:12px;color:var(--ink3);margin:0}
.warn{color:var(--bad)}
.rule{background:var(--card);border:1px solid var(--line);
border-left:3px solid var(--live);padding:10px 13px;border-radius:3px;
font-size:13.5px;color:var(--ink2);margin:10px 0 0}
header{display:flex;flex-direction:column}
.card{background:var(--card);border:1px solid var(--line);border-radius:5px;
overflow:hidden}
.row{display:grid;grid-template-columns:96px 1fr auto;gap:13px;padding:11px 14px;
border-bottom:1px solid var(--line);align-items:start}
.row:last-child{border-bottom:none}
.k{font-family:var(--mono);font-size:12px;color:var(--ink3);padding-top:2px}
.v{min-width:0}
.t{font-weight:600}
.d{font-size:13px;color:var(--ink2);margin:3px 0 0}
.chips{display:flex;gap:5px;flex-wrap:wrap;justify-content:flex-end}
.chip{font-family:var(--mono);font-size:11px;padding:2px 7px;border-radius:3px;
white-space:nowrap;border:1px solid var(--line2);color:var(--ink3);
text-decoration:none;display:inline-block}
.chip.ok{background:var(--okbg);color:var(--ok);border-color:transparent}
.chip.done{background:var(--okbg);color:var(--ok);border-color:transparent}
.chip.run{background:var(--runbg);color:var(--run);border-color:transparent}
.chip.bad{background:var(--badbg);color:var(--bad);border-color:transparent}
.chip.tag{background:transparent}
.ask{background:var(--card);border:1px solid var(--line);border-left:3px solid
var(--run);border-radius:5px;padding:14px 16px;display:flex;
flex-direction:column;gap:8px}
.ask-head{display:flex;align-items:baseline;gap:10px;flex-wrap:wrap}
.ask .d{margin:0}
.opt{display:flex;gap:10px;align-items:flex-start;padding:9px 11px;
border:1px solid var(--line);border-radius:4px;cursor:pointer}
.opt:hover{border-color:var(--line2)}
.opt.rec{border-color:var(--ok)}
.opt input{margin-top:4px;flex:none}
.opt-body{display:flex;flex-direction:column;gap:2px;min-width:0}
.opt-body b{font-weight:600}
.opt .chip{align-self:flex-start;margin-top:2px}
.what{font-size:13px;color:var(--ink2)}
.cost{font-size:12.5px;color:var(--ink3)}
.opt.other{border-style:dashed}
textarea{width:100%;background:var(--bg);color:var(--ink);border:1px solid
var(--line);border-radius:4px;padding:8px 10px;font-family:var(--sans);
font-size:13px;resize:vertical}
a{color:inherit}
@media(max-width:640px){.row{grid-template-columns:1fr}
.chips{justify-content:flex-start}}
''';
