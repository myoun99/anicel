import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:anicel/src/ui/timeline/timeline_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'dart:io';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/app_accents.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import '../../helpers/library_source.dart';

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
  _oneDecidesTheWritingDirection();
  _threeGlyphAbbreviations();
  _labelGlyphsKeepTheirAntiAliasing();

  // 🚨A GLOBAL. Saving and restoring rather than assigning a fresh default
  // back: writing `const AppAccentSettings()` in the teardown would not undo
  // this file, it would overwrite whatever the suite had set up.
  late AppAccentSettings saved;
  setUp(() => saved = AppColors.accentSettings.value);
  tearDown(() => AppColors.accentSettings.value = saved);

  test('스샷에서 뽑은 색상이 그대로 나온다 — LO는 흰색, 원화는 초록, 미술은 파랑', () {
    // ⚠️These are the user's own hues, measured out of `board-shots/`. A test
    // that only said 「어떤 색이 나온다」 would have passed on the palette I
    // invented before opening those files.
    //
    // 🪦값 자체는 **크림 톤**의 것이다. 네 톤을 다 구현해 실기에서 고르게
    // 했었고(I-4), 크림으로 확정된 뒤 나머지 셋과 고르는 장치를 걷었다
    // (유저 2026-08-28: 「색도 크림으로 정했으니까 나머지 유물 없애도되」).
    // 색상은 그대로고 톤만 옮겨 앉았다.
    expect(
      layerMarkColor(const LayerMark(process: LayerProcess.layout)),
      const Color(0xFFFFFDF7),
      reason: '유저: 「LO는 흰색이야」',
    );
    expect(
      layerMarkColor(const LayerMark(process: LayerProcess.key)),
      const Color(0xFFB5FDB0),
      reason: '유저: 「원화는 초록색이었고」',
    );
    expect(
      layerMarkColor(const LayerMark(process: LayerProcess.art)),
      const Color(0xFF6BB3F7),
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

  test('모든 라벨이 블록 잉크가 읽히는 밝기다', () {
    // 유저: 「프레임이름/코마숫자/색라벨은 다 같은 색상의 바탕 위에 올라가는
    // 텍스트니까 **셋 다 같은 로직** 통일해서 사용하도록」 + 「그거 감안해서
    // **검정색이 되도록 유도하는 색**으로만 설계해보자」.
    //
    // 🚨So the palette is not free: every colour has to sit ABOVE the block
    // ink's crossover, or the plate would flip to white and that one chip
    // would be the exception the user asked not to have.
    for (final mark in everyLayerMark()) {
      final fill = layerMarkColor(mark);
      expect(
        timelineGroundIsLight(fill),
        isTrue,
        reason:
            '$mark = $fill '
            '(luminance ${fill.computeLuminance().toStringAsFixed(3)}) — '
            '0.179 아래로 내려가면 그 칩만 흰 글자가 된다',
      );
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
    expect(revisesFor(LayerProcess.inbetween).last, LayerRevise.inbetweenCheck);
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
          reason:
              '🚨세로 레일 — 테이크가 색 라벨 아래. 가로로 놓으면 열 머리 '
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
    //
    // 🆕2026-09-02: x시트는 칩을 **직접 세우지도 않는다** — 레일의 행 위젯을
    // `axis: Axis.vertical` 로 세우고, 칩은 그 행이 한 곳에서 세운다. 그래서
    // 「x시트에 `LayerMarkChip(` 이 있다」는 이제 사본의 징후다.
    // The x-sheet grid is a LIBRARY — the file plus the collaborator parts
    // the audit's SRP cuts (2026-09-02) put beside it — so the row widget
    // is found where a cut put it.
    final grid = librarySource('lib/src/ui/timeline/xsheet_timeline_grid.dart');
    expect(
      grid,
      contains('TimelineLayerControlsRow('),
      reason: 'x시트의 열 머리는 레일의 행 위젯이다',
    );
    expect(
      grid,
      isNot(contains('LayerMarkChip(')),
      reason: '⛔x시트가 칩을 따로 세우면 행 위젯 밖에 두 번째 자리가 생긴 것이다',
    );
    final row = File(
      'lib/src/ui/timeline/timeline_layer_controls_row.dart',
    ).readAsStringSync();
    expect(row, contains('LayerMarkChip('), reason: '칩을 세우는 곳은 행 위젯 하나');
    expect(
      row,
      contains('axis: axis,'),
      reason: '그 행이 자기 축을 칩에 넘긴다 — 두 표면이 한 코드로 갈린다',
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
  void speak(AppLanguage language) =>
      AppText.settings.value = AppLanguageSettings(programLanguage: language);
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

/// ⛔**세로쓰기를 고르는 곳은 하나다** (래칫).
///
/// 색 라벨과 테이크 칩은 나란히 앉아 「레일이면 세워 쓰고 x시트면 가로로
/// 쓴다」를 **각자** 골랐다. 둘이 **일치**했으므로 행동 테스트는 통과했다 —
/// 유저: 「사본 남으면 진짜 용서안할게」. 사본은 갈라지기 전까지 안 보이므로
/// **소스를 훑는다.**
void _oneDecidesTheWritingDirection() {
  test('축을 보고 쓰기 방향을 고르는 곳은 한 곳뿐이다', () {
    final source = File(
      'lib/src/ui/timeline/layer_label_controls.dart',
    ).readAsLinesSync();
    final builders = <int>[];
    for (var i = 0; i < source.length; i++) {
      if (source[i].trimLeft().startsWith('//')) {
        continue;
      }
      // ⚠️축으로 **갈라지는** 곳만 센다. 섹션 밴드의 ACTION·SE·CAM 은 축과
      // 무관하게 늘 서 있으므로 같은 결정이 아니다 — 그것까지 세면 래칫이
      // 남의 기능을 붙잡고 「사본이다」라고 말한다.
      if (!source[i].contains('axis == Axis.')) {
        continue;
      }
      final window = source.skip(i).take(9).join(' ');
      if (window.contains('VerticalWritingText(')) {
        builders.add(i + 1);
      }
    }
    expect(
      builders,
      hasLength(1),
      reason:
          '⛔세로쓰기를 두 곳에서 만들면 그게 사본이다. 공용 결정은 '
          '`layerPlateGlyphs` — 줄: $builders',
    );
  });
}

/// 축약어는 **세 글자까지** 간다. 유저 2026-08-28: 「총작화감독은 총작감,
/// 총감독은 총감독, 러프원화는 러프원. 즉 **3글자까지 허용**이란느낌」.
void _threeGlyphAbbreviations() {
  void speak(AppLanguage language) =>
      AppText.settings.value = AppLanguageSettings(programLanguage: language);
  tearDown(() => AppText.settings.value = const AppLanguageSettings());

  test('유저가 지정한 셋이 세 글자로 나온다 — 한국어와 일본어 둘 다', () {
    speak(AppLanguage.ko);
    expect(layerProcessAbbrev(LayerProcess.roughKey), '러프원');
    expect(layerReviseAbbrev(LayerRevise.chiefAnimationDirector), '총작감');
    expect(layerReviseAbbrev(LayerRevise.chiefDirector), '총감독');

    speak(AppLanguage.ja);
    expect(layerProcessAbbrev(LayerProcess.roughKey), 'ラフ原');
    expect(layerReviseAbbrev(LayerRevise.chiefAnimationDirector), '総作監');
    expect(layerReviseAbbrev(LayerRevise.chiefDirector), '総監督');
  });

  test('세 글자가 상한이다 — 넷째 글자가 들어오면 띠가 감당 못 한다', () {
    // ⚠️상한을 **재는** 테스트다. 14px 슬롯이 칼럼 둘로 갈리므로 한 글자가
    // 7px 이고, 넷째 글자가 들어오면 한 줄이 5px 밑으로 떨어진다.
    for (final language in [AppLanguage.ko, AppLanguage.ja]) {
      speak(language);
      for (final process in LayerProcess.values) {
        expect(
          layerProcessAbbrev(process).characters.length,
          lessThanOrEqualTo(3),
          reason: '$language · ${process.jsonValue}',
        );
      }
      for (final revise in LayerRevise.values) {
        expect(
          layerReviseAbbrev(revise).characters.length,
          lessThanOrEqualTo(3),
          reason: '$language · ${revise.jsonValue}',
        );
      }
    }
  });
}

/// 🚨★★★색 라벨 글자는 **평범하게, AA 가 붙은 채로** 그려진다.
///
/// 🪦여기 계단 필터가 있었다. 유저 2026-08-28 의 「색라벨 텍스트 뭔가 좀
/// 읽기힘든데 … **쌩2치화** 된 텍스트로 할수있나?」로 들어왔고, 폰트를
/// BIZ UDPGothic 으로 바꾼 뒤 「글자가 1px같은게 사라졌어」로 이어져
/// 「우선 2치화는 없는걸로 가자」로 끝났다. 왜 있었고 왜 갔는지는
/// [AppAccentSettings.layerMarkGlyphWeight] 의 문서에 있다.
///
/// ⇒ 이 테스트가 지키는 것은 **그 자리가 다시 채워지지 않는 것**이다. 계단이
/// 돌아오면 가장자리의 중간 회색이 0 이 되므로, 그것을 센다.
void _labelGlyphsKeepTheirAntiAliasing() {
  // ⛔플레이트를 따로 세워서 재지 않는다. 그건 「내가 세운 것」을 재는 것이지
  // **화면에 나오는 것**이 아니다 — 앱에서 무언가 빠져도 통과한다.
  // 화면 전체를 찍고 **칩의 사각형만** 읽는다.
  testWidgets('진짜 패널을 찍어 판의 픽셀을 센다 — 가장자리에 회색이 남아 있다', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: key, child: markPanelForPixelTest()),
    );
    await tester.pumpAndSettle();

    final chip = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-layer-mark-a')),
    );

    late ByteData pixels;
    late int rowBytes;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      rowBytes = image.width * 4;
      pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    });

    // 판은 색 바탕에 잉크 글자다. 두 값 사이의 **중간 회색**이 곧 AA 다.
    final levels = <int>{};
    for (var y = (chip.top * 3).round(); y < (chip.bottom * 3).round(); y++) {
      for (var x = (chip.left * 3).round(); x < (chip.right * 3).round(); x++) {
        levels.add(pixels.getUint8(y * rowBytes + x * 4 + 1));
      }
    }
    final sorted = levels.toList()..sort();

    // 🚨계측기를 먼저 의심한다: 글자가 아예 안 그려졌으면 계조가 하나뿐이고
    // 어떤 주장이든 자동으로 참이 된다.
    expect(sorted.length, greaterThan(1), reason: '⛔빈 것을 쟀다 — 판에 글자가 없다');
    expect(
      sorted.where((v) => v > sorted.first + 12 && v < sorted.last - 12).length,
      greaterThan(0),
      reason: '🚨바탕과 잉크 사이가 계단이다 — 걷어낸 2치화가 돌아왔다 · 계조 $sorted',
    );
  });
}

/// 픽셀 테스트가 쓰는 **진짜 패널**. 레일 한 줄에 라벨이 붙은 레이어 하나.
Widget markPanelForPixelTest() {
  final layers = [
    Layer(
      id: const LayerId('a'),
      name: 'a',
      kind: LayerKind.animation,
      mark: const LayerMark(
        process: LayerProcess.layout,
        revise: LayerRevise.animationDirector,
      ),
      frames: [Frame(id: const FrameId('af'), duration: 1, strokes: const [])],
      timeline: const {},
    ),
  ];
  return MaterialApp(
    home: Scaffold(
      body: TimelinePanel(
        layers: layers,
        activeLayerId: const LayerId('a'),
        frameCursor: ValueNotifier<int>(0),
        playbackFrameCount: 12,
        exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
        onSelectLayer: (_) {},
        onSelectFrame: (_) {},
        onAddLayer: () {},
        onToggleLayerVisibility: (_) {},
        onLayerOpacityChanged: (_, _) {},
        onToggleLayerTimesheet: (_) {},
        onLayerMarkSelected: (_, _) {},
        orientation: TimelineOrientation.horizontal,
        onOrientationChanged: (_) {},
      ),
    ),
  );
}
