import 'package:flutter/material.dart';
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
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: child))),
    );
  }

  group('AppIconButton', () {
    testWidgets('the ON state is ACCENT INK, not a check mark or a fill '
        '(the app selection rule)', (tester) async {
      await pump(
        tester,
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIconButton(
              keyValue: 'on',
              tooltip: 'On',
              icon: Icon(Icons.draw),
              onPressed: null,
              isSelected: true,
            ),
            AppIconButton(
              keyValue: 'off',
              tooltip: 'Off',
              icon: Icon(Icons.draw),
              onPressed: null,
            ),
          ],
        ),
      );

      Color? foreground(String key) {
        final button = tester.widget<IconButton>(
          find.byKey(ValueKey<String>(key)),
        );
        return button.style?.foregroundColor?.resolve(<WidgetState>{});
      }

      expect(foreground('on'), AppColors.accent);
      expect(foreground('off'), isNull);
      expect(find.byIcon(Icons.check), findsNothing);
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
              onInkEnabledChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The bottom bar's own controls (the reference style)…
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey<String>('canvas-viewport-fit')),
          matching: find.byType(AppIconButton),
        ),
        findsOneWidget,
      );
      // …the sheet-mode controls that joined it (R26 #41)…
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
            const ValueKey<String>('timesheet-ink-toggle-button'),
          ),
          matching: find.byType(AppIconButton),
        ),
        findsOneWidget,
      );
    });
  });
}
