// A PANEL THE USER CLOSED STAYS CLOSED ON RESTORE; A PANEL THE SAVE MERELY
// NEVER KNEW (ADDED BY AN UPDATE) REJOINS ITS HOME DOCK.
//
// A mutant of the restoreWorkspaceLayout extraction (2026-09-03) dropped
// the hidden-tabs check from the rejoin step and every closed panel came
// back on launch — and the store's tests stayed green. This pin closes one
// panel and leaves another unknown.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/panels/editor_panel_layout.dart';
import 'package:anicel/src/ui/panels/workspace_layout_store.dart';

Map<String, DockGroup?> _defaults() => {
  'left': DockGroup(tabs: ['brushes', 'camera', 'newcomer']),
  'center': DockGroup(tabs: ['canvas']),
};

Map<String, Object?> _payload({List<String> hiddenTabs = const []}) => {
  'layout': {
    'docks': {
      'left': [
        {
          'tabs': ['camera'],
          'active': 'camera',
        },
      ],
      'center': [
        {
          'tabs': ['canvas'],
          'active': 'canvas',
        },
      ],
    },
  },
  'hiddenTabs': hiddenTabs,
};

void main() {
  test('a closed panel stays closed; an unknown one rejoins its home', () {
    final restored = restoreWorkspaceLayout(
      payload: _payload(hiddenTabs: ['brushes']),
      defaults: _defaults(),
    );
    expect(restored!.docks['left']!.tabs, ['camera', 'newcomer']);
  });

  test('with nothing closed, every missing tab rejoins', () {
    final restored = restoreWorkspaceLayout(
      payload: _payload(),
      defaults: _defaults(),
    );
    expect(restored!.docks['left']!.tabs, ['camera', 'brushes', 'newcomer']);
  });
}
