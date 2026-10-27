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
