import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/tick_layer.dart';

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
