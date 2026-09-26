import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/timeline_double_tap.dart';

/// storyboard-label-double-click (I-48's last family): the storyboard's
/// layer labels — its S rows', its transition row's — take the timeline
/// rail's double click, the same widget; and a single click on them picks
/// on the press, off the double tap's arena, so it never waits out the
/// window.
void main() {
  late EditorSessionManager session;

  setUp(TimelineDoubleTapGate.reset);

  Future<Track> openStoryboard(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
    session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    return session.repository.requireProject().tracks.first;
  }

  Finder seLabel(Track track) =>
      find.byKey(ValueKey<String>('storyboard-se-label-${track.id.value}-1'));

  Future<void> doubleClick(WidgetTester tester, Finder label) async {
    final at = tester.getCenter(label);
    await tester.tapAt(at, kind: PointerDeviceKind.stylus);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(at, kind: PointerDeviceKind.stylus);
    await tester.pumpAndSettle();
  }

  const dialog = ValueKey<String>('rename-layer-dialog');

  testWidgets('an S row\'s label opens the rename, and the row takes its new '
      'name', (tester) async {
    final track = await openStoryboard(tester);
    expect(seLabel(track), findsOneWidget, reason: 'fixture premise');

    await doubleClick(tester, seLabel(track));
    expect(find.byKey(dialog), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey<String>('rename-layer-text-field')),
      'Voice',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('rename-layer-ok-button')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      session.repository
          .requireProject()
          .tracks
          .first
          .seLayers
          .map((layer) => layer.name),
      contains('Voice'),
    );
  });

  testWidgets('a single click picks on the PRESS — nothing waits out the '
      'double tap\'s window', (tester) async {
    final track = await openStoryboard(tester);
    final pressed = track.seLayers.first;

    final gesture = await tester.startGesture(
      tester.getCenter(seLabel(track)),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();

    expect(
      session.selectedRow,
      LayerRowAddress(pressed.id),
      reason: 'the label picked its row on the press',
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the transition row\'s label is its track\'s fixture — the '
      'rename stands down, as on the timeline', (tester) async {
    final track = await openStoryboard(tester);

    await doubleClick(
      tester,
      find.byKey(
        ValueKey<String>('storyboard-transition-label-${track.id.value}'),
      ),
    );

    expect(find.byKey(dialog), findsNothing);
  });
}
