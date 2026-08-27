import 'dart:io';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_id.dart';
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
  _takeLabel();
  _oneWidgetBothSurfaces();
  _axisAgreement();
  _namesFollowTheLanguage();

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

/// I-5 — 테이크 라벨. 유저 2026-08-27: 「작업하다보면 리테이크가 존재한단말이지?
/// 그때 원화작업자가 레이아웃 그리고 리테이크 발생하면 **똑같은 색 라벨만으로는
/// 테이크1인지 2인지 구분 안되잖아**」.
void _takeLabel() {
  test('테이크는 마크 안에 산다 — 두 번째 필드도, 두 번째 명령도 아니다', () {
    const mark = LayerMark(process: LayerProcess.layout);
    final withTake = mark.withTake(2);

    expect(withTake.process, LayerProcess.layout, reason: '공정은 그대로');
    expect(withTake.take, 2);
    expect(withTake.takeText, 'T2', reason: '라벨에는 줄여서 T2');
    // ⛔A `Layer.take` beside `Layer.mark` would have needed its own
    // command, its own link-group mirror and its own JSON site.
    expect(
      mark.take,
      LayerMark.firstTake,
      reason: '원본은 안 바뀐다 — withTake 는 새 값을 만든다',
    );
  });

  test('기본은 T1 이다 — 유저: 「테이크는 기본값 T1」', () {
    expect(const LayerMark(process: LayerProcess.key).take, 1);
    expect(const LayerMark(process: LayerProcess.key).takeText, 'T1');
    expect(LayerMark.none.take, 1, reason: '라벨 없는 행도 1판이다');
  });

  test('테이크만 있고 공정이 없어도 살아남는다', () {
    // 「없음」 상태에서도 판 번호는 매길 수 있다. isNone 은 공정을 묻는 것이라
    // 여기서 true 이고, 그래도 JSON 은 테이크를 실어야 한다.
    final takeOnly = LayerMark.none.withTake(3);
    expect(takeOnly.isNone, isTrue);
    expect(LayerMark.fromJson(takeOnly.toJson()).take, 3);
  });

  test('1–9 밖의 저장값은 버린다 — 팝오버가 못 지우는 칩이 생기면 안 된다', () {
    for (final bad in <Object>[0, 10, -1, 'two']) {
      expect(
        LayerMark.fromJson({'process': 'layout', 'take': bad}).take,
        LayerMark.firstTake,
        reason: '저장된 take=$bad',
      );
    }
    expect(LayerMark.takeChoices, [1, 2, 3, 4, 5, 6, 7, 8, 9]);
  });

  test('테이크가 라벨의 정체성에 들어간다 — 같은 공정이라도 판이 다르면 다르다', () {
    const one = LayerMark(process: LayerProcess.layout, take: 1);
    const two = LayerMark(process: LayerProcess.layout, take: 2);
    expect(one == two, isFalse, reason: '이게 안 되면 리테이크가 구분이 안 된다');
    expect(one.hashCode == two.hashCode, isFalse);
  });

  test('마크와 테이크가 나란히 한 슬롯을 예약한다 — 없어도 자리는 그대로', () {
    // ⛔없다가 생기는 UI 금지: 테이크가 붙을 때 이름이 밀리면 안 된다.
    expect(layerLabelSlotWidth, layerMarkSlotWidth + layerTakeSlotWidth);
    expect(
      layerTakeSlotWidth,
      layerMarkSlotWidth,
      reason: '유저: 「색 라벨이랑 같은 디자인으로」',
    );
  });
}

/// 🚨두 플레이트는 **레일의 축을 따라** 놓인다.
///
/// x시트는 레일을 세워 두므로 그 열 머리는 아래로 흐른다. 가로로 놓았더니
/// 두 플레이트가 머리의 폭 밖으로 나가 **x시트 테스트 100건 이상이 무너졌다**
/// (08-27 실측). 슬롯 폭도 같은 축으로 재므로 둘이 반드시 일치해야 한다.
void _axisAgreement() {
  testWidgets('가로 레일에서는 나란히, 세로(x시트) 레일에서는 위아래로', (tester) async {
    for (final axis in Axis.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: axis == Axis.horizontal ? layerLabelSlotWidth : 28,
                height: axis == Axis.horizontal ? 28 : layerLabelSlotWidth,
                child: LayerMarkChip(
                  keyPrefix: 'probe',
                  layerId: const LayerId('a'),
                  mark: const LayerMark(process: LayerProcess.layout),
                  onMarkSelected: (_, _) {},
                  axis: axis,
                ),
              ),
            ),
          ),
        ),
      );

      final mark = tester.getRect(
        find.byKey(const ValueKey<String>('probe-layer-mark-a')),
      );
      final take = tester.getRect(
        find.byKey(const ValueKey<String>('probe-layer-take-a')),
      );
      if (axis == Axis.horizontal) {
        expect(
          take.left,
          closeTo(mark.right, 0.5),
          reason: '가로 레일 — 테이크가 색 라벨 오른쪽',
        );
      } else {
        expect(
          take.top,
          closeTo(mark.bottom, 0.5),
          reason: '🚨세로 레일 — 테이크가 색 라벨 아래. 가로로 놓으면 열 머리 '
              '폭 밖으로 나가 x시트가 통째로 무너진다',
        );
      }
    }
  });
}

/// 🚨★★★x시트는 **같은 코드**가 축만 바꿔 그린다. 유저 2026-08-27:
/// 「x시트 **로직적으로 통일**하는거 절대잊지말고」.
///
/// ⛔이 테스트는 「x시트에도 라벨이 보인다」가 아니라 **「두 표면이 같은 위젯을
/// 쓴다」**를 잰다 — 전자는 x시트가 자기 사본을 그려도 통과한다.
void _oneWidgetBothSurfaces() {
  test('레일과 x시트가 같은 칩 위젯을 쓴다 — 사본이 아니다', () {
    // 소스 스캔이다: 행동 테스트는 「지금은 똑같이 생긴 사본 둘」을 통과시킨다.
    final grid = File(
      'lib/src/ui/timeline/xsheet_timeline_grid.dart',
    ).readAsStringSync();
    expect(
      grid,
      contains('LayerMarkChip('),
      reason: 'x시트도 레일과 같은 칩을 세운다',
    );

    // 그리고 그 칩이 축을 인자로 받는지 — 축이 없으면 두 표면은 갈릴 수밖에
    // 없고, 갈리는 순간 사본이 된다.
    final controls = File(
      'lib/src/ui/timeline/layer_label_controls.dart',
    ).readAsStringSync();
    expect(
      controls,
      contains('final Axis axis;'),
      reason: '한 위젯이 두 방향을 인자로 답한다',
    );
    for (final surfaceOwn in [
      'class _XSheetMarkChip',
      'class XSheetLabelPlate',
      'class _SheetLabelPlate',
    ]) {
      expect(
        grid + controls,
        isNot(contains(surfaceOwn)),
        reason: '⛔x시트가 자기 라벨 위젯을 만들면 그 순간 두 벌이다',
      );
    }
  });
}

/// 🚨공정·수정 이름이 **프로그램 언어를 탄다**. 유저 2026-08-28: 「프로그램
/// 언어에따라 **로컬라이즈 안되니까** 해주고」 — 일본어 UI 에서 「ラベルなし」
/// 옆에 「용지」가 나오고 있었다.
void _namesFollowTheLanguage() {
  void speak(AppLanguage language) => AppText.settings.value =
      AppLanguageSettings(programLanguage: language);
  tearDown(() => AppText.settings.value = const AppLanguageSettings());

  test('네 언어 모두 공정·수정의 이름과 축약어를 갖는다', () {
    for (final language in AppLanguage.values) {
      speak(language);
      for (final process in LayerProcess.values) {
        expect(
          layerProcessLabel(process),
          isNotEmpty,
          reason: '$language · ${process.jsonValue}',
        );
        expect(layerProcessAbbrev(process), isNotEmpty);
      }
      for (final revise in LayerRevise.values) {
        expect(
          layerReviseLabel(revise),
          isNotEmpty,
          reason: '$language · ${revise.jsonValue}',
        );
        expect(layerReviseAbbrev(revise), isNotEmpty);
      }
    }
  });

  test('언어를 바꾸면 실제로 글자가 바뀐다 — 표가 비어도 fallback 으로 통과하지 '
      '않게', () {
    // ⛔`isNotEmpty` 만으로는 못 잡는다: 표가 통째로 비어 있어도 enum 의 영어가
    // fallback 으로 나와 전부 통과한다. **다르다**를 재야 한다.
    speak(AppLanguage.en);
    final english = layerProcessLabel(LayerProcess.key);
    speak(AppLanguage.ja);
    final japanese = layerProcessLabel(LayerProcess.key);
    speak(AppLanguage.ko);
    final korean = layerProcessLabel(LayerProcess.key);

    expect(english, 'Key');
    expect(japanese, isNot(english), reason: '原画');
    expect(korean, isNot(english), reason: '원화');
    expect(korean, isNot(japanese));
  });

  test('칩 글자도 번역을 탄다 — 모델의 영어가 새어나오지 않는다', () {
    speak(AppLanguage.ko);
    final text = layerMarkChipText(
      const LayerMark(
        process: LayerProcess.layout,
        revise: LayerRevise.animationDirector,
      ),
    );
    expect(text.process, 'LO');
    expect(text.revise, '작감', reason: '⛔모델의 \'AD\' 가 그대로 나오면 안 된다');
  });
}
