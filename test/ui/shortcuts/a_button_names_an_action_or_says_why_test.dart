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
///   · OWED — a command of the scope chosen above that is not an action
///     YET. The rounds of I-40 empty this list, and it only shrinks.
///   · ON A ROW — it acts on its own row or item (a layer's eye, a lane's
///     reset, a project tab's ✕): 「레이어 행의 눈 · 잠금 … 에는 키를 줄 수
///     없다」 was the cost 유저 took with the answer.
///   · A SETTING — one value of a choice, a switch, a step of a slider —
///     「도구 설정의 선택지 · 스위치」, the same cost.
///   · THE DOOR TO A SECOND LEVEL — it opens a menu or a popover and runs
///     nothing.
///   · IN A WINDOW — 「창 안의 버튼」, the answer's third exclusion.
///
/// ⚠️What is scanned: the app's ONE button (`AppIconButton`), the view
/// pill's spelling of it (`_barIconButton`), and the buttons that wrap it
/// and pass `shortcuts:` through (the strip's, the rail's, the command
/// pill). ⛔Not the kinds that are one of the answer's exclusions by what
/// they ARE — a boolean dot is a switch, a colour swatch a choice, a
/// flyout button a door, the layer row's toggles a row's — whose every use
/// would stand here with the same reason.
enum Why { owed, aRow, aSetting, aSecondLevel, inAWindow }

const ledger = <String, Why>{
  // ── OWED ────────────────────────────────────────────────────────────
  // The tool library's.
  "brush/brush_preset_panel.dart | 'brush-preset-import-button'": Why.owed,
  "brush/brush_preset_panel.dart | 'brush-preset-save-button'": Why.owed,
  'brush/guide_panels.dart | addKey': Why.owed,
  "brush/text_tool_settings.dart | 'text-tool-delete-text'": Why.owed,
  // The panels' own pills.
  'brush/sheet_canvas_panel.dart | '
          "'\${brush.keyPrefix}-brush-toggle-button'":
      Why.owed,
  'camera/camera_view_toggle_button.dart | keyValue': Why.owed,
  "media/media_pool_panel.dart | 'media-import-button'": Why.owed,
  "media/media_viewer_tab_host.dart | _key('open-file-button')": Why.owed,
  "media/media_viewer_tab_host.dart | _key('close-file-button')": Why.owed,
  "timeline/timeline_panel.dart | 'timeline-orientation-toggle-button'":
      Why.owed,
  'timeline/timeline_view_cluster.dart | zoomIn ? '
          "'timeline-zoom-in-button' : 'timeline-zoom-out-button'":
      Why.owed,
  "timesheet_tab_host.dart | 'timesheet-data-mode-toggle-button'": Why.owed,
  "timesheet_tab_host.dart | 'timesheet-format-button'": Why.owed,
  "widgets/page_turn_strip.dart | '\$keyPrefix-next-page-button'": Why.owed,
  "widgets/page_turn_strip.dart | '\$keyPrefix-previous-page-button'":
      Why.owed,
  // The media viewer's transport — one widget, which the import and export
  // windows mount too.
  "widgets/transport_bar.dart | _key('first')": Why.owed,
  "widgets/transport_bar.dart | _key('last')": Why.owed,
  "widgets/transport_bar.dart | _key('mute')": Why.owed,
  "widgets/transport_bar.dart | _key('play')": Why.owed,
  "widgets/transport_bar.dart | _key('step-back')": Why.owed,
  "widgets/transport_bar.dart | _key('step-forward')": Why.owed,
  // Opening and closing panels (「패널 열기 닫기같은거든」).
  "editor_workspace.dart | 'rail-group-\$railId'": Why.owed,
  "menu/editor_top_strip.dart | 'top-strip-floor-\${tab.tabId}'": Why.owed,
  "workspace/workspace_docks.dart | 'floating-bottom-collapse'": Why.owed,

  // ── ON A ROW ────────────────────────────────────────────────────────
  "brush/guide_panels.dart | 'guide-delete-\${guide.id.value}'": Why.aRow,
  "brush/guide_panels.dart | 'guide-make-vertical'": Why.aRow,
  "brush/guide_panels.dart | 'guide-remove'": Why.aRow,
  "brush/guide_panels.dart | 'guide-rename-\${guide.id.value}'": Why.aRow,
  "media/media_pool_panel.dart | 'media-asset-in-use-\${asset.path}'":
      Why.aRow,
  "menu/editor_top_strip.dart | 'project-tab-close-\$index'": Why.aRow,
  'timeline/layer_label_controls.dart | '
          "'\$keyPrefix-layer-timesheet-\$layerId'":
      Why.aRow,
  'timeline/layer_label_controls.dart | keyValue': Why.aRow,
  'timeline/layer_label_controls.dart | widget.keyValue': Why.aRow,
  'timeline/timeline_lane_rows.dart | '
          "'\$_keyPrefix-lane-group-fx-\${layer.id}-\${lane.laneId}'":
      Why.aRow,
  'timeline/timeline_lane_rows.dart | '
          "'\$_keyPrefix-lane-group-reset-\${layer.id}-\${lane.laneId}'":
      Why.aRow,
  'timeline/timeline_lane_rows.dart | '
          "'\$_keyPrefix-lane-value-link-\${layer.id}-\${lane.laneId}'":
      Why.aRow,
  'timeline/timeline_layer_controls_row.dart | '
          "'\$keyPrefix-lane-toggle-\${layer.id}'":
      Why.aRow,
  'timeline/timeline_layer_controls_row.dart | '
          "'\$keyPrefix-layer-link-badge-\${layer.id}'":
      Why.aRow,
  'timeline/timeline_layer_controls_row.dart | '
          "'\$keyPrefix-layer-onion-\${layer.id}'":
      Why.aRow,
  'widgets/fill_reference_button.dart | keyValue': Why.aRow,
  // A menu row's own trailing button.
  'widgets/panel_flyout.dart | action.keyValue': Why.aRow,

  // ── A SETTING ───────────────────────────────────────────────────────
  "brush/tool_settings_panel.dart | 'selection-mode-\${candidate.name}'":
      Why.aSetting,
  "envelope/cut_envelope_tab_host.dart | 'envelope-form-\${form.id}'":
      Why.aSetting,
  'widgets/boolean_dot.dart | keyValue': Why.aSetting,
  'widgets/field_slider.dart | '
          "'field-slider-step-\${direction > 0 ? 'up' : 'down'}'":
      Why.aSetting,

  // ── THE DOOR TO A SECOND LEVEL ──────────────────────────────────────
  "menu/editor_top_strip.dart | 'top-strip-brush-group-button'":
      Why.aSecondLevel,
  // The strip's popover buttons, made by one widget.
  'menu/editor_top_strip.dart | keyValue': Why.aSecondLevel,
  "timeline/timeline_action_toolbar.dart | 'timeline-effects-button'":
      Why.aSecondLevel,

  // ── IN A WINDOW ─────────────────────────────────────────────────────
  "brush/brush_tip_picker.dart | 'brush-tip-delete'": Why.inAWindow,
  "brush/brush_tip_picker.dart | 'brush-tip-picker-add'": Why.inAWindow,
  "brush/brush_tip_picker.dart | 'brush-tip-rename'": Why.inAWindow,
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
};

void main() {
  final buttons = callsNamingAnActionUnder('lib/src/ui', const {
    'AppIconButton',
    '_barIconButton',
    'StrapIconButton',
    'RailButton',
    'CommandPill',
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
