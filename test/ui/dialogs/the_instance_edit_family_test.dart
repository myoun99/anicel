import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/dialogs/camera_key_dialog.dart';
import 'package:anicel/src/ui/dialogs/instance_edit_dialog.dart';
import 'package:anicel/src/ui/timeline/camera_key_edit.dart';

/// The instance-edit family's window and one of its kinds — neither named
/// by a test (2026-09-05).
///
/// 🚨The shell owns no chrome: what it holds is what the FAMILY shares —
/// the stable action keys every kind's tests and muscle memory rely on,
/// the optional Delete, and the preview slot below the fields.
void main() {
  Future<Object?> showAndTap(
    WidgetTester tester,
    Widget dialog,
    String buttonKey,
  ) async {
    Object? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  popped = await showDialog<Object?>(
                    context: context,
                    builder: (_) => dialog,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey<String>(buttonKey)));
    await tester.pumpAndSettle();
    return popped;
  }

  Future<void> pumpShell(
    WidgetTester tester, {
    Widget? preview,
    VoidCallback? onSubmit,
    VoidCallback? onDelete,
    bool keepDefault = true,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: InstanceEditDialogShell(
          title: 'Edit',
          body: const Text('fields'),
          preview: preview,
          onSubmit: keepDefault ? (onSubmit ?? () {}) : onSubmit,
          onDelete: onDelete,
        ),
      ),
    ),
  );

  group('the shell', () {
    testWidgets('🚨the action keys are STABLE across every kind — tests and '
        'muscle memory both rely on them', (tester) async {
      await pumpShell(tester);

      expect(
        find.byKey(const ValueKey<String>('instance-edit-dialog')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('instance-edit-ok-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('instance-edit-cancel-button')),
        findsOneWidget,
      );
    });

    testWidgets('⛔DELETE appears only when the kind offers one', (
      tester,
    ) async {
      await pumpShell(tester);
      expect(
        find.byKey(const ValueKey<String>('instance-edit-delete-button')),
        findsNothing,
      );

      await pumpShell(tester, onDelete: () {});
      expect(
        find.byKey(const ValueKey<String>('instance-edit-delete-button')),
        findsOneWidget,
      );
    });

    testWidgets('a null onSubmit DISABLES the confirm rather than hiding it '
        '— nothing selected yet is not a reason for the button to vanish', (
      tester,
    ) async {
      await pumpShell(tester, onSubmit: null, keepDefault: false);

      expect(
        find.byKey(const ValueKey<String>('instance-edit-ok-button')),
        findsOneWidget,
        reason: 'still there',
      );

      var submits = 0;
      await pumpShell(tester, onSubmit: () => submits += 1);
      await tester.tap(
        find.byKey(const ValueKey<String>('instance-edit-ok-button')),
      );
      await tester.pumpAndSettle();
      expect(submits, 1, reason: 'and live when there is something to save');
    });

    testWidgets('the preview slot is HIDDEN when the kind has none — an '
        'empty pane is not a preview', (tester) async {
      await pumpShell(tester);
      expect(find.text('a preview'), findsNothing);

      await pumpShell(tester, preview: const Text('a preview'));
      expect(find.text('a preview'), findsOneWidget);
    });
  });

  group('the camera key dialog', () {
    CameraKeyLaneState lane(
      String id, {
      bool keyed = true,
      String value = '10, 20',
      bool hold = false,
    }) => CameraKeyLaneState(
      laneId: id,
      label: id,
      keyed: keyed,
      valueText: value,
      hold: hold,
    );

    testWidgets('the title names the frame in ONE-based counting — the '
        'sheet is read by people', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CameraKeyDialog(frameIndex: 4, lanes: [lane('position')]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('5'), findsWidgets);
    });

    testWidgets('🚨it pops EVERY lane\'s state, so the host folds them into '
        'ONE track edit rather than three', (tester) async {
      final popped = await showAndTap(
        tester,
        CameraKeyDialog(
          frameIndex: 0,
          lanes: [lane('position'), lane('scale'), lane('rotation')],
        ),
        'instance-edit-ok-button',
      );

      expect(popped, isA<List<CameraKeyLaneState>>());
      expect((popped! as List<CameraKeyLaneState>).length, 3);
    });

    testWidgets('🚨a typed value is TRIMMED on the way out — a stray space '
        'is not part of the number', (tester) async {
      Object? popped;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await showDialog<Object?>(
                      context: context,
                      builder: (_) => CameraKeyDialog(
                        frameIndex: 0,
                        lanes: [lane('position')],
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '  30, 40  ');
      await tester.tap(
        find.byKey(const ValueKey<String>('instance-edit-ok-button')),
      );
      await tester.pumpAndSettle();

      expect((popped! as List<CameraKeyLaneState>).single.valueText, '30, 40');
    });

    testWidgets('cancel pops NOTHING, whatever was typed', (tester) async {
      final popped = await showAndTap(
        tester,
        CameraKeyDialog(frameIndex: 0, lanes: [lane('position')]),
        'instance-edit-cancel-button',
      );

      expect(popped, isNull);
    });
  });
}
