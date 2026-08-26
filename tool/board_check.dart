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

void main(List<String> args) {
  if (args.isEmpty) return;
  final file = File(args.first);
  if (!file.existsSync()) return;

  final bad = <int>[];
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
      if (!merged.containsKey(id)) {
        order.add(id);
      }
      merged[id] = {...?merged[id], ...json.cast<String, dynamic>()};
    } catch (_) {
      bad.add(n);
    }
  }

  for (final id in order) {
    final card = merged[id]!;
    if (card['state'] == 'archived' || card['state'] == 'deleted') continue;
    final rest = '${card['rest'] ?? ''}'.trim();
    if (rest.isNotEmpty && checkWords.hasMatch(rest)) restIsACheck.add(id);
  }

  final complaints = <String>[];
  if (bad.isNotEmpty) {
    complaints.add('${bad.length}개 줄이 깨졌습니다 (줄 ${bad.join(', ')})');
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

  if (complaints.isNotEmpty) {
    stdout.write(complaints.join('\\n'));
  }
}
