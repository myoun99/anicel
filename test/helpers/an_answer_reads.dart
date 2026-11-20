import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

/// Whether [line] READS where it is laid: whole, or cut with its first
/// letter still on it, inside its own width — the rest of it the tooltip's
/// (`EllipsisText`).
///
/// 🗣️tool-settings-segments-overlap-at-the-narrowest-Q2 (유저 2026-11-18):
/// 「단추마다 첫 글자는 보이는 폭」.
bool lineReads(RenderParagraph line) {
  if (line.size.width + 0.01 >= line.getMaxIntrinsicWidth(double.infinity)) {
    return true;
  }
  final text = line.text.toPlainText();
  if (text.isEmpty) {
    return true;
  }
  final first = line.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.characters.first.length),
  );
  return first.isNotEmpty &&
      first.every(
        (box) => box.right > box.left && box.right <= line.size.width + 0.01,
      );
}
