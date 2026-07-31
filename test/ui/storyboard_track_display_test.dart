import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart' show LayerFxState;
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

/// R9 #21 — the V row's own columns. The rail row's fx switch and opacity
/// bar describe the row's SUBJECT, and this row's subject is the TRACK:
/// its fx master (over the per-cut switches) and its static opacity, both
/// persisted like every fx switch since R8.
void main() {
  group('Track model', () {
    test('a default track writes neither key — R8\'s rule that a default '
        'is silence, so files from before R9 are unchanged', () {
      final track = Track(id: createDefaultProject().tracks.first.id, name: 'V1', cuts: const []);
      final json = track.toJson();

      expect(json.containsKey('opacity'), isFalse);
      expect(json.containsKey('fxEnabled'), isFalse);
    });

    test('an old file with neither key opens at 1.0 and ON', () {
      final original = createDefaultProject();
      final json = original.toJson();
      // Strip the R9 keys the way a pre-R9 writer would have.
      for (final track in (json['tracks'] as List).cast<Map<String, dynamic>>()) {
        track.remove('opacity');
        track.remove('fxEnabled');
      }

      final reopened = Project.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );

      expect(reopened.tracks.first.opacity, 1.0);
      expect(reopened.tracks.first.fxEnabled, isTrue);
    });

    test('non-default values round-trip', () {
      final original = createDefaultProject();
      final edited = original.copyWith(
        tracks: [
          original.tracks.first.copyWith(opacity: 0.4, fxEnabled: false),
          ...original.tracks.skip(1),
        ],
      );

      final reopened = Project.fromJson(
        jsonDecode(jsonEncode(edited.toJson())) as Map<String, dynamic>,
      );

      expect(reopened.tracks.first.opacity, 0.4);
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
      expect(cutIds.every(session.isCutFxEnabled), isTrue);

      session.toggleTrackFx(trackId);

      expect(session.trackFxState(trackId), LayerFxState.off);
      expect(
        cutIds.every((id) => !session.isCutFxEnabled(id)),
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

      expect(session.trackFxState(trackId), LayerFxState.on);

      session.toggleTrackFx(trackId);
      expect(session.trackFxState(trackId), LayerFxState.off);
      expect(session.isCutFxEnabled(cutId), isFalse);

      session.toggleTrackFx(trackId);
      expect(session.trackFxState(trackId), LayerFxState.on);
      expect(session.isCutFxEnabled(cutId), isTrue);
    });

    test('the flag persists — it is model state, not a session set', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);

      session.toggleTrackFx(session.selectedTrackId);

      final reopened = Project.fromJson(
        jsonDecode(jsonEncode(session.repository.requireProject().toJson()))
            as Map<String, dynamic>,
      );
      expect(reopened.tracks.first.fxEnabled, isFalse);
    });
  });

  group('the track static opacity', () {
    test('is NOT an fx: an fx bypass leaves it composited', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);

      final trackId = session.selectedTrackId;
      session.commitTrackOpacity(trackId, 0.25);
      session.toggleTrackFx(trackId);

      expect(session.trackStaticOpacity(trackId), 0.25);
      expect(
        session.activeCutEditingFadeOpacity(),
        0.25,
        reason: 'a layer\'s static opacity is not gated by its fx switch '
            'either — only the animated fade stands down',
      );
    });

    test('the drag previews live and commits ONCE on release', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);

      final trackId = session.selectedTrackId;
      final before = session.repository.requireProject();

      session.previewTrackOpacity(trackId, 0.5);
      expect(
        session.trackStaticOpacity(trackId),
        0.5,
        reason: 'readers see the live value',
      );
      expect(
        identical(session.repository.requireProject(), before),
        isTrue,
        reason: 'per-move writes are what commit-on-release exists to avoid',
      );

      session.commitTrackOpacity(trackId, 0.5);
      expect(session.trackOpacityDragPreview.value, isNull);
      expect(
        session.repository.requireProject().tracks.first.opacity,
        0.5,
      );
      session.undo();
      expect(session.repository.requireProject().tracks.first.opacity, 1.0);
    });
  });

  testWidgets('the V row mounts the TRACK\'s fx switch and an opacity bar — '
      'the slot that was empty while every other rail row had one', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final session = EditorSessionManager(initialProject: createDefaultProject());
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
              thumbnailFor: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final trackId = session.selectedTrackId;
    final fxSwitch = find.byKey(
      ValueKey<String>('storyboard-track-fx-${trackId.value}'),
    );
    final opacityBar = find.byKey(
      ValueKey<String>('storyboard-track-opacity-${trackId.value}'),
    );
    expect(fxSwitch, findsOneWidget);
    expect(opacityBar, findsOneWidget);
    expect(tester.widget<FieldSlider>(opacityBar).value, 1.0);

    await tester.tap(fxSwitch);
    await tester.pumpAndSettle();
    expect(session.trackFxState(trackId), LayerFxState.off);
  });
}
