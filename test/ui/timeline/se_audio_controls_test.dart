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
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/audio_clips.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/se_sound_lane_policy.dart'
    show seSoundTotalVolumeLaneId;
import 'package:anicel/src/ui/widgets/field_slider.dart';

import '../../helpers/app_icon_button_probe.dart';
import '../../helpers/named_finders.dart';
import '../../helpers/number_pad_keyboard.dart';
import '../../helpers/text_finders.dart';
import '../../helpers/timeline_host.dart';

/// ⑨b SE audio UX: the row's mute speaker and its 「오디오」 group (I-140 —
/// ↩️the audio lane's AE-style offset value field, then the lane itself).

const _seLayerId = LayerId('sea-voice');

Project _project() {
  return Project(
    id: const ProjectId('sea-project'),
    name: 'SEA Project',
    createdAt: DateTime.utc(2026, 7, 10),
    tracks: [
      Track(
        id: const TrackId('sea-track'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('sea-cut'),
            name: 'SEA Cut',
            duration: 12,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              Layer(
                id: const LayerId('sea-cel'),
                name: 'A',
                frames: const [],
                timeline: const {},
              ),
              Layer(
                id: _seLayerId,
                name: 'S1',
                kind: LayerKind.se,
                frames: [
                  Frame(
                    id: const FrameId('sea-f1'),
                    duration: 3,
                    name: 'Steps',
                    strokes: const [],
                  ),
                ],
                timeline: const {
                  1: TimelineExposure.drawing(FrameId('sea-f1'), length: 3),
                },
                audioClips: [
                  AudioClip(filePath: 'steps.wav', frameId: const FrameId('sea-f1')),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

Layer _seLayer(ProjectRepository repository) {
  return repository
      .requireProject()
      .tracks
      .single
      .cuts
      .single
      .layers
      .firstWhere((layer) => layer.id == _seLayerId);
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required void Function(ProjectRepository repository) onRepositoryCreated,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: HomePage(
        initialProject: _project(),
        onRepositoryCreated: onRepositoryCreated,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _ensureVisibleAndTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('Layer json round-trips muted (absent = false)', () {
    final layer = Layer(
      id: const LayerId('m'),
      name: 'S1',
      kind: LayerKind.se,
      frames: const [],
      muted: true,
    );
    expect(Layer.fromJson(layer.toJson()).muted, isTrue);

    final json = layer.copyWith(muted: false).toJson();
    expect(json.containsKey('muted'), isFalse);
    expect(Layer.fromJson(json).muted, isFalse);
  });

  // 🗣️F-577 (유저 2026-11-10): 「사운드버튼은 단순하게 음소거/비음소거
  // 역할만 하는 토글버튼되도록」. ↩️It was a door to the SE mixer (R10 R3).
  testWidgets('the SE speaker is a mute toggle in both orientations, and its '
      'glyph reads the mute', (tester) async {
    // The x-sheet's header is the rail stood up, laid out whole and seen
    // through the window its panel can spare (`layer_rail_window.dart`): a
    // short dock cuts its tail, and the speaker is in that tail — the blend
    // column ends it (F-577). This test is about the TOGGLE being the same
    // in both orientations, so give the dock the height a user working in
    // the sheet would.
    // -300 → -322 (I-89 ③, 2026-10-11): the header grew 22 — a header
    // graph's slot, kept for its lanes since (I-89-Q17 A). The hand stops
    // the dock at half the window (결정 8), so the window pays twice that:
    // 1000 → 1044.
    // -322 → -460, 1044 → 1300 (F-577): the speaker went from the name's end
    // to the blend column, the tail's very end, so the dock opens to its
    // tallest (`EditorPanelLayoutModel.maxDockExtent`).
    await tester.binding.setSurfaceSize(const Size(1200, 1300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late ProjectRepository repository;
    await _pumpHome(tester, onRepositoryCreated: (repo) => repository = repo);
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -460),
    );
    await tester.pumpAndSettle();

    final speaker = find.named('timeline-layer-mute-sea-voice');
    expect(tester.appIconButton(speaker).icon, Icons.volume_up);
    await _ensureVisibleAndTap(tester, speaker);
    expect(_seLayer(repository).muted, isTrue);
    expect(
      tester.appIconButton(speaker).icon,
      Icons.volume_off,
      reason: 'the rail row memo sees the mute',
    );

    // The cel row carries no speaker — SE rows only.
    expect(
      find.named('timeline-layer-mute-sea-cel'),
      findsNothing,
    );

    // The X-sheet header carries the same toggle.
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();
    await _ensureVisibleAndTap(
      tester,
      find.named('xsheet-layer-mute-sea-voice'),
    );
    expect(_seLayer(repository).muted, isFalse);
  });

  // 🗣️I-145 (유저 2026-10-30) Q1 「따로 한 값 — 두 입구」, and F-577: the
  // second door is the bar beside the speaker.
  group('the Total bar is the row\'s Total — the 「오디오」 group\'s lane', () {
    final bar = find.named('timeline-layer-total-volume-sea-voice');

    String lane(EditorSessionManager session) => session.laneVerbs
        .laneValueAt(
          _seLayerId,
          seSoundTotalVolumeLaneId,
          0,
          frameIsGlobal: true,
        )!;

    testWidgets('🎯a drag moves the bar and writes at the release alone, '
        'as one undo, and the lane reads what it wrote', (tester) async {
      final semantics = tester.ensureSemantics();
      final session = EditorSessionManager(initialProject: _project());
      addTearDown(session.dispose);
      await pumpTimelineHostOn(tester, session, surface: const Size(1400, 600));
      expect(tester.widget<FieldSlider>(bar).value, 1.0, reason: 'CONTROL');
      // What the bar SHOWS — its own echo of the hand, which no host value
      // follows while it moves (↩️the mixer held the drag itself).
      double shown() => double.parse(
        RegExp(r'[0-9.]+').firstMatch(tester.getSemantics(bar).value)![0]!,
      );
      expect(shown(), 100, reason: 'CONTROL');

      final drag = await tester.startGesture(tester.getCenter(bar));
      await drag.moveBy(const Offset(-10, 0));
      await drag.moveBy(const Offset(-10, 0));
      await tester.pump();
      expect(
        shown(),
        lessThan(100),
        reason: 'CONTROL: the bar follows the hand',
      );
      expect(
        _seLayer(session.repository).seSound.totalVolume,
        1.0,
        reason: 'nothing written while it moves',
      );

      await drag.up();
      await tester.pumpAndSettle();
      final total = _seLayer(session.repository).seSound.totalVolume;
      expect(total, lessThan(1.0));
      expect(tester.widget<FieldSlider>(bar).value, total);
      expect(
        lane(session),
        '${(total * 100).toStringAsFixed(2)}%',
        reason: 'one field, two doors',
      );

      session.undo();
      await tester.pumpAndSettle();
      expect(_seLayer(session.repository).seSound.totalVolume, 1.0);
      semantics.dispose();
    });

    testWidgets('a value typed into the lane stands on the bar', (
      tester,
    ) async {
      final session = EditorSessionManager(initialProject: _project());
      addTearDown(session.dispose);
      await pumpTimelineHostOn(tester, session, surface: const Size(1400, 600));
      session.laneVerbs.setLaneValueAt(
        _seLayerId,
        seSoundTotalVolumeLaneId,
        3,
        '150',
        frameIsGlobal: true,
        description: 'Type',
        scaleLinked: false,
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<FieldSlider>(bar).value,
        closeTo(1.5, 1e-9),
        reason: 'past 100%: the bar reaches the Total\'s 200',
      );
    });
  });

  /// 🗣️I-140 (유저 2026-10-28): the row's sound is its 「오디오」 group —
  /// Q1 「행에 늘 있는 「오디오」 그룹」, Q2 「%」, Q3 「이번엔 한 값」. ↩️The
  /// speaker's mixer held a fader and a pan of the row, and the twirl showed
  /// a waveform lane of the row's sounds.
  testWidgets('the 「오디오」 group reads the row\'s Volume in % and its Pan '
      'as a side; a typed Volume keys at the playhead', (
    tester,
  ) async {
    late ProjectRepository repository;
    await _pumpHome(tester, onRepositoryCreated: (repo) => repository = repo);
    await _ensureVisibleAndTap(
      tester,
      find.named('timeline-lane-toggle-sea-voice'),
    );
    await _ensureVisibleAndTap(
      tester,
      find.named('timeline-lane-group-toggle-sea-voice-sound-group'),
    );

    Finder value(String laneId) =>
        find.byKey(ValueKey<String>('timeline-lane-value-sea-voice-$laneId'));
    String shown(String laneId) => tester
        .widgetList<Text>(
          find.descendant(of: value(laneId), matching: find.anyText()),
        )
        .map((text) => text.data)
        .join();
    expect(shown('sound:volume'), '100.00%', reason: 'as recorded, unkeyed');
    expect(shown('sound:pan'), 'C', reason: 'in the middle');

    await _ensureVisibleAndTap(
      tester,
      find.byKey(
        const ValueKey<String>(
          'timeline-lane-value-sea-voice-sound:volume-edit',
        ),
      ),
    );
    await openThePadsKeyboard(tester);
    await tester.enterText(
      find.byKey(
        const ValueKey<String>(
          'timeline-lane-value-field-sea-voice-sound:volume',
        ),
      ),
      '50',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final volume = _seLayer(repository).seSound.volume;
    expect(volume.keys.keys, [0], reason: 'keyed at the playhead (F-407)');
    expect(volume.keyAt(0)!.value, 0.5, reason: '50% of the sound');
    expect(shown('sound:volume'), '50.00%');
  });

  /// 🚨THE GUARD AND THE CLAMPS EVERY CLIP EDIT SHARES.
  ///
  /// Seven edits wrote these out separately until the audit folded them
  /// into one helper, and the mutation campaign then found all four
  /// surviving (2026-09-04): nothing asked what happens on a row that is
  /// not SE, on an index past the end, or with a negative number. A shared
  /// guard nobody tests is worse than seven, because one edit silently
  /// covers for the rest. (Three edits are left since I-140.)
  test('a clip edit refuses a non-SE row, a bad index, and negatives', () {
    final session = EditorSessionManager(initialProject: _project());
    addTearDown(session.dispose);

    Layer seLayer() => _seLayer(session.repository);
    Layer celLayer() => session.repository
        .requireProject()
        .tracks
        .expand((track) => track.cuts)
        .expand((cut) => cut.layers)
        .firstWhere((layer) => layer.id == const LayerId('sea-cel'));

    // A DRAWING row has no clips to edit — and asking must not create one.
    audioClipsOf(session).setAudioClipGain(const LayerId('sea-cel'), 0, 0.5);
    expect(celLayer().audioClips, isEmpty);
    expect(
      session.canUndo,
      isFalse,
      reason: 'a refused edit is not an undo step',
    );

    // An index past the end is refused, not clamped to the last clip.
    audioClipsOf(session).setAudioClipGain(_seLayerId, 7, 0.5);
    expect(seLayer().audioClips.single.gain, 1.0);
    expect(session.canUndo, isFalse);

    // 🚨AND THE INDEX EXACTLY AT THE END — the boundary the guard is
    // written for. `7` is refused by any upper bound at all; only
    // `clipIndex == clips.length` tells `>=` apart from `>`, and past
    // that guard the edit reaches `clips[clipIndex]` and throws.
    audioClipsOf(session).setAudioClipGain(_seLayerId, 1, 0.5);
    expect(seLayer().audioClips.single.gain, 1.0);
    expect(session.canUndo, isFalse);

    // Negative numbers clamp to zero rather than reaching the model.
    audioClipsOf(session).setAudioClipOffset(_seLayerId, 0, -4);
    expect(
      seLayer().audioClips.single.offsetFrames,
      0,
      reason: 'a negative slide is zero, not a negative offset',
    );
    audioClipsOf(session).setAudioClipGain(_seLayerId, 0, -2);
    expect(
      seLayer().audioClips.single.gain,
      0.0,
      reason: 'a negative gain is silence, not a negative multiplier',
    );
  });

  /// A DRAWING row that CARRIES clips — the state a kind change leaves
  /// behind — is refused BY ITS KIND. An empty clip list would be caught
  /// by the index check instead, which is how the first version of this
  /// case passed against a disabled kind guard (2026-09-04).
  test('a clip edit refuses a row that is not SE, even when it has clips', () {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('sea-project'),
        name: 'SEA Project',
        createdAt: DateTime.utc(2026, 7, 10),
        tracks: [
          Track(
            id: const TrackId('sea-track'),
            name: 'Video',
            cuts: [
              Cut(
                id: const CutId('sea-cut'),
                name: 'SEA Cut',
                duration: 12,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [
                  Layer(
                    id: const LayerId('sea-cel'),
                    name: 'A',
                    frames: [
                      Frame(
                        id: const FrameId('sea-f1'),
                        duration: 3,
                        strokes: const [],
                      ),
                    ],
                    audioClips: [
                      AudioClip(
                        filePath: 'steps.wav',
                        frameId: const FrameId('sea-f1'),
                        gain: 0.75,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);

    Layer celLayer() => session.repository
        .requireProject()
        .tracks
        .expand((track) => track.cuts)
        .expand((cut) => cut.layers)
        .firstWhere((layer) => layer.id == const LayerId('sea-cel'));

    audioClipsOf(session).setAudioClipGain(const LayerId('sea-cel'), 0, 0.25);
    expect(
      celLayer().audioClips.single.gain,
      0.75,
      reason: 'the row is a drawing row, so its clips are not editable here',
    );
    expect(session.canUndo, isFalse);
  });

  /// R5 #19: the instance editor's unlink can drop SEVERAL sounds off one
  /// block, and it must be ONE undo with them. The removal walks the
  /// indexes DESCENDING because every index is into the list as it stands
  /// NOW — taking a low one out first shifts every index above it, so an
  /// ascending walk deletes the wrong clips.
  test('unlinking several clips at once removes exactly those, in one undo', () {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('sea-project'),
        name: 'SEA Project',
        createdAt: DateTime.utc(2026, 7, 10),
        tracks: [
          Track(
            id: const TrackId('sea-track'),
            name: 'Video',
            cuts: [
              Cut(
                id: const CutId('sea-cut'),
                name: 'SEA Cut',
                duration: 12,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [
                  Layer(
                    id: _seLayerId,
                    name: 'S1',
                    kind: LayerKind.se,
                    frames: [
                      Frame(
                        id: const FrameId('sea-f1'),
                        duration: 3,
                        name: 'Steps',
                        strokes: const [],
                      ),
                    ],
                    timeline: const {
                      1: TimelineExposure.drawing(FrameId('sea-f1'), length: 3),
                    },
                    audioClips: [
                      AudioClip(filePath: 'a.wav', frameId: const FrameId('sea-f1')),
                      AudioClip(filePath: 'b.wav', frameId: const FrameId('sea-f1')),
                      AudioClip(filePath: 'c.wav', frameId: const FrameId('sea-f1')),
                      AudioClip(filePath: 'd.wav', frameId: const FrameId('sea-f1')),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);

    Layer seLayer() => session.repository
        .requireProject()
        .tracks
        .single
        .cuts
        .single
        .layers
        .single;

    // Deliberately UNSORTED and straddling: an ascending removal would
    // take 0 out, slide everything down, and then take what is now index 2
    // (`d.wav`) instead of `c.wav`.
    audioClipsOf(session).unlinkAudioClipsFromLayer(_seLayerId, [0, 2]);

    expect(
      seLayer().audioClips.map((clip) => clip.filePath),
      ['b.wav', 'd.wav'],
    );
    expect(session.canUndo, isTrue);
    session.undo();
    expect(
      seLayer().audioClips.map((clip) => clip.filePath),
      ['a.wav', 'b.wav', 'c.wav', 'd.wav'],
      reason: 'several unlinks are ONE undo step, not one per clip',
    );

    // An unlink that removes nothing is not an undo step.
    session.redo();
    audioClipsOf(session).unlinkAudioClipsFromLayer(_seLayerId, [9]);
    expect(
      seLayer().audioClips.map((clip) => clip.filePath),
      ['b.wav', 'd.wav'],
    );
  });

  /// ⛔"no-op when unchanged" is a LAW, not a comment: an edit that sets a
  /// clip to the value it already has must not spend an undo step. Without
  /// it the value field's every keystroke-commit stacks another entry and
  /// one undo takes the user nowhere.
  test('setting a clip to the value it already has spends no undo step', () {
    final session = EditorSessionManager(initialProject: _project());
    addTearDown(session.dispose);

    Layer seLayer() => _seLayer(session.repository);

    audioClipsOf(session).setAudioClipGain(_seLayerId, 0, 0.25);
    expect(seLayer().audioClips.single.gain, 0.25);

    audioClipsOf(session).setAudioClipGain(_seLayerId, 0, 0.25);
    audioClipsOf(session).setAudioClipOffset(_seLayerId, 0, 0);

    session.undo();
    expect(
      seLayer().audioClips.single.gain,
      1.0,
      reason:
          'the two repeat edits added nothing, so ONE undo reaches the '
          'gain the clip started with',
    );
    expect(session.canUndo, isFalse);
  });
}

/// The collaborator that owns the laws above, under its OWN name.
///
/// 🚨`tool/mutation_run.dart` picks the tests that will witness a mutation by
/// asking which tests IMPORT the file. Round 8 carved ~50 collaborators out of
/// `EditorSessionManager` and every pin still arrived through the session, so
/// 63 of the 71 files under `lib/src/ui/session/` reported UNNAMED and the
/// campaign skipped exactly the code that round wrote. ⛔Widening the runner to
/// transitive reachability was tried and reverted (one small file drew 390
/// namers); a collaborator that holds a law gets a test that names it instead.
AudioClips audioClipsOf(EditorSessionManager session) => session.audioClips;
