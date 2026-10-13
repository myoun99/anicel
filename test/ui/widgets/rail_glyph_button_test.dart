import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/app_tooltip.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';
import 'package:anicel/src/ui/widgets/rail_glyph_button.dart';

import '../../helpers/app_faces.dart';
import '../../helpers/named_finders.dart';

/// I-57 ① (유저 2026-10-09: 「가볍기만하면 레일전용버튼해도 상관없어」): the
/// rail's button is ONE render object where an [AppIconButton] is a tree,
/// and it may be lighter only where nothing else about it changes. These
/// pin that: the same pixels as the app's button in every state, the same
/// node for a screen reader, the same press — and the one tooltip window
/// the rail's buttons share, behaving as an [AppTooltip] does.
void main() {
  const box = AppIconButtonBox(width: 22, height: 26, iconSize: 16);

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: Center(child: child)),
    ),
  );

  Future<TestGesture> mouseAt(WidgetTester tester, Offset position) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: position);
    addTearDown(mouse.removePointer);
    return mouse;
  }

  // Past the fade either way and the exit delay, in frames (as the
  // AppTooltip tests settle theirs).
  Future<void> settleTooltip(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 10; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  int globalRoutes() =>
      GestureBinding.instance.pointerRouter.debugGlobalRouteCount;

  Finder byKey(String key) => find.byKey(ValueKey<String>(key));
  Finder byName(String name) => find.named(name);

  group('it paints what the app\'s icon button paints', () {
    // The glyphs' own shapes, not the test font's boxes — without them
    // every icon is the same square and a wrong glyph compares equal (the
    // control below caught exactly that: the parity was measuring nothing).
    setUpAll(() async {
      await loadTheAppFaces();
      await loadIcons();
    });

    Future<Uint8List> pixels(WidgetTester tester, String key) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        byKey(key),
      );
      late Uint8List bytes;
      await tester.runAsync(() async {
        final image = await boundary.toImage(
          pixelRatio: tester.view.devicePixelRatio,
        );
        bytes = (await image.toByteData())!.buffer.asUint8List();
        image.dispose();
      });
      return bytes;
    }

    /// The two buttons side by side, each in a boundary of its own, made
    /// from the SAME inputs — [icon] is the app button's spelling of
    /// [glyph].
    Future<void> pumpPair(
      WidgetTester tester, {
      required Widget icon,
      required RailGlyph glyph,
      VoidCallback? onPressed,
      bool isSelected = false,
      bool danger = false,
      bool outlined = false,
      AppIconButtonMetrics size = box,
    }) => pump(
      tester,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RepaintBoundary(
            key: const ValueKey<String>('app'),
            child: AppIconButton(
              keyValue: 'app-face',
              tooltip: 'Same',
              icon: icon,
              onPressed: onPressed,
              isSelected: isSelected,
              danger: danger,
              outlined: outlined,
              size: size,
            ),
          ),
          const SizedBox(width: 40),
          RepaintBoundary(
            key: const ValueKey<String>('rail'),
            child: RailGlyphButton(
              name: 'rail-face',
              tooltip: 'Same',
              glyph: glyph,
              onPressed: onPressed,
              isSelected: isSelected,
              danger: danger,
              outlined: outlined,
              size: size,
            ),
          ),
        ],
      ),
    );

    /// At rest, hovered and pressed, the rail's face against the app's.
    Future<void> expectTheSamePixels(WidgetTester tester) async {
      expect(
        tester.getSize(byName('rail-face')),
        tester.getSize(byKey('app-face')),
        reason: 'the same box',
      );
      expect(
        await pixels(tester, 'rail'),
        await pixels(tester, 'app'),
        reason: 'at rest',
      );

      final mouse = await mouseAt(tester, Offset.zero);
      await mouse.moveTo(tester.getCenter(byKey('app-face')));
      await tester.pump();
      final appHovered = await pixels(tester, 'app');
      await mouse.moveTo(tester.getCenter(byName('rail-face')));
      await tester.pump();
      expect(await pixels(tester, 'rail'), appHovered, reason: 'hovered');
      await mouse.moveTo(Offset.zero);
      await tester.pump();

      final onApp = await tester.startGesture(
        tester.getCenter(byKey('app-face')),
      );
      await tester.pump();
      final appPressed = await pixels(tester, 'app');
      await onApp.up();
      await tester.pump();
      final onRail = await tester.startGesture(
        tester.getCenter(byName('rail-face')),
      );
      await tester.pump();
      expect(await pixels(tester, 'rail'), appPressed, reason: 'pressed');
      await onRail.up();
      await settleTooltip(tester);
    }

    testWidgets('an icon at rest, hovered and pressed', (tester) async {
      await pumpPair(
        tester,
        icon: const Icon(Icons.visibility),
        glyph: const RailIconGlyph(Icons.visibility),
        onPressed: () {},
      );
      await expectTheSamePixels(tester);
    });

    testWidgets('the ON state — accent ink', (tester) async {
      await pumpPair(
        tester,
        icon: const Icon(Icons.filter_none),
        glyph: const RailIconGlyph(Icons.filter_none),
        onPressed: () {},
        isSelected: true,
      );
      await expectTheSamePixels(tester);
    });

    testWidgets('danger, outlined', (tester) async {
      await pumpPair(
        tester,
        icon: const Icon(Icons.movie),
        glyph: const RailIconGlyph(Icons.movie),
        onPressed: () {},
        danger: true,
        outlined: true,
      );
      await expectTheSamePixels(tester);
    });

    testWidgets('dead — the dim ink, and no layer under a hover', (
      tester,
    ) async {
      await pumpPair(
        tester,
        icon: const Icon(Icons.visibility),
        glyph: const RailIconGlyph(Icons.visibility),
      );
      await expectTheSamePixels(tester);
    });

    testWidgets('a glyph in its own colour keeps it in every state', (
      tester,
    ) async {
      final own = AppColors.accent.withValues(alpha: 0.5);
      await pumpPair(
        tester,
        icon: Icon(Icons.volume_up, color: own),
        glyph: RailIconGlyph(Icons.volume_up, color: own),
        onPressed: () {},
      );
      await expectTheSamePixels(tester);
    });

    testWidgets('a word set in type, as the fx switch is', (tester) async {
      const style = TextStyle(
        fontSize: 13,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w700,
      );
      await pumpPair(
        tester,
        icon: const Text('fx', textScaler: TextScaler.noScaling, style: style),
        glyph: const RailTextGlyph('fx', style: style),
        onPressed: () {},
      );
      await expectTheSamePixels(tester);
    });

    testWidgets('a token\'s box, laid on the device grid', (tester) async {
      await pumpPair(
        tester,
        icon: const Icon(Icons.settings_backup_restore),
        glyph: const RailIconGlyph(Icons.settings_backup_restore),
        onPressed: () {},
        size: AppIconButtonSize.micro,
      );
      await expectTheSamePixels(tester);
    });

    testWidgets('⛔CONTROL: a different glyph is different pixels', (
      tester,
    ) async {
      await pumpPair(
        tester,
        icon: const Icon(Icons.visibility),
        glyph: const RailIconGlyph(Icons.visibility_off),
        onPressed: () {},
      );
      expect(
        await pixels(tester, 'rail'),
        isNot(await pixels(tester, 'app')),
        reason: 'the comparison can see a glyph',
      );
    });

    testWidgets('a button that CHANGES shows what a fresh one would — the '
        'face repaints and lays out again only when it must, never less', (
      tester,
    ) async {
      Widget rail(RailGlyphButton button) =>
          RepaintBoundary(key: const ValueKey<String>('rail'), child: button);
      RailGlyphButton button({required bool on, required String word}) =>
          RailGlyphButton(
            name: 'changing',
            tooltip: 'Changing',
            glyph: RailTextGlyph(word, style: const TextStyle(fontSize: 13)),
            onPressed: () {},
            isSelected: on,
            size: AppIconButtonSize.micro,
          );

      // The ON state: the face only repaints.
      await pump(tester, rail(button(on: false, word: 'x')));
      final rest = await pixels(tester, 'rail');
      await pump(tester, rail(button(on: true, word: 'x')));
      final changed = await pixels(tester, 'rail');
      await pump(tester, const SizedBox());
      await pump(tester, rail(button(on: true, word: 'x')));
      expect(changed, await pixels(tester, 'rail'), reason: 'repainted');
      expect(changed, isNot(rest), reason: '⛔CONTROL: the state shows');

      // A bigger word: the face lays out again (a token's box grows with
      // its glyph, up to the token's width).
      final small = tester.getSize(byName('changing'));
      await pump(tester, rail(button(on: true, word: 'xxxxxxxx')));
      final grown = tester.getSize(byName('changing'));
      await pump(tester, const SizedBox());
      await pump(tester, rail(button(on: true, word: 'xxxxxxxx')));
      expect(grown, tester.getSize(byName('changing')), reason: 'laid out');
      expect(grown, isNot(small), reason: '⛔CONTROL: the word moves the box');
    });
  });

  group('a screen reader hears what it heard from the app\'s button', () {
    testWidgets('ONE node: the tooltip, a button, enabled, selected — and '
        'the way it reads', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RailGlyphButton(
              name: 'a11y-a',
              tooltip: 'Eye',
              glyph: const RailIconGlyph(Icons.visibility),
              onPressed: () {},
              isSelected: true,
              size: box,
            ),
            RailGlyphButton(
              name: 'a11y-b',
              tooltip: 'Lock',
              glyph: const RailIconGlyph(Icons.lock),
              onPressed: () {},
              size: box,
            ),
          ],
        ),
      );
      expect(
        tester.getSemantics(byName('a11y-a')),
        isSemantics(
          tooltip: 'Eye',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isSelected: true,
          hasTapAction: true,
          textDirection: TextDirection.ltr,
        ),
      );
      expect(
        tester.getSemantics(byName('a11y-a')).id,
        isNot(tester.getSemantics(byName('a11y-b')).id),
        reason: 'a row of buttons is not one long button',
      );
      handle.dispose();
    });

    testWidgets('a button with no tooltip says its name — the type '
        'button\'s kind', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        RailGlyphButton(
          name: 'named',
          tooltip: '',
          semanticLabel: 'Folder',
          glyph: const RailIconGlyph(Icons.folder),
          onPressed: () {},
          size: box,
        ),
      );
      expect(
        tester.getSemantics(byName('named')),
        isSemantics(
          label: 'Folder',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          textDirection: TextDirection.ltr,
        ),
      );
      handle.dispose();
    });

    testWidgets('🚨"double-tap to activate" presses it ONCE — and a finger '
        'still presses it once, not twice', (tester) async {
      var fired = 0;
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        RailGlyphButton(
          name: 'reader',
          tooltip: 'Reader',
          glyph: const RailIconGlyph(Icons.draw),
          onPressed: () => fired += 1,
          size: box,
        ),
      );
      final node = tester.getSemantics(byName('reader'));
      tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.tap,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(fired, 1, reason: 'the screen reader pressed it');

      await tester.tap(byName('reader'));
      await tester.pump(const Duration(seconds: 2));
      expect(fired, 2, reason: 'a finger presses it exactly once');
      handle.dispose();
    });

    testWidgets('a DEAD button offers a screen reader nothing to press', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        const RailGlyphButton(
          name: 'reader-dead',
          tooltip: 'Reader dead',
          glyph: RailIconGlyph(Icons.draw),
          onPressed: null,
          size: box,
        ),
      );
      final node = tester.getSemantics(byName('reader-dead'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      expect(
        node,
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
        reason: 'a dead button, said so',
      );
      handle.dispose();
    });
  });

  testWidgets('the cursor says whether a press does anything', (tester) async {
    await pump(
      tester,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RailGlyphButton(
            name: 'live',
            tooltip: 'Live',
            glyph: const RailIconGlyph(Icons.draw),
            onPressed: () {},
            size: box,
          ),
          const SizedBox(width: 40),
          const RailGlyphButton(
            name: 'dead',
            tooltip: 'Dead',
            glyph: RailIconGlyph(Icons.draw),
            onPressed: null,
            size: box,
          ),
        ],
      ),
    );
    final mouse = await mouseAt(tester, Offset.zero);
    // A test mouse is device 1, whatever its pointer.
    MouseCursor cursor() =>
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1)!;

    await mouse.moveTo(tester.getCenter(byName('live')));
    await tester.pump();
    expect(cursor(), SystemMouseCursors.click);
    await mouse.moveTo(tester.getCenter(byName('dead')));
    await tester.pump();
    expect(cursor(), SystemMouseCursors.basic);
    await mouse.moveTo(const Offset(790, 590));
    await settleTooltip(tester);
  });

  group('a press is the button\'s', () {
    testWidgets('🚨a tap on it does NOT also tap the row around it', (
      tester,
    ) async {
      var rowTaps = 0;
      var buttonTaps = 0;
      await pump(
        tester,
        SizedBox(
          width: 300,
          child: GestureDetector(
            key: const ValueKey<String>('row'),
            // A row is pressed anywhere on it, not only on what it holds.
            behavior: HitTestBehavior.opaque,
            onTap: () => rowTaps += 1,
            child: Row(
              children: [
                const SizedBox(width: 100, height: 40),
                RailGlyphButton(
                  name: 'inner',
                  tooltip: 'Inner',
                  glyph: const RailIconGlyph(Icons.delete),
                  onPressed: () => buttonTaps += 1,
                  size: box,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(byName('inner'));
      await tester.pump(const Duration(seconds: 2));
      expect(buttonTaps, 1);
      expect(rowTaps, 0, reason: 'the row must not answer its button\'s press');

      await tester.tapAt(tester.getTopLeft(byKey('row')) + const Offset(20, 20));
      await tester.pump(const Duration(seconds: 2));
      expect(rowTaps, 1, reason: '⛔CONTROL: the row still answers its own');
    });

    testWidgets('a button that goes dead under the finger stops looking '
        'pressed', (tester) async {
      Widget button(VoidCallback? onPressed) => RailGlyphButton(
        name: 'going',
        tooltip: 'Going',
        glyph: const RailIconGlyph(Icons.draw),
        onPressed: onPressed,
        size: box,
      );
      await pump(tester, button(() {}));
      final face = tester.renderObject<RenderRailGlyphFace>(byName('going'));
      final press = await tester.startGesture(
        tester.getCenter(byName('going')),
      );
      await tester.pump();
      expect(face.debugState.pressed, isTrue, reason: '⛔CONTROL');

      await pump(tester, button(null));
      expect(face.debugState.pressed, isFalse);
      await press.up();
      await settleTooltip(tester);
    });
  });

  testWidgets('🚨one button is the claim and ONE leaf — four render objects '
      'where the app\'s button is twenty', (tester) async {
    await pump(
      tester,
      RailGlyphButton(
        name: 'weight',
        tooltip: 'Weight',
        glyph: const RailIconGlyph(Icons.draw),
        onPressed: () {},
        size: box,
      ),
    );
    var renderObjects = 0;
    void visit(Element element) {
      if (element is RenderObjectElement) {
        renderObjects += 1;
      }
      element.visitChildren(visit);
    }

    visit(tester.element(find.byType(RailGlyphButton)));
    // ⛔THE POINT OF THE ROUND, as a number: the claim's three (its gesture
    // semantics and two listeners) and the face. A wrapper slipped around
    // the face fails here on purpose.
    expect(renderObjects, lessThanOrEqualTo(4));
  });

  group('the one tooltip window', () {
    Widget rail(int index, {String? tooltip}) => RailGlyphButton(
      name: 'rail-$index',
      tooltip: tooltip ?? 'tip $index',
      glyph: const RailIconGlyph(Icons.draw),
      onPressed: () {},
      size: box,
    );

    Future<void> pumpRail(WidgetTester tester, {String? tooltip}) => pump(
      tester,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 6; i += 1) ...[
            rail(i, tooltip: tooltip),
            const SizedBox(width: 30),
          ],
        ],
      ),
    );

    testWidgets('six buttons at rest hold no window and no route', (
      tester,
    ) async {
      await pump(tester, const SizedBox());
      final bare = globalRoutes();
      await pumpRail(tester);
      expect(globalRoutes(), bare);
      expect(SummonedTooltip.debugTarget, isNull);
    });

    testWidgets('a hover summons it with the button\'s words and holds the '
        'route while it shows; leaving lets both go', (tester) async {
      await pumpRail(tester);
      final bare = globalRoutes();
      final mouse = await mouseAt(tester, Offset.zero);
      await mouse.moveTo(tester.getCenter(byName('rail-3')));
      await settleTooltip(tester);
      expect(find.text('tip 3'), findsOneWidget);
      expect(SummonedTooltip.debugShownMessage, 'tip 3');
      expect(globalRoutes(), bare + 1);

      await mouse.moveTo(const Offset(790, 590));
      await settleTooltip(tester);
      expect(find.text('tip 3'), findsNothing);
      expect(SummonedTooltip.debugShownMessage, isNull);
      expect(globalRoutes(), bare);
    });

    testWidgets('it fades in, as an AppTooltip does', (tester) async {
      await pumpRail(tester);
      final mouse = await mouseAt(tester, Offset.zero);
      await mouse.moveTo(tester.getCenter(byName('rail-3')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      double opacity() => tester
          .widget<FadeTransition>(
            find.ancestor(
              of: find.text('tip 3'),
              matching: find.byType(FadeTransition),
            ),
          )
          .opacity
          .value;
      expect(opacity(), allOf(greaterThan(0), lessThan(1)), reason: 'midway');
      await settleTooltip(tester);
      expect(opacity(), 1);
      await mouse.moveTo(const Offset(790, 590));
      await settleTooltip(tester);
    });

    testWidgets('a button taken off the screen while its window shows takes '
        'the window and the route with it', (tester) async {
      await pump(tester, const SizedBox());
      final bare = globalRoutes();
      await pumpRail(tester);
      final mouse = await mouseAt(tester, Offset.zero);
      await mouse.moveTo(tester.getCenter(byName('rail-3')));
      await settleTooltip(tester);
      expect(find.text('tip 3'), findsOneWidget);

      await pump(tester, const SizedBox());
      await tester.pump();
      expect(find.text('tip 3'), findsNothing);
      expect(SummonedTooltip.debugTarget, isNull);
      expect(globalRoutes(), bare);
      await mouse.moveTo(const Offset(790, 590));
      await settleTooltip(tester);
    });

    testWidgets('ONE window for the crowd: the next button takes it over, '
        'never a second beside it', (tester) async {
      await pumpRail(tester);
      final mouse = await mouseAt(tester, Offset.zero);
      await mouse.moveTo(tester.getCenter(byName('rail-1')));
      await settleTooltip(tester);
      await mouse.moveTo(tester.getCenter(byName('rail-2')));
      await settleTooltip(tester);
      expect(find.text('tip 1'), findsNothing);
      expect(find.text('tip 2'), findsOneWidget);
      await mouse.moveTo(const Offset(790, 590));
      await settleTooltip(tester);
    });

    testWidgets('a press somewhere else takes it down', (tester) async {
      await pumpRail(tester);
      final bare = globalRoutes();
      final mouse = await mouseAt(tester, Offset.zero);
      await mouse.moveTo(tester.getCenter(byName('rail-3')));
      await settleTooltip(tester);
      expect(find.text('tip 3'), findsOneWidget);

      await tester.tapAt(const Offset(790, 590));
      await settleTooltip(tester);
      expect(
        find.text('tip 3'),
        findsNothing,
        reason: 'the mouse still hovers it; only the press elsewhere hides it',
      );
      expect(globalRoutes(), bare);
      await mouse.moveTo(const Offset(790, 590));
      await settleTooltip(tester);
    });

    testWidgets('a long press summons it for a finger, and after the show '
        'duration it goes and lets go', (tester) async {
      await pumpRail(tester);
      final bare = globalRoutes();
      await tester.longPress(byName('rail-4'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('tip 4'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1500));
      await settleTooltip(tester);
      expect(find.text('tip 4'), findsNothing);
      expect(globalRoutes(), bare);
    });

    testWidgets('dismissAllToolTips takes the summoned window down too', (
      tester,
    ) async {
      await pumpRail(tester);
      final mouse = await mouseAt(tester, Offset.zero);
      await mouse.moveTo(tester.getCenter(byName('rail-0')));
      await settleTooltip(tester);
      expect(find.text('tip 0'), findsOneWidget);

      expect(AppTooltip.dismissAllToolTips(), isTrue);
      await settleTooltip(tester);
      expect(find.text('tip 0'), findsNothing);
      expect(SummonedTooltip.debugTarget, isNull);
      await mouse.moveTo(const Offset(790, 590));
      await settleTooltip(tester);
    });

    testWidgets('an EMPTY tooltip summons nothing, as an AppTooltip\'s empty '
        'message shows nothing', (tester) async {
      await pumpRail(tester, tooltip: '');
      final bare = globalRoutes();
      final mouse = await mouseAt(tester, Offset.zero);
      await mouse.moveTo(tester.getCenter(byName('rail-2')));
      await settleTooltip(tester);
      expect(SummonedTooltip.debugTarget, isNull);
      expect(globalRoutes(), bare);
      await mouse.moveTo(const Offset(790, 590));
      await settleTooltip(tester);
    });

    testWidgets('🚨a window whose target has gone lets its route go — the '
        'route is held before the show, so the close finds it', (
      tester,
    ) async {
      late BuildContext context;
      await pump(
        tester,
        Builder(
          builder: (inside) {
            context = inside;
            return const SizedBox();
          },
        ),
      );
      final bare = globalRoutes();
      // A hover's wait is zero in this app (유저 F-53), so the show runs at
      // once — and finds no box to stand by.
      SummonedTooltip.hover(_Gone(context));
      expect(SummonedTooltip.debugTarget, isNull, reason: 'it closed');
      expect(globalRoutes(), bare);
    });

    testWidgets('it wears an AppTooltip\'s look — the same words come out '
        'the same size', (tester) async {
      await pump(
        tester,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppTooltip(
              message: 'Same words',
              child: SizedBox(
                key: ValueKey<String>('app-target'),
                width: 24,
                height: 24,
              ),
            ),
            const SizedBox(width: 60),
            rail(9, tooltip: 'Same words'),
          ],
        ),
      );
      final mouse = await mouseAt(tester, Offset.zero);
      await mouse.moveTo(tester.getCenter(byKey('app-target')));
      await settleTooltip(tester);
      final app = tester.getSize(find.text('Same words'));
      await mouse.moveTo(tester.getCenter(byName('rail-9')));
      await settleTooltip(tester);
      expect(tester.getSize(find.text('Same words')), app);
      await mouse.moveTo(const Offset(790, 590));
      await settleTooltip(tester);
    });
  });

  // The mark's and the take's plates (I-57 ①): the plate draws itself, and
  // the ONE render object around it is the button a [RailGlyphButton] is.
  group('a pressed PLATE is the same press', () {
    Widget plate({required VoidCallback onRow, required VoidCallback onPick}) =>
        SizedBox(
          width: 300,
          child: GestureDetector(
            key: const ValueKey<String>('row'),
            behavior: HitTestBehavior.opaque,
            onTap: onRow,
            child: Row(
              children: [
                const SizedBox(width: 100, height: 40),
                RailFlyoutTrigger(
                  name: 'plate',
                  tooltip: 'Plate tip',
                  semanticLabel: 'Plate',
                  entriesBuilder: () => [
                    PanelFlyoutItem(
                      keyValue: 'plate-pick',
                      label: 'Pick',
                      onSelected: onPick,
                    ),
                  ],
                  child: const ColoredBox(
                    color: Colors.white,
                    child: SizedBox(width: 30, height: 20),
                  ),
                ),
              ],
            ),
          ),
        );

    testWidgets('🚨a tap opens the shared list through the claim — and does '
        'NOT also tap the row around it', (tester) async {
      var rowTaps = 0;
      var picks = 0;
      await pump(
        tester,
        plate(onRow: () => rowTaps += 1, onPick: () => picks += 1),
      );
      await tester.tap(byName('plate'));
      await tester.pumpAndSettle();
      expect(byKey('plate-pick'), findsOneWidget, reason: 'the list opened');
      expect(rowTaps, 0, reason: 'the row must not answer its plate\'s press');
      await tester.tap(byKey('plate-pick'));
      await tester.pumpAndSettle();
      expect(picks, 1);
    });

    testWidgets('a hover summons the one window with its words, and the '
        'cursor says it is pressed', (tester) async {
      await pump(tester, plate(onRow: () {}, onPick: () {}));
      final mouse = await mouseAt(tester, Offset.zero);
      await mouse.moveTo(tester.getCenter(byName('plate')));
      await settleTooltip(tester);
      expect(SummonedTooltip.debugShownMessage, 'Plate tip');
      expect(
        tester.renderObject<RenderRailPlateFace>(byName('plate')).cursor,
        SystemMouseCursors.click,
      );
      await mouse.moveTo(const Offset(790, 590));
      await settleTooltip(tester);
      expect(SummonedTooltip.debugShownMessage, isNull);
    });

    testWidgets('ONE node for a screen reader: a button with its name and '
        'its tooltip, whose activation opens the list', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, plate(onRow: () {}, onPick: () {}));
      final node = tester.getSemantics(byName('plate'));
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.label, 'Plate');
      expect(data.tooltip, 'Plate tip');
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.tap,
      );
      await tester.pumpAndSettle();
      expect(byKey('plate-pick'), findsOneWidget, reason: 'the list opened');
      semantics.dispose();
    });

    testWidgets('🚨the press is the claim and ONE render object around the '
        'plate', (tester) async {
      await pump(tester, plate(onRow: () {}, onPick: () {}));
      var renderObjects = 0;
      void visit(Element element) {
        if (element is RenderObjectElement) {
          renderObjects += 1;
        }
        element.visitChildren(visit);
      }

      visit(tester.element(find.byType(RailFlyoutTrigger)));
      // The claim's three and the face — and the plate's own two (a colour
      // and a box) under it.
      expect(renderObjects, lessThanOrEqualTo(6));
    });
  });
}

/// A target that has a context to show from and no box on screen — a
/// button taken off the screen between its hover and its show.
final class _Gone implements SummonedTooltipTarget {
  _Gone(this.tooltipContext);

  @override
  final BuildContext tooltipContext;

  @override
  String get tooltipMessage => 'gone';

  @override
  Rect? get tooltipGlobalRect => null;
}
