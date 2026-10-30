import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/menu_rows_without_an_action.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🗣️I-40 (유저 2026-09-18): 「버튼 전수감사해서 숏컷리스트에 등록 … 설정의
/// 패널 열기 닫기같은거든 뭐든 모든 버튼」. Asked how far (I-40-Q1), 유저
/// chose on 2026-10-08: 「편집 화면의 명령 버튼과 메뉴 항목」 — every row of
/// a menu on the editing screen, and every button that does one thing.
///
/// A MENU ROW NAMES ITS ACTION (`shortcuts:`), OR STANDS HERE WITH WHY NOT.
/// A row is an action by naming one — that is what puts its key beside it,
/// lets a key press it (`pressFlyoutRow`) and lists it in the shortcut
/// window. A row that names none is one of three things, and the ledger
/// says which:
///
///   · ↩️OWED — a row of the scope chosen above that was not an action
///     YET. The rounds of I-40 emptied it on 2026-10-09, the last two
///     declined (I-40-Q5 · Q6): a new menu row arrives as an action, or here
///     as one of the three below.
///   · A CHOICE — one value out of a list (a font, a colour label, an edge
///     mode). The answer leaves these out: 「도구 설정의 선택지 · 스위치 …
///     에는 키를 줄 수 없다」 was the cost 유저 took with it.
///   · THE DOOR TO A SECOND LEVEL — it opens a submenu and runs nothing.
///   · DECLINED — asked, and 유저 answered that it takes no key; the line
///     names the question.
///
/// ⚠️This reads the SOURCE: what a row does when pressed is the widget
/// tests' (`timeline_bar_rows_are_actions_test`, `menu_rows_are_actions_
/// test`). What it holds is the one thing those cannot — that no row was
/// left out because nobody listed it.
enum Why { aChoice, aSecondLevel, declined }

const ledger = <String, Why>{
  "brush/text_tool_settings.dart | 'text-tool-font-\${_nameOf(family)}'":
      Why.aChoice,
  "brush/text_tool_settings.dart | 'text-tool-font-\${family.name}'":
      Why.aChoice,
  "brush/text_tool_settings.dart | 'text-tool-font-\${inUse.value}'":
      Why.aChoice,
  "brush/text_tool_settings.dart | 'text-tool-project-font-\$family'":
      Why.aChoice,
  "brush/text_tool_settings.dart | 'text-tool-text-\$index'": Why.aChoice,
  "cut_command_group.dart | 'cut-mark-button'": Why.aSecondLevel,
  // F-391: a stop of the zoom list — one value of a settings list; all its
  // row does is its own ⊖, which takes the stop out. F-480: the zoom lock's
  // list is the same rows (`_PercentListRow`), one value at most.
  'dialogs/input_settings_dialog.dart | '
          "'\$keyValue-\${_shownPercent(percent)}'":
      Why.aChoice,
  // I-72-block-without-instruction: 「(없음)」, the first value of the mark
  // list — the vocabulary's own rows go through `asFlyoutValueChoices`.
  "dialogs/instruction_event_dialog.dart | 'instruction-option-none'":
      Why.aChoice,
  // 🗣️I-40-Q2 (유저 2026-10-09, a file row's ⋮ — which file would a key
  // take?): 「그런건 단축키 안만들어도됨」.
  "media/media_pool_panel.dart | 'media-asset-menu-export-wav'": Why.declined,
  "media/media_pool_panel.dart | 'media-asset-menu-open'": Why.declined,
  "media/media_pool_panel.dart | 'media-asset-menu-open-sub'": Why.declined,
  "media/media_pool_panel.dart | 'media-asset-menu-place'": Why.declined,
  "media/media_pool_panel.dart | 'media-asset-menu-promote'": Why.declined,
  "media/media_pool_panel.dart | 'media-asset-menu-relink'": Why.declined,
  "media/media_pool_panel.dart | 'media-asset-menu-remove'": Why.declined,
  "media/media_pool_panel.dart | 'media-asset-menu-rename'": Why.declined,
  // ⚠️MY READING of I-40-Q2's answer, not a question of its own: a
  // palette's ⋯ is a row's menu as a file's ⋮ is — which palette would a
  // key take? (I-131)
  "color/color_palettes.dart | 'palette-delete'": Why.declined,
  "color/color_palettes.dart | 'palette-duplicate'": Why.declined,
  "color/color_palettes.dart | 'palette-export'": Why.declined,
  "color/color_palettes.dart | 'palette-make-default'": Why.declined,
  "color/color_palettes.dart | 'palette-rename'": Why.declined,
  // ⚠️MY READING of I-40-Q5's answer, as the palettes' above is of Q2's: a
  // row per plugin this device has is a row per recent project — 「몇 번째
  // 줄」 or 「그 플러그인」? (I-132)
  'timeline/timeline_bar_menus.dart | '
          "'add-effect-plugin-\${description.id}'":
      Why.declined,
  // 🗣️I-40-Q3 (유저 2026-10-09, two viewers — which one would a key take?):
  // 「안만들기로했음」.
  "media/media_viewer_tab_host.dart | _key('register-asset-button')":
      Why.declined,
  "media/media_viewer_tab_host.dart | _key('swap-button')": Why.declined,
  // 🗣️I-40-Q5 (유저 2026-10-09, a row per recent project — 「몇 번째 줄」
  // or 「그 파일」?): 「주지 않는다」. The row above it only opens that list.
  "menu/editor_top_strip.dart | 'menu-recent-\${entry.path}'": Why.declined,
  "menu/editor_top_strip.dart | 'menu-recent-projects'": Why.aSecondLevel,
  // 🗣️I-40-Q6 (유저 2026-10-09, a row per tab that did not fit the strip —
  // a panel's own action already shows it): 「주지 않는다」.
  "panels/editor_panel_tabs.dart | 'panel-tab-overflow-item-\${tab.id}'":
      Why.declined,
  // The shortcut window's list of presets (I-107): which layout the keys
  // are, one out of the list — `key` is `'shortcut-preset-${preset.id}'`.
  'shortcuts/shortcut_settings_dialog.dart | key': Why.aChoice,
  "timeline/layer_label_controls.dart | 'layer-mark-option-\${option.keySlug}'":
      Why.aChoice,
  "timeline/layer_label_controls.dart | 'layer-mark-option-none'": Why.aChoice,
  'timeline/layer_label_controls.dart | revisesFor(process).isEmpty ? '
          "'layer-mark-option-\${process.jsonValue}' : "
          "'layer-mark-stage-\${process.jsonValue}'":
      Why.aChoice,
  "timeline/timeline_row_edit_chrome.dart | 'run-edge-mode-hold'": Why.aChoice,
  "timeline/timeline_row_edit_chrome.dart | 'run-edge-mode-none'": Why.aChoice,
  "timeline/timeline_row_edit_chrome.dart | 'run-edge-mode-repeat'":
      Why.aChoice,
  "timeline/timeline_row_edit_chrome.dart | 'run-edge-mode-repeat-selection'":
      Why.aChoice,
};

void main() {
  final rows = menuRowsUnder('lib/src/ui');

  // The instrument before what it measures: a scan that counted a comment
  // as a row would ask the ledger for a line nothing can give, and one that
  // missed a row would call the ledger whole.
  test('the scan: a row is a CALL — not the class saying what a row takes, '
      'a comment, a switch asking what a row has, or a longer-named '
      'widget', () {
    final folder = Directory.systemTemp.createTempSync('menu-rows');
    deleteAfterSessionEnds(folder);
    File('${folder.path}/menu.dart').writeAsStringSync('''
class PanelFlyoutItem {
  const PanelFlyoutItem({this.keyValue});
}
final a = PanelFlyoutItem(keyValue: 'named', shortcuts: const ['x']);
final b = PanelFlyoutItem(
  keyValue: 'silent-\${f(1, 2)}',
  label: g(3, 4),
);
// PanelFlyoutItem(keyValue: 'in a comment')
final c = switch (e) {
  PanelFlyoutItem(:final keyValue) => keyValue,
  _ => null,
};
final d = NotAPanelFlyoutItem(keyValue: 'another widget');
final first = PanelFlyoutItem(label: 'keyless');
final second = PanelFlyoutItem(label: 'keyless too');
''');

    final found = menuRowsUnder(folder.path);

    expect(found.named, {"menu.dart | 'named'"});
    expect(found.silent, {
      "menu.dart | 'silent-\${f(1, 2)}'",
      'menu.dart | keyless row 1',
      'menu.dart | keyless row 2',
    });
  });

  test('⛔premise: the scan reaches the menus — the rows that are actions '
      'and the ones that are not', () {
    expect(
      rows.named,
      contains("cut_command_group.dart | 'edit-cut-note-button'"),
    );
    expect(
      rows.named,
      contains(
        'timeline/timeline_bar_menus.dart | '
        "'add-layer-kind-\${_addLayerKeySuffix(kind)}'",
      ),
    );
    expect(rows.silent, contains("cut_command_group.dart | 'cut-mark-button'"));
    expect(rows.named.intersection(rows.silent), isEmpty);
  });

  test('🚨a row that names no action is in the ledger, with why', () {
    expect(
      rows.silent.difference(ledger.keys.toSet()),
      isEmpty,
      reason:
          'a new menu row: give it its action (`shortcuts:` — I-40), or '
          'write here why it is none',
    );
  });

  test('⛔and the ledger holds no row that is gone, or is an action by '
      'now', () {
    expect(
      ledger.keys.toSet().difference(rows.silent),
      isEmpty,
      reason: 'take the line out — the list of what is owed only shrinks',
    );
  });
}
