import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';
import 'package:anicel/src/ui/playback/playback_transport_controls.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/app_icon_button_probe.dart';

/// 🗣️play-button-tooltip-untranslated (found 2026-10-02 while doing F-261,
/// and by the guide session a day earlier): the sill's play button said
/// 「Play」 / 「Stop」 in every language — and, one button over, the loop
/// toggle said `Loop (click for play once)` the same way.
///
/// The translation ratchet (F-37) could not have caught either: both were
/// the two arms of a ternary, and its scan reads the first literal after the
/// colon or nothing at all.
///
/// 🧪**THE TEST DOES NOT NAME THE TRANSLATIONS** (the sheet pill's pin's
/// rule): the same button, in the same state, must say three different things
/// in three languages. ⛔BOTH ARMS of each — only one of a ternary's is ever
/// on screen.
void main() {
  Project project() => Project(
    id: const ProjectId('project'),
    name: 'Project',
    frameRate: const ProjectFrameRate.integer(10),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Track',
        cuts: [
          Cut(
            id: const CutId('cut'),
            name: 'Cut',
            layers: const [],
            duration: 4,
            canvasSize: const CanvasSize(width: 8, height: 8),
          ),
        ],
      ),
    ],
    createdAt: DateTime.utc(2026),
  );

  /// What the play button and the loop toggle say in [language], playing or
  /// stopped, looping or playing once.
  Future<({String play, String loop})> said(
    WidgetTester tester, {
    required AppLanguage language,
    required bool playing,
    required bool looping,
  }) async {
    AppText.settings.value = AppLanguageSettings(programLanguage: language);
    final controller = CanvasPlaybackController(
      resolveProject: project,
      resolveActiveCutId: () => const CutId('cut'),
      resolveActiveTrackId: () => const TrackId('track'),
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
    );
    addTearDown(controller.dispose);
    controller.loopMode = looping
        ? PlaybackLoopMode.loop
        : PlaybackLoopMode.once;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackTransportControls(
            // A fresh element per mount: the words are read at build time.
            key: UniqueKey(),
            controller: controller,
            scope: PlaybackScope.activeCut,
          ),
        ),
      ),
    );
    if (playing) {
      controller.play(scope: PlaybackScope.activeCut);
      await tester.pump();
    }
    String of(String key) =>
        tester.appIconButton(find.byKey(ValueKey<String>(key))).tooltip;
    final words = (
      play: of('playback-play-button'),
      loop: of('playback-loop-toggle'),
    );
    controller.stop();
    await tester.pump();
    return words;
  }

  setUp(() {
    addTearDown(() => AppText.settings.value = const AppLanguageSettings());
  });

  for (final playing in [false, true]) {
    for (final looping in [true, false]) {
      testWidgets('the sill\'s transport reads its words from the table — '
          '${playing ? 'playing' : 'stopped'}, '
          '${looping ? 'looping' : 'playing once'}', (tester) async {
        final words = {
          for (final language in [
            AppLanguage.en,
            AppLanguage.ja,
            AppLanguage.ko,
          ])
            language: await said(
              tester,
              language: language,
              playing: playing,
              looping: looping,
            ),
        };
        expect(
          {for (final said in words.values) said.play},
          hasLength(3),
          reason: 'the play button says the same thing in two languages: '
              '${words.map((k, v) => MapEntry(k.name, v.play))}',
        );
        expect(
          {for (final said in words.values) said.loop},
          hasLength(3),
          reason: 'the loop toggle says the same thing in two languages: '
              '${words.map((k, v) => MapEntry(k.name, v.loop))}',
        );
      });
    }
  }

  testWidgets('each button says which of its two states it is in', (
    tester,
  ) async {
    Future<({String play, String loop})> at({
      required bool playing,
      required bool looping,
    }) => said(
      tester,
      language: AppLanguage.ko,
      playing: playing,
      looping: looping,
    );
    final rest = await at(playing: false, looping: true);
    final other = await at(playing: true, looping: false);
    expect(other.play, isNot(rest.play), reason: 'playing ≠ stopped');
    expect(other.loop, isNot(rest.loop), reason: 'once ≠ loop');
  });
}
