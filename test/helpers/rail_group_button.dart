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

/// The scroll of the rail on the [right], or the left — the rail's OWN: the
/// panels inside carry scrollables of their own, so a descendant search
/// finds several.
Finder railScroll({required bool right}) =>
    find.byKey(ValueKey<String>('rail-scroll-${right ? 'right' : 'left'}'));

/// Where [railScroll] stands.
ScrollPosition railPosition(WidgetTester tester, {required bool right}) =>
    tester
        .widget<SingleChildScrollView>(railScroll(right: right))
        .controller!
        .position;

/// Brings the rail on the [right], or the left, to its end — its last group
/// all in the window, where a group the window cuts would be laid to the
/// part it shows. The caller settles as its fixture does.
Future<void> scrollRailToItsEnd(
  WidgetTester tester, {
  required bool right,
}) async {
  final rail = railPosition(tester, right: right);
  rail.jumpTo(rail.maxScrollExtent);
  await tester.pump();
}
