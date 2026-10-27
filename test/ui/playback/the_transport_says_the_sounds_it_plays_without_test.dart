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
import 'package:anicel/src/ui/audio/sound_cannot_play.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';
import 'package:anicel/src/ui/playback/playback_transport_controls.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/widgets/app_tooltip.dart';

/// 유저 2026-10-17 (playback-waits-for-its-sound-Q1: 「a + 재생 중 재생 버튼
/// 줄 맨 앞에 빨간 경고 문구」): while this scope plays, the transport says
/// how many sounds the run plays without — beside the drops — and the
/// meter's reserved seat is red when the output would not open.
///
/// 🗣️F-463 ② (유저 2026-10-25): 「재생버튼 위에 오버레이로서? 자리
/// 안차지하고 … 위치적으로도 재생버튼 위쪽. 글자 작아도됨」 — the words ride
/// the play button's top and take no place. ↩️They stood in T29's fixed
/// 72px slot at the row's front, two lines, the sounds' line with a
/// tooltip.
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
            duration: 40,
            canvasSize: const CanvasSize(width: 8, height: 8),
          ),
        ],
      ),
    ],
    createdAt: DateTime.utc(2026),
  );

  const silent = PlaysWithout(
    sounds: {
      'C:/sounds/gone.wav': SoundCannotPlay.missing,
      '/sounds/odd.xyz': SoundCannotPlay.format,
    },
  );

  /// The row, playing [playing]'s run — or none — with [without]; its
  /// clock [ticking] only where a test drops frames.
  Future<CanvasPlaybackController> pump(
    WidgetTester tester, {
    PlaybackScope? playing = PlaybackScope.activeCut,
    PlaysWithout without = PlaysWithout.nothing,
    ValueNotifier<PlaysWithout>? notifier,
    bool ticking = false,
  }) async {
    final controller = CanvasPlaybackController(
      resolveProject: project,
      resolveActiveCutId: () => const CutId('cut'),
      resolveActiveTrackId: () => const TrackId('track'),
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
    );
    addTearDown(controller.dispose);
    if (ticking) {
      controller.attachTicker(const TestVSync());
      addTearDown(controller.detachTicker);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PlaybackTransportControls(
              controller: controller,
              scope: PlaybackScope.activeCut,
              resolveMeterPeaks: () => (left: 0, right: 0),
              playsWithout: notifier ?? ValueNotifier(without),
            ),
          ),
        ),
      ),
    );
    if (playing != null) {
      controller.play(scope: playing);
      addTearDown(controller.stop);
      await tester.pump();
    }
    return controller;
  }

  final silentLine = find.byKey(
    const ValueKey<String>('playback-silent-indicator'),
  );
  final dropLine = find.byKey(
    const ValueKey<String>('playback-dropped-indicator'),
  );
  final refused = find.byKey(const ValueKey<String>('playback-output-refused'));
  final transport = find.byKey(
    const ValueKey<String>('playback-transport-activeCut'),
  );
  Rect playButton(WidgetTester tester) => tester.getRect(
    find.byKey(const ValueKey<String>('playback-play-button')),
  );
  Rect meter(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey<String>('audio-level-meter')));

  /// The meter's seat's fill.
  Color? seatColor(WidgetTester tester) {
    final seat = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('audio-level-meter')),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    return (seat.decoration as ShapeDecoration).color;
  }

  testWidgets('while this scope plays, the play button\'s words say how many '
      'sounds the run plays without', (tester) async {
    await pump(tester, without: silent);
    expect(
      tester.widget<Text>(silentLine).data,
      AppText.strings.playbackSilentCount(2),
    );
    // ↩️The line said which and why on hover while it had a slot of its
    // own; over the play button a hover is the button's.
    expect(
      find.ancestor(of: silentLine, matching: find.byType(AppTooltip)),
      findsNothing,
    );
  });

  testWidgets('⛔CONTROL: stopped, or another scope playing, it says nothing '
      '— the run it would speak of is not this row\'s', (tester) async {
    await pump(tester, playing: null, without: silent);
    expect(silentLine, findsNothing);
    await pump(tester, playing: PlaybackScope.allCuts, without: silent);
    expect(silentLine, findsNothing);
  });

  testWidgets('🚨the words come and go over the play button\'s top, taking '
      'no place — no button moves, the row keeps its width, and a press '
      'there is the button\'s', (tester) async {
    final without = ValueNotifier(PlaysWithout.nothing);
    addTearDown(without.dispose);
    final controller = await pump(tester, notifier: without, ticking: true);
    final quiet = playButton(tester);
    final quietMeter = meter(tester);
    final quietRow = tester.getRect(transport);

    without.value = silent;
    await tester.pump();
    expect(silentLine, findsOneWidget, reason: 'premise');
    expect(playButton(tester), quiet);

    // One gap straight to 300ms: frames 1 and 2 gone over.
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.droppedFrames, greaterThan(0), reason: 'premise');
    expect(dropLine, findsOneWidget);
    expect(silentLine, findsOneWidget);
    expect(
      tester.getRect(dropLine).right,
      lessThanOrEqualTo(tester.getRect(silentLine).left + 0.01),
      reason: 'the drops, then the sounds',
    );
    expect(playButton(tester), quiet);
    expect(meter(tester), quietMeter);
    expect(tester.getRect(transport), quietRow, reason: 'no place taken');
    // Centred on the button, above it, reaching 3 into it; 72 wide.
    final box = Rect.fromLTRB(
      quiet.center.dx - 36 - 0.01,
      quiet.top + 3 - 9 - 0.01,
      quiet.center.dx + 36 + 0.01,
      quiet.top + 3 + 0.01,
    );
    for (final line in [dropLine, silentLine]) {
      final rect = tester.getRect(line);
      expect(
        box.contains(rect.topLeft) && box.contains(rect.bottomRight),
        isTrue,
        reason: 'over the button\'s top: $rect in $box',
      );
    }
    expect(tester.takeException(), isNull, reason: 'no overflow');

    without.value = PlaysWithout.nothing;
    await tester.pump();
    expect(silentLine, findsNothing);
    expect(playButton(tester), quiet);

    await tester.tapAt(Offset(quiet.center.dx, quiet.top + 1));
    await tester.pump();
    expect(controller.isPlaying, isFalse, reason: 'the press stopped it');
    controller.detachTicker();
    await tester.pump();
  });

  testWidgets('the meter beside the mic shows its seat at rest — a well, '
      'the backdrop in a field\'s frame (F-463 ③)', (tester) async {
    await pump(tester, playing: null);
    expect(seatColor(tester), AppColors.backdrop);
    expect(meter(tester).width, greaterThan(0));
  });

  testWidgets('an output that would not open turns the meter\'s seat red, '
      'saying so on hover — the seat it always had', (tester) async {
    final without = ValueNotifier(PlaysWithout.nothing);
    addTearDown(without.dispose);
    await pump(tester, playing: null, notifier: without);
    final seat = meter(tester);
    expect(refused, findsNothing);

    without.value = const PlaysWithout(output: true);
    await tester.pump();
    expect(
      (tester.widget<DecoratedBox>(refused).decoration as ShapeDecoration)
          .color,
      AppColors.danger,
    );
    expect(tester.getRect(refused), seat, reason: 'the seat, not a new one');
    expect(meter(tester), seat);
    expect(
      tester
          .widget<AppTooltip>(
            find.ancestor(of: refused, matching: find.byType(AppTooltip)),
          )
          .message,
      AppText.strings.playbackOutputRefused,
    );
  });

  test('every language says each reason and the count in its own words', () {
    final tables = [
      for (final language in AppLanguage.values) AppStrings.of(language),
    ];
    for (final why in SoundCannotPlay.values) {
      expect(
        {for (final table in tables) table.soundCannotPlay(why)},
        hasLength(tables.length),
        reason: '$why',
      );
    }
    expect(
      {for (final table in tables) table.playbackSilentCount(3)},
      hasLength(tables.length),
    );
    for (final table in tables) {
      expect(table.playbackSilentCount(3), contains('3'));
      expect(table.playbackSilentCount(1), contains('1'));
    }
    expect(
      {
        for (final why in SoundCannotPlay.values)
          tables.first.soundCannotPlay(why),
      },
      hasLength(SoundCannotPlay.values.length),
      reason: 'five reasons, five sentences',
    );
  });
}
