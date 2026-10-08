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
///   · OWED — a row of the scope chosen above that is not an action YET.
///     The rounds of I-40 empty this list, and it only shrinks: a new menu
///     row arrives as an action, or it arrives here and says why.
///   · A CHOICE — one value out of a list (a font, a colour label, an edge
///     mode). The answer leaves these out: 「도구 설정의 선택지 · 스위치 …
///     에는 키를 줄 수 없다」 was the cost 유저 took with it.
///   · THE DOOR TO A SECOND LEVEL — it opens a submenu and runs nothing.
///
/// ⚠️This reads the SOURCE: what a row does when pressed is the widget
/// tests' (`timeline_bar_rows_are_actions_test`, `menu_rows_are_actions_
/// test`). What it holds is the one thing those cannot — that no row was
/// left out because nobody listed it.
enum Why { owed, aChoice, aSecondLevel }

const ledger = <String, Why>{
  // The brush library's options menu: its rows are made by one helper, so
  // the thirteen stand as one line here.
  'brush/brush_preset_panel.dart | keyValue': Why.owed,
  "brush/canvas_panel/viewport_bottom_bar_build.dart | 'canvas-viewport-reset'":
      Why.owed,
  "brush/text_tool_settings.dart | 'text-tool-font-\${_nameOf(family)}'":
      Why.aChoice,
  "brush/text_tool_settings.dart | 'text-tool-font-\${family.name}'":
      Why.aChoice,
  "brush/text_tool_settings.dart | 'text-tool-font-\${inUse.value}'":
      Why.aChoice,
  "brush/text_tool_settings.dart | 'text-tool-project-font-\$family'":
      Why.aChoice,
  "brush/text_tool_settings.dart | 'text-tool-text-\$index'": Why.aChoice,
  "conte/conte_tab_host.dart | 'conte-blank-page-toggle'": Why.owed,
  "conte/conte_tab_host.dart | 'conte-cover-toggle'": Why.owed,
  "cut_command_group.dart | 'cut-mark-button'": Why.aSecondLevel,
  "media/media_pool_panel.dart | 'media-asset-menu-export-wav'": Why.owed,
  "media/media_pool_panel.dart | 'media-asset-menu-open'": Why.owed,
  "media/media_pool_panel.dart | 'media-asset-menu-open-sub'": Why.owed,
  "media/media_pool_panel.dart | 'media-asset-menu-place'": Why.owed,
  "media/media_pool_panel.dart | 'media-asset-menu-promote'": Why.owed,
  "media/media_pool_panel.dart | 'media-asset-menu-relink'": Why.owed,
  "media/media_pool_panel.dart | 'media-asset-menu-remove'": Why.owed,
  "media/media_pool_panel.dart | 'media-asset-menu-rename'": Why.owed,
  "media/media_viewer_tab_host.dart | _key('register-asset-button')":
      Why.owed,
  "media/media_viewer_tab_host.dart | _key('swap-button')": Why.owed,
  // One row per recent project — a list that is the user's own, as the
  // brush library's rows are (I-56 made those actions out of the library as
  // it stands). What shape an action takes here is asked when its round
  // comes; the row above it only opens that list.
  "menu/editor_top_strip.dart | 'menu-recent-\${entry.path}'": Why.owed,
  "menu/editor_top_strip.dart | 'menu-recent-projects'": Why.aSecondLevel,
  "menu/project_settings_menu.dart | 'project-settings-audio-rate'": Why.owed,
  "menu/project_settings_menu.dart | 'project-settings-camera-size'":
      Why.owed,
  "menu/project_settings_menu.dart | 'project-settings-fps'": Why.owed,
  "menu/project_settings_menu.dart | 'project-settings-playback-mode'":
      Why.owed,
  // One row per tab that did not fit the strip: picking it shows that
  // panel, which a panel's own action also does.
  "panels/editor_panel_tabs.dart | 'panel-tab-overflow-item-\${tab.id}'":
      Why.owed,
  "timeline/layer_label_controls.dart | 'layer-mark-option-\${option.keySlug}'":
      Why.aChoice,
  "timeline/layer_label_controls.dart | 'layer-mark-option-none'": Why.aChoice,
  'timeline/layer_label_controls.dart | revisesFor(process).isEmpty ? '
          "'layer-mark-option-\${process.jsonValue}' : "
          "'layer-mark-stage-\${process.jsonValue}'":
      Why.aChoice,
  "timeline/timeline_layer_controls_header.dart | 'legend-blend-\${mode.name}'":
      Why.owed,
  "timeline/timeline_layer_controls_header.dart | 'legend-eye-hide-all'":
      Why.owed,
  "timeline/timeline_layer_controls_header.dart | 'legend-eye-show-all'":
      Why.owed,
  "timeline/timeline_layer_controls_header.dart | 'legend-fill-ref-clear'":
      Why.owed,
  "timeline/timeline_layer_controls_header.dart | 'legend-filter-fill-ref'":
      Why.owed,
  "timeline/timeline_layer_controls_header.dart | 'legend-filter-fx'":
      Why.owed,
  'timeline/timeline_layer_controls_header.dart | '
          "'legend-filter-kind-\${kind.name}'":
      Why.owed,
  'timeline/timeline_layer_controls_header.dart | '
          "'legend-filter-mark-\${mark.keySlug}'":
      Why.owed,
  "timeline/timeline_layer_controls_header.dart | 'legend-filter-sheet'":
      Why.owed,
  "timeline/timeline_layer_controls_header.dart | 'legend-fx-bypass-all'":
      Why.owed,
  "timeline/timeline_layer_controls_header.dart | 'legend-fx-enable-all'":
      Why.owed,
  "timeline/timeline_layer_controls_header.dart | 'legend-mark-filter-clear'":
      Why.owed,
  "timeline/timeline_layer_controls_header.dart | 'legend-onion-open-panel'":
      Why.owed,
  'timeline/timeline_layer_controls_header.dart | '
          "'legend-onion-toggle-displayed'":
      Why.owed,
  "timeline/timeline_layer_controls_header.dart | 'legend-section-camera'":
      Why.owed,
  "timeline/timeline_layer_controls_header.dart | 'legend-section-se'":
      Why.owed,
  "timeline/timeline_layer_controls_header.dart | 'legend-sheet-all-off'":
      Why.owed,
  "timeline/timeline_layer_controls_header.dart | 'legend-sheet-all-on'":
      Why.owed,
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
      contains("cut_command_group.dart | 'rename-cut-button'"),
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
