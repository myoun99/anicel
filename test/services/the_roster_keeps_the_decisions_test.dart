// THE ROSTER'S DECISIONS, PINNED — the ones a later round would undo by
// accident rather than on purpose.
//
// ⚠️This does NOT pin counts. "41 presets" is a number that should be free to
// move; what must not move is the SHAPE the user decided (2026-09-09): no
// eraser group, no pixel group, paint split by medium, and no two brushes
// that the picker cannot tell apart.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_anti_alias.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_input_source.dart';
import 'package:anicel/src/models/brush_preset.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/brush_texture_mode.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_order.dart';
import 'package:anicel/src/models/brush_tip_rotation_mode.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_dab_coverage.dart';
import 'package:anicel/src/services/brush_preset_defaults.dart';
import 'package:anicel/src/services/brush_tip_defaults.dart';
import 'package:anicel/src/services/brush_tip_mask_defaults.dart';

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
    // ↩️Nor, for a while, a preset at no anti-alias (board F-218, 유저
    // 2026-09-28: 「이상한것들 쳐내고. 애니펜 이런거」 — Anime Pen was that
    // row). Lifted by F-433-Q1 (유저 2026-10-21: 「aa없는 프리셋을 금지한다고
    // 내가 발언했다면 지금 철회함. 브러시 개성에 맞춰서 없거나 1단계거나
    // 다르게 하는거 가능. 중요한건 개성」): the sharp ships at none.
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
          reason: 'a softer lead reaches deeper into the paper',
        );
        expect(
          softer.hardness,
          lessThan(harder.hardness),
          reason: 'a softer lead has the softer edge',
        );
      }
    });

    test('🚨the pencil laid on its side takes its tone from the pressure '
        'alone, and cuts as hard lying down as upright (F-433)', () {
      // 「각도에 따라 눕히는 연필 … 아날로그에서. 그런거 그대로 재현한 연필」.
      // ↩️It paled and softened as it lay down; 유저 F-433: 「불투명도
      // 제한같은거? 기울기 이런거 걸어놧는데, 없애고 똑같이 불투명도 필압으로」
      // and 「진짜 연필처럼 딱딱한느낌? 실루엣」.
      final tilted = byId('builtin-shading-pencil').settings;
      final curves = tilted.shape.curves;
      for (final target in [
        BrushPressureTarget.opacity,
        BrushPressureTarget.flow,
        BrushPressureTarget.hardness,
      ]) {
        expect(
          curves[(target, BrushInputSource.tilt)],
          isNull,
          reason: 'no tilt row on its ${target.name}',
        );
      }
      final opacity =
          curves[(BrushPressureTarget.opacity, BrushInputSource.pressure)]!;
      expect(opacity.evaluate(1.0), greaterThan(opacity.evaluate(0.2)));
      expect(tilted.hardness, 1.0);
    });

    test('🚨and its mark follows the pen: the point upright, a strip four '
        'times as long as it is wide lying down', () {
      // F-176-Q4 (유저 2026-10-18): 「세워서그리면 얇은선, 눕혀서 그리면
      // 연필처럼 dab이 길어지는? … 펜 실제 각도에 따라 dab 각도 바뀌는건가
      // 했는데 그거조차도아님. 가능하도록」. ↩️F-433 (유저 2026-10-21):
      // 「최대한 세우면 최대한 dab이 얇은 … 세웠을때 얇은게 안되있음」 — upright
      // was the brush's whole size.
      final tilted = byId('builtin-shading-pencil').settings;
      expect(tilted.rotationMode, BrushTipRotationMode.penTilt);
      final curves = tilted.shape.curves;
      final size = curves[(BrushPressureTarget.size, BrushInputSource.tilt)]!;
      final roundness =
          curves[(BrushPressureTarget.roundness, BrushInputSource.tilt)]!;
      // Upright: the point of the lead, the thinnest it draws.
      expect(size.evaluate(0.0), lessThan(0.1));
      for (final lean in [0.2, 0.4, 0.65, 1.0]) {
        expect(size.evaluate(lean), greaterThan(size.evaluate(0.0)));
      }
      expect(roundness.evaluate(0.0), closeTo(1.0, 1e-12));
      // Laid as flat as a Wacom pen reports (lean ⅔): its whole size, as
      // long as it is wide four times over.
      expect(size.evaluate(0.65), closeTo(1.0, 1e-12));
      expect(1.0 / roundness.evaluate(0.65), closeTo(4.0, 1e-9));
    });

    test('🗣️no pencil but the tilted one answers the pen\'s lean (F-462 ②)',
        () {
      // 유저 2026-10-25: 「일반연필 기울기에따라 뭐 바뀐다거나 다 잊고,
      // 눕히는연필만 지금 방향성대로 기울기에따라 팁 바뀌는느낌은 좋음」.
      // ↩️F-433 had them lean a little: 「일반 연필에도 어느정도 기울기로 형태
      // 바뀌는거 넣고」.
      for (final id in [
        'builtin-hard-pencil',
        'builtin-pencil',
        'builtin-soft-pencil',
        'builtin-dark-pencil',
        'builtin-colored-pencil',
      ]) {
        final settings = byId(id).settings;
        expect(
          [
            for (final (target, source) in settings.shape.curves.keys)
              if (source == BrushInputSource.tilt) target,
          ],
          isEmpty,
          reason: '$id has a tilt row',
        );
        expect(settings.rotationMode, isNot(BrushTipRotationMode.penTilt));
        expect(settings.tipOrder, isNot(BrushTipOrder.lean), reason: id);
      }
    });

    test('🗣️the grades throw a crumb of lead at random, turned all the way, '
        'on a paper reached deeper the harder they press (F-462 ②)', () {
      // 유저 2026-10-25: 「클튜 연필브러시들은 육각형식으로 안하니까 그거
      // 참고해서 다시 개편. 육각형같은거 잊어도됨」 · 「클튜브러시 그대로
      // 참고하되 따라한 느낌만 안나도록 참고해서 우리방식대로 재구현」.
      for (final id in [
        'builtin-hard-pencil',
        'builtin-pencil',
        'builtin-soft-pencil',
        'builtin-dark-pencil',
      ]) {
        final settings = byId(id).settings;
        expect(settings.tips, pencilCrumbBrushTipMasks, reason: id);
        expect(settings.tipOrder, BrushTipOrder.random, reason: id);
        expect(settings.angleJitter, 1.0, reason: id);
        expect(
          settings.textureMaskSource?.id,
          'builtin-graphite-tooth',
          reason: id,
        );
        // ↩️F-456 multiplied it: a lead only paled and laid smooth.
        expect(settings.textureMode, BrushTextureMode.height, reason: id);
        final reach = settings.shape.curves[(
          BrushPressureTarget.textureDensity,
          BrushInputSource.pressure,
        )]!;
        expect(reach.evaluate(0.0), lessThan(0.75), reason: '$id touched');
        expect(reach.evaluate(1.0), 1.0, reason: '$id pressed');
      }
      // Wax spreads over the tooth where graphite catches its peaks: the
      // colored pencil throws the crumbs on a multiplied paper.
      final colored = byId('builtin-colored-pencil').settings;
      expect(colored.tips, pencilCrumbBrushTipMasks);
      expect(colored.tipOrder, BrushTipOrder.random);
      expect(colored.textureMode, BrushTextureMode.multiply);
    });

    test('🚨the tilted pencil wears the lead upright to flat, three faces a '
        'step thrown per dab, on a tooth that multiplies — paler the lighter '
        'it presses (F-451, F-456)', () {
      // 유저: 「팁 사각형인채로 질감만 얼버무려서 연필느낌내는건 너무
      // 구현도가 낮음」 (F-451) · 「결여가 너무 일정함(같은부분 다시 그려도
      // 결여된 픽셀이 안채워짐)」 · Q4 「기울기가 단계를 고르고, 그 단계
      // 안에서 여러 장 중 무작위」 (F-456). ↩️Every graphite pencil wore it
      // until F-462 ②: 「눕히는연필만 지금 방향성대로」.
      for (final id in ['builtin-shading-pencil']) {
        final settings = byId(id).settings;
        expect(settings.tips, pencilLeadBrushTipMasks, reason: id);
        expect(settings.tipOrder, BrushTipOrder.lean, reason: id);
        expect(settings.tipsPerTurn, pencilLeadFacesPerStep, reason: id);
        expect(
          settings.textureMaskSource?.id,
          'builtin-graphite-tooth',
          reason: id,
        );
        // ⛔Not the height's cut: it left the same valleys bare however
        // often a line was laid again.
        expect(settings.textureMode, BrushTextureMode.multiply, reason: id);
        final tooth = settings.shape.curves[(
          BrushPressureTarget.textureDensity,
          BrushInputSource.pressure,
        )]!;
        expect(tooth.evaluate(0.0), 1.0, reason: '$id touched: all paper');
        expect(tooth.evaluate(1.0), lessThan(0.8), reason: '$id pressed');
      }
    });

    test('🚨the sharp is the user\'s own, as they exported it (F-433)', () {
      // 유저: 「프리셋 기본 샤프 연필, 내가 만든 샤프로 교체」.
      final sharp = byId('builtin-mechanical-pencil').settings;
      expect(sharp.size, 1.5);
      expect(sharp.spacing, 0.0207);
      expect(sharp.textureMaskSource?.id, 'builtin-canvas-weave');
      expect(sharp.textureDensity, 1.0);
      // Its no anti-alias too; its 뒤에 blend was a slip (F-433-Q1: 「뒤에는
      // 내가 잘못 지정한채로 내보낸거임. 블렌드는 표준. 기본aa는 없음」).
      expect(sharp.antiAlias, BrushAntiAlias.none);
      expect(sharp.blendMode, BrushBlendMode.color);
    });

    test('⛔the colouring pencil ships no other program\'s tip (F-433)', () {
      // The user's own wore a tip taken from another program's brush; a
      // third party's brush may not ship (`ip-review-clean`).
      final coloring = byId('builtin-coloring-pencil').settings;
      expect(coloring.tipMask?.id, 'builtin-color-clumps');
      expect(coloring.angleJitter, 1.0);
      expect(coloring.size, 454);
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

    test('🚨the gouache is a dry brush: the paper\'s height, reached '
        'deeper the harder it presses', () {
      // the-gouache-is-a-round-with-a-weave (유저 2026-10-23: 「뭐가
      // 과슈인지?」), Q2 answered a (10-24): pressed lightly only the paper's
      // peaks take paint, pressed hard it covers flat.
      final gouache = byId('builtin-gouache').settings;
      expect(gouache.textureMaskSource?.id, 'builtin-paper-grain');
      expect(gouache.textureMode, BrushTextureMode.height);
      expect(gouache.hardness, 0.85);
      final depth = gouache.shape.curves[(
        BrushPressureTarget.textureDensity,
        BrushInputSource.pressure,
      )]!;
      expect(depth.evaluate(0.0), closeTo(0.2, 1e-12), reason: 'touched');
      expect(depth.evaluate(1.0), closeTo(1.0, 1e-12), reason: 'pressed');
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
      // The curves — shape, floor and ceiling — which the preview's
      // synthetic stroke draws. ↩️The shapes alone, while a floor still lived
      // in the points; F-176-Q2 moved it out to Clip Studio's 最小値.
      s.sizePressureCurve?.toString() ?? '-',
      s.opacityPressureCurve?.toString() ?? '-',
      s.flowPressureCurve?.toString() ?? '-',
      s.hardnessPressureCurve?.toString() ?? '-',
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
      // ↩️Board F-218 put the graphite grades and the tilted pencil on the
      // grain tip; F-433 moved their grain to the paper, so they lay at the
      // finest step again. The two pencils the user made keep theirs.
      'builtin-mechanical-pencil': 'the user\'s own sharp, at its own step',
      'builtin-coloring-pencil':
          'the user\'s own colouring pencil, at its own step',
      'builtin-dry-ink': grain,
      'builtin-pastel': grain,
      'builtin-crayon': grain,
      'builtin-graphite-stick': grain,
      'builtin-wet-watercolor': grain,
      'builtin-flat-bristle': grain,
      'builtin-palette-knife': grain,
      'builtin-grit-spray': grain,
      'builtin-blending-stump': grain,
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

  /// One dab of [settings] on a sideways sweep — one heading at 0°, so the
  /// tip turns by its own angle.
  BrushDab sidewaysDabOf(BrushSettings settings) => BrushDab(
    center: CanvasPoint(x: 64, y: 64),
    color: 0xFF000000,
    size: settings.size,
    opacity: 1,
    flow: 1,
    hardness: settings.hardness,
    pressure: 1,
    sequence: 0,
    roundness: settings.roundness,
    angleDegrees: settings.angleDegrees,
    tipMask: settings.tipMask,
  );

  /// How wide and tall one [sidewaysDabOf] [settings] stands.
  ({int wide, int tall}) standsOnASidewaysSweep(BrushSettings settings) {
    var (left, right, top, bottom) = (1 << 30, -1, 1 << 30, -1);
    forEachBrushPixelCoverage(sidewaysDabOf(settings), (x, y, coverage, _) {
      if (coverage > 0.5) {
        (left, right) = (math.min(left, x), math.max(right, x));
        (top, bottom) = (math.min(top, y), math.max(bottom, y));
      }
    });
    return (wide: right - left + 1, tall: bottom - top + 1);
  }

  BrushSettings settingsOf(String id) => defaultBrushPresets
      .firstWhere((preset) => preset.id.value == id)
      .settings;

  test('🚨a grass tuft stands up on a sideways sweep and fans out', () {
    // Its own comment's law ("Tufts stand UP"). ↩️It landed round dots:
    // a roundness that squeezed the leaf along its length (10-24).
    final grass = settingsOf('builtin-grass');
    final (:wide, :tall) = standsOnASidewaysSweep(grass);
    expect(tall, greaterThan(wide), reason: '$wide wide, $tall tall');
    // F-462 ③ (유저 2026-10-25): 「팁이 너무 일직선 … 한 소재끼리 다른곳
    // 바라보고 다른 위치에 있어야」 — the blades lean their own ways, so the
    // tuft spreads across most of its height; and they rise from one foot,
    // so it weighs below its middle. ↩️A leaf's lens stood one narrow
    // column, as heavy above as below.
    expect(wide, greaterThan(tall * 0.6), reason: '$wide wide, $tall tall');
    var (above, below) = (0, 0);
    forEachBrushPixelCoverage(sidewaysDabOf(grass), (x, y, coverage, _) {
      if (coverage <= 0.5) return;
      if (y < 64) above += 1;
      if (y > 64) below += 1;
    });
    // Measured 2026-10-29: the tuft 24 wide, 27 tall, 15 above and 131
    // below; the leaf it replaced 8 wide, 20 tall, 54 above and 46 below.
    expect(below, greaterThan(above * 3), reason: '$above above, $below below');
  });

  // F-462 (유저 2026-10-25): 「우선 텍스처의 해칭 삭제. 거친 가장자리는
  // 연필로서 연필그룹에 등록」.
  test('🗣️the hatching is gone, and the rough edge draws as a pencil', () {
    expect(
      defaultBrushPresets.map((preset) => preset.id.value),
      isNot(contains('builtin-hatching')),
    );
    final rough = defaultBrushPresets.singleWhere(
      (preset) => preset.id.value == 'builtin-rough-edge',
    );
    expect(rough.groupId?.value, 'builtin-pencil-group');
    expect(rough.name, 'Rough Pencil');
  });

  // the-gouache-is-a-round-with-a-weave Q5–Q6 (유저 2026-10-24), each the
  // option the user picked off its comparison picture. ↩️Q4's brush, the
  // hatching, went with F-462.
  test('🗣️the marker multiplies, through a chisel nib at 45° (Q5)', () {
    final marker = settingsOf('builtin-marker');
    expect(marker.blendMode, BrushBlendMode.multiply);
    expect(marker.roundness, 0.45);
    expect(marker.angleDegrees, 45);
    expect(marker.rotationMode, BrushTipRotationMode.fixed);
  });

  test('🗣️the flat wash lays its wide band on a sideways sweep (Q6)', () {
    final wash = settingsOf('builtin-flat-wash');
    expect(wash.rotationMode, BrushTipRotationMode.fixed);
    // A sideways sweep paints as tall a band as one dab stands.
    final (:wide, :tall) = standsOnASidewaysSweep(wash);
    expect(tall, greaterThan(wide * 3), reason: '$wide wide, $tall tall');
  });
}
