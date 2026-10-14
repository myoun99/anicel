import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_transform_lane_carrier.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart'
    show buildAnicelProjectJsonBytes, decodeAnicelProjectDocument;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/session/session_row_button_presses.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectLaneId;
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

import '../../helpers/conte_track_fixture.dart';
import '../../helpers/named_finders.dart';

/// 🚨F-360, its second half (유저 2026-10-14: 「fx나 폴더나 이런 접음/펼침
/// 상태가 기록이 안되는건지? 제대로 기록되도록」): the STORYBOARD's twirls
/// are its rows' too. An S row is a track's SE row, so its twirl and the
/// groups open in it are that layer's own (`Layer.lanesExpanded`,
/// `Layer.expandedLaneGroups`) — the very ones the timeline's row twirls.
/// The V row is no layer: its fx chain twirled down and the groups open in
/// it are its track's (`Track.lanesExpanded`, `Track.expandedLaneGroups`),
/// reached by its lane carrier. The file keeps them, a press is one undo
/// step, and a press writes them in a gap as well.
///
/// ↩️They were three sets of the storyboard rail's own in the session's
/// view — so a reopen shut them all, an undo never reached them, and an S
/// row twirled on one panel stood shut on the other.
void main() {
  final transform = transformGroupHeaderLane.laneId;
  const blur = EffectId('v-blur');
  final fx = effectGroupLaneId(blur);
  final carrier = trackTransformLaneCarrierId(conteTrackId);

  /// The conte track with an effect on its V row — a V row has lanes only
  /// with one.
  Project film() {
    final project = conteTrackProject();
    return project.copyWith(
      tracks: [
        for (final track in project.tracks)
          track.copyWith(
            effects: [LayerEffect.defaults(id: blur, kind: EffectKind.blur)],
          ),
      ],
    );
  }

  EditorSessionManager sessionOn(Project project) {
    final session = EditorSessionManager(initialProject: project);
    addTearDown(session.dispose);
    return session;
  }

  Track trackOf(EditorSessionManager session) =>
      session.repository.requireProject().tracks.single;

  /// By id: a file opens with the track's SE floor backfilled
  /// (`withEnsuredTrackSeLayers`), and the fixture has one row.
  Layer seRowOf(EditorSessionManager session) =>
      trackOf(session).seLayers.firstWhere((row) => row.id == conteSeId);

  test('🚨what the storyboard twirled when the file was saved is twirled '
      'when it opens — an S row\'s lanes, a group in them, the V row\'s fx '
      'chain, a group in it', () {
    final s = sessionOn(film());
    SessionRowButtonPresses(s)
      ..toggleLanes(conteSeId)
      ..toggleLaneGroup(laneGroupKey(conteSeId, transform))
      ..toggleLanes(carrier)
      ..toggleLaneGroup(laneGroupKey(carrier, fx));

    final opened = sessionOn(
      decodeAnicelProjectDocument(
        buildAnicelProjectJsonBytes(project: s.repository.requireProject()),
      ).project,
    );

    for (final (name, session) in [('saved', s), ('opened', opened)]) {
      expect(seRowOf(session).lanesExpanded, isTrue, reason: name);
      expect(seRowOf(session).expandedLaneGroups, {transform}, reason: name);
      expect(trackOf(session).lanesExpanded, isTrue, reason: name);
      expect(trackOf(session).expandedLaneGroups, {fx}, reason: name);
      // And the rails read them off the document — the timeline's sets,
      // where the S row is the layer the timeline's SE row twirls.
      expect(
        session.railView.expandedLaneLayerIds.value,
        {conteSeId},
        reason: '$name: the S row\'s twirl is its SE row\'s',
      );
      expect(session.railView.expandedLaneGroupKeys.value, {
        laneGroupKey(conteSeId, transform),
        laneGroupKey(carrier, fx),
      }, reason: name);
      expect(
        session.railView.twirledTrackIds.value,
        {conteTrackId},
        reason: name,
      );
    }
  });

  test('🚨each of them is ONE undo step, and the undo puts it back', () {
    final s = sessionOn(film());
    final presses = SessionRowButtonPresses(s);
    for (final (name, press, open) in [
      (
        'the S row',
        () => presses.toggleLanes(conteSeId),
        () => seRowOf(s).lanesExpanded,
      ),
      (
        'a group in it',
        () => presses.toggleLaneGroup(laneGroupKey(conteSeId, transform)),
        () => seRowOf(s).expandedLaneGroups.contains(transform),
      ),
      (
        'the V row',
        () => presses.toggleLanes(carrier),
        () => trackOf(s).lanesExpanded,
      ),
      (
        'a group in its fx chain',
        () => presses.toggleLaneGroup(laneGroupKey(carrier, fx)),
        () => trackOf(s).expandedLaneGroups.contains(fx),
      ),
    ]) {
      final depth = s.historyManager.undoCount;
      press();
      expect(open(), isTrue, reason: '$name: the press twirled it');
      expect(s.historyManager.undoCount, depth + 1, reason: '$name: one step');

      s.undo();

      expect(open(), isFalse, reason: '$name: the undo put it back');
    }
  });

  test('🚨in a GAP as well — the storyboard stands there, and no cut holds '
      'these rows to address them in', () {
    final s = sessionOn(film());
    // cut-1 is frames 0..12 and cut-2 starts at 15.
    s.selectGlobalFrame(13);
    expect(s.activeCutOrNull, isNull, reason: 'premise: in the gap');

    SessionRowButtonPresses(s)
      ..toggleLanes(conteSeId)
      ..toggleLaneGroup(laneGroupKey(conteSeId, transform))
      ..toggleLanes(carrier)
      ..toggleLaneGroup(laneGroupKey(carrier, fx));

    expect(seRowOf(s).lanesExpanded, isTrue);
    expect(seRowOf(s).expandedLaneGroups, {transform});
    expect(trackOf(s).lanesExpanded, isTrue);
    expect(trackOf(s).expandedLaneGroups, {fx});
  });

  group('a twirl that shuts hands the storyboard\'s stand to the row that '
      'swallows it', () {
    for (final (name, row, lane, swallower) in [
      (
        'an S row\'s lane — to the S row',
        conteSeId,
        LaneRowAddress(conteSeId, transform),
        const LayerRowAddress(conteSeId),
      ),
      (
        'a V row\'s lane — to the TRACK\'s row, its carrier being no row',
        carrier,
        LaneRowAddress(carrier, fx),
        const TrackRowAddress(conteTrackId),
      ),
    ]) {
      test(name, () {
        final s = sessionOn(film());
        final presses = SessionRowButtonPresses(s)..toggleLanes(row);
        s.standOnRow(lane, panel: WorkingPanel.storyboard);
        expect(s.standing.storyboardStandingRow, lane, reason: 'premise');

        presses.toggleLanes(row);

        expect(s.standing.storyboardStandingRow, swallower);
      });
    }

    for (final (name, row, header, member) in [
      (
        'a member of an S row\'s group — to its header',
        conteSeId,
        transform,
        'scale',
      ),
      (
        'a member of a V row\'s fx group — to its header',
        carrier,
        fx,
        effectLaneId(blur, 'blurX'),
      ),
    ]) {
      test(name, () {
        final s = sessionOn(film());
        final presses = SessionRowButtonPresses(s)
          ..toggleLanes(row)
          ..toggleLaneGroup(laneGroupKey(row, header));
        final inside = LaneRowAddress(row, member);
        s.standOnRow(inside, panel: WorkingPanel.storyboard);
        expect(s.standing.storyboardStandingRow, inside, reason: 'premise');

        presses.toggleLaneGroup(laneGroupKey(row, header));

        expect(s.standing.storyboardStandingRow, LaneRowAddress(row, header));
      });
    }
  });

  testWidgets('through the REAL workspace: the V row\'s twirl opens its fx '
      'chain on the storyboard, and shuts it', (tester) async {
    // A twirl is no session notify — the rails hear the document through
    // the rail's view — so this is the one pin that the workspace's
    // storyboard tab hears a V row's: its track is no row the timeline's
    // sets hold.
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: HomePage(initialProject: film())));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
    final fxHeader = find.named(
      'storyboard-lane-group-toggle-${carrier.value}-$fx',
    );
    expect(fxHeader, findsNothing, reason: 'premise: shut');

    final twirl = find.named(
      'storyboard-track-lane-toggle-${conteTrackId.value}',
    );
    await tester.tap(twirl);
    await tester.pumpAndSettle();
    expect(fxHeader, findsOneWidget, reason: 'the chain twirled down');

    await tester.tap(twirl);
    await tester.pumpAndSettle();
    expect(fxHeader, findsNothing, reason: 'and up again');
  });
}
