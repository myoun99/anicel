import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/tool_setting_rows.dart';

/// Reads a tool's ACTION ([ToolSettingAction]) through the finder a test
/// holds for its KEY.
///
/// The key names the FACE — the box you see and press — so this climbs to
/// the widget whose public API `onPressed` and `decides` are, as
/// `AppIconButtonProbe` does for an icon button. ↩️The actions were
/// Material buttons until tool-settings-panel-tidy (2026-10-10), read
/// straight off the key with `tester.widget<FilledButton>(…)`.
extension ToolSettingActionProbe on WidgetTester {
  ToolSettingAction toolSettingAction(Finder face) =>
      widget<ToolSettingAction>(
        find.ancestor(of: face, matching: find.byType(ToolSettingAction)),
      );
}
