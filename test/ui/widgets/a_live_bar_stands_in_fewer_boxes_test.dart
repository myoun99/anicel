import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/ground_ink_writing.dart';
import 'package:anicel/src/ui/widgets/owning_axis_grip.dart';

/// A live bar stands in FEWER BOXES (card frame-panels-build-in-one-frame,
/// 2026-10-28): its grip says its node, its cursor and its wheel where a
/// [Semantics], a [Listener] and a [MouseRegion] stood over it, and the box
/// right above its writing places it where a [Padding] and an [Align] did.
///
/// Each is asked of the new boxes and of what they replaced, and the two
/// must answer alike.
void main() {
  group('the writing stands where a Padding round an Align stood it', () {
    const inset = EdgeInsets.symmetric(horizontal: 6);
    const oneInk = <GroundInkRun>[(end: 1.0, ink: Color(0xFFFFFFFF))];
    const twoInks = <GroundInkRun>[
      (end: 0.4, ink: Color(0xFF000000)),
      (end: 1.0, ink: Color(0xFFFFFFFF)),
    ];
    const base = TextStyle(fontSize: 10);

    // The bar's three rows: a number alone, a grid's number, and the name
    // with the number across the whole of the room.
    Widget write(TextStyle ink, Alignment? at) => at == null
        ? Row(
            children: [
              Expanded(
                child: Text('Size', maxLines: 1, style: base.merge(ink)),
              ),
              Text('42%', maxLines: 1, style: base.merge(ink)),
            ],
          )
        : Text('42%', maxLines: 1, style: base.merge(ink));

    Widget placed(List<GroundInkRun> runs, Alignment? at) => GroundInkWriting(
      runs: runs,
      padding: inset,
      alignment: at,
      builder: (context, ink) => write(ink, at),
    );

    // As the bar spelled it before: the boxes round the row, in the row.
    Widget wrapped(List<GroundInkRun> runs, Alignment? at) => _OldWriting(
      runs: runs,
      builder: (context, ink) => Padding(
        padding: inset,
        child: at == null
            ? write(ink, at)
            : Align(alignment: at, child: write(ink, at)),
      ),
    );

    // Where the writing is asked to stand: tight in a bar's box, loose in
    // a room of that size, and in a row that does not say its width.
    final hosts = <String, Widget Function(Widget writing)>{
      'tight': (writing) => SizedBox(width: 120, height: 18, child: writing),
      'loose': (writing) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 120, maxHeight: 18),
        child: writing,
      ),
      'unbounded': (writing) => UnconstrainedBox(
        constrainedAxis: Axis.vertical,
        child: SizedBox(height: 18, child: writing),
      ),
    };

    Widget host(Widget writing) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          child: ColoredBox(
            color: const Color(0xFF3355FF),
            child: SizedBox(
              width: 140,
              height: 24,
              child: Center(child: writing),
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
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        return bytes!.buffer.asUint8List();
      }))!;
    }

    // ⚠️What a box says it NEEDS is asked of one ink only: over two, the
    // writing is a layout builder's, which answers neither the dry layout
    // nor the intrinsics — before or after.
    Future<Map<String, Object?>> answersOf(
      WidgetTester tester,
      Type writing, {
      required bool asksNeeds,
    }) async {
      final box = tester.renderObject<RenderBox>(find.byType(writing));
      final constraints = box.constraints;
      return {
        'pixels': await pixels(tester),
        'size': box.size,
        'words': [
          for (final words in find.byType(RichText).evaluate())
            tester.getRect(find.byWidget(words.widget)),
        ],
        if (asksNeeds) ...{
          'dry': box.getDryLayout(constraints),
          'dry baseline': box.getDryBaseline(
            constraints,
            TextBaseline.alphabetic,
          ),
          'intrinsics': [
            box.getMinIntrinsicWidth(18),
            box.getMaxIntrinsicWidth(18),
            box.getMinIntrinsicHeight(120),
            box.getMaxIntrinsicHeight(120),
          ],
        },
      };
    }

    for (final MapEntry(key: hostName, value: hostOf) in hosts.entries) {
      for (final at in <Alignment?>[
        Alignment.center,
        Alignment.centerRight,
        null,
      ]) {
        // A row that fills its room has no width to fill in a row that
        // does not say one — the bar never asks it there.
        if (at == null && hostName == 'unbounded') {
          continue;
        }
        for (final (inkName, runs) in [('one ink', oneInk), ('two', twoInks)]) {
          testWidgets('$hostName · ${at ?? 'filled'} · $inkName', (
            tester,
          ) async {
            final asksNeeds = identical(runs, oneInk);
            await tester.pumpWidget(host(hostOf(wrapped(runs, at))));
            final before = await answersOf(
              tester,
              _OldWriting,
              asksNeeds: asksNeeds,
            );
            await tester.pumpWidget(host(hostOf(placed(runs, at))));
            final after = await answersOf(
              tester,
              GroundInkWriting,
              asksNeeds: asksNeeds,
            );
            for (final key in before.keys) {
              expect(after[key], before[key], reason: key);
            }
          });
        }
      }
    }

    // The box the shapes switch in is the one that placed the writing a
    // moment ago: over two inks it gives the place up to the box inside the
    // layout builder, and takes it back over one.
    testWidgets('a writing that changes shape or place stands where a new '
        'one would', (tester) async {
      final steps = <(List<GroundInkRun>, Alignment?)>[
        (oneInk, Alignment.center),
        (twoInks, Alignment.center),
        (oneInk, Alignment.center),
        (oneInk, Alignment.centerRight),
        (twoInks, null),
        (twoInks, Alignment.centerRight),
      ];
      Widget at(int step) =>
          host(hosts['tight']!(placed(steps[step].$1, steps[step].$2)));
      for (var step = 1; step < steps.length; step += 1) {
        await tester.pumpWidget(at(step - 1));
        await tester.pumpWidget(at(step));
        final moved = await answersOf(
          tester,
          GroundInkWriting,
          asksNeeds: false,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(at(step));
        final fresh = await answersOf(
          tester,
          GroundInkWriting,
          asksNeeds: false,
        );
        for (final key in fresh.keys) {
          expect(moved[key], fresh[key], reason: 'step $step: $key');
        }
      }
    });

    testWidgets('the writing has no box of its own round it — the one above '
        'it places it', (tester) async {
      await tester.pumpWidget(
        host(hosts['tight']!(placed(oneInk, Alignment.center))),
      );
      for (final type in [Padding, Align, Center]) {
        expect(
          find.descendant(
            of: find.byType(GroundInkWriting),
            matching: find.byType(type),
          ),
          findsNothing,
          reason: '$type',
        );
      }
    });
  });

  group("a live bar's grip says what the three boxes over it said", () {
    Widget host(Widget bar) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Center(child: SizedBox(width: 200, height: 24, child: bar)),
      ),
    );

    // What the bar's node said while a [Semantics] stood over its grip —
    // read off master `758b498f1` with the same three bars.
    final nodes = <String, (Widget, String, String, double)>{
      'micro': (
        FieldSlider.opacity(value: 0.5, onChanged: (_) {}),
        '50',
        '50',
        200,
      ),
      'named': (
        FieldSlider(
          value: 0.5,
          min: 0,
          max: 1,
          label: 'Size',
          unit: '%',
          onChanged: (_) {},
        ),
        'Size\nSize\n0.5%',
        '0.5%',
        162,
      ),
      'cell': (
        FieldSlider.cell(
          value: 0.5,
          min: 0,
          max: 1,
          label: 'Size',
          unit: '%',
          onChanged: (_) {},
        ),
        'Size\n0.5%',
        '0.5%',
        162,
      ),
    };
    for (final MapEntry(key: name, value: (bar, label, value, width))
        in nodes.entries) {
      testWidgets('$name: its node', (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(host(bar));
        final node = tester.getSemantics(find.byType(FieldSliderTrack));
        final data = node.getSemanticsData();
        expect(data.label, label);
        expect(data.value, value);
        expect(data.hint, '');
        expect(data.textDirection, TextDirection.ltr);
        expect(data.rect, Rect.fromLTWH(0, 0, width, 24));
        expect(data.flagsCollection.isSlider, isTrue);
        expect(data.actions, 0);
        expect(node.childrenCount, 0);
        semantics.dispose();
      });
    }

    testWidgets('its node says the value the bar takes', (tester) async {
      final semantics = tester.ensureSemantics();
      final value = ValueNotifier<double>(0.5);
      addTearDown(value.dispose);
      await tester.pumpWidget(
        host(
          ValueListenableBuilder<double>(
            valueListenable: value,
            builder: (context, v, _) =>
                FieldSlider.opacity(value: v, onChanged: (_) {}),
          ),
        ),
      );
      value.value = 0.7;
      await tester.pump();
      final node = tester.getSemantics(find.byType(FieldSliderTrack));
      expect(node.getSemanticsData().value, '70');
      semantics.dispose();
    });

    Future<MouseCursor?> cursorOver(WidgetTester tester, Widget bar) async {
      await tester.pumpWidget(host(bar));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(
        location: tester.getCenter(find.byType(FieldSliderTrack)),
      );
      addTearDown(mouse.removePointer);
      await tester.pump();
      // A test mouse is device 1, whatever its pointer.
      return RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);
    }

    testWidgets('a bar lying down resizes left and right', (tester) async {
      expect(
        await cursorOver(
          tester,
          FieldSlider.opacity(value: 0.5, onChanged: (_) {}),
        ),
        SystemMouseCursors.resizeLeftRight,
      );
    });

    testWidgets('a bar standing up resizes up and down', (tester) async {
      expect(
        await cursorOver(
          tester,
          FieldSlider.opacity(
            value: 0.5,
            axis: Axis.vertical,
            onChanged: (_) {},
          ),
        ),
        SystemMouseCursors.resizeUpDown,
      );
    });

    testWidgets('a dead bar says no cursor at all', (tester) async {
      expect(
        await cursorOver(
          tester,
          const FieldSlider.opacity(value: 0.5, onChanged: null),
        ),
        SystemMouseCursors.basic,
      );
    });

    testWidgets('the cursor follows the bar when it is turned', (
      tester,
    ) async {
      final axis = ValueNotifier<Axis>(Axis.horizontal);
      addTearDown(axis.dispose);
      await cursorOver(
        tester,
        ValueListenableBuilder<Axis>(
          valueListenable: axis,
          builder: (context, axis, _) => FieldSlider.opacity(
            value: 0.5,
            axis: axis,
            onChanged: (_) {},
          ),
        ),
      );
      axis.value = Axis.vertical;
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.resizeUpDown,
      );
    });

    testWidgets('none of the boxes it replaced stands over the grip or under '
        'it', (tester) async {
      await tester.pumpWidget(
        host(
          FieldSlider(
            value: 0.5,
            min: 0,
            max: 1,
            label: 'Size',
            unit: '%',
            onChanged: (_) {},
          ),
        ),
      );
      final grip = find.byWidgetPredicate((widget) => widget is OwningAxisGrip);
      expect(grip, findsOneWidget);
      final over = <Type>[];
      tester.element(grip).visitAncestorElements((element) {
        if (element.widget is FieldSlider) {
          return false;
        }
        over.add(element.widget.runtimeType);
        return true;
      });
      for (final type in [Semantics, Listener, MouseRegion]) {
        expect(over, isNot(contains(type)), reason: '$type over the grip');
        expect(
          find.descendant(of: grip, matching: find.byType(type)),
          findsNothing,
          reason: '$type under the grip',
        );
      }
    });
  });
}

/// The writing as it was before 2026-10-28 — a bare box the shapes switch
/// in, and over a ground that changes, a layout builder over a moved canvas
/// — so the new one is held against the boxes it replaced.
class _OldWriting extends StatelessWidget {
  const _OldWriting({required this.runs, required this.builder});

  final List<GroundInkRun> runs;
  final Widget Function(BuildContext context, TextStyle ink) builder;

  @override
  Widget build(BuildContext context) {
    final first = runs.first.ink;
    if (runs.every((run) => run.ink == first)) {
      return _OldBox(child: builder(context, TextStyle(color: first)));
    }
    return _OldBox(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedWidth) {
            return builder(context, TextStyle(color: first));
          }
          final colors = <Color>[];
          final stops = <double>[];
          var start = 0.0;
          for (final run in runs) {
            colors
              ..add(run.ink)
              ..add(run.ink);
            stops
              ..add(start)
              ..add(run.end);
            start = run.end;
          }
          final shader = LinearGradient(
            colors: colors,
            stops: stops,
          ).createShader(Offset.zero & constraints.biggest);
          return _OldInkAtOrigin(
            child: builder(
              context,
              TextStyle(foreground: Paint()..shader = shader),
            ),
          );
        },
      ),
    );
  }
}

class _OldBox extends SingleChildRenderObjectWidget {
  const _OldBox({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderProxyBox();
}

class _OldInkAtOrigin extends SingleChildRenderObjectWidget {
  const _OldInkAtOrigin({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderOldInkAtOrigin();
}

class _RenderOldInkAtOrigin extends RenderProxyBox {
  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) {
      return;
    }
    if (child.needsCompositing || child.isRepaintBoundary) {
      context.paintChild(child, offset);
      return;
    }
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    context.paintChild(child, Offset.zero);
    canvas.restore();
  }
}
