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
        final origin = kind == 'decision' ? _originOfId(id) : '';
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
            'answer': body['answer'] ?? '',
            'answerNote': memo,
            'ts': _now(),
            'state': 'archived',
          });
          // ⚠️No `state` on the card: the folded `유저` entry already says
          // 분류 전. This line exists only so the head's date moves.
          _append({'kind': 'item', 'id': origin, 'ts': _now()});
        } else if (kind == 'decision') {
          // A question nobody folded — it IS the card, so the answer stays on
          // it and it goes to 분류 전 like any other thing the user said.
          _append({
            'kind': kind,
            'id': id,
            'answer': body['answer'] ?? '',
            'answerNote': memo,
            'ts': _now(),
            'state': 'inbox',
          });
        } else if (ticked) {
          // ⛔NOT `deleted`. That was safe only while a 실기 확인 row WAS a
          // check record with nothing but a title. The section holds real
          // cards with whole stories now, and this is the section the user
          // sweeps many rows at a time — one click would have taken a card
          // and its story with it. 완료 clears the list just the same.
          _append({
            'kind': 'item',
            'id': id,
            'at': '완료',
            'said': '확인 — 문제 없음',
            'ts': _now(),
          });
        } else {
          _append({
            'kind': 'item',
            'id': id,
            'at': '유저',
            'said': memo,
            'ts': _now(),
          });
        }
      case '/dismiss':
        for (final id in (body['ids'] as List?) ?? [body['id']]) {
          _append({
            'kind': 'item',
            'id': id,
            'state': 'archived',
            'ts': _now(),
          });
        }
      // 🚨★★★THE USER ASKS FOR A MOVE; I MAKE IT (유저 2026-08-31: 「대기중/
      // 착수 가능 등에서 내가 아 이건 순서 보류하고 싶다 싶을 때 **가볍게
      // 순서 대기 쪽으로 옮기는 게 힘든데, 그거 하는 기능 있으면 좋을 거
      // 같아**」).
      //
      // ⚠️ONE LINE, and its 대분류 is 분류 전 — not the section they asked
      // for. Everything the user writes comes back to me to act on, which has
      // been the law since 2026-08-26 and is the reason **유저는 분류 체계를
      // 몰라도 된다**: the request is the entry's text, and moving the card is
      // my job. ⛔Writing 「나중에」 straight from the button would make the
      // board move a card nobody had read.
      case '/ask-move':
        _append({
          'kind': 'item',
          'id': body['id'],
          'at': '유저',
          'said': '${body['to'] ?? ''}${_ro('${body['to'] ?? ''}')} 옮겨 주세요',
          'ts': _now(),
        });
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

/// Which card a question belongs to, asked at SUBMIT time — before a render
/// has built [_byOrigin].
///
/// The name answers it for anything written since the `T14-Q1` convention;
/// `of` is the override for the questions named before it, so the file is
/// read for those. ⚠️Returns empty for a question that belongs to nothing —
/// an old standalone one — and that answer still lands in 분류 전 as itself,
/// because there is no origin for it to land on.
String _originOfId(String id) {
  final m = _qName.firstMatch(id);
  final byName = m?.group(1) ?? '';
  for (final line in File(_recordsPath).readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty) continue;
    try {
      final json = jsonDecode(t);
      if (json is! Map || json['id'] != id) continue;
      final of = '${json['of'] ?? ''}'.trim();
      if (of.isNotEmpty) return of;
    } catch (_) {
      continue;
    }
  }
  return byName;
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
  _Log(this.ts, this.at, this.text,
      {this.byUser = false, this.pr, this.how = '', this.ask});

  /// 🚨★★★THE QUESTION THIS ENTRY IS, when it is one (유저 2026-08-31:
  /// 「질문 자체를 대분류로 옮기고, 새로운 카드 만들어서 참조가 아니라,
  /// **해당 원본 카드 내에서** 질문 카드를 만드는? 질문 여러 개일 수 있잖아.
  /// 그래서 카드 내에 질문이 생기는 거지」).
  ///
  /// ⛔A question used to be a CARD of its own — its own id, its own panel in
  /// 답할 것, a link back to the card that raised it, and a second block
  /// rendered under that card's story. So one subject had two rows, and the
  /// answer landed outside the timeline no matter when it arrived.
  ///
  /// ⚠️Held BY REFERENCE, never copied: the entry keeps the question entry
  /// itself, so the options and the answer are read live. Copying them in
  /// would put one fact in two records, which is the failure this whole board
  /// keeps being redesigned around.
  final _Entry? ask;
  final String ts;

  /// 🚨The PR this stage shipped, when it is a 구현 stage (유저 2026-08-26:
  /// 「한 패널이 결국 여러PR을 가질수있게된다고 생각하거든? 그러니 pr태그를
  /// 내용으로 옮기자. 그러고 구현이라는 항목만들고 거기에 태그 넣도록. 그럼
  /// 구현도 결국 공정이니까 깔끔하게 타임라인흐르잖아」).
  ///
  /// 🎯Exactly right, and it dissolves the awkward chip this replaced. A PR is
  /// something that HAPPENED to the card at a moment — which is what every
  /// other entry here already is. As a head badge it could only ever hold one,
  /// so a card that shipped in three passes had to lie about two of them or
  /// be split into three cards (I-1 and I-1-rest are that split, made because
  /// the shape had no room for the truth).
  final int? pr;

  /// The 공정 this entry belongs to — 유저 피드백 · 대기중 · AI 판단 · 실기확인.
  final String at;
  final String text;

  /// Whose words these are. Drives nothing but the tint: the stage name
  /// already says it, and saying it twice is the 「설명 문구」 habit.
  final bool byUser;

  /// 🚨HOW TO CHECK WHAT THIS STAGE SHIPPED (유저 2026-08-27: 「확인을
  /// 어떻게 하는지를 설명하려고한다면 구현항목에 확인방법을 추가하는게
  /// 맞지않을까」).
  ///
  /// 🎯Better than the card-level `how`, and for a reason the card level
  /// cannot express: a card ships several times, and each 구현 put something
  /// DIFFERENT in front of the user. A single 「이렇게 본다」 on the card has
  /// to describe all of them at once, so it ends up describing the newest and
  /// quietly dropping the rest.
  ///
  /// ⚠️Only a line that is a 구현 (names a `pr`, or says so with `at`) takes
  /// its `how` here. Everywhere else `how` is still the card's, which is what
  /// a hand-written 실기 확인 uses.
  final String how;
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

  /// The FIRST ts any record for this card carried — when it was raised.
  /// [updated] is last-wins and cannot answer that, and a question folded into
  /// its card has to land in the story at the moment it was ASKED.
  String created = '';

  /// Set when this record has been folded into another card as an entry, so it
  /// no longer stands as a card of its own — see [_foldQuestionsIntoOrigins].
  String? foldedInto;

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

  /// Every PR this card has ever claimed, in the order it claimed them. [pr]
  /// is just the newest — kept because the 확인할 것 row badges one landing,
  /// but the LIST is what stops an older PR of the same card reappearing as
  /// an orphan placeholder.
  final List<int> prs = [];
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
    if (ts.isNotEmpty && e.created.isEmpty) e.created = ts;
    // ⚠️Recorded BEFORE `note` is merged, so the list keeps what each line
    // said rather than what the card ended up saying. A line that repeats the
    // note verbatim adds nothing and is skipped — amendments that touch only
    // `state` or `pr` often carry the old note along for readability.
    // ⚠️`at` names the FIRST stage this record opens. A record normally
    // carries one of the three; when it carries several they are several
    // stages and the later ones take their own names.
    int? linePr;
    if (json['pr'] != null) {
      linePr = (json['pr'] as num).toInt();
      e.pr = linePr;
      if (!e.prs.contains(linePr)) e.prs.add(linePr);
    }
    var at = '${json['at'] ?? ''}'.trim();
    // A line that names a PR is a 구현 unless it says otherwise — that is what
    // claiming a PR MEANS, and defaulting it here is what makes the stage name
    // something I cannot forget to write.
    if (at.isEmpty && linePr != null) at = '구현';
    var prLeft = linePr;
    // A 구현's own 「이렇게 확인한다」. ⚠️Only a line that IS an implementation
    // takes the card's `how` onto its stage; everywhere else `how` stays the
    // card's, which is what a hand-written 실기 확인 reads.
    final stageHow = (linePr != null || at == '구현')
        ? '${json['how'] ?? ''}'.trim()
        : '';
    void stage(String text, String fallback, {bool byUser = false}) {
      if (text.isEmpty) return;
      // 🚨★★★THE DEDUPE MUST NOT EAT THE SECTION WORD. It used to clear `at`
      // BEFORE this check, so a line whose text repeated an earlier entry
      // added nothing AND consumed its own stage name — the move vanished
      // with no trace anywhere. 🧪H25 lost its 대기중 exactly that way and
      // sat in 바로 가능 with the word written in the file. Now an unadded
      // entry leaves `at` for the next text on the line, and if nothing takes
      // it the caller writes the bare move entry.
      if (e.log.any((l) => l.text == text)) return;
      final label = at.isEmpty ? fallback : at;
      at = '';
      // ⚠️The PR rides the FIRST stage this line opens, not all of them: it
      // shipped once, however many things the line had to say about it.
      e.log.add(_Log(ts, label, text,
          byUser: byUser, pr: prLeft, how: prLeft == null ? '' : stageHow));
      prLeft = null;
    }

    // 🚨★★★AN ANSWER IS NOT PINNED ANYWHERE — it stands where it was said
    // (유저 2026-08-31: 「설마 대답한거는 무조건 아래고정인가? 대답도
    // 타임라인흐름대로 기록해야하지않나? 별개로 두면안되지. **별개로
    // 두는것좀 절대로 없게해. 싹 다 타임라인흐름이야**」).
    //
    // ⛔It USED to be emitted after 작업 기록, 남은 것 and 구현, so a line
    // carrying both an answer and what that answer left over showed my note
    // first and the user's own words underneath it — pinned below, exactly
    // the shape they named. The user's words open the line now, beside
    // `유저 메모`, because the line exists BECAUSE they said something.
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
    stage('${json['said'] ?? ''}'.trim(), '유저 메모', byUser: true);
    stage('${json['note'] ?? ''}'.trim(), '작업 기록');
    stage('${json['think'] ?? ''}'.trim(), 'AI 판단');
    // 🚨★★★남은 것 IS A STAGE, not a banner recomputed from the field (유저
    // 2026-08-26: 「남은것도 하나의 공정흐름중 하나고 그렇단건 기록해야할거란
    // 거야. 그러니 그 다음 공정 들어왔다고 없애지말고 남기는식으로」).
    //
    // The first cut synthesised one row from the last-wins `rest`, so writing
    // a shorter list next week **erased the longer one** — and the shrinking
    // of that list is exactly the thing worth being able to read. Each write
    // now stands where it was written; the field only answers 「is there still
    // something left RIGHT NOW」, which is what decides the section.
    //
    // ⚠️Clearing (`rest: ""`) writes no stage, deliberately: nothing was said,
    // and the correction that goes with it belongs in a note of its own.
    final leftover = '${json['rest'] ?? ''}'.trim();
    // ⚠️Through `stage()` like every other text on the line, so it CONSUMES
    // the line's `at`. It used to append straight to the log, which left `at`
    // unclaimed and made the bare-move fallback fire a second, empty entry
    // beside it —「남은 것」 and「남은 것 으로 옮김」on one line.
    stage(leftover, '남은 것');
    // A bare `{"id":…, "pr":N}` with nothing written still happened, and a 구현
    // with no story is better than a 구현 that vanishes.
    if (prLeft != null) {
      e.log.add(_Log(ts, '구현', 'PR #$prLeft', pr: prLeft, how: stageHow));
    }
    // 🚨★★★A MOVE IS AN ENTRY LIKE ANY OTHER (유저 2026-08-31: 「거기서
    // 대기중 이동 이런 거나 분류 전 이동 이런 그냥 항목 이동? 착수 가능
    // 이동 그냥 이런 항목을 만드는 게 좋을 거 같기도 하고. **그 마지막
    // 항목에 따라 위치가 정해지는?**」).
    //
    // A line can carry a section word and nothing to say — `{"id":…,
    // "at":"대기중"}`. Nothing consumed the word, so without this the story
    // would not show the move and [_placeByStory] would have nothing to read.
    // ⛔The old shape wrote it into a `state` field instead, off the timeline,
    // which is the split this round exists to end.
    if (at.isNotEmpty && _sectionState.containsKey(at)) {
      stage('$at${_ro(at)} 옮김', at);
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
    // 🚨AN EMPTY ANSWER IS NOT AN ANSWER — it is the way back.
    //
    // `answer` is what takes a card OUT of every working list, which is right
    // for a tick. But a card answered with a MEMO comes back to 분류 전 to be
    // triaged, and once I move it onward it is work again. Nothing could say
    // so: `answer` only ever got set, so a triaged card fell out of 확인할 것
    // (answered), out of 분류 전 (state moved) and out of 착수 가능
    // (`answer == null` required) — **present in the file and on no list at
    // all**. C-ipad-crash spent a turn like that (2026-08-27).
    //
    // ⚠️Empty never means 「answered」 anywhere else: a tick writes `ok` and a
    // decision writes its option key, both non-empty.
    if (json['answer'] != null) {
      final answered = '${json['answer']}';
      e.answer = answered.isEmpty ? null : answered;
    }
    if (json['answerNote'] != null) e.answerNote = json['answerNote'] as String;
    if (json['under'] != null) e.under = (json['under'] as num).toInt();
    if (json['of'] != null) e.of = '${json['of']}';
    if (json['rest'] != null) e.rest = '${json['rest']}';
    if (json['tags'] != null) {
      e.tags = (json['tags'] as List).map((t) => '$t').toList();
    }
    if (json['options'] != null) {
      // 🚨★★★EVERY OPTION HAS A KEY, BY CONSTRUCTION.
      //
      // The radio's `value` is `o['key']`, so an option written without one
      // rendered `value="null"` and the user's pick came back as the STRING
      // 「null」 — **the answer was lost and nobody was told.** It happened to
      // I-4-tone on 2026-08-28: the user answered 크림 in the program, the
      // board wrote `answer:"null"`, and only a chat message saved it. Five
      // cards across three sessions had the same defect.
      //
      // ⛔Fixing the cards would be adding one more place that has to be
      // remembered. The key is an INDEX — that is all anyone ever wrote by
      // hand — so it is filled in here and cannot be missing.
      var index = 0;
      e.options = (json['options'] as List).map((o) {
        index++;
        final option = Map<String, dynamic>.from(o as Map);
        option['key'] ??= '$index';
        return option;
      }).toList();
    }
  }
  _badLines = bad;
  // ⚠️Drop the bare 「PR #N」 placeholder once a real 구현 for that same PR has
  // arrived. A line that claims a PR and says nothing still deserves a stage —
  // it happened — but the moment someone writes what it DID, keeping both
  // shows one merge as two, and the empty one is the copy to lose.
  for (final e in byId.values) {
    if (e.log.length < 2) continue;
    final told = {
      for (final l in e.log)
        if (l.pr != null && l.text != 'PR #${l.pr}') l.pr!,
    };
    if (told.isEmpty) continue;
    e.log.removeWhere((l) => l.pr != null && told.contains(l.pr) &&
        l.text == 'PR #${l.pr}');
  }
  // 🚨A question is an entry on its card, folded in before anything is placed
  // — the section it lands in depends on it. See [_foldQuestionsIntoOrigins].
  _foldQuestionsIntoOrigins(byId);
  _foldChecksIntoCards(byId);
  // 🚨★★★AND ONLY NOW IS THE CARD PLACED. Every entry is in, so the walk
  // backwards can see the whole story — see [_placeByStory].
  for (final e in byId.values) {
    _placeByStory(e);
  }
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
    () async {
      try {
        _store(await _fetch());
      } catch (_) {
        // Keep what we had. See the class doc.
      } finally {
        _busy = false;
      }
    }();
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
  } catch (_) {
    return _Gh(const [], ok: false);
  }
  if (result.exitCode != 0) return _Gh(const [], ok: false);

  final List<dynamic> rows;
  try {
    rows = jsonDecode(result.stdout as String) as List;
  } catch (e) {
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
  'wip': '하는 중',
  'ask': '답할 것',
  // 유저 2026-08-25: 「대기중의 지시대기는 사실상 상담대기니까 이름 상담대기로
  // 바꾸자」. 「지시 대기」는 유저가 명령을 안 내려서 멈춰 있다고 읽히는데,
  // 실제로 멈춰 있는 이유는 아직 이야기가 안 끝나서다.
  // 🆕2026-08-31 유저가 다시 이름을 골랐다 — 상담 대기 → 대화 중,
  // 순서 대기 → 나중에. 칸 이름과 배지를 같은 말로 두기 위해서다.
  'gate': '대화 중',
  'queue': '나중에',
  'mine': '내가 정리 중',
  'hands': '실기 확인',
  'inbox': '분류 전',
};

/// Item states that mean "not startable yet". Anything else with no PR is
/// ready to go.
const _waiting = <String>{'ask', 'gate', 'queue', 'mine'};

/// 🚨★★★THE SECTION A STAGE NAME PUTS THE CARD IN — the one place a written
/// word becomes a column.
///
/// 유저 2026-08-31: 「순서 대기인 게 왜 착수 가능에 있냐? … 이거 애초에
/// 보드 구조가 이상해서 니가 이상하게 받아들이는 건가?」 — it was. `at` is
/// the word on the card; `state` is the code the sections were computed from;
/// nothing made them agree. Seven live cards disagreed when this was written.
///
/// ⚠️This is the INVERSE of [_stateLabels] and must stay so: every value here
/// is a key there. A word that is not a section (구현 · AI 판단 · 정정 ·
/// 유저 피드백 …) is deliberately absent — those are stages in the story, not
/// places to put the card.
///
/// ⚠️Spelling variants are listed, not normalised away: the file already has
/// both 「대기중」 and 「대기 중」, both 「답할것」 and 「답할 것」, and a
/// record written last month cannot be asked to respell itself. ⛔Do NOT add a
/// fuzzy match instead — a card silently landing in a section because its
/// label nearly matched is the failure this map exists to end.
const _sectionState = <String, String>{
  '착수 가능': 'open',
  // 🚨남은 것 IS the 바로 가능 column: the entry says WHAT is left, the column
  // says WHERE it waits. Two of these rows differ that way on purpose.
  '남은 것': 'open',
  // 🚨A question I raised puts the card in 답할 것; the user's answer hands it
  // straight back to me. Both are 대분류, so the two sections fall out of the
  // story in time order instead of being maintained beside it.
  // ⚠️`유저` is the NEW name and the only one mapped. The legacy labels
  // (유저 메모 · 유저 피드백 · 유저 대답) stay 소분류 on purpose — mapping
  // them would drag every card that ever heard from the user back to 분류 전.
  '질문': 'ask',
  '유저': 'inbox',
  '착수': 'open',
  '순서 대기': 'queue',
  '상담 대기': 'gate',
  '상담': 'gate',
  '대기중': 'gate',
  '대기 중': 'gate',
  '보류': 'gate',
  '답할 것': 'ask',
  '답할것': 'ask',
  '분류 전': 'inbox',
  '분류': 'inbox',
  '진행 중': 'wip',
  // 🆕2026-08-31 — the words 유저 chose. The older spellings above stay as
  // aliases because the file already holds them and a record written last
  // month cannot be asked to respell itself.
  '하는 중': 'wip',
  '대화 중': 'gate',
  '나중에': 'queue',
  // 🚨실기 확인 is a SECTION now, not a kind of card — see [_foldChecksIntoCards].
  '실기 확인': 'hands',
  '완료': 'archived',
};

/// 🚨★★★THE LAST 대분류 IN THE CARD'S STORY — the one reader for 「이 카드는
/// 어디 있나」 and for 「아직 남은 것이 있나」.
///
/// 유저 2026-08-31: 「마지막에 남은 작업이라는 항목이 있고, 그 밑에 대분류적인
/// 항목이 없다면 [착수 가능]. … **해당 항목 내에서 코드확인기록이나
/// 유저피드백기록 이런 게 쌓여도 대분류적으로 착수 가능이면 착수 가능에
/// 두도록**」.
///
/// ⛔This REPLACES 「the last entry, whatever it is」 (#1395). That rule moved
/// a card out of 바로 가능 the moment anything at all was written after its
/// 남은 것 — including a note recording that I had just checked the code,
/// which is the one thing a card in that column most wants to have.
String _lastSection(_Entry e) {
  for (var i = e.log.length - 1; i >= 0; i--) {
    final name = _stageName(e, i);
    if (!_sectionState.containsKey(name)) continue;
    // ⏱🚨★★★하는 중 IS A CLAIM WITH A SHELF LIFE, and that is the whole
    // reason it can exist at all (유저 2026-08-31: 「해당 카드에 대한 작업을
    // 시작할 때 해당 세션이 작업자로서 자기 이름 기록하는 곳에 기록하고 …
    // **근데 카드 집어서 작업 시작하는 거 낡기 쉬울 거 같으니 낡지 않는
    // 구조로** 하고」).
    //
    // ⛔As a STATE it would go stale the instant a session died: the card
    // would say 하는 중 for ever and only a person noticing could clear it.
    // As a claim that expires, nobody has to clear anything — a session that
    // is really working keeps writing entries, and one that stopped simply
    // stops renewing. The card falls back to whatever section it came from.
    if (_sectionState[name] == 'wip' && _wentQuiet(e)) continue;
    return name;
  }
  return '';
}

/// ⏱Whether the card's newest entry is older than a working day's worth of
/// silence. ⚠️Measured from the NEWEST entry of all, not from the claim: a
/// session that is still writing notes is still working, whatever it last
/// called the section.
bool _wentQuiet(_Entry e) {
  if (e.log.isEmpty) return true;
  final last = DateTime.tryParse(e.log.last.ts);
  // No timestamp at all means an old record that predates the field. Those
  // cannot be renewed, so they cannot hold a claim either.
  if (last == null) return true;
  return DateTime.now().difference(last) > _claimLasts;
}

/// ⏱Long enough to cover a night and a normal interruption, short enough that
/// a dead session does not hold a card past tomorrow.
const Duration _claimLasts = Duration(hours: 24);

/// 🚨★★★AND THE SECTION IS COMPUTED, NEVER STORED.
///
/// ⛔`state` used to be written by hand beside `at`, and nothing made the two
/// agree — 7 live cards disagreed when this was written, `linux-target` among
/// them: `at: 순서 대기` with `state: open`, so it sat in 착수 가능 wearing a
/// 순서 대기 label. 유저 found it: 「순서 대기인 게 왜 착수 가능에 있냐?」.
/// A value nobody recomputes is a value that goes stale; a value folded out of
/// the story cannot.
///
/// ⚠️Three states are endings or hand-markings with no stage word behind them,
/// so a walk backwards would resurrect the card from an older section:
/// `deleted` · `archived` written straight onto the card · `mine`. Reopening
/// is an ENTRY (`at: 남은 것`, `at: 하는 중`), and that entry writes `open`
/// first, so the guard never blocks a real reopen.
void _placeByStory(_Entry e) {
  if (e.state == 'deleted' || e.state == 'archived' || e.state == 'mine') {
    return;
  }
  final section = _sectionState[_lastSection(e)];
  if (section != null) e.state = section;
}

/// 🚨★★★A QUESTION IS AN ENTRY ON THE CARD THAT RAISED IT — not a card of its
/// own (유저 2026-08-31: 「질문이 생기면 참조카드 + 원본카드 여러 개 생기는
/// 게 아니라 **원본 카드 안에 질문 UI 같은 거 만들어서** 답할 것 대분류로
/// 옮기는 거지」).
///
/// ⛔The old shape put ONE SUBJECT IN TWO ROWS: a `X-Q1` card in 답할 것, the
/// origin card in 대기, a link each way, and a third rendering of the same
/// question in a block under the origin's story. The answer then sat below the
/// whole story no matter when it was given, which is what 유저 found:
/// 「대답한 거는 무조건 아래 고정인가? … 별개로 두는 것 좀 절대로 없게 해.」
///
/// ⚠️NO MIGRATION. The old records stay exactly as they are and are folded on
/// the way to the screen — the file is the record, and rewriting history to
/// suit a renderer is how a board starts lying about what happened.
///
/// ⚠️The answer is folded as `유저`, which IS a 대분류 (→ 분류 전): an answer
/// hands the card back to me to act on, and that has been the law since
/// 2026-08-26. The question folds as `질문` (→ 답할 것). So a card sits in
/// 답할 것 while its newest word is a question and moves to 분류 전 the moment
/// one is answered — the sections fall out of the story instead of being
/// maintained beside it, and `_asking` stopped being needed at all.
void _foldQuestionsIntoOrigins(Map<String, _Entry> byId) {
  for (final q in byId.values.toList()) {
    if (q.kind != 'decision') continue;
    final (of, _) = _asks(q);
    final origin = of.isEmpty ? null : byId[of];
    // A question whose origin is not in the file IS the card. Nothing to fold.
    if (origin == null) continue;
    q.foldedInto = origin.id;
    final raised = q.created.isNotEmpty ? q.created : q.updated;
    origin.log.add(_Log(raised, '질문', q.title, ask: q));
    if (q.answer == null) continue;
    // The answer already exists as an entry on the question, written when it
    // was submitted. Its TIME is the thing worth keeping — that is the whole
    // point of putting it in the stream.
    final said = q.log.where((l) => l.byUser).toList();
    final at = said.isEmpty ? q.updated : said.last.ts;
    final text = said.isEmpty ? q.answer! : said.last.text;
    origin.log.add(_Log(at, '유저', text, byUser: true));
  }
  for (final e in byId.values) {
    _sortByTime(e.log);
  }
}

/// ⚠️STABLE, and unparseable timestamps keep the position they were read in.
/// Older lines predate the `ts` field entirely, and a made-up time would
/// scatter them; leaving them where the file put them is the honest answer.
void _sortByTime(List<_Log> log) {
  final keyed = <(DateTime?, int, _Log)>[];
  for (var i = 0; i < log.length; i++) {
    keyed.add((DateTime.tryParse(log[i].ts), i, log[i]));
  }
  // A row with no time inherits the one before it, so it cannot jump.
  DateTime? carry;
  final settled = <(DateTime, int, _Log)>[];
  for (final (t, i, l) in keyed) {
    carry = t ?? carry;
    settled.add((carry ?? DateTime(1970), i, l));
  }
  settled.sort((a, b) {
    final c = a.$1.compareTo(b.$1);
    return c != 0 ? c : a.$2.compareTo(b.$2);
  });
  log
    ..clear()
    ..addAll(settled.map((e) => e.$3));
}

/// 🚨★★★A HANDS-ON CHECK IS AN ENTRY TOO, and 실기 확인 is a SECTION rather
/// than a kind of card (유저 2026-08-31: 「나중에 실기 확인도 여러 개일
/// 가능성 있는데 그것도 통일해서 깔끔하게 구현되잖아」).
///
/// ⛔`kind: "check"` was a parallel card system: its own records, its own row
/// shape, its own nesting under a landing. A card that shipped and then needed
/// three things tried on a tablet became FOUR rows.
///
/// ⚠️A check that names the card it belongs to (`under`) folds into it. One
/// that names nothing IS its own card, and gets the 실기 확인 entry written
/// onto itself so the section falls out of its story like every other card's.
void _foldChecksIntoCards(Map<String, _Entry> byId) {
  final byPr = <int, _Entry>{};
  for (final e in byId.values) {
    for (final n in e.prs) {
      byPr[n] = e;
    }
  }
  for (final c in byId.values.toList()) {
    if (c.kind != 'check') continue;
    final at = c.created.isNotEmpty ? c.created : c.updated;
    final text = c.how.isNotEmpty ? c.how : c.title;
    // `under` is a PR NUMBER, and the card that shipped it is the one this
    // check belongs to.
    final host = c.under == null ? null : byPr[c.under];
    if (host != null && host.id != c.id) {
      c.foldedInto = host.id;
      host.log.add(_Log(at, '실기 확인', text.isEmpty ? c.id : text));
      continue;
    }
    if (_lastSection(c) == '실기 확인') continue;
    c.log.add(_Log(at, '실기 확인', text.isEmpty ? c.id : text));
  }
  for (final e in byId.values) {
    _sortByTime(e.log);
  }
}

String _esc(String s) => const HtmlEscape().convert(s);

/// 「로」 or 「으로」 for [word] — chosen by its last syllable, the way a
/// person writes it. ⚠️Not decoration: the board writes this particle into
/// entries and buttons, and 「분류 으로 옮김」 / 「실기 확인 로」 read as
/// machine output, which is what makes a reader stop trusting the text
/// around it.
String _ro(String word) {
  if (word.isEmpty) return '로';
  final code = word.codeUnitAt(word.length - 1);
  // Outside the Hangul syllable block there is no 받침 to look at.
  if (code < 0xAC00 || code > 0xD7A3) return '로';
  final jong = (code - 0xAC00) % 28;
  // No final consonant, or ㄹ — both take the short form.
  return jong == 0 || jong == 8 ? '로' : '으로';
}

String _render(List<_Entry> entries, _Gh gh, List<_Checkout> gits,
    {int landedPage = 1}) {
  // `deleted` joins `archived` as a state that stops a card being drawn. Two
  // words for two different endings, kept apart on purpose: 「archived」 is I
  // put this away, 「deleted」 is the user ticked it and it is finished. The
  // file keeps both lines either way.
  // ⚠️And a record folded into another card is not a card here either — see
  // [_foldQuestionsIntoOrigins]. It is still reachable through the entry that
  // holds it, which is the only place it should now be seen.
  final alive = entries
      .where((e) =>
          e.state != 'archived' && e.state != 'deleted' && e.foldedInto == null)
      .toList();
  // Laws are not work: they never appear as a card of their own, they attach
  // to the cards whose tag they name. Set before anything renders.
  _laws = alive.where((e) => e.kind == 'law').toList();
  _records = alive.where((e) => e.kind == 'record').toList();
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
  final inbox = alive.where((e) => e.state == 'inbox').toList();
  // 🚨★★★답할 것 LISTS CARDS, NOT QUESTIONS (유저 2026-08-31: 「질문이
  // 생기면 참조카드 + 원본카드 여러 개 생기는 게 아니라 원본 카드 안에
  // 질문 UI 같은 거 만들어서 답할 것 대분류로 옮기는 거지」).
  //
  // The card is here because its newest 대분류 is a 질문 — see
  // [_foldQuestionsIntoOrigins]. ⛔No second reader: this does NOT ask 「does
  // it have an unanswered question」 anywhere. The story already answered.
  //
  // ⚠️A question whose origin is not in the file was never folded, so it still
  // stands as a card of its own — that is what `foldedInto == null` keeps.
  final asks = alive
      .where((e) =>
          e.foldedInto == null &&
          (e.state == 'ask' || (e.kind == 'decision' && e.answer == null)))
      .toList();
  // 🚨★★★실기 확인 = cards whose newest 대분류 says so. Nothing lands here by
  // merging any more (유저 2026-08-31: 「머지는 PR마다 여러 번 되는데 실기
  // 확인은 다르잖아 … 작업 완료되면 실기 확인만 대분류로서 존재하게」).
  // A merge is an event and a section is a place; putting a card here because
  // a PR landed made the two share an axis, and they always drift apart.
  final checks = alive.where((e) => e.state == 'hands').toList();

  // Every PR a live card ever claimed, not just its newest. An older one left
  // out here comes back as an orphan `pr-N` placeholder beside the card that
  // actually owns it.
  final claimed = <int, _Entry>{
    for (final e in alive)
      for (final n in e.prs) n: e,
  };
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
    buriedPrs.addAll(e.prs);
  }

  // 🚨★★★THE ROWS COME FROM CARDS, NOT FROM `gh pr list`.
  //
  // Building them from the PR list looked natural and was wrong twice over,
  // both found by a card that simply was not on screen:
  //
  //  1. **`--limit 40` is a WINDOW, and a window slides.** Nineteen cards had
  //     already fallen out the bottom — F-2, F-3, F-5, F-6 … — merged, alive,
  //     never checked, and invisible. ⛔A check list whose rows disappear on
  //     their own is worse than no check list, because it looks finished.
  //  2. **One PR can close several cards.** #1214 closed three; one PR, one
  //     row meant two of them were unreachable no matter what the limit was.
  //
  // A card is the SUBJECT of a check; the PR is a detail on it. So the card is
  // the row, and `gh` is consulted for what only it knows — whether a PR is
  // still open, and when it merged.
  final openPrs = {
    for (final pr in gh.prs)
      if (pr.state == 'OPEN') pr.number,
  };
  final byNumber = {for (final pr in gh.prs) pr.number: pr};
  _prState = {for (final pr in gh.prs) pr.number: pr.state};
  // 🚨★★★지금 IS BUILT FROM CARDS TOO (유저 2026-08-27: 「이거 답할것이 원본
  // 카드에서 포인터로서 존재하는거랑 똑같은 규칙이나 로직 적용하면 지금항목에
  // 새 카드가 추가되는게아니라 카드에 공정으로서 포인터로 기록하면
  // 확실할거같은데 어때. 규칙 통일화되는거지」).
  //
  // Right, and it is the same disease one storey up. A question does not
  // become a card of its own — it is a pointer on the card that raised it.
  // A PR should not either: it is something that HAPPENED to a card, which
  // is what a 구현 stage already says. Building 지금 by walking `gh.prs` gave
  // every open PR a row with an English commit title and no story, exactly
  // the rows 확인할 것 stopped drawing one round ago.
  //
  // ⚠️An open PR NOBODY claimed still gets a stand-in — see `_isGap`. That is
  // not a row pretending to be a card; it is the board saying a merge is
  // coming with nothing written about it.
  final nowCards = <_Entry>[];
  for (final e in alive) {
    if (e.answer != null) continue;
    if (!e.prs.any(openPrs.contains)) continue;
    nowCards.add(e);
  }
  for (final pr in gh.prs) {
    if (pr.state != 'OPEN') continue;
    if (claimed.containsKey(pr.number)) continue;
    if (buriedPrs.contains(pr.number)) continue;
    if (buriedIds.contains('pr-${pr.number}')) continue;
    nowCards.add(_prEntry(pr)..prs.add(pr.number));
  }
  final now = [for (final e in nowCards) _itemPanel(e)];

  // What a card is waiting to be looked at with, newest first. A card whose PR
  // gh no longer lists still sorts — by when the card itself last moved.
  DateTime? landedAt(_Entry e) {
    DateTime? best;
    for (final n in e.prs) {
      final at = byNumber[n]?.mergedAt;
      if (at != null && (best == null || at.isAfter(best))) best = at;
    }
    return best ?? DateTime.tryParse(e.updated);
  }

  final fresh = <_Entry>[];
  for (final e in alive) {
    if (e.prs.isEmpty || e.answer != null) continue;
    // 🚨A MERGE IS NOT A FINISH — a card with leftovers stays where the work
    // is, because a tick here deletes it and the leftovers go with it.
    if (_stillOwed(e)) continue;
    // Still building: it belongs in 지금, not in a list of things to look at.
    if (e.prs.any(openPrs.contains)) continue;
    // ⚠️The 최근 착지 mark only applies to PRs gh still knows about. For one
    // outside the window there is no merge time to compare, and dropping it
    // would be the disappearing-row bug wearing a different hat.
    final known = e.prs.map((n) => byNumber[n]).whereType<_Pr>();
    if (known.isNotEmpty && !known.any(_isNews)) continue;
    fresh.add(e);
  }
  // Landings nobody claimed still need a row — that is the whole point of the
  // placeholder — but only while gh can see them.
  for (final pr in gh.prs) {
    if (pr.state != 'MERGED' || !_isNews(pr)) continue;
    if (claimed.containsKey(pr.number)) continue;
    if (buriedPrs.contains(pr.number)) continue;
    if (buriedIds.contains('pr-${pr.number}')) continue;
    fresh.add(_prEntry(pr)..prs.add(pr.number));
  }
  fresh.sort((a, b) {
    final x = landedAt(a), y = landedAt(b);
    if (x == null) return y == null ? 0 : 1;
    if (y == null) return -1;
    return y.compareTo(x);
  });
  // 확인할 것 = every landing, plus the checks that stand on their own.
  //
  // 🚨ONE SUBJECT, ONE ROW, ONE PAGE. Three ways a row could double up, all
  // closed here rather than left to luck:
  //
  //  1. A record that is BOTH a `check` and the claimer of a PR would render
  //     once as a landing and again out of `checks` — `freshIds` stops that.
  //  2. A check written as the hands-on half of a landing would sit BESIDE the
  //     landing it belongs to. That one was real: C-tp1..C-tp6 are the device
  //     checks for the tool-preset round, whose PR was on this very list.
  //     `subs` nests them inside it.
  //  3. 🆕A check whose landing sits on ANOTHER page used to fall through to
  //     standalone and get drawn on EVERY page — the old answer to 「never
  //     hide a check」. 유저 2026-08-28: 「중복된게 두 페이지에 걸쳐있거든?
  //     … 페이지마다 내용 완전히 달라야지」. It is not a scroll.
  //
  //
  // The new answer keeps the promise without the duplication: a check travels
  // WITH its landing, and one that has no landing here goes LAST, which is
  // where it always went.
  //
  // ⛔The order is not the lever. Putting the hand-written checks first would
  // keep them on page 1 — and it pushed every landing onto page 2, which is
  // the wrong half to hide: a landing is a thing merged minutes ago and the
  // reason the section is open. The old note worried a page-2 check waits a
  // month; the answer to that is that turning a page is now free, not that
  // the newest work gets moved out of sight.
  // ⛔`fresh` — the landings — no longer feeds this section. Every unit here
  // is a card that says 실기 확인, and its PRs ride its 구현 entries.
  final orphanIds = {for (final c in checks) c.id};
  final units = <_Entry>[...checks];
  final pages =
      units.isEmpty ? 1 : (units.length + _landedPerPage - 1) ~/ _landedPerPage;
  final page = landedPage.clamp(1, pages);

  // EVERY page is rendered, and the pager only moves a class. Turning a page
  // used to refetch the whole board — measured at 0.5s on a warm cache and
  // 3.7s when the `gh` window had expired, for a change that touches nothing
  // but these rows (유저: 「그냥 누르자마자 전환되게하고싶은데」). Rendering
  // both pages costs less than sending the other 610KB of board twice.
  final toCheck = <String>[];
  for (var p = 1; p <= pages; p++) {
    final onPage = units.skip((p - 1) * _landedPerPage).take(_landedPerPage);
    final here = {
      for (final e in onPage)
        if (!orphanIds.contains(e.id)) ...e.prs,
    };
    final subs = <int, List<_Entry>>{};
    for (final c in checks) {
      final u = c.under;
      if (u != null && here.contains(u)) (subs[u] ??= []).add(c);
    }
    final rows = StringBuffer();
    for (final e in onPage) {
      if (orphanIds.contains(e.id)) {
        rows.write(_checkRow(e));
        continue;
      }
      // The row badges the NEWEST of this card's PRs that gh can still see —
      // the rest are in its story as 구현 stages. A card whose PRs have all
      // aged out of the window gets no badge and loses nothing: the stages
      // carry the numbers and the links.
      _Pr? badge;
      for (final n in e.prs) {
        final pr = byNumber[n];
        if (pr == null) continue;
        if (badge == null || n > badge.number) badge = pr;
      }
      rows.write(_checkRow(e, pr: badge, subs: [
        for (final n in e.prs) ...?subs[n],
      ]));
    }
    toCheck.add('<div class="pg${p == page ? ' on' : ''}" data-pg="$p">'
        '$rows</div>');
  }

  final loose = alive
      .where((e) =>
          e.kind == 'item' &&
          e.state != 'inbox' &&
          // A card whose newest 대분류 is a 질문 is drawn in 답할 것, with the
          // question open inside it. Listing it here too would be one subject
          // in two rows — the shape this round exists to end.
          e.state != 'ask' &&
          // A card waiting to be tried on a device is drawn in 실기 확인.
          e.state != 'hands' &&
          // An answered item has been looked at and reported on; it belongs in
          // its own story now, not back in 착수 가능 claiming to be unstarted.
          e.answer == null &&
          // A claimed PR normally means the card is being CHECKED, not
          // started. Unless it still has leftovers — then this is exactly
          // where it belongs, with the merged part already in its story.
          (e.pr == null || !claimed.containsKey(e.pr) || _stillOwed(e)))
      .toList();
  // Work can be underway before there is a PR to point at -- an investigation,
  // a round mid-flight. Without this those items sat in 착수 가능 claiming to
  // be unstarted, which is the one thing they are not.
  final underway = loose.where((e) => e.state == 'wip').toList();
  final rest = loose.where((e) => e.state != 'wip').toList();
  final ready = rest.where((e) => !_waiting.contains(e.state)).toList();
  // 🚨TWO DIFFERENT WAITS, TWO SECTIONS (유저 2026-08-31: 「대기중엔 상담대기
  // /답대기/순서대기 있는데, **순서대기만 별도 항목 필터로서 만들어서 따로
  // 두고 싶어**」). 나중에 is 「I could start this, I chose not to yet」;
  // 대화 중 is 「I cannot start this until we finish talking」. Lumping them
  // made the second invisible inside the first.
  final later = rest.where((e) => e.state == 'queue').toList();
  final talking =
      rest.where((e) => _waiting.contains(e.state) && e.state != 'queue').toList();
  now.addAll(underway.map(_itemPanel));

  final b = StringBuffer();
  b.writeln('<!doctype html><html><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '<title>Anicel 보드</title><style>${_css()}</style></head><body>');
  b.writeln('<div class="wrap">');
  b.write('<h1>Anicel 보드</h1>');
  b.write('<p class="stamp">분류 전 <b>${inbox.length}</b> · 답할 것 <b>${asks.length}</b>'
      ' · 하는 중 <b>${now.length}</b> · 바로 가능 <b>${ready.length}</b>'
      ' · 대화 중 <b>${talking.length}</b> · 나중에 <b>${later.length}</b>'
      ' · 실기 확인 <b>${checks.length}</b>');
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
  // 🚨★★★THE SEVEN SECTIONS, IN THE ORDER 유저 NAMED THEM (2026-08-31). The
  // names are the words a person would use, and 대기 중 is split because
  // 「나중에」 and 「대화 중」 are two different waits: 「순서 대기만 별도
  // 항목 필터로서 만들어서 따로 두고 싶어」.
  //
  // ⚠️A section name and the 대분류 that puts a card in it are the SAME WORD
  // wherever they can be — see [_sectionState]. Three differ on purpose,
  // because the event and the place have different names: 유저 → 분류 전,
  // 질문 → 답할 것, 남은 것 → 바로 가능.
  b.write(_group('분류 전', inbox.length, '내가 읽고 분류한다', inbox.map(_itemPanel)));
  b.write(_group('답할 것', asks.length, '고르고 제출',
      asks.map((e) => e.kind == 'decision' ? _askPanel(e) : _itemPanel(e))));
  // The refresh lives here because this is the only section it changes, and a
  // control parked away from what it affects is a control you have to remember
  // the meaning of.
  b.write(_group('하는 중', now.length, '', now,
      control: _ctl('<button class="ghost sm" title="PR 상태는 페이지를 열 때만 읽습니다. '
          '지금 다시 읽으려면 누르세요 — 이 칸만 갱신됩니다." '
          'onclick="refresh(event)">↻</button>')));
  b.write(_group('바로 가능', ready.length, '명령만 내리면 착수', ready.map(_itemPanel)));
  b.write(_group('대화 중', talking.length, '이야기가 안 끝났다',
      talking.map(_itemPanel)));
  b.write(_group('나중에', later.length, '순서를 미뤄 둔 것', later.map(_itemPanel)));
  // ONE list (유저 2026-08-26). The count is the whole thing, not the page:
  // this section used to show a number that was really a cap, and that is
  // exactly what made it lie.
  b.write(_group('실기 확인', checks.length,
      '체크 = 문제 없음 · 메모 = 문제', toCheck,
      footer: _pager(units.length, page),
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

/// The pager for 확인할 것.
///
/// It is drawn even when there is only one page: a control that appears only
/// once the list is long enough is a control nobody knows exists.
///
/// 🆕The 「1 / 2」 caption is gone (유저 2026-08-28: 「페이지텍스트 1/2랑 옆에
/// 버튼 1 2 이거 하나로 합칠수있잖아」). It said twice what the buttons say
/// once — the lit button IS the current page, and how many buttons there are
/// IS how many pages there are. The section header already carries the total.
String _pager(int total, int page) {
  final pages = total <= _landedPerPage ? 1 : (total + _landedPerPage - 1) ~/ _landedPerPage;
  final b = StringBuffer('<div class="pager">');
  for (var i = 1; i <= pages; i++) {
    final cls = i == page ? 'pg-btn on' : 'pg-btn';
    // ⛔Not a plain href. A page change is a change to ONE section, and a
    // navigation throws away every panel on the board you had open to read
    // (유저 2026-08-26: 「페이지 바뀔때마다 페이지 바뀌는데 그게아니라 새로고침
    // 안하고 그냥 내부 위젯만 바꾼다거나 가능한가?」). The href stays for
    // middle-click and for a browser with no JS.
    b.write('<a class="$cls" href="?landed=$i" '
        'onclick="return goPage($i)">$i</a>');
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
  '카드 없음': 'bad',
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
String _askBody(_Entry d, {required bool answered}) {
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
/// nothing folded it, so it still needs a panel. ⚠️Every other question is
/// drawn by [_story] as an entry.
String _askPanel(_Entry d) {
  final b = StringBuffer();
  b.writeln('<details class="p ask" id="c-${_esc(d.id)}" data-kind="decision">');
  b.writeln(_head(d.id, d.title, d.tags, '', '', date: d.updated));
  b.writeln('<div class="body">');
  b.writeln(_care(d));
  b.writeln(_recordPanels(d));
  b.writeln(_askBody(d, answered: d.answer != null));
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
  final gap = _isGap(c);
  final tags = [
    if (gap) '카드 없음',
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
  b.writeln(_care(c));
  b.writeln(_recordPanels(c));
  if (gap) {
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
  // Its questions come with it to 확인할 것 — 「무엇을 물었고 무엇으로 정했나」
  // is half of knowing whether the thing in front of you is right.
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
bool _isGap(_Entry e) => e.id.startsWith('pr-');

String _itemPanel(_Entry e) {
  // No badge for a ready item, and none for the inbox either: both are already
  // named by the section they sit in. The tag (피드백 / 아이디어 / 임시) is the
  // part that actually differs between rows.
  final inbox = e.state == 'inbox';
  // 🚨A card that arrived because a question of its was ANSWERED. The inbox
  // editor exists to fix a filing made mid-thought; an origin pushed here by
  // an answer is something to READ, and the editor branch does not draw the
  // questions — so the answer it came to deliver would be the one thing
  // hidden.
  final answeredQuestion =
      (_byOrigin[e.id] ?? const <_Entry>[]).any((q) => q.answer != null);
  // 대기 중 promises that 「배지가 무엇을 기다리는지 말한다」, and the state
  // it names is folded straight out of the story now — an unanswered question
  // makes the card's newest 대분류 a 질문, which IS the 답할 것 section.
  // ⛔`_asking` was a second reader for that and is gone.
  final badge =
      (e.state == 'open' || inbox) ? '' : (_stateLabels[e.state] ?? e.state);
  // 분류 전 now receives three different arrivals, and which one a row is
  // decides what I do with it. The chip says so on the row (유저 2026-08-26:
  // 「분류전으로 옮기고 대답 태그 붙이면」). ⚠️Plain feedback and ideas already
  // carry their own tag from intake, so only the returning kinds need one.
  final arrival = switch (e.kind) {
    'decision' => '대답',
    'check' => '실기 피드백',
    // An item only 「arrives」 if the user wrote on it — a plain working card
    // has nothing new to announce.
    _ => e.answer != null
        ? '유저 피드백'
        : (answeredQuestion && inbox ? '대답' : ''),
  };
  // The user's own writing is not editable once it is an ANSWER — editing it
  // would rewrite what they said, which is the one thing this whole redesign
  // exists to stop.
  // ⚠️`answer == null` too: an item that came BACK carrying feedback is not a
  // half-finished filing to correct, it is something to read. Showing it in an
  // edit box would offer to rewrite what the user just said.
  final editable =
      inbox && e.kind == 'item' && e.answer == null && !answeredQuestion;
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
        // ⚠️Same law in both panels: a stand-in for a PR nobody wrote a card
        // for says so, wherever it is drawn. It reached 지금 unmarked when
        // this lived only in `_checkRow`.
        if (_isGap(e)) '카드 없음',
        if (arrival.isNotEmpty) arrival,
        // ⛔No PR chip here. A card can ship in several passes, and a head
        // badge holds one — so it lives in the story as a 구현 stage, where
        // there is room for all of them and for what each one did.
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
    // 🚨★★★AND ITS STORY, ALWAYS. A card in 분류 전 used to show the edit box
    // and NOTHING ELSE, so a card that arrived here because the user pressed
    // 「나중에 로」 showed no sign of having been asked — the request was in
    // the file and invisible on screen. ⛔That is the same 「별개로 둠」 this
    // round is removing everywhere else (유저: 「싹 다 타임라인흐름이야」).
    b.writeln(_story(e));
  } else {
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
  }
  // 🚨★★★MOVING A CARD SHOULD COST ONE PRESS (유저 2026-08-31: 「가볍게
  // 순서 대기 쪽으로 옮기는 게 힘든데, 그거 하는 기능 있으면 좋겠어」).
  // ⚠️These ASK; they do not move. The press writes one 유저 entry saying
  // where it should go, which lands the card in 분류 전 for me to read — see
  // `/ask-move`. ⛔A button that moved the card itself would move something
  // nobody had read, and the request would leave no trace in the story.
  b.writeln('<div class="foot moves">');
  for (final to in const ['나중에', '대화 중', '바로 가능', '실기 확인']) {
    b.writeln('<button class="ghost sm" '
        'onclick="askMove(event,\'${_esc(e.id)}\',\'$to\')">$to${_ro(to)}</button>');
  }
  b.writeln('<span class="state"></span></div>');
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
List<_Entry> _laws = const [];

/// Area REFERENCE records (`kind: record`) — living tables a card's area
/// keeps current (the first one: which TVPaint versions the .tvpp import
/// is verified against). Same attach-by-tag scheme as laws, same folded
/// styling, different verb: a law says what breaks if you start without
/// knowing; a record says what is currently true.
List<_Entry> _records = const [];

/// The area's records, folded under the card the same way its law is.
String _recordPanels(_Entry e) {
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
/// 🚨★★★**남은 것이 마지막 항목일 때만 아직 남은 것이다.**
///
/// 유저 2026-08-30, 정정: 「기록은 기록이니까 **남은것 그대로 남겨야지 그 다음
/// 구현이 오는거고 맨 마지막에 남은것항목일때만 착수가능이나 대기중에 올리는
/// 거고**」.
///
/// ⛔예전에는 `rest` 필드가 **비어 있지 않기만 하면** 미완으로 쳤다. 그 필드는
/// 한번 쓰면 누가 지워 주기 전까지 남으므로, 그 뒤에 구현이 오고 일이 끝나도
/// 카드가 영영 착수 칸에 앉아 있었다 — I-4 가 그랬고, 유저가 「작업끝난걸로
/// 아는데」라고 물어서 드러났다.
///
/// ⛔그리고 이것을 **그리는 자리를 옮겨서** 풀려고 했던 것도 틀렸다. 기록은
/// 기록이라 쓰인 자리에 그대로 있어야 한다(유저: 「멋대로하지말라고」). 위치가
/// 아니라 **순서**가 답한다.
///
/// ⚠️뒤에 오는 것이 구현이어야 하는 것은 **아니다**(유저 정정: 「반드시 그렇단게
/// 아니라 **내 피드백이던 뭐던 올수있는거고 남은것은 그냥 하나의 기록일뿐**
/// 이라는 의미야」). 남은 것은 특별한 상태가 아니라 **기록 하나**일 뿐이고,
/// 그 뒤에 무엇이든 한 줄이 더 적혔다면 그것은 더 이상 마지막 말이 아니다.
/// 여전히 남은 것이 있다면 **다시 한 줄 적으면 된다.**
///
/// ⚠️그래서 아직 남은 것이 있으면 **`rest` 를 마지막 대분류로** 써야 한다.
/// 한 줄에 `rest` 와 다른 대분류를 같이 쓰면 뒤엣것이 이긴다.
///
/// 🆕2026-08-31: 뒤에 오는 것이 **소분류**(작업 기록·코드 확인·AI 판단·구현)
/// 라면 이제 남은 것 그대로다 — 유저: 「해당 항목 내에서 코드확인기록이나
/// 유저피드백기록 이런 게 쌓여도 대분류적으로 착수 가능이면 착수 가능에」.
/// ⛔#1395 는 「무엇이든 뒤에 오면 끝」이었고, 그건 **코드를 확인했다고 적는
/// 순간 카드가 칸을 떠나게** 만들었다 — 그 칸의 카드가 가장 갖고 싶어 하는
/// 바로 그 기록이다.
bool _stillOwed(_Entry e) => _lastSection(e) == '남은 것';

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

String _story(_Entry e) {
  if (e.log.isEmpty && e.rest.isEmpty) return '<p class="d">메모 없음.</p>';
  final b = StringBuffer();
  for (var i = 0; i < e.log.length; i++) {
    final entry = e.log[i];
    final newest = i == e.log.length - 1;
    final flat = entry.text.replaceAll('\n', ' ');
    final peek = flat.length > 44 ? '${flat.substring(0, 44)}…' : flat;
    final mine = _stageName(e, i);
    // 🚨★★★ONE READER FOR 「아직 남은 것인가」 — [_stillOwed] AND THIS.
    //
    // 유저 2026-08-31: 「**색라벨은 정한 규칙대로 남은것이 마지막에 있어야**
    // 착수가능이도록 하고싶은데, **지금 마지막이 아닌데도 착수가능이거든?**」
    //
    // ⛔#1395 moved the SECTION onto 「마지막 항목이 남은 것인가」 but left the
    // colour asking a different question — 「does this entry match the `rest`
    // field」 — so a 남은 것 with work written after it still wore the loud
    // colour. Two readers, one question, which is the thing that splits.
    // 남은 것 is one record among others: only the LAST word is still owed.
    final leftover = mine == '남은 것';
    final live = leftover && newest;
    // ⚠️`open` is an ATTRIBUTE, not a class. Written inside the class string
    // it renders as `class="lg open"` — valid HTML, silently folded, and 68
    // stages that were meant to stand open did not.
    //
    // ⛔ONLY THE LAST ONE STANDS OPEN (유저 2026-08-31: 「마지막 항목만
    // 펼치기 상태로 두는거고」). It used to add `|| live`, which is now the
    // same condition anyway — kept out so the next reader cannot make them
    // disagree again.
    // 🚨★★★A QUESTION IS AN ENTRY, and it brings its own form with it — the
    // radios, the memo box and the submit all live here now (유저 2026-08-31:
    // 「원본 카드 안에 질문 UI 같은 거 만들어서」). ⛔It used to be a whole
    // second block under the story, so an answer sat below everything no
    // matter when it arrived.
    final ask = entry.ask;
    final answered = ask?.answer != null;
    b.writeln('<details class="lg'
        '${entry.byUser || mine.startsWith('유저') ? ' says' : ''}'
        '${ask != null && !answered ? ' q' : ''}'
        '${live ? ' todo' : ''}${leftover && !live ? ' done' : ''}"'
        '${newest ? ' open' : ''}'
        '${ask == null ? '' : ' id="c-${_esc(ask.id)}" data-kind="decision"'}>');
    b.writeln('<summary><span class="lgk">${_esc(mine)}</span>'
        '<span class="lgp">${_esc(peek)}</span>'
        '${ask == null ? '' : '<span class="chip ${answered ? 'ok' : 'run'}">'
            '${answered ? '답함' : '대기'}</span>'}'
        '${entry.pr == null ? '' : _prChip(entry.pr!)}'
        '<span class="when">${_esc(_day(entry.ts))}</span></summary>');
    if (ask == null) {
      b.writeln('<p class="d">${_esc(entry.text)}</p>');
    } else {
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
// One press = one 유저 entry saying where the card should go. The card lands
// in 분류 전 and I move it -- the button never moves it itself.
function askMove(ev, id, to){
  ev.stopPropagation();
  const c = document.getElementById('c-'+id);
  post('/ask-move', {id:id, to:to}, c)
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
  // ⚠️Re-fetch the page you are ON. Asking for `/` returns page 1, so
  // submitting anything from page 2 used to teleport you back to the top of a
  // list you had scrolled past.
  return fetch('/?landed=' + curPage(), {cache:'no-store'})
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
// Turns a page of 확인할 것 by swapping that one section's DOM.
//
// The rows change; nothing else on the board does. So nothing else should move
// — not the scroll position, not the panels you had open elsewhere, not a memo
// you were halfway through typing. A navigation loses all three.
//
// ⚠️Open state is restored for the panels that survive the swap. A row that
// was on the old page and is not on the new one is simply gone, which is what
// turning a page means.
// Which page of 확인할 것 is on screen — read from the pager the server drew,
// so there is no second copy of this fact to drift.
function curPage(){
  const on = document.querySelector('.pager a.on');
  return on ? (parseInt(on.textContent, 10) || 1) : 1;
}
// Every page is already in the document, so turning one is a class swap.
//
// It used to refetch the whole board — measured at 0.5s warm and 3.7s once the
// `gh` window had expired, to change rows that were already decided when the
// page was drawn (유저 2026-08-28: 「특히 페이지 전환할떄 너무느려. 그냥
// 누르자마자 전환되게하고싶은데」). Nothing needs saving and restoring either:
// open panels and half-typed memos are not touched, because nothing is
// replaced. The scroll does not move for the same reason.
function goPage(n){
  const pgs = document.querySelectorAll('.pg');
  if(!pgs.length) return true;   // nothing to swap: let the link navigate
  pgs.forEach(function(d){
    d.classList.toggle('on', parseInt(d.dataset.pg, 10) === n);
  });
  document.querySelectorAll('.pager a.pg-btn').forEach(function(a){
    a.classList.toggle('on', parseInt(a.textContent, 10) === n);
  });
  return false;
}
// Swaps just the 지금 section rather than reloading: everything else on the
// page is unaffected by a PR lookup, and a full reload throws away every panel
// you had open to read.
function swapSection(id, done){
  return fetch('/?landed=' + curPage(), {cache:'no-store'})
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
/* A page button is a BUTTON: a real box you can aim at, not a bare number.
   The current one is filled rather than outlined -- 유저 2026-08-28: 「1 2
   버튼을 제대로 사각형실루엣같은거 그려서 버튼이게하고 현재 페이지면 강조색
   칠하게」. `--card` for the label so it reads on the accent in both themes;
   white would go grey-on-pale in dark mode, where --live is the light one. */
.pager a.pg-btn{display:inline-flex;align-items:center;justify-content:center;
min-width:30px;height:30px;padding:0 8px;border:1px solid var(--line2);
border-radius:6px;background:var(--card);color:var(--ink2);
font-size:13px;font-variant-numeric:tabular-nums;text-decoration:none;
cursor:pointer;user-select:none}
.pager a.pg-btn:hover{border-color:var(--live);color:var(--live)}
.pager a.pg-btn.on{background:var(--live);border-color:var(--live);
color:var(--card);font-weight:600}
.pager a.pg-btn.on:hover{color:var(--card)}
/* Every page is in the document; the pager lights exactly one. Turning a page
   is a class swap, not a refetch. */
.pg{display:none}
.pg.on{display:block}
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
/* 남은 것 is the last stage and the loud one — it is the reason the card is
   not in 확인할 것. 손대기 전에 is the first and the quiet one: it has to be
   READ before the work, not shouted during it. */
/* A landing nobody wrote a card for. Loud on purpose: it is a gap in the
   record, not a kind of check. */
.gap{color:var(--bad)}
.lg.todo{border-left-color:var(--run)}
.lg.todo>summary>.lgk{color:var(--run);font-weight:700}
/* A 남은 것 that has since been superseded: still in the timeline, because
   the list getting shorter is the story, but no longer shouting. */
.lg.done>summary>.lgk{color:var(--ink3);text-decoration:line-through}
.lg.care{border-left-color:var(--line2)}
.lg.care>summary>.lgk{color:var(--ink3)}
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
.foot.moves{margin-top:6px;border-top:1px solid var(--line);padding-top:8px}
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
