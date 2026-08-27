import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

/// 🚨★★★ARMING A TAKE MUST NOT MOVE THE ROW.
///
/// 유저 2026-08-27: 「재생하면 생기는 마이크 오른쪽 패딩? 공간? **그게 왜
/// 생기는건지 몰랐어서**」. They were reading a LAYOUT JUMP as a bug in the
/// mic button, and it was one: the clip light was mounted with
/// `!recording ? SizedBox.shrink() : …`, so starting a take grew the row.
///
/// ⛔없다가 생기는 UI 금지 — 자리는 항상 예약하고 내용만 바꾼다. The seat is
/// reserved and only the colour changes.
///
/// 🧪MEASURED AS THE USER SEES IT: the geometry of the row, before and after
/// the flag flips. Asserting "the icon is in the tree" would pass on a
/// zero-size box, which is the very shape that caused this.
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

  CanvasPlaybackController newController() => CanvasPlaybackController(
    resolveProject: project,
    resolveActiveCutId: () => const CutId('cut'),
    resolveActiveTrackId: () => const TrackId('track'),
    resolveFrameRate: () => const ProjectFrameRate.integer(10),
  );

  Future<({ValueNotifier<bool> recording, ValueNotifier<bool> clipLit})>
  pumpRow(WidgetTester tester, {bool freeWidth = false}) async {
    final controller = newController();
    addTearDown(controller.dispose);
    final recording = ValueNotifier<bool>(false);
    addTearDown(recording.dispose);
    final clipLit = ValueNotifier<bool>(false);
    addTearDown(clipLit.dispose);
    final row = PlaybackTransportControls(
      controller: controller,
      scope: PlaybackScope.activeCut,
      isVoiceRecording: recording,
      onToggleVoiceRecording: () {},
      voiceRecordClipLit: clipLit,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // ⛔Top-LEFT aligned so the row reports the width it WANTS. Inside a
          // stretched bar a grown child shoves its neighbours instead of
          // widening, and the number would not say so.
          body: freeWidth
              ? Align(alignment: Alignment.topLeft, child: row)
              : row,
        ),
      ),
    );
    await tester.pump();
    return (recording: recording, clipLit: clipLit);
  }

  testWidgets('arming a take does not resize the transport row', (
    tester,
  ) async {
    final handles = await pumpRow(tester, freeWidth: true);

    final rowFinder = find.byType(PlaybackTransportControls);
    final lightFinder = find.byKey(
      const ValueKey<String>('playback-record-clip-light'),
    );
    final idleWidth = tester.getSize(rowFinder).width;
    // ⛔THE LIGHT'S OWN RECT, not the mic's. The light sits AFTER the mic, so
    // in a left-aligned row a growing light never moves the mic — asserting
    // that it does not move would be true whatever this code did. What the
    // user saw is the gap that appeared BESIDE the mic, and that gap is this
    // widget's own box.
    final idleLight = tester.getRect(lightFinder);
    expect(idleWidth, greaterThan(0), reason: 'fixture: the row laid out');
    expect(
      idleLight.width,
      greaterThan(0),
      reason: 'fixture: the seat is occupied even while idle',
    );

    handles.recording.value = true;
    await tester.pump();

    expect(
      tester.getSize(rowFinder).width,
      idleWidth,
      reason: 'the clip light keeps its seat whether or not a take is armed '
          '- a row that grows on record is the reported 마이크 오른쪽 공간',
    );
    expect(
      tester.getRect(lightFinder),
      idleLight,
      reason: 'and the seat is the SAME box, not merely the same width - a '
          'light that moved would push its neighbours just as visibly',
    );
  });

  testWidgets('the row hand-rolls no IconButton of its own', (tester) async {
    // ⛔ASKED OF THE WIDGET TREE, not of the source: every button in this row
    // is an [AppIconButton], so the app's on-state law (accent foreground,
    // never a colour picked here) reaches all of them. The record button was
    // the last exception - `iconSize: 18` and a hand-painted
    // `colorScheme.error` of its own.
    await pumpRow(tester);

    final wrapped = tester.widgetList<AppIconButton>(
      find.descendant(
        of: find.byType(PlaybackTransportControls),
        matching: find.byType(AppIconButton),
      ),
    );
    expect(
      wrapped.length,
      greaterThanOrEqualTo(4),
      reason: 'fixture: start, play, loop and record are all mounted',
    );
    final raw = tester.widgetList<IconButton>(
      find.descendant(
        of: find.byType(PlaybackTransportControls),
        matching: find.byType(IconButton),
      ),
    );
    // Every AppIconButton mounts exactly one IconButton internally, so a
    // count above that is a hand-rolled one standing beside them.
    expect(
      raw.length,
      wrapped.length,
      reason: 'a hand-rolled IconButton in this row is an exception to the '
          'app icon button law, and this row already declared it joined',
    );
  });

  testWidgets(
    'recording lights the RECORD button, and red stays on the clip light',
    (tester) async {
      final handles = await pumpRow(tester);

      AppIconButton micButton() => tester.widget<AppIconButton>(
        find.ancestor(
          of: find.byKey(
            const ValueKey<String>('playback-record-voice-button'),
          ),
          matching: find.byType(AppIconButton),
        ),
      );
      expect(micButton().isSelected, isFalse, reason: 'fixture: idle');

      handles.recording.value = true;
      await tester.pump();
      expect(
        micButton().isSelected,
        isTrue,
        reason: 'an ON state is the accent foreground - the same law Play and '
            'Loop already obey. Red belongs to the clip light beside it, '
            'where it means one thing: a sample hit the ceiling',
      );
    },
  );

  testWidgets('the reserved seat shows NOTHING until a take is armed', (
    tester,
  ) async {
    // ⛔THE OTHER HALF OF 「자리는 예약하고 내용만 바꾼다」. The seat test above
    // proves the space is there; without this one the fix could have shipped
    // a dot that is always visible, which is a different UI than the row had.
    final handles = await pumpRow(tester);

    Color? lightColour() => tester
        .widget<Icon>(
          find.byKey(const ValueKey<String>('playback-record-clip-light')),
        )
        .color;

    expect(
      lightColour(),
      Colors.transparent,
      reason: 'idle, the seat is held and the content is absent',
    );

    handles.recording.value = true;
    await tester.pump();
    expect(
      lightColour(),
      isNot(Colors.transparent),
      reason: 'armed, the light is on duty',
    );

    handles.clipLit.value = true;
    await tester.pump();
    expect(
      lightColour(),
      isNot(Colors.transparent),
      reason: 'and it goes red on a clip - the one thing red means here',
    );
  });
}
