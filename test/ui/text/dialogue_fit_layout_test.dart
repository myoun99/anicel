import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/se_dialogue_spacing.dart';
import 'package:anicel/src/ui/text/dialogue_fit_layout.dart';

/// 🗣️F-496 ③ (유저 2026-10-28): 「왼쪽정렬로 둬서 1코마부터 첫번째 글자가
/// 시작되도록. 대사 오프셋은 이 시작되는 위치를 변경함. 1코마기준으로
/// 움직임. 글자별 코마는 … 3코마로 설정하면 글자 하나당 3코마의 공간을
/// 차지하는느낌」.
void main() {
  // Twelve frames of 10.
  List<DialogueGlyphSlot> slots(
    int glyphs, {
    int frames = 12,
    SeDialogueSpacing spacing = SeDialogueSpacing.standard,
  }) => dialogueGlyphSlots(
    glyphCount: glyphs,
    frames: frames,
    mainExtent: frames * 10.0,
    spacing: spacing,
  );

  test('glyph i stands on the frame i koma in, its koma to grow into', () {
    expect(slots(3), [
      (cellStart: 0.0, cellExtent: 10.0, roomExtent: 30.0),
      (cellStart: 30.0, cellExtent: 10.0, roomExtent: 30.0),
      (cellStart: 60.0, cellExtent: 10.0, roomExtent: 30.0),
    ], reason: 'from the first frame, three a glyph — the standard');
  });

  test('the offset moves the first glyph by frames, and the rest with it',
      () {
    expect(
      slots(
        2,
        spacing: const SeDialogueSpacing(offset: 2, komaPerGlyph: 4),
      ).map((slot) => slot.cellStart),
      [20.0, 60.0],
    );
  });

  test('glyphs too many for the frames after the offset share them '
      'evenly — the offset stays where it was set', () {
    expect(
      slots(4, frames: 6, spacing: const SeDialogueSpacing(offset: 2)),
      [
        for (final at in [20.0, 30.0, 40.0, 50.0])
          (cellStart: at, cellExtent: 10.0, roomExtent: 10.0),
      ],
    );
    expect(
      slots(8, frames: 4).first,
      (cellStart: 0.0, cellExtent: 5.0, roomExtent: 5.0),
      reason: 'half a frame each: its cell no longer than its share',
    );
  });

  test('an offset past the block stands on its last frame', () {
    expect(
      slots(1, frames: 4, spacing: const SeDialogueSpacing(offset: 9)),
      [(cellStart: 30.0, cellExtent: 10.0, roomExtent: 10.0)],
    );
  });

  test('no glyphs, or a block of no frames, lay nothing', () {
    expect(slots(0), isEmpty);
    expect(slots(3, frames: 0), isEmpty);
  });

  test('🚨F-358: a window shows the glyphs whose frame it holds — the '
      'whole block\'s, not its own share laid again', () {
    // Cell centres 5, 35, 65.
    final three = slots(3);
    expect(dialogueGlyphsShownIn(three), (first: 0, end: 3));
    expect(
      dialogueGlyphsShownIn(three, from: 35),
      (first: 1, end: 3),
      reason: 'a centre on the opening edge is the window\'s',
    );
    expect(
      dialogueGlyphsShownIn(three, from: 36, to: 65),
      (first: 2, end: 2),
      reason: 'and one on the closing edge is the next window\'s',
    );
    expect(dialogueGlyphsShownIn(const [], from: 10), (first: 0, end: 0));
  });

  // F-93's narrowing moved to `word_condensation_test.dart` with the rule
  // itself — it is every block word's now, not the dialogue's alone.
}
