import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/app_save_settings.dart';
import 'package:anicel/src/ui/dialogs/autosave_settings_section.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';

/// The Preferences snapshot list (Q-recovery-gc, 유저 08-26): rows with
/// name/location + date + size, multi-select by tap, one confirmed
/// Delete — and the 30-day sweep armed at the shell's launch.
void main() {
  late Directory recovery;

  setUp(() {
    recovery = Directory(AppSave.recoveryDirectory())
      ..createSync(recursive: true);
  });
  tearDown(() {
    try {
      recovery.deleteSync(recursive: true);
    } on Object {
      // Windows handles.
    }
  });

  String snapshot(String name, {Duration age = const Duration(days: 1)}) {
    final path = '${recovery.path.replaceAll('\\', '/')}/$name';
    File(path).writeAsStringSync('overlay-bytes');
    File(path).setLastModifiedSync(DateTime.now().subtract(age));
    return path;
  }

  Future<EditorSessionManager> pumpSection(WidgetTester tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AutosaveSettingsSection(session: session),
          ),
        ),
      ),
    );
    return session;
  }

  testWidgets('rows are listed and Delete stays dark until something is '
      'selected', (tester) async {
    final a = snapshot('SceneA.anicel.aa11aa11.autosave');
    snapshot('SceneB.anicel.bb22bb22.autosave', age: const Duration(days: 3));
    await pumpSection(tester);

    expect(
      find.byKey(ValueKey<String>('settings-recovery-row-$a')),
      findsOneWidget,
    );
    expect(find.textContaining('SceneA.anicel'), findsOneWidget);
    expect(find.textContaining('SceneB.anicel'), findsOneWidget);
    final delete = tester.widget<TextButton>(
      find.byKey(const ValueKey<String>('settings-recovery-delete')),
    );
    expect(
      delete.onPressed,
      isNull,
      reason: 'the button is reserved space, inert until a selection exists',
    );
  });

  testWidgets('select two → Delete asks → confirm removes the files and '
      'the rows', (tester) async {
    final a = snapshot('SceneA.anicel.aa11aa11.autosave');
    final b = snapshot('SceneB.anicel.bb22bb22.autosave');
    final kept = snapshot('SceneC.anicel.cc33cc33.autosave');
    await pumpSection(tester);

    await tester.tap(find.byKey(ValueKey<String>('settings-recovery-row-$a')));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey<String>('settings-recovery-row-$b')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-recovery-delete')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('recovery-delete-dialog')),
      findsOneWidget,
      reason: 'a snapshot can be the only copy of unsaved crash work — '
          'unlike the conform cache, this delete asks',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('recovery-delete-confirm')),
    );
    await tester.pumpAndSettle();

    expect(File(a).existsSync(), isFalse);
    expect(File(b).existsSync(), isFalse);
    expect(File(kept).existsSync(), isTrue);
    expect(
      find.byKey(ValueKey<String>('settings-recovery-row-$a')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey<String>('settings-recovery-row-$kept')),
      findsOneWidget,
    );
  });

  testWidgets('Cancel keeps everything', (tester) async {
    final a = snapshot('SceneA.anicel.aa11aa11.autosave');
    await pumpSection(tester);
    await tester.tap(find.byKey(ValueKey<String>('settings-recovery-row-$a')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-recovery-delete')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('recovery-delete-cancel')),
    );
    await tester.pumpAndSettle();
    expect(File(a).existsSync(), isTrue);
  });

  testWidgets('🚨 the shell arms the 30-day sweep at launch', (tester) async {
    // The WIRING: a sweep nobody calls is a policy nobody has. HomePage
    // is what makes snapshots exist, so it is where abandonment ends.
    final abandoned = snapshot(
      'Gone.anicel.dead0000.autosave',
      age: const Duration(days: 40),
    );
    final young = snapshot('Live.anicel.beef0000.autosave');

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pump();

    expect(File(abandoned).existsSync(), isFalse);
    expect(File(young).existsSync(), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
