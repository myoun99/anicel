import 'dart:math' as math;

/// A sound's offset trim after a slide of [dragPixels] along the frame axis
/// at [pixelsPerFrame]: dragging the waveform toward the block's start
/// (negative pixels) plays a LATER part of the file there. Clamped into the
/// file — never before its start, never past its last frame ([fileFrames]).
///
/// ONE law for every surface that slides a sound under its block: the
/// audio lane's span and the block edit window's strip (유저 2026-09-27:
/// 「이거 블록별로 오프셋이 맞지않나? 그래서 블록 편집창에서 하는게
/// 맞을듯」).
int slidAudioOffset({
  required int base,
  required double dragPixels,
  required double pixelsPerFrame,
  required int fileFrames,
}) => (base - (dragPixels / pixelsPerFrame).round()).clamp(
  0,
  math.max(0, fileFrames - 1),
);

/// An offset trim as the person reads it: frames skipped into the file.
String formatAudioOffset(int offsetFrames) => '${offsetFrames}f';
