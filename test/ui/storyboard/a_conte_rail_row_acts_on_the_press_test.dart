import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/input/control_press_claim.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/storyboard_twirls.dart';

/// 🚨THE CONTE PANEL'S RAIL ROWS ARE THE TIMELINE'S (I-89 ①, 유저
/// 2026-10-13: 「다시 말하지만 이런건 다 콘티패널에도 동일하게 있어야해.
/// 같은 법으로」) — two laws the timeline's rows keep, kept here:
///
/// * 「**레이어 쪽 버튼은 탭다운**」 (유저 확정 2026-08-30): every button on a
///   rail row acts on the press, a column's or not. The S and transition
///   rows were this rail's own labels, and only their swipe columns stood
///   on the press — the colour label, the type button and the speaker
///   waited for the release.
/// * 「**클릭하고 떼면 뭐든 비우게**」 (T10): a press inside the selection
///   holds it — it may be the start of a move — and when it turns out to
///   be a tap, the selection goes. No row of this rail let go.
void main() {
  setUp(debugClearValueControlPointers);
  tearDown(debugClearValueControlPointers);

  Future<EditorSessionManager> pumpRail(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: withStoryboardTwirls(
            session,
            (twirls) => StoryboardTabHost(
              session: session,
              expandedLaneLayerIds: twirls.expandedLaneLayerIds,
              onToggleLayerLanes: twirls.onToggleLayerLanes,
              expandedLaneGroupKeys: twirls.expandedLaneGroupKeys,
              onToggleLaneGroupKey: twirls.onToggleLaneGroupKey,
              pixelsPerFrame: 12,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnails: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  Track trackOf(EditorSessionManager session) =>
      session.repository.requireProject().tracks.first;

  testWidgets('an S row\'s speaker has opened its mixer before it is '
      'released', (tester) async {
    final session = await pumpRail(tester);
    final se = trackOf(session).seLayers.first.id;
    final mixer = find.byKey(const ValueKey<String>('se-layer-mixer'));

    final gesture = await tester.startGesture(
      tester.getCenter(find.named('storyboard-layer-mute-$se')),
    );
    await tester.pumpAndSettle();
    expect(
      mixer,
      findsOneWidget,
      reason: '「레이어 쪽 버튼은 탭다운」 — the speaker is no swipe column, '
          'so only the ROW puts it on the press',
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(mixer, findsOneWidget, reason: 'and the release keeps it open');
  });

  testWidgets('every row of the rail puts its buttons on the press — the S '
      'row, the transition row and the V row', (tester) async {
    final session = await pumpRail(tester);
    final track = trackOf(session);
    // Each one's TYPE button: in the row, and no swipe column — so only
    // the row can put it on the press (the timeline's own pin's reading,
    // `layer_side_acts_on_the_press_header_on_the_release_test`).
    for (final name in [
      'storyboard-layer-type-button-${track.seLayers.first.id}',
      'storyboard-layer-type-button-${track.transitionLayer.id}',
      'storyboard-layer-type-button-v-${track.id.value}',
    ]) {
      final button = find.named(name);
      expect(button, findsOneWidget, reason: '$name is not on the rail');
      expect(
        find.ancestor(
          of: button,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is PressFireScope && widget.fireOn == PressFire.down,
          ),
        ),
        findsWidgets,
        reason: '$name waits for the release',
      );
    }
  });

  testWidgets('a tap inside the selection lets it go — on an S row and on '
      'the V row', (tester) async {
    final session = await pumpRail(tester);
    final track = trackOf(session);
    final s1 = track.seLayers.first;
    final selection = <TimelineRowAddress>[
      for (final se in track.seLayers) LayerRowAddress(se.id),
      TrackRowAddress(track.id),
    ];

    // Its NAME — the row's own ground, no control on it.
    session.rowSelection.value = selection;
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(
          ValueKey<String>('storyboard-se-label-${track.id.value}-1'),
        ),
        matching: find.text(s1.name),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      session.rowSelection.value,
      isEmpty,
      reason: '「클릭하고 떼면 뭐든 비우게」 — the S row held it on the press, '
          'and nothing let it go on the release',
    );

    session.rowSelection.value = selection;
    await tester.pump();
    await tester.tap(
      find.byKey(ValueKey<String>('storyboard-track-label-${track.id.value}')),
    );
    await tester.pumpAndSettle();
    expect(
      session.rowSelection.value,
      isEmpty,
      reason: 'and the V row, which wears no layer, the same',
    );
  });
}
