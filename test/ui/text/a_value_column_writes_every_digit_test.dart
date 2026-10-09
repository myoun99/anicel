import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/text/readout_text.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart';

/// 🗣️F-326 (유저 2026-10-09): 「트랜스폼이든 카메라행이든 위치값같은게
/// 소수점까지 조정가능한 숫자 다 보여줌이라는 규칙에 어긋남. 1218이다가
/// 조절하면 소수점보엿다가 정수면 소수점사라지고 이럼. 이건 변형도구 숫자
/// 바뀔떄도 같음」.
///
/// A value column — a timeline lane, a tool setting's drag readout — writes
/// every digit of the readout grid whatever the value happens to be: the
/// slider's law and the view pill's ([readoutText]). ↩️It rounded to one
/// decimal (two in the Move tool) and dropped the trailing zeros, so a
/// number read `1218`, then `1218.3` under the same finger, then `1218`.
void main() {
  test('the digits stay under the finger — a whole number keeps them', () {
    for (final (value, text) in const [
      (1218.0, '1218.00'),
      (1218.3, '1218.30'),
      (1218.37, '1218.37'),
      (-3.5, '-3.50'),
      (0.0, '0.00'),
      (-0.004, '0.00'),
      (99.996, '100.00'),
    ]) {
      expect(columnValueText(value), text, reason: 'value $value');
    }
  });

  test('every lane writes them, its unit after', () {
    const spec = EffectParameterSpec(
      id: 'p',
      label: 'P',
      minimum: -10000,
      maximum: 10000,
      defaultValue: 0,
      unit: EffectParameterUnit.pixels,
    );
    expect(formatEffectLaneValue(spec, 12), '12.00 px');
    const number = EffectParameterSpec(
      id: 'n',
      label: 'N',
      minimum: -10000,
      maximum: 10000,
      defaultValue: 0,
      unit: EffectParameterUnit.number,
    );
    expect(formatEffectLaneValue(number, 3), '3.00');
    expect(
      formatTransformLaneValue(
        'position',
        TransformPose(center: CanvasPoint(x: 1218, y: 99.996)),
      ),
      '1218.00, 100.00',
    );
    expect(
      formatTransformLaneValue(
        'rotation',
        TransformPose(center: CanvasPoint(x: 0, y: 0), rotationDegrees: -3.5),
      ),
      '-3.50°',
    );
    const tag = SeNameTag(
      style: TextCelStyle(fontSize: 12, letterSpacing: 0.1),
    );
    expect(formatSeNameTagLaneValue(seNameTagSizeLaneId, tag), '12.00');
    expect(formatSeNameTagLaneValue(seNameTagTrackingLaneId, tag), '0.10');
  });

  test('a scrubbed lane writes them too — what it commits is what it '
      'shows', () {
    expect(
      scrubTransformLaneValue('position', '1218.00, 0.00', const Offset(1, 0)),
      '1219.00, 0.00',
    );
    expect(
      scrubTransformLaneValue('rotation', '10.00°', const Offset(1, 0)),
      '10.50°',
    );
  });
}
