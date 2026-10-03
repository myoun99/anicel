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
import 'dart:async';
import 'dart:convert';
import 'dart:io';

// 🚨The card model lives in ONE place — see [board_model.dart]. The gate
// reads the same file, so it cannot judge the board by different rules.
import 'board_model.dart';

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

/// ⚠️NOT `late final`, so the page can be drawn without a server behind it.
/// `_shotsFor` reads this on every card; as a `late` it threw the moment a
/// test imported this file, which is a large part of why the renderer had no
/// tests at all while three of its bugs shipped in one day. Empty means 「no
/// shots directory」 and [_shotsFor] already answers that with `const []` —
/// the same answer it gives for a directory that is not there yet.
String _shotsDir = '';
late final String _ghPath;
late final String _gitRoot;

/// 🚨★★★THE BOARD REPLACES ITSELF WHEN ITS OWN SOURCE CHANGES.
///
/// 유저 2026-08-31: 「근데 **매번 너가 갱신해줘야 반영되는건가? 좀 약한
/// 구조 아닌가**」 — it was. The chain was ①I merge ②I pull the checkout
/// ③some session's Stop hook notices and rebuilds. Step ③ only happens while
/// a session is running, so opening the board with no session open served
/// whatever was last built, silently and for as long as nobody looked.
///
/// ⛔A fix that merged and never reached the screen is the exact shape this
/// project keeps stepping in: on 2026-08-31 유저 asked why a rule was not
/// working when it had merged twelve minutes earlier and the exe was older
/// than the merge.
///
/// ⇒ The running board carries a copy of the source it was built from. Every
/// request compares — a byte compare of ~130KB, well under a millisecond —
/// and when they differ it draws ONE more page saying so, hands the rebuild
/// to [_relaunch], and exits. Nobody has to remember anything.
///
/// ⚠️Silent when the copy is missing, which is what `dart run` looks like: a
/// development run must not blow itself up mid-probe.
File? _builtFrom;
List<File>? _liveSources;

/// EVERY source this exe is compiled from — the entry file and the `tool/`
/// files it imports, sorted so the order cannot drift.
///
/// 🚨★★★AN EXE IS MADE OF MORE THAN ITS ENTRY FILE, and forgetting that made
/// this whole mechanism a lie for any change that did not touch the entry.
/// 🧪2026-08-31: #1433 changed only `board_model.dart` — which BOTH binaries
/// compile in — and the running board kept serving code built from the
/// previous one. No rebuild, no notice, nothing to look at. That is exactly
/// the failure the self-replace above was written to end, one level down.
///
/// ⚠️ONE LEVEL is the whole graph here: each entry imports `board_model.dart`
/// and that imports nothing of ours. Derived rather than listed, because a
/// listed name is a word somebody has to remember — and this file has spent
/// the day removing those.
///
/// ⛔THE SAME RULE LIVES IN `board_up.sh` (`sources_of`), because that is what
/// WRITES the stamp. Two spellings of one rule: change both or neither.
List<File> sourcesOfEntry(File entry) {
  final dir = entry.parent.path;
  final out = <String>{entry.path.replaceAll('\\', '/')};
  final imports = RegExp(r"^import '([A-Za-z0-9_]+\.dart)';", multiLine: true);
  for (final m in imports.allMatches(entry.readAsStringSync())) {
    out.add('${dir.replaceAll('\\', '/')}/${m.group(1)}');
  }
  final paths = out.toList()..sort();
  return [for (final p in paths) File(p)];
}

/// The stamp this exe was built with, and the sources as they are now — set
/// once at startup so a request only pays the compare.
///
/// 🚨★★★A NEW FILE NAME, and that is the whole point. `.src` held a COPY OF
/// THE ENTRY FILE; this holds the concatenation of every source. Those two
/// answers to 「what is this exe made of」 cannot both live in one path,
/// because the writer (`board_up.sh`, in the memory folder) and the reader
/// (this file, in the repo) **cannot land in the same instant**.
///
/// 🧪2026-08-31, and I did it to the live board: I patched the shell first,
/// the Stop hook ran it, and the running server — still comparing the entry
/// file alone — found the concatenation different on EVERY request and took
/// itself down every time. Not a stale board: a board that would not stay up.
///
/// ⇒ With a new name the order stops mattering. An old exe keeps reading
/// `.src` and is happy; a new exe finds no `.srcs` yet and stays silent,
/// which is exactly what this function already does for a missing stamp
/// (「⚠️Silent when the copy is missing, which is what `dart run` looks
/// like」). Neither can loop.
void _findOwnSource() {
  final stamp = File('${Platform.resolvedExecutable}.srcs');
  if (!stamp.existsSync()) return;
  final entry = File('$_gitRoot/tool/board_server.dart');
  if (!entry.existsSync()) return;
  final sources = sourcesOfEntry(entry);
  if (sources.any((f) => !f.existsSync())) return;
  _builtFrom = stamp;
  _liveSources = sources;
}

/// ⚠️Bytes, not a hash and NOT mtime. mtime was measured wrong on this very
/// file: the source read 16:57:11 and the exe 16:57:44 — OLDER source, NEWER
/// content, because git does not rewrite a path whose content it already
/// holds. A hash would work too but needs a package; the build already keeps
/// the copy, so comparing it is exact and costs nothing to maintain.
bool _sourceMoved() {
  final was = _builtFrom;
  final now = _liveSources;
  if (was == null || now == null) return false;
  try {
    final a = was.readAsBytesSync();
    final b = <int>[for (final f in now) ...f.readAsBytesSync()];
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return true;
    }
    return false;
  } on Object catch (_) {
    // Unreadable for a moment mid-write. Not news; the next request asks again.
    return false;
  }
}

/// Hands the rebuild to the script that owns it and steps out of the way.
///
/// ⚠️Windows will not let us overwrite a running exe, so this process has to
/// END for the rebuild to succeed — which is why the page said so first. The
/// launcher recompiles and starts the new one; a browser that reloads finds
/// the new board on the same port.
///
/// ⛔The rule for WHEN to rebuild is not repeated here. `board_up.sh` owns it,
/// the Stop hook calls the same script, and a second copy of the test is how
/// this bug happened the first time.
Never _relaunch() {
  final up = File('${File(_recordsPath).parent.path}/board_up.sh');
  if (up.existsSync()) {
    unawaited(Process.start(
      'bash',
      [up.path],
      mode: ProcessStartMode.detached,
      runInShell: true,
    ));
  }
  exit(0);
}

/// The one page a stale board serves: it says what is happening and comes back
/// on its own when the new build answers. ⚠️Self-contained — the CSS and JS of
/// the real board belong to the build that is being replaced.
String _rebuildingPage() => '''
<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>보드를 다시 만드는 중</title>
<style>
body{margin:0;display:grid;place-items:center;height:100vh;
  font:15px/1.6 "BIZ UDPGothic","Nanum Gothic",system-ui,sans-serif;
  background:#14161a;color:#e6e8ec}
.box{max-width:520px;padding:28px 32px;text-align:center}
h1{font-size:17px;margin:0 0 10px}
p{margin:6px 0;color:#9aa1ad;font-size:13.5px}
b{color:#e6e8ec}
</style></head><body><div class="box">
<h1>보드 코드가 바뀌었습니다 — 다시 만드는 중</h1>
<p>보통 30초 안팎, 처음 만드는 경우 몇 분까지 걸립니다. <b>끝나면 이 화면이 알아서 새 보드로 바뀝니다.</b></p>
<p>제출한 답과 메모는 이미 기록에 들어가 있어 사라지지 않습니다.</p>
</div>
<script>
setInterval(function(){
  fetch('/fresh',{cache:'no-store'})
    .then(function(r){ if(r.ok) location.replace('/'); })
    .catch(function(){});
}, 1000);
</script>
</body></html>
''';

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
  _findOwnSource();

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
    } on Object catch (e) {
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
        final id = '${body['id']}';
        // 🚨AN ANSWERED QUESTION STOPS BEING A CARD (유저 2026-08-27: 「답할
        // 것의 카드는 애초에 원본 카드에서 파생?되서 이어지는 카드아닌가?
        // 원본카드에 질문항목이 존재하고 답하면 대답 카드 자체는 사라지고
        // 참조로서 해당 항목에 들어가는거아닌가?」).
        //
        // Right, and it is the same law as everything else here: a question
        // was never a subject of its own. It goes `archived` — which is not
        // a loss, because `_byOrigin` reads ARCHIVED questions too, so the
        // origin's Q row keeps showing it with the answer in place.
        //
        // ⇒ The NEWS lands on the ORIGIN instead: that card goes to 분류 전,
        // because an answer is something the user said that I have to read
        // and act on. One card, one row, and the answer is where the work is.
        final origin = kind == 'decision' ? originOfId(id, File(_recordsPath)) : '';
        // 🚨THE RECORD KEEPS THE USER'S WORD, NOT THE RADIO'S VALUE. The
        // value is the option's key — an index by construction — so the line
        // used to read `{"answer":"2"}` and said nothing on its own
        // (유저 2026-09-12: 「보드에 2만으로는 알수없잖아」). Resolved HERE,
        // where the answer is written, so no writer has to remember it.
        final answer = answerWordFor(
          id,
          '${body['answer'] ?? ''}',
          File(_recordsPath),
        );
        // 🚨★★★WHAT THE USER SUBMITS IS AN ENTRY, and the entry says where the
        // card goes. ⛔Every branch here used to write a `state` as well, and
        // the story then overrode it — the same 「한 질문에 리더 둘」 this
        // round is removing everywhere else. 🧪H2 proved it: a memo left on a
        // 실기 확인 row wrote `state: "inbox"` and the card stayed in 실기
        // 확인, because its newest 대분류 still said so.
        //
        // Three shapes, one rule each:
        //  · 결정에 답함 → the answer rides the QUESTION record (archived), and
        //    the fold puts it on the card as a `유저` entry, which is 분류 전.
        //  · 체크 → 완료. 「봤고 문제 없음」 ends the card, and the tick is in
        //    its story as the user's own word.
        //  · 메모 → 유저. Something to read, so it comes back to me.
        if (origin.isNotEmpty) {
          _append({
            'kind': kind,
            'id': id,
            'answer': answer,
            'answerNote': memo,
            'ts': _now(),
            'state': 'archived',
          });
          // ⚠️No `state` on the card: the folded `유저` entry already says
          // 분류 전. This line exists only so the head's date moves.
          _append({'kind': 'item', 'id': origin, 'ts': _now()});
        } else if (kind == 'decision') {
          // A question nobody folded — it IS the card, so the answer stays on
          // it. ⚠️No `state`: the fold relabels its answer entry `유저`, and
          // 분류 전 falls out of the story like every other card's.
          _append({
            'kind': kind,
            'id': id,
            'answer': answer,
            'answerNote': memo,
            'ts': _now(),
          });
        } else {
          // ⛔THE CLEAN-TICK BRANCH IS GONE, and with it the card-level 제출
          // on a check card. `/tick` owns that answer now: it clears ONE
          // check by `ref`, which is the difference a card-level button could
          // never express. ⚠️A stale page that still posts here lands in the
          // line below — 유저 memo → 분류 전, which is the safe half.
          _append({
            'kind': 'item',
            'id': id,
            'at': '유저',
            'said': memo,
            'ts': _now(),
          });
        }
      // ↩️확인 on the rows picked in the list: every check each card still
      // waits on, ticked quietly — the very lines [tickRecords] writes. It was
      // `state: archived` on the card (#1200, 2026-08-24, when one card was
      // one check), which on today's board would also end a card that waits
      // on a check from somewhere else — 🧪brush-fidelity and I-4 sat in 백로그
      // with work left when this was written.
      case '/dismiss':
        final board = _board();
        for (final id in (body['ids'] as List?) ?? [body['id']]) {
          final card = board.where((c) => c.id == '$id').firstOrNull;
          if (card == null) continue;
          confirmRecords(card: card, now: _now).forEach(_append);
        }
      // 🚨★★★THE WRITER COUNTS, SO THE READER KEEPS ONE RULE (유저
      // 2026-08-31: 「그냥 내가 실기 확인 제출해서 0개 되면 사라지는데, 그걸
      // 그냥 **대분류 확인이라는 항목을 만드는 작업으로 하면** 자연스럽게
      // 되는 거 아니야?」).
      //
      // ⛔Placement used to carry 「완료인데 체크가 남았으면 실기로
      // 되돌린다」 — a rule about ONE 대분류 living inside the reader, which
      // is the shape this whole redesign removes. Here the tick asks how many
      // checks are still waiting and writes the word that is true: `확인`
      // while any remain, `완료` for the last one. 칸 = 마지막 대분류, still.
      //
      // ⚠️`ref` is the ts of the check being cleared — an entry has no id of
      // its own, and within one card a ts IS its identity.
      case '/tick':
        final id = '${body['id']}';
        final ref = '${body['ref'] ?? ''}';
        final card = _board().where((c) => c.id == id).firstOrNull;
        final note = '${body['note'] ?? ''}'.trim();
        // What the lines say, and why a tick can write two of them, lives on
        // [tickRecords] — a route that only appends is a route no test can
        // assert on.
        for (final line in tickRecords(
          card: card,
          id: id,
          ref: ref,
          note: note,
          now: _now,
        )) {
          _append(line);
        }
      // ↩️🚨★★★ONE PRESS MOVES THE CARD (유저 2026-10-02, on the redesign
      // that said 「상태는 한 번 누르면 바로 바뀝니다 … 바뀐 일은 이야기에
      // 「사용자가 옮김」으로 남으니 흔적은 그대로 남습니다」: 「문제없어
      // 진행해줘. 최대한 프로들이랑 똑같으면되」).
      //
      // It reverses this, written on 2026-08-31 for the request 「대기중/착수
      // 가능 등에서 내가 아 이건 순서 보류하고 싶다 싶을 때 **가볍게 순서
      // 대기 쪽으로 옮기는 게 힘든데, 그거 하는 기능 있으면 좋을 거 같아**」:
      // 「⚠️ONE LINE, and its 대분류 is 분류 전 — not the section they asked
      // for. Everything the user writes comes back to me to act on … **유저는
      // 분류 체계를 몰라도 된다**: the request is the entry's text, and moving
      // the card is mine. ⛔A button that moved the card itself would move
      // something nobody had read, and the request would leave no trace in
      // the story.」
      //
      // ⇒ The trace half still holds: the move IS an entry, the user's own,
      // under the status word it moved to — so the story says who moved it and
      // when, and the fold places the card by it like any other word.
      case '/move':
        final id = '${body['id']}';
        final line = moveRecord(
          card: _board().where((c) => c.id == id).firstOrNull,
          id: id,
          to: '${body['to'] ?? ''}',
          now: _now,
        );
        if (line == null) {
          req.response.statusCode = 400;
          await req.response.close();
          return;
        }
        _append(line);
      // 🆕A field, last-wins, with no entry: a priority is a dial on the card,
      // not something that happened in its story.
      case '/priority':
        final id = '${body['id']}';
        final card = _board().where((c) => c.id == id).firstOrNull;
        _append({
          'kind': card?.kind ?? 'item',
          'id': id,
          'priority': '${body['priority'] ?? ''}'.trim(),
          'ts': _now(),
        });
      // 🆕「이 빌드로 시험 중」: what master is right now, and when — the build
      // verification is grouped by.
      case '/build':
        final commit = _master();
        _append({
          'kind': 'build',
          'id': 'build-${_now().substring(0, 19).replaceAll(':', '')}',
          'title': commit,
          'ts': _now(),
        });
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'ok': true, 'commit': commit}));
        await req.response.close();
        return;
      case '/intake':
        newId = _intake(body);
      case '/edit':
        final text = '${body['text'] ?? ''}'.trim();
        // ⛔A GUARD ONLY THE PAGE ENFORCES IS A GUARD THAT CAN BE SKIPPED.
        // An empty write here sets `said` and `title` to '' — the card loses
        // its own words. The box is empty by default now, so this is one
        // stray Enter away rather than something nobody would ever send.
        if (text.isEmpty) break;
        final first = text.split('\n').first;
        // Still the user's own words, so still `said` — and `said` does
        // TWO things, which is why this looked like an edit box for so long.
        // ⚠️The HEAD is last-wins: `said` and `title` become this text, so
        // the card's one-line summary is whatever was written most recently.
        // 🚨The STORY appends: `readBoard` runs every distinct `said` through
        // `stage(..., '유저 메모')`, so each press leaves its own dated line
        // (identical text is deduped, which is why re-submitting an unchanged
        // box used to look like nothing happened).
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
        await _ghStale.force();
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

  // A liveness probe with a name: it answers as soon as the board is up, which
  // is what the rebuilding page waits for.
  if (path == '/fresh') {
    req.response
      ..headers.contentType = ContentType.json
      ..headers.set('Cache-Control', 'no-store')
      ..write(jsonEncode({'moved': _sourceMoved()}));
    await req.response.close();
    return;
  }
  if (path == '/api/board') {
    final data = await _boardJson();
    req.response
      ..headers.contentType = ContentType.json
      ..headers.set('Cache-Control', 'no-store')
      ..write(jsonEncode(data));
    await req.response.close();
    return;
  }
  if (path == '/api/find') {
    req.response
      ..headers.contentType = ContentType.json
      ..headers.set('Cache-Control', 'no-store')
      ..write(jsonEncode(_find(req.uri.queryParameters['q'] ?? '')));
    await req.response.close();
    return;
  }
  if (path == '/card') {
    final html = _detail(
      _board(),
      await _prs(),
      req.uri.queryParameters['id'] ?? '',
    );
    req.response
      ..headers.contentType = ContentType.html
      ..headers.set('Cache-Control', 'no-store')
      ..write(html);
    await req.response.close();
    return;
  }
  if (path != '/') {
    req.response.statusCode = 404;
    await req.response.close();
    return;
  }
  // 🚨★★★NEW CODE ARRIVES ON A REFRESH, AND ONLY ON A REFRESH.
  //
  // 유저 2026-08-31: 「그냥 새로고침 누르면 갱신되도록 할 수 있나? 그럼
  // 내가 알아서 새로고침하면 되는 거니까 단순해지는 거 같은데」 — it is.
  // No banner, no polling, no button: the board is stale until you ask for a
  // fresh page, and asking is the one gesture that already means 「throw this
  // page away」.
  //
  // ⚠️ONLY THE PAGE ITSELF REBUILDS, and it is the user's other requirement:
  // 「내가 소스가 바뀌기 전에 답한 것도 안 사라지게 잘 하는 것도 중요하고」.
  // After a submit the page reads `/api/board` and `/card`, never this path,
  // so handing over cannot kill the server in the middle of the flow that
  // just recorded an answer.
  //
  // ✅The answer itself is never at risk either way: `_append` writes the line
  // SYNCHRONOUSLY, so it is on disk before the reply is sent and a restart
  // re-reads it. What a refresh can lose is text still sitting in a box, and
  // that is exactly what the user chose to lose by refreshing.
  //
  // ⚠️Windows will not overwrite a running exe, so this process has to end for
  // the rebuild to work — the page it serves first says so and waits for the
  // new board on the same port.
  if (_sourceMoved()) {
    req.response
      ..headers.contentType = ContentType.html
      ..headers.set('Cache-Control', 'no-store')
      ..write(_rebuildingPage());
    await req.response.close();
    _relaunch();
  }
  final boot = await _boardJson();
  req.response
    ..headers.contentType = ContentType.html
    ..headers.set('Cache-Control', 'no-store')
    ..write(_shell(boot));
  await req.response.close();
}

/// The commit master is at now, short — what a build marks.
String _master() {
  try {
    final r = Process.runSync('git', ['-C', _gitRoot, 'rev-parse', '--short', 'master'],
        stdoutEncoding: utf8);
    return r.exitCode == 0 ? (r.stdout as String).trim() : '';
  } on Object catch (_) {
    return '';
  }
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
  // ⚠️The stage name is 유저 for all three now — see below. What still
  // differs is the id prefix and the tag, and the tag is where a reader looks
  // to tell a finished thought from an unfinished one: 임시 is its own filing,
  // not a lesser feedback, and says whoever reads it should expect to ask
  // rather than act.
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
    // 🚨`said`, and NOT also `note`. This is the user's own writing; the panel
    // labels it as theirs. The whole redesign turns on never letting my words
    // and theirs share a field — and writing both would print the same
    // paragraph twice, once under each name.
    'said': text,
    // 🚨★★★`유저`, THE 대분류 — not a label of its own. Everything the user
    // writes is one kind of entry and it lands in 분류 전; which KIND of
    // filing it was is the tag beside it (피드백 / 아이디어 / 임시), so the
    // stage name was saying it twice. ⛔And `state: 'inbox'` is gone with it:
    // this was the last place a section was written rather than folded out of
    // the story. Older intake records keep their own `state`, which still
    // works — nothing in their story names a section, so nothing overrides it.
    'at': '유저',
    'tags': [label, if (tag.isNotEmpty) tag],
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
  final entry = _board().where((e) => e.id == id);
  if (entry.isEmpty || entry.first.state != 'inbox') return false;
  final kept = File(_recordsPath).readAsLinesSync().where((line) {
    final t = line.trim();
    if (t.isEmpty) return false;
    try {
      return (jsonDecode(t) as Map<String, dynamic>)['id'] != id;
    } on Object catch (_) {
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
  for (final e in _board()) {
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
  final id = '${body['id']}'.replaceAll(RegExp('[^A-Za-z0-9_.-]'), '_');
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

/// A value that is slow to fetch and cheap to be a few seconds old.
///
/// 🚨The window used to be a WALL: once it expired, whoever clicked next paid
/// the whole cost. Measured 2026-08-28 — 0.5s warm, **3.7s** on the first
/// request after the window lapsed, for inputs a page turn does not even
/// change (유저: 「이 보드 자체가 렉이 좀 있는데 어떻게안되나」).
///
/// Now an expired value is still served immediately and the refresh runs
/// behind it. The slow path is paid once, at startup, instead of every twenty
/// seconds by whoever happens to be clicking when the timer lapses.
///
/// ⚠️A failed refresh keeps the last good value rather than blanking it: the
/// board saying nothing is worse than the board being a minute old, and `gh`
/// failing outright already has its own banner.
class _Stale<T> {
  _Stale(this._fetch);

  final Future<T> Function() _fetch;
  T? _value;
  DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);
  bool _busy = false;

  /// Only the FIRST caller of all ever waits.
  Future<T> get() async {
    final held = _value;
    if (held == null) return _store(await _fetch());
    if (DateTime.now().difference(_at).inSeconds >= _ghCacheSeconds) _refresh();
    return held;
  }

  void _refresh() {
    if (_busy) return;
    _busy = true;
    unawaited(() async {
      try {
        _store(await _fetch());
      } on Object catch (_) {
        // Keep what we had. See the class doc.
      } finally {
        _busy = false;
      }
    }());
  }

  /// 「↻」 — the ONE caller that wants to wait. Pressing refresh is a person
  /// saying the stale answer is not good enough, so this is the one path that
  /// does not hand one back.
  Future<T> force() async => _store(await _fetch());

  T _store(T v) {
    _value = v;
    _at = DateTime.now();
    return v;
  }
}

final _ghStale = _Stale<_Gh>(_fetchPrs);

/// One `gh` call shared by every request inside the cache window. It is the
/// only input slow enough to be worth caching, and a few seconds of staleness
/// on a PR list is not a staleness anyone can act on.
Future<_Gh> _prs() => _ghStale.get();

Future<_Gh> _fetchPrs() async {
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
  } on Object catch (_) {
    return _Gh(const [], ok: false);
  }
  if (result.exitCode != 0) return _Gh(const [], ok: false);

  final List<dynamic> rows;
  try {
    rows = jsonDecode(result.stdout as String) as List;
  } on Object catch (e) {
    // A response we cannot read is a failed lookup, not a failed page: the
    // board still has work to show, and saying "gh 를 못 불렀습니다" is both
    // true and better than a 500 that shows nothing at all.
    stderr.writeln('board: could not parse gh output: $e');
    return _Gh(const [], ok: false);
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
  return _Gh(prs, ok: true);
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

final _gitStale = _Stale<List<_Checkout>>(_readCheckouts);

/// Reads every worktree of the repository, so "which checkout am I looking at
/// and is it current" stops being something you find out by being told it is
/// five commits behind.
///
/// ⚠️Eleven `git` calls on five worktrees, which is the other half of the
/// 3.7s — hence the same [_Stale] wrapper the PR list wears.
Future<List<_Checkout>> _checkouts() => _gitStale.get();

Future<List<_Checkout>> _readCheckouts() async {
  String run(String dir, List<String> args) {
    try {
      final r = Process.runSync('git', ['-C', dir, ...args],
          stdoutEncoding: utf8);
      return r.exitCode == 0 ? (r.stdout as String).trim() : '';
    } on Object catch (_) {
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
  return out;
}

// ------------------------------------------------------------------ render

String _esc(String s) => const HtmlEscape().convert(s);

/// The lines a tick on [id] appends: the tick itself, and the user's words
/// beside it when there are any. [card] is what the board holds for [id]
/// right now (null if nothing), [ref] the `ts` of the check being cleared.
///
/// 🚨★★★A CHECK TICKED WITH WORDS IS 분류 전, NOT 완료.
///
/// ⛔This is the board's own law — 「유저가 적은 것은 언제나 분류 전」 — and
/// it is here because breaking it cost four reports. H24, F-28, F-22-rest and
/// R27-rest were all ticked `ok` WITH a memo saying what was still wrong; the
/// tick cleared the row, the words went with it, and nothing on the board
/// said they existed. They surfaced on 2026-08-31 only because I went looking
/// through the file.
///
/// ⚠️An empty memo still means 문제 없음, so the quiet path is exactly what
/// it was: 확인 완료 while checks remain, 완료 on the last one.
/// ⛔TWO LINES, because they are two facts and only one of them clears the
/// check. `checksWaiting` clears on 확인 완료 / 완료 and on nothing else — a
/// single 유저 line would have left the button on screen looking like the
/// tick never landed. 🧪Caught before it shipped by reading that function
/// rather than assuming it.
///
/// 🚨★★★BOTH LINES CARRY THE CARD'S OWN KIND (2026-09-15). They used to say
/// `kind: item` whatever the card was. On a card born `kind: check` that one
/// word made it an item, and a check's 실기 확인 entry is not a line in the
/// file — it is the entry [foldChecksIntoCards] folds in FOR a check. So the
/// tick that cleared the check deleted the entry its own [ref] named, and
/// six finished checks kept the gate saying 「가리키는 곳이 없는 값」 at the
/// end of every turn, in every session.
List<Map<String, dynamic>> tickRecords({
  required BoardCard? card,
  required String id,
  required String ref,
  required String note,
  required String Function() now,
}) {
  final left = card == null
      ? const <String>[]
      : checksWaiting(card).where((ts) => ts != ref).toList();
  return _tickLines(card, id, ref, note, now, last: left.isEmpty);
}

/// The lines 확인 on the list's picked rows appends for [card]: every check it
/// still waits on, ticked quietly, oldest first — each as [tickRecords]
/// writes it.
List<Map<String, dynamic>> confirmRecords({
  required BoardCard card,
  required String Function() now,
}) {
  final waiting = checksWaiting(card);
  return [
    for (var i = 0; i < waiting.length; i++)
      ..._tickLines(card, card.id, waiting[i], '', now,
          last: i == waiting.length - 1),
  ];
}

/// One tick's lines; [last] says no other check on the card is left waiting.
List<Map<String, dynamic>> _tickLines(
  BoardCard? card,
  String id,
  String ref,
  String note,
  String Function() now, {
  required bool last,
}) {
  final kind = card?.kind ?? 'item';
  // ⚠️The last tick ends the card only where cards wait to be tried — 검증
  // (유저 2026-08-31: 「그냥 내가 실기 확인 제출해서 0개 되면 사라지는데」,
  // said of that section). A card that moved on with a check still unticked
  // keeps its place: this check passing is not the card finishing, the same
  // law [foldChecksIntoCards] keeps the other way round. ⚠️No card at all is
  // a PR stand-in, and ticking one buries it, as it always did.
  final ends =
      last && (card == null || statusOf(card) == BoardStatus.verify);
  return [
    {
      'kind': kind,
      'id': id,
      'at': ends ? '완료' : '확인 완료',
      'ref': ref,
      'said': note.isEmpty ? '확인 — 문제 없음' : '확인함',
      'ts': now(),
    },
    // ⚠️Carries the same `ref`: the dedupe key is (text, ref), and two checks
    // answered with the SAME words would otherwise collapse into one — the
    // bug `ref` was added to fix, one row down.
    if (note.isNotEmpty)
      {
        'kind': kind,
        'id': id,
        'at': '유저',
        'ref': ref,
        'said': note,
        'ts': now(),
      },
  ];
}

/// The line a move of [id] to [to] appends, or null when [to] is not a status
/// word. [card] is what the board holds for [id] right now.
///
/// The user's own entry under the word it moved to — `said` is what marks a
/// line as theirs — so the story says who moved the card and when, and the
/// fold places it by that word like any other. ⚠️The card's own kind, for the
/// reason [tickRecords] gives.
Map<String, dynamic>? moveRecord({
  required BoardCard? card,
  required String id,
  required String to,
  required String Function() now,
}) {
  if (!kStatusWord.values.contains(to)) return null;
  return {
    'kind': card?.kind ?? 'item',
    'id': id,
    'at': to,
    'said': '$to${ro(to)} 옮김',
    'ts': now(),
  };
}

// ---------------------------------------------------------------- the board

/// 🆕🚨★★★THE LIVE BOARD IS A LIST AND ONE OPEN CARD (유저 2026-10-02: 「보드가
/// 너무 느려. 피드백같은거 제출누르고 반영되기까지 10초는 걸리는거같아」 ·
/// 「전체적으로도 최대한 프로들이랑 똑같으면되」).
///
/// 🧪Measured before: ONE page of 15.6MB, 97.5% of it the stories folded inside
/// 425 cards nobody had opened, and every submit fetched it whole again to
/// redraw one card — 0.4s to read the file, 0.5s to draw it, seconds more for
/// the browser to parse it. ⇒ The page is a shell ([_shell]); the list is a
/// JSON of card HEADS ([_headOf]); a card's body is drawn only when it is
/// opened ([_detail]). That is the list-and-detail shape every tracker uses,
/// and the body is drawn by the very same renderers the old page used.
///
/// ⛔No timer and no push: the board changes when a person acts on it or
/// reloads it (유저 2026-08-31: 「그냥 새로고침 누르면 갱신되도록」).

/// The file as last read. ⚠️Re-read when it changes, and after a minute even
/// if it did not: 하는 중 expires by the clock ([wentQuiet]), not by a write.
({int size, DateTime modified, DateTime at, List<BoardCard> cards})? _held;

List<BoardCard> _board() {
  final file = File(_recordsPath);
  final stat = file.statSync();
  final held = _held;
  if (held != null &&
      held.size == stat.size &&
      held.modified == stat.modified &&
      DateTime.now().difference(held.at) < const Duration(minutes: 1)) {
    return held.cards;
  }
  final cards = readBoard(file);
  _held = (
    size: stat.size,
    modified: stat.modified,
    at: DateTime.now(),
    cards: cards,
  );
  return cards;
}

/// What every body renderer reads besides its own card — set before any body
/// is drawn.
void _prepare(List<BoardCard> entries, _Gh gh) {
  // `deleted` joins `archived` as a state that stops a card being drawn. Two
  // words for two different endings, kept apart on purpose: 「archived」 is I
  // put this away, 「deleted」 is the user ticked it and it is finished. The
  // file keeps both lines either way.
  // ⚠️And a record folded into another card is not a card here either — see
  // [foldQuestionsIntoCards]. It is still reachable through the entry that
  // holds it, which is the only place it should now be seen.
  final alive = entries
      .where((e) =>
          e.state != 'archived' && e.state != 'deleted' && e.foldedInto == null)
      .toList();
  // Laws are not work: they never appear as a card of their own, they attach
  // to the cards whose tag they name.
  _laws = alive.where((e) => e.kind == 'law').toList();
  _records = alive.where((e) => e.kind == 'record').toList();
  // The question index — see [_byOrigin] for why it reads `entries` and not
  // `alive`.
  final byOrigin = <String, List<BoardCard>>{};
  for (final e in entries) {
    if (!cardAsks(e)) continue;
    final (of, _) = asksOf(e);
    if (of.isEmpty) continue;
    (byOrigin[of] ??= []).add(e);
  }
  for (final list in byOrigin.values) {
    list.sort((a, b) {
      final (_, x) = asksOf(a);
      final (_, y) = asksOf(b);
      return x.compareTo(y);
    });
  }
  _byOrigin = byOrigin;
  _prState = {for (final pr in gh.prs) pr.number: pr.state};
}

/// Whether [e] is a card a person works on — not a law, a record or a build,
/// and not a question folded into the card that asked it.
bool _isCard(BoardCard e) =>
    e.foldedInto == null &&
    !const {'law', 'record', 'build', 'meta'}.contains(e.kind);

/// How long a finished card stays on the 완료 list. Older ones are still found
/// by search ([_find]); a list of every card ever finished is not a list.
const _doneShows = Duration(days: 14);

bool _ended(BoardStatus s) =>
    s == BoardStatus.done || s == BoardStatus.canceled;

/// 분류 대기 receives different arrivals, and which one a row is decides what
/// I do with it. The chip says so on the row (유저 2026-08-26: 「분류전으로
/// 옮기고 대답 태그 붙이면」). ⚠️Plain feedback and ideas already carry their
/// own tag from intake, so only the returning kinds need one.
String _arrivalOf(BoardCard e) {
  // 🚨A card that arrived because a question of its was ANSWERED is something
  // to READ, not a half-finished filing.
  final answeredQuestion =
      (_byOrigin[e.id] ?? const <BoardCard>[]).any((q) => q.answer != null);
  return switch (e.kind) {
    'decision' => '대답',
    'check' => '실기 피드백',
    // An item only 「arrives」 if the user wrote on it — a plain working card
    // has nothing new to announce.
    _ => e.answer != null
        ? '유저 피드백'
        : (answeredQuestion && e.state == 'inbox' ? '대답' : ''),
  };
}

/// Where a card stands on the live board: [statusOf], and a card with an open
/// PR is in flight whatever its story last said.
///
/// 🚨★★★지금 IS BUILT FROM CARDS (유저 2026-08-27: 「이거 답할것이 원본
/// 카드에서 포인터로서 존재하는거랑 똑같은 규칙이나 로직 적용하면
/// 지금항목에 새 카드가 추가되는게아니라 카드에 공정으로서 포인터로
/// 기록하면 확실할거같은데 어때. 규칙 통일화되는거지」). A PR is something
/// that HAPPENED to a card, which is what a 구현 stage already says; a card in
/// flight is a card whose PR is open.
BoardStatus _liveStatus(BoardCard e, Set<int> openPrs) {
  final status = statusOf(e);
  final idle = status == BoardStatus.triage ||
      status == BoardStatus.backlog ||
      status == BoardStatus.discussion ||
      status == BoardStatus.todo;
  return idle && e.prs.any(openPrs.contains) ? BoardStatus.doing : status;
}

/// One card's HEAD — everything a list row shows, and nothing of its story.
Map<String, Object?> _headOf(BoardCard e, Set<int> openPrs) {
  final status = _liveStatus(e, openPrs);
  final turn = turnOf(e);
  final waiting = checksWaiting(e);
  return {
    'id': e.id,
    'title': e.title.isEmpty ? e.id : e.title,
    'status': status.name,
    'q': [
      for (final q in openQuestions(e))
        if (q.title.isEmpty) q.id else q.title,
    ],
    'checks': waiting.length,
    'since': waiting.isEmpty ? '' : waiting.first,
    'user': turn.user,
    'me': turn.me,
    'arrival': _arrivalOf(e),
    'prio': e.priority,
    'owner': ownerOf(e),
    'type': e.tags.where(kTypeTags.contains).firstOrNull ?? '',
    'areas': [for (final t in e.tags) if (!kTypeTags.contains(t)) t],
    'created': e.created,
    'updated': e.updated,
    'gap': _isGap(e),
    'prs': [
      for (final n in e.prs) {'n': n, 'state': _prState[n] ?? ''},
    ],
  };
}

/// Every PR stand-in: an open PR that no card claims.
///
/// 🚨★★★THE ROWS COME FROM CARDS, NOT FROM `gh pr list` — `--limit 40` is a
/// window that slides, and one PR can close several cards. An open PR NOBODY
/// claimed still gets a stand-in: not a row pretending to be a card, but the
/// board saying a merge is coming with nothing written about it.
///
/// 🚨A PR WHOSE CARD IS DEAD MUST NOT COME BACK AS A PLACEHOLDER. ⚠️Read from
/// ALL cards: the dead ones are precisely the ones a live-only list leaves
/// out, and ticking a landing left it on screen that way once.
List<BoardCard> _standIns(List<BoardCard> entries, _Gh gh) {
  final claimed = <int>{
    for (final e in entries)
      if (e.state != 'archived' && e.state != 'deleted') ...e.prs,
  };
  final buriedIds = <String>{};
  final buriedPrs = <int>{};
  for (final e in entries) {
    if (e.state != 'archived' && e.state != 'deleted') continue;
    buriedIds.add(e.id);
    buriedPrs.addAll(e.prs);
  }
  return [
    for (final pr in gh.prs)
      if (pr.state == 'OPEN' &&
          !claimed.contains(pr.number) &&
          !buriedPrs.contains(pr.number) &&
          !buriedIds.contains('pr-${pr.number}'))
        _prEntry(pr)..prs.add(pr.number),
  ];
}

/// The list: every live card's head, the finished ones of the last two weeks,
/// the builds, and what the machine says — checkouts and PRs.
Future<Map<String, Object?>> _boardJson() async {
  final entries = _board();
  final gh = await _prs();
  final gits = await _checkouts();
  _prepare(entries, gh);
  final openPrs = {
    for (final pr in gh.prs)
      if (pr.state == 'OPEN') pr.number,
  };
  final since = DateTime.now().subtract(_doneShows);
  final heads = <Map<String, Object?>>[];
  for (final e in [...entries.where(_isCard), ..._standIns(entries, gh)]) {
    if (_ended(statusOf(e))) {
      final at = DateTime.tryParse(e.updated);
      if (at == null || at.isBefore(since)) continue;
    }
    heads.add(_headOf(e, openPrs));
  }
  return {
    'cards': heads,
    'builds': [
      for (final b in buildsOf(entries)) {'ts': b.ts, 'commit': b.commit},
    ],
    'checkouts': [
      for (final c in gits)
        {
          'name': c.path.split(RegExp(r'[\\/]')).last,
          'path': c.path,
          'branch': c.branch,
          'ahead': c.ahead,
          'behind': c.behind,
          'dirty': c.dirty,
        },
    ],
    'prs': [
      for (final pr in gh.prs)
        {
          'n': pr.number,
          'state': pr.state,
          'title': pr.title,
          'checks': pr.checks,
          'merged': pr.mergedAt?.toIso8601String(),
        },
    ],
    'ghOk': gh.ok,
    'bad': badLines,
  };
}

/// Finished cards older than the 완료 list, found by search — the list stays
/// short and nothing that ever happened is out of reach.
List<Map<String, Object?>> _find(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final entries = _board();
  final since = DateTime.now().subtract(_doneShows);
  final out = <Map<String, Object?>>[];
  for (final e in entries.where(_isCard).toList().reversed) {
    if (!_ended(statusOf(e))) continue;
    final at = DateTime.tryParse(e.updated);
    if (at != null && !at.isBefore(since)) continue;
    final hay = '${e.id} ${e.title} ${e.tags.join(' ')}'.toLowerCase();
    if (!hay.contains(q)) continue;
    out.add(_headOf(e, const {}));
    if (out.length >= 40) break;
  }
  return out;
}

/// One card, opened: its head as fields, then its body.
String _detail(List<BoardCard> entries, _Gh gh, String id) {
  _prepare(entries, gh);
  final openPrs = {
    for (final pr in gh.prs)
      if (pr.state == 'OPEN') pr.number,
  };
  final card = entries.where((c) => c.id == id && _isCard(c)).firstOrNull ??
      _standIns(entries, gh).where((c) => c.id == id).firstOrNull;
  if (card == null) {
    return '<p class="d gone">「${_esc(id)}」 는 지금 보드에 없습니다.</p>';
  }
  return _article(card, openPrs);
}

/// The body each card is drawn with. ⚠️data-kind is what `send` writes back:
/// a question card answers, a card in 검증 is ticked per check, and every
/// other card takes feedback — `item` so a memo on a working card is filed as
/// feedback and comes back to me, exactly like one left on a 확인할 것 row,
/// ⛔and NOT as `check`, which would delete the card if the box were
/// submitted empty.
String _article(BoardCard e, Set<int> openPrs) {
  final status = _liveStatus(e, openPrs);
  final kind = cardAsks(e)
      ? 'decision'
      : (status == BoardStatus.verify ? 'check' : 'item');
  final body = switch (kind) {
    'decision' => _askCardBody(e),
    'check' => _checkCardBody(e),
    _ => _itemCardBody(e),
  };
  final id = _esc(e.id);
  final b = StringBuffer();
  b.writeln('<article class="p det" id="c-$id" data-kind="$kind" '
      'data-status="${status.name}">');
  b.writeln('<header class="dh">');
  b.writeln('<div class="dtop"><span class="did">$id</span>'
      '<span class="state"></span></div>');
  b.writeln('<h2 class="dt">${_esc(e.title.isEmpty ? e.id : e.title)}</h2>');
  b.writeln('<dl class="fields">');
  // 🆕ONE PRESS MOVES THE CARD — see `/move` for the decision it reverses.
  b.write('<dt>상태</dt><dd><select class="move" '
      'onchange="move(\'$id\', this.value, this)">');
  for (final s in BoardStatus.values) {
    final selected = s == status ? ' selected' : '';
    b.write('<option value="${kStatusWord[s]}"$selected>'
        '${kStatusName[s]}</option>');
  }
  b.writeln('</select></dd>');
  b.write('<dt>우선순위</dt><dd><span class="seg">');
  for (final p in const ['긴급', '높음', '보통', '낮음', '']) {
    final on = e.priority == p ? ' aria-pressed="true"' : '';
    b.write('<button type="button"$on '
        'onclick="setPrio(\'$id\', \'$p\', this)">${p.isEmpty ? '미정' : p}</button>');
  }
  b.writeln('</span></dd>');
  final owner = ownerOf(e);
  b.writeln('<dt>담당</dt><dd>${owner.isEmpty ? '<span class="none">미정</span>' : _esc(owner)}</dd>');
  if (e.tags.isNotEmpty) {
    b.writeln('<dt>태그</dt><dd>${[
      for (final t in e.tags) '<span class="chip">${_esc(t)}</span>',
    ].join()}</dd>');
  }
  final waiting = checksWaiting(e);
  b.writeln('<dt>날짜</dt><dd class="mono">만든 날 ${_esc(_day(e.created))}'
      ' · 바뀐 날 ${_esc(_day(e.updated))}'
      '${waiting.isEmpty ? '' : ' · 검증 대기 ${_esc(_day(waiting.first))}부터'}'
      '</dd>');
  b.writeln('</dl></header>');
  b.writeln('<div class="body">$body</div>');
  b.writeln('</article>');
  return b.toString();
}

/// The shell: styles, the boot data, the script. The list and the open card
/// are drawn by the script from [_boardJson] and `/card`.
String _shell(Map<String, Object?> boot) {
  // `</` would end the script tag; `<\/` is the same string to JSON.
  final data = jsonEncode(boot).replaceAll('</', r'<\/');
  return '<!doctype html><html lang="ko"><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '<title>Anicel 보드</title><style>${_css()}</style></head><body>'
      '<header class="top"><h1>Anicel 보드</h1>'
      '<input id="q" type="search" placeholder="찾기 — 번호 · 제목 · 태그  /"'
      ' autocomplete="off">'
      '<button class="new" type="button" onclick="compose()">＋ 새로 적기</button>'
      '<span class="stamp" id="stamp"></span></header>'
      '<div class="app"><nav class="rail" id="rail"></nav>'
      '<main class="list" id="list"></main>'
      '<aside class="detail" id="detail"></aside></div>'
      '<script id="boot" type="application/json">$data</script>'
      '<script>${_js()}</script></body></html>';
}

/// 🚨★★★WHAT THE BOARD DRAWS FOR EACH CARD, from cards alone — the public way
/// in, so a test can look at the markup a person acts on.
///
/// ⛔Every board bug on 2026-08-31 was in the renderer and none of them could
/// be caught: a question drawn as an ordinary row, a hands-on check with no
/// memo box, a memo box holding words it no longer edits. The model was right
/// each time.
///
/// ⚠️It takes cards and nothing else. gh and git are what a server fetches; a
/// card with neither still has to be drawn right, and that is exactly the
/// card a test should assert on. Every card the list holds, opened in turn.
String renderCards(List<BoardCard> entries) {
  final gh = _Gh(const [], ok: false);
  _prepare(entries, gh);
  return [
    for (final e in entries.where(_isCard))
      if (!_ended(statusOf(e))) _article(e, const {}),
  ].join('\n');
}

/// The page's script, for a test that asks what the page DOES.
String boardScript() => _js();

/// Every card's head as the list receives it — for a test that asks where a
/// card stands.
List<Map<String, Object?>> boardHeads(List<BoardCard> entries) {
  _prepare(entries, _Gh(const [], ok: false));
  return [
    for (final e in entries.where(_isCard)) _headOf(e, const {}),
  ];
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



/// Every question, filed under the card that raised it.
///
/// ⚠️Built from ALL entries, archived ones included. A question I have already
/// acted on and put away is still part of its card's story, and dropping it
/// would take the ANSWER out of the panel the moment the answer got used —
/// which is the one moment it starts mattering. (Same shape as the bug where
/// a ticked landing came back: `alive` filters out precisely what you need.)
Map<String, List<BoardCard>> _byOrigin = const {};


/// What `gh` says each PR is doing, so a 구현 stage can say it (유저
/// 2026-08-27: 「지금을 만드는게 아니라 구현항목을 잘 활용하면 될거같은데」).
///
/// 🎯The stage already names the PR. Making it name the STATE too is what
/// retires the 지금 section's own row shape: a card in flight is a card whose
/// newest 구현 says 열림, and the section is derived from that rather than
/// walking `gh.prs` and drawing a row per PR.
///
/// ⚠️Empty for a PR outside `gh pr list`'s window, and the stage then says
/// nothing rather than guessing — the same rule the 확인할 것 badge follows.
Map<int, String> _prState = const {};



/// 🚨★★★THE QUESTION ITSELF — where it is asked, why it is stuck, the
/// options, and the box to answer in. Rendered INSIDE the story of the card
/// that raised it (유저 2026-08-31: 「원본 카드 안에 질문 UI 같은 거 만들어서
/// 답할 것 대분류로 옮기는 거지」).
///
/// ⚠️`data-kind="decision"` and the radio name both key off the QUESTION's own
/// id, not the card's — so one card can carry several questions and each
/// submits on its own. The `/submit` contract is untouched: it still receives
/// the question's id and still hands the card back to me.
///
/// ⛔This used to be the whole of `_askPanel`, a panel of its own with its own
/// head and its own row in 답할 것. Splitting the body out is what let one
/// subject stop being two rows.
String _askBody(BoardCard d, {required bool answered}) {
  final b = StringBuffer();
  if (d.where.isNotEmpty) {
    b.writeln('<p class="d"><b>화면에서</b> — ${_esc(d.where)}</p>');
  }
  if (d.why.isNotEmpty) {
    b.writeln('<p class="d"><b>왜 막혔나</b> — ${_esc(d.why)}</p>');
  }
  // 🚨A `recommend` THAT NAMES NO OPTION IS TEXT NOBODY EVER SEES.
  //
  // It is only ever compared against an option key, so prose written there
  // renders as **nothing at all** — I wrote a whole paragraph of reasoning
  // into it on 2026-08-28 and the user never saw a word. ⛔Silence is the
  // wrong failure: show the text and say it is misplaced, so the author
  // finds out and the reader still gets the sentence.
  final recommendsAnOption = d.options.any((o) => '${o['key']}' == d.recommend);
  if (d.recommend != null && d.recommend!.isNotEmpty && !recommendsAnOption) {
    b.writeln('<p class="d"><b>⚠️추천</b> — ${_esc(d.recommend!)}'
        '<br><i>(선택지 키가 아니라 문장이 들어 있어 추천 표시가 안 붙습니다 '
        '— `recommend` 에는 선택지의 번호를 씁니다)</i></p>');
  }
  // ⚠️An ANSWERED question keeps its options on screen but loses the form:
  // the answer is already an entry further down the story, and a live radio
  // beside it would invite a second answer to a settled question.
  if (answered) {
    final picked = d.options.firstWhere(
      (o) => '${o['key']}' == d.answer,
      orElse: () => <String, dynamic>{'label': d.answer},
    );
    b.writeln('<p class="d"><b>→ ${_esc('${picked['label']}')}</b></p>');
    return b.toString();
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
  return b.toString();
}

/// A question whose origin is not in the file is a card in its own right —
/// nothing folded it, so it still needs a body. ⚠️Every other question is
/// drawn by [_story] as an entry of the card that asked it.
String _askCardBody(BoardCard d) => [
      _care(d),
      _recordPanels(d),
      _askBody(d, answered: d.answer != null),
    ].join('\n');

/// A card in 검증 — waiting to be tried on a device.
///
/// ⛔THIS PANEL USED TO SERVE TWO LISTS. 최근 착지 came from `gh` for free
/// but had NOWHERE to report a result; 실기 확인 had the memo box but had to
/// be hand-written — so one change got written twice, once as an item note
/// and again as a check card (유저 2026-08-26: 「둘다 뭐가 작업됬는지 하나
/// 하나 확인하는용이라서. 그래서 너가 두군데 써넣는것도 힘들거고」).
/// Merging them into one panel was right; what was still wrong is that a
/// MERGE put a card here at all. 유저 2026-08-31 ended that, and with it went
/// the `#1236` badge, the 실기 chip that told the two halves apart, and the
/// nested sub-checks. There is one shape now, so nothing needs naming.
///
/// The two ANSWERS stay distinct, because they mean different things and cost
/// different amounts (유저 확정): the TICK is 「봤고 문제 없음」 and sweeps
/// many rows at once through 확인; the MEMO is 「문제가 있다」 and is written
/// per row. ⚠️The sweep is the list's now — a box on each row and one 확인
/// for the ones picked — and the memo is the box beside each check here.
///
/// data-kind is `check` ([_article]): the result of looking at a thing is a
/// check result. ⚠️It also routes the submit — a tick writes 완료, a memo
/// comes back as 유저 (see `/submit`).
String _checkCardBody(BoardCard c) {
  final b = StringBuffer();
  b.writeln(_care(c));
  b.writeln(_recordPanels(c));
  if (_isGap(c)) {
    // ⛔Said out loud rather than papered over. The row stays tickable — the
    // user may well have opened the PR and been satisfied — but it must not
    // pretend to be a written check, because a tick on one of these buries
    // work nobody ever described.
    b.writeln('<p class="d gap"><b>카드 없음</b> — 이 착지에는 '
        '「무엇을 볼지」를 적은 카드가 없습니다. 제목도 PR 제목 그대로입니다.</p>');
  }
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
  // 🚨★★★ONE CHECK, ONE BOX. This card used to carry a second memo box of
  // its own under the story, with its own wording (「비워 두면 OK」) and its
  // own button (제출). When every 실기 확인 entry grew its own box (#1427),
  // that made TWO boxes asking one question — and `send()` reads
  // `c.querySelector('textarea')`, THE FIRST ONE IN THE CARD.
  //
  // ⛔So typing 「73프레임이 하얗다」 into the lower box and pressing 제출 read
  // the EMPTY upper box, decided the tick was clean, and wrote 「확인 — 문제
  // 없음」. The words were gone and the card closed as fine. That is precisely
  // the failure #1427 existed to end, reintroduced by #1427.
  //
  // ⚠️Nothing is stranded: measured on the live board, all 57 check cards
  // carry at least one per-entry 확인 (55 have one, 2 have two). The control
  // moved INTO the check it answers, which is where 유저 asked for it —
  // 「실기확인 항목마다 메모란도 존재해야하지않을까? 원래 실기확인은 그렇잖아」.
  b.writeln(_shotStrip(c.id));
  return b.toString();
}

/// A stand-in for a PR that no board item ever claimed — a landing the records
/// know nothing about. It has the PR's own title and nothing else, which is
/// exactly what 최근 착지 showed for those before.
BoardCard _prEntry(_Pr pr) => BoardCard('pr-${pr.number}', 'item')..title = pr.title;

/// Whether a 확인할 것 row is a stand-in rather than a card somebody wrote.
///
/// 🚨A landing with no card is a GAP, not a check (유저 2026-08-27: 「이거 pr
/// 제목이랑 이런거 그대로 사용하는 옛날방식 남아있는데 뭐지? 우리 실기확인
/// 카드 어떻게 만드는지 다 얘기나눳지? 전혀 안지켜져있는데?」).
///
/// The row carries an English PR title and nothing else — no 이렇게 본다, no
/// 왜 중요한가, no story. It cannot tell anyone what to look at, and dressing
/// it up as a check row hid that: eighteen of them were sitting in the list
/// looking exactly like the written ones.
bool _isGap(BoardCard e) => e.id.startsWith('pr-');

/// A working card's body: its laws and records, its story, and a box for
/// feedback — or, while it is still a filing nobody has sorted, the box that
/// adds to it.
String _itemCardBody(BoardCard e) {
  final inbox = e.state == 'inbox';
  // 🚨A card that arrived because a question of its was ANSWERED. The inbox
  // editor exists to fix a filing made mid-thought; an origin pushed here by
  // an answer is something to READ, and the editor branch does not draw the
  // questions — so the answer it came to deliver would be the one thing
  // hidden.
  final answeredQuestion =
      (_byOrigin[e.id] ?? const <BoardCard>[]).any((q) => q.answer != null);
  // The user's own writing is not editable once it is an ANSWER — editing it
  // would rewrite what they said, which is the one thing this whole redesign
  // exists to stop.
  // ⚠️`answer == null` too: an item that came BACK carrying feedback is not a
  // half-finished filing to correct, it is something to read. Showing it in an
  // edit box would offer to rewrite what the user just said.
  final editable =
      inbox && e.kind == 'item' && e.answer == null && !answeredQuestion;
  final b = StringBuffer();
  if (editable) {
    // 🚨★★★EMPTY, because what this button does is ADD (유저 2026-08-31:
    // 「지금은 그게아니라 **추가로 메모다는거잖아. 그 구조는 좋은데**
    // 메모입력란에 과거에 입력한 텍스트가 그대로 남아있으니까 입력한
    // 메모를 수정하는건가 처럼 느껴져. 그러니 **메모란 비어있도록**」).
    //
    // ⛔It was prefilled with the last thing said, from when this really
    // was an edit box. `/edit` has appended to the story for a while now
    // (each distinct text becomes its own dated 유저 메모 line), so the old
    // words sitting in the box were the control describing an action it no
    // longer takes — and pressing it unchanged wrote nothing at all, because
    // identical text dedupes.
    //
    // ⚠️Empty box ⇒ empty submit must be REFUSED. The head fields ARE
    // last-wins, so a blank press would leave the card with no summary and
    // no title. The story is right above; this box is only its next line.
    // 🚨★★★AND ITS STORY, ALWAYS. A card in 분류 전 used to show the edit box
    // and NOTHING ELSE, so a card that arrived here because the user pressed
    // 「나중에 로」 showed no sign of having been asked — the request was in
    // the file and invisible on screen. ⛔That is the same 「별개로 둠」 this
    // round is removing everywhere else (유저: 「싹 다 타임라인흐름이야」).
    b.writeln(_story(e));
    b.writeln('<textarea rows="4" placeholder="덧붙일 말 — 위의 이야기에 '
        '한 줄로 붙습니다 (스크린샷은 Ctrl+V)"></textarea>');
    b.writeln(_shotStrip(e.id));
    b.writeln('<div class="foot">'
        '<button onclick="save(\'${_esc(e.id)}\')">추가</button>'
        '<button class="ghost" onclick="purge(\'${_esc(e.id)}\')">삭제</button>'
        '<span class="state"></span></div>');
    return b.toString();
  }
  b.writeln(_care(e));
  b.writeln(_recordPanels(e));
  if (_isGap(e)) {
    b.writeln('<p class="d gap"><b>카드 없음</b> — 이 PR에는 '
        '「무엇을 하는 일인지」를 적은 카드가 없습니다. 제목도 PR 제목 '
        '그대로입니다.</p>');
  }
  b.writeln(_story(e));
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
String _care(BoardCard e) {
  final hits = _laws.where((l) => e.tags.contains(l.tag) && l.care.isNotEmpty);
  if (hits.isEmpty) return '';
  final b = StringBuffer();
  // 🚨ONE item, folded, first (유저 2026-08-26: 「항목이름 작업전 확인 으로
  // 바꾸고 분야별로 항목 만드는게아니라 옛날처럼 그대로하는데 그걸 작업전확인에
  // 몰아넣는거야」).
  //
  // ⛔An item per area was me letting the DATA's shape (one law record per
  // tag) pick the UI's shape. To a reader they are one thing — what to know
  // before starting — and splitting them made a card with two laws look like
  // it had two different warnings to weigh.
  //
  // It leads because it is the one thing to read BEFORE the work rather than
  // during it, and it folds because it is long enough to push the card's own
  // story off the screen.
  final laws = hits.toList();
  final areas = laws
      .map((l) => l.id.startsWith('law-') ? l.id.substring(4) : l.id)
      .join(' · ');
  b.write('<details class="lg care">'
      '<summary><span class="lgk">작업전 확인</span>'
      '<span class="lgp">${_esc(areas)}</span></summary>');
  for (final l in laws) {
    b.write('<p class="d">${_esc(l.care)}</p>');
  }
  b.write('</details>');
  return b.toString();
}

/// Area laws, refreshed on every render from the records file.
List<BoardCard> _laws = const [];

/// Area REFERENCE records (`kind: record`) — living tables a card's area
/// keeps current (the first one: which TVPaint versions the .tvpp import
/// is verified against). Same attach-by-tag scheme as laws, same folded
/// styling, different verb: a law says what breaks if you start without
/// knowing; a record says what is currently true.
List<BoardCard> _records = const [];

/// The area's records, folded under the card the same way its law is.
String _recordPanels(BoardCard e) {
  final hits =
      _records.where((r) => e.tags.contains(r.tag) && r.care.isNotEmpty);
  if (hits.isEmpty) return '';
  final b = StringBuffer();
  final records = hits.toList();
  final titles =
      records.map((r) => r.title.isEmpty ? r.id : r.title).join(' · ');
  b.write('<details class="lg">'
      '<summary><span class="lgk">기록</span>'
      '<span class="lgp">${_esc(titles)}</span></summary>');
  for (final r in records) {
    if (records.length > 1 && r.title.isNotEmpty) {
      b.write('<p class="d"><b>${_esc(r.title)}</b></p>');
    }
    for (final line in r.care.split('\n')) {
      if (line.trim().isEmpty) continue;
      b.write('<p class="d">${_esc(line)}</p>');
    }
  }
  b.write('</details>');
  return b.toString();
}

/// The 구현 stage's chip: the number, and what that PR is doing right now.
///
/// ⛔A PR outside `gh pr list`'s window gets the number alone. Saying 「머지」
/// because it is old would be a guess, and the disappearing-row round already
/// paid for guessing about what the window cannot see.
String _prChip(int number) {
  final state = _prState[number];
  final (word, cls) = switch (state) {
    'OPEN' => ('열림', 'run'),
    'MERGED' => ('머지', 'ok'),
    'CLOSED' => ('닫힘', 'bad'),
    _ => ('', 'ok'),
  };
  return '<span class="chip $cls">#$number${word.isEmpty ? '' : ' · $word'}'
      '</span>';
}

/// One entry, rendered. Split out so a 대분류 and the 소분류 inside it are
/// drawn by the SAME code — the difference between them is where they sit,
/// not what they look like.
String _entryRow(BoardCard e, int i, {required bool open}) {
  final entry = e.log[i];
  final flat = entry.text.replaceAll('\n', ' ');
  final peek = flat.length > 44 ? '${flat.substring(0, 44)}…' : flat;
  final mine = stageName(e, i);
  // 🚨★★★ONE READER FOR 「아직 남은 것인가」 — [stillOwed] AND THIS.
  // 남은 것 is one record among others: only the LAST word is still owed.
  final leftover = mine == '남은 것';
  final live = leftover && lastSection(e) == '남은 것' && _lastIsThis(e, i);
  final ask = entry.ask;
  final answered = ask?.answer != null;
  // 🆕유저 2026-10-02: 「실기확인 눈에 안띄니까 질문처럼 답함 대기 이런 태그
  // 붙이고싶어」 — a hands-on check wears the question's chip, in the
  // question's place: 확인함 once ticked, 대기 until then.
  final check = mine == '실기 확인' || mine == '검증';
  final checked = check && _cleared(e, entry.ts);
  final b = StringBuffer();
  // ⚠️`open` is an ATTRIBUTE, not a class. Written inside the class string it
  // renders as `class="lg open"` — valid HTML, silently folded, and 68 stages
  // that were meant to stand open did not.
  b.writeln('<details class="lg'
      '${entry.byUser || mine.startsWith('유저') ? ' says' : ''}'
      '${ask != null && !answered ? ' q' : ''}'
      '${live ? ' todo' : ''}${leftover && !live ? ' done' : ''}"'
      '${open ? ' open' : ''}'
      '${ask == null ? '' : ' id="c-${_esc(ask.id)}" data-kind="decision"'}>');
  b.writeln('<summary><span class="lgk">${_esc(mine)}</span>'
      '<span class="lgp">${_esc(peek)}</span>'
      '${ask == null ? '' : '<span class="chip ${answered ? 'ok' : 'run'}">'
          '${answered ? '답함' : '대기'}</span>'}'
      '${!check ? '' : '<span class="chip ${checked ? 'ok' : 'run'}">'
          '${checked ? '확인함' : '대기'}</span>'}'
      '${entry.pr == null ? '' : _prChip(entry.pr!)}'
      '<span class="when">${_esc(_day(entry.ts))}</span></summary>');
  if (ask == null) {
    b.writeln('<p class="d">${_esc(entry.text)}</p>');
  } else {
    // 🚨★★★AN ENTRY WITH A TITLE OF ITS OWN KEEPS IT WHEN OPENED (유저
    // 2026-08-31: 「질문 항목처럼 타이틀이 별개로 있는 건 **펼친다고 해서
    // 타이틀 숨기지 마**」).
    //
    // ⛔The summary preview cuts at 44 characters, and opening a question
    // swapped in `where`/`why`/options — which never repeat the title. So the
    // one row whose title is the whole point of it was the one row where the
    // title could only ever be read half-way.
    b.writeln('<p class="d qt"><b>${_esc(entry.text)}</b></p>');
    b.writeln(_askBody(ask, answered: answered));
  }
  if (entry.how.isNotEmpty) {
    b.writeln('<p class="d"><b>이렇게 확인한다</b> — ${_esc(entry.how)}</p>');
  }
  if (entry.pr != null) {
    b.writeln('<p class="d"><a class="chip link" target="_blank" '
        'href="https://github.com/$_repo/pull/${entry.pr}">'
        'PR #${entry.pr} 열기 →</a></p>');
  }
  // 🚨★★★EACH HANDS-ON CHECK IS TICKED ON ITS OWN (유저 2026-08-31: 「실기
  // 확인은 카드 안에 여러 개 존재하니까 **모든 게 ok일 때만 사라져야**
  // 하겠지만」).
  //
  // ⛔One 제출 on the card cleared everything it was holding, so ticking the
  // first of three checks took the other two off the board — and nothing
  // brings them back, because nothing shows them. The form lives on the entry
  // now, exactly like a question's, and the card leaves when the last one is
  // ticked.
  if (check && !checked) {
    // 🚨★★★A MEMO PER CHECK (유저 2026-08-31: 「실기확인 항목마다 메모란도
    // 존재해야하지않을까? **원래 실기확인은 그렇잖아**」).
    //
    // ⛔The card-level box could not answer this: three checks share it, so
    // 「the 73rd frame is white」 written against check 2 arrived attached to
    // nothing. What you saw belongs to the thing you were looking at.
    //
    // ⚠️Same words as the card's own box on purpose — 「문제가 있으면 적어
    // 주세요 — 비워 두면 문제 없음」 is already the sentence this board uses
    // for 「tick, and tell me only if there is something to tell」.
    b.writeln('<div class="tick">');
    b.writeln('<textarea rows="2" placeholder="문제가 있으면 적어 주세요 — '
        '비워 두면 문제 없음 (스크린샷은 Ctrl+V)"></textarea>');
    b.writeln('<div class="foot">'
        '<button onclick="tick(event,\'${_esc(e.id)}\',\'${_esc(entry.ts)}\')">'
        '확인</button>'
        '<span class="state"></span></div>');
    b.writeln('</div>');
  }
  return b.toString();
}

/// Whether entry [i] is the last 대분류 in the story — the one that decides
/// the card's section. ⚠️Reads the same map [lastSection] does.
bool _lastIsThis(BoardCard e, int i) {
  for (var j = e.log.length - 1; j > i; j--) {
    if (kSection.containsKey(stageName(e, j))) return false;
  }
  return true;
}

/// Whether the hands-on check written at [ts] has already been ticked.
///
/// ⚠️ONE READER: [checksWaiting] is what the tick handler counts with, so the
/// button and the word that handler writes can never disagree about which
/// checks are still open. 🧪They DID disagree for one round — this asked only
/// for 「완료」 and never learned about 「확인 완료」, so every button stayed
/// on screen while the count behind them was right.
bool _cleared(BoardCard e, String ts) => !checksWaiting(e).contains(ts);

/// 🚨★★★A 대분류 IS A FOLDER, AND WHAT FOLLOWS IT LIVES INSIDE.
///
/// 유저 2026-08-31: 「걱정인 건 **대분류는 사실 하나의 항목이자 폴더나
/// 마찬가지인데 그게 제대로 UI로서 알기 쉽게 보여지는 건지.** 대분류
/// 펼치고 그 안에 소분류 있고 그거 펼치는 느낌이 직관적일 거 같은데」.
///
/// ⛔The story was ONE FLAT LIST. 🧪`I-4` came out as sixty rows at the same
/// depth — 질문, 남은 것, 상담, 구현, 작업 기록 all side by side — so the
/// model knew which were sections and the screen did not. A reader could not
/// see the spine of the card, only its sediment.
///
/// ⇒ Each 대분류 opens a folder and every 소분류 written after it is drawn
/// inside, until the next 대분류 starts a new one. A folder with nothing
/// inside stays a plain row: that is honest, it really did have nothing
/// written under it.
///
/// ⚠️Entries before the FIRST 대분류 have no folder to be in and are drawn at
/// the top level. Old cards start that way and inventing a folder for them
/// would be putting them somewhere they never were.
String _story(BoardCard e) {
  if (e.log.isEmpty && e.rest.isEmpty) return '<p class="d">메모 없음.</p>';
  // Where each folder starts, and what falls inside it.
  // ⚠️AN ENDING IS NOT A FOLDER (유저 2026-08-31: 「적어도 실기 확인이라는
  // 대분류에서 **소분류로 완료라고 찍히는 게** 맞지 않을까」). A folder holds
  // what was written AFTER it, and nothing is ever written after 완료 — so it
  // opened a folder of one row, sitting beside the hands-on check it belonged
  // to instead of inside it. It still ENDS the card; it just does not hold
  // anything.
  final heads = <int>[];
  for (var i = 0; i < e.log.length; i++) {
    final section = kSection[stageName(e, i)];
    if (section != null && section != 'archived') heads.add(i);
  }
  final b = StringBuffer();
  final firstHead = heads.isEmpty ? e.log.length : heads.first;
  // ⚠️Only the LAST folder stands open (유저 2026-08-31: 「마지막 항목만
  // 펼치기 상태로 두는거고」), and inside it only its last entry.
  for (var i = 0; i < firstHead; i++) {
    b.writeln(_entryRow(e, i, open: heads.isEmpty && i == e.log.length - 1));
    b.writeln('</details>');
  }
  for (var h = 0; h < heads.length; h++) {
    final start = heads[h];
    final end = h + 1 < heads.length ? heads[h + 1] : e.log.length;
    final inside = end - start - 1;
    final lastFolder = h == heads.length - 1;
    b.writeln(_entryRow(e, start, open: lastFolder));
    if (inside > 0) {
      b.writeln('<div class="under">');
      for (var i = start + 1; i < end; i++) {
        b.writeln(_entryRow(e, i, open: lastFolder && i == end - 1));
        b.writeln('</details>');
      }
      b.writeln('</div>');
    }
    b.writeln('</details>');
  }
  return b.toString();
}

/// The page's script: the list, drawn from the heads; the open card, fetched
/// from `/card`; and every action, each followed by ONE fresh read of the
/// list and of the card that is open.
///
/// ⚠️A raw string: `$` is the script's own, never Dart's.
String _js() => r'''
var DATA = JSON.parse(document.getElementById('boot').textContent);
var queued = [];   // screenshots pasted into the composer, not yet filed

// Per-viewer conveniences only — the board itself lives in the records file.
function remember(k, v){
  try {
    if (v === undefined) return localStorage.getItem('board.' + k);
    localStorage.setItem('board.' + k, v);
  } catch (e) { return null; }
  return null;
}

var S = {view: remember('view') || 'me', q: '', owner: null, area: null,
         sel: null, more: {}, picked: new Set(), old: null};

var STATUS = {triage:'분류 대기', backlog:'백로그', discussion:'대화 중',
  todo:'할 일', doing:'진행 중', verify:'검증', known:'알려진 문제', done:'완료',
  canceled:'취소'};
var PRIOS = ['긴급', '높음', '보통', '낮음', ''];
var VIEWS = [['me','나에게 온 것'], ['doing','진행 중'], ['todo','할 일'],
  ['discussion','대화 중'], ['backlog','백로그'], ['triage','분류 대기'],
  ['known','알려진 문제'], ['done','완료'], ['system','시스템']];
var PAGE = 60;

function esc(s){
  return String(s == null ? '' : s).replace(/[&<>"']/g, function(c){
    return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];
  });
}
function day(ts){ return ts ? ts.slice(5, 10) : ''; }
function age(ts){
  var t = Date.parse(ts || '');
  return isNaN(t) ? null : Math.max(0, Math.floor((Date.now() - t) / 864e5));
}
function prioRank(p){ var i = PRIOS.indexOf(p || ''); return i < 0 ? 4 : i; }
function live(c){ return c.status !== 'done' && c.status !== 'canceled'; }
function oldest(k){ return function(a, b){ return (a[k] || '') < (b[k] || '') ? -1 : 1; }; }
function newest(k){ return function(a, b){ return (a[k] || '') < (b[k] || '') ? 1 : -1; }; }

function matches(c){
  if (S.owner !== null && (c.owner || '') !== S.owner) return false;
  if (S.area !== null && c.areas.indexOf(S.area) < 0) return false;
  if (!S.q) return true;
  var hay = (c.id + ' ' + c.title + ' ' + c.areas.join(' ') + ' ' + c.type +
    ' ' + (c.owner || '')).toLowerCase();
  return hay.indexOf(S.q.toLowerCase()) >= 0;
}

// Verification belongs to the build it is tried on, the way a QA list does:
// what this build brought, what landed after it, what was carried over. With
// no build marked yet it falls back to the day each card landed.
function verifyGroups(rows){
  var b = DATA.builds;
  if (b.length) {
    var last = b[b.length - 1];
    var prev = b.length > 1 ? b[b.length - 2] : null;
    // ⚠️Two weeks unlooked-at is its own pile whatever the builds say: the
    // first build marked has no build before it, and would otherwise hand
    // over everything ever left as 「this build」.
    var stale = function(c){ return age(c.since) > 14; };
    var after = rows.filter(function(c){ return c.since > last.ts; });
    var before = rows.filter(function(c){ return c.since <= last.ts; });
    var inBuild = before.filter(function(c){ return !stale(c) && (!prev || c.since > prev.ts); });
    var carried = before.filter(function(c){ return !stale(c) && prev && c.since <= prev.ts; });
    return [
      {t:'이 빌드에서 볼 것', note: last.commit + ' · ' + day(last.ts) + ' 빌드', rows: inBuild},
      {t:'다음 빌드에서', note:'빌드 뒤에 착지', rows: after},
      {t:'이월', note:'지난 빌드부터', rows: carried, fold: true},
      {t:'이월 · 2주 넘음', rows: before.filter(stale), fold: true},
    ];
  }
  var spans = [['오늘 · 어제', 0, 1], ['이번 주', 2, 7], ['지난주', 8, 14], ['2주 넘음', 15, 1e9]];
  return spans.map(function(s, i){
    return {t: s[0], note: i === 0 ? '빌드 기록 전 — 착지한 날로 묶음' : '',
      rows: rows.filter(function(c){ var a = age(c.since); return a >= s[1] && a <= s[2]; }),
      fold: i >= 2};
  });
}

function byKey(rows, key, order){
  var groups = {};
  rows.forEach(function(c){ (groups[key(c)] = groups[key(c)] || []).push(c); });
  var names = Object.keys(groups);
  if (order) names.sort(order);
  return names.map(function(n){ return {t: n, rows: groups[n]}; });
}

function groupsFor(view){
  var pool = DATA.cards.filter(matches);
  if (S.q) {
    var found = pool.slice().sort(function(a, b){
      return (live(a) ? 0 : 1) - (live(b) ? 0 : 1) || (a.updated < b.updated ? 1 : -1);
    });
    var g = byKey(found, function(c){ return STATUS[c.status]; });
    if (S.old && S.old.length) g.push({t: '지난 카드', rows: S.old});
    return g;
  }
  // What the user can press: a question to answer, a check to tick. ↩️A 답
  // 기다림 group stood here and listed 대화 중 cards — see `BoardStatus`.
  if (view === 'me') {
    var decide = pool.filter(function(c){ return live(c) && c.q.length; }).sort(oldest('updated'));
    var checks = pool.filter(function(c){ return live(c) && !c.q.length && c.checks > 0; }).sort(oldest('since'));
    var out = [{t:'결정 필요', rows: decide, skip: ['decide']}];
    verifyGroups(checks).forEach(function(x){
      x.t = '검증 · ' + x.t; x.pick = true; x.skip = ['check']; out.push(x);
    });
    return out;
  }
  if (view === 'doing') {
    var doing = pool.filter(function(c){ return c.status === 'doing'; }).sort(newest('updated'));
    return byKey(doing, function(c){ return c.owner || '담당 미정'; }).map(function(g){
      // WIP: a session holding more than two at once is spread thin.
      if (g.rows.length > 2 && g.t !== '담당 미정') g.note = '동시에 ' + g.rows.length + '장';
      return g;
    });
  }
  if (view === 'todo' || view === 'discussion' || view === 'backlog') {
    var rows = pool.filter(function(c){ return c.status === view; });
    var stale = view === 'backlog' ? rows.filter(function(c){ return age(c.updated) > 30; }) : [];
    var fresh = rows.filter(function(c){ return stale.indexOf(c) < 0; });
    var g2 = byKey(fresh, function(c){ return c.prio || '미정'; }, function(a, b){
      return prioRank(a === '미정' ? '' : a) - prioRank(b === '미정' ? '' : b);
    }).map(function(g){ g.rows.sort(oldest('updated')); g.skip = ['prio']; return g; });
    if (stale.length) g2.push({t:'30일 넘게 그대로', rows: stale.sort(oldest('updated')), fold: true});
    return g2;
  }
  if (view === 'triage') {
    return [
      {t:'새로 들어온 것', rows: pool.filter(function(c){ return c.status === 'triage'; }).sort(oldest('created'))},
      {t:'사용자가 덧붙임', note:'제 차례', skip: ['me'], rows: pool.filter(function(c){
        return live(c) && c.status !== 'triage' && c.me; }).sort(oldest('updated'))},
    ];
  }
  if (view === 'known') {
    return [{t:'알려진 문제', rows: pool.filter(function(c){ return c.status === 'known'; }).sort(newest('updated'))}];
  }
  if (view === 'done') {
    return [
      {t:'완료', note:'최근 14일', rows: pool.filter(function(c){ return c.status === 'done'; }).sort(newest('updated'))},
      {t:'취소', rows: pool.filter(function(c){ return c.status === 'canceled'; }).sort(newest('updated'))},
    ];
  }
  return [];
}

function countFor(view){
  if (view === 'system') return DATA.checkouts.length;
  var seen = {};
  groupsFor(view).forEach(function(g){ g.rows.forEach(function(c){ seen[c.id] = 1; }); });
  return Object.keys(seen).length;
}

// 🚨★★★NO CHIP THAT REPEATS ITS OWN GROUP (유저 2026-08-31: 「나중에 항목의
// 나중에 태그 필요없고, 대화중도 필요없고 … 답할것도 답할것 태그
// 필요없고」) — each group names the flags its rows would only repeat.
// 🆕The 실기 대기 chip (유저 2026-10-02: 「실기확인 눈에 안띄니까 질문처럼 답함
// 대기 이런 태그 붙이고싶어」): a check still waiting on a card that has moved
// on is folded inside its story, so the row says so.
function flagsOf(c){
  var f = [];
  if (c.q.length) f.push(['decide', '결정 필요' + (c.q.length > 1 ? ' ' + c.q.length : ''), 'run']);
  if (c.checks && c.status !== 'verify') f.push(['check', '실기 대기', 'run']);
  if (c.me && c.status !== 'triage') f.push(['me', '제 차례', 'live']);
  if (c.arrival) f.push(['arrival', c.arrival, c.arrival === '대답' ? 'ok' : 'bad']);
  if (c.gap) f.push(['gap', '카드 없음', 'bad']);
  return f;
}

function rowHtml(c, g){
  var skip = g.skip || [];
  var chips = flagsOf(c).filter(function(f){ return skip.indexOf(f[0]) < 0; })
    .map(function(f){ return '<span class="chip ' + f[2] + '">' + esc(f[1]) + '</span>'; }).join('');
  var when = c.checks ? c.since : c.updated;
  var a = age(when);
  var pick = g.pick
    ? '<input type="checkbox" class="pick" data-pick="' + esc(c.id) + '"' + (S.picked.has(c.id) ? ' checked' : '') + '>'
    : '<span class="dot s-' + c.status + '" title="' + STATUS[c.status] + '"></span>';
  var prio = c.prio && skip.indexOf('prio') < 0 ? '<span class="pri p' + prioRank(c.prio) + '">' + esc(c.prio) + '</span>' : '';
  var areas = c.areas.slice(0, 2).map(function(t){ return '<span class="chip">' + esc(t) + '</span>'; }).join('');
  return '<div class="row" tabindex="0" data-id="' + esc(c.id) + '" aria-selected="' + (S.sel === c.id) + '">' +
    pick + '<span class="rid">' + esc(c.id) + '</span>' +
    '<span class="rt">' + prio + '<span class="tt">' + esc(c.title) + '</span>' + chips + '</span>' +
    '<span class="rm">' + areas + (c.owner ? '<span class="own">' + esc(c.owner) + '</span>' : '') +
    '<span class="age' + (a > 14 ? ' old' : '') + '" title="' + esc(when) + '">' +
    (c.checks ? '착지 ' : '') + day(when) + ' · ' + (a === null ? '-' : a) + '일</span></span></div>';
}

function renderRail(){
  var rail = document.getElementById('rail');
  var html = '<div class="views">' + VIEWS.map(function(v){
    var n = countFor(v[0]);
    return '<button class="view' + (v[0] === 'me' && n ? ' hot' : '') + '" data-view="' + v[0] +
      '" aria-current="' + (S.view === v[0] && !S.q) + '"><span class="dot s-' + v[0] + '"></span>' +
      '<span>' + v[1] + '</span><span class="n">' + n + '</span></button>';
  }).join('') + '</div>';
  var owners = {}, areas = {};
  DATA.cards.forEach(function(c){
    if (!live(c)) return;
    owners[c.owner || ''] = (owners[c.owner || ''] || 0) + 1;
    c.areas.forEach(function(t){ areas[t] = (areas[t] || 0) + 1; });
  });
  function facet(title, map, attr, on){
    return '<div class="facet"><h3>' + title + '</h3><div class="chips">' +
      Object.keys(map).sort(function(a, b){ return map[b] - map[a]; }).map(function(k){
        return '<button class="fchip" data-' + attr + '="' + esc(k) + '" aria-pressed="' + (on === k) + '">' +
          esc(k || '미정') + ' <span class="n">' + map[k] + '</span></button>';
      }).join('') + '</div></div>';
  }
  rail.innerHTML = html + facet('담당', owners, 'owner', S.owner) + facet('영역', areas, 'area', S.area);
}

// 🆕확인 for the picked rows sits beside 모두 고르기, in the group they were
// picked from (유저 2026-10-02: 「검증항목에서 모두고르기 옆에 확인버튼
// 만들어줘」). ⛔It was a bar over the list that appeared only once something
// was picked — UI that pops into existence. Both buttons are always there;
// only their words and whether they can be pressed change.
function pickControls(g, i){
  var picked = g.rows.filter(function(c){ return S.picked.has(c.id); }).length;
  var all = g.rows.length > 0 && picked === g.rows.length;
  return '<span class="picks"><button class="ghost sm" data-pickall="' + i + '"' +
    (g.rows.length ? '' : ' disabled') + '>' + (all ? '모두 풀기' : '모두 고르기') + '</button>' +
    '<button class="sm" data-confirm="' + i + '"' + (picked ? '' : ' disabled') + '>확인' +
    (picked ? ' ' + picked + '장' : '') + '</button><span class="state"></span></span>';
}

function renderList(){
  var list = document.getElementById('list');
  if (S.view === 'system' && !S.q) { list.innerHTML = systemHtml(); return; }
  var groups = groupsFor(S.view);
  var title = S.q ? '찾기 — 「' + esc(S.q) + '」' : VIEWS.filter(function(v){ return v[0] === S.view; })[0][1];
  var html = '<div class="vhead"><h2>' + title + '</h2>';
  if (S.view === 'me' && !S.q) {
    html += '<button class="ghost sm" onclick="markBuild(event)" title="지금 master 를 빌드했다고 적습니다 — 검증이 이 빌드 기준으로 묶입니다">이 빌드로 시험 중</button>';
  }
  if (S.view === 'doing' && !S.q) html += '<button class="ghost sm" onclick="refreshPrs(event)">PR 다시 읽기</button>';
  if (S.q && S.old === null) html += '<button class="ghost sm" onclick="findOld()">지난 카드에서도 찾기</button>';
  html += '<span class="state"></span></div>';
  groups.forEach(function(g, i){
    var key = S.view + ':' + g.t;
    var shown = S.more[key] !== undefined ? S.more[key] : (g.fold ? 0 : PAGE);
    html += '<section class="grp"><div class="gh"><span class="gt">' + esc(g.t) + '</span>' +
      '<span class="gn">' + g.rows.length + '</span>' + (g.note ? '<span class="note">' + esc(g.note) + '</span>' : '');
    if (g.pick) html += pickControls(g, i);
    html += '</div>';
    if (!g.rows.length) html += '<p class="none">없음</p>';
    html += g.rows.slice(0, shown).map(function(c){ return rowHtml(c, g); }).join('');
    if (g.rows.length > shown) {
      html += '<button class="more" data-more="' + esc(key) + '">' + (shown ? '더 보기' : '펼치기') +
        ' · ' + (g.rows.length - shown) + '장</button>';
    }
    html += '</section>';
  });
  list.innerHTML = html;
  list._groups = groups;
}

function systemHtml(){
  var h = '<div class="vhead"><h2>시스템</h2><button class="ghost sm" onclick="refreshPrs(event)">PR 다시 읽기</button><span class="state"></span></div>';
  h += '<section class="grp"><div class="gh"><span class="gt">체크아웃</span><span class="gn">' + DATA.checkouts.length + '</span></div>';
  h += DATA.checkouts.map(function(c){
    var trouble = [c.behind ? c.behind + ' 뒤' : '', c.ahead ? c.ahead + ' 앞' : '',
      c.dirty ? '커밋 안 된 파일 ' + c.dirty : ''].filter(Boolean).join(' · ');
    return '<div class="row static"><span class="dot s-system"></span><span class="rid">' + esc(c.name) +
      '</span><span class="rt"><span class="tt mono">' + esc(c.path) + '</span></span><span class="rm">' +
      '<span class="chip">' + esc(c.branch) + '</span><span class="chip ' + (trouble ? 'run' : 'ok') + '">' +
      esc(trouble || 'origin/master 와 같음 · 깨끗') + '</span></span></div>';
  }).join('') + '</section>';
  h += '<section class="grp"><div class="gh"><span class="gt">PR</span><span class="gn">' + DATA.prs.length + '</span>' +
    (DATA.ghOk ? '' : '<span class="note warn">gh 를 못 불렀습니다</span>') + '</div>';
  h += DATA.prs.map(function(p){
    var cls = p.state === 'OPEN' ? 'run' : (p.state === 'MERGED' ? 'ok' : 'bad');
    return '<div class="row static"><span class="dot s-system"></span><span class="rid">#' + p.n +
      '</span><span class="rt"><span class="tt">' + esc(p.title) + '</span></span><span class="rm">' +
      '<span class="chip ' + cls + '">' + esc(p.state) + '</span><span class="chip">' + esc(p.checks) + '</span></span></div>';
  }).join('') + '</section>';
  return h;
}

function renderStamp(){
  var parts = [];
  if (!DATA.ghOk) parts.push('<span class="warn">gh 를 못 불렀습니다 — PR 정보가 비어 있습니다</span>');
  if (DATA.bad && DATA.bad.length) parts.push('<span class="warn">기록 ' + DATA.bad.length + '줄을 읽지 못했습니다 (줄 ' + DATA.bad.join(', ') + ')</span>');
  document.getElementById('stamp').innerHTML = parts.join(' · ');
}

function renderAll(){ renderRail(); renderList(); renderStamp(); }

// ---- the open card

// What a person typed in the open card survives a fresh read of it — except
// in the box whose own submit caused the read, which must come back empty.
function typedIn(pane, skip){
  var typed = {};
  pane.querySelectorAll('[data-kind]').forEach(function(o){
    if (!o.id || o.id === skip) return;
    var i = 0;
    o.querySelectorAll('textarea, input[type=text]').forEach(function(f){
      if (f.closest('[data-kind]') !== o) return;
      if (f.value) typed[o.id + '#' + i] = f.value;
      i++;
    });
  });
  return typed;
}
function putBack(pane, typed){
  pane.querySelectorAll('[data-kind]').forEach(function(o){
    if (!o.id) return;
    var i = 0;
    o.querySelectorAll('textarea, input[type=text]').forEach(function(f){
      if (f.closest('[data-kind]') !== o) return;
      var v = typed[o.id + '#' + i];
      if (v) f.value = v;
      i++;
    });
  });
}

function openCard(id, skip){
  var pane = document.getElementById('detail');
  var same = S.sel === id;
  var typed = same ? typedIn(pane, skip) : {};
  var openRows = [];
  if (same) pane.querySelectorAll('details[open]').forEach(function(d){
    var s = d.querySelector('summary'); if (s) openRows.push(s.textContent);
  });
  S.sel = id;
  document.querySelectorAll('.row[data-id]').forEach(function(r){
    r.setAttribute('aria-selected', String(r.dataset.id === id));
  });
  document.body.classList.add('reading');
  return fetch('/card?id=' + encodeURIComponent(id), {cache: 'no-store'})
    .then(function(r){ return r.text(); })
    .then(function(html){
      if (S.sel !== id) return;
      var top = same ? pane.scrollTop : 0;
      pane.innerHTML = html + '<button class="close ghost sm" onclick="closeCard()">닫기</button>';
      putBack(pane, typed);
      if (same) pane.querySelectorAll('details').forEach(function(d){
        var s = d.querySelector('summary');
        if (s && openRows.indexOf(s.textContent) >= 0) d.open = true;
      });
      pane.scrollTop = top;
    });
}
function closeCard(){
  S.sel = null;
  document.getElementById('detail').innerHTML = '';
  document.body.classList.remove('reading');
  document.querySelectorAll('.row[aria-selected="true"]').forEach(function(r){ r.setAttribute('aria-selected', 'false'); });
}

function loadBoard(){
  return fetch('/api/board', {cache: 'no-store'})
    .then(function(r){ return r.json(); })
    .then(function(d){ DATA = d; });
}
// ONE fresh read after every write: the list, and the open card.
function afterWrite(skip){
  return loadBoard().then(function(){
    renderAll();
    // The composer is not a card: what is typed there is not the server's.
    if (S.sel && S.sel !== 'intake') return openCard(S.sel, skip);
  });
}

// ---- actions

function stateOf(el){ return el ? el.querySelector('.state') : null; }
function say(el, text){ var s = stateOf(el); if (s) s.textContent = text; }
async function post(url, body, el){
  say(el, '저장 중…');
  var r = await fetch(url, {method: 'POST', body: JSON.stringify(body)});
  if (!r.ok) throw new Error(r.status);
  return r.json();
}
function send(id){
  var c = document.getElementById('c-' + id);
  var r = c.querySelector('input[name="ans-' + id + '"]:checked');
  // ⛔Not the first box in the card: a card's story can hold a question's
  // box and a check's box ABOVE its own feedback box, and the first one found
  // was then the one read — the 「ONE CHECK, ONE BOX」 failure in another
  // place. A card's own box is a child of its body; a question's is its own.
  var t = c.dataset.kind === 'item'
    ? c.querySelector(':scope > .body > textarea')
    : c.querySelector('textarea');
  var answer = r ? r.value : '';
  var memo = t ? (t.value || '').trim() : '';
  if (c.dataset.kind === 'decision' && !answer && !memo) { say(c, '고르거나 메모를 적어 주세요'); return; }
  // ⛔An empty memo on a working card is not a tick — there is nothing here to
  // tick. Only a check's own box carries that meaning.
  if (c.dataset.kind === 'item' && !memo) { say(c, '적을 내용이 있어야 제출됩니다'); return; }
  post('/submit', {id: id, kind: c.dataset.kind, answer: answer || 'ok', memo: memo}, c)
    .then(function(){ if (t) t.value = ''; return afterWrite(c.id); })
    .catch(function(e){ say(c, '실패: ' + e.message); });
}
// One hands-on check, ticked on its own. The card leaves only when the last
// of them is cleared — see `placeByStory`.
function tick(ev, id, ref){
  ev.stopPropagation();
  var c = document.getElementById('c-' + id);
  // The box beside THIS button, not the card's shared one — a card can hold
  // several checks and each carries its own words.
  var box = ev.target.closest('.tick');
  var t = box ? box.querySelector('textarea') : null;
  var note = t ? (t.value || '').trim() : '';
  post('/tick', {id: id, ref: ref, note: note}, box || c)
    .then(function(){ if (t) t.value = ''; return afterWrite(c.id); })
    .catch(function(e){ say(box || c, '실패: ' + e.message); });
}
function save(id){
  var c = document.getElementById('c-' + id);
  var t = c.querySelector('.body > textarea');
  var text = t ? (t.value || '').trim() : '';
  // The box starts empty, so an empty press is a press with nothing to say —
  // and sending it would blank the card's own words and title.
  if (!text) { say(c, '적을 내용이 있어야 추가됩니다'); return; }
  post('/edit', {id: id, text: text}, c)
    .then(function(){ t.value = ''; return afterWrite(c.id); })
    .catch(function(e){ say(c, '실패: ' + e.message); });
}
function purge(id){
  var c = document.getElementById('c-' + id);
  if (!confirm(id + ' 을(를) 완전히 지웁니다. 번호도 다시 쓰입니다.')) return;
  post('/purge', {id: id}, c)
    .then(function(){ closeCard(); return afterWrite(); })
    .catch(function(e){ say(c, '실패: ' + e.message); });
}
function move(id, word, el){
  var c = document.getElementById('c-' + id);
  post('/move', {id: id, to: word}, c)
    .then(function(){ return afterWrite(); })
    .catch(function(e){ say(c, '실패: ' + e.message); });
}
function setPrio(id, p, el){
  var c = document.getElementById('c-' + id);
  post('/priority', {id: id, priority: p}, c)
    .then(function(){ return afterWrite(); })
    .catch(function(e){ say(c, '실패: ' + e.message); });
}
function markBuild(ev){
  var head = ev.target.closest('.vhead');
  post('/build', {}, head)
    .then(function(r){ say(head, (r.commit || '') + ' 빌드로 적었습니다'); return afterWrite(); })
    .catch(function(e){ say(head, '실패: ' + e.message); });
}
function refreshPrs(ev){
  var head = ev.target.closest('.vhead');
  say(head, '읽는 중…');
  post('/refresh', {}, null)
    .then(function(){ return afterWrite(); })
    .catch(function(e){ say(head, '실패: ' + e.message); });
}
// Every check a picked row's card still waits on is ticked — a card holding
// three gets all three (유저 2026-10-02: 「카드에 여러 실기확인있으면 여러
// 실기확인에도 확인 찍히도록」); the lines are `confirmRecords`'.
function confirmGroup(btn){
  var g = document.getElementById('list')._groups[Number(btn.dataset.confirm)];
  var ids = g.rows.filter(function(c){ return S.picked.has(c.id); })
    .map(function(c){ return c.id; });
  if (!ids.length) return;
  var box = btn.closest('.picks');
  post('/dismiss', {ids: ids}, box)
    .then(function(){ ids.forEach(function(id){ S.picked.delete(id); }); return afterWrite(); })
    .catch(function(e){ say(box, '실패: ' + e.message); });
}
function findOld(){
  fetch('/api/find?q=' + encodeURIComponent(S.q), {cache: 'no-store'})
    .then(function(r){ return r.json(); })
    .then(function(rows){ S.old = rows; renderList(); });
}

// ---- the composer

// Two buttons rather than a type dropdown, because the choice is the whole
// classification a person can make while still mid-thought: this is broken
// (feedback) or this would be good (idea). Everything else — number, title,
// which area it belongs to — is sorted out later, on the board.
function compose(){
  closeCard();
  S.sel = 'intake';
  document.body.classList.add('reading');
  document.getElementById('detail').innerHTML =
    '<article class="p det" id="c-intake"><header class="dh"><div class="dtop"><span class="did">새로 적기</span>' +
    '<span class="state"></span></div></header><div class="body">' +
    '<textarea id="intake-text" rows="6" placeholder="떠오른 대로 적으세요. 번호와 제목은 제가 붙입니다.&#10;스크린샷은 Ctrl+V 로 그대로 붙여넣기."></textarea>' +
    '<div id="intake-shots" class="shots"></div>' +
    '<input type="text" id="intake-tag" placeholder="분야 (비워도 됩니다 — 제가 정리합니다)">' +
    '<div class="foot"><button onclick="file(\'feedback\')">피드백 — 지금 이게 잘못됐다</button>' +
    '<button class="alt" onclick="file(\'idea\')">아이디어 — 이런 게 있으면 좋겠다</button>' +
    '<button class="ghost" onclick="file(\'draft\')">임시저장 — 아직 정리 전</button></div></div>' +
    '<button class="close ghost sm" onclick="closeCard()">닫기</button></article>';
  document.getElementById('intake-text').focus();
}
function file(kind){
  var c = document.getElementById('c-intake');
  var text = (document.getElementById('intake-text').value || '').trim();
  if (!text && queued.length === 0) { say(c, '내용을 적거나 스크린샷을 붙여넣어 주세요'); return; }
  post('/intake', {kind: kind, text: text,
                   tag: (document.getElementById('intake-tag').value || '').trim()}, c)
    .then(async function(res){
      for (var i = 0; i < queued.length; i++) {
        await fetch('/shot', {method: 'POST', body: JSON.stringify({id: res.id, data: queued[i]})});
      }
      queued = [];
      return loadBoard().then(function(){ renderAll(); return openCard(res.id); });
    })
    .catch(function(e){ say(c, '실패: ' + e.message); });
}

// Paste-to-attach is wired at the document, not per textarea, so every memo
// box on the page gets it — including ones added later. A screenshot is the
// cheapest thing a person can give and the most expensive thing to describe
// in words, so it should never be the box that does not take one.
document.addEventListener('paste', function(e){
  var ta = e.target;
  if (!ta || ta.tagName !== 'TEXTAREA') return;
  var items = (e.clipboardData && e.clipboardData.items) || [];
  for (var i = 0; i < items.length; i++) {
    var it = items[i];
    if (it.type.indexOf('image/') !== 0) continue;
    e.preventDefault();
    var reader = new FileReader();
    reader.onload = function(){
      // 🚨THE CARD, not the entry. Entries are `<details class="lg">` with
      // NO id, so once a textarea lived inside one (#1427) a loose walk found
      // the entry and posted an empty id — a screenshot pasted into a
      // per-check memo box went nowhere and said nothing. Cards are the ones
      // named `c-<id>`, including the composer (`c-intake`).
      var card = ta.closest('[id^="c-"]');
      if (!card) return;
      var id = card.id.replace(/^c-/, '');
      if (id === 'intake') {
        queued.push(reader.result);
        var img = document.createElement('img');
        img.src = reader.result;
        document.getElementById('intake-shots').appendChild(img);
        say(card, '스크린샷 ' + queued.length + '장 — 제출하면 같이 올라갑니다');
      } else {
        say(card, '스크린샷 올리는 중…');
        fetch('/shot', {method: 'POST', body: JSON.stringify({id: id, data: reader.result})})
          .then(function(){ return afterWrite(); })
          .catch(function(err){ say(card, '실패: ' + err.message); });
      }
    };
    reader.readAsDataURL(it.getAsFile());
  }
});

// ---- input

document.addEventListener('click', function(e){
  var v = e.target.closest('[data-view]');
  if (v) { S.view = v.dataset.view; S.q = ''; S.old = null; document.getElementById('q').value = '';
    remember('view', S.view); renderAll(); return; }
  var o = e.target.closest('[data-owner]');
  if (o) { S.owner = S.owner === o.dataset.owner ? null : o.dataset.owner; renderAll(); return; }
  var a = e.target.closest('[data-area]');
  if (a) { S.area = S.area === a.dataset.area ? null : a.dataset.area; renderAll(); return; }
  var m = e.target.closest('[data-more]');
  if (m) { var k = m.dataset.more; S.more[k] = (S.more[k] || 0) + PAGE; renderList(); return; }
  var all = e.target.closest('[data-pickall]');
  if (all) {
    var g = document.getElementById('list')._groups[Number(all.dataset.pickall)];
    var on = g.rows.some(function(c){ return !S.picked.has(c.id); });
    g.rows.forEach(function(c){ if (on) S.picked.add(c.id); else S.picked.delete(c.id); });
    renderList(); return;
  }
  var ok = e.target.closest('[data-confirm]');
  if (ok) { confirmGroup(ok); return; }
  var pk = e.target.closest('[data-pick]');
  if (pk) { if (pk.checked) S.picked.add(pk.dataset.pick); else S.picked.delete(pk.dataset.pick);
    renderList(); return; }
  var r = e.target.closest('.row[data-id]');
  if (r) openCard(r.dataset.id);
});
document.getElementById('q').addEventListener('input', function(e){
  S.q = e.target.value.trim(); S.old = null; renderAll();
});
document.addEventListener('keydown', function(e){
  var el = document.activeElement;
  var typing = el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT');
  if (e.key === '/' && !typing) { e.preventDefault(); document.getElementById('q').focus(); return; }
  if (e.key === 'Escape') { if (typing) el.blur(); else closeCard(); return; }
  if (typing || e.ctrlKey || e.metaKey || e.altKey) return;
  if (e.key === 'j' || e.key === 'k') {
    var rows = Array.from(document.querySelectorAll('#list .row[data-id]'));
    if (!rows.length) return;
    var i = rows.findIndex(function(x){ return x.dataset.id === S.sel; });
    i = e.key === 'j' ? Math.min(rows.length - 1, i + 1) : Math.max(0, i - 1);
    rows[i].scrollIntoView({block: 'nearest'});
    openCard(rows[i].dataset.id);
    e.preventDefault();
    return;
  }
  if (e.key === 'n') { e.preventDefault(); compose(); return; }
  if ((e.key === 'Enter' || e.key === ' ') && el && el.classList && el.classList.contains('row')) {
    e.preventDefault(); openCard(el.dataset.id);
  }
});

renderAll();
''';

/// The page's styles: the live board's palette, carried over, on an app shell
/// — a rail of views, one list, one open card.
String _css() => '''
:root{--ink:#16181d;--ink2:#3d434f;--ink3:#6b7280;--bg:#f7f6f3;--card:#fff;
--sunk:#efede8;--line:#e2e0da;--line2:#cfccc4;--ok:#0f6f5c;--okbg:#eaf5f2;
--run:#8a5a10;--runbg:#f6edd9;--bad:#9a3412;--badbg:#fdeee7;--live:#1d4ed8;
--livebg:#e8eefc;
--mono:ui-monospace,"Cascadia Mono",Menlo,monospace;
--sans:"Segoe UI",-apple-system,"Noto Sans KR",system-ui,sans-serif}
@media(prefers-color-scheme:dark){:root{
--ink:#eceef2;--ink2:#b9bfcb;--ink3:#838b99;--bg:#14161a;--card:#1c1f25;
--sunk:#181a1f;--line:#2b2f37;--line2:#3a3f49;--ok:#5fc9ae;--okbg:#142824;
--run:#e0b25e;--runbg:#332912;--bad:#e08a63;--badbg:#2c1a12;--live:#86aaf5;
--livebg:#1a2337;color-scheme:dark}}
*{box-sizing:border-box}
html,body{height:100%}
body{margin:0;background:var(--bg);color:var(--ink);font-family:var(--sans);
font-size:14px;line-height:1.55;word-break:keep-all;display:flex;flex-direction:column}
button,input,select,textarea{font:inherit;color:inherit}
:focus-visible{outline:2px solid var(--live);outline-offset:2px}
.mono{font-family:var(--mono);font-size:12px;word-break:break-all}
.top{flex:none;display:flex;align-items:center;gap:14px;flex-wrap:wrap;
padding:10px 16px;border-bottom:1px solid var(--line)}
.top h1{margin:0;font-size:16px;letter-spacing:-.01em}
#q{flex:1;min-width:200px;max-width:460px;border:1px solid var(--line2);
background:var(--card);border-radius:6px;padding:6px 10px}
.stamp{font-size:12px;color:var(--ink3)}
.warn{color:var(--bad)}
.app{flex:1;min-height:0;display:grid;
grid-template-columns:210px minmax(0,1fr) minmax(0,520px)}
.rail{border-right:1px solid var(--line);padding:12px 10px;overflow:auto;
display:flex;flex-direction:column;gap:16px;min-width:0}
.views{display:flex;flex-direction:column;gap:2px}
.view{display:flex;align-items:center;gap:8px;border:0;background:none;
border-radius:6px;padding:6px 8px;cursor:pointer;text-align:left;color:var(--ink2);
font-weight:400}
.view:hover{background:var(--sunk);color:var(--ink)}
.view[aria-current="true"]{background:var(--card);color:var(--ink);font-weight:600;
box-shadow:0 0 0 1px var(--line)}
.view .n{margin-left:auto;font-family:var(--mono);font-size:12px;color:var(--ink3);
font-variant-numeric:tabular-nums}
.view.hot .n{color:var(--run);font-weight:700}
.dot{width:8px;height:8px;border-radius:50%;flex:none;background:var(--line2)}
.s-me{background:var(--run)}.s-triage{background:var(--ink3)}
.s-backlog{background:transparent;box-shadow:inset 0 0 0 1.5px var(--ink3)}
.s-todo{background:transparent;box-shadow:inset 0 0 0 1.5px var(--live)}
.s-discussion{background:transparent;box-shadow:inset 0 0 0 1.5px var(--run)}
.s-doing{background:var(--live)}.s-verify{background:var(--run)}
.s-known{background:var(--bad)}.s-done{background:var(--ok)}
.s-canceled{background:var(--line2)}.s-system{background:var(--line2)}
.facet h3{margin:0 0 6px;font-size:11px;letter-spacing:.08em;color:var(--ink3);font-weight:600}
.facet .chips{display:flex;flex-wrap:wrap;gap:4px}
.fchip{border:1px solid var(--line2);background:var(--card);border-radius:999px;
padding:1px 9px;font-size:12px;cursor:pointer;color:var(--ink2);font-weight:400}
.fchip .n{font-family:var(--mono);color:var(--ink3)}
.fchip:hover{background:var(--sunk);color:var(--ink)}
.fchip[aria-pressed="true"]{background:var(--livebg);border-color:var(--live);color:var(--live)}
.list{overflow:auto;min-width:0;padding-bottom:48px}
.vhead{display:flex;align-items:center;gap:10px;flex-wrap:wrap;padding:12px 18px 2px}
.vhead h2{margin:0;font-size:16px}
.grp{margin-top:6px}
.gh{display:flex;align-items:center;gap:8px;padding:9px 18px 6px;
position:sticky;top:0;background:var(--bg);z-index:1}
.gt{font-size:12px;font-weight:700;color:var(--ink2)}
.gn{font-family:var(--mono);font-size:12px;color:var(--ink3)}
.note{font-size:11.5px;color:var(--ink3)}
.gh .picks{margin-left:auto;display:flex;align-items:center;gap:6px}
.none{margin:0;padding:6px 18px 8px;font-size:12.5px;color:var(--ink3)}
.row{display:grid;grid-template-columns:14px 104px minmax(0,1fr) auto;gap:10px;
align-items:center;padding:7px 18px;border-top:1px solid var(--line);cursor:pointer}
.row.static{cursor:default}
.row:hover{background:var(--sunk)}
.row[aria-selected="true"]{background:var(--card);box-shadow:inset 3px 0 0 var(--live)}
.row .pick{margin:0}
.rid{font-family:var(--mono);font-size:12px;color:var(--ink3);overflow:hidden;
text-overflow:ellipsis;white-space:nowrap}
.rt{min-width:0;display:flex;align-items:center;gap:6px}
.tt{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.rm{display:flex;align-items:center;gap:6px;font-size:12px;color:var(--ink3);white-space:nowrap}
.own{max-width:110px;overflow:hidden;text-overflow:ellipsis}
.age{font-family:var(--mono);font-variant-numeric:tabular-nums;min-width:74px;text-align:right}
.age.old{color:var(--bad)}
.pri{flex:none;font-size:11px;font-weight:700;padding:0 6px;border-radius:3px;
background:var(--sunk);color:var(--ink2)}
.pri.p0{background:var(--badbg);color:var(--bad)}.pri.p1{background:var(--runbg);color:var(--run)}
.more{display:block;margin:6px 18px;width:calc(100% - 36px);border:1px dashed var(--line2);
background:none;border-radius:6px;padding:6px;cursor:pointer;color:var(--ink2);font-weight:400}
.more:hover{background:var(--sunk);color:var(--ink)}
.detail{border-left:1px solid var(--line);overflow:auto;background:var(--card);min-width:0;position:relative}
.detail .close{position:absolute;top:12px;right:14px}
.det{border:0;border-radius:0;background:none}
.dh{padding:16px 20px 10px;border-bottom:1px solid var(--line);display:flex;flex-direction:column;gap:8px}
.dtop{display:flex;gap:10px;align-items:baseline;padding-right:60px}
.did{font-family:var(--mono);font-size:12px;color:var(--ink3)}
.dt{margin:0;font-size:16.5px;line-height:1.45;text-wrap:balance}
.fields{display:grid;grid-template-columns:72px minmax(0,1fr);gap:6px 12px;margin:0;font-size:13px}
.fields dt{color:var(--ink3)}
.fields dd{margin:0;display:flex;flex-wrap:wrap;gap:4px;align-items:center;min-width:0}
.fields .none{padding:0}
select.move{border:1px solid var(--line2);border-radius:6px;background:var(--bg);padding:2px 6px}
.seg{display:inline-flex;border:1px solid var(--line2);border-radius:6px;overflow:hidden}
.seg button{border:0;border-radius:0;background:var(--card);padding:1px 9px;font-size:12px;
font-weight:400;color:var(--ink2)}
.seg button+button{border-left:1px solid var(--line2)}
.seg button[aria-pressed="true"]{background:var(--livebg);color:var(--live);font-weight:600}
.seg button:hover{background:var(--sunk);color:var(--ink)}
.det>.body{border-top:0;padding:4px 20px 28px}
.gone{padding:20px}
body.reading .app{grid-template-columns:210px minmax(0,1fr) minmax(0,520px)}
@media(max-width:1100px){
.app{grid-template-columns:180px minmax(0,1fr)}
.detail{display:none}
body.reading .app{grid-template-columns:180px minmax(0,1fr)}
body.reading .detail{display:block;position:fixed;inset:0;z-index:5;border-left:0}
}
@media(max-width:700px){
.app,body.reading .app{grid-template-columns:minmax(0,1fr)}
.rail{border-right:0;border-bottom:1px solid var(--line);max-height:40vh}
.views{flex-direction:row;flex-wrap:wrap}
.row{grid-template-columns:14px minmax(0,1fr) auto}
.rid,.own{display:none}
}
/* ---- a card's body, as the board has always drawn it */
.chip{font-family:var(--mono);font-size:10.5px;padding:2px 7px;border-radius:3px;
white-space:nowrap;border:1px solid var(--line2);color:var(--ink3)}
.chip.ok{background:var(--okbg);color:var(--ok);border-color:transparent}
.chip.run{background:var(--runbg);color:var(--run);border-color:transparent}
.chip.bad{background:var(--badbg);color:var(--bad);border-color:transparent}
.chip.live{background:var(--livebg);color:var(--live);border-color:transparent}
.body{display:flex;flex-direction:column;gap:7px}
.body>*:first-child{margin-top:10px}
.d{font-size:13px;color:var(--ink2);margin:0;white-space:pre-wrap}
.when{font-family:var(--mono);font-size:10.5px;color:var(--ink3);
white-space:nowrap;flex:none;min-width:38px;text-align:right}
/* One entry of a card's story. Indented under a hairline so a long history
   reads as one thing rather than as many panels; the summary carries the
   stage, the date and a preview so the row is findable while folded. */
.lg{border-left:2px solid var(--line2);padding-left:9px;margin:0}
/* 소분류는 자기 대분류 안에 들여쓴다 — 폴더가 눈에 보이게 하는 것이 전부다. */
/* 질문처럼 자기 제목을 가진 항목은 펼쳐도 제목이 남는다. */
.qt{margin-bottom:6px}
.under{margin:4px 0 2px 14px;border-left:2px solid var(--line);padding-left:10px}
.under>.lg{border-left:none;padding-left:0}
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
/* A landing nobody wrote a card for. Loud on purpose: it is a gap in the
   record, not a kind of check. */
.gap{color:var(--bad)}
/* 남은 것 is the last stage and the loud one; 손대기 전에 is the first and the
   quiet one: it has to be READ before the work, not shouted during it. */
.lg.todo{border-left-color:var(--run)}
.lg.todo>summary>.lgk{color:var(--run);font-weight:700}
/* A 남은 것 that has since been superseded: still in the timeline, because
   the list getting shorter is the story, but no longer shouting. */
.lg.done>summary>.lgk{color:var(--ink3);text-decoration:line-through}
.lg.care{border-left-color:var(--line2)}
.lg.care>summary>.lgk{color:var(--ink3)}
/* 「누가 말한거고 어떤 문장인지」 — the user's own stages carry a warmer rail
   and darker text so the eye can drop down an open card and find their words
   without reading the labels. */
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
.tick{display:flex;flex-direction:column;gap:6px;margin:6px 0 4px}
.foot{display:flex;align-items:center;gap:8px;flex-wrap:wrap}
button{font-family:var(--sans);font-size:13px;font-weight:600;padding:6px 14px;
border-radius:4px;border:1px solid var(--ok);background:var(--okbg);
color:var(--ok);cursor:pointer}
button:hover{background:var(--ok);color:var(--card)}
button.alt{border-color:var(--live);background:transparent;color:var(--live)}
button.alt:hover{background:var(--live);color:var(--card)}
button.sm{padding:2px 9px;font-size:11.5px;font-weight:500}
button.ghost{border-color:var(--line2);background:transparent;color:var(--ink3)}
button.ghost:hover{border-color:var(--ink2);color:var(--ink);background:transparent}
button[disabled]{opacity:.4;cursor:default;pointer-events:none}
.state{font-size:12px;color:var(--ink3)}
a{color:var(--live)}
@media(prefers-reduced-motion:reduce){*{scroll-behavior:auto!important}}
''';
