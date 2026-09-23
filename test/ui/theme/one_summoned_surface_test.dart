import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/dart_sources.dart';

/// 🚨★★★공통창은 색을 **한 군데서만** 고른다.
///
/// 유저 2026-08-28: 「겹이랑 팝오버랑 색이 다르거든? 겹은 진한 검정이고 팝오버는
/// 회색인데, 이 진한검정 아주 마음에들었어. 이 색을 바탕으로 **공통창 다**
/// 변경하고싶어. **뭐 하나 바꾸면 알아서 변경되겟지?**」 — 그 질문에 「예」라고
/// 답하는 것이 이 파일이다.
///
/// ⛔행동 테스트로는 못 잡는다: 다이얼로그가 [AppPopupSurface.color] 와 **지금은
/// 같은 값**을 자기 손으로 적고 있었고, 색을 비교하는 테스트는 그것을 통과시킨다.
/// **사본은 값이 갈라지기 전까지 안 보인다** ⇒ 소스를 훑어 「자기가 직접 적었는가」를
/// 본다.
void main() {
  test('불려 나온 창은 전부 한 토큰을 읽는다 — 메뉴·툴팁·다이얼로그·팝오버', () {
    final theme = buildAppTheme();

    expect(theme.popupMenuTheme.color, AppPopupSurface.color);
    expect(theme.dialogTheme.backgroundColor, AppPopupSurface.color);
    expect(
      theme.dialogTheme.shape,
      AppPopupSurface.shape,
      reason: '모서리와 테두리도 같은 창 모양이다',
    );
    expect(
      (theme.tooltipTheme.decoration! as ShapeDecoration).color,
      AppPopupSurface.color,
      reason: '툴팁만 회색으로 남아 있었다',
    );
    expect(
      theme.menuTheme.style?.backgroundColor?.resolve(const <WidgetState>{}),
      AppPopupSurface.color,
    );
  });

  test('⛔불려 나온 창의 바탕색을 자기 손으로 적는 곳이 없다 (래칫)', () {
    // A file that SUMMONS a window may not name a chrome colour anywhere in
    // it. ⚠️Anchoring on the summoning line and scanning a few lines forward
    // does NOT work, and I checked: `panel_flyout.dart` builds its
    // `OverlayEntry` in one place and skins the layer sixty lines later, so
    // a windowed scan walked straight past the exact regression this guards.
    const summons = <String>[
      'OverlayEntry(',
      'showMenu(',
      'showDialog',
      'AlertDialog',
      'PopupMenuButton',
      'DropdownMenu',
      'PopupMenuTheme',
      'TooltipTheme',
      'DialogTheme',
      'MenuStyle',
    ];
    final named = RegExp(
      r'color:\s*AppColors\.(surface|surfaceHigh|surfaceLow|panel)\b',
    );

    final offenders = <String>[];
    var scanned = 0;
    for (final entity in dartFilesUnder('lib')) {
      // The theme file is the one place allowed to spell the value out —
      // that IS the token's definition.
      if (entity.path.endsWith('app_theme.dart')) {
        continue;
      }
      final lines = entity.readAsLinesSync();
      if (!lines.any((line) => summons.any(line.contains))) {
        continue;
      }
      scanned++;
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) {
          continue;
        }
        final hit = named.firstMatch(lines[i]);
        if (hit != null) {
          offenders.add('${entity.path}:${i + 1} — ${hit.group(0)}');
        }
      }
    }

    // 🚨계측기를 먼저 의심한다: a scan that matched no files would report
    // 「위반 없음」 for the emptiest of reasons.
    expect(
      scanned,
      greaterThanOrEqualTo(25),
      reason: '창을 부르는 파일을 못 찾았다 — 스캔이 빈 것을 쟀다',
    );
    expect(
      offenders,
      isEmpty,
      reason:
          '불려 나온 창은 AppPopupSurface.color 를 읽어야 한다 — 값이 같아도 '
          '자기가 적으면 사본이고, 토큰을 고쳤을 때 안 따라온다:\n'
          '${offenders.join('\n')}',
    );
  });
}
