import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/tick_layer.dart';

import '../../helpers/frame_census.dart';

/// I-22 ③: WHAT A TICK MOVES IS LAID OUT AND PAINTED ALONE.
///
/// A rebuild inside a `LayoutBuilder`'s subtree lays that LayoutBuilder out
/// again, and a layout ends by asking for a paint of everything up to the
/// boundary above it. A [TickLayer] is the scope and the boundary both, and
/// it keeps the layout in only where its size is decided from above.
void main() {
  final ticks = ValueNotifier<int>(0);
  tearDown(() => ticks.value = 0);

  /// A host that stands for a panel: a layout builder over a boundary, with
  /// the tick layer — or the bare [tick] — filled into it.
  Widget host({required bool layered}) {
    final tick = ValueListenableBuilder<int>(
      valueListenable: ticks,
      builder: (context, value, _) => Text('$value'),
    );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, _) => RepaintBoundary(
          child: Stack(
            children: [
              Positioned.fill(
                child: layered ? TickLayer(child: tick) : tick,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// What a tick asks of the host: its layout builder read from a frame
  /// callback scheduled after the tick's own, and its boundary read before
  /// the paint.
  Future<({bool laidOut, bool painted})> tick(WidgetTester tester) async {
    final builder = tester.renderObject(find.byType(LayoutBuilder).first);
    final boundary = tester.renderObject<RenderObject>(
      find.byType(RepaintBoundary).first,
    );
    ticks.value += 1;
    bool? laidOut;
    SchedulerBinding.instance.scheduleFrameCallback(
      (_) => laidOut = builder.debugNeedsLayout,
    );
    await tester.pump(Duration.zero, EnginePhase.layout);
    final painted = boundary.debugNeedsPaint;
    await tester.pump();
    expect(find.text('${ticks.value}'), findsOneWidget, reason: 'premise');
    return (laidOut: laidOut!, painted: painted);
  }

  testWidgets('a tick inside lays out and paints the layer, not the host', (
    tester,
  ) async {
    await tester.pumpWidget(host(layered: true));

    final asked = await tick(tester);

    expect(asked.laidOut, isFalse, reason: 'the layer owns the scope');
    expect(asked.painted, isFalse, reason: 'and the boundary');
  });

  testWidgets('CONTROL: the same tick bare lays out and paints the host', (
    tester,
  ) async {
    await tester.pumpWidget(host(layered: false));

    final asked = await tick(tester);

    expect(asked.laidOut, isTrue);
    expect(asked.painted, isTrue);
  });

  /// A host whose one semantics boundary holds a panel — a box that counts
  /// the semantics walks passing into it — round the tick layer, or round
  /// the bare [tick], beside a label of its own.
  Widget describedHost({required bool layered, required List<int> walks}) {
    final tick = ValueListenableBuilder<int>(
      valueListenable: ticks,
      builder: (context, value, _) => Text('$value'),
    );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Semantics(
        container: true,
        child: _WalkCounter(
          walks: walks,
          child: Stack(
            children: [
              const Text('beside'),
              Positioned.fill(child: layered ? TickLayer(child: tick) : tick),
            ],
          ),
        ),
      ),
    );
  }

  /// How many semantics walks the tick sent into the panel round it: a
  /// tick's frame less a frame with nothing changed — a debug build walks
  /// the whole tree once a frame to check it, changed or not.
  Future<int> walksIntoThePanel(WidgetTester tester, List<int> walks) async {
    expect(walks.single, greaterThan(0), reason: 'premise: the build walked');
    var before = walks.single;
    SchedulerBinding.instance.scheduleFrame();
    await tester.pump();
    final unchanged = walks.single - before;
    before = walks.single;
    ticks.value += 1;
    await tester.pump();
    expect(find.text('${ticks.value}'), findsOneWidget, reason: 'premise');
    return walks.single - before - unchanged;
  }

  testWidgets('a tick inside re-walks the layer\'s semantics, not the '
      'panel round it', (tester) async {
    final semantics = tester.ensureSemantics();
    final walks = [0];
    await tester.pumpWidget(describedHost(layered: true, walks: walks));

    expect(await walksIntoThePanel(tester, walks), 0);
    expect(
      find.bySemanticsLabel('${ticks.value}'),
      findsOneWidget,
      reason: 'the tick reads to a screen reader as it did',
    );
    semantics.dispose();
  });

  testWidgets('CONTROL: the same tick bare re-walks the panel round it', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final walks = [0];
    await tester.pumpWidget(describedHost(layered: false, walks: walks));

    expect(await walksIntoThePanel(tester, walks), greaterThan(0));
    semantics.dispose();
  });

  /// A host that builds its tick layer again whenever [builds] moves —
  /// round [child] itself, or round a new widget holding it when [renew]
  /// says so.
  Widget rebuildingHost({
    required ValueNotifier<int> builds,
    required Widget child,
    required bool renew,
  }) => Directionality(
    textDirection: TextDirection.ltr,
    child: ValueListenableBuilder<int>(
      valueListenable: builds,
      builder: (context, _, _) => Stack(
        children: [
          Positioned.fill(
            child: TickLayer(child: renew ? KeyedSubtree(child: child) : child),
          ),
        ],
      ),
    ),
  );

  /// What building the layer again asks of it: its LayoutBuilder read once
  /// the build is done, its boundary once the layout is.
  Future<({bool laidOut, bool painted})> buildAgain(
    WidgetTester tester,
    ValueNotifier<int> builds,
  ) async {
    RenderObject layoutBuilder() => tester.renderObject(
      find.descendant(
        of: find.byType(TickLayer),
        matching: find.byType(LayoutBuilder),
      ),
    );
    builds.value += 1;
    await tester.pump(Duration.zero, EnginePhase.build);
    final laidOut = layoutBuilder().debugNeedsLayout;
    await tester.pump();
    RenderTickBoundary? boundary;
    void look(RenderObject node) {
      if (node is RenderTickBoundary) {
        boundary ??= node;
        return;
      }
      node.visitChildren(look);
    }

    look(tester.renderObject(find.byType(TickLayer)));
    builds.value += 1;
    await tester.pump(Duration.zero, EnginePhase.layout);
    final painted = boundary!.debugNeedsPaint;
    await tester.pump();
    return (laidOut: laidOut, painted: painted);
  }

  testWidgets('built again round the same child, the layer is not laid out '
      'or painted again', (tester) async {
    final builds = ValueNotifier<int>(0);
    addTearDown(builds.dispose);
    const child = Text('held');
    await tester.pumpWidget(
      rebuildingHost(builds: builds, child: child, renew: false),
    );

    final asked = await buildAgain(tester, builds);

    expect(asked.laidOut, isFalse, reason: 'its builder would hand back the '
        'very child it holds');
    expect(asked.painted, isFalse);
    expect(find.text('held'), findsOneWidget);
  });

  testWidgets('CONTROL: built again round a new child, it is laid out and '
      'painted again', (tester) async {
    final builds = ValueNotifier<int>(0);
    addTearDown(builds.dispose);
    const child = Text('held');
    await tester.pumpWidget(
      rebuildingHost(builds: builds, child: child, renew: true),
    );

    final asked = await buildAgain(tester, builds);

    expect(asked.laidOut, isTrue);
    expect(asked.painted, isTrue);
  });

  /// A panel's host: a [host] layer — or a tick layer — round a listener
  /// that builds [panel] again whenever [builds] moves, handing back the
  /// very panel it holds.
  Widget panelHost({
    required ValueNotifier<int> builds,
    required Widget panel,
    bool host = true,
  }) {
    final listener = ValueListenableBuilder<int>(
      valueListenable: builds,
      builder: (context, _, held) => held!,
      child: panel,
    );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Semantics(
        container: true,
        child: Stack(
          children: [
            Positioned.fill(
              child: host
                  ? TickLayer.host(child: listener)
                  : TickLayer(child: listener),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> panelPainted(
    WidgetTester tester,
    ValueNotifier<int> builds,
  ) async {
    final panel = tester.renderObject(find.text('panel'));
    final frame = await frameCensus(tester, () => builds.value += 1);
    expect(
      frame.rebuilt,
      contains(ValueListenableBuilder<int>),
      reason: 'premise: the host was built again',
    );
    return frame.painted.any((object) => identical(object, panel));
  }

  testWidgets('a host built again round a panel that did not change paints '
      'none of the panel', (tester) async {
    final builds = ValueNotifier<int>(0);
    addTearDown(builds.dispose);
    await tester.pumpWidget(
      panelHost(builds: builds, panel: const Text('panel')),
    );

    expect(await panelPainted(tester, builds), isFalse);
  });

  testWidgets('CONTROL: a tick layer round the same listener paints it '
      'again — what ticks is what changed', (tester) async {
    final builds = ValueNotifier<int>(0);
    addTearDown(builds.dispose);
    await tester.pumpWidget(
      panelHost(builds: builds, panel: const Text('panel'), host: false),
    );

    expect(await panelPainted(tester, builds), isTrue);
  });

  testWidgets('and re-walks none of the panel\'s semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    final builds = ValueNotifier<int>(0);
    addTearDown(builds.dispose);
    final walks = [0];
    await tester.pumpWidget(
      panelHost(
        builds: builds,
        panel: _WalkCounter(walks: walks, child: const Text('panel')),
      ),
    );
    var before = walks.single;
    SchedulerBinding.instance.scheduleFrame();
    await tester.pump();
    final unchanged = walks.single - before;
    before = walks.single;

    builds.value += 1;
    await tester.pump();

    expect(walks.single - before - unchanged, 0);
    expect(
      find.bySemanticsLabel('panel'),
      findsOneWidget,
      reason: 'the panel reads to a screen reader as it did',
    );
    semantics.dispose();
  });

  testWidgets('under loose constraints it says so', (tester) async {
    await tester.pumpWidget(
      const Center(
        child: TickLayer(child: SizedBox(width: 10, height: 10)),
      ),
    );

    expect(tester.takeException(), isAssertionError);
  });
}

/// A box that counts the semantics walks passing through it: rebuilding a
/// boundary's share of the tree visits every node under it this way.
class _WalkCounter extends SingleChildRenderObjectWidget {
  const _WalkCounter({required this.walks, super.child});

  final List<int> walks;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderWalkCounter(walks);
}

class _RenderWalkCounter extends RenderProxyBox {
  _RenderWalkCounter(this.walks);

  final List<int> walks;

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    walks[0] += 1;
    super.visitChildrenForSemantics(visitor);
  }
}
