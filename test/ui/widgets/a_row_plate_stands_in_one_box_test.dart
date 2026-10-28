import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/widgets/row_plate.dart';

import '../../helpers/named_finders.dart';

/// A row's plate stands in ONE BOX (card frame-panels-build-in-one-frame,
/// 2026-10-28): [RowPlate] is laid out, painted, hit and read as the
/// `Container` and the `Semantics` under it were.
///
/// Each is asked of the plate and of what it replaced, and the two must
/// answer alike.
void main() {
  const outline = Color(0xFF8899AA);
  // The rail row's plate (its leading border thicker here, so a border
  // that went missing from the room shows), the sheet column's, and none —
  // a chromeless row.
  const decorations = <String, BoxDecoration?>{
    'row': BoxDecoration(
      color: Color(0xFF223344),
      border: Border(
        left: BorderSide(color: outline, width: 3),
        right: BorderSide(color: outline),
        bottom: BorderSide(color: outline),
      ),
    ),
    'column': BoxDecoration(
      color: Color(0xFF445566),
      border: Border(
        right: BorderSide(color: outline),
        top: BorderSide(color: outline),
        bottom: BorderSide(color: outline),
      ),
    ),
    'none': null,
  };
  const paddings = <EdgeInsets>[EdgeInsets.only(right: 8), EdgeInsets.zero];
  const contentsKey = ValueKey<String>('contents');
  const hostKey = ValueKey<String>('host');

  // A row's slots in small: a button with a node of its own, and a name.
  Widget contents() => Flex(
    key: contentsKey,
    direction: Axis.horizontal,
    children: [
      const SizedBox(width: 6),
      Semantics(
        label: 'eye',
        button: true,
        child: const ColoredBox(
          color: Color(0xFFEEDD00),
          child: SizedBox(width: 12, height: 12),
        ),
      ),
      const Expanded(
        child: Text(
          'Layer 1',
          maxLines: 1,
          style: TextStyle(fontSize: 10, color: Color(0xFFFFFFFF)),
        ),
      ),
    ],
  );

  Widget plate(BoxDecoration? decoration, EdgeInsets padding, String label) =>
      RowPlate(
        width: 160,
        height: 24,
        padding: padding,
        decoration: decoration,
        label: label,
        child: contents(),
      );

  // As the row spelled it before.
  Widget old(BoxDecoration? decoration, EdgeInsets padding, String label) =>
      Container(
        width: 160,
        height: 24,
        padding: padding,
        decoration: decoration,
        child: Semantics(
          label: label,
          container: true,
          explicitChildNodes: true,
          child: contents(),
        ),
      );

  // Where the plate is asked to stand: in a room its size, in a bigger
  // one, and in a smaller one that clamps it.
  final hosts = <String, Widget Function(Widget subject)>{
    'tight': (subject) => SizedBox(width: 160, height: 24, child: subject),
    'loose': (subject) => Center(child: subject),
    'smaller': (subject) => SizedBox(width: 100, height: 20, child: subject),
  };

  Widget host(Widget Function(Widget) shape, Widget subject) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: RepaintBoundary(
        child: Semantics(
          key: hostKey,
          container: true,
          child: ColoredBox(
            color: const Color(0xFF3355FF),
            child: SizedBox(
              width: 200,
              height: 40,
              child: Align(alignment: Alignment.topLeft, child: shape(subject)),
            ),
          ),
        ),
      ),
    ),
  );

  Future<Uint8List> pixels(WidgetTester tester) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    return (await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return bytes!.buffer.asUint8List();
    }))!;
  }

  Rect globalRectOf(SemanticsNode node) {
    var rect = node.rect;
    for (SemanticsNode? at = node; at != null; at = at.parent) {
      if (at.transform case final transform?) {
        rect = MatrixUtils.transformRect(transform, rect);
      }
    }
    return rect;
  }

  // Every node under the host's, as a screen reader is handed it.
  List<String> nodesOf(WidgetTester tester) {
    final nodes = <String>[];
    void walk(SemanticsNode node, int depth) {
      final data = node.getSemanticsData();
      nodes.add(
        '$depth "${data.label}" ${data.flagsCollection} ${data.actions} '
        '${globalRectOf(node)}',
      );
      node.visitChildren((child) {
        walk(child, depth + 1);
        return true;
      });
    }

    walk(tester.getSemantics(find.byKey(hostKey)), 0);
    return nodes;
  }

  // What a press lands on, every 3px across the host and a little past
  // the plate: the plate's box, or a box of its contents, or nothing.
  List<String> hitsOf(WidgetTester tester, RenderBox outer) {
    final contents = tester.renderObject(find.byKey(contentsKey));
    final origin = tester.getTopLeft(find.byKey(hostKey));
    bool under(RenderObject target) {
      for (RenderObject? at = target; at != null; at = at.parent) {
        if (identical(at, contents)) {
          return true;
        }
      }
      return false;
    }

    return [
      for (var y = 0.0; y < 40; y += 3)
        for (var x = 0.0; x < 200; x += 3)
          switch (tester.hitTestOnBinding(origin + Offset(x, y)).path) {
            final path when !path.any((entry) => entry.target == outer) =>
              'miss',
            final path => switch (path.first.target) {
              final RenderObject target when under(target) =>
                '${target.runtimeType}',
              _ => 'plate',
            },
          },
    ];
  }

  Future<Map<String, Object?>> answersOf(
    WidgetTester tester,
    Finder subject,
  ) async {
    final box = tester.renderObject<RenderBox>(subject);
    final constraints = box.constraints;
    return {
      'pixels': await pixels(tester),
      'size': box.size,
      'contents': tester.getRect(find.byKey(contentsKey)),
      'hits': hitsOf(tester, box),
      'nodes': nodesOf(tester),
      'dry': box.getDryLayout(constraints),
      'dry baseline': box.getDryBaseline(
        constraints,
        TextBaseline.alphabetic,
      ),
      'intrinsics': [
        box.getMinIntrinsicWidth(24),
        box.getMaxIntrinsicWidth(24),
        box.getMinIntrinsicHeight(160),
        box.getMaxIntrinsicHeight(160),
      ],
    };
  }

  for (final MapEntry(key: hostName, value: shape) in hosts.entries) {
    for (final MapEntry(key: ground, value: decoration)
        in decorations.entries) {
      for (final padding in paddings) {
        testWidgets('$hostName · $ground · padding $padding: the plate '
            'answers as the Container round a Semantics did', (tester) async {
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(
            host(shape, old(decoration, padding, 'layer')),
          );
          final before = await answersOf(tester, find.byType(Container));
          await tester.pumpWidget(
            host(shape, plate(decoration, padding, 'layer')),
          );
          final after = await answersOf(tester, find.byType(RowPlate));
          for (final key in before.keys) {
            expect(after[key], before[key], reason: key);
          }
          semantics.dispose();
        });
      }
    }
  }

  testWidgets('a plate that changes its ground paints the new one', (
    tester,
  ) async {
    Future<Uint8List> drawn(BoxDecoration? decoration) async {
      await tester.pumpWidget(
        host(
          hosts['tight']!,
          plate(decoration, paddings.first, 'layer'),
        ),
      );
      return pixels(tester);
    }

    final orders = [
      ['row', 'column'],
      ['none', 'row'],
      ['column', 'none'],
    ];
    for (final [from, to] in orders) {
      await tester.pumpWidget(const SizedBox());
      final fresh = await drawn(decorations[to]);
      await tester.pumpWidget(const SizedBox());
      await drawn(decorations[from]);
      expect(await drawn(decorations[to]), fresh, reason: '$from → $to');
    }
  });

  testWidgets('the node takes a new label, and the plate wears its name', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    Widget named(String? name, String label) => host(
      hosts['tight']!,
      RowPlate(
        name: name,
        width: 160,
        height: 24,
        decoration: decorations['row'],
        label: label,
        child: contents(),
      ),
    );

    await tester.pumpWidget(named(null, 'layer'));
    expect(tester.getSemantics(find.byType(RowPlate)).label, 'layer');
    expect(find.named('lit'), findsNothing);

    await tester.pumpWidget(named('lit', 'selected layer'));
    expect(
      tester.getSemantics(find.byType(RowPlate)).label,
      'selected layer',
    );
    expect(tester.widget(find.named('lit')), isA<RowPlate>());
    semantics.dispose();
  });
}
