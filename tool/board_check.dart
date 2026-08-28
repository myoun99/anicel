// The board's own gate. Prints one complaint per problem and nothing at all
// when the file is clean; `board_gate.sh` blocks the turn on any output.
//
// Compiled to an exe by `board_up.sh` beside `board_server.exe` — a `dart run`
// here costs 1.8s of JIT on EVERY turn, which is what retired the last
// gate-side dart check. An exe starts in tens of milliseconds.
//
// It checks three things:
//
//  1. **Every line parses.** The board renderer SKIPS a bad line and carries
//     on — the right call for a board (30 items beat none) and the wrong one
//     for a gate, since a skipped item just quietly stops existing.
//
//  2. 🚨**Every question a person is meant to answer is actually answerable.**
//     Added 2026-08-26 because the user could not answer three cards in a row:
//
//     > 「지금 답할것 질문이 자세하게 안써있고 **대답칸도 없어서** 뭘 말하는
//     > 건지 모르겠어. **계속 그러는데** 해당항목 앞으로 구체적으로 쓰도록
//     > **규칙으로 강제해줘**」
//
//     The cause was mechanical, not stylistic. `_askPanel` renders `where`,
//     `why` and `options` — and never renders `note`. Cards written as one
//     `note` blob therefore arrived on screen as a bare title with no detail
//     and, because the radio buttons ARE the options, **no way to answer**.
//     A rule in a document could not have caught that; this can.
//
//  3. **Every new line says when it was written.** See `tsRequired` below.
import 'dart:convert';
import 'dart:io';

/// Matches a PR named in prose — 「#1302」, 「PR #1302」 — which the board
/// cannot file by. Four digits only: three-digit issue numbers and 「#1」
/// style round tags are not PRs.
final RegExp _prInProse = RegExp(r'#\d{4}\b');

/// When `<원본id>-Q<번호>` became the way to name a question (the round that
/// made the name the binding). Questions raised before it are not defects.
const String _questionNamingSince = '2026-08-27';

void main(List<String> args) {
  if (args.isEmpty) return;
  final file = File(args.first);
  if (!file.existsSync()) return;

  final bad = <int>[];

  /// Ids that said SOMETHING on at least one line — see [emptyCards].
  final hasWords = <String>{};
  // 🚨Lines appended after the watermark must carry `ts`, and the watermark is
  // a line in the file rather than a number in this source: the records file
  // is append-only, so 「everything after this line」 is a stable rule that no
  // later edit can shift.
  //
  // Why it needed a gate at all — the panel date (유저 2026-08-26: 「그 패널이
  // 갱신된게 언제인지」) is computed from `ts`, and 252 of 408 existing lines
  // did not have one. A date the board cannot know renders blank, which is
  // honest but useless; the only way it stops being blank is if every line
  // written from here on carries one. ⛔A rule in a document would not have —
  // three of the lines missing `ts` were written the same day this was found.
  final noTs = <int>[];
  var tsRequired = false;
  // 🚨★★★A CHECK WRITTEN INTO `rest` (유저 2026-08-27: 「이런거 잘 규칙으로
  // 정리하자. 재발안하도록」).
  //
  // `rest` means CODE remains, and a card that has any drops out of 확인할 것.
  // So a verification instruction put there does the exact opposite of what
  // it intends: the card that just shipped and most needs looking at is the
  // one that vanishes from the list of things to look at.
  //
  // ⛔A written law was not enough — I wrote that law on 08-27 and broke it
  // the same day, on the very next card. This is a lint on my own prose,
  // which is the honest shape: the gate is telling me I have described a
  // CHECK in the field for WORK. The check belongs on the 구현 stage's `how`.
  //
  // ⚠️Judged on the MERGED card, never line by line. The file is append-only,
  // so a `rest` I wrote badly and then cleared is still sitting in it — and a
  // gate that read every line would complain about corrected history forever,
  // which is the fastest way to teach someone to ignore a gate.
  final restIsACheck = <String>[];
  final checkWords = RegExp('실기|재확인|확인한다|확인해|검증|눌러 ?본|봐야');
  // Merged the way the server merges: later records overwrite only the
  // fields they name, so a card is judged as it will RENDER, not as any one
  // line spells it. Without that, an amendment line touching `state` alone
  // would read as a card with no options at all.
  final merged = <String, Map<String, dynamic>>{};
  final order = <String>[];

  var n = 0;
  for (final line in file.readAsLinesSync()) {
    n++;
    final t = line.trim();
    if (t.isEmpty) continue;
    try {
      final json = jsonDecode(t);
      if (json is! Map) {
        bad.add(n);
        continue;
      }
      if (json['kind'] != 'meta' && json['id'] == null) {
        bad.add(n);
        continue;
      }
      if (tsRequired && '${json['ts'] ?? ''}'.trim().isEmpty) noTs.add(n);
      if (json['kind'] == 'meta' && json['tsRequired'] == true) {
        tsRequired = true;
      }
      final id = json['id'];
      if (id is! String) continue;
      for (final field in const ['how', 'note', 'think', 'said', 'why']) {
        if ('${json[field] ?? ''}'.trim().isNotEmpty) hasWords.add(id);
      }
      if (!merged.containsKey(id)) {
        order.add(id);
      }
      merged[id] = {...?merged[id], ...json.cast<String, dynamic>()};
    } catch (_) {
      bad.add(n);
    }
  }

  // 🚨★★★DRAWN NOWHERE. A card can be in the file and on no list at all, and
  // that is worse than being on the wrong one — nothing brings it back
  // because nothing shows it (유저 2026-08-27: 「여러가지 함정있잖아? 제대로
  // 규칙대로 안굴러가는거」).
  //
  // The sections, and what each demands:
  //   분류 전   state == inbox
  //   답할 것   kind == decision && answer == null
  //   확인할 것 kind == check && answer == null   ·  OR a card with a pr
  //   착수/대기 kind == item && state != inbox && answer == null
  //
  // ⇒ An ITEM that is answered, out of the inbox and holds no PR satisfies
  // none of them. `C-ipad-crash` spent a turn exactly there: answered by a
  // memo, then triaged onward, which moved its state and left the answer set.
  final invisible = <String>[];
  // 🚨A CARD THAT IS ONLY A TITLE (유저 2026-08-27: 「카드있는 실기확인의 pr
  // 있는데, 그런거 가끔 진짜 pr이름만 타이틀로 있고 내용 아무것도 없을때
  // 많거든? 진짜 심플하게 pr만 카드로 등록한게 끝인거」).
  //
  // Claiming the PR is not the same as saying anything about it. A card with
  // the PR's own English title and no 이렇게 본다, no note, no story is the
  // `카드 없음` row wearing a card's clothes — and it passes the 「is there a
  // card」 check precisely because someone typed the two fields that make one.
  final emptyCards = <String>[];
  final prosePrs = <String>[];
  // 🚨★★★A STATE THE BOARD HAS NEVER HEARD OF FILES AS 「착수 가능」.
  //
  // The renderer drops `archived`/`deleted`, labels `wip`/`ask`/`gate`/
  // `queue`/`mine`/`inbox`, and treats everything else as ready to start.
  // So inventing a state name does not create a new column — it silently
  // files the card under 「명령만 내리면 착수」.
  //
  // 유저 2026-08-29 saw the result: 「색 키를 GPU로 보니까 작업완료고 남은건
  // 실기뿐인거같은데 이런건 착수가능이 아니라 실기확인에 있는게 맞는거아니야?
  // … 이거 게이트에 문제있는거같은데 분류못해내는거보니」. Twenty finished
  // cards were sitting there under `done`, a word nothing in the server
  // defines — along with `later`, `blocked`, `answered` and `idea`.
  //
  // ⛔The fix is NOT to teach the renderer these words. A state that means
  // 「finished」 already exists; a second name for it is the invention.
  final unknownStates = <String>[];
  const knownStates = <String>{
    'open',
    'inbox',
    'wip',
    'ask',
    'gate',
    'queue',
    'mine',
    'archived',
    'deleted',
  };
  // 🚨A question that belongs to nothing. `T14-Q1` binds by NAME; anything
  // else needs `of`. Without either, the answer has nowhere to be carried
  // back to and the card's own Q row will never mention it.
  final orphanQuestions = <String>[];
  final qName = RegExp(r'^(.+)-Q\d+$');

  // 🚨ONE ack file, EVERY complaint. It used to exempt only the checks added
  // last, so acking a card the gate named did nothing and the same line came
  // back every turn — an ack that does not silence is worse than none,
  // because the next reader learns to scroll past the gate.
  //
  // ⚠️What it means is 「I have decided to leave this card alone」, and that
  // decision is the same decision whichever complaint prompted it. Deciding
  // is the point; the file is where the decision is written down.
  final ackFile = File('${file.parent.path}/.gate-ack');
  final acked = ackFile.existsSync()
      ? ackFile.readAsLinesSync().map((l) => l.trim()).toSet()
      : <String>{};

  for (final id in order) {
    final card = merged[id]!;
    final state = '${card['state'] ?? 'open'}';
    if (state == 'archived' || state == 'deleted') continue;
    if (acked.contains(id)) continue;
    final rest = '${card['rest'] ?? ''}'.trim();
    if (rest.isNotEmpty && checkWords.hasMatch(rest)) restIsACheck.add(id);

    final kind = '${card['kind'] ?? 'item'}';
    if (kind == 'law' || kind == 'meta') continue;
    final answered = '${card['answer'] ?? ''}'.isNotEmpty;
    final hasPr = card['pr'] != null;

    // ⚠️Only questions raised SINCE the naming convention. The old
    // standalone ones are not defects — `Q-remaining-14` asks which of
    // fourteen cards to do first and genuinely belongs to none of them — and
    // a gate that complains about them every turn is a gate nobody reads.
    if (kind == 'decision' &&
        card['answer'] == null &&
        '${card['ts'] ?? ''}'.compareTo(_questionNamingSince) >= 0 &&
        !qName.hasMatch(id) &&
        '${card['of'] ?? ''}'.trim().isEmpty) {
      orphanQuestions.add(id);
    }

    // ⛔ITEMS only. An answered DECISION is meant to leave the lists — it
    // lives on as the reference in its origin's Q row — and an answered
    // CHECK was either ticked (deleted) or came back as feedback (inbox).
    // The hole is an item: answered, moved out of the inbox, holding no PR.
    if (kind == 'item' && answered && state != 'inbox' && !hasPr) {
      invisible.add(id);
    }
    if (hasPr && !hasWords.contains(id)) emptyCards.add(id);

    // 🚨★★★A PR NAMED IN PROSE IS A PR THE BOARD CANNOT SEE.
    //
    // The board files a card by its `pr` FIELD: a card whose PRs are all
    // merged leaves 착수 가능 and becomes something to check. Writing
    // 「#1302」 in the note tells the reader and nobody else, so the card
    // sits in 착수 가능 claiming to be unstarted work.
    //
    // 유저 2026-08-29 found four of them at once: 「색 키를 GPU로 보니까
    // 작업완료고 남은건 실기뿐인거같은데 이런건 착수가능이 아니라
    // 실기확인에 있는게 맞는거아니야? … 이거 게이트에 문제있는거같은데
    // 분류못해내는거보니」. The rule existed; nothing checked the input.
    if (kind == 'item' &&
        !hasPr &&
        state != 'archived' &&
        state != 'deleted' &&
        _prInProse.hasMatch('${card['note'] ?? ''}')) {
      prosePrs.add(id);
    }
    if (!knownStates.contains(state)) {
      unknownStates.add('$id($state)');
    }
  }

  final complaints = <String>[];
  if (bad.isNotEmpty) {
    complaints.add('${bad.length}개 줄이 깨졌습니다 (줄 ${bad.join(', ')})');
  }
  if (emptyCards.isNotEmpty) {
    complaints.add(
      '제목만 있고 내용이 없는 카드: ${emptyCards.join(', ')}\n'
      'PR을 물었다는 것과 그 PR에 대해 뭐라도 말했다는 것은 다릅니다 — 제목이 '
      'PR 제목 그대로면 보드를 열어도 무엇을 볼지 알 수 없습니다.\n'
      '⇒ 최소한 하나는 있어야 합니다: how(이렇게 본다) · note(무엇을 왜 '
      '바꿨나) · think(판단) · said(유저 원문)',
    );
  }
  if (invisible.isNotEmpty) {
    complaints.add(
      '어느 목록에도 안 뜨는 카드: ${invisible.join(', ')}\n'
      '답이 있으면 확인할 것에서 빠지고, state 가 inbox 가 아니면 분류 전에서도 '
      '빠지고, 착수 가능은 답 없는 것만 받습니다 — 파일에는 있고 화면에는 '
      '없습니다.\n'
      '⇒ 다시 일로 돌리려면 답을 비우세요: {"id":…, "answer":"", "state":"open"}',
    );
  }
  if (orphanQuestions.isNotEmpty) {
    complaints.add(
      '어느 카드의 질문인지 모르는 결정: ${orphanQuestions.join(', ')}\n'
      '이름이 `<원본id>-Q<번호>` 면 이름이 곧 연결입니다(예: T14-Q1). 옛 이름을 '
      '쓰려면 `of` 로 원본을 적으세요 — 없으면 답이 돌아갈 곳이 없고 원본 카드의 '
      'Q 목록에도 안 뜹니다.',
    );
  }
  if (restIsACheck.isNotEmpty) {
    complaints.add(
      '「남은 것」에 확인 방법이 들어 있는 카드: ${restIsACheck.join(', ')}\n'
      '`rest` 는 **코드가 남았다**는 뜻입니다 — rest 가 있으면 그 카드는 '
      '확인할 것에서 빠집니다. 방금 착지해서 확인이 필요한 카드가 확인 목록에서 '
      '사라지는 것이 정확히 반대 결과입니다.\n'
      '⇒ 확인 방법은 그 착지의 **구현 공정**에 씁니다: '
      '{"id":…, "at":"구현", "pr":N, "note":…, "how":"이렇게 확인한다 …"}',
    );
  }
  if (noTs.isNotEmpty) {
    complaints.add(
      'ts 가 없는 줄: ${noTs.join(', ')}\n'
      '보드 패널의 「생김 · 갱신」은 ts 로 그립니다 — 없으면 그 카드는 날짜가 '
      '안 뜨거나 옛 날짜에 멈춥니다. 각 줄에 '
      '"ts":"YYYY-MM-DDTHH:MM:SS+09:00" 를 넣으세요.',
    );
  }

  // A LIVE question: a decision still asking, with no answer submitted.
  final unanswerable = <String>[];
  final thin = <String>[];
  final misdirected = <String>[];
  for (final id in order) {
    final card = merged[id]!;
    if (card['kind'] != 'decision') continue;
    if (card['state'] != 'ask') continue;
    if (card['answer'] != null) continue;

    final options = card['options'];
    if (options is! List || options.length < 2) {
      unanswerable.add(id);
      continue;
    }
    // The detail the panel can actually show. `note` is not on that list —
    // it renders nowhere, so a card that keeps its reasoning there is a
    // title and a set of radio buttons with nothing to decide between.
    final where = '${card['where'] ?? ''}'.trim();
    final why = '${card['why'] ?? ''}'.trim();
    final labelled = options.every(
      (o) => o is Map && '${o['label'] ?? ''}'.trim().isNotEmpty,
    );
    if (where.isEmpty || why.isEmpty || !labelled) {
      thin.add(id);
    }
    // 🚨A `recommend` THAT NAMES NO OPTION IS TEXT NOBODY EVER SEES.
    //
    // The panel only compares it against an option key, so prose written
    // there renders as **nothing at all**. I put a whole paragraph of
    // reasoning into `recommend` on I-4-tone (2026-08-28) and the user never
    // saw a word of it — the same shape as the `note` failure this file was
    // written for. ⛔The server now shows misplaced text with a warning, but
    // the card should not get written that way in the first place.
    final recommend = '${card['recommend'] ?? ''}'.trim();
    if (recommend.isNotEmpty) {
      var index = 0;
      final keys = options.map((o) {
        index++;
        return '${(o is Map ? o['key'] : null) ?? index}';
      }).toSet();
      if (!keys.contains(recommend)) {
        misdirected.add(id);
      }
    }
  }

  if (unanswerable.isNotEmpty) {
    complaints.add(
      '답할 수 없는 결정 카드: ${unanswerable.join(', ')}\\n'
      '보드의 답변 라디오는 options 로 그려집니다 — options 가 없으면 화면에는 '
      '제목과 「다른 안」 칸만 뜹니다. 2개 이상 넣으세요.',
    );
  }
  if (thin.isNotEmpty) {
    complaints.add(
      '내용이 안 보이는 결정 카드: ${thin.join(', ')}\\n'
      'where(화면에서 뭔지) + why(왜 막혔나) + 각 option 의 label 이 필요합니다. '
      '⛔note 는 이 패널에 렌더링되지 않습니다 — 거기 적은 설명은 유저에게 '
      '보이지 않습니다.',
    );
  }

  if (unknownStates.isNotEmpty) {
    complaints.add(
      '보드가 모르는 state: ${unknownStates.join(', ')}\n'
      '아는 것은 ${knownStates.join(' · ')} 뿐이고, 나머지는 전부 '
      '「착수 가능」으로 떨어집니다 — 끝난 카드가 「명령만 내리면 착수」 칸에 '
      '앉습니다. ⛔새 이름을 지어내지 말고 있는 것을 쓰세요: 끝났으면 '
      'archived, 유저가 체크했으면 deleted, 나중이면 queue, 상담 대기면 gate.',
    );
  }

  if (prosePrs.isNotEmpty) {
    complaints.add(
      'PR을 본문에만 적은 카드: ${prosePrs.join(', ')}\n'
      '보드는 `pr` **필드**로 카드를 분류합니다 — PR이 전부 머지된 카드는 '
      '착수 가능에서 빠지고 확인할 것으로 갑니다. note 본문의 「#1302」는 '
      '사람만 읽습니다. ⚠️여러 장이면 **줄마다 pr 하나**로 나눠 적으세요 '
      '(`e.prs` 는 줄의 `pr` 로만 채워집니다).',
    );
  }

  if (misdirected.isNotEmpty) {
    complaints.add(
      '추천이 안 보이는 결정 카드: ${misdirected.join(', ')}\n'
      '`recommend` 는 **선택지의 키**(보통 1·2·3)를 적는 칸이고, 그 선택지에 '
      '「추천」 칩을 붙이는 데에만 쓰입니다. 문장을 적으면 화면에 아무것도 '
      '안 나옵니다 — 추천하는 이유는 why 나 그 선택지의 what/cost 에 쓰세요.',
    );
  }

  // 🚨★★★AN ANSWER NOBODY READ IS THE SAME AS NO ANSWER.
  //
  // 유저 2026-08-27: 「세션에서 대답 완료해서 작업끝났것이 답할것에 아직
  // 올라와있고 그런데 확인해줄래? **그런일 발생안하도록 작업흐름 개선하고
  // 싶고**」 — measured that day: TEN cards sat in 분류 전 with an answer on
  // them, and EIGHT more sat there unclassified. Two of those memos were the
  // work the user had just asked for out loud, written days earlier in a card
  // I had never opened.
  //
  // 분류 전 means 「내가 읽고 분류한다」. A card that stays there is not
  // waiting for the user, it is waiting for ME — and nothing made that
  // visible at the end of a turn.
  //
  // ⚠️AGE, not presence: feedback arriving this turn belongs in 분류 전 and
  // blocking on it would make the section useless. A day later it is not
  // triage any more, it is a card nobody read.
  final untriaged = <String>[];
  // The other half — a question still asking whose answer arrived in CHAT.
  // The board cannot know about those, so they sit for ever
  // (`Q-remaining-14` did, while the work its answer named was merged).
  final stale = <String>[];
  final now = DateTime.now();
  bool old(Map<String, dynamic> card) {
    final ts = DateTime.tryParse('${card['ts'] ?? ''}');
    // No stamp at all means it predates the `ts` rule — old by construction.
    return ts == null || now.difference(ts).inHours >= 24;
  }

  for (final id in order) {
    final card = merged[id]!;
    final state = '${card['state'] ?? ''}';
    if (acked.contains(id)) continue;
    final answer = card['answer'];
    final answered =
        answer != null && '$answer'.trim().isNotEmpty && '$answer' != 'null';
    if (state == 'inbox' && (answered || old(card))) {
      untriaged.add(id);
      continue;
    }
    if (state == 'ask' && !answered && old(card)) {
      stale.add(id);
    }
  }

  if (untriaged.isNotEmpty) {
    complaints.add(
      '분류 전에 하루 넘게 남은 카드: ${untriaged.join(', ')}\n'
      '분류 전은 「내가 읽고 분류한다」는 뜻입니다 — 그대로 두면 유저가 준 '
      '피드백을 아무도 안 읽은 것이 됩니다. 08-27에 열여덟 건이 그렇게 쌓였고 '
      '그중 둘이 유저가 그날 말로 요청한 바로 그 작업이었습니다.\n'
      '⇒ 카드마다 한 줄: 태그와 state 를 붙이고(할 일이 없으면 archived), '
      '유저 메모가 있으면 그 원문을 "said" 로 남기고 "answer":null 로 지웁니다.',
    );
  }
  if (stale.isNotEmpty) {
    complaints.add(
      '하루 넘게 답을 기다리는 질문: ${stale.join(', ')}\n'
      '이 대화에서 이미 답이 나오지 않았는지 확인하세요 — 채팅으로 온 답은 '
      '보드가 모릅니다. 답이 나왔으면 카드에 옮겨 적고 닫으세요.\n'
      '아직 진짜로 열려 있는 질문이면 그 id 를 .gate-ack 에 한 줄로 적으세요.',
    );
  }

  if (complaints.isNotEmpty) {
    stdout.write(complaints.join('\\n'));
  }
}
