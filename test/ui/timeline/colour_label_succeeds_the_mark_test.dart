import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/ui/theme/app_accents.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/theme/layer_mark_palette.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';

/// I-4 — 색 라벨이 `LayerMark` 를 **승계**했다는 것을 재는 계약.
///
/// 유저 2026-08-27: 「알아서 **통일/재사용** 같은거 유념하면서」 · 「사본 남으면
/// **진짜 용서안할게**」. 색 라벨은 옛 8색 태그 옆에 새로 생긴 것이 아니라 그
/// 자리를 **가져갔다** — 프레임 블록의 바탕을 칠하는 그 자리 그대로.
void main() {
  // 🚨A GLOBAL. Saving and restoring rather than assigning a fresh default
  // back: writing `const AppAccentSettings()` in the teardown would not undo
  // this file, it would overwrite whatever the suite had set up.
  late AppAccentSettings saved;
  setUp(() => saved = AppColors.accentSettings.value);
  tearDown(() => AppColors.accentSettings.value = saved);

  test('기본 팔레트는 원본 그대로다 — 유저: 「기본값은 원본그대로로 두고」', () {
    expect(const AppAccentSettings().layerMarkPalette, LayerMarkPalette.original);
  });

  test('스샷에서 뽑은 색이 그대로 나온다 — LO는 흰색, 원화는 초록, 미술은 파랑', () {
    AppColors.accentSettings.value = saved.copyWith(
      layerMarkPalette: LayerMarkPalette.original,
    );
    // ⚠️These are the user's own values, measured out of `board-shots/`.
    // A test that only said 「어떤 색이 나온다」 would have passed on the
    // palette I invented before opening those files.
    expect(
      layerMarkColor(const LayerMark(process: LayerProcess.layout)),
      const Color(0xFFFFFFFF),
      reason: '유저: 「LO는 흰색이야」',
    );
    expect(
      layerMarkColor(const LayerMark(process: LayerProcess.key)),
      const Color(0xFF80FF85),
      reason: '유저: 「원화는 초록색이었고」',
    );
    expect(
      layerMarkColor(const LayerMark(process: LayerProcess.art)),
      const Color(0xFF007FFF),
      reason: '유저: 「BG는 파랑색이었고」',
    );
  });

  test('수정 색은 공정과 무관하게 같다 — 「LO연출이던 원화연출이던 같은색」', () {
    for (final revise in LayerRevise.values) {
      final onLayout = layerMarkColor(
        LayerMark(process: LayerProcess.layout, revise: revise),
      );
      final onKey = layerMarkColor(
        LayerMark(process: LayerProcess.key, revise: revise),
      );
      expect(
        onKey,
        onLayout,
        reason: '${revise.displayName} — 공정이 색을 바꾸면 안 된다',
      );
    }
  });

  test('팔레트를 바꾸면 레이어를 하나도 안 건드리고 색이 전부 바뀐다', () {
    const mark = LayerMark(process: LayerProcess.key);
    final seen = <Color>{};
    for (final palette in LayerMarkPalette.values) {
      AppColors.accentSettings.value = saved.copyWith(
        layerMarkPalette: palette,
      );
      seen.add(layerMarkColor(mark));
    }
    expect(
      seen.length,
      LayerMarkPalette.values.length,
      reason: '네 톤이 서로 달라야 「보면서 고르는」 것이 가능하다',
    );
  });

  test('네 톤 전부, 모든 라벨이 블록 잉크가 읽히는 밝기다', () {
    // 유저: 「프레임이름/코마숫자/색라벨은 다 같은 색상의 바탕 위에 올라가는
    // 텍스트니까 **셋 다 같은 로직** 통일해서 사용하도록」 + 「그거 감안해서
    // **검정색이 되도록 유도하는 색**으로만 설계해보자」.
    //
    // 🚨So the palette is not free: every colour has to sit ABOVE the block
    // ink's crossover, or the plate would flip to white and that one chip
    // would be the exception the user asked not to have.
    for (final palette in LayerMarkPalette.values) {
      AppColors.accentSettings.value = saved.copyWith(
        layerMarkPalette: palette,
      );
      for (final mark in everyLayerMark()) {
        final fill = layerMarkColor(mark);
        expect(
          timelineGroundIsLight(fill),
          isTrue,
          reason:
              '${palette.displayName} · $mark = $fill '
              '(luminance ${fill.computeLuminance().toStringAsFixed(3)}) — '
              '0.179 아래로 내려가면 그 칩만 흰 글자가 된다',
        );
      }
    }
  });

  test('용지는 수정이 없고, 콘티는 감독·총감독 둘뿐이다', () {
    expect(
      revisesFor(LayerProcess.paper),
      isEmpty,
      reason: '유저 정정: 「용지는 수정공정 존재 안하도록」',
    );
    expect(revisesFor(LayerProcess.conte), [
      LayerRevise.director,
      LayerRevise.chiefDirector,
    ]);
  });

  test('동화와 시아게는 여섯에 자기 검사를 하나씩 더 갖는다', () {
    expect(
      revisesFor(LayerProcess.inbetween).last,
      LayerRevise.inbetweenCheck,
    );
    expect(revisesFor(LayerProcess.finish).last, LayerRevise.cellCheck);
    expect(
      revisesFor(LayerProcess.inbetween).length,
      revisesFor(LayerProcess.layout).length + 1,
      reason: '레이아웃의 여섯을 그대로 쓰고 검사 하나가 얹힌다',
    );
  });

  test('수정 목록은 한 벌이고 공정이 참조한다 — 사본이 아니다', () {
    // ⛔The point of the reference: every revise a stage offers is one of THE
    // set, so renaming one renames it everywhere. A per-stage copy would let
    // 원화's 작화감독 drift from 레이아웃's.
    for (final process in LayerProcess.values) {
      for (final revise in revisesFor(process)) {
        expect(
          LayerRevise.values,
          contains(revise),
          reason: '${process.displayName} 이 자기만의 수정을 만들면 안 된다',
        );
      }
    }
  });

  test('라벨이 없으면 블록 바탕은 예전 그대로다', () {
    expect(
      layerMarkColor(LayerMark.none),
      timelineDrawingHeldColor,
      reason: '「none IS the paper」 — 라벨 안 붙은 행은 칠이 안 바뀐다',
    );
  });
}
