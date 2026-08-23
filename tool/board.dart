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
// EVERY ROW IS A PANEL. Collapsed it shows a title and a chip; clicking the
// row opens it. Nothing else is on screen, which is the point -- the page
// answers "what needs me" before it answers anything else.
//
// ANSWERS ARE SUBMITTED, NOT INFERRED. A radio click changes an input's
// PROPERTY, not its attribute, so nothing about it survives into the saved
// document -- an early version of this page silently lost a pick that way.
// The submit button writes `data-answer` / `data-memo` ATTRIBUTES instead,
// which is what the live-document layer actually persists, and flips a visible
// badge so the user can see it took.
//
// It is an instrument, so here is what it looks like when it lies:
//   - a record with a `pr` GitHub has never heard of  -> the chip renders the
//     raw state string instead of a colour, which reads as broken
//   - `gh` unavailable (offline, not logged in)       -> every PR chip falls
//     back to "PR #n" with no state, and the header says so. It never
//     invents a state.
//   - a malformed JSONL line                          -> the line number goes
//     to stderr and the line is skipped; the page still renders. Silence
//     would be the dangerous outcome here, so it is never silent.
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
  final ghRan = !args.contains('--no-gh');
  final prs = ghRan ? await _pullPrStates(_flag(args, '--gh') ?? 'gh') : const <int, _Pr>{};

  File(out).writeAsStringSync(_render(entries, prs, ghRan: ghRan));

  final asks = entries.where((e) => e.kind == 'decision' && e.answer == null).length;
  final checks = entries.where((e) => e.kind == 'check' && e.answer == null).length;
  stdout.writeln('board: ${entries.length} records, $asks 답할 것, $checks 실기 확인 -> $out');
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
  String how = '';
  int? pr;
  List<Map<String, dynamic>> options = const [];
  String? recommend;
  String? answer;
  String answerNote = '';
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
    if (kind.isNotEmpty) entry.kind = kind;
    if (json['title'] != null) entry.title = json['title'] as String;
    if (json['state'] != null) entry.state = json['state'] as String;
    if (json['note'] != null) entry.note = json['note'] as String;
    if (json['where'] != null) entry.where = json['where'] as String;
    if (json['why'] != null) entry.why = json['why'] as String;
    if (json['how'] != null) entry.how = json['how'] as String;
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
  'gate': '게이트',
  'mine': '내 몫',
  'done': '착지',
};

String _esc(String s) => const HtmlEscape().convert(s);

String _render(List<_Entry> entries, Map<int, _Pr> prs, {required bool ghRan}) {
  final asks = entries.where((e) => e.kind == 'decision' && e.answer == null).toList();
  final checks = entries.where((e) => e.kind == 'check' && e.answer == null).toList();
  final settled = entries
      .where((e) => (e.kind == 'decision' || e.kind == 'check') && e.answer != null)
      .toList();
  final items = entries.where((e) => e.kind == 'item').toList();

  bool live(_Entry e) {
    if (e.state != 'wip') return false;
    final pr = e.pr == null ? null : prs[e.pr];
    return pr == null || pr.state == 'OPEN';
  }

  final now = items.where(live).toList();
  final landed =
      items.where((e) => (e.state == 'wip' && !live(e)) || e.state == 'done').toList();
  final rest =
      items.where((e) => !now.contains(e) && !landed.contains(e)).toList();

  final b = StringBuffer();
  b.writeln('<title>Anicel 보드</title>');
  b.writeln('<style>${_css()}</style>');
  b.writeln('<div class="wrap">');
  b.write('<h1>Anicel 보드</h1>');
  b.write('<p class="stamp">답할 것 <b>${asks.length}</b> · 실기 확인 '
      '<b>${checks.length}</b> · 지금 <b>${now.length}</b> · 열린 것 <b>${rest.length}</b>');
  if (!ghRan) {
    b.write(' · <span class="warn">PR 상태 못 읽음</span>');
  }
  b.writeln('</p>');
  b.writeln('<p class="rule">줄을 누르면 펼쳐집니다. <b>고른 뒤 제출을 눌러야 저장됩니다.</b></p>');

  b.write(_group('답할 것', asks.length, '고르고 제출', asks.map(_askPanel)));
  b.write(_group('실기 확인', checks.length, '메모가 비면 OK', checks.map(_checkPanel)));
  b.write(_group('지금', now.length, '', now.map((e) => _itemPanel(e, prs))));
  b.write(_group('열린 것', rest.length, '', rest.map((e) => _itemPanel(e, prs))));
  b.write(_group('최근 착지', landed.length, '', landed.map((e) => _itemPanel(e, prs))));
  b.write(_group('정해진 것', settled.length, '', settled.map(_settledPanel)));

  b.writeln('<script>${_js()}</script>');
  b.writeln('</div>');
  return b.toString();
}

String _group(String title, int n, String why, Iterable<String> panels) {
  if (n == 0) return '';
  final b = StringBuffer();
  b.writeln('<h2>$title <span class="n">$n</span>'
      '${why.isEmpty ? '' : '<span class="why">${_esc(why)}</span>'}</h2>');
  b.writeln('<div class="stack">');
  for (final p in panels) {
    b.writeln(p);
  }
  b.writeln('</div>');
  return b.toString();
}

String _head(_Entry e, String badge, String badgeClass) {
  final tags = e.tags.map((t) => '<span class="chip">${_esc(t)}</span>').join();
  return '<summary><span class="k">${_esc(e.id)}</span>'
      '<span class="t">${_esc(e.title)}</span>'
      '<span class="right">$tags'
      '<span class="chip $badgeClass badge">${_esc(badge)}</span></span></summary>';
}

String _askPanel(_Entry d) {
  final b = StringBuffer();
  b.writeln('<details class="p ask" id="c-${_esc(d.id)}">');
  b.writeln(_head(d, '미제출', 'run'));
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
  b.writeln('<textarea rows="2" placeholder="메모 — 왜 그렇게 정했는지"></textarea>');
  b.writeln('<div class="foot">'
      '<button onclick="sub(\'${_esc(d.id)}\')">제출</button>'
      '<span class="state">아직 제출 안 함</span></div>');
  b.writeln('</div></details>');
  return b.toString();
}

String _checkPanel(_Entry c) {
  final b = StringBuffer();
  b.writeln('<details class="p chk" id="c-${_esc(c.id)}">');
  b.writeln(_head(c, '미확인', 'run'));
  b.writeln('<div class="body">');
  if (c.how.isNotEmpty) {
    b.writeln('<p class="d"><b>이렇게 본다</b> — ${_esc(c.how)}</p>');
  }
  if (c.why.isNotEmpty) {
    b.writeln('<p class="d"><b>왜 중요한가</b> — ${_esc(c.why)}</p>');
  }
  if (c.note.isNotEmpty) {
    b.writeln('<p class="d">${_esc(c.note)}</p>');
  }
  b.writeln('<textarea rows="2" placeholder="문제가 있으면 적어 주세요 — 비워 두면 OK"></textarea>');
  b.writeln('<div class="foot">'
      '<button onclick="chk(\'${_esc(c.id)}\')">제출</button>'
      '<span class="state">아직 제출 안 함</span></div>');
  b.writeln('</div></details>');
  return b.toString();
}

String _itemPanel(_Entry e, Map<int, _Pr> prs) {
  String badge = _stateLabels[e.state] ?? e.state;
  var cls = e.state == 'gate' ? 'bad' : '';
  var link = '';
  if (e.pr != null) {
    final pr = prs[e.pr];
    if (pr == null) {
      badge = 'PR #${e.pr}';
    } else if (pr.state == 'MERGED') {
      badge = '머지 #${e.pr}';
      cls = 'ok';
    } else if (pr.state == 'CLOSED') {
      badge = '닫힘 #${e.pr}';
      cls = 'bad';
    } else {
      badge = switch (pr.checks) {
        'pending' => 'CI 중 #${e.pr}',
        'red' => 'CI 빨강 #${e.pr}',
        _ => 'CI 초록 #${e.pr}',
      };
      cls = pr.checks == 'red' ? 'bad' : (pr.checks == 'pending' ? 'run' : 'ok');
    }
    link = '<p class="d"><a href="https://github.com/myoun99/anicel/pull/${e.pr}">'
        'PR #${e.pr} 열기 →</a></p>';
  }
  final body = e.note.isEmpty && link.isEmpty
      ? '<div class="body"><p class="d">메모 없음.</p></div>'
      : '<div class="body">'
          '${e.note.isEmpty ? '' : '<p class="d">${_esc(e.note)}</p>'}$link</div>';
  return '<details class="p">${_head(e, badge, cls)}$body</details>';
}

String _settledPanel(_Entry d) {
  final picked = d.options.firstWhere(
    (o) => o['key'] == d.answer,
    orElse: () => <String, dynamic>{'label': d.answer},
  );
  final body = '<div class="body">'
      '<p class="d"><b>→ ${_esc('${picked['label']}')}</b></p>'
      '${d.answerNote.isEmpty ? '' : '<p class="d">${_esc(d.answerNote)}</p>'}'
      '</div>';
  return '<details class="p">${_head(d, '정해짐', 'ok')}$body</details>';
}

/// Submit writes ATTRIBUTES, because that is what survives into the saved
/// document — a radio's `checked` property does not, and an early version of
/// this page lost a pick exactly that way.
String _js() => '''
function pick(id){return document.getElementById('c-'+id)}
function stamp(c,badge,line){
  c.querySelector('.badge').textContent=badge;
  c.querySelector('.state').textContent=line;
  c.querySelector('.badge').className='chip ok badge';
}
function sub(id){
  var c=pick(id);
  var r=c.querySelector('input[name="ans-'+id+'"]:checked');
  var t=c.querySelector('textarea');
  var v=r?r.value:'';
  var m=t?(t.value||'').trim():'';
  if(!v&&!m){stamp(c,'미제출','고르거나 메모를 적어 주세요');return}
  c.setAttribute('data-answer',v);
  c.setAttribute('data-memo',m);
  stamp(c,'제출됨','제출됨 — '+(v?('안 '+v):'메모만')+(m?(' · '+m):''));
}
function chk(id){
  var c=pick(id);
  var t=c.querySelector('textarea');
  var m=t?(t.value||'').trim():'';
  c.setAttribute('data-check',m?'ng':'ok');
  c.setAttribute('data-memo',m);
  stamp(c,m?'피드백':'OK',m?('피드백 — '+m):'OK — 문제 없음');
}
''';

String _css() => '''
:root{--ink:#16181d;--ink2:#3d434f;--ink3:#6b7280;--bg:#f7f6f3;--card:#fff;
--line:#e2e0da;--line2:#cfccc4;--ok:#0f6f5c;--okbg:#eaf5f2;--run:#8a5a10;
--runbg:#f6edd9;--bad:#9a3412;--badbg:#fdeee7;--live:#1d4ed8;
--mono:ui-monospace,"Cascadia Mono",Menlo,monospace;
--sans:"Segoe UI",-apple-system,"Noto Sans KR",system-ui,sans-serif}
@media(prefers-color-scheme:dark){:root:not([data-theme="light"]){
--ink:#eceef2;--ink2:#b9bfcb;--ink3:#838b99;--bg:#14161a;--card:#1c1f25;
--line:#2b2f37;--line2:#3a3f49;--ok:#5fc9ae;--okbg:#142824;--run:#e0b25e;
--runbg:#332912;--bad:#e08a63;--badbg:#2c1a12;--live:#86aaf5}}
:root[data-theme="dark"]{--ink:#eceef2;--ink2:#b9bfcb;--ink3:#838b99;
--bg:#14161a;--card:#1c1f25;--line:#2b2f37;--line2:#3a3f49;--ok:#5fc9ae;
--okbg:#142824;--run:#e0b25e;--runbg:#332912;--bad:#e08a63;--badbg:#2c1a12;
--live:#86aaf5}
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
.rule{font-size:12.5px;color:var(--ink3);margin:8px 0 0}
.stack{display:flex;flex-direction:column;gap:5px}
.p{background:var(--card);border:1px solid var(--line);border-radius:5px}
.p[open]{border-color:var(--line2)}
.ask{border-left:3px solid var(--run)}
.chk{border-left:3px solid var(--live)}
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
.d{font-size:13px;color:var(--ink2);margin:0}
.opt{display:flex;gap:9px;align-items:flex-start;padding:8px 10px;
border:1px solid var(--line);border-radius:4px;cursor:pointer}
.opt.rec{border-color:var(--ok)}
.opt.other{border-style:dashed}
.opt input{margin-top:4px;flex:none}
.ob{display:flex;flex-direction:column;gap:2px;min-width:0}
.ob .chip{align-self:flex-start;margin-top:2px}
.what{font-size:12.5px;color:var(--ink2)}
.cost{font-size:12px;color:var(--ink3)}
textarea{width:100%;background:var(--bg);color:var(--ink);
border:1px solid var(--line);border-radius:4px;padding:7px 9px;
font-family:var(--sans);font-size:13px;resize:vertical}
.foot{display:flex;align-items:center;gap:10px}
button{font-family:var(--sans);font-size:13px;font-weight:600;padding:6px 16px;
border-radius:4px;border:1px solid var(--ok);background:var(--okbg);
color:var(--ok);cursor:pointer}
button:hover{background:var(--ok);color:var(--card)}
.state{font-size:12px;color:var(--ink3)}
a{color:var(--live)}
@media(max-width:560px){summary{flex-wrap:wrap}.k{min-width:0}
.t{flex:1 0 100%;order:3}}
''';
