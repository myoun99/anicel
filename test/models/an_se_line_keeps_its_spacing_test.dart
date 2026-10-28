import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/se_dialogue_spacing.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/services/editing/cut_duplicate_helpers.dart';

/// 🗣️F-496 ③ (유저 2026-10-28): 「글자별 코마는 기본값 3코마, 오프셋은
/// 기본값 0(1코마째부터 시작)」 — the block's own, written with it.
void main() {
  Frame block({SeDialogueSpacing spacing = SeDialogueSpacing.standard}) =>
      Frame(
        id: const FrameId('se-1'),
        duration: 12,
        strokes: const [],
        name: 'やめて',
        seName: 'A子',
        seSpacing: spacing,
      );
  const set = SeDialogueSpacing(offset: 2, komaPerGlyph: 5);

  test('a block that never set it starts on its first frame, three a '
      'glyph', () {
    expect(block().seSpacing, SeDialogueSpacing.standard);
    expect(
      (
        offset: SeDialogueSpacing.standard.offset,
        koma: SeDialogueSpacing.standard.komaPerGlyph,
      ),
      (offset: 0, koma: 3),
    );
  });

  test('an offset before the block reads as its first frame, and a glyph '
      'takes a frame at least', () {
    expect(
      const SeDialogueSpacing(offset: -4, komaPerGlyph: 0),
      const SeDialogueSpacing(offset: 0, komaPerGlyph: 1),
    );
  });

  test('the standard is not written; a set spacing is, and comes back', () {
    final standard = block().toJson();
    expect(standard.containsKey('seDialogueOffset'), isFalse);
    expect(standard.containsKey('seKomaPerGlyph'), isFalse);
    expect(Frame.fromJson(standard).seSpacing, SeDialogueSpacing.standard);

    expect(Frame.fromJson(block(spacing: set).toJson()).seSpacing, set);
    for (final one in [
      const SeDialogueSpacing(offset: 4),
      const SeDialogueSpacing(komaPerGlyph: 1),
    ]) {
      expect(
        Frame.fromJson(block(spacing: one).toJson()).seSpacing,
        one,
        reason: 'each field on its own: $one',
      );
    }
  });

  test('the spacing is part of the drawing — equality and copies see it', () {
    expect(block(spacing: set), isNot(block()));
    expect(block(spacing: set).copyWith(name: 'x').seSpacing, set);
    expect(
      block().copyWith(seSpacing: set).seSpacing,
      set,
      reason: 'the dialog writes it through the copy',
    );
    expect(
      duplicateFrameContent(
        frame: block(spacing: set),
        newFrameId: const FrameId('se-2'),
      ).seSpacing,
      set,
    );
  });

  test('a sheet cell sees it too: two that differ in it alone are not one',
      () {
    const head = TimesheetCell(TimesheetCellKind.drawing, spanLength: 12);
    expect(
      const TimesheetCell(
        TimesheetCellKind.drawing,
        spanLength: 12,
        seSpacing: set,
      ),
      isNot(head),
      reason: 'a sheet that keeps its picture by its cells repaints on it',
    );
  });
}
