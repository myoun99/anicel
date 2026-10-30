// A PENCIL IS GRAINED BY ITS TIP, AND THE PAPER ONLY TOUCHES IT (F-511, 유저
// 2026-10-30: 「설정의 질감으로 연필느낌 얼버무린다니까? … 질감을 꺼도
// 팁자체가 연필느낌나게 … 브러시 팁으로서 표현하라고 몇번을말해」 · 「아예
// 질감을 없애란게 아니고 클튜정도로」).
//
// 🧪THE CONTROL IS BUILT IN: the same stroke, the same dice, on a plain round
// tip. It has to read smooth, or `_grain` would be measuring something else.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/services/brush_preset_defaults.dart';
import 'package:anicel/src/services/brush_tip_mask_defaults.dart';
import 'package:anicel/src/ui/brush/brush_stroke_preview_cache.dart';

const _width = 400;

/// 40 px at the pressure arc's height: the row is 1 / 0.62 of its nib.
const _height = 64;

const _grades = [
  'builtin-hard-pencil',
  'builtin-pencil',
  'builtin-soft-pencil',
  'builtin-dark-pencil',
  'builtin-colored-pencil',
  'builtin-mechanical-pencil',
];

BrushSettings _settingsOf(String id) =>
    defaultBrushPresets.firstWhere((preset) => preset.id.value == id).settings;

BrushSettings _withoutPaper(BrushSettings settings) => BrushSettings.fromShape(
  settings.shape.withMask(BrushMaskSlot.texture, null),
);

BrushSettings _onARound(BrushSettings settings) =>
    BrushSettings.fromShape(settings.shape.copyWith(tips: const []));

Uint8List _line(BrushSettings settings) =>
    rasterizeBrushStrokeSample(settings, _width, _height);

/// How far a pixel of the line stands from its neighbour, as a share of the
/// line's own ink: a smooth band reads near nothing, specks near one.
double _grain(Uint8List line) {
  var steps = 0;
  var ink = 0;
  for (var y = 0; y < _height; y += 1) {
    for (var x = 0; x + 1 < _width; x += 1) {
      final here = line[y * _width + x];
      final next = line[y * _width + x + 1];
      if (here == 0 && next == 0) {
        continue;
      }
      steps += (here - next).abs();
      ink += here > next ? here : next;
    }
  }
  return steps / ink;
}

/// The line's ink, summed.
int _ink(Uint8List line) => line.fold(0, (sum, level) => sum + level);

void main() {
  test('🗣️with the paper off a pencil\'s line is still specks — and a round '
      'tip laid the same way is not', () {
    for (final id in _grades) {
      final off = _withoutPaper(_settingsOf(id));
      expect(_grain(_line(off)), greaterThan(0.25), reason: id);
      expect(_grain(_line(_onARound(off))), lessThan(0.1), reason: '$id round');
    }
  });

  test('🗣️the paper only touches it: on or off, the line lays the same ink '
      'within a tenth', () {
    for (final id in _grades) {
      final on = _ink(_line(_settingsOf(id)));
      final off = _ink(_line(_withoutPaper(_settingsOf(id))));
      expect(on / off, greaterThan(0.9), reason: id);
    }
  });

  test('each tip is a cloud of flecks, thin enough to stay one at the general '
      'step, and none is the next', () {
    double emptyShare(BrushTipMask tip) =>
        tip.alpha.where((level) => level == 0).length / tip.alpha.length;
    for (final tip in pencilCrumbBrushTipMasks) {
      expect(emptyShare(tip), inInclusiveRange(0.8, 0.9), reason: tip.id);
    }
    expect(
      pencilCrumbBrushTipMasks.map((tip) => tip.alpha.join()).toSet(),
      hasLength(3),
    );
  });
}
