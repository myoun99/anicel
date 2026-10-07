import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_model.dart';
import '../../tool/board_server.dart';
import '../helpers/temp_dir.dart';

/// 🆕THE BOARD READS EACH CARD ON SEPARATE AXES — where it stands, whose move
/// it is, who holds it (유저 2026-10-02: 「최대한 프로들이랑 똑같으면되」).
///
/// ⚠️The record is the same file; these are readings of it, and the list is
/// drawn from them. Each test is a way one of them went wrong while it was
/// being built, measured on a copy of the live records before it was fixed.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('board-axes'));
  tearDown(() => deleteTempQuietly(dir));

  // ⚠️Off the real clock, a second apart: 진행 중 is a claim that lapses a day
  // after the card's last entry ([wentQuiet]), so a fixed date here is a test
  // that fails next week.
  var clock = 0;
  String now() => DateTime.now()
      .subtract(const Duration(hours: 1))
      .add(Duration(seconds: clock++))
      .toIso8601String();

  List<BoardCard> read(List<String> lines) => readBoard(
        File('${dir.path}/board.jsonl')
          ..writeAsStringSync(lines.map((l) => '$l\n').join()),
      );
  BoardCard cardOf(List<String> lines, [String id = 'W']) =>
      read(lines).firstWhere((c) => c.id == id);

  /// [lines] and the line a move from the board writes.
  List<String> moved(List<String> lines, String to) => [
        ...lines,
        jsonEncode(
          moveRecord(card: cardOf(lines), id: 'W', to: to, now: now),
        ),
      ];

  /// [lines] and every line [write] makes of the card as it stands.
  List<String> plus(
    List<String> lines,
    List<Map<String, dynamic>> Function(BoardCard card) write,
  ) =>
      [...lines, ...write(cardOf(lines)).map(jsonEncode)];

  List<Map<String, dynamic>> quietTick(BoardCard c) => tickRecords(
        card: c,
        id: c.id,
        ref: checksWaiting(c).first,
        note: '',
        now: now,
      );

  const work = '{"kind":"item","id":"W","title":"작업","at":"나중에",'
      '"note":"할 것","ts":"2026-10-01T09:00:00"}';
  const tried = '{"kind":"item","id":"W","title":"작업","at":"실기 확인",'
      '"note":"이걸 본다","ts":"2026-10-01T09:00:00"}';
  const triedAgain = '{"kind":"item","id":"W","at":"실기 확인",'
      '"note":"저것도 본다","ts":"2026-10-01T09:10:00"}';
  const memo = '{"kind":"item","id":"W","at":"유저","said":"이것도 봐 줘",'
      '"ts":"2026-10-01T09:30:00"}';
  const question = '{"kind":"decision","id":"W-Q1","at":"질문",'
      '"title":"이렇게 할까","where":"거기","why":"막혔다",'
      '"options":[{"key":"a","label":"A안"},{"key":"b","label":"B안"}],'
      '"ts":"2026-10-01T10:00:00"}';

  group('상태 — 옮긴 말이 곧 자리', () {
    test('🚨every status the board offers is where its move puts the card',
        () {
      for (final s in BoardStatus.values) {
        expect(
          statusOf(cardOf(moved([work], kStatusWord[s]!))),
          s,
          reason: '⛔a word the select offers that the fold does not place '
              'is a move that silently does nothing',
        );
      }
    });

    test('🚨a card moved to and fro stands on its LAST move', () {
      // 🧪할 일 → 백로그 → 할 일 → 백로그 wrote 「백로그로 옮김」 twice, and
      // the story's dedupe ate the second: the card stayed in 할 일 with the
      // move in the file.
      var lines = [work];
      for (final to in ['할 일', '백로그', '할 일', '백로그']) {
        lines = moved(lines, to);
      }
      final card = cardOf(lines);
      expect(statusOf(card), BoardStatus.backlog);
      expect(
        card.log.where((l) => l.byUser && l.at == '백로그'),
        hasLength(2),
        reason: 'and each move is the user\'s own entry, the deduped one too',
      );
    });

    test('⛔a finished card moved back is open again', () {
      expect(
        statusOf(cardOf(moved(moved([work], '완료'), '할 일'))),
        BoardStatus.todo,
      );
    });

    test('⛔a record written in the old words lands in the same places', () {
      String at(String word) => '{"kind":"item","id":"W","title":"작업",'
          '"at":"$word","note":"$word","ts":"2026-10-01T09:00:00"}';
      expect(statusOf(cardOf([at('나중에')])), BoardStatus.backlog);
      expect(statusOf(cardOf([at('착수 가능')])), BoardStatus.todo);
      expect(statusOf(cardOf([at('실기 확인')])), BoardStatus.verify);
      // ↩️대화 중 and the words before it are a status again, not 백로그 with a
      // flag — see `BoardStatus`.
      expect(statusOf(cardOf([at('대화 중')])), BoardStatus.discussion);
      expect(statusOf(cardOf([at('상담 대기')])), BoardStatus.discussion);
    });

    test('🚨a card held for a talk waits on nobody\'s answer', () {
      // 🧪It was listed under 나에게 온 것 as 「답 기다림」: 백로그 with a flag,
      // so the same card stood in two places, waiting on no question.
      final card = cardOf(moved([work], '대화 중'));
      expect(statusOf(card), BoardStatus.discussion);
      expect(turnOf(card).user, isFalse);
      expect(
        turnOf(cardOf([...moved([work], '대화 중'), memo])).me,
        isTrue,
        reason: '⛔what the user says on it still comes back to me',
      );
    });

    test('⛔every word the fold places a card by reads as a status', () {
      // [statusOf] reads a place with `!`: a section value it does not map
      // throws on the first card written with that word.
      for (final word in kSection.keys) {
        final line = '{"kind":"item","id":"W","title":"작업","at":"$word",'
            '"note":"$word","ts":"${now()}"}';
        expect(() => statusOf(cardOf([line])), returnsNormally, reason: word);
      }
    });

    test('⛔a question does not move the card it is asked on', () {
      final card = cardOf([work, question]);
      expect(statusOf(card), BoardStatus.backlog);
      expect(openQuestions(card).map((q) => q.id), ['W-Q1']);
      expect(turnOf(card).user, isTrue);
    });

    test('🚨an ending the user answered is not an ending', () {
      // 🧪The first cut read the 완료 under the user's words: a last check
      // ticked with 「아직 렉이 있다」 was drawn finished, with nobody's turn —
      // the way H24, F-28, F-22-rest and R27-rest were lost for four days.
      final spoke = cardOf(plus([tried], (c) => tickRecords(
            card: c,
            id: 'W',
            ref: checksWaiting(c).first,
            note: '아직 렉이 있다',
            now: now,
          )));
      expect(statusOf(spoke), BoardStatus.triage);
      expect(turnOf(spoke).me, isTrue);

      final quiet = cardOf(plus([tried], quietTick));
      expect(statusOf(quiet), BoardStatus.done, reason: '⛔premise: the '
          'same tick without words does end it');
    });
  });

  group('차례 — 다음에 움직일 사람', () {
    test('🚨the user\'s memo stays my turn after they move the card', () {
      // 🧪Asking only about the newest entry, the move buried the memo.
      final once = moved([work, memo], '할 일');
      expect(turnOf(cardOf(once)).me, isTrue);
      expect(
        turnOf(cardOf(moved(moved(once, '백로그'), '할 일'))).me,
        isTrue,
        reason: 'back to 할 일, its words were deduped and the move read as '
            'mine',
      );
    });

    test('⛔a move alone is not a word to me', () {
      expect(turnOf(cardOf(moved([work], '할 일'))).me, isFalse);
    });

    test('⛔my note after their memo ends my turn', () {
      const reply = '{"kind":"item","id":"W","note":"읽었다",'
          '"ts":"2026-10-01T10:00:00"}';
      expect(turnOf(cardOf([work, memo])).me, isTrue, reason: '⛔premise');
      expect(turnOf(cardOf([work, memo, reply])).me, isFalse);
    });

    test('⛔a card the user finished after writing is nobody\'s turn', () {
      final card = cardOf(moved([work, memo], '완료'));
      expect(statusOf(card), BoardStatus.done);
      expect(turnOf(card), (user: false, me: false));
    });
  });

  group('확인 — 마지막 틱이 끝내는 것은 검증 칸의 카드뿐', () {
    test('⛔premise: the last quiet tick ends a card in 검증', () {
      final card = cardOf(plus([tried], quietTick));
      expect(card.state, 'archived');
      expect(checksWaiting(card), isEmpty);
    });

    test('🚨a card that moved on keeps its place when its check is ticked',
        () {
      final lines = moved([tried], '백로그');
      expect(checksWaiting(cardOf(lines)), hasLength(1), reason: '⛔premise');
      final card = cardOf(plus(lines, quietTick));
      expect(checksWaiting(card), isEmpty);
      expect(
        statusOf(card),
        BoardStatus.backlog,
        reason: 'this check passing is not the card finishing — it has work',
      );
    });

    test('🚨확인 on picked rows ticks each check, ending only a card in 검증',
        () {
      // ↩️It wrote `state: archived` on the card, from when one card was one
      // check; 🧪brush-fidelity and I-4 sat in 백로그 with work left.
      List<Map<String, dynamic>> confirm(BoardCard c) =>
          confirmRecords(card: c, now: now);
      final inVerify = [tried, triedAgain];
      expect(
        confirm(cardOf(inVerify)).map((l) => l['at']),
        ['확인 완료', '완료'],
      );
      expect(statusOf(cardOf(plus(inVerify, confirm))), BoardStatus.done);

      final movedOn = plus(moved(inVerify, '백로그'), confirm);
      expect(checksWaiting(cardOf(movedOn)), isEmpty);
      expect(statusOf(cardOf(movedOn)), BoardStatus.backlog);
    });

    test('🚨확인 on a picked row stamps every check its card holds', () {
      // 유저 2026-10-02: 「카드에 여러 실기확인있으면 여러 실기확인에도 확인
      // 찍히도록」. Drawn on a card that stays on the board, so the story is
      // there to read.
      final lines = moved([tried, triedAgain], '백로그');
      final before = cardOf(lines);
      expect(checksWaiting(before), hasLength(2), reason: '⛔premise');
      expect(
        confirmRecords(card: before, now: now).map((l) => l['ref']),
        checksWaiting(before),
        reason: 'one tick per check, each naming the check it clears',
      );
      final html = renderCards(read(plus(
        lines,
        (c) => confirmRecords(card: c, now: now),
      )));
      expect(
        RegExp('<span class="chip ok">확인함</span>').allMatches(html),
        hasLength(2),
      );
      expect(html, isNot(contains('class="tick"')), reason: 'no box is left');
    });

    test('🚨a card finished, reopened and sent to 검증 waits on the new check',
        () {
      // 🧪A 완료 ended every check for good, so it sat in 검증 with no box.
      final lines = moved(moved(moved([tried], '완료'), '할 일'), '검증');
      final card = cardOf(lines);
      expect(statusOf(card), BoardStatus.verify);
      expect(checksWaiting(card), hasLength(1));
    });

    test('⛔a card that ended by its state waits on nothing', () {
      // 🧪77 finished cards still counted checks and would have worn
      // 「실기 대기」 on the 완료 list.
      const born = '{"kind":"check","id":"C","title":"기기에서 본다",'
          '"how":"열고 본다","ts":"2026-10-01T09:00:00"}';
      expect(checksWaiting(cardOf([born], 'C')), hasLength(1),
          reason: '⛔premise');
      const cleared = '{"kind":"check","id":"C","state":"deleted",'
          '"ts":"2026-10-01T10:00:00"}';
      expect(checksWaiting(cardOf([born, cleared], 'C')), isEmpty);
    });
  });

  group('담당 · 빌드 · 목록 머리', () {
    test('the owner field wins over the 「담당:」 a note once said', () {
      const took = '{"kind":"item","id":"W","note":"🧭담당: 브러시 세션 — 집었다",'
          '"ts":"2026-10-01T10:00:00"}';
      expect(ownerOf(cardOf([work, took])), '브러시');
      const field = '{"kind":"item","id":"W","owner":"보드",'
          '"ts":"2026-10-01T11:00:00"}';
      expect(ownerOf(cardOf([work, took, field])), '보드');
    });

    test('builds come oldest first and are not cards', () {
      final cards = read([
        work,
        '{"kind":"build","id":"build-2","title":"bbb",'
            '"ts":"2026-10-02T09:00:00"}',
        '{"kind":"build","id":"build-1","title":"aaa",'
            '"ts":"2026-10-01T09:00:00"}',
      ]);
      expect(buildsOf(cards).map((b) => b.commit), ['aaa', 'bbb']);
      expect(boardHeads(cards).map((h) => h['id']), ['W']);
    });

    // 유저 2026-10-08, on F-283: 「이 카드 왜 검증에있지? 작업끝난건가?」 — one
    // part of it had landed and waited on its check, another was still to
    // do, and the 검증 list showed it like a finished card. Asked how the
    // row should say so: 「그 줄에 칩 하나 — 작업 남음」.
    test('🚨a head says when a card waits on a check while work on it is '
        'left', () {
      Map<String, Object?> headOf(List<String> lines) =>
          boardHeads(read(lines)).firstWhere((head) => head['id'] == 'W');

      expect(headOf([tried])['status'], 'verify', reason: '⛔premise');
      expect(headOf([tried])['workLeft'], isFalse);

      final reopened = moved([tried], '할 일');
      expect(headOf(reopened)['checks'], 1, reason: '⛔premise: it waits');
      expect(headOf(reopened)['status'], 'todo', reason: '⛔premise');
      expect(headOf(reopened)['workLeft'], isTrue);

      expect(headOf([work])['workLeft'], isFalse, reason: 'no check at all');
    });

    test('the list words that for where the row stands: 「작업 남음」 in the '
        '검증 groups, which no longer skip the chip, and 「실기 대기」 '
        'everywhere else', () {
      final script = boardScript();
      expect(
        script,
        contains(
          "if (c.workLeft) f.push(['check', "
          "g && g.pick ? '작업 남음' : '실기 대기', 'run']);",
        ),
      );
      expect(script, contains('flagsOf(c, g)'));
      expect(script, contains('x.pick = true; out.push(x);'));
      expect(script, isNot(contains("x.skip = ['check']")));
      expect(
        script,
        isNot(contains("c.status !== 'verify') f.push")),
        reason: 'the page does not work the fact out a second time',
      );
    });

    test('a head carries the axes the list groups by', () {
      const tagged = '{"kind":"item","id":"W","tags":["피드백","보드"],'
          '"ts":"2026-10-01T09:05:00"}';
      final head = boardHeads(read([work, tagged, question]))
          .firstWhere((h) => h['id'] == 'W');
      expect(head['status'], 'backlog');
      expect(head['q'], ['이렇게 할까']);
      expect(head['user'], isTrue);
      expect(head['type'], '피드백');
      expect(head['areas'], ['보드']);
    });
  });
}
