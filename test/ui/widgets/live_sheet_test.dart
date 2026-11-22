import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/grip_band.dart';
import 'package:anicel/src/ui/widgets/live_sheet.dart';

import '../../helpers/raster_parity.dart';

/// `LiveSheet` — where what a pointer lights is drawn (card
/// the-left-tool-strip-rebakes-on-every-hover, 11-22). What the sheet buys
/// is pinned where it is bought (`a_hover_keeps_its_regions_image_test`,
/// `a_pointer_passing_over_a_strip_takes_no_image_test`); here, that a look
/// drawn on the sheet is the look its box would have painted: the same
/// pixels, in the same place, under and over the same things.
const _red = Color(0xFFE02020);
const _green = Color(0xFF20C040);
const _blue = Color(0xFF2040E0);

/// The surface's box in the capture ([pumpSurface] puts it 20 down).
const double _left = 20;
const double _width = 300;
const double _height = 220;

/// A box that lays one colour over the whole of itself — under what the
/// sheet holds, or over it — as a face lays its state layer and a grip its
/// band ([LaidLook]).
class _Lamp extends LeafRenderObjectWidget {
  const _Lamp(
    this.color, {
    super.key,
    this.over = false,
    this.size = const Size(40, 30),
  });

  /// Null for a lamp that is out.
  final Color? color;
  final bool over;
  final Size size;

  LiveLooks? _looksOf(BuildContext context) =>
      over ? LiveSheet.overOf(context) : LiveSheet.underOf(context);

  @override
  _RenderLamp createRenderObject(BuildContext context) => _RenderLamp()
    ..lampSize = size
    ..wear(_looksOf(context))
    ..color = color;

  @override
  void updateRenderObject(BuildContext context, _RenderLamp renderObject) {
    renderObject
      ..lampSize = size
      ..wear(_looksOf(context))
      ..color = color;
  }
}

class _RenderLamp extends RenderBox {
  /// How many times the sheet drew the lamp's look.
  int drawnBySheet = 0;

  late final LaidLook<Color> laid = LaidLook<Color>(this, (canvas, color) {
    drawnBySheet += 1;
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
  });

  Size _lampSize = Size.zero;
  Size get lampSize => _lampSize;
  set lampSize(Size value) {
    if (value != _lampSize) {
      _lampSize = value;
      markNeedsLayout();
    }
  }

  Color? _color;
  Color? get color => _color;
  set color(Color? value) {
    _color = value;
    if (attached) {
      // Laid again, equal or not: what `lay` makes of an equal look is
      // the sheet's to say.
      laid.lay(value);
      markNeedsPaint();
    }
  }

  void wear(LiveLooks? looks) {
    laid.wear(looks);
    if (attached) {
      laid.lay(_color);
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    laid
      ..attached()
      ..lay(_color);
  }

  @override
  void detach() {
    laid.detached();
    super.detach();
  }

  @override
  void performLayout() => size = constraints.constrain(_lampSize);

  @override
  void paint(PaintingContext context, Offset offset) {
    if (laid.onSheet) {
      return;
    }
    if (_color case final color?) {
      context.canvas.drawRect(offset & size, Paint()..color = color);
    }
  }
}

void main() {
  Future<void> pump(WidgetTester tester, Widget surface) => pumpSurface(
    tester,
    Theme(data: buildAppTheme(), child: surface),
    left: _left,
    width: _width,
    height: _height,
  );

  /// The colour at [at], a point of the surface.
  Color at(WidgetTester tester, ByteData bytes, Offset at) =>
      capturePixelAt(tester, bytes, at + const Offset(_left, 20));

  /// How far the captures [a] and [b] are apart.
  ({int worst, int over, String where, String samples}) apart(
    WidgetTester tester,
    ByteData a,
    ByteData b,
  ) => compareRasters(
    a,
    b,
    width: (parityCaptureWidth * tester.view.devicePixelRatio).round(),
    tolerance: 0,
  );

  void expectSame(
    WidgetTester tester,
    ByteData sheet,
    ByteData inPlace, {
    required String reason,
  }) {
    final gap = apart(tester, sheet, inPlace);
    expect(
      gap.over,
      0,
      reason: '$reason — worst ${gap.worst} at ${gap.where}: ${gap.samples}',
    );
  }

  _RenderLamp lampOf(WidgetTester tester, [Finder? lamp]) =>
      tester.renderObject<_RenderLamp>(lamp ?? find.byType(_Lamp));

  group('a look laid on the sheet', () {
    testWidgets('lies under what the sheet holds, and one laid over it, '
        'over', (tester) async {
      await pump(
        tester,
        const LiveSheet(
          child: Stack(
            children: [
              Positioned(left: 10, top: 10, child: _Lamp(_red)),
              Positioned(
                left: 30,
                top: 20,
                width: 40,
                height: 30,
                child: ColoredBox(color: _blue),
              ),
              Positioned(left: 60, top: 40, child: _Lamp(_green, over: true)),
            ],
          ),
        ),
      );
      final bytes = await captureBytes(tester);
      expect(at(tester, bytes, const Offset(15, 15)), _red);
      expect(
        at(tester, bytes, const Offset(35, 25)),
        _blue,
        reason: 'the box is painted over the lamp laid under',
      );
      expect(
        at(tester, bytes, const Offset(65, 45)),
        _green,
        reason: 'the lamp laid over is painted over the box',
      );
      for (final lamp in tester.renderObjectList<_RenderLamp>(
        find.byType(_Lamp),
      )) {
        expect(lamp.laid.onSheet, isTrue);
        expect(lamp.drawnBySheet, greaterThan(0));
      }
    });

    testWidgets('is drawn where its box stands and as large — through an '
        'offset, a shift and a scale', (tester) async {
      Widget surface(Widget Function(Widget child) sheet) => sheet(
        Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 30, top: 50),
            child: Transform.translate(
              offset: const Offset(12, 7),
              child: Transform.scale(
                scale: 2,
                alignment: Alignment.topLeft,
                child: const _Lamp(_red),
              ),
            ),
          ),
        ),
      );
      await pump(tester, surface((child) => LiveSheet(child: child)));
      expect(lampOf(tester).laid.onSheet, isTrue);
      final onSheet = await captureBytes(tester);
      await pump(tester, surface((child) => LiveSheet.inPlace(child: child)));
      expect(lampOf(tester).laid.onSheet, isFalse);
      final inPlace = await captureBytes(tester);

      // The lamp: 80 × 60 from (42, 57).
      expect(at(tester, inPlace, const Offset(118, 112)), _red);
      expect(at(tester, inPlace, const Offset(126, 112)), isNot(_red));
      expectSame(tester, onSheet, inPlace, reason: 'the lamp on the sheet');
    });

    testWidgets('🎯moves with a scroll in the scroll\'s own frame, and is '
        'cut where its box is', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      // The viewport: 220 × 140 from (40, 40). The lamp: 40 × 30, sixty
      // down what scrolls.
      Widget surface(Widget Function(Widget child) sheet) => sheet(
        Padding(
          padding: const EdgeInsets.all(40),
          child: SingleChildScrollView(
            controller: scroll,
            child: const SizedBox(
              height: 1000,
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: _Lamp(_red),
                ),
              ),
            ),
          ),
        ),
      );
      await pump(tester, surface((child) => LiveSheet(child: child)));
      var bytes = await captureBytes(tester);
      expect(at(tester, bytes, const Offset(50, 110)), _red);
      expect(at(tester, bytes, const Offset(50, 65)), isNot(_red));

      scroll.jumpTo(40);
      // One frame: the scroll's own.
      await tester.pump();
      bytes = await captureBytes(tester);
      expect(
        at(tester, bytes, const Offset(50, 65)),
        _red,
        reason: 'the look went up with its box, in that frame',
      );
      expect(at(tester, bytes, const Offset(50, 125)), isNot(_red));

      // Half out of the viewport's top: the lamp stands 20..50, the
      // viewport starts at 40.
      scroll.jumpTo(80);
      await tester.pump();
      final cut = await captureBytes(tester);
      expect(at(tester, cut, const Offset(50, 45)), _red);
      expect(
        at(tester, cut, const Offset(50, 30)),
        isNot(_red),
        reason: 'what the viewport cuts of the box, it cuts of the look',
      );
      // Another scroll view under another sheet: scrolled as far again.
      await pump(tester, surface((child) => LiveSheet.inPlace(child: child)));
      scroll.jumpTo(80);
      await tester.pump();
      expect(lampOf(tester).laid.onSheet, isFalse);
      expectSame(
        tester,
        cut,
        await captureBytes(tester),
        reason: 'the lamp half scrolled out',
      );
    });

    testWidgets('stands where its box stands a frame after a move nothing '
        'said — a boundary shifted with the box behind it', (tester) async {
      Widget surface(Offset shift) => LiveSheet(
        child: Align(
          alignment: Alignment.topLeft,
          child: Transform.translate(
            offset: shift,
            // The lamp is not painted again for the shift.
            child: const RepaintBoundary(child: _Lamp(_red)),
          ),
        ),
      );
      await pump(tester, surface(const Offset(10, 10)));
      expect(
        at(tester, await captureBytes(tester), const Offset(15, 15)),
        _red,
      );
      await pump(tester, surface(const Offset(100, 80)));
      // The frame the sheet asked for, seeing the box elsewhere.
      await tester.pump();
      final bytes = await captureBytes(tester);
      expect(at(tester, bytes, const Offset(105, 85)), _red);
      expect(at(tester, bytes, const Offset(15, 15)), isNot(_red));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('is as large as its box a frame after the box grew with '
        'the same look', (tester) async {
      Widget surface(Size size) => LiveSheet(
        child: Align(
          alignment: Alignment.topLeft,
          child: _Lamp(_red, size: size),
        ),
      );
      await pump(tester, surface(const Size(40, 30)));
      expect(
        at(tester, await captureBytes(tester), const Offset(80, 15)),
        isNot(_red),
      );
      await pump(tester, surface(const Size(90, 30)));
      await tester.pump();
      expect(
        at(tester, await captureBytes(tester), const Offset(80, 15)),
        _red,
      );
    });

    testWidgets('🎯is not drawn again while it lies still — no frame asks '
        'for it, and an equal look laid again is the same look', (
      tester,
    ) async {
      Widget surface(Color? color) => LiveSheet(
        child: Align(alignment: Alignment.topLeft, child: _Lamp(color)),
      );
      await pump(tester, surface(_red));
      await tester.pump();
      final lamp = lampOf(tester);
      final drawn = lamp.drawnBySheet;
      expect(drawn, greaterThan(0));
      expect(tester.binding.hasScheduledFrame, isFalse);

      for (var frame = 0; frame < 6; frame += 1) {
        tester.binding.scheduleFrame();
        await tester.pump();
      }
      expect(lamp.drawnBySheet, drawn, reason: 'frames drawn for others');
      expect(tester.binding.hasScheduledFrame, isFalse);

      await pump(tester, surface(const Color(0xFFE02020)));
      await tester.pump();
      expect(lamp.drawnBySheet, drawn, reason: 'an equal look laid again');

      await pump(tester, surface(_green));
      expect(lamp.drawnBySheet, drawn + 1, reason: 'another look');
      expect(
        at(tester, await captureBytes(tester), const Offset(15, 15)),
        _green,
      );
    });

    testWidgets('is lifted as its box shows none, and as its box leaves', (
      tester,
    ) async {
      Widget surface(Widget lamp) => LiveSheet(
        child: Align(alignment: Alignment.topLeft, child: lamp),
      );
      await pump(tester, surface(const _Lamp(_red)));
      expect(
        at(tester, await captureBytes(tester), const Offset(15, 15)),
        _red,
      );

      await pump(tester, surface(const _Lamp(null)));
      expect(
        at(tester, await captureBytes(tester), const Offset(15, 15)),
        isNot(_red),
        reason: 'the lamp went out',
      );

      await pump(tester, surface(const _Lamp(_red)));
      await pump(tester, surface(const SizedBox(width: 40, height: 30)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        at(tester, await captureBytes(tester), const Offset(15, 15)),
        isNot(_red),
        reason: 'the lamp left',
      );
    });
  });

  group('a box kept through a move in the tree', () {
    testWidgets('lays its look on the sheet it comes to stand in, and '
        'paints it itself where it leaves one', (tester) async {
      final kept = GlobalKey();
      Widget surface({required bool onSheet}) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            height: 100,
            child: LiveSheet(
              child: Align(
                alignment: Alignment.topLeft,
                child: onSheet ? _Lamp(_red, key: kept) : null,
              ),
            ),
          ),
          SizedBox(
            width: 100,
            height: 100,
            child: LiveSheet.inPlace(
              child: Align(
                alignment: Alignment.topLeft,
                child: onSheet ? null : _Lamp(_red, key: kept),
              ),
            ),
          ),
        ],
      );
      await pump(tester, surface(onSheet: false));
      final lamp = lampOf(tester);
      expect(lamp.laid.onSheet, isFalse);
      expect(
        at(tester, await captureBytes(tester), const Offset(115, 15)),
        _red,
      );

      await pump(tester, surface(onSheet: true));
      expect(lampOf(tester), same(lamp), reason: 'the box is kept');
      expect(lamp.laid.onSheet, isTrue);
      expect(lamp.drawnBySheet, greaterThan(0));
      var bytes = await captureBytes(tester);
      expect(at(tester, bytes, const Offset(15, 15)), _red);
      expect(at(tester, bytes, const Offset(115, 15)), isNot(_red));

      await pump(tester, surface(onSheet: false));
      expect(lampOf(tester), same(lamp));
      expect(lamp.laid.onSheet, isFalse);
      final drawn = lamp.drawnBySheet;
      await tester.pump();
      expect(lamp.drawnBySheet, drawn, reason: 'the sheet it left draws none');
      bytes = await captureBytes(tester);
      expect(at(tester, bytes, const Offset(115, 15)), _red);
      expect(at(tester, bytes, const Offset(15, 15)), isNot(_red));
    });
  });

  group('a look is painted in place', () {
    testWidgets('where its box stands aside, over a ground painted in the '
        'sheet — which covers a look laid under', (tester) async {
      Widget surface(Widget Function(Widget child) lampIn) => LiveSheet(
        child: ColoredBox(
          color: _blue,
          child: Align(
            alignment: Alignment.topLeft,
            child: lampIn(const _Lamp(_red)),
          ),
        ),
      );
      // ⚠️What `inPlace` is for: the ground is painted over the sheet.
      await pump(tester, surface((lamp) => lamp));
      expect(lampOf(tester).laid.onSheet, isTrue);
      expect(
        at(tester, await captureBytes(tester), const Offset(15, 15)),
        _blue,
      );

      await pump(tester, surface((lamp) => LiveSheet.inPlace(child: lamp)));
      final lamp = lampOf(tester);
      expect(lamp.laid.onSheet, isFalse);
      expect(lamp.drawnBySheet, 0);
      expect(
        at(tester, await captureBytes(tester), const Offset(15, 15)),
        _red,
      );
    });

    testWidgets('where its box is built over the sheet and drawn '
        'elsewhere — an overlay\'s', (tester) async {
      final portal = OverlayPortalController()..show();
      await pump(
        tester,
        Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (context) => LiveSheet(
                child: OverlayPortal(
                  controller: portal,
                  overlayChildBuilder: (context) => const Positioned(
                    left: 150,
                    top: 100,
                    child: _Lamp(_red),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final lamp = lampOf(tester);
      expect(lamp.laid.onSheet, isFalse);
      expect(lamp.drawnBySheet, 0);
      expect(
        at(tester, await captureBytes(tester), const Offset(155, 105)),
        _red,
      );
    });
  });

  group('a face on the sheet', () {
    /// The button's captures at rest, under the pointer and pressed.
    Future<({ByteData rest, ByteData hovered, ByteData pressed})> looksOf(
      WidgetTester tester,
      TestGesture mouse,
      Widget surface,
    ) async {
      Future<void> frames() async {
        for (var frame = 0; frame < 3; frame += 1) {
          await tester.pump();
        }
      }

      await mouse.moveTo(const Offset(400, 280));
      await pump(tester, surface);
      await frames();
      final rest = await captureBytes(tester);
      await mouse.moveTo(tester.getCenter(find.byType(AppIconButton)));
      await frames();
      final hovered = await captureBytes(tester);
      await mouse.down(tester.getCenter(find.byType(AppIconButton)));
      await frames();
      final pressed = await captureBytes(tester);
      await mouse.up();
      await frames();
      return (rest: rest, hovered: hovered, pressed: pressed);
    }

    Future<TestGesture> mouseOf(WidgetTester tester) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(400, 280));
      addTearDown(mouse.removePointer);
      return mouse;
    }

    testWidgets('🎯lights the pixels it lights in place — under the '
        'pointer, and pressed', (tester) async {
      final mouse = await mouseOf(tester);
      Widget surface(Widget Function(Widget child) sheet) => sheet(
        Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: AppIconButton(
              keyValue: 'lit',
              tooltip: 'Lit',
              icon: const Icon(Icons.draw),
              onPressed: () {},
            ),
          ),
        ),
      );
      final inPlace = await looksOf(
        tester,
        mouse,
        surface((child) => LiveSheet.inPlace(child: child)),
      );
      final onSheet = await looksOf(
        tester,
        mouse,
        surface((child) => LiveSheet(child: child)),
      );

      expect(
        apart(tester, inPlace.rest, inPlace.hovered).over,
        greaterThan(100),
        reason: 'a hover is seen',
      );
      expect(
        apart(tester, inPlace.rest, inPlace.pressed).over,
        greaterThan(100),
        reason: 'a press is seen',
      );
      expectSame(tester, onSheet.rest, inPlace.rest, reason: 'at rest');
      expectSame(
        tester,
        onSheet.hovered,
        inPlace.hovered,
        reason: 'under the pointer',
      );
      expectSame(tester, onSheet.pressed, inPlace.pressed, reason: 'pressed');
    });

    testWidgets('lights as it is told to while the pointer is on it — '
        'selected under the pointer', (tester) async {
      final mouse = await mouseOf(tester);
      Widget surface(
        Widget Function(Widget child) sheet, {
        required bool selected,
      }) => sheet(
        Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: AppIconButton(
              keyValue: 'lit',
              tooltip: 'Lit',
              icon: const Icon(Icons.draw),
              isSelected: selected,
              onPressed: () {},
            ),
          ),
        ),
      );
      Future<({ByteData before, ByteData after})> toldUnderThePointer(
        Widget Function(Widget child) sheet,
      ) async {
        await mouse.moveTo(const Offset(400, 280));
        await pump(tester, surface(sheet, selected: false));
        await mouse.moveTo(tester.getCenter(find.byType(AppIconButton)));
        await tester.pump();
        await tester.pump();
        final before = await captureBytes(tester);
        await pump(tester, surface(sheet, selected: true));
        await tester.pump();
        return (before: before, after: await captureBytes(tester));
      }

      final inPlace = await toldUnderThePointer(
        (child) => LiveSheet.inPlace(child: child),
      );
      final onSheet = await toldUnderThePointer(
        (child) => LiveSheet(child: child),
      );
      expect(
        apart(tester, inPlace.before, inPlace.after).over,
        greaterThan(0),
        reason: 'selected is seen',
      );
      expectSame(tester, onSheet.before, inPlace.before, reason: 'before');
      expectSame(tester, onSheet.after, inPlace.after, reason: 'selected');
    });

    testWidgets('takes its light with it as it leaves under the '
        'pointer', (tester) async {
      final mouse = await mouseOf(tester);
      Widget surface({required bool there}) => LiveSheet(
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: there
                ? AppIconButton(
                    keyValue: 'leaving',
                    tooltip: 'Leaving',
                    icon: const Icon(Icons.draw),
                    onPressed: () {},
                  )
                : null,
          ),
        ),
      );
      await pump(tester, surface(there: false));
      final bare = await captureBytes(tester);

      await pump(tester, surface(there: true));
      await mouse.moveTo(tester.getCenter(find.byType(AppIconButton)));
      await tester.pump();
      await tester.pump();
      expect(
        apart(tester, bare, await captureBytes(tester)).over,
        greaterThan(100),
        reason: 'the button is there, lit',
      );

      await pump(tester, surface(there: false));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expectSame(
        tester,
        await captureBytes(tester),
        bare,
        reason: 'no light is left where it stood',
      );
    });

    testWidgets('an outlined face paints its own inside, over the ground '
        'it stands on', (tester) async {
      final mouse = await mouseOf(tester);
      // The ground is painted in the sheet: an inside laid under it would
      // not be seen, and an outlined face's edge is that inside's.
      Widget surface(Widget Function(Widget child) sheet) => sheet(
        ColoredBox(
          color: AppColors.surface,
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: AppIconButton(
                keyValue: 'edged',
                tooltip: 'Edged',
                icon: const Icon(Icons.draw),
                outlined: true,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      final inPlace = await looksOf(
        tester,
        mouse,
        surface((child) => LiveSheet.inPlace(child: child)),
      );
      final onSheet = await looksOf(
        tester,
        mouse,
        surface((child) => LiveSheet(child: child)),
      );
      expect(
        apart(tester, inPlace.rest, inPlace.hovered).over,
        greaterThan(100),
        reason: 'a hover is seen',
      );
      expectSame(tester, onSheet.rest, inPlace.rest, reason: 'at rest');
      expectSame(
        tester,
        onSheet.hovered,
        inPlace.hovered,
        reason: 'under the pointer',
      );
    });
  });

  group('a grip\'s band on the sheet', () {
    testWidgets('lies over what it lifts, the pixels it paints in place — '
        'near a hand, and under it', (tester) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(400, 280));
      addTearDown(mouse.removePointer);
      final nearby = ValueNotifier<bool>(false);
      addTearDown(nearby.dispose);
      const grip = ValueKey<String>('grip');
      Widget surface(Widget Function(Widget child) sheet) => sheet(
        Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox.square(
              dimension: 40,
              child: Stack(
                children: [
                  // What the band lifts, painted in the sheet.
                  const Positioned.fill(child: ColoredBox(color: _blue)),
                  Positioned.fill(
                    child: LiftingGripBand<String>(
                      gripKey: grip,
                      data: 'lifted',
                      chip: const [(icon: Icons.draw, label: 'lifted')],
                      nearby: nearby,
                      shape: AppShapes.control(40),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      Future<({ByteData away, ByteData near, ByteData under, ByteData born})>
      looksOf(Widget surface) async {
        nearby.value = false;
        await mouse.moveTo(const Offset(400, 280));
        await pump(tester, surface);
        await tester.pump();
        final away = await captureBytes(tester);
        nearby.value = true;
        await tester.pump();
        await tester.pump();
        final near = await captureBytes(tester);
        await mouse.moveTo(tester.getCenter(find.byKey(grip)));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        final under = await captureBytes(tester);
        // Near a hand as it comes into the tree.
        await mouse.moveTo(const Offset(400, 280));
        await pump(tester, const SizedBox());
        await pump(tester, surface);
        await tester.pump();
        final born = await captureBytes(tester);
        return (away: away, near: near, under: under, born: born);
      }

      final inPlace = await looksOf(
        surface((child) => LiveSheet.inPlace(child: child)),
      );
      final onSheet = await looksOf(
        surface((child) => LiveSheet(child: child)),
      );

      // The band's rows are the box's top ones; the box starts 20 in.
      expect(at(tester, inPlace.away, const Offset(40, 21)), _blue);
      expect(
        at(tester, inPlace.near, const Offset(40, 21)),
        isNot(_blue),
        reason: 'near a hand, the band shows',
      );
      expect(at(tester, inPlace.near, const Offset(40, 24)), _blue);
      expect(
        at(tester, inPlace.under, const Offset(40, 24)),
        isNot(_blue),
        reason: 'under a hand, it is thick',
      );
      expectSame(tester, onSheet.away, inPlace.away, reason: 'no hand near');
      expectSame(tester, onSheet.near, inPlace.near, reason: 'a hand near');
      expectSame(tester, onSheet.under, inPlace.under, reason: 'under a hand');
      expect(
        at(tester, inPlace.born, const Offset(40, 21)),
        isNot(_blue),
        reason: 'a band near a hand as it comes into the tree shows',
      );
      expectSame(tester, onSheet.born, inPlace.born, reason: 'born near');
    });
  });
}
