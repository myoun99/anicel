import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart'
    show InstructionEvent;
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
import 'package:anicel/src/models/sheet_sources.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/track_transitions.dart'
    show cutMediaStartFrame;
import 'package:anicel/src/models/transition_geometry.dart'
    show cutTransitionRampAt;
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/services/import/import_layer_spot.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart'
    show PlaybackScope;
import 'package:anicel/src/ui/session/storyboard_cursor.dart';
import 'package:anicel/src/ui/storyboard_playhead_mapping.dart';

/// 🚨A CUT'S OWN FRAME 0 IS ITS MEDIA START (I-73-ol-index-space).
///
/// A cut an O.L arrives into is drawn its のりしろ before its conte begins
/// (F-227): its rows' keys, the timeline's columns and what playback shows
/// all count from there. The session's own conversions counted from the
/// cut's PLACE on the track instead — 🧪measured 2026-10-08 on this
/// fixture: the storyboard's playhead on the track's frame 30 left the
/// session on the receiving cut's frame 6, whose picture plays at frame
/// 24; a sound at frame 30 stood on the timeline's column 6, six left of
/// the picture it is heard with; and the timeline's column 12 said it was
/// the track's frame 36 while its picture played at 30.
///
/// One conversion now, on the axis (`TrackFrameAxis` — its arithmetic is
/// pinned beside it, `a_cuts_own_frames_begin_its_lead_before_its_place`),
/// and one lens for the cut view's window on the track's rows
/// (`activeCutMediaStartFrame`). These are the session's readers of both.
void main() {
  const trackId = TrackId('t1');
  const a = CutId('a');
  const b = CutId('b');
  const sound = LayerId('s1');
  const ol = InstructionEvent(instructionId: 'ol', length: 12);

  Cut cut(String id) => Cut(
    id: CutId(id),
    name: id,
    duration: 24,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [
      Layer(id: LayerId('cel-$id'), name: 'A', frames: const []),
      Layer(
        id: LayerId('sb-$id'),
        name: 'Conte',
        kind: LayerKind.storyboard,
        frames: [
          for (final panel in ['p1', 'p2'])
            Frame(id: FrameId('$panel-$id'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: TimelineExposure.drawing(FrameId('p1-$id'), length: 12),
          12: TimelineExposure.drawing(FrameId('p2-$id'), length: 12),
        },
      ),
    ],
  );

  /// Cuts a [0, 24) and b [24, 48), and one S row: a sound over [20, 22),
  /// and one inside b, [30, 34).
  EditorSessionManager sessionWithNoOl() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('ol'),
        name: 'O.L',
        createdAt: DateTime.utc(2026, 10, 8),
        tracks: [
          Track(
            id: trackId,
            name: 'V1',
            seLayers: [
              Layer(
                id: sound,
                name: 'S1',
                kind: LayerKind.se,
                frames: [
                  for (final id in const ['early', 'late'])
                    Frame(id: FrameId(id), duration: 1, strokes: const []),
                ],
                timeline: const {
                  20: TimelineExposure.drawing(FrameId('early'), length: 2),
                  30: TimelineExposure.drawing(FrameId('late'), length: 4),
                },
              ),
            ],
            cuts: [cut('a'), cut('b')],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  /// [sessionWithNoOl] with an O.L over [18, 30) between the cuts: six
  /// frames of it are b's のりしろ, so b's own frame 0 is the track's 18
  /// and its conte begins at its frame 6. The earlier sound is in the
  /// overlap.
  EditorSessionManager sessionOf() => sessionWithNoOl()
    ..transitions.updateTransitionInstructions({18: ol});

  Layer soundRow(EditorSessionManager session) =>
      session.repository.requireProject().tracks.single.seLayers.single;

  test('the fixture: b stands at 24 and its own frames begin at 18', () {
    final session = sessionOf()..selectCut(b);
    expect(session.activeCutGlobalStartFrame, 24);
    expect(session.activeCutMediaStartFrame, 18);
    expect(
      session.activeCutMediaStartFrame,
      cutMediaStartFrame(session.repository.requireProject(), b),
      reason: 'the lens is the model\'s own answer for the cut',
    );
    session.selectCut(a);
    expect(
      (session.activeCutGlobalStartFrame, session.activeCutMediaStartFrame),
      (0, 0),
      reason: 'a cut nothing arrives into: one number',
    );
  });

  test('🚨the lens follows the O.L — made after it was first read, and '
      'unmade', () {
    final session = sessionWithNoOl()..selectCut(b);
    expect(session.activeCutMediaStartFrame, 24, reason: 'no O.L yet');

    session.transitions.updateTransitionInstructions({18: ol});
    expect(session.activeCutMediaStartFrame, 18);

    session.undo();
    expect(session.activeCutMediaStartFrame, 24);
  });

  test('with no cut open the lens is the identity: the track\'s rows are '
      'read on their own axis, and the cut\'s window shows nothing', () {
    final session = sessionOf();

    session.selectGlobalFrame(60);

    expect(session.activeCutId, isNull, reason: 'fixture: past the film');
    expect(session.activeCutMediaStartFrame, 0);
    expect(session.trackSe.rowAxisOffset(sound), 0);
    expect(
      session.trackSe.trackSeWindow.displayLayer(soundRow(session)).timeline,
      isEmpty,
    );
  });

  test('🚨a frame of the track is the cut\'s own frame that PLAYS there — '
      'and back', () {
    for (final (global, own) in const [(24, 6), (30, 12), (40, 22), (47, 29)]) {
      final session = sessionOf();

      session.selectGlobalFrame(global);

      expect(session.activeCutId, b, reason: 'track $global');
      expect(session.currentFrameIndex, own, reason: 'track $global');
      expect(session.editingGlobalFrame, global);
      expect(
        session.rowSpans.trackGlobalFrameOf(b, session.currentFrameIndex),
        global,
        reason: 'the frame the picture on that column plays at',
      );
    }
  });

  test('a cut no track holds has no place to count a frame from', () {
    final session = sessionOf();
    expect(session.rowSpans.trackGlobalFrameOf(const CutId('nowhere'), 7), 7);
  });

  test('the overlap belongs to the cut it stands in: its frames are the '
      'cut\'s in front', () {
    final session = sessionOf();

    session.selectGlobalFrame(20);

    expect(session.activeCutId, a);
    expect(session.currentFrameIndex, 20);
  });

  test('🚨the timeline says where it stands: a column of the のりしろ is a '
      'frame of the track before the cut\'s place — and the storyboard '
      'shows its playhead on the cut\'s own block', () {
    final session = sessionOf()..selectCut(b);
    session.standOnRow(const LayerRowAddress(LayerId('cel-b')));

    session.selectFrameIndex(2);

    expect(session.editingGlobalFrame, 20);
    expect(
      session.playheadCursors.trackFrameNow(),
      24,
      reason: 'held to the cut, as a frame past its end is',
    );

    session.selectFrameIndex(12);
    expect(session.editingGlobalFrame, 30);
    expect(session.playheadCursors.trackFrameNow(), 30);
  });

  test('🚨a press on the V row takes the cut under the track\'s frame, on '
      'the frame of its own that plays there', () {
    final session = sessionOf()..selectCut(b);
    session.selectFrameIndex(12);
    session.selectTrackCutAtPlayhead(trackId);
    expect((session.activeCutId, session.currentFrameIndex), (b, 12));

    // The giving cut's のりしろ past its end plays over the receiving
    // cut's frames: the track's 26 is b's.
    session.selectCut(a);
    session.selectFrameIndex(26);
    expect(session.editingGlobalFrame, 26, reason: 'fixture');
    session.selectTrackCutAtPlayhead(trackId);
    expect((session.activeCutId, session.currentFrameIndex), (b, 8));

    // …and the receiving cut's, before its conte, over the giving cut's.
    session.selectFrameIndex(2);
    expect(session.editingGlobalFrame, 20, reason: 'fixture');
    session.selectTrackCutAtPlayhead(trackId);
    expect((session.activeCutId, session.currentFrameIndex), (a, 20));
  });

  group('a scrub on the track', () {
    test('🚨over the open cut stands on the frame that plays there', () {
      final session = sessionOf()..selectCut(b);

      session.frameScrub.scrubGlobalFrame(30);

      expect(session.currentFrameIndex, 12);
      session.frameScrub.commitFrameScrub();
      expect((session.activeCutId, session.currentFrameIndex), (b, 12));
    });

    test('🚨parked over another cut shows that cut on its own frame — and '
        'lands there', () {
      final session = sessionOf()..selectCut(a);
      // A press and a move, both off the open cut: the move engages the
      // live preview.
      session.frameScrub.scrubGlobalFrame(29);
      session.frameScrub.scrubGlobalFrame(30);
      expect(session.frameScrub.active.value, isTrue, reason: 'fixture');

      final shown = session.cutUnderPlayhead.resolve()!;
      expect((shown.cut.id, shown.startFrame, shown.localFrame), (b, 24, 12));
      expect(session.cutUnderPlayhead.localFrame, 12);

      session.frameScrub.commitFrameScrub();
      expect((session.activeCutId, session.currentFrameIndex), (b, 12));
    });
  });

  group('the cut\'s window on the track\'s S rows', () {
    test('🚨opens at the cut\'s own frame 0: a sound stands under the '
        'picture it is heard with', () {
      final session = sessionOf()..selectCut(b);
      final window = session.trackSe.trackSeWindow;

      expect(window.toLocalFrame(30), 12);
      expect(window.toGlobalFrame(12), 30);
      expect(session.trackSe.rowAxisOffset(sound), 18);
      expect(
        window.cutEndFrameExclusive,
        48,
        reason: 'and the cut still ends where it ends on the track',
      );
      final shown = window.displayLayer(soundRow(session));
      expect(
        {
          for (final entry in shown.timeline.entries)
            entry.key: entry.value.length,
        },
        {2: 2, 12: 4},
        reason: 'the sound in the overlap plays over b\'s のりしろ, and is '
            'no spill-in from before the window',
      );
      expect(session.trackSe.rowAxisOffset(const LayerId('cel-b')), 0);
    });

    test('🚨a sound let go on a cell of the row lands on the frame that '
        'cell plays', () {
      final session = sessionOf()..selectCut(b);

      expect(
        session.dropSpotFor(sound, 4, 'door.wav'),
        const SeCellSpot(layerId: sound, trackFrame: 22, shownCell: 4),
      );
    });

    test('🚨a sound made at the storyboard\'s cursor stands on the '
        'cursor\'s frame', () {
      final session = sessionOf();
      session.standOnRow(
        const LayerRowAddress(sound),
        panel: WorkingPanel.storyboard,
        globalFrameIndex: 40,
      );
      expect(session.activeCutId, b, reason: 'fixture: a cut is open');
      expect(
        session.storyboardCursor.canCreateSeEntryAtStoryboardCursor,
        isTrue,
        reason: 'fixture',
      );

      session.storyboardCursor.createSeEntryAtStoryboardCursor();

      expect(soundRow(session).timeline[40]?.length, 1);
      expect(soundRow(session).timeline.keys, [20, 30, 40]);
    });
  });

  group('the transition row in the cut', () {
    const fadeOut = InstructionEvent(instructionId: 'fo', length: 6);

    /// The O.L, and a fade out over b's last six frames — the track's
    /// [42, 48), b's own [24, 30).
    EditorSessionManager withAFadeInsideB() {
      final session = sessionOf();
      session.transitions.updateTransitionInstructions({18: ol, 42: fadeOut});
      return session..selectCut(b);
    }

    Map<int, int> lengthsOf(Layer row) => {
      for (final entry in row.instructions.entries)
        entry.key: entry.value.length,
    };

    test('🚨its marks stand on the cut\'s own frames: the O.L from its '
        'frame 0, a span inside the cut under its pictures', () {
      final session = withAFadeInsideB();

      expect(
        lengthsOf(session.transitions.trackTransitionDisplayLayer),
        {0: 12, 24: 6},
      );
      expect(session.transitions.transitionSpanStartShownInCutAt(25), 42);
    });

    test('🚨a drag\'s preview is laid on the same frames', () {
      final session = withAFadeInsideB();
      final row = session.activeTrack.transitionLayer;

      final preview = session.transitions.previewFormsOf(row);

      expect(lengthsOf(preview.shown), {0: 12, 24: 6});
      expect(preview.global, same(row));
    });

    test('🚨a span made from the cut view starts on the track\'s frame its '
        'first cell plays at', () {
      final session = sessionOf()..selectCut(b);
      // Nothing selected: one frame at the playhead — the first frame past
      // the O.L, free on the track's row and on the cut's.
      session.selectFrameIndex(12);
      expect(
        session.transitions.transitionSpanCreationInCutOrNull,
        (startFrame: 30, length: 1),
      );

      session.updateFrameRangeSelectionDrag(
        layerId: session.activeTrack.transitionLayer.id,
        anchorIndex: 14,
        headIndex: 19,
      );
      expect(
        session.transitions.transitionSpanCreationOrNull,
        (startFrame: 32, length: 6),
      );
    });

    // ⚠️Board `I-73-ol-sheet-columns`: the sheet's cel columns are the
    // cut's own frames, so in a cut an O.L arrives into these two stand
    // the のりしろ above the pictures they go with. They are counted the
    // same way as each other, which this keeps until the sheet is put
    // right as one.
    test('the SHEET still counts its track-owned columns from the cut\'s '
        'place — both the same way', () {
      final session = withAFadeInsideB();
      final track = session.repository.requireProject().tracks.single;

      expect(
        lengthsOf(
          session.transitions.trackTransitionSheetLayerFor(
            cutStart: 24,
            duration: 24,
            olWord: 'O.L',
          ),
        ),
        {0: 12, 18: 6},
      );
      final sounds = SheetSources.of(
        cut: track.cuts[1],
        trackSeLayers: track.seLayers,
        cutStartFrame: 24,
      ).seLayers.single.layer;
      expect(
        {
          for (final entry in sounds.timeline.entries)
            entry.key: entry.value.length,
        },
        {6: 4},
      );
    });
  });

  group('the name tags a frame of the cut puts on the canvas', () {
    /// Four speakers on the S row, named by where they speak: inside a
    /// over [20, 22) — the overlap — on a's last frame, on b's first, and
    /// inside b over [30, 34).
    EditorSessionManager withSpeakers() {
      final session = sessionOf();
      const spoken = {
        'in-a': (20, 2),
        'a-last': (23, 1),
        'b-first': (24, 1),
        'in-b': (30, 4),
      };
      session.repository.replaceLayer(
        layer: soundRow(session).copyWith(
          frames: [
            for (final name in spoken.keys)
              Frame(
                id: FrameId(name),
                duration: 1,
                strokes: const [],
                seName: name,
              ),
          ],
          timeline: {
            for (final MapEntry(key: name, value: (start, length))
                in spoken.entries)
              start: TimelineExposure.drawing(FrameId(name), length: length),
          },
        ),
      );
      return session;
    }

    List<String> tagsAt(EditorSessionManager session, CutId cutId, int own) {
      final cut = session.repository
          .requireProject()
          .tracks
          .single
          .cuts
          .firstWhere((cut) => cut.id == cutId);
      return [
        for (final tag in session.seEntries.seNameTagsForCutFrame(cut, own))
          tag.content.text,
      ];
    }

    test('🚨are those of the track\'s frame it plays at', () {
      final session = withSpeakers();

      expect(tagsAt(session, b, 6), ['b-first']);
      expect(tagsAt(session, b, 11), isEmpty);
      expect(tagsAt(session, b, 12), ['in-b']);
      expect(tagsAt(session, b, 15), ['in-b']);
      expect(tagsAt(session, b, 16), isEmpty);
      expect(tagsAt(session, a, 20), ['in-a']);
      expect(tagsAt(session, a, 23), ['a-last']);
    });

    test('a frame outside the cut\'s place is held to the cut: past its '
        'end on its last frame, in the のりしろ before its conte on its '
        'first', () {
      final session = withSpeakers();

      expect(tagsAt(session, a, 26), ['a-last']);
      expect(tagsAt(session, a, 400), ['a-last']);
      expect(
        tagsAt(session, b, 2),
        ['b-first'],
        reason: 'the track\'s 20 is a\'s — its speaker is not put over '
            'this picture',
      );
    });

    test('a cut no track holds puts none', () {
      final session = withSpeakers();

      expect(
        session.seEntries.seNameTagsForCutFrame(cut('elsewhere'), 6),
        isEmpty,
      );
    });
  });

  test('🚨the fade on the editing canvas is the one over the frame that '
      'plays', () {
    final session = sessionOf()..selectCut(b);
    double rampAt(int trackFrame) => cutTransitionRampAt(
      cutStart: 24,
      cutEnd: 48,
      spans: session.transitions.activeTrackTransitionSpans,
      globalFrame: trackFrame,
    );
    expect(
      rampAt(24),
      allOf(greaterThan(rampAt(18)), lessThan(1)),
      reason: 'fixture: mid-dissolve at the cut\'s place',
    );
    final fade = session.opacityVerbs.activeCutEditingFadeOpacity;

    expect(fade(frameIndex: 0), rampAt(18));
    expect(fade(frameIndex: 6), rampAt(24));
    expect(fade(frameIndex: 12), 1);
  });

  group('the conte panel under the cursor', () {
    final conteRow = LayerRowAddress(trackConteRowId(trackId));

    StoryboardCursorStoryboardPanel panelUnder(EditorSessionManager session) =>
        session.storyboardCursor.storyboardCursorBlockOrNull()!
            as StoryboardCursorStoryboardPanel;

    // b's panels are its own [6, 18) and [18, 30). The frames asked here
    // are within a のりしろ of the second panel's start, so a reader that
    // counts the margin twice names the wrong one.
    test('🚨from the storyboard: the panel under the track\'s frame', () {
      final session = sessionOf();
      session.standOnRow(
        conteRow,
        panel: WorkingPanel.storyboard,
        globalFrameIndex: 32,
      );

      expect(session.currentFrameIndex, 14);
      expect(panelUnder(session).panelStartIndex, 6);

      session.standOnRow(
        conteRow,
        panel: WorkingPanel.storyboard,
        globalFrameIndex: 38,
      );
      expect(panelUnder(session).panelStartIndex, 18);
    });

    test('🚨and the same panel when the timeline put the cursor there', () {
      final session = sessionOf()..selectCut(b);
      session.standOnRow(const LayerRowAddress(LayerId('sb-b')));
      session.selectFrameIndex(14);
      session.standOnRow(conteRow, panel: WorkingPanel.storyboard);

      expect(session.currentFrameIndex, 14, reason: 'fixture');
      expect(panelUnder(session).panelStartIndex, 6);
    });
  });

  group('while the track plays', () {
    test('🚨the cut\'s cursor is on the frame the picture is: its own', () {
      final session = sessionOf();
      session.playbackRig.playback.play(
        scope: PlaybackScope.allCuts,
        startGlobalFrame: 30,
      );
      addTearDown(session.playbackRig.playback.stop);

      expect(session.playbackRig.playback.position?.cutId, b, reason: 'fix');
      expect(session.playheadCursors.cutFrameNow(), 12);
      expect(session.playheadCursors.trackFrameNow(), 30);
      expect(session.cutUnderPlayhead.localFrame, 12);
      final shown = session.cutUnderPlayhead.resolve()!;
      expect((shown.cut.id, shown.startFrame, shown.localFrame), (b, 24, 12));
    });

    test('🚨the follow seats the cut it crosses into on that frame', () {
      final session = sessionOf()..selectCut(a);
      final playback = session.playbackRig.playback;
      playback.play(scope: PlaybackScope.allCuts, startGlobalFrame: 20);
      addTearDown(playback.stop);
      expect(playback.position?.cutId, a, reason: 'fixture: the overlap');

      playback.seekToGlobalFrame(30);
      session.followPlaybackCut();

      expect((session.activeCutId, session.currentFrameIndex), (b, 12));
    });

    test('🚨and a stop lands on that frame', () async {
      final session = sessionOf();
      session.playbackRig.playback.play(
        scope: PlaybackScope.allCuts,
        startGlobalFrame: 30,
      );

      session.playbackRig.playback.stop();
      await Future<void>.delayed(Duration.zero);

      expect(session.activeCutId, b);
      expect(session.currentFrameIndex, 12);
      expect(session.editingGlobalFrame, 30);
    });
  });

  group('a cut played alone counts its own frames already', () {
    test('its cursor, and where the storyboard shows it', () {
      final session = sessionOf()..selectCut(b);
      session.playbackRig.playback.play(
        scope: PlaybackScope.activeCut,
        startGlobalFrame: 12,
      );
      addTearDown(session.playbackRig.playback.stop);

      expect(session.playheadCursors.cutFrameNow(), 12);
      expect(session.cutUnderPlayhead.localFrame, 12);
      expect(
        session.playheadCursors.trackFrameNow(),
        30,
        reason: 'shown where the storyboard shows the cut\'s frame',
      );

      // Its のりしろ plays first — shown on the cut's own block, where the
      // storyboard holds the editing playhead too.
      session.playbackRig.playback.seekToGlobalFrame(2);
      expect(session.playheadCursors.cutFrameNow(), 2);
      expect(session.playheadCursors.trackFrameNow(), 24);
    });

    test('its stop', () async {
      final session = sessionOf()..selectCut(b);
      session.playbackRig.playback.play(
        scope: PlaybackScope.activeCut,
        startGlobalFrame: 12,
      );

      session.playbackRig.playback.stop();
      await Future<void>.delayed(Duration.zero);

      expect((session.activeCutId, session.currentFrameIndex), (b, 12));
    });

    test('🚨and a press on the storyboard\'s ruler seeks it to the frame of '
        'its own that plays under the press', () {
      final session = sessionOf()..selectCut(b);
      final playback = session.playbackRig.playback;
      playback.play(scope: PlaybackScope.activeCut);
      addTearDown(playback.stop);

      seekStoryboardGlobalFrame(session, 30);

      expect(playback.playlistFrame, 12);
      expect(session.playheadCursors.trackFrameNow(), 30);
    });
  });

  testWidgets('🚨the storyboard\'s ready bar asks a cut for its OWN frames: '
      'a cel not yet baked shows where it plays', (tester) async {
    Cut bare(String id, {List<Layer> layers = const []}) => Cut(
      id: CutId(id),
      name: id,
      duration: 24,
      canvasSize: const CanvasSize(width: 8, height: 8),
      layers: layers,
    );
    // Nothing to compose in a; in b one cel over its own [8, 10) and
    // [26, 28) — the track's [26, 28) and [44, 46): b's own frames stand
    // six before its place, to its end.
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('ready'),
        name: 'Ready',
        createdAt: DateTime.utc(2026, 10, 8),
        tracks: [
          Track(
            id: trackId,
            name: 'V1',
            cuts: [
              bare('a'),
              bare(
                'b',
                layers: [
                  Layer(
                    id: const LayerId('cel'),
                    name: 'A',
                    frames: [
                      Frame(
                        id: const FrameId('drawn'),
                        duration: 1,
                        strokes: const [],
                      ),
                    ],
                    timeline: const {
                      8: TimelineExposure.drawing(FrameId('drawn'), length: 2),
                      26: TimelineExposure.drawing(FrameId('drawn'), length: 2),
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    session.transitions.updateTransitionInstructions({18: ol});

    expect(storyboardReadyRuns(session, 0, 48), [
      (startIndex: 0, endIndexExclusive: 26),
      (startIndex: 28, endIndexExclusive: 44),
      (startIndex: 46, endIndexExclusive: 48),
    ]);
  });
}
