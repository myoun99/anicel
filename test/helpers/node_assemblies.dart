import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// How often a [CountsAssemblies] node has been put together.
class Assemblies {
  int count = 0;
}

/// A semantics boundary that counts how often its node is put together —
/// what a flush does to every node it builds again, in every build mode: a
/// node whose geometry a layout above it dropped, or whose own semantics
/// were marked.
class CountsAssemblies extends SingleChildRenderObjectWidget {
  const CountsAssemblies({super.key, required this.assemblies, super.child});

  final Assemblies assemblies;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCountsAssemblies(assemblies);
}

class _RenderCountsAssemblies extends RenderProxyBox {
  _RenderCountsAssemblies(this.assemblies);

  final Assemblies assemblies;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isSemanticBoundary = true;
  }

  @override
  void assembleSemanticsNode(
    SemanticsNode node,
    SemanticsConfiguration config,
    Iterable<SemanticsNode> children,
  ) {
    assemblies.count += 1;
    super.assembleSemanticsNode(node, config, children);
  }
}

/// How often [assemblies]' node was put together again by [act]: a frame of
/// it less a frame with nothing changed.
Future<int> assembliesBy(
  WidgetTester tester,
  Assemblies assemblies,
  VoidCallback act,
) async {
  expect(assemblies.count, greaterThan(0), reason: 'premise: it was built');
  var before = assemblies.count;
  SchedulerBinding.instance.scheduleFrame();
  await tester.pump();
  final unchanged = assemblies.count - before;
  before = assemblies.count;
  act();
  await tester.pump();
  return assemblies.count - before - unchanged;
}
