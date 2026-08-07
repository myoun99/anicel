import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/panels/editor_panel_layout.dart';

EditorPanelLayoutModel _model() => EditorPanelLayoutModel(
  docks: {
    'left': DockGroup(
      tabs: ['tools', 'brushes', 'camera'],
      activeTabId: 'brushes',
    ),
    'bottom': DockGroup(tabs: ['timeline', 'storyboard']),
    'right': null,
  },
);

void main() {
  group('EditorPanelLayoutModel', () {
    test('a dock is ONE group of tabs with one active', () {
      final model = _model();
      expect(model.tabsIn('left'), ['tools', 'brushes', 'camera']);
      expect(model.activeTabIn('left'), 'brushes');
      expect(model.activeTabIn('bottom'), 'timeline');
      expect(model.tabsIn('right'), isEmpty);
      expect(model.activeTabIn('right'), isNull);
      expect(model.locateTab('camera'), (dockId: 'left', tabIndex: 2));
      expect(model.locateTab('unknown'), isNull);
    });

    test('selectTab switches the active tab and notifies', () {
      final model = _model();
      var notified = 0;
      model.addListener(() => notified += 1);

      model.selectTab('left', 'camera');

      expect(model.activeTabIn('left'), 'camera');
      expect(notified, 1);
    });

    test('selectTab ignores unknown tabs, docks and re-selection', () {
      final model = _model();
      var notified = 0;
      model.addListener(() => notified += 1);

      model.selectTab('left', 'storyboard'); // not in this dock
      model.selectTab('left', 'brushes'); // already active
      model.selectTab('nope', 'camera'); // unknown dock
      model.selectTab('right', 'camera'); // empty dock

      expect(notified, 0);
    });

    test('same-dock move reorders with insertion-index semantics', () {
      final model = _model();

      model.moveTab(tabId: 'tools', toDockId: 'left', insertIndex: 2);

      expect(model.tabsIn('left'), ['brushes', 'tools', 'camera']);
    });

    test('same-dock move onto its own slot is a silent no-op', () {
      final model = _model();
      var notified = 0;
      model.addListener(() => notified += 1);

      model.moveTab(tabId: 'brushes', toDockId: 'left', insertIndex: 1);
      model.moveTab(tabId: 'brushes', toDockId: 'left', insertIndex: 2);

      expect(notified, 0);
    });

    test('cross-dock move joins the target group and activates', () {
      final model = _model();

      model.moveTab(tabId: 'camera', toDockId: 'bottom', insertIndex: 1);

      expect(model.tabsIn('left'), ['tools', 'brushes']);
      expect(model.tabsIn('bottom'), ['timeline', 'camera', 'storyboard']);
      expect(model.activeTabIn('bottom'), 'camera');
    });

    test('moving the active tab out falls back to a neighbour', () {
      final model = _model();

      model.moveTab(tabId: 'brushes', toDockId: 'bottom', insertIndex: 0);

      expect(model.activeTabIn('left'), 'camera');
    });

    test('a move into an EMPTY dock grows that dock its group', () {
      final model = _model();

      model.moveTab(tabId: 'camera', toDockId: 'right', insertIndex: 0);

      expect(model.tabsIn('right'), ['camera']);
      expect(model.activeTabIn('right'), 'camera');
      expect(model.tabsIn('left'), ['tools', 'brushes']);
    });

    test('a dock emptied by a move goes empty rather than disappearing', () {
      final model = EditorPanelLayoutModel(
        docks: {
          'left': DockGroup(tabs: ['camera']),
          'bottom': DockGroup(tabs: ['timeline']),
        },
      );

      model.moveTab(tabId: 'camera', toDockId: 'bottom', insertIndex: 0);

      expect(model.tabsIn('left'), isEmpty);
      // The id survives so the rail slot can be dropped into again.
      expect(model.dockIds, contains('left'));
      expect(model.tabsIn('bottom'), ['camera', 'timeline']);
    });

    test('removeTab hides a panel and addTab reopens it into the group', () {
      final model = _model();

      model.removeTab('brushes');
      expect(model.tabsIn('left'), ['tools', 'camera']);
      expect(model.activeTabIn('left'), 'camera');

      model.addTab('brushes', toDockId: 'left');
      expect(model.tabsIn('left'), ['tools', 'camera', 'brushes']);
    });

    test('addTab into an EMPTY dock grows its group', () {
      final model = _model();

      model.removeTab('camera');
      model.addTab('camera', toDockId: 'right');

      expect(model.tabsIn('right'), ['camera']);
      expect(model.activeTabIn('right'), 'camera');
    });

    test('unknown tabs or docks cannot move', () {
      final model = _model();
      expect(model.canMoveTab(tabId: 'nope', toDockId: 'left'), isFalse);
      expect(model.canMoveTab(tabId: 'tools', toDockId: 'nope'), isFalse);
      expect(model.canMoveTab(tabId: 'tools', toDockId: 'right'), isTrue);
    });

    test('dock extents clamp and notify', () {
      final model = _model();
      expect(model.dockExtent('left', fallback: 260), 260);

      model.resizeDock('left', 40, fallback: 260);
      expect(model.dockExtent('left', fallback: 260), 300);

      model.resizeDock('left', -1000, fallback: 260);
      expect(model.dockExtent('left', fallback: 260), 160);
    });

    test('a drag past the ceiling banks nothing to spend on the way back', () {
      // The reported "the splitter follows the cursor, but short and late":
      // without a ceiling the stored number kept climbing past what the
      // window could show, and the first N pixels of the drag back down
      // moved nothing.
      final model = _model();

      model.resizeDock('bottom', 10000, fallback: 350, maxExtent: 400);
      expect(model.dockExtent('bottom', fallback: 350), 400);

      model.resizeDock('bottom', -30, fallback: 350, maxExtent: 400);
      expect(model.dockExtent('bottom', fallback: 350), 370);
    });

    test('toJson/restore round-trips the layout', () {
      final model = _model();
      model.moveTab(tabId: 'camera', toDockId: 'right', insertIndex: 0);
      model.resizeDock('bottom', 50, fallback: 350);
      final json = model.toJson();

      final other = _model();
      final docksJson = (json['docks'] as Map).cast<String, Object?>();
      other.restore(
        docks: {
          for (final entry in docksJson.entries)
            entry.key: DockGroup(
              tabs: ((entry.value as Map)['tabs'] as List).cast<String>(),
              activeTabId: (entry.value as Map)['active'] as String,
            ),
        },
        dockExtents: (json['extents'] as Map).cast<String, double>(),
      );

      expect(other.tabsIn('left'), ['tools', 'brushes']);
      expect(other.tabsIn('right'), ['camera']);
      expect(other.dockExtent('bottom', fallback: 350), 400);
    });

    test('an emptied dock is not written out, and restore keeps its id', () {
      final model = _model();
      final json = model.toJson();
      expect((json['docks'] as Map).containsKey('right'), isFalse);
    });
  });
}
