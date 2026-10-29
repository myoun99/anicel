import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/dialogs/app_confirm_dialog.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_window.dart';

import '../flyout_test_helpers.dart';
import '../../helpers/room_for_the_pills.dart';
import '../../helpers/timeline_host.dart';

/// 🗣️F-479 (유저 2026-10-26): 「레이어 삭제하겠습니까? 창 같은 공용
/// 메시지창, 탭 안눌러도 포커스 바로 닫기에 있어서 엔터로 닫기 눌러지게.
/// 그리고 처음 탭하면 삭제할 레이어 리스트에 포커스있는데, 굳이 이거에
/// 포커스 가능하게 할 이유없을듯. 취소 삭제 등 아래에 있는 버튼만 포커스
/// 이동가능하게」.
///
/// The keyboard stops at a message window's buttons alone, and a window
/// with one way out opens on it. Driven in the app itself: a key pressed
/// in a window must not be the editor's (its route is no child of the
/// shell's key road — `EditorKeyFunnel`).
void main() {
  Project project() => Project(
    id: const ProjectId('f479'),
    name: 'F-479',
    createdAt: DateTime.utc(2026, 10, 27),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'V',
        cuts: [
          Cut(
            id: const CutId('c'),
            name: 'C',
            duration: 12,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              for (final name in ['A', 'B', 'C'])
                Layer(id: LayerId(name), name: name, frames: const []),
            ],
          ),
        ],
      ),
    ],
  );

  /// Whether the keyboard is on the widget [finder] names, or inside it.
  bool focusIsIn(WidgetTester tester, Finder finder) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) {
      return false;
    }
    final target = tester.element(finder);
    var inside = identical(focused, target);
    focused.visitAncestorElements((element) {
      inside = inside || identical(element, target);
      return !inside;
    });
    return inside;
  }

  testWidgets('a notice opens on 닫기 — Enter closes it, no Tab first', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(appWindowWithRoomForItsPills);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();

    unawaited(
      showAppNotice(
        tester.element(find.byType(HomePage)),
        title: 'Notice',
        message: 'Something happened once.',
      ),
    );
    await tester.pumpAndSettle();
    const close = ValueKey<String>('app-notice-close');
    expect(find.byKey(close), findsOneWidget, reason: '⛔전제');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byKey(close), findsNothing, reason: 'Enter pressed 닫기');
  });

  testWidgets('whatever its one button wears, the window opens on it', (
    tester,
  ) async {
    for (final emphasis in AppWindowActionEmphasis.values) {
      final only = ValueKey<String>('only-way-out-${emphasis.name}');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: AppConfirmDialog(
            title: 'One way out',
            message: emphasis.name,
            actions: [
              AppWindowAction(
                label: 'Go',
                actionKey: only,
                emphasis: emphasis,
                onPressed: () {},
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(
        focusIsIn(tester, find.byKey(only)),
        isTrue,
        reason: emphasis.name,
      );
    }
  });

  // 🗣️F-479-Q1 (유저 2026-10-27): 「「삭제」 — 창이 묻는 일을 하는 강조 버튼」.
  testWidgets('the delete window opens on 삭제 — Enter deletes, no Tab '
      'first', (tester) async {
    final session = await pumpTimelineHost(
      tester,
      project(),
      surface: timelineTabWithRoomForItsPills,
    );
    session.rowSelectionVerbs.beginRowSelection(
      LayerRowAddress(session.activeLayerId!),
    );
    await tester.pumpAndSettle();
    final layers = session.layers.length;
    await tapCommandButton(
      tester,
      const ValueKey<String>('shared-delete-button'),
    );
    final delete = find.byKey(
      const ValueKey<String>('delete-layer-confirm-button'),
    );
    expect(delete, findsOneWidget, reason: '⛔전제: the window');
    expect(focusIsIn(tester, delete), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(delete, findsNothing);
    expect(session.layers, hasLength(layers - 1), reason: 'Enter deleted');
  });

  testWidgets('a window opens on its emphasized button wherever it stands — '
      'and on none where none is: a choice among equals, or a yes that '
      'throws work away', (tester) async {
    AppWindowAction action(
      String key, [
      AppWindowActionEmphasis emphasis = AppWindowActionEmphasis.quiet,
    ]) => AppWindowAction(
      label: key,
      actionKey: ValueKey<String>(key),
      emphasis: emphasis,
      onPressed: () {},
    );
    Future<void> open(List<AppWindowAction> actions) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: AppConfirmDialog(title: 'T', message: 'M', actions: actions),
        ),
      );
      await tester.pump();
    }

    List<String> focusedOf(List<String> keys) => [
      for (final key in keys)
        if (focusIsIn(tester, find.byKey(ValueKey<String>(key)))) key,
    ];

    await open([
      action('cancel'),
      action('yes', AppWindowActionEmphasis.primary),
      action('other'),
    ]);
    expect(focusedOf(['cancel', 'yes', 'other']), ['yes']);

    await open([action('one'), action('two'), action('three')]);
    expect(focusedOf(['one', 'two', 'three']), isEmpty);

    await open([
      action('cancel'),
      action('replace', AppWindowActionEmphasis.danger),
    ]);
    expect(focusedOf(['cancel', 'replace']), isEmpty);
  });

  // 🗣️I-70-Q6 (유저 2026-10-29: 「포커스 없음」): the usage statistics'
  // consent is answered by a press alone — its own test drives the Enter.
  testWidgets('a question only a press may answer opens on neither button '
      '— its yes emphasized all the same', (tester) async {
    const send = ValueKey<String>('consent-confirm-button');
    const dontSend = ValueKey<String>('consent-cancel-button');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => confirmWindow(
            context,
            ConfirmQuestion(
              keys: confirmDialogKeys('consent'),
              title: 'T',
              message: 'M',
              opensOnItsYes: false,
            ),
            accept: const ConfirmChoice('Send'),
            decline: const ConfirmChoice("Don't send"),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(send), findsOneWidget, reason: '⛔전제');
    expect(focusIsIn(tester, find.byKey(send)), isFalse);
    expect(focusIsIn(tester, find.byKey(dontSend)), isFalse);
    final dialog = tester.widget<AppConfirmDialog>(
      find.byType(AppConfirmDialog),
    );
    expect(
      dialog.actions.last.emphasis,
      AppWindowActionEmphasis.primary,
      reason: 'where it opens is not what it looks like',
    );
  });

  // 🗣️F-479-Q2 (유저 2026-10-27): 「닫기 창은 「저장」을 강조 버튼으로 —
  // Enter = 저장하고 닫기」. The Enter itself is driven through a real save
  // in `unsaved_work_gate_test.dart`.
  testWidgets('the window before unsaved work is thrown away opens on 저장 '
      '— never on the 닫기 that throws it away', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pump();
    // Any command marks the session dirty — a new drawing is the cheapest.
    final newFrame = find.byKey(const ValueKey<String>('new-frame-button'));
    await tester.ensureVisible(newFrame);
    await tester.pumpAndSettle();
    await tester.tap(newFrame);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    const gate = ValueKey<String>('system-exit-dialog');
    expect(find.byKey(gate), findsOneWidget, reason: '⛔전제: the gate');
    final focused = [
      for (final key in const ['cancel', 'save-as', 'save', 'close'])
        if (focusIsIn(
          tester,
          find.byKey(ValueKey<String>('system-exit-$key')),
        ))
          key,
    ];
    expect(focused, ['save']);
  });

  testWidgets('Tab goes round the delete window\'s buttons alone — never '
      'onto the list of layers it names', (tester) async {
    final session = await pumpTimelineHost(
      tester,
      project(),
      surface: timelineTabWithRoomForItsPills,
    );
    session.rowSelectionVerbs.beginRowSelection(
      LayerRowAddress(session.activeLayerId!),
    );
    await tester.pumpAndSettle();
    await tapCommandButton(
      tester,
      const ValueKey<String>('shared-delete-button'),
    );
    const list = ValueKey<String>('app-notice-details-toggle');
    final cancel = find.byKey(
      const ValueKey<String>('delete-layer-cancel-button'),
    );
    final delete = find.byKey(
      const ValueKey<String>('delete-layer-confirm-button'),
    );
    expect(find.byKey(list), findsOneWidget, reason: '⛔전제: the list');

    final stops = <String>[];
    for (var press = 0; press < 3; press += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      stops.add(
        focusIsIn(tester, cancel)
            ? 'cancel'
            : focusIsIn(tester, delete)
            ? 'delete'
            : focusIsIn(tester, find.byKey(list))
            ? 'list'
            : 'elsewhere',
      );
    }
    expect(stops, ['cancel', 'delete', 'cancel']);
  });
}
