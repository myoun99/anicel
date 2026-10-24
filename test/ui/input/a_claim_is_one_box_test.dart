import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/input/control_press_claim.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/ui/theme/app_scroll_behavior.dart';

/// 🪶A CLAIM IS ONE BOX (frame-panels-build-in-one-frame, 2026-10-25).
///
/// [ControlPressClaim] was a State, a `RawGestureDetector`, that detector's
/// semantics and two `Listener`s; [DragVerbClaim] a widget and a `Listener`;
/// [SurfaceDragClaim] a widget and a detector. Each is one render object now,
/// because a timeline tab mounts some 135 claims every time it opens.
///
/// 🧪WHAT PROVES THEY STILL ANSWER AS THEY DID: [_answers] is what the old
/// composition answered (recorded at master 3354f5258, before this change),
/// for every claim kind — a plain button, a column's (fires on the down,
/// under a watch), a sheet's cell, a nested pair, a dead one, a button with
/// a slider's verb inside, a canvas surface, and bare paper for contrast —
/// a claim over nothing a pointer can hit, a button whose own tap is silent,
/// a verb claimed over a canvas, a grip's opaque verb, a button on a canvas
/// that claims the press as its own verb — pressed by a mouse,
/// a finger and a pen held still, wobbled, swept down, swept across, carried
/// off and cancelled, and swept by a trackpad. Each line says what fired, in
/// order, how far the list scrolled, and which claims stood on the pointer
/// while it was down and after it lifted. Then the semantics tree.
///
/// Set `ZZ_RECORD` to a path to write the lines a build gives instead.
void main() {
  tearDown(debugClearValueControlPointers);

  testWidgets('every claim answers every press as the old composition did', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final said = <String>[];
    final list = ScrollController();
    addTearDown(list.dispose);
    await tester.pumpWidget(_Fixture(list: list, said: said));
    await tester.pump();

    final lines = <String>[];
    var pointerId = 1;
    for (final target in _targets) {
      for (final kind in const [
        PointerDeviceKind.mouse,
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
      ]) {
        for (final gesture in _Gesture.values) {
          final id = pointerId++;
          final at = tester.getCenter(find.byKey(ValueKey<String>(target)));
          final held = await _press(tester, TestPointer(id, kind), at, gesture);
          lines.add(
            '$target ${kind.name} ${gesture.name}: ${said.join(' ')} · '
            'scrolled ${list.offset.toStringAsFixed(1)} · held $held · '
            'after ${_claimsOn(id)}',
          );
          said.clear();
          list.jumpTo(0);
          await tester.pump(const Duration(seconds: 1));
        }
      }
      final id = pointerId++;
      final at = tester.getCenter(find.byKey(ValueKey<String>(target)));
      await _panZoom(tester, TestPointer(id, PointerDeviceKind.trackpad), at);
      lines.add(
        '$target trackpad panZoom: ${said.join(' ')} · '
        'scrolled ${list.offset.toStringAsFixed(1)}',
      );
      said.clear();
      list.jumpTo(0);
      await tester.pump(const Duration(seconds: 1));
    }

    final handle = tester.ensureSemantics();
    await tester.pump();
    lines.addAll(
      tester.binding.renderViews.single.owner!.semanticsOwner!
          .rootSemanticsNode!
          .toStringDeep(childOrder: DebugSemanticsDumpOrder.traversalOrder)
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          // An object's hash is not an answer: it differs run to run.
          .map((line) => line.replaceAll(RegExp(r'#[0-9a-f]{5}\('), '#(')),
    );
    handle.dispose();

    final record = Platform.environment['ZZ_RECORD'];
    if (record != null) {
      File(record).writeAsStringSync('${lines.join('\n')}\n');
      return;
    }
    expect(lines, _answers);
  });

  testWidgets('the transcript is not vacuous — it holds both answers', (
    tester,
  ) async {
    // A press that fired and one that did not, on the down and on the
    // release; a press that scrolled the list and one that held it, by a
    // hand and by a trackpad; a claim standing while the press was down and
    // gone once it lifted; a button's own tap silenced, and one let through.
    expect(_answers.where((l) => l.contains('·')).length, 266);
    expect(_answers, contains(matches('^plain mouse still: plain plain.tap ')));
    expect(_answers, contains(matches('^silent mouse still: silent · ')));
    expect(_answers, contains(matches('^dead mouse still: dead.tap ')));
    expect(_answers, contains(matches(r'^column \w+ still: watch column ')));
    expect(_answers, contains(matches('^canvasButton mouse still: canvasButton.tap ')));
    expect(_answers, contains(matches('^paper touch swipeDown: +· scrolled [1-9]')));
    expect(_answers, contains(matches(r'^plain touch swipeDown: +· scrolled 0\.0')));
    expect(_answers, contains(matches('^paper trackpad panZoom: +· scrolled [1-9]')));
    expect(_answers, contains(matches(r'^plain trackpad panZoom: +· scrolled 0\.0')));
    expect(_answers, contains(matches('held spoken true verb false · after spoken false')));
    expect(_answers, contains(matches('held spoken false verb true · after spoken false verb false')));
  });

  testWidgets('a claim rebuilt answers with what it was rebuilt with', (
    tester,
  ) async {
    final said = <String>[];
    late StateSetter rebuild;
    var second = false;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return PressFireScope(
              fireOn: second ? PressFire.down : PressFire.upInside,
              child: ControlPressClaim(
                onPressed: () => said.add(second ? 'second' : 'first'),
                child: const Listener(
                  key: ValueKey<String>('claimed'),
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(width: 40, height: 40),
                ),
              ),
            );
          },
        ),
      ),
    );
    final at = tester.getCenter(find.byKey(const ValueKey<String>('claimed')));
    final first = await tester.startGesture(at);
    expect(said, isEmpty, reason: 'a button fires on the release');
    await first.up();
    expect(said, ['first']);
    rebuild(() => second = true);
    await tester.pump();
    final again = await tester.startGesture(at);
    expect(said, ['first', 'second'], reason: 'a column fires on the press');
    await again.up();
    expect(said, ['first', 'second']);
  });

  testWidgets('a claim mounts nothing between itself and what it claims', (
    tester,
  ) async {
    const body = ValueKey<String>('body');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SurfaceDragClaim(
          child: DragVerbClaim(
            child: ControlPressClaim(
              onPressed: () {},
              child: const SizedBox(key: body, width: 10, height: 10),
            ),
          ),
        ),
      ),
    );
    for (final type in const [
      SurfaceDragClaim,
      DragVerbClaim,
      ControlPressClaim,
    ]) {
      final claim = tester.element(find.byType(type));
      final children = <Element>[];
      claim.visitChildren(children.add);
      expect(children, hasLength(1), reason: '$type');
      expect(
        children.single.widget,
        isA<Widget>().having(
          (w) => w.runtimeType,
          'type',
          anyOf(DragVerbClaim, ControlPressClaim, SizedBox),
        ),
        reason: '$type holds its child directly',
      );
      final box = tester.renderObject(find.byType(type));
      expect(box, isA<RenderProxyBoxWithHitTestBehavior>(), reason: '$type');
    }
    expect(
      tester.renderObject(find.byType(ControlPressClaim)),
      isA<RenderProxyBox>().having(
        (b) => b.child,
        'child',
        same(tester.renderObject(find.byKey(body))),
      ),
    );
  });
}

enum _Gesture { still, wobble, swipeDown, swipeAcross, carryOff, cancel }

const _targets = [
  'paper',
  'plain',
  'column',
  'cell',
  'nestedInner',
  'nestedOuter',
  'dead',
  'slider',
  'surface',
  'hollow',
  'silent',
  'canvasVerb',
  'grip',
  'canvasButton',
];

/// Which claims stand on [id]: a control's tap, and a verb's drag.
String _claimsOn(int id) =>
    'spoken ${pressIsSpokenFor(id)} verb ${valueControlOwnsPointer(id)}';

/// [gesture] by [pointer] from [at]; which claims stood while it was down.
Future<String> _press(
  WidgetTester tester,
  TestPointer pointer,
  Offset at,
  _Gesture gesture,
) async {
  await tester.sendEventToBinding(pointer.addPointer(location: at));
  await tester.sendEventToBinding(pointer.down(at));
  await tester.pump(const Duration(milliseconds: 16));
  final held = _claimsOn(pointer.pointer);
  Future<void> step(Offset by, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.sendEventToBinding(pointer.move(pointer.location! + by));
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  switch (gesture) {
    case _Gesture.still:
      await tester.sendEventToBinding(pointer.up());
    case _Gesture.wobble:
      await step(const Offset(2, 2), 1);
      await tester.sendEventToBinding(pointer.up());
    case _Gesture.swipeDown:
      await step(const Offset(0, -30), 5);
      await tester.sendEventToBinding(pointer.up());
    case _Gesture.swipeAcross:
      await step(const Offset(-12, 0), 5);
      await tester.sendEventToBinding(pointer.up());
    case _Gesture.carryOff:
      await step(const Offset(60, 0), 4);
      await tester.sendEventToBinding(pointer.up());
    case _Gesture.cancel:
      await step(const Offset(1, 1), 1);
      await tester.sendEventToBinding(pointer.cancel());
  }
  await tester.pump(const Duration(milliseconds: 16));
  await tester.sendEventToBinding(pointer.removePointer());
  await tester.pump();
  return held;
}

Future<void> _panZoom(
  WidgetTester tester,
  TestPointer pointer,
  Offset at,
) async {
  await tester.sendEventToBinding(pointer.panZoomStart(at));
  await tester.pump(const Duration(milliseconds: 16));
  for (var i = 1; i <= 5; i++) {
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(at, pan: Offset(0, -30.0 * i)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.sendEventToBinding(pointer.panZoomEnd());
  await tester.pump();
}

class _Fixture extends StatelessWidget {
  const _Fixture({required this.list, required this.said});

  final ScrollController list;
  final List<String> said;

  VoidCallback _say(String word) => () => said.add(word);

  /// What a control is made of: an opaque body with its own tap, so the
  /// transcript also says when the claim leaves the inner tap its click.
  Widget _body(String key, {double width = 160}) => GestureDetector(
    key: ValueKey<String>(key),
    behavior: HitTestBehavior.opaque,
    onTap: _say('$key.tap'),
    child: SizedBox(width: width, height: 44),
  );

  Widget _row(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Align(alignment: Alignment.centerLeft, child: child),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          height: 1000,
          child: ListView(
            controller: list,
            children: [
              _row(
                const Listener(
                  key: ValueKey<String>('paper'),
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(width: 160, height: 44),
                ),
              ),
              _row(
                ControlPressClaim(
                  onPressed: _say('plain'),
                  child: _body('plain'),
                ),
              ),
              _row(
                PressFireWatch(
                  beforeFire: _say('watch'),
                  child: PressFireScope(
                    fireOn: PressFire.down,
                    child: ControlPressClaim(
                      onPressed: _say('column'),
                      child: _body('column'),
                    ),
                  ),
                ),
              ),
              _row(
                PressFireScope(
                  fireOn: PressFire.upInsideOrPan,
                  child: ControlPressClaim(
                    onPressed: _say('cell'),
                    child: _body('cell'),
                  ),
                ),
              ),
              _row(
                ControlPressClaim(
                  onPressed: _say('outer'),
                  child: GestureDetector(
                    key: const ValueKey<String>('nestedOuter'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _say('nestedOuter.tap'),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 120),
                      child: ControlPressClaim(
                        onPressed: _say('inner'),
                        child: _body('nestedInner', width: 60),
                      ),
                    ),
                  ),
                ),
              ),
              _row(ControlPressClaim(onPressed: null, child: _body('dead'))),
              _row(
                ControlPressClaim(
                  onPressed: _say('sliderButton'),
                  child: DragVerbClaim(
                    child: GestureDetector(
                      key: const ValueKey<String>('slider'),
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (_) => said.add('slide.start'),
                      onHorizontalDragUpdate: (_) => said.add('slide'),
                      onHorizontalDragEnd: (_) => said.add('slide.end'),
                      child: const SizedBox(width: 160, height: 44),
                    ),
                  ),
                ),
              ),
              _row(
                SurfaceDragClaim(
                  // Translucent, as a canvas is: it paints nothing a
                  // pointer can hit, and the claim around it still holds.
                  child: Listener(
                    key: const ValueKey<String>('surface'),
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) => said.add('canvas.down'),
                    onPointerUp: (_) => said.add('canvas.up'),
                    child: const SizedBox(width: 160, height: 44),
                  ),
                ),
              ),
              _row(
                ControlPressClaim(
                  onPressed: _say('hollow'),
                  child: const SizedBox(
                    key: ValueKey<String>('hollow'),
                    width: 160,
                    height: 44,
                  ),
                ),
              ),
              _row(
                ControlPressClaim(
                  onPressed: _say('silent'),
                  child: GestureDetector(
                    key: const ValueKey<String>('silent'),
                    behavior: HitTestBehavior.opaque,
                    onTap: silentPress(_say('silent.tap')),
                    child: const SizedBox(width: 160, height: 44),
                  ),
                ),
              ),
              _row(
                DragVerbClaim(
                  child: SurfaceDragClaim(
                    child: Listener(
                      key: const ValueKey<String>('canvasVerb'),
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) => said.add('canvasVerb.down'),
                      child: const SizedBox(width: 160, height: 44),
                    ),
                  ),
                ),
              ),
              _row(
                const DragVerbClaim(
                  key: ValueKey<String>('grip'),
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(width: 160, height: 44),
                ),
              ),
              _row(
                DragVerbClaim(
                  behavior: HitTestBehavior.opaque,
                  child: ControlPressClaim(
                    onPressed: _say('canvasButton'),
                    child: _body('canvasButton'),
                  ),
                ),
              ),
              for (var i = 0; i < 12; i++) const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the old composition answered, at master 3354f5258.
const _answers = <String>[
  'paper mouse still:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'paper mouse wobble:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'paper mouse swipeDown:  · scrolled 150.0 · held spoken false verb false · after spoken false verb false',
  'paper mouse swipeAcross:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'paper mouse carryOff:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'paper mouse cancel:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'paper touch still:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'paper touch wobble:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'paper touch swipeDown:  · scrolled 150.0 · held spoken false verb false · after spoken false verb false',
  'paper touch swipeAcross:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'paper touch carryOff:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'paper touch cancel:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'paper stylus still:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'paper stylus wobble:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'paper stylus swipeDown:  · scrolled 150.0 · held spoken false verb false · after spoken false verb false',
  'paper stylus swipeAcross:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'paper stylus carryOff:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'paper stylus cancel:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'paper trackpad panZoom:  · scrolled 150.0',
  'plain mouse still: plain plain.tap · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'plain mouse wobble: plain · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'plain mouse swipeDown:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'plain mouse swipeAcross: plain · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'plain mouse carryOff:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'plain mouse cancel:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'plain touch still: plain plain.tap · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'plain touch wobble: plain · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'plain touch swipeDown:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'plain touch swipeAcross: plain · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'plain touch carryOff:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'plain touch cancel:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'plain stylus still: plain plain.tap · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'plain stylus wobble: plain · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'plain stylus swipeDown:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'plain stylus swipeAcross: plain · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'plain stylus carryOff:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'plain stylus cancel:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'plain trackpad panZoom:  · scrolled 0.0',
  'column mouse still: watch column column.tap · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'column mouse wobble: watch column · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'column mouse swipeDown: watch column · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'column mouse swipeAcross: watch column · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'column mouse carryOff: watch column · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'column mouse cancel: watch column · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'column touch still: watch column column.tap · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'column touch wobble: watch column · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'column touch swipeDown: watch column · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'column touch swipeAcross: watch column · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'column touch carryOff: watch column · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'column touch cancel: watch column · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'column stylus still: watch column column.tap · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'column stylus wobble: watch column · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'column stylus swipeDown: watch column · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'column stylus swipeAcross: watch column · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'column stylus carryOff: watch column · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'column stylus cancel: watch column · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'column trackpad panZoom:  · scrolled 0.0',
  'cell mouse still: cell cell.tap · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'cell mouse wobble: cell · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'cell mouse swipeDown:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'cell mouse swipeAcross:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'cell mouse carryOff:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'cell mouse cancel:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'cell touch still: cell cell.tap · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'cell touch wobble: cell · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'cell touch swipeDown:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'cell touch swipeAcross:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'cell touch carryOff:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'cell touch cancel:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'cell stylus still: cell cell.tap · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'cell stylus wobble: cell · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'cell stylus swipeDown:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'cell stylus swipeAcross:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'cell stylus carryOff:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'cell stylus cancel:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'cell trackpad panZoom:  · scrolled 0.0',
  'nestedInner mouse still: inner nestedInner.tap · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedInner mouse wobble: inner · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedInner mouse swipeDown:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedInner mouse swipeAcross:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedInner mouse carryOff:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedInner mouse cancel:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedInner touch still: inner nestedInner.tap · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedInner touch wobble: inner · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedInner touch swipeDown:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedInner touch swipeAcross:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedInner touch carryOff:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedInner touch cancel:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedInner stylus still: inner nestedInner.tap · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedInner stylus wobble: inner · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedInner stylus swipeDown:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedInner stylus swipeAcross:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedInner stylus carryOff:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedInner stylus cancel:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedInner trackpad panZoom:  · scrolled 0.0',
  'nestedOuter mouse still: outer nestedOuter.tap · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedOuter mouse wobble: outer · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedOuter mouse swipeDown:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedOuter mouse swipeAcross: outer · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedOuter mouse carryOff:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedOuter mouse cancel:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedOuter touch still: outer nestedOuter.tap · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedOuter touch wobble: outer · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedOuter touch swipeDown:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedOuter touch swipeAcross: outer · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedOuter touch carryOff:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedOuter touch cancel:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedOuter stylus still: outer nestedOuter.tap · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedOuter stylus wobble: outer · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedOuter stylus swipeDown:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedOuter stylus swipeAcross: outer · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedOuter stylus carryOff:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedOuter stylus cancel:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'nestedOuter trackpad panZoom:  · scrolled 0.0',
  'dead mouse still: dead.tap · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'dead mouse wobble:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'dead mouse swipeDown:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'dead mouse swipeAcross:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'dead mouse carryOff:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'dead mouse cancel:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'dead touch still: dead.tap · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'dead touch wobble:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'dead touch swipeDown:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'dead touch swipeAcross:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'dead touch carryOff:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'dead touch cancel:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'dead stylus still: dead.tap · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'dead stylus wobble:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'dead stylus swipeDown:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'dead stylus swipeAcross:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'dead stylus carryOff:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'dead stylus cancel:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'dead trackpad panZoom:  · scrolled 0.0',
  'slider mouse still: sliderButton · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'slider mouse wobble: slide.start sliderButton slide.end · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'slider mouse swipeDown:  · scrolled 120.0 · held spoken true verb true · after spoken false verb false',
  'slider mouse swipeAcross: slide.start slide slide slide slide sliderButton slide.end · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'slider mouse carryOff: slide.start slide slide slide slide.end · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'slider mouse cancel:  · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'slider touch still: sliderButton · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'slider touch wobble: sliderButton · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'slider touch swipeDown:  · scrolled 120.0 · held spoken true verb true · after spoken false verb false',
  'slider touch swipeAcross: slide.start slide slide slide sliderButton slide.end · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'slider touch carryOff: slide.start slide slide slide slide.end · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'slider touch cancel:  · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'slider stylus still: sliderButton · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'slider stylus wobble: sliderButton · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'slider stylus swipeDown:  · scrolled 120.0 · held spoken true verb true · after spoken false verb false',
  'slider stylus swipeAcross: slide.start slide slide slide sliderButton slide.end · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'slider stylus carryOff: slide.start slide slide slide slide.end · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'slider stylus cancel:  · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'slider trackpad panZoom:  · scrolled 0.0',
  'surface mouse still: canvas.down canvas.up · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'surface mouse wobble: canvas.down canvas.up · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'surface mouse swipeDown: canvas.down canvas.up · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'surface mouse swipeAcross: canvas.down canvas.up · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'surface mouse carryOff: canvas.down canvas.up · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'surface mouse cancel: canvas.down · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'surface touch still: canvas.down canvas.up · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'surface touch wobble: canvas.down canvas.up · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'surface touch swipeDown: canvas.down canvas.up · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'surface touch swipeAcross: canvas.down canvas.up · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'surface touch carryOff: canvas.down canvas.up · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'surface touch cancel: canvas.down · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'surface stylus still: canvas.down canvas.up · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'surface stylus wobble: canvas.down canvas.up · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'surface stylus swipeDown: canvas.down canvas.up · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'surface stylus swipeAcross: canvas.down canvas.up · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'surface stylus carryOff: canvas.down canvas.up · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'surface stylus cancel: canvas.down · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'surface trackpad panZoom:  · scrolled 0.0',
  'hollow mouse still:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'hollow mouse wobble:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'hollow mouse swipeDown:  · scrolled 150.0 · held spoken false verb false · after spoken false verb false',
  'hollow mouse swipeAcross:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'hollow mouse carryOff:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'hollow mouse cancel:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'hollow touch still:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'hollow touch wobble:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'hollow touch swipeDown:  · scrolled 150.0 · held spoken false verb false · after spoken false verb false',
  'hollow touch swipeAcross:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'hollow touch carryOff:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'hollow touch cancel:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'hollow stylus still:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'hollow stylus wobble:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'hollow stylus swipeDown:  · scrolled 150.0 · held spoken false verb false · after spoken false verb false',
  'hollow stylus swipeAcross:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'hollow stylus carryOff:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'hollow stylus cancel:  · scrolled 0.0 · held spoken false verb false · after spoken false verb false',
  'hollow trackpad panZoom:  · scrolled 150.0',
  'silent mouse still: silent · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'silent mouse wobble: silent · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'silent mouse swipeDown:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'silent mouse swipeAcross: silent · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'silent mouse carryOff:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'silent mouse cancel:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'silent touch still: silent · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'silent touch wobble: silent · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'silent touch swipeDown:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'silent touch swipeAcross: silent · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'silent touch carryOff:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'silent touch cancel:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'silent stylus still: silent · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'silent stylus wobble: silent · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'silent stylus swipeDown:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'silent stylus swipeAcross: silent · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'silent stylus carryOff:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'silent stylus cancel:  · scrolled 0.0 · held spoken true verb false · after spoken false verb false',
  'silent trackpad panZoom:  · scrolled 0.0',
  'canvasVerb mouse still: canvasVerb.down · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'canvasVerb mouse wobble: canvasVerb.down · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'canvasVerb mouse swipeDown: canvasVerb.down · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'canvasVerb mouse swipeAcross: canvasVerb.down · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'canvasVerb mouse carryOff: canvasVerb.down · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'canvasVerb mouse cancel: canvasVerb.down · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'canvasVerb touch still: canvasVerb.down · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'canvasVerb touch wobble: canvasVerb.down · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'canvasVerb touch swipeDown: canvasVerb.down · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'canvasVerb touch swipeAcross: canvasVerb.down · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'canvasVerb touch carryOff: canvasVerb.down · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'canvasVerb touch cancel: canvasVerb.down · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'canvasVerb stylus still: canvasVerb.down · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'canvasVerb stylus wobble: canvasVerb.down · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'canvasVerb stylus swipeDown: canvasVerb.down · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'canvasVerb stylus swipeAcross: canvasVerb.down · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'canvasVerb stylus carryOff: canvasVerb.down · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'canvasVerb stylus cancel: canvasVerb.down · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'canvasVerb trackpad panZoom:  · scrolled 0.0',
  'grip mouse still:  · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'grip mouse wobble:  · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'grip mouse swipeDown:  · scrolled 150.0 · held spoken false verb true · after spoken false verb false',
  'grip mouse swipeAcross:  · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'grip mouse carryOff:  · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'grip mouse cancel:  · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'grip touch still:  · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'grip touch wobble:  · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'grip touch swipeDown:  · scrolled 150.0 · held spoken false verb true · after spoken false verb false',
  'grip touch swipeAcross:  · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'grip touch carryOff:  · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'grip touch cancel:  · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'grip stylus still:  · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'grip stylus wobble:  · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'grip stylus swipeDown:  · scrolled 150.0 · held spoken false verb true · after spoken false verb false',
  'grip stylus swipeAcross:  · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'grip stylus carryOff:  · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'grip stylus cancel:  · scrolled 0.0 · held spoken false verb true · after spoken false verb false',
  'grip trackpad panZoom:  · scrolled 150.0',
  'canvasButton mouse still: canvasButton.tap · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'canvasButton mouse wobble:  · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'canvasButton mouse swipeDown:  · scrolled 120.0 · held spoken true verb true · after spoken false verb false',
  'canvasButton mouse swipeAcross:  · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'canvasButton mouse carryOff:  · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'canvasButton mouse cancel:  · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'canvasButton touch still: canvasButton.tap · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'canvasButton touch wobble: canvasButton.tap · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'canvasButton touch swipeDown:  · scrolled 120.0 · held spoken true verb true · after spoken false verb false',
  'canvasButton touch swipeAcross:  · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'canvasButton touch carryOff:  · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'canvasButton touch cancel:  · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'canvasButton stylus still: canvasButton.tap · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'canvasButton stylus wobble: canvasButton.tap · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'canvasButton stylus swipeDown:  · scrolled 120.0 · held spoken true verb true · after spoken false verb false',
  'canvasButton stylus swipeAcross:  · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'canvasButton stylus carryOff:  · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'canvasButton stylus cancel:  · scrolled 0.0 · held spoken true verb true · after spoken false verb false',
  'canvasButton trackpad panZoom:  · scrolled 0.0',
  'SemanticsNode#0',
  ' │ Rect.fromLTRB(0.0, 0.0, 2400.0, 3300.0)',
  ' │',
  ' └─SemanticsNode#1',
  '   │ Rect.fromLTRB(0.0, 0.0, 800.0, 1100.0) scaled by 3.0x',
  '   │ textDirection: ltr',
  '   │',
  '   └─SemanticsNode#2',
  '     │ Rect.fromLTRB(0.0, 0.0, 800.0, 1100.0)',
  '     │ sortKey: OrdinalSortKey#(order: 0.0)',
  '     │',
  '     └─SemanticsNode#3',
  '       │ Rect.fromLTRB(0.0, 0.0, 800.0, 1100.0)',
  '       │ flags: scopesRoute',
  '       │',
  '       └─SemanticsNode#4',
  '         │ Rect.fromLTRB(0.0, 0.0, 400.0, 1000.0)',
  '         │',
  '         └─SemanticsNode#25',
  '           │ Rect.fromLTRB(0.0, 0.0, 400.0, 1000.0)',
  '           │ actions: scrollToOffset, scrollUp',
  '           │ flags: hasImplicitScrolling',
  '           │ scrollChildren: 25',
  '           │ scrollIndex: 0',
  '           │ scrollExtentMin: 0.0',
  '           │ scrollPosition: 0.0',
  '           │ scrollExtentMax: 657.9',
  '           │',
  '           ├─SemanticsNode#5',
  '           │   Rect.fromLTRB(0.0, 0.0, 400.0, 60.0)',
  '           │   tags: RenderViewport.twoPane',
  '           │   indexInParent: 0',
  '           │',
  '           ├─SemanticsNode#6',
  '           │   Rect.fromLTRB(0.0, 60.0, 400.0, 120.0)',
  '           │   tags: RenderViewport.twoPane',
  '           │   actions: tap',
  '           │   indexInParent: 1',
  '           │',
  '           ├─SemanticsNode#7',
  '           │   Rect.fromLTRB(0.0, 120.0, 400.0, 180.0)',
  '           │   tags: RenderViewport.twoPane',
  '           │   actions: tap',
  '           │   indexInParent: 2',
  '           │',
  '           ├─SemanticsNode#8',
  '           │   Rect.fromLTRB(0.0, 180.0, 400.0, 240.0)',
  '           │   tags: RenderViewport.twoPane',
  '           │   actions: tap',
  '           │   indexInParent: 3',
  '           │',
  '           ├─SemanticsNode#9',
  '           │ │ Rect.fromLTRB(0.0, 240.0, 400.0, 300.0)',
  '           │ │ tags: RenderViewport.twoPane',
  '           │ │ actions: tap',
  '           │ │ indexInParent: 4',
  '           │ │',
  '           │ └─SemanticsNode#10',
  '           │     Rect.fromLTRB(120.0, 8.0, 180.0, 52.0)',
  '           │     actions: tap',
  '           │',
  '           ├─SemanticsNode#11',
  '           │   Rect.fromLTRB(0.0, 300.0, 400.0, 360.0)',
  '           │   tags: RenderViewport.twoPane',
  '           │   actions: tap',
  '           │   indexInParent: 5',
  '           │',
  '           ├─SemanticsNode#12',
  '           │   Rect.fromLTRB(0.0, 360.0, 400.0, 420.0)',
  '           │   tags: RenderViewport.twoPane',
  '           │   actions: scrollLeft, scrollRight',
  '           │   indexInParent: 6',
  '           │',
  '           ├─SemanticsNode#13',
  '           │   Rect.fromLTRB(0.0, 420.0, 400.0, 480.0)',
  '           │   tags: RenderViewport.twoPane',
  '           │   indexInParent: 7',
  '           │',
  '           ├─SemanticsNode#14',
  '           │   Rect.fromLTRB(0.0, 480.0, 400.0, 540.0)',
  '           │   tags: RenderViewport.twoPane',
  '           │   indexInParent: 8',
  '           │',
  '           ├─SemanticsNode#15',
  '           │   Rect.fromLTRB(0.0, 540.0, 400.0, 600.0)',
  '           │   tags: RenderViewport.twoPane',
  '           │   actions: tap',
  '           │   indexInParent: 9',
  '           │',
  '           ├─SemanticsNode#16',
  '           │   Rect.fromLTRB(0.0, 600.0, 400.0, 660.0)',
  '           │   tags: RenderViewport.twoPane',
  '           │   indexInParent: 10',
  '           │',
  '           ├─SemanticsNode#17',
  '           │   Rect.fromLTRB(0.0, 660.0, 400.0, 720.0)',
  '           │   tags: RenderViewport.twoPane',
  '           │   indexInParent: 11',
  '           │',
  '           ├─SemanticsNode#18',
  '           │   Rect.fromLTRB(0.0, 720.0, 400.0, 780.0)',
  '           │   tags: RenderViewport.twoPane',
  '           │   actions: tap',
  '           │   indexInParent: 12',
  '           │',
  '           ├─SemanticsNode#19',
  '           │   Rect.fromLTRB(0.0, 780.0, 400.0, 860.0)',
  '           │   tags: RenderViewport.twoPane',
  '           │   indexInParent: 13',
  '           │',
  '           ├─SemanticsNode#20',
  '           │   Rect.fromLTRB(0.0, 860.0, 400.0, 940.0)',
  '           │   tags: RenderViewport.twoPane',
  '           │   indexInParent: 14',
  '           │',
  '           ├─SemanticsNode#21',
  '           │   Rect.fromLTRB(0.0, 940.0, 400.0, 1000.0)',
  '           │   tags: RenderViewport.twoPane',
  '           │   indexInParent: 15',
  '           │',
  '           ├─SemanticsNode#22',
  '           │   Rect.fromLTRB(0.0, 1020.0, 400.0, 1100.0)',
  '           │   tags: RenderViewport.twoPane',
  '           │   flags: isHidden',
  '           │   HIDDEN',
  '           │   indexInParent: 16',
  '           │',
  '           ├─SemanticsNode#23',
  '           │   Rect.fromLTRB(0.0, 1100.0, 400.0, 1180.0)',
  '           │   tags: RenderViewport.twoPane',
  '           │   flags: isHidden',
  '           │   HIDDEN',
  '           │   indexInParent: 17',
  '           │',
  '           └─SemanticsNode#24',
  '               Rect.fromLTRB(0.0, 1180.0, 400.0, 1250.0)',
  '               tags: RenderViewport.twoPane',
  '               flags: isHidden',
  '               HIDDEN',
  '               indexInParent: 18',
];
