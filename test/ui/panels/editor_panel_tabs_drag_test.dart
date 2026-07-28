import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/panels/editor_panel_layout.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';

/// Two draggable single-section tab groups wired to one layout model, the
/// way the workspace dock sections are.
class _Harness extends StatelessWidget {
  const _Harness({required this.model, this.lockedTabIds = const {}});

  final EditorPanelLayoutModel model;
  final Set<String> lockedTabIds;

  static const Map<String, IconData> _icons = {
    'a': Icons.abc,
    'b': Icons.brush,
    'c': Icons.camera,
    'x': Icons.close,
    'y': Icons.face,
  };

  Widget _group(String dockId) {
    // Empty docks collapse in the real dock layout; a bare drop target
    // stands in for the workspace's drop rail here.
    if (model.sectionsIn(dockId).isEmpty) {
      return DragTarget<EditorPanelTabDragData>(
        onAcceptWithDetails: (details) => model.moveTabToNewSection(
          tabId: details.data.tabId,
          toDockId: dockId,
          atSectionIndex: 0,
        ),
        builder: (context, _, _) =>
            SizedBox.expand(key: ValueKey<String>('empty-group-$dockId')),
      );
    }
    final section = model.sectionsIn(dockId).single;
    return EditorPanelTabs(
      groupId: dockId,
      tabs: [
        for (final id in section.tabs)
          EditorPanelTab(
            id: id,
            label: id.toUpperCase(),
            icon: _icons[id]!,
            locked: lockedTabIds.contains(id),
            builder: (context) => Text('content-$id'),
          ),
      ],
      activeTabId: section.activeTabId,
      onTabSelected: (tabId) => model.selectTab(dockId, 0, tabId),
      canAcceptTab: (data) =>
          model.canMoveTab(tabId: data.tabId, toDockId: dockId),
      onTabMoved: (data, insertIndex) => model.moveTabToSection(
        tabId: data.tabId,
        toDockId: dockId,
        toSectionIndex: 0,
        insertIndex: insertIndex,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: model,
          builder: (context, _) => Column(
            children: [
              SizedBox(height: 150, child: _group('one')),
              SizedBox(height: 150, child: _group('two')),
            ],
          ),
        ),
      ),
    );
  }
}

EditorPanelLayoutModel _twoGroups() => EditorPanelLayoutModel(
  docks: {
    'one': [
      DockSection(tabs: ['a', 'b', 'c']),
    ],
    'two': [
      DockSection(tabs: ['x', 'y']),
    ],
  },
);

List<String> _tabsIn(EditorPanelLayoutModel model, String dockId) {
  final sections = model.sectionsIn(dockId);
  return sections.isEmpty ? const [] : sections.single.tabs;
}

Finder _tab(String id) => find.byKey(ValueKey<String>('panel-tab-$id'));

Finder _grip(String id) =>
    find.descendant(of: _tab(id), matching: find.byIcon(Icons.drag_indicator));

/// Drags a tab to [target] by its GRIP (R10-⑩: only the grip lifts).
Future<void> _dragTab(WidgetTester tester, String id, Offset target) async {
  final gesture = await tester.startGesture(tester.getCenter(_grip(id)));
  await tester.pump(const Duration(milliseconds: 20));
  // Two hops so DragTarget onMove sees the final hover position.
  await gesture.moveTo(target + const Offset(0, -10));
  await tester.pump();
  await gesture.moveTo(target);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// A point on the left or right half of a tab button.
Offset _tabHalf(WidgetTester tester, String id, {required bool right}) {
  final center = tester.getCenter(_tab(id));
  final edgeX = right
      ? tester.getTopRight(_tab(id)).dx - 3
      : tester.getTopLeft(_tab(id)).dx + 3;
  return Offset(edgeX, center.dy);
}

void main() {
  testWidgets('dropping on a tab\'s right half inserts after it', (
    tester,
  ) async {
    final model = _twoGroups();
    await tester.pumpWidget(_Harness(model: model));

    await _dragTab(tester, 'a', _tabHalf(tester, 'c', right: true));

    expect(_tabsIn(model, 'one'), ['b', 'c', 'a']);
  });

  testWidgets('dropping on a tab\'s left half inserts before it', (
    tester,
  ) async {
    final model = _twoGroups();
    await tester.pumpWidget(_Harness(model: model));

    await _dragTab(tester, 'c', _tabHalf(tester, 'a', right: false));

    expect(_tabsIn(model, 'one'), ['c', 'a', 'b']);
  });

  testWidgets('dropping on the strip tail appends to that group', (
    tester,
  ) async {
    final model = _twoGroups();
    await tester.pumpWidget(_Harness(model: model));

    // Well to the right of the last tab of group two = its strip tail.
    final tail = tester.getCenter(_tab('y')) + const Offset(200, 0);
    await _dragTab(tester, 'a', tail);

    expect(_tabsIn(model, 'one'), ['b', 'c']);
    expect(_tabsIn(model, 'two'), ['x', 'y', 'a']);
    // A re-docked tab becomes active in its new group.
    expect(model.sectionsIn('two').single.activeTabId, 'a');
    expect(find.text('content-a'), findsOneWidget);
  });

  testWidgets('cross-group drop on a tab half lands at that index', (
    tester,
  ) async {
    final model = _twoGroups();
    await tester.pumpWidget(_Harness(model: model));

    await _dragTab(tester, 'b', _tabHalf(tester, 'y', right: false));

    expect(_tabsIn(model, 'one'), ['a', 'c']);
    expect(_tabsIn(model, 'two'), ['x', 'b', 'y']);
  });

  testWidgets('a group\'s last tab can leave, emptying the group', (
    tester,
  ) async {
    final model = EditorPanelLayoutModel(
      docks: {
        'one': [
          DockSection(tabs: ['a', 'b', 'c']),
        ],
        'two': [
          DockSection(tabs: ['x']),
        ],
      },
    );
    await tester.pumpWidget(_Harness(model: model));

    await _dragTab(tester, 'x', _tabHalf(tester, 'b', right: false));

    expect(_tabsIn(model, 'one'), ['a', 'x', 'b', 'c']);
    expect(model.sectionsIn('two'), isEmpty);
  });

  testWidgets('a tab can drop into an emptied group\'s drop target', (
    tester,
  ) async {
    final model = EditorPanelLayoutModel(
      docks: {
        'one': [
          DockSection(tabs: ['a', 'b', 'c']),
        ],
        'two': [
          DockSection(tabs: ['x']),
        ],
      },
    );
    await tester.pumpWidget(_Harness(model: model));
    await _dragTab(tester, 'x', _tabHalf(tester, 'b', right: false));
    expect(model.sectionsIn('two'), isEmpty);

    final emptyGroup = find.byKey(const ValueKey<String>('empty-group-two'));
    await _dragTab(tester, 'x', tester.getCenter(emptyGroup));

    expect(_tabsIn(model, 'two'), ['x']);
    expect(model.sectionsIn('two').single.activeTabId, 'x');
  });

  testWidgets('locked tabs refuse to lift', (tester) async {
    final model = _twoGroups();
    await tester.pumpWidget(_Harness(model: model, lockedTabIds: const {'a'}));

    // A locked tab keeps its grip VISIBLE but inert (R12-⑨: locking must
    // never reshape the tab); dragging it moves nothing.
    expect(_grip('a'), findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(_grip('a')));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(_tabHalf(tester, 'y', right: false));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_tabsIn(model, 'one'), ['a', 'b', 'c']);
    expect(_tabsIn(model, 'two'), ['x', 'y']);
  });

  testWidgets('plain taps still switch tabs on a draggable strip', (
    tester,
  ) async {
    final model = _twoGroups();
    await tester.pumpWidget(_Harness(model: model));
    expect(find.text('content-a'), findsOneWidget);

    await tester.tap(_tab('b'));
    await tester.pumpAndSettle();

    expect(model.sectionsIn('one').single.activeTabId, 'b');
    expect(find.text('content-b'), findsOneWidget);
    expect(_tabsIn(model, 'one'), ['a', 'b', 'c']);
  });
}
