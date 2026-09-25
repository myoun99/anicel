import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

/// R26 #42: the canvas bottom bar's icon style is the app's DEFAULT icon
/// UI now, so it lives in one widget and other surfaces mount that widget
/// — these pin both halves of that claim (the style itself, and the
/// timesheet actually wearing it).
///
/// 🆕2026-09-10 (유저 「2번가자」): the Material `IconButton` inside is gone —
/// it was 27 render objects a button and 47% of the idle screen. Everything
/// below that says "M3" is a number read out of Flutter's own
/// `_IconButtonDefaultsM3` / `IconButton.styleFrom`, so the light face is
/// pinned to what the heavy one painted, not to what looked about right.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: child))),
    );
  }

  Color glyphColor(WidgetTester tester, String key) => IconTheme.of(
    tester.element(
      find.descendant(
        of: find.byKey(ValueKey<String>(key)),
        matching: find.byType(Icon),
      ),
    ),
  ).color!;

  ColorScheme schemeOf(WidgetTester tester, String key) =>
      Theme.of(tester.element(find.byKey(ValueKey<String>(key)))).colorScheme;

  // The face's OWN state layer: the DecoratedBox wrapped around the glyph's
  // `Align(widthFactor: 1)`. ⚠️A plain `byType(DecoratedBox)` under the key
  // finds TWO while hovered — hovering shows the Tooltip, and an
  // OverlayPortal's overlay child is its descendant in the element tree, so
  // the bubble's box answers too.
  final faceLayer = find.byWidgetPredicate(
    (widget) =>
        widget is DecoratedBox &&
        widget.child is Align &&
        (widget.child! as Align).widthFactor == 1.0,
    description: 'the face state layer',
  );

  // What `IconButton.styleFrom` makes of a colour for a state layer:
  // `withOpacity`, which rounds the alpha to 8 bits (0.08 → 20/255). The
  // face takes its layers from styleFrom itself, so this is the colour it
  // paints; a float `withValues(alpha: 0.08)` is the same pixel but not an
  // equal Color.
  Color stateLayer(Color base, double opacity) =>
      base.withAlpha((255.0 * opacity).round());

  group('AppIconButton', () {
    testWidgets('the ON state is ACCENT INK, not a check mark or a fill '
        '(the app selection rule)', (tester) async {
      await pump(
        tester,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIconButton(
              keyValue: 'on',
              tooltip: 'On',
              icon: const Icon(Icons.draw),
              onPressed: () {},
              isSelected: true,
            ),
            AppIconButton(
              keyValue: 'off',
              tooltip: 'Off',
              icon: const Icon(Icons.draw),
              onPressed: () {},
            ),
          ],
        ),
      );

      // ⚠️The painted colour, not a style object: the old form read
      // `style.foregroundColor.resolve({})` off two DISABLED buttons, which
      // is a number M3 never painted — a disabled button is 0.38 onSurface
      // whether it is selected or not (next test).
      expect(glyphColor(tester, 'on'), AppColors.accent);
      expect(glyphColor(tester, 'off'), schemeOf(tester, 'off').onSurfaceVariant);
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('an OUTLINED button draws its edge — the hairline at rest, '
        'the accent while ON — and a plain one draws none', (tester) async {
      BorderSide edgeOf(String key) {
        final box = tester.widget<DecoratedBox>(
          find.descendant(
            of: find.byKey(ValueKey<String>(key)),
            matching: faceLayer,
          ),
        );
        final shape = (box.decoration as ShapeDecoration).shape;
        return (shape as OutlinedBorder).side;
      }

      await pump(
        tester,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (key, outlined, selected) in const [
              ('rest', true, false),
              ('lit', true, true),
              ('plain', false, true),
            ])
              AppIconButton(
                keyValue: key,
                tooltip: key,
                icon: const Icon(Icons.insert_drive_file_outlined),
                onPressed: () {},
                isSelected: selected,
                outlined: outlined,
              ),
          ],
        ),
      );

      expect(edgeOf('rest').color, AppColors.hairlineStrong);
      expect(edgeOf('lit').color, AppColors.accent);
      expect(edgeOf('plain'), BorderSide.none);
    });

    testWidgets('a DISABLED button is onSurface at 0.38 — selected or not, '
        'as M3 paints it', (tester) async {
      await pump(
        tester,
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIconButton(
              keyValue: 'dead-on',
              tooltip: 'Dead on',
              icon: Icon(Icons.draw),
              onPressed: null,
              isSelected: true,
            ),
            AppIconButton(
              keyValue: 'dead-off',
              tooltip: 'Dead off',
              icon: Icon(Icons.draw),
              onPressed: null,
            ),
          ],
        ),
      );

      final dim = schemeOf(tester, 'dead-on').onSurface.withValues(alpha: 0.38);
      expect(glyphColor(tester, 'dead-on'), dim);
      expect(glyphColor(tester, 'dead-off'), dim);
      expect(
        tester
            .widget<AppIconButtonFace>(find.byKey(const ValueKey('dead-on')))
            .onPressed,
        isNull,
        reason: 'the key still names the box a test reads null-ness off',
      );
    });

    testWidgets('a TEXT glyph takes the same colour as an icon would', (
      tester,
    ) async {
      await pump(
        tester,
        AppIconButton(
          keyValue: 'text',
          tooltip: 'Actual size',
          icon: const Text('1:1'),
          onPressed: () {},
          isSelected: true,
        ),
      );
      // The promise [AppIconButton.icon] makes. ⚠️Material never kept it —
      // an IconButton has no text style, so its Material fell back to the
      // theme's `bodyMedium`; the face keeps it with a DefaultTextStyle.
      final style = DefaultTextStyle.of(tester.element(find.text('1:1')));
      expect(style.style.color, AppColors.accent);
    });

    testWidgets('the size token drives the box: the strip variant is '
        'shorter than the bar variant but keeps the same shape', (
      tester,
    ) async {
      await pump(
        tester,
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIconButton(
              keyValue: 'bar',
              tooltip: 'Bar',
              icon: Icon(Icons.draw),
              onPressed: null,
            ),
            AppIconButton(
              keyValue: 'strip',
              tooltip: 'Strip',
              icon: Icon(Icons.draw),
              onPressed: null,
              size: AppIconButtonSize.strip,
            ),
          ],
        ),
      );

      final bar = tester.getSize(find.byKey(const ValueKey<String>('bar')));
      final strip = tester.getSize(find.byKey(const ValueKey<String>('strip')));

      expect(bar.height, AppIconButtonSize.bar.height);
      expect(strip.height, AppIconButtonSize.strip.height);
      expect(strip.height, lessThan(bar.height));
    });

    testWidgets('the box HUGS the glyph up to the token — a bar button with '
        'an 18px icon is its MIN width, not its max', (tester) async {
      await pump(
        tester,
        AppIconButton(
          keyValue: 'hug',
          tooltip: 'Hug',
          icon: const Icon(Icons.draw),
          onPressed: () {},
        ),
      );
      // M3 lays the child in `Align(widthFactor: 1, heightFactor: 1)`. A
      // `Center` there expands to the max constraint instead and widens every
      // bar button from 26 to 30 — the kind of change a hundred layout tests
      // notice without naming.
      final size = tester.getSize(find.byKey(const ValueKey<String>('hug')));
      expect(size.width, AppIconButtonSize.bar.minWidth);
      expect(size.height, AppIconButtonSize.bar.height);
    });

    testWidgets('hover, press and release lay M3\'s state layer over the box', (
      tester,
    ) async {
      await pump(
        tester,
        AppIconButton(
          keyValue: 'layer',
          tooltip: 'Layer',
          icon: const Icon(Icons.draw),
          onPressed: () {},
        ),
      );
      Color? layer() {
        final box = tester.widget<DecoratedBox>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('layer')),
            matching: faceLayer,
          ),
        );
        return (box.decoration as ShapeDecoration).color;
      }

      final base = schemeOf(tester, 'layer').onSurfaceVariant;
      final center = tester.getCenter(find.byKey(const ValueKey('layer')));
      expect(layer(), isNull, reason: 'nothing is laid over a button at rest');

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(center);
      await tester.pump();
      expect(layer(), stateLayer(base, 0.08), reason: 'hovered');

      await mouse.down(center);
      await tester.pump();
      expect(layer(), stateLayer(base, 0.1), reason: 'pressed wins');

      await mouse.up();
      await tester.pump();
      expect(layer(), stateLayer(base, 0.08), reason: 'still hovered');

      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(seconds: 2));
      expect(layer(), isNull, reason: 'the pointer left');
    });

    testWidgets('a SELECTED button\'s layer is the accent, as styleFrom '
        'derives it from the foreground', (tester) async {
      await pump(
        tester,
        AppIconButton(
          keyValue: 'sel',
          tooltip: 'Sel',
          icon: const Icon(Icons.draw),
          onPressed: () {},
          isSelected: true,
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('sel'))));
      await tester.pump();
      final box = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('sel')),
          matching: faceLayer,
        ),
      );
      expect(
        (box.decoration as ShapeDecoration).color,
        stateLayer(AppColors.accent, 0.08),
      );
      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('🚨in the APP\'S theme it paints what Material painted — the '
        'IconButtonTheme\'s colours, not M3\'s defaults', (tester) async {
      // Measured 2026-09-10 before this test existed: 65 of the 94 buttons on
      // the idle screen came out dimmer, because the face went straight to
      // M3's defaults and skipped the app's `iconButtonTheme` (foreground
      // AppColors.text, disabled AppColors.textDim at 0.5). Material resolves
      // own style → theme → defaults, first non-null wins; a plain
      // MaterialApp has no theme step, which is why the tests above could not
      // see it.
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIconButton(
                    keyValue: 'app-rest',
                    tooltip: 'Rest',
                    icon: const Icon(Icons.draw),
                    onPressed: () {},
                  ),
                  const AppIconButton(
                    keyValue: 'app-dead',
                    tooltip: 'Dead',
                    icon: Icon(Icons.draw),
                    onPressed: null,
                  ),
                  AppIconButton(
                    keyValue: 'app-on',
                    tooltip: 'On',
                    icon: const Icon(Icons.draw),
                    onPressed: () {},
                    isSelected: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      Color painted(String key) => tester
          .widget<RichText>(
            find.descendant(
              of: find.byKey(ValueKey<String>(key)),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style!
          .color!;
      Color? layerOf(String key) {
        final box = tester.widget<DecoratedBox>(
          find.descendant(
            of: find.byKey(ValueKey<String>(key)),
            matching: faceLayer,
          ),
        );
        return (box.decoration as ShapeDecoration).color;
      }

      expect(painted('app-rest'), AppColors.text);
      expect(painted('app-dead'), AppColors.textDim.withValues(alpha: 0.5));
      expect(painted('app-on'), AppColors.accent);

      // The hover layer comes from the same theme — styleFrom derives it
      // from the theme's foreground — and a dead button still shows none.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey<String>('app-rest'))),
      );
      await tester.pump();
      expect(layerOf('app-rest'), stateLayer(AppColors.text, 0.08));
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey<String>('app-dead'))),
      );
      await tester.pump();
      expect(layerOf('app-dead'), isNull, reason: 'dead buttons have none');
      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a tap fires ONCE — through the claim, never also through '
        'the face', (tester) async {
      var fired = 0;
      await pump(
        tester,
        AppIconButton(
          keyValue: 'once',
          tooltip: 'Once',
          icon: const Icon(Icons.draw),
          onPressed: () => fired += 1,
        ),
      );
      await tester.tap(find.byKey(const ValueKey<String>('once')));
      await tester.pump(const Duration(seconds: 2));
      expect(fired, 1);
    });

    testWidgets('the Tooltip is still a real Tooltip — `find.byTooltip` and '
        'touch long-press keep working', (tester) async {
      await pump(
        tester,
        AppIconButton(
          keyValue: 'tip',
          tooltip: 'Say my name',
          icon: const Icon(Icons.draw),
          onPressed: () {},
        ),
      );
      expect(find.byTooltip('Say my name'), findsOneWidget);
    });

    testWidgets('a screen reader hears ONE node: the tooltip, a button, '
        'enabled, selected, focusable', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIconButton(
              keyValue: 'a11y-a',
              tooltip: 'Eye',
              icon: const Icon(Icons.visibility),
              onPressed: () {},
              isSelected: true,
            ),
            AppIconButton(
              keyValue: 'a11y-b',
              tooltip: 'Lock',
              icon: const Icon(Icons.lock),
              onPressed: () {},
            ),
          ],
        ),
      );
      expect(
        tester.getSemantics(find.byKey(const ValueKey('a11y-a'))),
        isSemantics(
          tooltip: 'Eye',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isSelected: true,
          isFocusable: true,
        ),
      );
      // Two buttons, two nodes: a container per button is what stops a rail
      // row of six from reading as one long button.
      expect(
        tester.getSemantics(find.byKey(const ValueKey('a11y-a'))).id,
        isNot(tester.getSemantics(find.byKey(const ValueKey('a11y-b'))).id),
      );
      handle.dispose();
    });

    testWidgets('🚨a screen reader\'s "double-tap to activate" presses the '
        'button ONCE — and a finger still presses it once, not twice', (
      tester,
    ) async {
      // 유저 2026-09-10: 「탭은 다른 숏컷 쓸수도있어서 굳이 필요없을거같고,
      // 스크린리더만 있으면좋을까싶은데」. The claim fires from the pointer
      // stream, so the face's own callback was a silent no-op — and a screen
      // reader's activation arrives as SemanticsAction.tap, not a pointer, so
      // it called that no-op (measured: 0 on master and on the light face).
      var fired = 0;
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        AppIconButton(
          keyValue: 'reader',
          tooltip: 'Reader',
          icon: const Icon(Icons.draw),
          onPressed: () => fired += 1,
        ),
      );
      final node = tester.getSemantics(
        find.byKey(const ValueKey<String>('reader')),
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.tap,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(fired, 1, reason: 'the screen reader pressed it');

      await tester.tap(find.byKey(const ValueKey<String>('reader')));
      await tester.pump(const Duration(seconds: 2));
      expect(fired, 2, reason: 'a finger still presses it exactly once');
      handle.dispose();
    });

    testWidgets('a DISABLED button offers a screen reader nothing to press', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        const AppIconButton(
          keyValue: 'reader-dead',
          tooltip: 'Reader dead',
          icon: Icon(Icons.draw),
          onPressed: null,
        ),
      );
      final node = tester.getSemantics(
        find.byKey(const ValueKey<String>('reader-dead')),
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      handle.dispose();
    });

    testWidgets('🚨a tap on the button does NOT also tap the row around it — '
        'the arena still says the press is the button\'s', (tester) async {
      var rowTaps = 0;
      var buttonTaps = 0;
      await pump(
        tester,
        SizedBox(
          width: 300,
          child: InkWell(
            key: const ValueKey<String>('row'),
            onTap: () => rowTaps += 1,
            child: Row(
              children: [
                const SizedBox(width: 100, height: 40),
                AppIconButton(
                  keyValue: 'inner',
                  tooltip: 'Inner',
                  icon: const Icon(Icons.delete),
                  onPressed: () => buttonTaps += 1,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey<String>('inner')));
      await tester.pump(const Duration(seconds: 2));
      // The Material InkWell used to WIN this — the deepest tap in the arena
      // — and that win was the only thing silencing the row. Found when a
      // guide's delete button started selecting its row as well.
      expect(buttonTaps, 1);
      expect(rowTaps, 0, reason: 'the row must not answer a press on its button');

      // …and the row still answers a tap that is NOT on the button.
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey<String>('row'))) +
            const Offset(20, 20),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(rowTaps, 1);
    });

    testWidgets('🚨one button is at most 20 render objects — the Material '
        'one was 27', (tester) async {
      await pump(
        tester,
        AppIconButton(
          keyValue: 'weight',
          tooltip: 'Weight',
          icon: const Icon(Icons.draw),
          onPressed: () {},
        ),
      );
      var renderObjects = 0;
      void visit(Element element) {
        if (element is RenderObjectElement) {
          renderObjects += 1;
        }
        element.visitChildren(visit);
      }

      visit(tester.element(find.byType(AppIconButton)));
      // ⛔THE WHOLE POINT OF THE ROUND, as a number. 94 of these stand on the
      // idle screen, so each one back is ~94 render objects plus their
      // semantics mirror. Measured 2026-09-10 in the app: 27 with the
      // Material button, and this bound is the light face's own count — a
      // Flutter upgrade that adds a node to `Tooltip` or `Icon` fails it
      // on purpose, so the number is read again rather than drifting.
      expect(renderObjects, lessThanOrEqualTo(20));
    });
  });

  group('R26 #42 adoption', () {
    testWidgets('the canvas bottom bar and the timesheet panel wear the SAME '
        'button widget', (tester) async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);

      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimesheetTabHost(
              session: session,
              continuous: false,
              onContinuousChanged: (_) {},
              viewport: CanvasViewport(),
              onViewportChanged: (_) {},
              onBrushAllowedChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The reference control — Fit — is back on the sheet (R2 #13: a page
      // you read is a page you zoom), and it wears the shared widget…
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey<String>('canvas-viewport-fit')),
          matching: find.byType(AppIconButton),
        ),
        findsOneWidget,
      );
      // …the sheet-mode controls that joined the bar (R26 #41)…
      expect(
        find.ancestor(
          of: find.byKey(
            const ValueKey<String>('timesheet-page-mode-toggle-button'),
          ),
          matching: find.byType(AppIconButton),
        ),
        findsOneWidget,
      );
      // …and the status-strip commands that used to hand-roll an InkWell.
      expect(
        find.ancestor(
          of: find.byKey(
            const ValueKey<String>('timesheet-brush-toggle-button'),
          ),
          matching: find.byType(AppIconButton),
        ),
        findsOneWidget,
      );
    });
  });
}
