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
/// The submitted [answer] as THE USER'S WORD: an option's key resolved to
/// that option's label, or [answer] unchanged when it names no option.
///
/// 🚨★★★**A RECORD HAS TO SAY WHAT WAS CHOSEN, ON ITS OWN.** The radio's
/// value is `o['key']`, and a key is an INDEX by construction (see where
/// options are parsed) — so an answered question landed in the records file
/// as `{"answer":"2"}`, which means nothing to anyone reading that line later
/// (유저 2026-09-12: 「보드에 2만으로는 알수없잖아」).
///
/// ⚠️The BOARD was never confused: `_askBody` resolves the key back to its
/// label when it draws. That is exactly what made this hard to see — and why
/// it still had to be fixed. 기록이 원본이고 보드는 열 때마다 그려진다, so a
/// line that needs its card beside it to be read is a line that says nothing.
///
/// ⛔NOT a second field. `answer` already means the user's word — board_check
/// leaves it out of the pointer checks for that very reason — and a new key
/// would be one more thing every reader has to learn.
/// ⛔An answer naming no option is returned UNTOUCHED: free text, the panel's
/// `other`, and every answer recorded before this one stay exactly as written.
/// ⚠️It parses the board to ask one question, like [originOfId] beside it. A
/// submit is a human-paced act and the board is parsed to draw it anyway;
/// a second parser written here to save that would be the copy this file
/// exists to avoid.
String answerWordFor(String id, String answer, File records) {
  if (answer.isEmpty) return answer;
  for (final card in readBoard(records)) {
    if (card.id != id) continue;
    for (final option in card.options) {
      if ('${option['key']}' != answer) continue;
      final label = '${option['label'] ?? ''}'.trim();
      return label.isEmpty ? answer : label;
    }
  }
  return answer;
}

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
    } on Object catch (_) {
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
      {this.byUser = false,
      this.pr,
      this.how = '',
      this.ask,
      this.ref = '',
      this.to = '',
      this.from = ''});

  /// 🚨★★★ONE SESSION'S WORD TO ANOTHER IS AN ENTRY ON A CARD — [to] names
  /// the 담당 it is left for ([kEveryone] for all of them), [from] the 담당
  /// who wrote it (유저 2026-10-07,
  /// the-board-is-one-server-for-both-machines-Q2: 「글은 카드의 흐름에 적고,
  /// 「전달」 보기는 그것을 모아 보여 주기만 한다」).
  ///
  /// ⛔Not a list of its own. The first shape proposed kept these in a store
  /// beside the cards, and the law that ended that shape for answers stands
  /// here too: 「별개로 두는것좀 절대로 없게해. 싹 다 타임라인흐름이야」
  /// (유저 2026-08-31). A letter stands in its card's story at the moment it
  /// was written; the 「전달」 view is a reading of these entries and holds
  /// nothing.
  ///
  /// Why it exists at all: two machines run sessions under two accounts, and
  /// a session's own messages do not cross accounts. The board is the one
  /// thing both reach.
  final String to;
  final String from;

  /// Who has read this letter, and when — each 담당 once, by the 읽음 line
  /// that named this entry ([kReadMark]). ⚠️Filled on the letter itself and
  /// not added as an entry: a mark is not a stage of the card, and a story
  /// with a 「읽음」 row under every letter would bury the letters.
  final Map<String, String> readBy = {};

  bool get isLetter => to.isNotEmpty;

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

  /// Whose words these are. On screen it drives nothing but the tint: the
  /// stage name already says it, and saying it twice is the 「설명 문구」
  /// habit.
  /// ↩️It also decides whose move it is now ([userSpokeLast], 2026-10-02), so
  /// a user's line must not lose it — see the bare move in [readBoard].
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
  /// The card's NAME. ⚠️Still a field, and deliberately: a name is not a
  /// stage in a story, and 「the last line that named it」 is what a name IS.
  /// 🧪`note` and `said` were the two that made 「머리에 보이는 문장과 이야기
  /// 의 마지막 문장이 다르다」 possible, and both are gone now — the head
  /// carries a name, the story carries the sentences.
  String title = '';
  List<String> tags = const [];
  String state = 'open';

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

  /// 🆕긴급 · 높음 · 보통 · 낮음, or empty for 미정 — an axis of its own, not
  /// a section (유저 2026-10-02: 「최대한 프로들이랑 똑같으면되」; the board
  /// redesign's 「우선순위는 사용자가 정합니다」). Last-wins, like a name.
  String priority = '';

  /// 🆕Which session holds the card — a field rather than a phrase in a note
  /// (「담당: …」), so a list can group by it. Last-wins; empty clears it.
  String owner = '';
}

/// Folds the append-only log into current state: a later line with the same id
/// overwrites only the fields it names, so "this now has an answer" is one
/// short line rather than a restatement of the whole record.
/// Lines the reader could not use. The board still draws -- thirty items beat
/// none -- but it says so at the top, because an item that silently stops
/// existing is the one failure this format can still have. This replaces a
/// Stop hook that cost 2.4s of every turn to answer the same question.
List<int> badLines = const [];

/// 🚨★★★EVERY KEY ANY READER LOOKS AT. Nothing else in a record is read.
///
/// ⛔This board's whole failure history is one shape: **a word the writer had
/// to remember**, spelled slightly wrong, silently doing nothing. `ask` in
/// place of `options`. A PR in the note body instead of `pr`. `kind` forgotten
/// on a question. Every time, the data was there and no reader looked at it,
/// and nothing anywhere said so.
///
/// ⚠️THIS SET IS NOT MAINTAINED BY HAND — that would be one more word to
/// remember, which is the defect. `a_record_says_nothing_unread_test` reads
/// the `json['…']` sites out of this file and fails if they disagree.
const kReadFields = <String>{
  'answer', 'answerNote', 'at', 'care', 'from', 'how', 'id', 'kind', 'note',
  'of', 'options', 'owner', 'pr', 'priority', 'recommend', 'ref', 'rest',
  'said', 'state', 'tag', 'tags', 'think', 'title', 'to', 'ts', 'under',
  'where', 'why',
};

/// The stage a letter stands under in its card's story when its line names
/// no other — see [BoardLog.to].
const kLetterStage = '전달';

/// The `at` of the line a reader leaves on a letter — see [BoardLog.readBy].
const kReadMark = '읽음';

/// The `to` that means every 담당: a notice, read by each of them once.
const kEveryone = '모두';

/// The ONE card a notice goes on when it is about no card (유저 2026-10-07,
/// the option chosen: 「카드와 무관한 알림은 「세션 알림」 카드 하나에
/// 적는다(담당마다가 아니라 전체에 하나)」). A card like any other — its
/// story is where those notices stand.
const kNoticesCard = 'session-notes';

/// One session's word to another, with the card whose story it stands in.
typedef BoardLetter = ({BoardCard card, BoardLog entry});

/// Every letter on the board, in the order the cards and their stories hold
/// them. ⚠️A READING of the cards, built each time it is asked for: nothing
/// keeps letters apart from the stories they are entries of.
List<BoardLetter> lettersOf(Iterable<BoardCard> cards) => [
      for (final card in cards)
        for (final entry in card.log)
          if (entry.isLetter) (card: card, entry: entry),
    ];

/// Whether [letter] still waits for [reader]: it was left for them or for
/// everyone, somebody else wrote it, and they have not marked it read.
bool letterWaitsFor(BoardLog letter, String reader) =>
    letter.isLetter &&
    reader.isNotEmpty &&
    (letter.to == reader || letter.to == kEveryone) &&
    letter.from != reader &&
    !letter.readBy.containsKey(reader);

/// The `kind` values a reader treats specially. Anything else is a plain card
/// — which is usually a typo, and always silent.
///
/// 🆕`build`: the user pressed 「이 빌드로 시험 중」 — its `title` is the master
/// commit they built, its `ts` when. Not a card: verification groups by it.
const kKinds = <String>{
  'item', 'decision', 'law', 'meta', 'check', 'record', 'build',
};

/// One thing a record said that nobody reads. ⚠️Three fields rather than one
/// formatted string, because the gate has to ANSWER WITH THEM: the id to
/// match an ack, the line to be findable, the field to be fixed.
typedef UnreadField = ({int line, String id, String field});

/// 🚨★★★WHAT A RECORD SAID THAT NOBODY READ.
///
/// Filled by [readBoard] beside [badLines], for the same reason: the screen
/// carries on without it, and the gate is where 「그건 아무도 안 읽습니다」
/// gets said out loud.
List<UnreadField> unreadFields = const [];

List<BoardCard> readBoard(File file, {DateTime? now}) {
  final bad = <int>[];
  final unread = <UnreadField>[];
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
    } on Object catch (_) {
      stderr.writeln('board: line $lineNo is not valid JSON, skipped');
      bad.add(lineNo);
      continue;
    }
    final kind = json['kind'] as String? ?? '';
    // ⛔EXCEPT `meta`, and not as a convenience: a meta line is a note to
    // self that carries whatever that note needs, and **this file is not its
    // only reader**. 🧪Measured: `landedSince` looked dead to every `json['…']`
    // site in tool/, and `board_gate.sh:223` greps it out of the file with
    // `grep -o '"landedSince":"[^"]*"'`. Flagging those two lines would have
    // taught the reader to ignore this check on its first run.
    //
    // ⚠️`law` IS checked — it is a card the board draws, not a note.
    // The id may be missing; the line number is what makes it findable.
    if (kind != 'meta') {
      for (final k in json.keys) {
        if (kReadFields.contains(k)) continue;
        unread.add((line: lineNo, id: '${json['id'] ?? '-'}', field: k));
      }
      if (kind.isNotEmpty && !kKinds.contains(kind)) {
        unread.add(
            (line: lineNo, id: '${json['id'] ?? '-'}', field: 'kind=$kind'));
      }
    }
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
    final ts = '${json['ts'] ?? ''}';
    // 🚨A 읽음 IS A MARK ON THE LETTER IT NAMES, and nothing of the card's:
    // `ref` is that letter's stamp, `from` the 담당 who read it. ⚠️Taken
    // before `updated` on purpose — being read is not the card moving, and a
    // card that jumped to the top of a list each time somebody read a letter
    // on it would be sorted by its readers.
    if ('${json['at'] ?? ''}'.trim() == kReadMark) {
      final reader = '${json['from'] ?? ''}'.trim();
      final named = '${json['ref'] ?? ''}';
      for (final entry in e.log) {
        if (!entry.isLetter || entry.ts != named || reader.isEmpty) continue;
        entry.readBy.putIfAbsent(reader, () => ts);
      }
      continue;
    }
    // Last line wins: the head shows when this card last moved.
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
    // A line that names a 담당 in `to` is that line's note LEFT FOR them —
    // see [BoardLog.to].
    final letterTo = '${json['to'] ?? ''}'.trim();
    final letterFrom = '${json['from'] ?? ''}'.trim();
    void stage(String text, String fallback,
        {bool byUser = false, bool letter = false}) {
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
      // ⚠️A LETTER IS NEVER A REPEAT. The same words left for a second 담당,
      // or left twice, are two tellings — each has its own reader to reach,
      // and the dedupe would have delivered only the first.
      if (!letter && e.log.any((l) => l.text == text && l.ref == ref)) return;
      final label = at.isEmpty ? fallback : at;
      at = '';
      // ⚠️The PR rides the FIRST stage this line opens, not all of them: it
      // shipped once, however many things the line had to say about it.
      e.log.add(BoardLog(ts, label, text,
          byUser: byUser, pr: prLeft, how: prLeft == null ? '' : stageHow,
          ref: ref,
          to: letter ? letterTo : '',
          from: letter ? letterFrom : ''));
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
    stage('${json['note'] ?? ''}'.trim(),
        letterTo.isEmpty ? '작업 기록' : kLetterStage,
        letter: letterTo.isNotEmpty);
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
    // 🚨AND THE MOVE ITSELF IS NEVER A DUPLICATE, so it does not go through
    // `stage()`'s dedupe. Two moves to one place are two facts, each at its own
    // time. 🧪A card moved 할 일 → 백로그 → 할 일 → 백로그 from the board
    // wrote 「백로그로 옮김」 twice; the dedupe ate the second, and the card
    // stayed in 할 일 with the move in the file — the H25 loss above, one
    // level down.
    // ⚠️Whose move it is comes with it: `said` is the user's words on every
    // writer that sets it (a memo, a tick, a move from the board), so a move
    // on such a line is theirs even when its words were deduped away.
    // ⚠️Otherwise exactly the entry `stage()` would add — the PR still rides
    // it, and the placeholder pass below still reads it.
    if (at.isNotEmpty && kSection.containsKey(at)) {
      e.log.add(BoardLog(ts, at, '$at${ro(at)} 옮김',
          byUser: json['said'] != null, pr: prLeft,
          how: prLeft == null ? '' : stageHow, ref: '${json['ref'] ?? ''}'));
    }
    if (json['title'] != null) e.title = json['title'] as String;
    if (json['state'] != null) e.state = json['state'] as String;
    // ⛔`note` and `said` are NOT stored on the card. They are stages, and
    // `stage(...)` below puts each one in the log where it happened —
    // 「저장하는 것은 사건뿐, 나머지는 접어서 만든다」, the last piece of
    // `board-one-stream`.
    //
    // 🚨THEY WERE LAST-WINS FIELDS AND THAT COST A REAL BLIND SPOT: the
    // gate's 「PR을 본문에만 적은 카드」 read `c.note`, so a PR written into
    // an earlier note went silent the moment one more note followed it.
    // 🧪Measured, then folded — the check reads the log now.
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
    if (json['priority'] != null) e.priority = '${json['priority']}'.trim();
    if (json['owner'] != null) e.owner = '${json['owner']}'.trim();
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
  unreadFields = unread;
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
/// ⚠️Every value here is a place [_statusOfSection] knows, except `ask`, which
/// [placeWordOf] reads past — [statusOf] throws on any other. ↩️It used to be
/// the inverse of the old page's `_stateLabels`, gone with that page
/// (2026-10-02). A word that is not a section (구현 · AI 판단 · 정정 · 유저
/// 피드백 …) is deliberately absent — those are stages in the story, not
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
  // 🆕2026-10-02 — 유저: 「보드에 알려진 문제 항목이라는 새 항목 만들어서
  // 거기 격리하자. 계속 파악은 하고싶어」. Not 나중에: that is work put off;
  // this is a behaviour accepted as it is, watched rather than scheduled.
  '알려진 문제': 'known',
  // 🆕THE REDESIGN'S STATUS WORDS (유저 2026-10-02: 「최대한 프로들이랑
  // 똑같으면되」) — the same places under the names a tracker uses, so a
  // writer can say 백로그 instead of 나중에. ⚠️Aliases, not replacements: a
  // record written last month keeps its word, and both land in one place.
  '분류 대기': 'inbox',
  '백로그': 'queue',
  '할 일': 'open',
  '검증': 'hands',
  // 🆕「안 하기로 함 · 중복」 — an ending like 완료, so it shares 완료's
  // place; the board tells the two apart by the word ([statusOf]).
  '취소': 'archived',
  // 🚨실기 확인 is a SECTION now, not a kind of card — see [foldChecksIntoCards].
  '실기 확인': 'hands',
  // 🚨끝은 자리가 아니라 끝이다. 유저 2026-08-31: 「확인 다 끝나서 사라지는
  // 카드는 대분류 확인이 된다고 했잖아 … **대분류 이름적으로 완료가 더
  // 정확한데**」 — 맞다. 개별 체크 하나를 지우는  는 **소분류**라
  // 여기 없다: 칸을 안 바꾸므로 카드는 실기 확인에 그대로 있고, 규칙은
  // 하나도 늘지 않는다.
  // 🚨끝은 자리가 아니라 끝이다. 유저 2026-08-31: 「확인 다 끝나서 사라지는
  // 카드는 대분류 확인이 된다고 했잖아 … **대분류 이름적으로 완료가 더
  // 정확한데**」 — 맞다. 그래서 카드를 끝내는 말은 `완료` 다.
  //
  // ⚠️개별 체크 하나를 지우는 `확인 완료` 는 **소분류라 여기 없다**: 칸을
  // 안 바꾸므로 카드는 실기 확인에 그대로 있고, 규칙은 하나도 늘지 않는다
  // (유저: 「규칙 하나도 안 늘어나고 보드에서 확인 항목만 안 보일 뿐」).
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
  e.state = section;
}

/// 🚨★★★HOW MANY HANDS-ON CHECKS ON THIS CARD ARE STILL WAITING.
///
/// ⚠️Read by the TICK HANDLER, not by [placeByStory]. 유저 2026-08-31:
/// 「그냥 내가 실기 확인 제출해서 0개 되면 사라지는데, 그걸 그냥 **대분류
/// 확인이라는 항목을 만드는 작업으로 하면** 자연스럽게 되는 거 아니야?」 —
/// yes, and it deletes a special case: placement used to carry 「완료인데
/// 체크가 남았으면 실기로 되돌린다」, a rule about ONE 대분류 living inside
/// the reader. Now the writer counts and says which word it is — `확인` while
/// any remain, `완료` for the last — and the reader keeps its one rule.
List<String> checksWaiting(BoardCard e) {
  // A card that has ended has nothing left to try on a device, however it
  // ended — a 완료 entry, a bulk 확인 from the list (`archived`), or an old
  // clean tick (`deleted`). ⚠️Reopening writes `open` first, so a card brought
  // back is read in full again.
  if (e.state == 'archived' || e.state == 'deleted') return const [];
  final open = <String>[];
  final cleared = <String>{};
  for (var i = 0; i < e.log.length; i++) {
    final name = stageName(e, i);
    if (name == '실기 확인' || name == '검증') open.add(e.log[i].ts);
    if (name != '확인 완료' && name != '완료' && name != '취소') continue;
    final ref = e.log[i].ref;
    // ⚠️No `ref` on a 완료 means 「this card is done」, full stop — what every
    // 완료 written before per-check ticks existed meant. 🆕취소 ends it the
    // same way: a card nobody will do has nothing left to try on a device.
    // ↩️But only for the checks written BEFORE it (2026-10-02). It used to
    // end every check for good, so a card finished, reopened and sent to 검증
    // again from the board sat in 검증 waiting on nothing — no box to tick.
    if (ref.isEmpty && (name == '완료' || name == '취소')) {
      open.clear();
      continue;
    }
    cleared.add(ref);
  }
  return [for (final ts in open) if (!cleared.contains(ts)) ts];
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
/// Whether this card ASKS something — it carries options to pick from.
///
/// 🚨⛔NOT `kind == 'decision'`, and that is the whole point (유저 2026-08-31:
/// 「질문으로 옮김이라는 내용만 있는 질문항목이야. 질문의 내용이없어. 다른
/// 질문들이랑 뭐가 다르길래 이렇게 작동하지? **통일하고 이런일 없도록
/// 구조변경해도되**」).
///
/// `kind` was a WORD A WRITER HAD TO REMEMBER, and I forgot it six times in
/// one day: six question cards written as `item` reached 답할 것 and rendered
/// as ordinary rows — 「질문으로 옮김」 and no question inside. Nothing was
/// wrong with the data; the reader was asking the wrong thing about it.
///
/// ⚠️A card with options IS a question, whatever anyone called it. The legacy
/// `decision` kind still counts so nothing written before this loses its
/// panel.
bool cardAsks(BoardCard c) => c.options.isNotEmpty || c.kind == 'decision';

/// Whether an answered question is STILL only a question — no 대분류 has
/// moved it into a work column since.
///
/// ⚠️Reads [lastSection] and [kSection], the same pair [placeByStory] uses to
/// put the card on screen, for the reason the guard beside it gives: what is
/// being asked is 「would the board draw this as work」, and asking it any
/// other way is a second opinion that can drift from what is drawn.
bool _stillOnlyAsking(BoardCard c) {
  final section = kSection[lastSection(c)];
  return section == null || section == 'ask';
}

/// Which cards have ENDED, and why.
///
/// 🚨★★★IT LIVES HERE BECAUSE TWO SIDES ASK IT. `board_say` refuses a new
/// subject on an ended card and `board_check` decides whether a folded card
/// has quietly fallen off the board — the same question, and while this
/// function sat in the writer the gate answered it with a private
/// `state == archived || deleted` of its own. They disagreed about the very
/// same cards: a question answered BY HAND carries no `state`, so one side
/// called it 「이미 끝난 카드」 and the other 「끝나지도 않았는데」, and there
/// was no line anyone could write that satisfied both. That is precisely the
/// two-readers bug this file's own header forbids.
///
/// ⚠️A question that already carries an ANSWER counts as ended. It is not
/// archived by state, but writing a NEW question onto it is the same mistake:
/// the panel shows the old answer and the new words never become a question.
Map<String, String> endedCards(List<BoardCard> cards) => {
      for (final c in cards)
        if (c.state == 'archived')
          c.id: '완료'
        else if (c.state == 'deleted')
          c.id: '삭제됨'
        // 🚨★★★A QUESTION, not merely a card carrying an `answer`.
        // ⛔`R27-rest` is an ordinary work card whose old `/submit` left
        // `answer:"ok"` on it, and the first version of this guard read that
        // as 「answered question」 and refused to let me record findings on
        // live work. Measured within the hour of shipping it.
        // ⚠️`cardAsks` is the same reader the board draws by, so this cannot
        // drift into a second opinion about what a question is.
        //
        // 🚨★★★BUT ONLY WHILE IT IS STILL JUST A QUESTION. A card can raise a
        // question, get its answer, and CARRY ON AS WORK — `F-34` did exactly
        // that (asked how many digits a slider shows, 유저 answered on
        // 2026-09-01, and the next entry was `남은 것` with the plan). The
        // options stay on the card, so `cardAsks` keeps saying yes for ever,
        // and the guard was refusing every record about the work — including
        // the one that says it landed. Measured 2026-09-10: the card sat in
        // 착수 가능 with the code already written and no way to say so.
        //
        // ⛔The refusal's own reason is 「끝난 카드는 보드가 안 그린다」, so the
        // test has to be WHETHER IT IS DRAWN AS WORK. A card whose last
        // 대분류 is a question column is still a question; one that has moved
        // to 남은 것 · 착수 가능 · 하는 중 · 실기 확인 is not, and records
        // belong on it like any other card.
        else if (cardAsks(c) && c.answer != null && _stillOnlyAsking(c))
          c.id: '이미 답이 나온 질문',
    };

void foldQuestionsIntoCards(Map<String, BoardCard> byId, [DateTime? now]) {
  for (final q in byId.values.toList()) {
    if (!cardAsks(q)) continue;
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
    if (kSection[lastSection(c)] == 'hands') continue;
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

// ---------------------------------------------------------------- the axes

/// 🆕🚨★★★EACH CARD IS READ ON SEPARATE AXES — where it stands, whose move it
/// is, who holds it, how urgent — instead of one section answering all of
/// them (유저 2026-10-02: 「나중에 항목이라던가 착수가능 항목이라던가 이런
/// 항목 내가 생각해낸거니까 프로들은 어떤식으로 분류하고 그러는지」 ·
/// 「최대한 프로들이랑 똑같으면되」).
///
/// ⛔A section answered three questions at once, so a card true on two of
/// them could show one: 🧪on 2026-10-02 eleven cards held an unanswered
/// question and five of them sat in 답할 것; the other six were in 분류 전 ·
/// 대화 중 · 나중에 · 실기 확인, and nothing on screen said they asked.
///
/// ⚠️THE RECORD IS UNCHANGED. [placeByStory] still folds `state` exactly as
/// before — the gate and the writer read it — and this is a second reading of
/// the same story, the way a tracker keeps one event log and draws its views
/// from it.
///
/// ↩️🚨대화 중 IS A STATUS AGAIN (유저 2026-10-02: 「답 기다림이랑 백로그랑
/// 무슨차이지? 이부분 정리해야할거같은데」). The first cut folded it into
/// 백로그 as a flag and listed it under 나에게 온 것 as 「답 기다림」 — the same
/// cards in two places, waiting on an answer to no question. It is the user's
/// own column, named twice (08-25 상담대기: 「실제로 멈춰 있는 이유는 아직
/// 이야기가 안 끝나서」 · 08-31 대화 중): work held until a talk finishes —
/// the stage between 백로그 and 할 일, which trackers call 「needs
/// discussion」.
enum BoardStatus {
  triage,
  backlog,
  discussion,
  todo,
  doing,
  verify,
  known,
  done,
  canceled,
}

/// What each status is called on screen.
const kStatusName = <BoardStatus, String>{
  BoardStatus.triage: '분류 대기',
  BoardStatus.backlog: '백로그',
  BoardStatus.discussion: '대화 중',
  BoardStatus.todo: '할 일',
  BoardStatus.doing: '진행 중',
  BoardStatus.verify: '검증',
  BoardStatus.known: '알려진 문제',
  BoardStatus.done: '완료',
  BoardStatus.canceled: '취소',
};

/// The word that puts a card in each status — what a move writes. Every one
/// is a key of [kSection], so the fold places it like any other word.
const kStatusWord = <BoardStatus, String>{
  BoardStatus.triage: '분류 대기',
  BoardStatus.backlog: '백로그',
  BoardStatus.discussion: '대화 중',
  BoardStatus.todo: '할 일',
  BoardStatus.doing: '진행 중',
  BoardStatus.verify: '검증',
  BoardStatus.known: '알려진 문제',
  BoardStatus.done: '완료',
  BoardStatus.canceled: '취소',
};

/// The place word [statusOf] stands the card on, or '' when the story names
/// none — read past the two words that are no longer places: 유저 (the user
/// spoke, so the move is mine) and 질문 (a question, so the move is theirs).
/// ⚠️하는 중 keeps the shelf life [lastSection] gives it.
String placeWordOf(BoardCard e) {
  var spoke = '';
  for (var i = e.log.length - 1; i >= 0; i--) {
    final name = stageName(e, i);
    final section = kSection[name];
    if (name == '유저') {
      spoke = name;
      continue;
    }
    if (section == null || section == 'ask') continue;
    if (section == 'wip' && wentQuiet(e)) continue;
    // 🚨AN ENDING THE USER ANSWERED IS NOT AN ENDING. Their words after it say
    // something is still wrong — H24, F-28, F-22-rest and R27-rest were lost
    // for four days to exactly that (see `tickRecords`) — so the card comes
    // back to be read, where the fold puts it too. 🧪The first cut skipped
    // 유저 and read the 완료 under it: a last check ticked with 「아직 렉이
    // 있다」 was drawn finished, with nobody's turn.
    if (spoke.isNotEmpty && section == 'archived') return spoke;
    return name;
  }
  return '';
}

BoardStatus? _statusOfSection(String? section) => switch (section) {
      'inbox' => BoardStatus.triage,
      'queue' => BoardStatus.backlog,
      'gate' => BoardStatus.discussion,
      'open' => BoardStatus.todo,
      'wip' || 'mine' => BoardStatus.doing,
      'hands' => BoardStatus.verify,
      'known' => BoardStatus.known,
      'archived' || 'deleted' => BoardStatus.done,
      _ => null,
    };

/// Where the card stands. ⚠️An ending is read off `state`, which the fold
/// and a tick-dismissal both write; 취소 is told from 완료 by its word.
BoardStatus statusOf(BoardCard e) {
  if (e.state == 'archived' || e.state == 'deleted') {
    return lastSection(e) == '취소' ? BoardStatus.canceled : BoardStatus.done;
  }
  final word = placeWordOf(e);
  if (word.isNotEmpty) return _statusOfSection(kSection[word])!;
  // No place word in the story: what an older record's own `state` said, or a
  // card nobody has filed yet.
  return _statusOfSection(e.state) ?? BoardStatus.triage;
}

/// The questions on this card nobody has answered yet, oldest first.
List<BoardCard> openQuestions(BoardCard e) => [
      for (final l in e.log)
        if (l.ask != null && l.ask!.answer == null) l.ask!,
    ];

/// Whether the user has SAID something — a memo, an answer, words left on a
/// check — since I last wrote on the card, so the next move is mine.
///
/// ⚠️A move or a clean tick is the user ACTING, not saying: it is looked past,
/// not counted. 🧪Asking only about the newest entry, a memo followed by a
/// move went silent — the move was last, and the memo it buried still waited
/// on me with nothing saying so.
bool userSpokeLast(BoardCard e) {
  for (var i = e.log.length - 1; i >= 0; i--) {
    if (!e.log[i].byUser) return false;
    final name = stageName(e, i);
    if (name == '유저' || name.startsWith('유저 ') || name == '임시 메모') {
      return true;
    }
  }
  return false;
}

/// 🆕Whose move it is — both can be true at once: a card can hold a question
/// for the user while I owe an answer to their last memo.
///
/// ⚠️The user's turn is something they can press: a question to answer, a
/// check to tick. ↩️A card in 대화 중 used to count as well, and that is how
/// it came to be listed as 「답 기다림」 — a talk is held together, not
/// answered from the board.
({bool user, bool me}) turnOf(BoardCard e) {
  final status = statusOf(e);
  final ended = status == BoardStatus.done || status == BoardStatus.canceled;
  if (ended) return (user: false, me: false);
  final user = openQuestions(e).isNotEmpty || checksWaiting(e).isNotEmpty;
  return (user: user, me: userSpokeLast(e) || status == BoardStatus.triage);
}

/// 「담당: X」 in a note — how a session said it took a card before [BoardCard.owner]
/// existed. ⚠️Read only when the field is empty.
final _ownerInNote = RegExp(r'담당\s*[:：]\s*([^—()\n·*\]\[,.]+)');

/// Which session holds the card: the field, else the newest 「담당:」 in its story.
String ownerOf(BoardCard e) {
  if (e.owner.isNotEmpty) return e.owner;
  for (var i = e.log.length - 1; i >= 0; i--) {
    final m = _ownerInNote.firstMatch(e.log[i].text);
    if (m == null) continue;
    final name = m.group(1)!.trim().replaceFirst(RegExp(r'\s*세션$'), '');
    if (name.isNotEmpty) return name;
  }
  return '';
}

/// Tags that say what KIND of thing a card is; every other tag names its area.
const kTypeTags = <String>{'피드백', '아이디어', '임시', '기획'};

/// 🆕A build the user marked — 「이 빌드로 시험 중」. Verification is grouped
/// by these, the way a QA list belongs to the build it is run on.
typedef BoardBuild = ({String ts, String commit});

/// Every marked build, oldest first.
List<BoardBuild> buildsOf(List<BoardCard> cards) => [
      for (final c in cards)
        if (c.kind == 'build') (ts: c.created, commit: c.title),
    ]..sort((a, b) => a.ts.compareTo(b.ts));

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
