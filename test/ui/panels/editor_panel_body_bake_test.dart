import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/input/pen_friendly_scroll_controller.dart';
import 'package:anicel/src/ui/panels/editor_panel_body.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:anicel/src/ui/panels/editor_panel_frame.dart';
import 'package:anicel/src/ui/theme/app_scroll_behavior.dart';
import 'package:anicel/src/ui/widgets/app_scrollbar.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';

/// The contract behind "a new panel is light without its author doing
/// anything": whatever goes through the shared body gets baked, and the
/// bake sits INSIDE the scroll view so scrolling is a layer offset
/// rather than a re-raster.
///
/// Both halves are load-bearing and neither is visible by inspection —
/// a panel that lost its bake looks exactly like one that has it.
class _CountingPainter extends CustomPainter {
  _CountingPainter(this.counter);

  final List<int> counter;

  @override
  void paint(Canvas canvas, Size size) {
    counter[0] += 1;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF123456));
  }

  @override
  bool shouldRepaint(_CountingPainter oldDelegate) => false;
}

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 260, height: 300, child: child)),
);

void main() {
  testWidgets('the shared body bakes its child, scrolling or not', (
    tester,
  ) async {
    for (final scrolls in <bool>[true, false]) {
      await tester.pumpWidget(
        _host(
          EditorPanelBody(
            scrollable: scrolls,
            debugLabel: 'probe',
            child: const SizedBox(height: 100),
          ),
        ),
      );
      expect(
        find.byType(StaticRaster),
        findsOneWidget,
        reason: 'a panel body is baked whether or not it scrolls ($scrolls)',
      );
    }
  });

  testWidgets('the bake is INSIDE the scroll view, not around it', (
    tester,
  ) async {
    // A viewport is itself a repaint boundary, so a bake wrapped AROUND
    // a scrolling body can never capture anything — it would find the
    // viewport and paint through, silently, forever. This is the
    // assertion that would have caught that.
    await tester.pumpWidget(
      _host(
        const EditorPanelBody(
          debugLabel: 'probe',
          child: SizedBox(height: 100),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(StaticRaster),
      ),
      findsOneWidget,
    );
    final render = tester.renderObject<RenderStaticRaster>(
      find.byType(StaticRaster),
    );
    expect(
      render.debugNestedBoundary,
      isFalse,
      reason: 'nothing in the way: ${render.debugNestedBoundaryPath}',
    );
    expect(render.captureCount, 1, reason: 'and it actually baked');
  });

  testWidgets('scrolling a baked body does not re-bake it', (tester) async {
    final counter = <int>[0];
    await tester.pumpWidget(
      _host(
        EditorPanelBody(
          debugLabel: 'probe',
          child: SizedBox(
            height: 900,
            child: CustomPaint(painter: _CountingPainter(counter)),
          ),
        ),
      ),
    );
    final render = tester.renderObject<RenderStaticRaster>(
      find.byType(StaticRaster),
    );
    final baked = render.captureCount;
    expect(baked, 1);
    expect(counter[0], 1);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -200));
    await tester.pump();
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -200));
    await tester.pump();

    expect(
      render.captureCount,
      baked,
      reason:
          'the viewport composites a boundaried child at the new offset — '
          'scrolling is a layer move, not a repaint',
    );
    expect(counter[0], 1);
  });

  testWidgets('a tab that overflows its dock keeps baking', (tester) async {
    // The cost CLIFF this guards: `EditorPanelTabs` puts a panel whose
    // minimum size exceeds the dock inside a `SingleChildScrollView`, and
    // a viewport is a repaint boundary. A bake around the outside would
    // therefore stand down — but only once the dock is narrow enough to
    // overflow, so the panel would bake in a wide window, silently pay
    // full raster price in a narrow one, and no test that pumps a single
    // window size would ever notice.
    final counter = <int>[0];
    Widget tabsAt(double width) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: 300,
          child: EditorPanelTabs(
            tabs: <EditorPanelTab>[
              EditorPanelTab(
                id: 'probe',
                label: 'Probe',
                icon: Icons.circle,
                minContentWidth: 400,
                builder: (context) =>
                    CustomPaint(painter: _CountingPainter(counter)),
              ),
            ],
            activeTabId: 'probe',
            onTabSelected: (_) {},
          ),
        ),
      ),
    );

    for (final width in <double>[600, 200]) {
      await tester.pumpWidget(tabsAt(width));
      await tester.pump();
      final render = tester.renderObject<RenderStaticRaster>(
        find.byType(StaticRaster),
      );
      expect(
        render.debugNestedBoundary,
        isFalse,
        reason:
            'at width $width the bake must sit inside the overflow '
            'scroller, not around it: ${render.debugNestedBoundaryPath}',
      );
      expect(
        render.captureCount,
        greaterThan(0),
        reason: 'at width $width the panel must actually bake',
      );
    }
  });

  testWidgets('a framed panel names its bake after the panel', (tester) async {
    await tester.pumpWidget(
      _host(
        const EditorPanelFrame(
          title: 'Probe',
          child: SizedBox(height: 100),
        ),
      ),
    );
    final render = tester.renderObject<RenderStaticRaster>(
      find.byType(StaticRaster),
    );
    expect(
      render.debugLabel,
      'body:Probe',
      reason: 'the standing report has to say WHICH panel it is talking about',
    );
  });

  testWidgets('🐛F-103: a panel keeps its State when its dock crosses the '
      'floor and back, or folds — a neighbour opening or closing must not '
      'remount it', (tester) async {
    Widget tabsAt(Size size, {required bool keepAlive, required bool folded}) =>
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: size.width,
              height: size.height,
              child: EditorPanelTabs(
                collapsed: folded,
                tabs: <EditorPanelTab>[
                  EditorPanelTab(
                    id: 'probe',
                    label: 'Probe',
                    icon: Icons.circle,
                    minContentWidth: 400,
                    minContentHeight: 250,
                    collapsedExtent: 40,
                    keepAlive: keepAlive,
                    builder: (context) => const _StateProbe(),
                  ),
                ],
                activeTabId: 'probe',
                onTabSelected: (_) {},
              ),
            ),
          ),
        );
    Map<Axis, double> reach() => {
      for (final scroller in tester.stateList<ScrollableState>(
        find.ancestor(
          of: find.byType(_StateProbe),
          matching: find.byType(Scrollable),
        ),
      ))
        axisDirectionToAxis(scroller.axisDirection):
            scroller.position.maxScrollExtent,
    };

    for (final keepAlive in const [false, true]) {
      await tester.pumpWidget(const SizedBox());
      final states = <State>{};
      final reaches = <(Size, bool, Map<Axis, double>)>[];
      for (final (size, folded) in const [
        (Size(600, 400), false),
        (Size(200, 400), false),
        (Size(600, 400), false),
        (Size(600, 150), false),
        (Size(200, 150), false),
        (Size(200, 150), true),
        (Size(600, 400), true),
        (Size(600, 400), false),
      ]) {
        await tester.pumpWidget(
          tabsAt(size, keepAlive: keepAlive, folded: folded),
        );
        await tester.pump();
        states.add(tester.state(find.byType(_StateProbe)));
        reaches.add((size, folded, reach()));
      }
      expect(
        states,
        hasLength(1),
        reason:
            'keepAlive: $keepAlive — fits, over on x, over on y, over on '
            'both, folded — one State throughout',
      );
      for (final (size, folded, reached) in reaches) {
        final step = '$size${folded ? ' folded' : ''}, keepAlive: $keepAlive';
        expect(
          reached[Axis.horizontal],
          !folded && size.width < 400 ? greaterThan(0) : 0,
          reason: '$step — sideways, only under the floor and never folded',
        );
        expect(
          reached[Axis.vertical],
          !folded && size.height < 250 ? greaterThan(0) : 0,
          reason: '$step — up and down, only under the floor and never folded',
        );
      }
    }
  });

  testWidgets('two kept tabs with floors in one group each scroll on their '
      'own — the shown one still says so with its bar after the dock moves, '
      'and a pen still reaches through its coast', (tester) async {
    Widget groupShowing(String active, double height) => MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: height,
          child: EditorPanelTabs(
            tabs: <EditorPanelTab>[
              for (final id in const ['a', 'b'])
                EditorPanelTab(
                  id: id,
                  label: id,
                  icon: Icons.circle,
                  keepAlive: true,
                  minContentHeight: 600,
                  builder: (context) =>
                      _StateProbe(key: ValueKey<String>('probe-$id')),
                ),
            ],
            activeTabId: active,
            onTabSelected: (_) {},
          ),
        ),
      ),
    );
    Iterable<ScrollableState> scrollersOf(String id) =>
        tester.stateList<ScrollableState>(
          find.ancestor(
            of: find.byKey(ValueKey<String>('probe-$id'), skipOffstage: false),
            matching: find.byType(Scrollable, skipOffstage: false),
          ),
        );
    ScrollPosition verticalOf(String id) => scrollersOf(id)
        .firstWhere((state) => state.axisDirection == AxisDirection.down)
        .position;

    // Both kept tabs are built by the third step. The fourth moves the dock,
    // which is what makes a bar read its controller again — a bar that is
    // never rebuilt keeps whatever it last drew.
    for (final (active, height) in const [
      ('a', 300.0),
      ('b', 300.0),
      ('a', 300.0),
      ('a', 280.0),
    ]) {
      await tester.pumpWidget(groupShowing(active, height));
      // The bar follows scroll metrics, which schedule its rebuild for the
      // next frame.
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'showing $active');
    }
    expect(verticalOf('a').maxScrollExtent, greaterThan(0));
    expect(verticalOf('b').maxScrollExtent, greaterThan(0));
    expect(
      find.byType(AppControllerScrollbar),
      findsOneWidget,
      reason:
          'the shown tab overflows and says so; a controller shared with the '
          'kept tab offstage has two positions, and the bar reads neither',
    );
    for (final scroller in [...scrollersOf('a'), ...scrollersOf('b')]) {
      expect(
        scroller.position,
        isA<PenFriendlyScrollPosition>(),
        reason: 'PEN-10: a pen still reaches the panel through a coast',
      );
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a drag on a panel that FITS scrolls nothing — a scroller with '
      'nothing to scroll starts no scroll, on either axis', (tester) async {
    final started = <Axis>[];
    var heard = Offset.zero;
    await tester.pumpWidget(
      _host(
        NotificationListener<ScrollStartNotification>(
          onNotification: (notification) {
            started.add(notification.metrics.axis);
            return false;
          },
          child: EditorPanelTabs(
            tabs: <EditorPanelTab>[
              EditorPanelTab(
                id: 'probe',
                label: 'Probe',
                icon: Icons.circle,
                minContentWidth: 100,
                minContentHeight: 100,
                // Reads raw pointers and claims nothing, so the only
                // recognizer that could take the drag is a scroller's.
                builder: (context) => Listener(
                  key: const ValueKey<String>('drag-probe'),
                  behavior: HitTestBehavior.opaque,
                  onPointerMove: (event) => heard += event.delta,
                  child: const SizedBox.expand(),
                ),
              ),
            ],
            activeTabId: 'probe',
            onTabSelected: (_) {},
          ),
        ),
      ),
    );
    final probe = find.byKey(const ValueKey<String>('drag-probe'));
    await tester.drag(probe, const Offset(0, 80));
    await tester.drag(probe, const Offset(80, 0));
    await tester.pumpAndSettle();

    expect(heard.dy, greaterThan(40), reason: 'the vertical drag reached it');
    expect(heard.dx, greaterThan(40), reason: 'the sideways drag reached it');
    expect(started, isEmpty, reason: 'nothing to scroll, so nothing scrolled');
  });
}

/// A panel whose State identity is the measurement: a remount makes a new
/// one.
class _StateProbe extends StatefulWidget {
  const _StateProbe({super.key});

  @override
  State<_StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<_StateProbe> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
