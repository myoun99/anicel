import 'package:flutter_test/flutter_test.dart';

import '../../helpers/menu_rows_without_an_action.dart';

/// 🗣️I-40 (유저 2026-09-18): 「버튼 전수감사해서 숏컷리스트에 등록 … 뭐든
/// 모든 버튼」. Asked how far (I-40-Q1), 유저 chose on 2026-10-08: 「편집
/// 화면의 명령 버튼과 메뉴 항목」 — every button that does one thing.
///
/// A BUTTON NAMES ITS ACTION (`shortcuts:`), OR STANDS HERE WITH WHY NOT —
/// the menu rows' ledger (`a_menu_row_names_an_action_or_says_why_test`)
/// asked of the buttons. A button names an action to put its key in its
/// tooltip and to be what that key presses. One that names none is:
///
///   · ↩️OWED — a command of the scope chosen above that was not an action
///     YET. The rounds of I-40 emptied it on 2026-10-11, the tool settings'
///     buttons last and the sheets' pills declined (I-40-Q7): a new button
///     arrives as an action, or here as one of the five below.
///   · ON A ROW — it acts on its own row or item (a layer's eye, a lane's
///     reset, a project tab's ✕): 「레이어 행의 눈 · 잠금 … 에는 키를 줄 수
///     없다」 was the cost 유저 took with the answer.
///   · A SETTING — one value of a choice, a switch, a step of a slider —
///     「도구 설정의 선택지 · 스위치」, the same cost.
///   · THE DOOR TO A SECOND LEVEL — it opens a menu or a popover and runs
///     nothing.
///   · IN A WINDOW — 「창 안의 버튼」, the answer's third exclusion.
///   · DECLINED — asked, and 유저 answered that it takes no key; the line
///     names the question.
///
/// ⚠️What is scanned: the app's ONE button (`AppIconButton`), the view
/// pill's spelling of it (`_barIconButton`), the buttons that wrap it and
/// pass `shortcuts:` through (the strip's, the rail's, the command pill),
/// and the layer rails' own button (`RailGlyphButton`, I-57 ①), which
/// names no action, so each of its uses stands here — and a tool's
/// ACTIONS (`ToolSettingAction`, tool-settings-panel-tidy 2026-10-10:
/// they wore Material's buttons until then, which this scan never
/// read). ⛔Not the kinds that are one of the answer's exclusions by what
/// they ARE — a boolean dot is a switch, a colour swatch a choice, a
/// flyout button a door, the layer row's toggles a row's — whose every use
/// would stand here with the same reason. Nor `RailGlyphButton.face`: the
/// face an `AppIconButton` wears around a plain `Icon` IS that button, and
/// is scanned where the button is called.
enum Why { aRow, aSetting, aSecondLevel, inAWindow, declined }

const ledger = <String, Why>{
  // ── ON A ROW ────────────────────────────────────────────────────────
  "brush/guide_panels.dart | 'guide-delete-\${guide.id.value}'": Why.aRow,
  "brush/guide_panels.dart | 'guide-remove'": Why.aRow,
  "brush/guide_panels.dart | 'guide-rename-\${guide.id.value}'": Why.aRow,
  // A palette's − (I-131): it takes the current colour out of the palette
  // whose name row it stands on.
  "color/color_palettes.dart | 'palette-\${palette.id}-remove'": Why.aRow,
  // A palette's lock (I-131, 10-28): it locks the palette whose name row it
  // stands on.
  "color/color_palettes.dart | 'palette-\${palette.id}-lock'": Why.aRow,
  "media/media_pool_panel.dart | 'media-asset-in-use-\${asset.path}'":
      Why.aRow,
  "menu/editor_top_strip.dart | 'project-tab-close-\$index'": Why.aRow,
  // A header graph's two toggles (I-89 ③): the graph of the group whose
  // header or camera row wears it, and the pin of the lane it stands on.
  'timeline/lane_graph_toggle.dart | name': Why.aRow,
  'timeline/layer_label_controls.dart | '
          "'\$keyPrefix-layer-timesheet-\$layerId'":
      Why.aRow,
  'timeline/layer_label_controls.dart | name': Why.aRow,
  // The one twirl (what a row holds under it) and the type cell (the row
  // it stands on) — one line, as both pass their `name`.
  'timeline/layer_rail_columns.dart | name': Why.aRow,
  // A header graph's own button (I-89 ③D): it enlarges the graph it
  // stands in over every other row, or lets it back.
  'timeline/timeline_lane_graph.dart | '
          "'\$keyPrefix-lane-graph-enlarge-\$groupKey'":
      Why.aRow,
  // Its pen (I-3, AE's): it takes up the pen of the graph it stands in,
  // and Ctrl held (Cmd on a Mac) is that pen from the keyboard.
  'timeline/timeline_lane_graph.dart | '
          "'\$keyPrefix-lane-graph-pen-\$groupKey'":
      Why.aRow,
  // Its transform box (AE's 「Show Transform Box」): it shows or hides the
  // box round the keys picked in the graph it stands in.
  'timeline/timeline_lane_graph.dart | '
          "'\$keyPrefix-lane-graph-box-\$groupKey'":
      Why.aRow,
  // Its snap (AE's 「Snap」, graph-key-drag-snaps): it turns the snap of the
  // graph it stands in on or off, and Ctrl held (Cmd on a Mac) during a
  // carry turns it the other way.
  'timeline/timeline_lane_graph.dart | '
          "'\$keyPrefix-lane-graph-snap-\$groupKey'":
      Why.aRow,
  'timeline/timeline_lane_rows.dart | '
          "'\$_keyPrefix-lane-group-fx-\${layer.id}-\${lane.laneId}'":
      Why.aRow,
  'timeline/timeline_lane_rows.dart | '
          "'\$_keyPrefix-lane-group-reset-\${layer.id}-\${lane.laneId}'":
      Why.aRow,
  'timeline/timeline_layer_controls_row.dart | '
          "'\$keyPrefix-layer-onion-\${layer.id}'":
      Why.aRow,
  // The buttons at the end of a name (F-409: one button since): the link
  // badge, a reference row's file and a camera's path — one line, as the
  // three pass their slug.
  'timeline/timeline_layer_controls_row.dart | '
          "'\$keyPrefix-layer-\$slug-\${layer.id}'":
      Why.aRow,
  'widgets/clip_button.dart | name': Why.aRow,
  // A menu row's own trailing button.
  'widgets/panel_flyout.dart | action.keyValue': Why.aRow,

  // ── A SETTING ───────────────────────────────────────────────────────
  // The scale's chain: a switch, on the transform tool's 배율 row and on
  // a layer's Scale lane alike — one button since tool-settings-panel-
  // tidy (2026-10-10); it stood on the lane row as that row's own.
  'widgets/scale_chain_button.dart | keyValue': Why.aSetting,
  'widgets/boolean_dot.dart | keyValue': Why.aSetting,
  // A value's ± — a bar's and a number box's, one pair since tool-settings-
  // panel-tidy (2026-10-10); they were the settings bar's own until then.
  'widgets/value_hands.dart | '
          "'\$keyPrefix-\${direction > 0 ? 'up' : 'down'}'":
      Why.aSetting,
  // The text tool's mirror (text-letters-lean-and-underline ⑦): a switch
  // of the held box's own `flipped`, the next text's when none is held.
  // The transform tool's flip names its action: it flips a selection,
  // not a value the tool keeps.
  "brush/text_tool_settings.dart | 'text-tool-flip-horizontal'":
      Why.aSetting,

  // ── THE DOOR TO A SECOND LEVEL ──────────────────────────────────────
  // A value's pencil: it opens the value's number pad and runs nothing.
  'widgets/value_hands.dart | keyValue': Why.aSecondLevel,
  "menu/editor_top_strip.dart | 'top-strip-brush-group-button'":
      Why.aSecondLevel,
  // The strip's popover buttons, made by one widget.
  'menu/editor_top_strip.dart | keyValue': Why.aSecondLevel,
  "timeline/timeline_action_toolbar.dart | 'timeline-effects-button'":
      Why.aSecondLevel,
  // A palette's ⋯ (I-131): it opens that palette's menu.
  "color/color_palettes.dart | 'palette-\${palette.id}-more'":
      Why.aSecondLevel,
  // The cut pill's name cell, read alone since its ＋ is zoned apart from
  // it round the cut's name (F-463) — the fx pill's door.
  "cut_command_group.dart | 'cut-menu-button'": Why.aSecondLevel,
  // The brush settings' wrench (I-141): it opens the brush's detail window
  // and runs nothing.
  "brush/brush_settings_panel.dart | 'brush-detail-button'":
      Why.aSecondLevel,

  // ── IN A WINDOW ─────────────────────────────────────────────────────
  "brush/brush_tip_picker.dart | 'brush-tip-delete'": Why.inAWindow,
  "brush/brush_tip_picker.dart | 'brush-tip-picker-add'": Why.inAWindow,
  "brush/brush_tip_picker.dart | 'brush-tip-rename'": Why.inAWindow,
  // A palette colour's delete, in that colour's double-click window
  // (I-131, 10-28).
  "color/color_palettes.dart | 'palette-place-delete'": Why.inAWindow,
  "debug/input_inspector.dart | 'input-inspector-clear'": Why.inAWindow,
  "debug/input_inspector.dart | 'input-inspector-close'": Why.inAWindow,
  "dialogs/audio_settings_section.dart | 'settings-audio-report-refresh'":
      Why.inAWindow,
  "dialogs/audio_settings_section.dart | 'settings-output-test-button'":
      Why.inAWindow,
  'dialogs/instruction_set_editor_dialog.dart | '
          "'instruction-def-delete-\${def.id}'":
      Why.inAWindow,
  'dialogs/instruction_set_editor_dialog.dart | '
          "'instruction-def-edit-\${def.id}'":
      Why.inAWindow,
  "dialogs/memory_settings_section.dart | 'memory-allowance-automatic'":
      Why.inAWindow,
  'shortcuts/shortcut_settings_dialog.dart | '
          "'shortcut-record-\${definition.id}'":
      Why.inAWindow,
  'shortcuts/shortcut_settings_dialog.dart | '
          "'shortcut-reset-\${definition.id}'":
      Why.inAWindow,
  'shortcuts/shortcut_settings_dialog.dart | '
          "'shortcut-unassign-\${definition.id}'":
      Why.inAWindow,
  "widgets/app_window.dart | 'app-window-close'": Why.inAWindow,
  // The number pad's keys (I-134): a window a value's pencil opens, whose
  // keys the keyboard's digits, minus, point, Enter and Escape press.
  "widgets/number_pad.dart | '\${widget.keyValue}-pad-\$name'":
      Why.inAWindow,

  // ── DECLINED ────────────────────────────────────────────────────────
  // 🗣️I-40-Q3 (유저 2026-10-09, two media viewers — which one would a key
  // take?): 「안만들기로했음」. The transport is one widget, which the import
  // and export windows mount too.
  "media/media_viewer_tab_host.dart | _key('open-file-button')":
      Why.declined,
  "media/media_viewer_tab_host.dart | _key('close-file-button')":
      Why.declined,
  "widgets/transport_bar.dart | _key('first')": Why.declined,
  "widgets/transport_bar.dart | _key('last')": Why.declined,
  "widgets/transport_bar.dart | _key('mute')": Why.declined,
  "widgets/transport_bar.dart | _key('play')": Why.declined,
  "widgets/transport_bar.dart | _key('step-back')": Why.declined,
  "widgets/transport_bar.dart | _key('step-forward')": Why.declined,
  // 🗣️I-40-Q4 (유저 2026-10-09, the strip's floor buttons and the rails'
  // group buttons — each panel already has its own open/close key):
  // 「둘 다 주지 않는다」.
  "editor_workspace.dart | 'rail-group-\$railId'": Why.declined,
  "menu/editor_top_strip.dart | 'top-strip-floor-\${tab.tabId}'":
      Why.declined,
  // 🗣️I-40-Q7 (유저 2026-10-10, the sheets' own pills — the 붓 that lets a
  // sheet take ink, on the timesheet, the conte and the cut envelope alike,
  // and the page turns of the first two: one button per panel, so which
  // panel's would a key press?): 「주지 않는다」. The viewers wear the same
  // button since I-114 (「다른 캔버스 베이스패널의 브러시 허용이랑 똑같은」),
  // one per viewer, so the same answer.
  "brush/sheet_canvas_panel.dart | '\$keyPrefix-brush-toggle-button'":
      Why.declined,
  "widgets/page_turn_bar.dart | '\$keyPrefix-next-page-button'":
      Why.declined,
  "widgets/page_turn_bar.dart | '\$keyPrefix-previous-page-button'":
      Why.declined,
};

void main() {
  final buttons = callsNamingAnActionUnder('lib/src/ui', const {
    'AppIconButton',
    '_barIconButton',
    'StrapIconButton',
    'RailButton',
    'RailGlyphButton',
    'CommandPill',
    'ToolSettingAction',
    'ToolSettingAction.glyph',
  }, what: 'button');

  test('⛔premise: the scan reaches the buttons — the bar spelling '
      'included — and the ones that are actions', () {
    expect(
      buttons.named,
      contains(
        "playback/playback_transport_controls.dart | 'playback-play-button'",
      ),
    );
    expect(
      buttons.named,
      contains(
        'brush/canvas_panel/viewport_bottom_bar_build.dart | '
        "'canvas-viewport-fit'",
      ),
      reason: 'the pill builds its buttons through `_bar._barIconButton`',
    );
    expect(buttons.silent, contains('widgets/app_window.dart | '
        "'app-window-close'"));
    expect(buttons.named.intersection(buttons.silent), isEmpty);
  });

  test('🚨a button that names no action is in the ledger, with why', () {
    expect(
      buttons.silent.difference(ledger.keys.toSet()),
      isEmpty,
      reason:
          'a new button: give it its action (`shortcuts:` — I-40), or '
          'write here why it is none',
    );
  });

  test('⛔and the ledger holds no button that is gone, or is an action by '
      'now', () {
    expect(
      ledger.keys.toSet().difference(buttons.silent),
      isEmpty,
      reason: 'take the line out — the list of what is owed only shrinks',
    );
  });
}
