// EVERY PANEL'S EMPTY LINE IS THE ONE WIDGET, IN THE PLACE THE USER CHOSE.
//
// 유저 2026-09-15: 「공용 위젯 하나 + 짧은 한 줄」 (empty-state-law-Q1) and
// 「내용이 올 자리에」 (empty-state-placement-Q1) — a list says it where its
// first row would be, a stage says it in the middle.
//
// ⚠️A pump sees one line in one place, and passes just as well for a panel
// that went back to a `Text` of its own in the same spot. This reads the
// files instead and asks what a pump cannot: 「is the line the one widget,
// and is its place the one this panel was given」.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';

/// Every panel that says it has nothing — the place of each line it says,
/// in source order.
const _panels = <String, List<String>>{
  'lib/src/ui/brush/guide_panels.dart': ['list', 'list'],
  'lib/src/ui/brush/tool_library_panel.dart': ['list'],
  // ↩️Two until F-124 (2026-09-17): the cut tool's hint sat here wearing an
  // empty line's clothes, and it was not one — it was two sentences under a
  // control explaining what cutting does, which is what F-2 forbids. What is
  // left is the real empty state, the one that says nothing is held yet.
  'lib/src/ui/brush/tool_settings_panel.dart': ['list'],
  'lib/src/ui/export/export_preset_rail.dart': ['list'],
  'lib/src/ui/export/export_queue_column.dart': ['list'],
  'lib/src/ui/media/media_pool_panel.dart': ['list'],
  'lib/src/ui/media/media_viewer_tab_host.dart': ['stage'],
  'lib/src/ui/timeline/layer_grid/layer_grid_rail_rows.dart': ['list'],
  'lib/src/ui/timeline/xsheet_timeline_grid.dart': ['list'],
  'lib/src/ui/timeline_tab_host.dart': ['stage'],
  'lib/src/ui/timesheet_tab_host.dart': ['stage'],
};

/// One call of the widget, up to the place it names.
final _call = RegExp(
  r'EmptyStateText\([^;]*?place: EmptyStatePlace\.(\w+)',
  dotAll: true,
);

void main() {
  test('each panel says it has nothing in the place it was given', () {
    for (final MapEntry(key: path, value: places) in _panels.entries) {
      final source = File(path).readAsStringSync();
      expect(
        [for (final call in _call.allMatches(source)) call.group(1)],
        places,
        reason: '$path: its empty lines, in source order',
      );
    }
  });

  test('a panel that starts saying it has nothing is listed above', () {
    final unlisted = <String>[];
    for (final file in dartFilesUnder('lib/src/ui')) {
      final path = file.path.replaceAll(r'\', '/');
      final relative = path.substring(path.indexOf('lib/'));
      if (relative.endsWith('/widgets/empty_state_text.dart') ||
          _panels.containsKey(relative)) {
        continue;
      }
      if (file.readAsStringSync().contains('EmptyStateText(')) {
        unlisted.add(relative);
      }
    }
    expect(unlisted, isEmpty, reason: 'name the place each new line takes');
  });
}
