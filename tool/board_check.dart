// The board's own gate. Prints one complaint per problem and nothing at all
// when the file is clean; `board_gate.sh` blocks the turn on any output.
//
// Compiled to an exe by `board_up.sh` beside `board_server.exe` — a `dart run`
// here costs 1.8s of JIT on EVERY turn, which is what retired the last
// gate-side dart check. An exe starts in tens of milliseconds.
//
// It checks two things:
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
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) return;
  final file = File(args.first);
  if (!file.existsSync()) return;

  final bad = <int>[];
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

  final complaints = <String>[];
  if (bad.isNotEmpty) {
    complaints.add('${bad.length}개 줄이 깨졌습니다 (줄 ${bad.join(', ')})');
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
