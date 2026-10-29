import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/se_line_type.dart';
import 'package:anicel/src/services/editing/cut_duplicate_helpers.dart';

/// 🗣️I-20 (유저 2026-09-30): 「se 블록의 타입으로서 on off mono 타입 추가」 ·
/// I-20-Q1 「타입이 없는 상태는 존재하지않음. 기본값은 ON」 · I-20-Q2 「콘티
/// 대사 칸에도 찍는다 — 이름 뒤 괄호」 + 「ON일때는 타임시트 이름위랑
/// 콘티용지에는 표시하지않음 … OFF거나 MONO일때만」.
void main() {
  Frame block({SeLineTypes seTypes = SeLineTypes.allOn}) => Frame(
    id: const FrameId('se-1'),
    duration: 1,
    strokes: const [],
    name: 'やめて',
    seName: 'A子',
    seTypes: seTypes,
  );
  const c1 = CutId('c1');
  const c2 = CutId('c2');
  const c3 = CutId('c3');
  // 🗣️F-386: ON in the cut where she is seen, OFF in the next.
  final onThenOff = SeLineTypes(byCut: {c2: SeLineType.off});

  group('a block that never chose is ON, and ON is the absent field', () {
    test('a new block and an old file read back as ON in every cut', () {
      expect(block().seTypes, SeLineTypes.allOn);
      expect(block().seTypes.inCut(c1), SeLineType.on);
      final old = block().toJson()..remove('seType');
      expect(Frame.fromJson(old).seTypes, SeLineTypes.allOn);
    });

    test('ON is not written; OFF and MONO are, and come back', () {
      expect(block().toJson().containsKey('seType'), isFalse);
      expect(block().toJson().containsKey('seTypeByCut'), isFalse);
      for (final type in [SeLineType.off, SeLineType.mono]) {
        final json = block(seTypes: SeLineTypes(own: type)).toJson();
        expect(json['seType'], type.name);
        expect(Frame.fromJson(json).seTypes.inCut(c1), type);
      }
    });

    test('a delivery is part of the drawing — equality and copies see it',
        () {
      expect(block(seTypes: SeLineTypes(own: SeLineType.off)), isNot(block()));
      expect(block(seTypes: onThenOff), isNot(block()));
      expect(block(seTypes: onThenOff).copyWith(name: 'x').seTypes, onThenOff);
      expect(
        duplicateFrameContent(
          frame: block(seTypes: onThenOff),
          newFrameId: const FrameId('se-2'),
        ).seTypes,
        onThenOff,
        reason: 'the duplicate helper used to rebuild a frame field by field '
            'and drop whatever it had not been told about',
      );
    });
  });

  group('F-386: a delivery is the block\'s in a cut', () {
    test('a cut with an answer of its own says it; every other says the '
        'block\'s own', () {
      expect(onThenOff.inCut(c1), SeLineType.on);
      expect(onThenOff.inCut(c2), SeLineType.off);
      expect(onThenOff.inCut(c3), SeLineType.on,
          reason: 'a cut the block reaches later carries on as it began');
      expect(onThenOff.inCut(null), SeLineType.on,
          reason: 'a block between cuts has its own alone');
    });

    test('a cut that says what the block says is not kept apart', () {
      expect(
        SeLineTypes(own: SeLineType.off, byCut: {c1: SeLineType.off}),
        SeLineTypes(own: SeLineType.off),
      );
      expect(onThenOff.withCut(c2, SeLineType.on), SeLineTypes.allOn);
    });

    test('each cut\'s answer is written under its cut and comes back', () {
      final types = SeLineTypes(
        own: SeLineType.mono,
        byCut: {c2: SeLineType.off, c3: SeLineType.on},
      );
      final json = block(seTypes: types).toJson();
      expect(json['seType'], 'mono');
      expect(json['seTypeByCut'], {'c2': 'off', 'c3': 'on'});
      expect(Frame.fromJson(json).seTypes, types);
    });

    test('the window writes back the cuts it showed, the head\'s as the '
        'block\'s own', () {
      final left = SeLineTypes(
        byCut: {c2: SeLineType.off, c3: SeLineType.mono},
      );
      // Moved on so it plays in c2 and c3: c2's answer becomes the block's
      // own, and what c1 said goes with the cut the window no longer shows.
      expect(
        left.shownIn([c2, c3]),
        SeLineTypes(own: SeLineType.off, byCut: {c3: SeLineType.mono}),
      );
      expect(left.shownIn([c2]), SeLineTypes(own: SeLineType.off),
          reason: 'c3\'s answer, not shown, is let go');
      expect(left.shownIn(const []), left,
          reason: 'a block in no cut keeps what it has');
    });

    test('the pills set the picked cut, or the block\'s own in no cut', () {
      expect(SeLineTypes.allOn.withCut(c2, SeLineType.off), onThenOff);
      expect(
        onThenOff.withCut(null, SeLineType.mono),
        SeLineTypes(own: SeLineType.mono, byCut: {c2: SeLineType.off}),
      );
    });
  });

  group('the sheets print OFF and MONO, never ON', () {
    test('one answer for both sheets', () {
      expect(SeLineType.on.writtenOut, isFalse);
      expect(SeLineType.off.writtenOut, isTrue);
      expect(SeLineType.mono.writtenOut, isTrue);
    });

    test('the conte dialogue column: speaker(TYPE)「line」', () {
      ConteDialogueLine line(SeLineType type, {String speaker = 'A子'}) =>
          ConteDialogueLine(
            startFrame: 0,
            text: 'やめて',
            speaker: speaker,
            delivery: type,
          );
      expect(line(SeLineType.on).printed, 'A子「やめて」');
      expect(line(SeLineType.off).printed, 'A子(OFF)「やめて」');
      expect(line(SeLineType.mono).printed, 'A子(MONO)「やめて」');
      expect(line(SeLineType.off, speaker: '').printed, '(OFF)「やめて」');
      expect(line(SeLineType.on, speaker: '').printed, 'やめて');
    });
  });
}
