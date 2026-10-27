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

/// 🚨★★★THE TAKE'S CLIP MARK RIDES THE MIC, AND NOTHING MOVES FOR IT.
///
/// 🗣️F-487-Q1 (유저 2026-10-27): 「합치는데, 빨간 점을 마이크에 오버레이로
/// 오른쪽 위에 둠. 근데 빨간 점은 녹음중이다 라는거랑 비슷해서 좀 더
/// 깨졌다는거 알기쉬운 아이콘으로? 오른쪽 위에 들어가니 작게」.
///
/// ↩️It had a seat of its own right of the mic, kept clear while no take
/// clipped — the seat 유저 08-27 asked about (「재생하면 생기는 마이크 오른쪽
/// 패딩? 공간? **그게 왜 생기는건지 몰랐어서**」: it was mounted only while
/// recording, so arming a take grew the row), and the gap F-487 asked about
/// again once it was kept.
///
/// 🧪MEASURED AS THE USER SEES IT: the geometry of the row and the mic,
/// before and after the flags flip. Asserting "the icon is in the tree"
/// would pass on a zero-size box, which is the very shape that caused this.
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

  const markKey = ValueKey<String>('playback-record-clip-mark');
  final micFinder = find.ancestor(
    of: find.byKey(const ValueKey<String>('playback-record-voice-button')),
    matching: find.byType(AppIconButton),
  );

  Future<
    ({
      ValueNotifier<bool> recording,
      ValueNotifier<bool> clipLit,
      List<String> presses,
    })
  >
  pumpRow(WidgetTester tester) async {
    final controller = newController();
    addTearDown(controller.dispose);
    final recording = ValueNotifier<bool>(false);
    addTearDown(recording.dispose);
    final clipLit = ValueNotifier<bool>(false);
    addTearDown(clipLit.dispose);
    final presses = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // ⛔Top-LEFT aligned so the row reports the width it WANTS. Inside a
          // stretched bar a grown child shoves its neighbours instead of
          // widening, and the number would not say so.
          body: Align(
            alignment: Alignment.topLeft,
            child: PlaybackTransportControls(
              controller: controller,
              scope: PlaybackScope.activeCut,
              isVoiceRecording: recording,
              onToggleVoiceRecording: () => presses.add('mic'),
              voiceRecordClipLit: clipLit,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (recording: recording, clipLit: clipLit, presses: presses);
  }

  testWidgets('the row ends at the mic — no seat stands beside it', (
    tester,
  ) async {
    await pumpRow(tester);
    expect(
      tester.getRect(micFinder).right,
      tester.getRect(find.byType(PlaybackTransportControls)).right,
      reason: 'the fixture mounts no meter, so nothing is right of the mic '
          '- the 12px the clip light kept there was the reported gap',
    );
  });

  testWidgets('arming a take and clipping it move nothing', (tester) async {
    final handles = await pumpRow(tester);
    final rowFinder = find.byType(PlaybackTransportControls);
    final idleRow = tester.getRect(rowFinder);
    final idleMic = tester.getRect(micFinder);
    final idleMark = tester.getRect(find.byKey(markKey));

    handles.recording.value = true;
    await tester.pump();
    handles.clipLit.value = true;
    await tester.pump();

    expect(tester.getRect(rowFinder), idleRow);
    expect(tester.getRect(micFinder), idleMic);
    expect(
      tester.getRect(find.byKey(markKey)),
      idleMark,
      reason: 'the mark is laid out whether or not it is lit - only its '
          'colour changes (없다가 생기는 UI 금지)',
    );
  });

  testWidgets('the mark is small, on the mic\'s top-right, and no dot', (
    tester,
  ) async {
    await pumpRow(tester);
    final mic = tester.getRect(micFinder);
    final mark = tester.getRect(find.byKey(markKey));
    expect(mark.width, lessThanOrEqualTo(10), reason: '「작게」');
    expect(
      mic.contains(mark.center),
      isTrue,
      reason: 'it rides the mic',
    );
    expect(mark.center.dx, greaterThan(mic.center.dx), reason: 'right');
    expect(mark.center.dy, lessThan(mic.center.dy), reason: 'top');
    expect(
      tester.widget<Icon>(find.byKey(markKey)).icon,
      isNot(Icons.circle),
      reason: '「빨간 점은 녹음중이다 라는거랑 비슷해서」 - a glyph that says '
          'broken, not the dot a recording light is',
    );
  });

  testWidgets('the mark shows NOTHING until the take clips, then red', (
    tester,
  ) async {
    final handles = await pumpRow(tester);
    Color? markColour() => tester.widget<Icon>(find.byKey(markKey)).color;

    expect(markColour(), Colors.transparent, reason: 'idle');

    handles.recording.value = true;
    await tester.pump();
    expect(
      markColour(),
      Colors.transparent,
      reason: 'armed, the mic itself says it records (its accent)',
    );

    handles.clipLit.value = true;
    await tester.pump();
    expect(
      markColour(),
      Theme.of(tester.element(find.byKey(markKey))).colorScheme.error,
      reason: 'and it goes red on a clip - the one thing red means here',
    );
  });

  testWidgets('a press on the mark is the mic\'s', (tester) async {
    final handles = await pumpRow(tester);
    handles.recording.value = true;
    handles.clipLit.value = true;
    await tester.pump();

    await tester.tapAt(tester.getCenter(find.byKey(markKey)));
    await tester.pump();
    expect(handles.presses, ['mic'], reason: 'the mark takes no press');
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
    // AppIconButton mounts NO Material IconButton since 2026-09-10 (its face
    // is drawn by hand — see [AppIconButtonFace]), so ANY IconButton in this
    // row is a hand-rolled one standing beside them. The old form counted
    // "one per AppIconButton" and would now pass with four strangers in it.
    expect(
      raw,
      isEmpty,
      reason: 'a hand-rolled IconButton in this row is an exception to the '
          'app icon button law, and this row already declared it joined',
    );
  });

  testWidgets(
    'recording lights the RECORD button, and red stays on the clip mark',
    (tester) async {
      final handles = await pumpRow(tester);

      AppIconButton micButton() => tester.widget<AppIconButton>(micFinder);
      expect(micButton().isSelected, isFalse, reason: 'fixture: idle');

      handles.recording.value = true;
      await tester.pump();
      expect(
        micButton().isSelected,
        isTrue,
        reason: 'an ON state is the accent foreground - the same law Play and '
            'Loop already obey. Red belongs to the clip mark on its corner, '
            'where it means one thing: a sample hit the ceiling',
      );
    },
  );
}
