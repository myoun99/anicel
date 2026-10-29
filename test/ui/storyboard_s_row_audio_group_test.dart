import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/se_sound_lane_policy.dart'
    show seSoundGroupLaneId;

import '../helpers/named_finders.dart';

/// 🚨C5 (2026-08-17): the storyboard's S-row twirl shows the lanes the
/// TIMELINE's own lane law gives the row — both rails read one list. The
/// storyboard once mounted a waveform lane off the twirl alone, so an empty
/// S row showed a strip its timeline twin never drew.
///
/// I-140 (유저 2026-10-28, Q1 「행에 늘 있는 「오디오」 그룹」): the waveform
/// lane is gone, and every S row — a sound imported or none — twirls its
/// 「오디오」 group down, as its timeline twin does.
const _trackId = TrackId('agate-track');
const _withSoundId = LayerId('agate-se-sound');
const _emptyId = LayerId('agate-se-empty');

Project _project() => Project(
  id: const ProjectId('agate-project'),
  name: 'Audio Lane Gate',
  createdAt: DateTime.utc(2026, 8, 17),
  tracks: [
    Track(
      id: _trackId,
      name: 'Video',
      cuts: [
        Cut(
          id: const CutId('agate-cut'),
          name: 'Cut',
          duration: 10,
          canvasSize: const CanvasSize(width: 640, height: 360),
          layers: [
            Layer(
              id: const LayerId('agate-cel'),
              name: 'A',
              frames: const [],
              timeline: const {},
            ),
          ],
        ),
      ],
      seLayers: [
        // Slot 0 (S1): a sound block WITH an imported clip.
        Layer(
          id: _withSoundId,
          name: 'S1',
          kind: LayerKind.se,
          frames: [
            Frame(
              id: const FrameId('agate-cel-sound'),
              duration: 4,
              strokes: const [],
            ),
          ],
          timeline: {
            1: const TimelineExposure.drawing(
              FrameId('agate-cel-sound'),
              length: 4,
            ),
          },
          audioClips: [
            AudioClip(filePath: 'a.wav', frameId: const FrameId('agate-cel-sound')),
          ],
        ),
        // Slot 1 (S2): nothing imported.
        Layer(
          id: _emptyId,
          name: 'S2',
          kind: LayerKind.se,
          frames: const [],
          timeline: const {},
        ),
      ],
    ),
  ],
);

Future<void> _openStoryboard(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: _project())),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
  );
  await tester.pumpAndSettle();
}

/// The S row at [slot]'s twirl — the timeline's own row's, named by its
/// layer (I-89 ①).
Future<void> _twirl(WidgetTester tester, int slot) async {
  final layer = _project().tracks.single.seLayers[slot];
  final toggle = find.named('storyboard-lane-toggle-${layer.id.value}');
  await tester.ensureVisible(toggle);
  await tester.pumpAndSettle();
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

void main() {
  for (final (slot, id, what) in [
    (0, _withSoundId, 'WITH a sound imported'),
    (1, _emptyId, 'with NO sound imported'),
  ]) {
    testWidgets('twirling an S row $what shows its 「오디오」 group and no '
        'waveform lane — the timeline\'s own list', (tester) async {
      await _openStoryboard(tester);
      await _twirl(tester, slot);

      expect(
        find.byKey(
          ValueKey<String>(
            'storyboard-se-lane-row-0-${slot + 1}-$seSoundGroupLaneId',
          ),
        ),
        findsOneWidget,
        reason: 'the group\'s band, on every S row',
      );
      expect(
        find.byKey(
          ValueKey<String>(
            'storyboard-lane-label-${id.value}-$seSoundGroupLaneId',
          ),
        ),
        findsOneWidget,
        reason: 'and its label on the rail',
      );
      expect(
        find.byKey(
          ValueKey<String>('storyboard-se-lane-row-0-${slot + 1}-se-audio'),
        ),
        findsNothing,
        reason: 'the waveform lane went (I-140) — the row\'s band draws its '
            'sounds',
      );
    });
  }
}
