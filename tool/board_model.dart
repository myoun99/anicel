// 🚨★★★THE BOARD'S MODEL, SHARED BY THE SERVER AND THE GATE.
//
// A card is a stream of entries and everything else is folded out of it: its
// title, its section, whether it still owes work. ⛔Nothing here may be
// re-implemented on the other side. The bug this whole redesign removed was
// two readers answering one question — `at` said 순서 대기 while `state` said
// open, and seven live cards lied about where they were. A gate that judged
// the board by its own copy of these rules would be the same bug wearing a
// different hat, and worse: it would be the thing that is supposed to catch it.
//
// 📐**칸 = 이야기의 마지막 대분류.** 소분류(작업 기록 · 코드 확인 · AI 판단 ·
// 구현 · 정정)는 칸을 바꾸지 않는다. See [kSectionState].
import 'dart:convert';
import 'dart:io';

/// Which card a question belongs to, asked at SUBMIT time — before a render
/// has built [_byOrigin].
///
/// The name answers it for anything written since the `T14-Q1` convention;
/// `of` is the override for the questions named before it, so the file is
/// read for those. ⚠️Returns empty for a question that belongs to nothing —
/// an old standalone one — and that answer still lands in 분류 전 as itself,
/// because there is no origin for it to land on.
String originOfId(String id, File records) {
  final m = kQName.firstMatch(id);
  final byName = m?.group(1) ?? '';
  for (final line in records.readAsLinesSync()) {
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
class BoardLog {
  BoardLog(this.ts, this.at, this.text,
      {this.byUser = false, this.pr, this.how = '', this.ask, this.ref = ''});

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
  final BoardCard? ask;
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

  /// 🚨The entry this one ANSWERS, named by its `ts`. Only a 완료 uses it:
  /// it says WHICH 실기 확인 was cleared, so a card holding three of them
  /// leaves only when all three have one — see [placeByStory].
  final String ref;
}

class BoardCard {
  BoardCard(this.id, this.kind);

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
  /// no longer stands as a card of its own — see [foldQuestionsIntoCards].
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
  final List<BoardLog> log = [];

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
List<int> badLines = const [];

List<BoardCard> readBoard(File file, {DateTime? now}) {
  final bad = <int>[];
  final byId = <String, BoardCard>{};
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
      // meta lines are notes to self and carry no id.
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
      return BoardCard(id, kind);
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
      // 🚨★★★AND IT MUST NOT EAT AN ENTRY THAT ANSWERS SOMETHING ELSE.
      // Three hands-on checks ticked in a row all say 「확인 — 문제 없음」,
      // so by TEXT alone the second and third were the first one again — and
      // the card sat there holding two cleared checks it could not see.
      // 🧪Measured: buttons went 3 → 2 → 1 → 1 and the card never left.
      // What makes them different is `ref`: WHICH entry each one answers.
      final ref = '${json['ref'] ?? ''}';
      if (e.log.any((l) => l.text == text && l.ref == ref)) return;
      final label = at.isEmpty ? fallback : at;
      at = '';
      // ⚠️The PR rides the FIRST stage this line opens, not all of them: it
      // shipped once, however many things the line had to say about it.
      e.log.add(BoardLog(ts, label, text,
          byUser: byUser, pr: prLeft, how: prLeft == null ? '' : stageHow,
          ref: ref));
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
        e.log.add(BoardLog(ts, '유저 대답', said, byUser: true));
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
      e.log.add(BoardLog(ts, '구현', 'PR #$prLeft', pr: prLeft, how: stageHow));
    }
    // 🚨★★★A MOVE IS AN ENTRY LIKE ANY OTHER (유저 2026-08-31: 「거기서
    // 대기중 이동 이런 거나 분류 전 이동 이런 그냥 항목 이동? 착수 가능
    // 이동 그냥 이런 항목을 만드는 게 좋을 거 같기도 하고. **그 마지막
    // 항목에 따라 위치가 정해지는?**」).
    //
    // A line can carry a section word and nothing to say — `{"id":…,
    // "at":"대기중"}`. Nothing consumed the word, so without this the story
    // would not show the move and [placeByStory] would have nothing to read.
    // ⛔The old shape wrote it into a `state` field instead, off the timeline,
    // which is the split this round exists to end.
    if (at.isNotEmpty && kSection.containsKey(at)) {
      stage('$at${ro(at)} 옮김', at);
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
  badLines = bad;
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
  // — the section it lands in depends on it. See [foldQuestionsIntoCards].
  // 🚨★★★ON A CARD, `tag` MEANS `tags` (유저 2026-08-31: 「너가 만든 카드는
  // 태그가 없고」).
  //
  // ⛔It silently meant NOTHING. Chips are drawn from `tags`, and the
  // 「손대기 전에」 laws are matched by `e.tags.contains(l.tag)` — so a card
  // written with `tag` got no chip AND no law, and nothing said so. I wrote
  // `"tag":"구조"` on every card I made this session and every one landed
  // bare. Two fields one letter apart, one of which does nothing, is a trap
  // rather than a convention.
  //
  // ⚠️Folded HERE rather than per line, so it cannot be undone by a later
  // line that names `tags`. ⚠️And not on a `law`, where `tag` keeps its own
  // meaning — WHICH tag this law governs. A law is not a card.
  for (final e in byId.values) {
    if (e.kind == 'law' || e.tag.isEmpty || e.tags.contains(e.tag)) continue;
    e.tags = [...e.tags, e.tag];
  }
  foldQuestionsIntoCards(byId, now);
  // 🚨★★★PLACED BEFORE THE CHECKS FOLD, because that fold has to know which
  // hosts are still on the board — see [foldChecksIntoCards]. Then placed
  // again, because the fold adds entries that decide where a card sits.
  for (final e in byId.values) {
    placeByStory(e);
  }
  foldChecksIntoCards(byId, now);
  for (final e in byId.values) {
    placeByStory(e);
  }
  return [for (final id in order) byId[id]!];
}

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
const kSection = <String, String>{
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
  // 🚨실기 확인 is a SECTION now, not a kind of card — see [foldChecksIntoCards].
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
String lastSection(BoardCard e) {
  for (var i = e.log.length - 1; i >= 0; i--) {
    final name = stageName(e, i);
    if (!kSection.containsKey(name)) continue;
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
    if (kSection[name] == 'wip' && wentQuiet(e)) continue;
    return name;
  }
  return '';
}

/// ⏱Whether the card's newest entry is older than a working day's worth of
/// silence. ⚠️Measured from the NEWEST entry of all, not from the claim: a
/// session that is still writing notes is still working, whatever it last
/// called the section.
bool wentQuiet(BoardCard e) {
  if (e.log.isEmpty) return true;
  final last = DateTime.tryParse(e.log.last.ts);
  // No timestamp at all means an old record that predates the field. Those
  // cannot be renewed, so they cannot hold a claim either.
  if (last == null) return true;
  return DateTime.now().difference(last) > kClaimLasts;
}

/// ⏱Long enough to cover a night and a normal interruption, short enough that
/// a dead session does not hold a card past tomorrow.
const Duration kClaimLasts = Duration(hours: 24);

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
void placeByStory(BoardCard e) {
  if (e.state == 'deleted' || e.state == 'archived' || e.state == 'mine') {
    return;
  }
  final section = kSection[lastSection(e)];
  if (section == null) return;
  // 🚨★★★A CARD WITH SEVERAL HANDS-ON CHECKS LEAVES ONLY WHEN THEY ALL PASS
  // (유저 2026-08-31: 「물론 실기 확인은 카드 안에 여러 개 존재하니까 **모든
  // 게 ok일 때만 사라져야 하겠지만**」).
  //
  // ⛔One 완료 used to end the card whatever else it was still holding, so
  // ticking the first of three checks took the other two off the board with
  // it — and nothing would ever bring them back, because nothing shows them.
  //
  // ⚠️A 완료 answers ONE check, named by `ref` — the ts of the entry it
  // clears. A 완료 with no `ref` is the old shape and still ends the whole
  // card; that is what every 완료 written before this meant.
  if (section == 'archived' && _checksLeft(e)) {
    e.state = 'hands';
    return;
  }
  e.state = section;
}

/// Whether any 실기 확인 entry on this card is still waiting for its own 완료.
bool _checksLeft(BoardCard e) {
  final checks = <String>{};
  final cleared = <String>{};
  for (var i = 0; i < e.log.length; i++) {
    final name = stageName(e, i);
    if (name == '실기 확인') checks.add(e.log[i].ts);
    if (name != '완료') continue;
    final ref = e.log[i].ref;
    // ⚠️No `ref` means 「this card is done」, full stop. Every 완료 written
    // before per-check ticks existed means exactly that.
    if (ref.isEmpty) return false;
    cleared.add(ref);
  }
  return !checks.every(cleared.contains);
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
void foldQuestionsIntoCards(Map<String, BoardCard> byId, [DateTime? now]) {
  for (final q in byId.values.toList()) {
    if (q.kind != 'decision') continue;
    final (of, _) = asksOf(q);
    final origin = of.isEmpty ? null : byId[of];
    // A question whose origin is not in the file IS the card. Nothing folds,
    // but its own answer still has to place it — ⚠️relabelled `유저`, the
    // 대분류, so 분류 전 comes out of its story like every other card's
    // instead of being written into a `state` by the submit handler.
    if (origin == null) {
      for (var i = q.log.length - 1; i >= 0; i--) {
        if (!q.log[i].byUser) continue;
        final was = q.log[i];
        q.log[i] = BoardLog(was.ts, '유저', was.text, byUser: true);
        break;
      }
      continue;
    }
    q.foldedInto = origin.id;
    final raised = q.created.isNotEmpty ? q.created : q.updated;
    origin.log.add(BoardLog(raised, '질문', q.title, ask: q));
    if (q.answer == null) continue;
    // The answer already exists as an entry on the question, written when it
    // was submitted. Its TIME is the thing worth keeping — that is the whole
    // point of putting it in the stream.
    final said = q.log.where((l) => l.byUser).toList();
    final at = said.isEmpty ? q.updated : said.last.ts;
    final text = said.isEmpty ? q.answer! : said.last.text;
    origin.log.add(BoardLog(at, '유저', text, byUser: true));
  }
  for (final e in byId.values) {
    sortByTime(e.log, now);
  }
}

/// ⚠️STABLE, and unparseable timestamps keep the position they were read in.
/// Older lines predate the `ts` field entirely, and a made-up time would
/// scatter them; leaving them where the file put them is the honest answer.
/// ⚠️[now] is an ARGUMENT so a test can pin it. Taking the wall clock here
/// made every fixture stamped 「later today」 read as the future, which the
/// clamp below then flattened into file order — a suite that passed or failed
/// by what time of day it ran.
void sortByTime(List<BoardLog> log, [DateTime? now]) {
  // 🚨★★★A TIME THAT HAS NOT HAPPENED CANNOT ORDER ANYTHING.
  //
  // ⛔I stamped 39 records on 2026-08-31 with clock times of 02·03·04·06·09·
  // 11·12·14시 while the actual clock read 01:36 — plausible-looking numbers
  // I made up instead of reading. The cost landed on 유저 mid-test: they
  // ticked `C-t11` 완료 at 01:34 and the card did not leave, because my
  // 실기 확인 stamped 14:10 sorted AFTER their tick and stayed the last
  // 대분류. They saw both halves of it: 「제출 버튼 눌러도 바로 삭제
  // 안 되네?」 and 「완료 항목은 실기 확인 다음 아닌가? 타임라인적으로?」.
  //
  // A future stamp is treated as NO stamp: it inherits the entry before it,
  // which puts it in file order — and file order is the true order, because
  // the file is append-only. ⚠️This does not hide the mistake; the gate names
  // it (see board_check). It stops the mistake from reordering the story.
  final clock = now ?? DateTime.now();
  final keyed = <(DateTime?, int, BoardLog)>[];
  for (var i = 0; i < log.length; i++) {
    final t = DateTime.tryParse(log[i].ts);
    keyed.add((t != null && t.isAfter(clock) ? null : t, i, log[i]));
  }
  // A row with no time inherits the one before it, so it cannot jump.
  DateTime? carry;
  final settled = <(DateTime, int, BoardLog)>[];
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
void foldChecksIntoCards(Map<String, BoardCard> byId, [DateTime? now]) {
  final byPr = <int, BoardCard>{};
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
    // 🚨★★★A CHECK NEVER GOES DOWN WITH ITS HOST.
    //
    // ⛔Folding put the check INSIDE the card that shipped its PR, and if that
    // card had ended the check went with it — still unticked, and now on no
    // list at all, so nothing could ever bring it back. 🧪TEN of them: the
    // 4GB save check rode `stop-gate-was-dead` into the archive, four buffer
    // checks rode `scroll-the-buffer-on-a-pan`, two rode a deleted round.
    // 유저 found the symptom from the other side — 「실기 확인에 등장 안 하는
    // 카드가 있어」 — and it is the same law they had just stated about ticks:
    // **something else finishing is not this check passing.**
    //
    // ⇒ A check whose host has ended stands as its own card. That is what it
    // was before the fold and it is where a person can still act on it.
    final hostGone = host != null &&
        (host.state == 'archived' ||
            host.state == 'deleted' ||
            host.foldedInto != null);
    if (host != null && host.id != c.id && !hostGone) {
      c.foldedInto = host.id;
      host.log.add(BoardLog(at, '실기 확인', text.isEmpty ? c.id : text));
      continue;
    }
    if (lastSection(c) == '실기 확인') continue;
    c.log.add(BoardLog(at, '실기 확인', text.isEmpty ? c.id : text));
  }
  for (final e in byId.values) {
    sortByTime(e.log, now);
  }
}

/// A decision id shaped `<원본>-Q<번호>` — the naming the user asked for
/// (2026-08-26: 「Q-layer-name이 아니라 패널이름-질문넘버. 예를들어 T14-Q1」).
///
/// 🎯Parsing it is what makes the link impossible to forget. A question named
/// `T14-Q1` IS bound to T14; there is no second field to fill in and no way
/// for the name and the binding to disagree. [BoardCard.of] stays as the
/// override for the cards named before this convention existed.
final kQName = RegExp(r'^(.+)-Q(\d+)$');

/// Which card a question belongs to, and where it sits in that card's list.
(String, int) asksOf(BoardCard e) {
  final m = kQName.firstMatch(e.id);
  if (m != null) return (e.of.isEmpty ? m.group(1)! : e.of, int.parse(m.group(2)!));
  return (e.of, 0);
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
bool stillOwed(BoardCard e) => lastSection(e) == '남은 것';

String stageName(BoardCard e, int i) {
  final at = e.log[i].at;
  if (at.isNotEmpty) return at;
  if (i == 0) {
    if (e.tags.contains('피드백')) return '유저 피드백';
    if (e.tags.contains('아이디어')) return '유저 아이디어';
    if (e.tags.contains('임시')) return '임시 메모';
  }
  return '작업 기록';
}


/// 「로」 or 「으로」 for [word] — chosen by its last syllable, the way a
/// person writes it. ⚠️Not decoration: the board writes this particle into
/// entries and buttons, and 「분류 으로 옮김」 / 「실기 확인 로」 read as
/// machine output, which is what makes a reader stop trusting the text
/// around it.
String ro(String word) {
  if (word.isEmpty) return '로';
  final code = word.codeUnitAt(word.length - 1);
  // Outside the Hangul syllable block there is no 받침 to look at.
  if (code < 0xAC00 || code > 0xD7A3) return '로';
  final jong = (code - 0xAC00) % 28;
  // No final consonant, or ㄹ — both take the short form.
  return jong == 0 || jong == 8 ? '로' : '으로';
}
