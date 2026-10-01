// THE ROSTER'S DECISIONS, PINNED — the ones a later round would undo by
// accident rather than on purpose.
//
// ⚠️This does NOT pin counts. "41 presets" is a number that should be free to
// move; what must not move is the SHAPE the user decided (2026-09-09): no
// eraser group, no pixel group, paint split by medium, and no two brushes
// that the picker cannot tell apart.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_anti_alias.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_input_source.dart';
import 'package:anicel/src/models/brush_preset.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
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
    // ↩️Nor a pixel ROW (board F-218, 유저 2026-09-28: 「이상한것들 쳐내고.
    // 애니펜 이런거」): Anime Pen was that row, and a pixel line is the 없음
    // step any brush can take.
    for (final preset in defaultBrushPresets) {
      expect(
        preset.settings.antiAlias,
        isNot(BrushAntiAlias.none),
        reason: '${preset.name} would be the pixel pen again',
      );
    }
  });

  // Board F-218 (유저 2026-09-28, answered 2026-10-01 「개편안 승인. 너가
  // 제안한 그대로」): the roster the user approved on its review page.
  group('the F-218 roster', () {
    BrushPreset byId(String id) =>
        defaultBrushPresets.firstWhere((preset) => preset.id.value == id);

    test('Basic opens the list with the two rounds, under their old ids', () {
      // 「포토샵보면 둥근라운드 딱딱한라운드 뭐 이런 진짜 기본적인 브러시가
      // 제대로 있는데 여긴 이상함」.
      expect(defaultBrushGroups.first.id.value, 'builtin-basic-group');
      final basic = [
        for (final preset in defaultBrushPresets)
          if (preset.groupId == defaultBrushGroups.first.id) preset.name,
      ];
      expect(basic, ['Hard Round', 'Soft Round']);
      expect(byId('builtin-ink-pen').name, 'Hard Round');
      expect(byId('builtin-ink-pen').settings.hardness, 1.0);
      expect(byId('builtin-soft-brush').name, 'Soft Round');
      expect(byId('builtin-soft-brush').settings.hardness, 0.0);
    });

    test('every graphite pencil has graphite in it, and the grades step the '
        'way the leads do', () {
      // 「연필은 싹 다 비슷비슷한 브러시라 차이를 못느끼겠음 … 현실기반?」 —
      // three pencils were plain round tips, a thin pen each.
      for (final id in [
        'builtin-hard-pencil',
        'builtin-pencil',
        'builtin-soft-pencil',
        'builtin-dark-pencil',
        'builtin-mechanical-pencil',
        'builtin-shading-pencil',
      ]) {
        final settings = byId(id).settings;
        expect(
          settings.tipMask != null || settings.textureMaskSource != null,
          isTrue,
          reason: '${byId(id).name} would be a pen again',
        );
      }
      const gradeIds = [
        'builtin-hard-pencil',
        'builtin-pencil',
        'builtin-soft-pencil',
        'builtin-dark-pencil',
      ];
      expect(
        [for (final id in gradeIds) byId(id).name],
        ['2H Pencil', 'HB Pencil', '2B Pencil', '4B Pencil'],
      );
      final grades = [for (final id in gradeIds) byId(id).settings];
      for (var i = 1; i < grades.length; i += 1) {
        final softer = grades[i];
        final harder = grades[i - 1];
        expect(
          softer.flow * softer.opacity,
          greaterThan(harder.flow * harder.opacity),
          reason: 'a softer lead lays darker',
        );
        expect(
          softer.textureDensity,
          greaterThan(harder.textureDensity),
          reason: 'a softer lead grains coarser',
        );
        expect(
          softer.hardness,
          lessThan(harder.hardness),
          reason: 'a softer lead has the softer edge',
        );
      }
    });

    test('the pencil laid on its side spreads wide, pale and soft', () {
      // 「각도에 따라 눕히는 연필 … 아날로그에서. 그런거 그대로 재현한 연필」.
      final tilted = byId('builtin-shading-pencil').settings;
      final curves = tilted.shape.curves;
      expect(
        curves[(BrushPressureTarget.size, BrushInputSource.tilt)],
        isNotNull,
      );
      final opacity =
          curves[(BrushPressureTarget.opacity, BrushInputSource.tilt)]!;
      expect(opacity.evaluate(1.0), lessThan(opacity.evaluate(0.0)));
      final hardness =
          curves[(BrushPressureTarget.hardness, BrushInputSource.tilt)]!;
      expect(hardness.evaluate(1.0), lessThan(hardness.evaluate(0.0)));
    });

    test('one watercolour carries paper, and it is cold-press', () {
      // 「질감 있다면 그냥 수채가아니라 아날로그 수채라던가 … 진짜 아날로그
      // 질감 종이질감」.
      final watercolors = [
        for (final preset in defaultBrushPresets)
          if (preset.groupId?.value == 'builtin-watercolor-group') preset,
      ];
      final papered = [
        for (final preset in watercolors)
          if (preset.settings.textureMaskSource != null) preset,
      ];
      expect(papered.map((preset) => preset.name), ['Analog Watercolor']);
      expect(
        papered.single.settings.textureMaskSource!.id,
        'builtin-cold-press',
      );
    });

    test('the five that drew another brush\'s row are gone', () {
      for (final id in [
        'builtin-rough-pencil',
        'builtin-anime-pen',
        'builtin-rough-ink',
        'builtin-round-bristle',
        'builtin-spray',
      ]) {
        expect(
          defaultBrushPresets.where((preset) => preset.id.value == id),
          isEmpty,
          reason: id,
        );
      }
    });
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
      // Board F-218: the graphite grades and the tilted pencil wear the grain
      // tip now.
      'builtin-hard-pencil': grain,
      'builtin-pencil': grain,
      'builtin-soft-pencil': grain,
      'builtin-shading-pencil': grain,
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
