import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/panels/editor_panel_layout.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';

/// Two draggable tab groups wired to one layout model, the way the
/// workspace docks are.
class _Harness extends StatelessWidget {
  const _Harness({
    required this.model,
    this.lockedTabIds = const {},
    this.width,
  });

  final EditorPanelLayoutModel model;
  final Set<String> lockedTabIds;

  /// How much room the groups get across. Null = whatever the surface has,
  /// which is every test here but the compression one.
  final double? width;

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
    final tabIds = model.tabsIn(dockId);
    if (tabIds.isEmpty) {
      return DragTarget<EditorPanelTabDragData>(
        onAcceptWithDetails: (details) => model.moveTab(
          tabId: details.data.tabId,
          toDockId: dockId,
          insertIndex: 0,
        ),
        builder: (context, _, _) =>
            SizedBox.expand(key: ValueKey<String>('empty-group-$dockId')),
      );
    }
    return EditorPanelTabs(
      groupId: dockId,
      tabs: [
        for (final id in tabIds)
          EditorPanelTab(
            id: id,
            label: id.toUpperCase(),
            icon: _icons[id]!,
            locked: lockedTabIds.contains(id),
            builder: (context) => Text('content-$id'),
          ),
      ],
      activeTabId: model.activeTabIn(dockId)!,
      onTabSelected: (tabId) => model.selectTab(dockId, tabId),
      canAcceptTab: (data) =>
          model.canMoveTab(tabId: data.tabId, toDockId: dockId),
      onTabMoved: (data, insertIndex) => model.moveTab(
        tabId: data.tabId,
        toDockId: dockId,
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
              SizedBox(width: width, height: 150, child: _group('one')),
              SizedBox(width: width, height: 150, child: _group('two')),
            ],
          ),
        ),
      ),
    );
  }
}

EditorPanelLayoutModel _twoGroups() => EditorPanelLayoutModel(
  docks: {
    'one': DockGroup(tabs: ['a', 'b', 'c']),
    'two': DockGroup(tabs: ['x', 'y']),
  },
);

List<String> _tabsIn(EditorPanelLayoutModel model, String dockId) =>
    model.tabsIn(dockId);

Finder _tab(String id) => find.byKey(ValueKey<String>('panel-tab-$id'));

/// The lift zone. It is an 8px strip of the tab's leading edge now, not a
/// glyph — so it is found by KEY. A finder that looked for the three dots
/// would go quiet the moment they were replaced, which is exactly what a
/// drag test must not do.
Finder _grip(String id) => find.byKey(ValueKey<String>('panel-grip-$id'));

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
  testWidgets('the band is the GRIP ladder and nothing else: invisible '
      'until the panel is under the pointer', (tester) async {
    // 유저, R3 #9. The band carried two jobs — "this panel is open" and "you
    // may drag me" — and the first always won, so the tab you were most
    // likely to want to drag was the one tab whose band could never offer
    // itself. It is the handle now, on three rungs: the PANEL is hovered
    // (기본색) → the band itself is (호버색) → it is being dragged (클릭색).
    final model = _twoGroups();
    await tester.pumpWidget(_Harness(model: model));

    Color bandOf(String id) => tester
        .widget<ColoredBox>(
          find.descendant(of: _grip(id), matching: find.byType(ColoredBox)),
        )
        .color;

    // One band per tab, spanning the tab and lying on its top edge (the
    // strip is above the body here).
    final tab = tester.getRect(_tab('a'));
    final band = tester.getRect(_grip('a'));
    expect(band.width, closeTo(tab.width, 0.5));
    expect(band.top, closeTo(tab.top, 0.5));

    // ★THE BAND ITSELF, not the 8px zone that holds it.
    //
    // The zone's rect above says nothing about what is drawn inside it, and
    // that gap hid the band completely: `Align` hands its child LOOSE
    // constraints, and a `ColoredBox` with no child takes
    // `constraints.smallest` — so a band given only a HEIGHT laid out 0px
    // wide. Coloured, painted, on the right edge, and invisible (유저, R4 #6:
    // 띠를 드래그해서 이동은 가능한데 그 띠 ui가 없어). The same trap
    // collapsed a grip's height in R1a; a `ColoredBox` must be told BOTH.
    final painted = tester.getRect(
      find.descendant(of: _grip('a'), matching: find.byType(ColoredBox)),
    );
    expect(painted.width, closeTo(tab.width, 0.5));
    expect(painted.height, greaterThan(0));

    // At rest NEITHER band says anything — not even the open one.
    expect(bandOf('a'), Colors.transparent);
    expect(bandOf('b'), Colors.transparent);

    // A pointer anywhere on the panel raises every band it can lift.
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    await pointer.moveTo(tester.getCenter(find.byType(EditorPanelTabs).first));
    await tester.pumpAndSettle();
    expect(bandOf('a'), isNot(Colors.transparent));
    expect(bandOf('b'), isNot(Colors.transparent));

    // And when the hand leaves they go quiet again — which tab is OPEN is
    // said by the tab's own fill, not by the band.
    await pointer.removePointer();
    await tester.pumpAndSettle();
    expect(bandOf('a'), Colors.transparent);
  });

  testWidgets('유저 R4 #1: a seam separates the tab strip from the body, and '
      'the OPEN tab cuts its own gap in it', (tester) async {
    // 패널 아이콘쪽 영역 밑에 가로선 둬서 탭이랑 내용 구분할 수 있게 하자.
    //
    // The strip fill and the body fill are the same colour, so before this
    // line there was nothing at all between them. The line has to stop under
    // the open tab, though, or it would cut through the one seam the panel
    // spends a contract keeping invisible (「선택 탭은 패널의 발」) — so it is
    // painted UNDER the tabs and the selected tab's opaque fill erases it.
    //
    // ⚠️Pixels, not widget geometry: "there is a `ColoredBox` in the tree" is
    // exactly what a 0px-wide band would also have satisfied two tests up.
    final model = _twoGroups();
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey<String>('seam-capture'),
        child: _Harness(model: model),
      ),
    );
    await tester.pumpAndSettle();

    final seam = tester.getRect(
      find.byKey(const ValueKey<String>('panel-strip-seam')).first,
    );
    final strip = tester.getRect(find.byType(EditorPanelTabs).first);
    expect(seam.height, 1, reason: 'a hairline, not a band');
    expect(
      seam.bottom,
      closeTo(strip.top + EditorPanelTabs.stripHeight, 0.5),
      reason: 'it lies ON the boundary the strip shares with the body',
    );

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey<String>('seam-capture')),
    );
    final image = boundary.toImageSync();
    late Uint8List bytes;
    late int rowStride;
    await tester.runAsync(() async {
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      bytes = data!.buffer.asUint8List();
      rowStride = image.width;
    });
    image.dispose();
    int rgbAt(double x, double y) {
      final i = (y.round() * rowStride + x.round()) * 4;
      return (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
    }

    // 'a' is the open tab in group one; 'b' is not.
    //
    // ⚠️Sample the seam's OWN row. `seam.top + 0.5` rounds to the row below
    // it, which is the body — and the body is what a missing line looks
    // like, so the test would have passed for the wrong reason on one of
    // the three probes and failed on the others.
    final seamY = seam.top;
    final scheme = Theme.of(
      tester.element(find.byType(EditorPanelTabs).first),
    ).colorScheme;
    final line = scheme.outlineVariant.toARGB32() & 0xFFFFFF;
    final body = scheme.surface.toARGB32() & 0xFFFFFF;

    expect(
      rgbAt(tester.getCenter(_tab('a')).dx, seamY),
      body,
      reason: 'the OPEN tab reaches the body — no line across its foot',
    );
    expect(
      rgbAt(tester.getCenter(_tab('b')).dx, seamY),
      line,
      reason: 'a closed tab sits ON the strip, so the seam runs under it',
    );
    expect(
      rgbAt(strip.right - 4, seamY),
      line,
      reason: 'and across the empty tail of the strip',
    );
  });

  testWidgets('a tab fills the strip: the selected fill reaches the panel '
      'body and the glyph is centred', (tester) async {
    // The band moved into a Stack over the tab, and a Stack's default LOOSE
    // fit handed the tab's body loosened constraints — so it shrank to its
    // 16px glyph at the top of a 30px strip. The selected tab's fill stopped
    // reaching the body it is supposed to merge into (a 14px seam of strip
    // colour appeared under it) and every glyph rode 7px high.
    final model = _twoGroups();
    await tester.pumpWidget(_Harness(model: model));

    final tab = tester.getRect(_tab('a'));
    expect(tab.height, EditorPanelTabs.stripHeight);

    final body = tester.getRect(
      find.descendant(of: _tab('a'), matching: find.byType(Container)).first,
    );
    expect(
      body.height,
      closeTo(tab.height, 0.5),
      reason: 'the fill runs the strip, so the seam to the body closes',
    );
    final icon = tester.getRect(
      find.descendant(of: _tab('a'), matching: find.byType(Icon)).first,
    );
    expect(icon.center.dy, closeTo(tab.center.dy, 0.5));
  });

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
    expect(model.activeTabIn('two'), 'a');
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
        'one': DockGroup(tabs: ['a', 'b', 'c']),
        'two': DockGroup(tabs: ['x']),
      },
    );
    await tester.pumpWidget(_Harness(model: model));

    await _dragTab(tester, 'x', _tabHalf(tester, 'b', right: false));

    expect(_tabsIn(model, 'one'), ['a', 'x', 'b', 'c']);
    expect(model.tabsIn('two'), isEmpty);
  });

  testWidgets('a tab can drop into an emptied group\'s drop target', (
    tester,
  ) async {
    final model = EditorPanelLayoutModel(
      docks: {
        'one': DockGroup(tabs: ['a', 'b', 'c']),
        'two': DockGroup(tabs: ['x']),
      },
    );
    await tester.pumpWidget(_Harness(model: model));
    await _dragTab(tester, 'x', _tabHalf(tester, 'b', right: false));
    expect(model.tabsIn('two'), isEmpty);

    final emptyGroup = find.byKey(const ValueKey<String>('empty-group-two'));
    await _dragTab(tester, 'x', tester.getCenter(emptyGroup));

    expect(_tabsIn(model, 'two'), ['x']);
    expect(model.activeTabIn('two'), 'x');
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

  testWidgets('a strip with no room COMPRESSES into an overflow rather than '
      'scrolling', (tester) async {
    final model = EditorPanelLayoutModel(
      docks: {
        'one': DockGroup(tabs: ['a', 'b', 'c', 'x']),
        'two': DockGroup(tabs: ['y']),
      },
    );
    // A tab costs 32 across, so three fit in 100 — and the overflow button
    // spends one of those slots on itself.
    await tester.pumpWidget(_Harness(model: model, width: 100));

    expect(_tab('a'), findsOneWidget);
    expect(_tab('b'), findsOneWidget);
    expect(_tab('c'), findsNothing);
    expect(_tab('x'), findsNothing);

    // ★띠는 스크롤하지 않는다 (유저 확정), and the reason is gesture rather
    // than taste: inside a scroller the drag that MOVES a panel is taken by
    // the scroll arena before the tab under the finger ever sees it.
    expect(
      find.descendant(
        of: find.byType(EditorPanelTabs).first,
        matching: find.byType(Scrollable),
      ),
      findsNothing,
    );

    final overflow = find.byKey(
      const ValueKey<String>('panel-tab-overflow-one'),
    );
    expect(overflow, findsOneWidget);
    await tester.tap(overflow);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('panel-tab-overflow-item-x')),
    );
    await tester.pumpAndSettle();

    // What did not fit is still REACHABLE — and compression hides the tail,
    // it never reorders the strip.
    expect(model.activeTabIn('one'), 'x');
    expect(find.text('content-x'), findsOneWidget);
    expect(_tabsIn(model, 'one'), ['a', 'b', 'c', 'x']);
  });

  testWidgets('plain taps still switch tabs on a draggable strip', (
    tester,
  ) async {
    final model = _twoGroups();
    await tester.pumpWidget(_Harness(model: model));
    expect(find.text('content-a'), findsOneWidget);

    await tester.tap(_tab('b'));
    await tester.pumpAndSettle();

    expect(model.activeTabIn('one'), 'b');
    expect(find.text('content-b'), findsOneWidget);
    expect(_tabsIn(model, 'one'), ['a', 'b', 'c']);
  });
}
