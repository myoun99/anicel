import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart' show LayerFxState;
import 'package:anicel/src/models/layer_section_defaults.dart'
    show seLayerIdForTrack;
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

/// R9 #21 — the V row's own column. The rail row's fx switch describes the
/// row's SUBJECT, and this row's subject is the TRACK: its fx master,
/// persisted like every fx switch since R8.
///
/// ↩️The head carried two more until 2026-10-08 (I-73, 유저: 「V행의
/// 불투명도랑 비지블 필요없어보여서 삭제하고싶은데 어때」 · 「5. 값도지움」) —
/// the track's static OPACITY, a bar here and a value in the file, and an
/// EYE that hid the picture of the cut under the playhead. What is pinned
/// of them now is that they are gone and their columns still stand.
void main() {
  group('Track model', () {
    test('a default track writes no fx key — R8\'s rule that a default is '
        'silence, so files from before R9 are unchanged', () {
      final track = Track(
        id: createDefaultProject().tracks.first.id,
        name: 'V1',
        cuts: const [],
      );

      expect(track.toJson().containsKey('fxEnabled'), isFalse);
    });

    test('an old file without the key opens with the switch ON', () {
      final original = createDefaultProject();
      final json = original.toJson();
      // Strip the R9 key the way a pre-R9 writer would have.
      for (final track
          in (json['tracks'] as List).cast<Map<String, dynamic>>()) {
        track.remove('fxEnabled');
      }

      final reopened = Project.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );

      expect(reopened.tracks.first.fxEnabled, isTrue);
    });

    test('a switch that is OFF round-trips', () {
      final original = createDefaultProject();
      final edited = original.copyWith(
        tracks: [
          original.tracks.first.copyWith(fxEnabled: false),
          ...original.tracks.skip(1),
        ],
      );

      final reopened = Project.fromJson(
        jsonDecode(jsonEncode(edited.toJson())) as Map<String, dynamic>,
      );

      expect(reopened.tracks.first.fxEnabled, isFalse);
    });
  });

  group('the track fx master', () {
    test('OFF gates every cut on the track through the ONE choke point '
        'every display already asks', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);

      final trackId = session.selectedTrackId;
      final cutIds = session.repository
          .requireProject()
          .tracks
          .firstWhere((track) => track.id == trackId)
          .cuts
          .map((cut) => cut.id)
          .toList();
      expect(cutIds, isNotEmpty);
      expect(cutIds.every(session.effectsAndFx.isCutFxEnabled), isTrue);

      session.effectsAndFx.toggleTrackFx(trackId);

      expect(session.effectsAndFx.trackFxState(trackId), LayerFxState.off);
      expect(
        cutIds.every((id) => !session.effectsAndFx.isCutFxEnabled(id)),
        isTrue,
        reason: 'every cut on the track reads bypassed without any per-cut '
            'write — the master arrives at isCutFxEnabled',
      );
    });

    test('the switch is BINARY — R10 R3 retired the per-cut axis, so a '
        'track has no MIXED left to report', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);

      final trackId = session.selectedTrackId;
      final cutId = session.repository
          .requireProject()
          .tracks
          .firstWhere((track) => track.id == trackId)
          .cuts
          .first
          .id;

      expect(session.effectsAndFx.trackFxState(trackId), LayerFxState.on);

      session.effectsAndFx.toggleTrackFx(trackId);
      expect(session.effectsAndFx.trackFxState(trackId), LayerFxState.off);
      expect(session.effectsAndFx.isCutFxEnabled(cutId), isFalse);

      session.effectsAndFx.toggleTrackFx(trackId);
      expect(session.effectsAndFx.trackFxState(trackId), LayerFxState.on);
      expect(session.effectsAndFx.isCutFxEnabled(cutId), isTrue);
    });

    test('the flag persists — it is model state, not a session set', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);

      session.effectsAndFx.toggleTrackFx(session.selectedTrackId);

      final reopened = Project.fromJson(
        jsonDecode(jsonEncode(session.repository.requireProject().toJson()))
            as Map<String, dynamic>,
      );
      expect(reopened.tracks.first.fxEnabled, isFalse);
    });
  });

  // ↩️A group stood here for the track's static opacity: that an fx bypass
  // left it composited (it was not an fx), and that its bar previewed live
  // and committed once on release. The value went with the bar.

  testWidgets('the V row mounts the TRACK\'s fx switch in the fx column, and '
      'neither an eye nor an opacity bar beside it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => StoryboardTabHost(
              session: session,
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

    final trackId = session.selectedTrackId;
    final head = find.byKey(
      ValueKey<String>('storyboard-track-label-row-${trackId.value}'),
    );
    final fxSwitch = find.byKey(
      ValueKey<String>('storyboard-track-fx-${trackId.value}'),
    );
    expect(fxSwitch, findsOneWidget);
    expect(
      find.descendant(of: head, matching: find.byType(FieldSlider)),
      findsNothing,
      reason: 'the opacity bar left the head',
    );
    expect(
      find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            (key.value.startsWith('storyboard-cut-visibility-') ||
                key.value.startsWith('storyboard-track-opacity-'));
      }),
      findsNothing,
      reason: 'and so did the eye',
    );

    // The columns are still there: the switch stands where an S row's does,
    // not slid over into the room the two left.
    final seFx = find.byKey(
      ValueKey<String>(
        'storyboard-layer-fx-${seLayerIdForTrack(trackId, 1)}',
      ),
    );
    expect(seFx, findsOneWidget, reason: 'LIVENESS: an S row wears the column');
    expect(
      tester.getRect(fxSwitch).left,
      tester.getRect(seFx).left,
      reason: 'a column a row has nothing to show in is reserved and empty',
    );

    await tester.tap(fxSwitch);
    await tester.pumpAndSettle();
    expect(session.effectsAndFx.trackFxState(trackId), LayerFxState.off);
  });
}
