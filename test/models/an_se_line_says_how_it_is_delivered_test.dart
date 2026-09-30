import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/se_line_type.dart';
import 'package:anicel/src/services/editing/cut_duplicate_helpers.dart';

/// 🗣️I-20 (유저 2026-09-30): 「se 블록의 타입으로서 on off mono 타입 추가」 ·
/// I-20-Q1 「타입이 없는 상태는 존재하지않음. 기본값은 ON」 · I-20-Q2 「콘티
/// 대사 칸에도 찍는다 — 이름 뒤 괄호」 + 「ON일때는 타임시트 이름위랑
/// 콘티용지에는 표시하지않음 … OFF거나 MONO일때만」.
void main() {
  Frame block({SeLineType seType = SeLineType.on}) => Frame(
    id: const FrameId('se-1'),
    duration: 1,
    strokes: const [],
    name: 'やめて',
    seName: 'A子',
    seType: seType,
  );

  group('a block that never chose is ON, and ON is the absent field', () {
    test('a new block and an old file read back as ON', () {
      expect(block().seType, SeLineType.on);
      final old = block().toJson()..remove('seType');
      expect(Frame.fromJson(old).seType, SeLineType.on);
    });

    test('ON is not written; OFF and MONO are, and come back', () {
      expect(block().toJson().containsKey('seType'), isFalse);
      for (final type in [SeLineType.off, SeLineType.mono]) {
        final json = block(seType: type).toJson();
        expect(json['seType'], type.name);
        expect(Frame.fromJson(json).seType, type);
      }
    });

    test('a delivery is part of the drawing — equality and copies see it',
        () {
      expect(block(seType: SeLineType.off), isNot(block()));
      expect(block(seType: SeLineType.off).copyWith(name: 'x').seType,
          SeLineType.off);
      expect(
        duplicateFrameContent(
          frame: block(seType: SeLineType.mono),
          newFrameId: const FrameId('se-2'),
        ).seType,
        SeLineType.mono,
        reason: 'the duplicate helper used to rebuild a frame field by field '
            'and drop whatever it had not been told about',
      );
    });
  });

  group('the sheets print OFF and MONO, never ON', () {
    test('one answer for both sheets', () {
      expect(SeLineType.on.printsOnSheets, isFalse);
      expect(SeLineType.off.printsOnSheets, isTrue);
      expect(SeLineType.mono.printsOnSheets, isTrue);
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
