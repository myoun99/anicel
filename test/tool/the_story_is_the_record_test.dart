import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_check.dart';
import '../../tool/board_model.dart';
import '../helpers/temp_dir.dart';

/// 🚨★★★THE LAST PIECE OF `board-one-stream` — 「저장하는 것은 사건뿐,
/// 나머지는 접어서 만든다」.
///
/// `note` and `said` were LAST-WINS fields on the card while the same words
/// also became entries in its story. Two readings of one fact, and the card
/// itself warned what that costs: 「머리에 보이는 문장과 이야기의 마지막
/// 문장이 다를 수 있다」.
///
/// 🧪It was not theoretical. The gate's 「PR을 본문에만 적은 카드」 read
/// `c.note`, so a PR written into an EARLIER note went silent the moment one
/// more note followed it. Measured before the change: same card, same prose,
/// caught when the PR line was last and missed when one line followed. That
/// is not a gate, that is a coin toss on ordering.
///
/// ⚠️`title` STAYS a field, deliberately. A name is not a stage in a story,
/// and 「the last line that named it」 is what a name is.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('board-story'));
  tearDown(() => deleteTempQuietly(dir));

  File records(List<String> lines) =>
      File('${dir.path}/board.jsonl')..writeAsStringSync(lines.join('\n'));

  String complaints(List<String> lines) =>
      boardCheckComplaints(records(lines), now: DateTime.utc(2026, 9, 1));

  const kProse = 'PR을 본문에만 적은 카드';
  const head = '{"kind":"item","id":"W","at":"남은 것","title":"작업",'
      '"rest":"할 것","ts":"2026-08-31T20:00:00Z"}';
  const prLine =
      '{"kind":"item","id":"W","note":"#1234 로 고쳤다","ts":"2026-08-31T21:00:00Z"}';

  group('본문의 PR — 이야기 전체에서 찾는다', () {
    test('🚨the PR line last: caught (it always was)', () {
      expect(complaints([head, prLine]), contains(kProse));
    });

    test('🚨★★★one more note after it: STILL caught', () {
      // ⛔THE REGRESSION THIS FILE EXISTS FOR. Before the fold this went
      // silent, because `c.note` had been overwritten by the later line.
      final out = complaints([
        head,
        prLine,
        '{"kind":"item","id":"W","note":"그 다음 이야기",'
            '"ts":"2026-08-31T21:30:00Z"}',
      ]);
      expect(
        out,
        contains(kProse),
        reason: 'the fact did not change — only which line came last',
      );
    });

    test('⛔the user quoting a number is not me writing one', () {
      // The complaint is 「내가 본문에 적었다」. A user's own feedback that
      // mentions a PR is their words, and `said` entries are theirs.
      final out = complaints([
        head,
        '{"kind":"item","id":"W","said":"#1234 이후로 느려진 것 같아",'
            '"ts":"2026-08-31T21:00:00Z"}',
      ]);
      expect(out, isNot(contains(kProse)));
    });

    test('⛔an entry that CLAIMS its PR properly is the right shape', () {
      final out = complaints([
        head,
        '{"kind":"item","id":"W","pr":1234,"at":"구현","note":"고쳤다",'
            '"ts":"2026-08-31T21:00:00Z"}',
        '{"kind":"item","id":"W","at":"실기 확인","note":"이걸 본다",'
            '"ts":"2026-08-31T21:30:00Z"}',
      ]);
      expect(out, isNot(contains(kProse)));
    });
  });

  group('카드는 문장을 들고 있지 않는다', () {
    test('🚨note and said reach the story, and only the story', () {
      final cards = readBoard(records([
        head,
        '{"kind":"item","id":"W","note":"내 기록","ts":"2026-08-31T21:00:00Z"}',
        '{"kind":"item","id":"W","said":"유저 말","ts":"2026-08-31T21:30:00Z"}',
      ]));
      final w = cards.firstWhere((c) => c.id == 'W');
      expect(w.log.map((l) => l.text), containsAll(['내 기록', '유저 말']));
      expect(
        w.log.firstWhere((l) => l.text == '유저 말').byUser,
        isTrue,
        reason: 'whose words they are is what `said` MEANT, and the entry '
            'carries it — that is the part worth keeping',
      );
    });

    test('⛔title is still the card\'s name — a name is not a stage', () {
      final cards = readBoard(records([
        head,
        '{"kind":"item","id":"W","title":"다시 지은 이름",'
            '"ts":"2026-08-31T21:00:00Z"}',
      ]));
      expect(cards.firstWhere((c) => c.id == 'W').title, '다시 지은 이름');
    });
  });
}
