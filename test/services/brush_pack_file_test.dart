import 'dart:convert';

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_group_id.dart';
import 'package:anicel/src/models/brush_preset.dart';
import 'package:anicel/src/models/brush_preset_id.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/services/brush_pack_file.dart';

/// 유저 확정 (`brush-export-format-Q1`, 답 1): Anicel's OWN brush format,
/// nothing lost — and 「불투명도든 뭐든 손설정이든 정한거 싹 다 내보낼때
/// 나르도록 하고싶음」.
void main() {
  BrushTipMask maskOf(String id) => BrushTipMask(
    id: id,
    size: 2,
    alpha: Uint8List.fromList(const [0, 90, 180, 255]),
  );

  BrushPreset presetOf(String id, {BrushGroupId? groupId}) => BrushPreset(
    id: BrushPresetId(id),
    name: 'Brush $id',
    groupId: groupId,
    settings: BrushSettings(
      size: 21,
      flow: 0.6,
      hardness: 0.4,
      tipMask: maskOf('tip-$id'),
      textureMaskSource: maskOf('paper-$id'),
      textureInvert: true,
      textureBrightness: -0.3,
      dualMask: maskOf('dual-$id'),
      dualDensity: 0.35,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.2),
    ),
  );

  test('🚨a pack round-trips EVERYTHING a preset carries', () {
    const group = BrushGroupId('watercolor');
    final pack = BrushPack(

      presets: [presetOf('a', groupId: group), presetOf('b')],
      handSettings: {
        // H25-again: whatever the hand set — a pressure curve, a flow — rides
        // beside the three values the bank started with.
        'a': {
          'size': 44.0,
          'opacity': 0.5,
          'blendMode': BrushBlendMode.multiply.name,
          'flow': 0.3,
          'sizePressureCurve': BrushPressureCurve.linearFrom(0.6).toJson(),
        },
      },
    );

    final back = decodeBrushPack(encodeBrushPack(pack));

    expect(back.presets, pack.presets);
    // ⛔No groups in the format — the file's NAME carries the group, because
    // the merge names the arriving group after the source file whatever the
    // pack says. See the class comment.
    expect(back.handSettings['a'], pack.handSettings['a']);
  });

  test('🚨the masks travel INLINE — a file has no tip library to resolve '
      'against', () {
    final back = decodeBrushPack(
      encodeBrushPack(BrushPack(presets: [presetOf('a')])),
    );

    final settings = back.presets.single.settings;
    expect(settings.tipMask?.alpha, [0, 90, 180, 255]);
    expect(settings.dualMask?.alpha, [0, 90, 180, 255]);
    expect(
      settings.textureMaskSource?.alpha,
      [0, 90, 180, 255],
      reason: 'the SOURCE travels, so the levels stay adjustable downstream',
    );
    expect(settings.textureInvert, isTrue);
  });

  test('a pack with no hand settings and no groups writes neither key', () {
    final json = encodeBrushPack(
      BrushPack(presets: [presetOf('a')]),
    );

    expect(json.contains('handSettings'), isFalse);
    expect(json.contains('"groups"'), isFalse);
    expect(decodeBrushPack(json).handSettings, isEmpty);
  });

  test('a version-1 pack still reads — its three hand values are an '
      'overlay already', () {
    final v1 = jsonEncode({
      'anicelBrushPack': 1,
      'presets': [presetOf('a').toJson()],
      'handSettings': {
        'a': {'size': 44.0, 'opacity': 0.5, 'blendMode': 'multiply'},
      },
    });

    expect(decodeBrushPack(v1).handSettings['a'], {
      'size': 44.0,
      'opacity': 0.5,
      'blendMode': 'multiply',
    });
  });

  group('what it refuses', () {
    test('a file that is not JSON at all', () {
      expect(
        () => decodeBrushPack('not json'),
        throwsA(isA<BrushPackFormatException>()),
      );
    });

    test('JSON that is not a pack', () {
      expect(
        () => decodeBrushPack('{"presets": []}'),
        throwsA(isA<BrushPackFormatException>()),
      );
    });

    test('🚨a pack from a NEWER Anicel, rather than dropping what it cannot '
        'read', () {
      final future = encodeBrushPack(
        BrushPack(presets: [presetOf('a')]),
      ).replaceFirst(
        '"anicelBrushPack":$brushPackVersion',
        '"anicelBrushPack":${brushPackVersion + 1}',
      );

      expect(
        () => decodeBrushPack(future),
        throwsA(
          isA<BrushPackFormatException>().having(
            (error) => error.message,
            'message',
            contains('newer version'),
          ),
        ),
      );
    });

    test('a pack with no brushes in it', () {
      expect(
        () => decodeBrushPack('{"anicelBrushPack":1,"presets":[]}'),
        throwsA(isA<BrushPackFormatException>()),
      );
    });

    test('a damaged preset, with one sentence rather than a type name', () {
      expect(
        () => decodeBrushPack('{"anicelBrushPack":1,"presets":[{"id":3}]}'),
        throwsA(
          isA<BrushPackFormatException>().having(
            (error) => error.message,
            'message',
            contains('damaged'),
          ),
        ),
      );
    });
  });
}
