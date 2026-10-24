import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/editor_workspace.dart';

/// The key of the rail button that opens and closes the rail group
/// [railId] — the one spelling of it among the tests, for a helper of their
/// own that presses a key by name.
String railGroupButtonKey(String railId) => 'rail-group-$railId';

/// The rail button that opens and closes the rail group [railId].
Finder railGroupButton(String railId) =>
    find.byKey(ValueKey<String>(railGroupButtonKey(railId)));

/// The tool settings' rail group: their own slot under the library's, and it
/// ships closed (「툴라이브러리 버튼, 그 밑에 툴설정 버튼」, 유저 확정 R3 #10).
final String toolSettingsGroupId = EditorWorkspace.railGroupId(
  right: false,
  slot: 2,
);

/// Presses the tool settings' rail button — opening them where they ship
/// closed. The caller settles as its fixture does.
Future<void> pressToolSettingsButton(WidgetTester tester) =>
    tester.tap(railGroupButton(toolSettingsGroupId));
