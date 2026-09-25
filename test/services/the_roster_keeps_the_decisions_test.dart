// THE ROSTER'S DECISIONS, PINNED — the ones a later round would undo by
// accident rather than on purpose.
//
// ⚠️This does NOT pin counts. "41 presets" is a number that should be free to
// move; what must not move is the SHAPE the user decided (2026-09-09): no
// eraser group, no pixel group, paint split by medium, and no two brushes
// that the picker cannot tell apart.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/services/brush_preset_defaults.dart';
import 'package:anicel/src/services/brush_tip_defaults.dart';

void main() {
  test('⛔no eraser group, and no preset smuggling one in', () {
    // 유저 2026-09-09: 「지우개그룹은 만들 이유를 못느끼겠고. 왜냐하면 툴이
    // 있으니까」 — the eraser is a TOOL. A group would duplicate it, and so
    // would a preset that pins the erase blend, which is why both are checked.
    expect(
      defaultBrushGroups.map((group) => group.name.toLowerCase()),
      isNot(contains('eraser')),
    );
    for (final preset in defaultBrushPresets) {
      expect(
        preset.settings.blendMode,
        isNot(BrushBlendMode.erase),
        reason: '${preset.name} would be the banned group in disguise',
      );
    }
  });

  test('⛔no pixel group — the pixel brush is an AA setting', () {
    // 유저 2026-09-09: 「픽셀브러시도 그냥 G펜 우리가 만들어서 넣고 aa off면
    // 픽셀대로 나오게 클튜처럼 하면되는거고」.
    expect(
      defaultBrushGroups.map((group) => group.name.toLowerCase()),
      isNot(contains('pixel')),
    );
    final animePen = defaultBrushPresets.firstWhere(
      (preset) => preset.name == 'Anime Pen',
    );
    expect(animePen.settings.antiAlias.name, 'none');
    // 🚨And the hardness that makes the AA setting mean anything: at 1.0 the
    // coverage is already binary, so `none` would be a field set to no effect.
    expect(animePen.settings.hardness, lessThan(1.0));
    // ⛔A masked tip would be binarized whole by the same threshold.
    expect(animePen.settings.tipMask, isNull);
  });

  test('paint is split by medium, and every group has members', () {
    // 유저 2026-09-09: 「페인트는 그룹 더 나눠서 수채화나 오일이나 이런거」.
    final names = defaultBrushGroups.map((group) => group.name).toList();
    expect(names, containsAll(<String>['Watercolor', 'Oil']));
    expect(names, isNot(contains('Paint')));
    // 유저 2026-09-09: 「이름 펜이 맞지않을까」 — the group of pens is named
    // for the tool, like every other group here.
    expect(names, contains('Pen'));
    expect(names, isNot(contains('Ink')));

    for (final group in defaultBrushGroups) {
      expect(
        defaultBrushPresets.where((preset) => preset.groupId == group.id),
        isNotEmpty,
        reason: '${group.name} would render as an empty tab',
      );
    }
    // Nothing is left at the root: a built-in with no group is invisible in
    // the tabbed picker.
    for (final preset in defaultBrushPresets) {
      expect(preset.groupId, isNotNull, reason: preset.name);
    }
  });

  test('🔑no two presets differ ONLY by what the picker cannot draw', () {
    // The preview normalizes SIZE to the row, skips scatter and every jitter,
    // and bakes alpha only — so size, scatter, jitter, blend and the whole
    // colour-mixing block are invisible in the list. Two rows that share
    // everything else are one brush wearing two names, which is what
    // 「최대한 안겹치도록… 에어브러시 같은게 두개 안생기도록」 forbids.
    String visibleKey(BrushSettings s) => [
      s.tipMask?.id ?? '-',
      s.dualMask?.id ?? '-',
      s.dualMaskScale,
      s.textureMask?.id ?? '-',
      s.textureScale,
      s.textureDensity,
      s.roundness,
      s.angleDegrees,
      s.hardness,
      s.spacing,
      s.rotationMode.name,
      s.antiAlias.name,
      // The curve SHAPES, which the preview's synthetic stroke draws.
      s.sizePressureCurve?.points.toString() ?? '-',
      s.opacityPressureCurve?.points.toString() ?? '-',
      s.flowPressureCurve?.points.toString() ?? '-',
      s.hardnessPressureCurve?.points.toString() ?? '-',
    ].join('|');

    final seen = <String, String>{};
    for (final preset in defaultBrushPresets) {
      final key = visibleKey(preset.settings);
      final twin = seen[key];
      expect(
        twin,
        isNull,
        reason:
            '"${preset.name}" and "$twin" draw the same row — they differ '
            'only in fields the picker cannot show',
      );
      seen[key] = preset.name;
    }
  });

  test('🚨every tip a preset names also SHIPS in the tip library', () {
    // A saved library stores a tip by ID and `loadOrDefaults` resolves it
    // back through `defaultBrushTipEntries`. So a mask that ships on a preset
    // but not as a library entry survives only until the first save: after
    // that the brush silently falls back to its round tip, and the only way
    // to notice is to save, reload and see a brush change shape.
    //
    // 🚨Wet Blot shipped exactly that way and nobody saw it (found 2026-09-10,
    // by a preset test that reloaded the roster's LAST entry). This pins the
    // invariant so the next tip cannot repeat it.
    final library = defaultBrushTipEntries.map((entry) => entry.id).toSet();
    for (final preset in defaultBrushPresets) {
      final settings = preset.settings;
      for (final mask in <BrushTipMask?>[
        settings.tipMask,
        settings.dualMask,
        settings.textureMaskSource,
      ]) {
        if (mask == null) {
          continue;
        }
        expect(
          library,
          contains(mask.id),
          reason:
              '"${preset.name}" draws with ${mask.id}, which the tip library '
              'cannot hand back after a save',
        );
      }
    }
  });

  test('every preset id and name is unique', () {
    expect(
      defaultBrushPresets.map((preset) => preset.id).toSet(),
      hasLength(defaultBrushPresets.length),
    );
    expect(
      defaultBrushPresets.map((preset) => preset.name).toSet(),
      hasLength(defaultBrushPresets.length),
    );
    expect(
      defaultBrushGroups.map((group) => group.id).toSet(),
      hasLength(defaultBrushGroups.length),
    );
  });

  test('a general brush lays its dabs at the finest spacing — only a brush '
      'whose look IS the gap keeps one of its own', () {
    // 유저 2026-09-24: 「지금 프리셋 브러시들 간격이 너무 멀어서 일반적인
    // 설정으론 최소치로 두자. 간격이 필요한 특수한거만 둬도되고」.
    // Measured 2026-09-24 on the sample stroke at an 87 px tip: at 1% a grain
    // or bristle tip's texture fell to 16–51% of what it had.
    const grain = 'its grain is the gap between stamps';
    const ownGap = <String, String>{
      'builtin-chalk-preset': grain,
      'builtin-rough-pencil': grain,
      'builtin-dark-pencil': grain,
      'builtin-colored-pencil': grain,
      'builtin-dry-ink': grain,
      'builtin-pastel': grain,
      'builtin-crayon': grain,
      'builtin-graphite-stick': grain,
      'builtin-wet-watercolor': grain,
      'builtin-flat-bristle': grain,
      'builtin-palette-knife': grain,
      'builtin-grit-spray': grain,
      'builtin-blending-stump': grain,
      'builtin-hatching': grain,
      'builtin-rough-edge': grain,
      'builtin-concrete': grain,
      'builtin-blender': 'a blender picks colour up once per dab',
      'builtin-water-blend': 'a blender picks colour up once per dab',
      'builtin-charcoal': 'its spacing jitter needs a gap to scatter',
      'builtin-dry-brush': 'its spacing jitter needs a gap to scatter',
      'builtin-splatter-preset': 'a decoration: separate marks',
      'builtin-stipple': 'a decoration: separate dots',
      'builtin-sponge': 'a decoration: separate dabs of sponge',
      'builtin-cloud': 'a decoration: separate puffs',
      'builtin-grass': 'a decoration: separate blades',
      'builtin-sparkle': 'a decoration: separate sparkles',
      'builtin-snow': 'a decoration: separate flakes',
      'builtin-bubble': 'a decoration: separate bubbles',
      'builtin-leaves': 'a decoration: separate leaves',
    };
    for (final preset in defaultBrushPresets) {
      final why = ownGap[preset.id.value];
      if (why == null) {
        expect(
          preset.settings.spacing,
          BrushShape.minSpacing,
          reason: '${preset.name} is a general brush',
        );
      } else {
        expect(
          preset.settings.spacing,
          greaterThan(BrushShape.minSpacing),
          reason: '${preset.name} keeps its gap — $why',
        );
      }
    }
  });
}
