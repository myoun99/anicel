import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_cut_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/export/export_plan.dart';
import 'package:anicel/src/ui/playback/audio_playback_schedule.dart';

void main() {
  Frame frame(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const []);

  Layer layer(
    String id, {
    String name = 'A',
    List<Frame> frames = const [],
    bool isVisible = true,
  }) =>
      Layer(id: LayerId(id), name: name, frames: frames, isVisible: isVisible);

  Cut cut(
    String id, {
    String name = 'Cut',
    int duration = 3,
    List<Layer>? layers,
  }) => Cut(
    id: CutId(id),
    name: name,
    duration: duration,
    canvasSize: const CanvasSize(width: 8, height: 8),
    layers: layers ?? [layer('$id-layer'), createCameraLayer(cutId: CutId(id))],
  );

  Project project(List<Track> tracks) => Project(
    id: const ProjectId('project'),
    name: 'Project',
    cameraSize: const CanvasSize(width: 32, height: 18),
    tracks: tracks,
    createdAt: DateTime.utc(2026),
  );

  group('buildExportFramePlan', () {
    test('active cut covers exactly its frames', () {
      final plan = buildExportFramePlan(
        project: project([
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [cut('a', duration: 2), cut('b', duration: 3)],
          ),
        ]),
        activeCutId: const CutId('a'),
        range: ExportRange.activeCut,
      );

      expect(plan, hasLength(2));
      expect(plan.map((task) => task.cut.id.value), everyElement('a'));
      expect(plan.map((task) => task.frameIndex), [0, 1]);
    });

    test("all cuts walks the active cut's track in order, other tracks "
        'excluded', () {
      final plan = buildExportFramePlan(
        project: project([
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [cut('a', duration: 2), cut('b', duration: 3)],
          ),
          Track(
            id: const TrackId('other'),
            name: 'Other',
            cuts: [cut('c', duration: 10)],
          ),
        ]),
        activeCutId: const CutId('b'),
        range: ExportRange.allCuts,
      );

      expect(plan, hasLength(5));
      expect(plan.map((task) => task.cut.id.value), ['a', 'a', 'b', 'b', 'b']);
      expect(plan.map((task) => task.frameIndex), [0, 1, 0, 1, 2]);
    });

    test('frame range is 0-based inclusive and clamps to the cut', () {
      final tracks = [
        Track(
          id: const TrackId('track'),
          name: 'Track',
          cuts: [cut('a', duration: 5)],
        ),
      ];

      final inner = buildExportFramePlan(
        project: project(tracks),
        activeCutId: const CutId('a'),
        range: ExportRange.frameRange,
        rangeStartFrame: 1,
        rangeEndFrame: 3,
      );
      expect(inner.map((task) => task.frameIndex), [1, 2, 3]);

      final clamped = buildExportFramePlan(
        project: project(tracks),
        activeCutId: const CutId('a'),
        range: ExportRange.frameRange,
        rangeStartFrame: -2,
        rangeEndFrame: 99,
      );
      expect(clamped.map((task) => task.frameIndex), [0, 1, 2, 3, 4]);
    });

    test('includeGaps adds black-frame tasks (negative indexes) so video '
        'matches all-cuts playback; the default and single-cut ranges skip '
        'them', () {
      final tracks = [
        Track(
          id: const TrackId('track'),
          name: 'Track',
          cuts: [
            cut('a', duration: 2),
            cut('b', duration: 3).copyWith(leadingGapFrames: 2),
          ],
        ),
      ];

      final video = buildExportFramePlan(
        project: project(tracks),
        activeCutId: const CutId('a'),
        range: ExportRange.allCuts,
        includeGaps: true,
      );
      expect(video.map((task) => task.frameIndex), [0, 1, -2, -1, 0, 1, 2]);
      expect(video.map((task) => task.cut.id.value), [
        'a', 'a', 'b', 'b', 'b', 'b', 'b', //
      ]);
      expect(video.where((task) => task.isGap), hasLength(2));

      // The default (PNG sequences) collapses the gap.
      final png = buildExportFramePlan(
        project: project(tracks),
        activeCutId: const CutId('a'),
        range: ExportRange.allCuts,
      );
      expect(png.map((task) => task.frameIndex), [0, 1, 0, 1, 2]);

      // A single-cut range never plays its leading gap, so it never
      // exports one either.
      final single = buildExportFramePlan(
        project: project(tracks),
        activeCutId: const CutId('b'),
        range: ExportRange.activeCut,
        includeGaps: true,
      );
      expect(single.map((task) => task.frameIndex), [0, 1, 2]);
    });

    test('a zero-duration cut still exports one frame (playback floor)', () {
      final plan = buildExportFramePlan(
        project: project([
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [cut('a', duration: 0)],
          ),
        ]),
        activeCutId: const CutId('a'),
        range: ExportRange.activeCut,
      );

      expect(plan.map((task) => task.frameIndex), [0]);
    });
  });

  group('buildExportCelPlan', () {
    test('lists each authored frame of visible drawing layers once, '
        'skipping camera and hidden layers', () {
      final plan = buildExportCelPlan(
        project: project([
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [
              cut(
                'a',
                name: 'Cut',
                layers: [
                  layer('draw', name: 'A', frames: [frame('f1'), frame('f2')]),
                  layer(
                    'hidden',
                    name: 'H',
                    frames: [frame('f3')],
                    isVisible: false,
                  ),
                  createCameraLayer(cutId: const CutId('a')),
                ],
              ),
            ],
          ),
        ]),
        activeCutId: const CutId('a'),
        range: ExportRange.activeCut,
      );

      expect(plan, hasLength(2));
      expect(plan.map((task) => task.frame.id.value), ['f1', 'f2']);
      // Default naming: layer name + frame name (position fallback when the
      // frame is unnamed).
      expect(plan.map((task) => task.fileName), ['A1.png', 'A2.png']);
    });

    test('onTimesheetOnly keeps only layers marked for the sheet', () {
      final tracks = [
        Track(
          id: const TrackId('track'),
          name: 'Track',
          cuts: [
            cut(
              'a',
              layers: [
                layer('on-sheet', name: 'A', frames: [frame('f1')]),
                layer(
                  'off-sheet',
                  name: 'B',
                  frames: [frame('f2')],
                ).copyWith(onTimesheet: false),
              ],
            ),
          ],
        ),
      ];

      final all = buildExportCelPlan(
        project: project(tracks),
        activeCutId: const CutId('a'),
        range: ExportRange.activeCut,
      );
      expect(all.map((task) => task.layer.name), ['A', 'B']);

      final sheetOnly = buildExportCelPlan(
        project: project(tracks),
        activeCutId: const CutId('a'),
        range: ExportRange.activeCut,
        onTimesheetOnly: true,
      );
      expect(sheetOnly.map((task) => task.layer.name), ['A']);
    });

    test('frame range covers the whole active cut for cels', () {
      final plan = buildExportCelPlan(
        project: project([
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [
              cut(
                'a',
                layers: [
                  layer('draw', frames: [frame('f1'), frame('f2')]),
                  createCameraLayer(cutId: const CutId('a')),
                ],
              ),
            ],
          ),
        ]),
        activeCutId: const CutId('a'),
        range: ExportRange.frameRange,
      );

      expect(plan, hasLength(2));
    });

    test('duplicate cut/layer names bump the file name instead of '
        'colliding', () {
      final plan = buildExportCelPlan(
        project: project([
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [
              cut(
                'a',
                name: 'Cut',
                layers: [
                  layer('one', name: 'A', frames: [frame('f1')]),
                  layer('two', name: 'A', frames: [frame('f2')]),
                ],
              ),
            ],
          ),
        ]),
        activeCutId: const CutId('a'),
        range: ExportRange.activeCut,
      );

      expect(plan.map((task) => task.fileName), ['A1.png', 'A1_2.png']);
    });

    test('naming options assemble project/cut prefixes, digits, suffix and '
        'folders', () {
      final tracks = [
        Track(
          id: const TrackId('track'),
          name: 'Track',
          cuts: [
            cut(
              'a',
              name: 'C01',
              layers: [
                layer(
                  'draw',
                  name: 'A',
                  frames: [
                    Frame(
                      id: const FrameId('f1'),
                      duration: 1,
                      strokes: const [],
                      name: '3',
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ];

      List<String> namesFor(ExportCelNaming naming) => buildExportCelPlan(
        project: project(tracks),
        activeCutId: const CutId('a'),
        range: ExportRange.activeCut,
        naming: naming,
      ).map((task) => task.fileName).toList();

      expect(
        namesFor(
          const ExportCelNaming(
            includeProjectName: true,
            includeCutName: true,
            frameDigits: 4,
          ),
        ),
        ['Project_C01_A0003.png'],
      );
      expect(namesFor(const ExportCelNaming(includeLayerName: false)), [
        '3.png',
      ]);
      expect(namesFor(const ExportCelNaming(suffix: '_fix')), ['A3_fix.png']);
      expect(
        namesFor(const ExportCelNaming(cutFolder: true, layerFolder: true)),
        ['C01/A/A3.png'],
      );
    });
  });

  group('padFrameNumber', () {
    test('pads the first digit run and leaves the rest alone', () {
      expect(padFrameNumber('1', 4), '0001');
      expect(padFrameNumber('12', 3), '012');
      expect(padFrameNumber('a12b', 4), 'a0012b');
      expect(padFrameNumber('1234', 4), '1234');
      expect(padFrameNumber('12345', 4), '12345');
      expect(padFrameNumber('abc', 4), 'abc');
      expect(padFrameNumber('1', 0), '1');
    });
  });

  group('sanitizeExportFileComponent', () {
    test('replaces characters Windows forbids and trims trailing dots', () {
      expect(sanitizeExportFileComponent('Cut: 1?'), 'Cut_ 1_');
      expect(sanitizeExportFileComponent(r'a\b/c'), 'a_b_c');
      expect(sanitizeExportFileComponent('name...'), 'name');
      expect(sanitizeExportFileComponent('   '), 'untitled');
      expect(sanitizeExportFileComponent(''), 'untitled');
    });
  });

  group('buildExportAudioPlan', () {
    // Frame-linked sounds: one SE layer per sound, its block = the window.
    Layer seLayer(
      String id, {
      required String file,
      required int start,
      required int length,
    }) => Layer(
      id: LayerId(id),
      name: 'S1',
      kind: LayerKind.se,
      frames: [Frame(id: FrameId('$id-frame'), duration: 1, strokes: const [])],
      timeline: {
        start: TimelineExposure.drawing(FrameId('$id-frame'), length: length),
      },
      audioClips: [AudioClip(filePath: file, frameId: FrameId('$id-frame'))],
    );

    // The plan is pure frames now (the mix renderer does the one sample
    // conversion). Cut a: 10 frames, blocks at 0 (full cut) and 6..10.
    // Cut b: 20 frames, block at local 3 (global 13 in all-cuts order)
    // running to the cut end.
    Cut cutA() => cut(
      'a',
      duration: 10,
      layers: [
        seLayer('se-a1', file: 'a.wav', start: 0, length: 10),
        seLayer('se-a2', file: 'b.wav', start: 6, length: 4),
      ],
    );
    Cut cutB() => cut(
      'b',
      duration: 20,
      layers: [seLayer('se-b', file: 'c.wav', start: 3, length: 17)],
    );

    test('muted SE layers contribute no clips (the mute speaker silences '
        'export like playback)', () {
      final cutWithMuted = cut(
        'a',
        duration: 10,
        layers: [
          seLayer(
            'se-a1',
            file: 'a.wav',
            start: 0,
            length: 10,
          ).copyWith(muted: true),
          seLayer('se-a2', file: 'b.wav', start: 6, length: 4),
        ],
      );
      final plan = buildExportFramePlan(
        project: project([
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [cutWithMuted],
          ),
        ]),
        activeCutId: const CutId('a'),
        range: ExportRange.activeCut,
      );

      final clips = buildExportAudioPlan(plan: plan);

      expect(clips.map((clip) => clip.filePath), ['b.wav']);
    });

    test('all-cuts export lays clips globally, capped at their cut blocks', () {
      final plan = buildExportFramePlan(
        project: project([
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [cutA(), cutB()],
          ),
        ]),
        activeCutId: const CutId('a'),
        range: ExportRange.allCuts,
      );

      final clips = buildExportAudioPlan(plan: plan);

      expect(clips, const [
        // a.wav fills its whole cut.
        ScheduledAudioClip(filePath: 'a.wav', startFrame: 0, endFrameExclusive: 10),
        // b.wav starts at frame 6 and caps at cut a's end (frame 10).
        ScheduledAudioClip(filePath: 'b.wav', startFrame: 6, endFrameExclusive: 10),
        // c.wav sits at global frame 13 (cut b local 3) and never bleeds
        // past cut b.
        ScheduledAudioClip(filePath: 'c.wav', startFrame: 13, endFrameExclusive: 30),
      ]);
    });

    test('a frame-range export seeks into clips that started earlier and '
        'drops clips past the range', () {
      final plan = buildExportFramePlan(
        project: project([
          Track(id: const TrackId('track'), name: 'Track', cuts: [cutA()]),
        ]),
        activeCutId: const CutId('a'),
        range: ExportRange.frameRange,
        rangeStartFrame: 4,
        rangeEndFrame: 5,
      );

      final clips = buildExportAudioPlan(plan: plan);

      expect(clips, const [
        // a.wav began 4 frames before the range: the trim seeks 4 frames
        // into the source; it plays from the export's frame 0 for the
        // 2-frame range.
        ScheduledAudioClip(
          filePath: 'a.wav',
          startFrame: 0,
          endFrameExclusive: 2,
          offsetFrames: 4,
        ),
        // b.wav (frame 6) starts after the exported range ends → silent.
      ]);
    });

    test('a clip offset trim adds to the source seek on top of range '
        'clipping', () {
      final trimmedCut = cut(
        'a',
        duration: 10,
        layers: [
          seLayer('se-a1', file: 'a.wav', start: 2, length: 8).copyWith(
            audioClips: const [
              AudioClip(
                filePath: 'a.wav',
                frameId: FrameId('se-a1-frame'),
                offsetFrames: 5,
              ),
            ],
          ),
        ],
      );
      final fullPlan = buildExportFramePlan(
        project: project([
          Track(id: const TrackId('track'), name: 'Track', cuts: [trimmedCut]),
        ]),
        activeCutId: const CutId('a'),
        range: ExportRange.allCuts,
      );

      expect(buildExportAudioPlan(plan: fullPlan), const [
        // The block starts at frame 2 with a 5-frame trim: the source is
        // seeked 5 frames in, the placement stays the block's position.
        ScheduledAudioClip(
          filePath: 'a.wav',
          startFrame: 2,
          endFrameExclusive: 10,
          offsetFrames: 5,
        ),
      ]);

      // Range clipping compounds with the trim.
      final rangedPlan = buildExportFramePlan(
        project: project([
          Track(id: const TrackId('track'), name: 'Track', cuts: [trimmedCut]),
        ]),
        activeCutId: const CutId('a'),
        range: ExportRange.frameRange,
        rangeStartFrame: 4,
        rangeEndFrame: 7,
      );

      expect(buildExportAudioPlan(plan: rangedPlan), const [
        // 2 frames of the block precede the range + the 5-frame trim.
        ScheduledAudioClip(
          filePath: 'a.wav',
          startFrame: 0,
          endFrameExclusive: 4,
          offsetFrames: 7,
        ),
      ]);
    });

    test('track-owned SE sounds run THROUGH exported gap frames and '
        're-clamp when the plan collapses the gap', () {
      // Track: cut a (10 frames) + cut b (20 frames, 5-frame leading gap →
      // gap = track frames 10..14). Track SE rows on the global axis:
      // g.wav spans [8, 18) across the gap; h.wav starts INSIDE it at 12.
      final proj = project([
        Track(
          id: const TrackId('track'),
          name: 'Track',
          seLayers: [
            seLayer('se-g', file: 'g.wav', start: 8, length: 10),
            seLayer('se-h', file: 'h.wav', start: 12, length: 5),
          ],
          cuts: [
            cut('a', duration: 10),
            cut('b', duration: 20).copyWith(leadingGapFrames: 5),
          ],
        ),
      ]);

      // Video plan (gaps exported as black): the track axis and the export
      // axis stay in lockstep — sounds keep running through the gap, and a
      // gap-starting sound lands on its exact frame.
      final videoPlan = buildExportFramePlan(
        project: proj,
        activeCutId: const CutId('a'),
        range: ExportRange.allCuts,
        includeGaps: true,
      );
      expect(
        buildExportAudioPlan(plan: videoPlan, project: proj),
        const [
          ScheduledAudioClip(
            filePath: 'g.wav',
            startFrame: 8,
            endFrameExclusive: 18,
          ),
          ScheduledAudioClip(
            filePath: 'h.wav',
            startFrame: 12,
            endFrameExclusive: 17,
          ),
        ],
      );

      // A gap-skipping plan collapses the timeline: the run breaks at the
      // gap, sounds re-sync to the track axis on the far side (seek bumps)
      // and the purely-in-gap stretch goes silent.
      final collapsedPlan = buildExportFramePlan(
        project: proj,
        activeCutId: const CutId('a'),
        range: ExportRange.allCuts,
      );
      expect(
        buildExportAudioPlan(plan: collapsedPlan, project: proj),
        const [
          ScheduledAudioClip(
            filePath: 'g.wav',
            startFrame: 8,
            endFrameExclusive: 10,
          ),
          ScheduledAudioClip(
            filePath: 'g.wav',
            startFrame: 10,
            endFrameExclusive: 13,
            offsetFrames: 7,
          ),
          ScheduledAudioClip(
            filePath: 'h.wav',
            startFrame: 10,
            endFrameExclusive: 12,
            offsetFrames: 3,
          ),
        ],
      );
    });

    test('gain and fades land on the plan; a range starting mid-fade keeps '
        'the fade-in remainder', () {
      final shapedCut = cut(
        'a',
        duration: 10,
        layers: [
          seLayer('se-a1', file: 'a.wav', start: 2, length: 8).copyWith(
            audioClips: const [
              AudioClip(
                filePath: 'a.wav',
                frameId: FrameId('se-a1-frame'),
                gain: 1.5,
                fadeInFrames: 4,
                fadeOutFrames: 2,
              ),
            ],
          ),
        ],
      );

      final fullPlan = buildExportFramePlan(
        project: project([
          Track(id: const TrackId('track'), name: 'Track', cuts: [shapedCut]),
        ]),
        activeCutId: const CutId('a'),
        range: ExportRange.allCuts,
      );
      expect(buildExportAudioPlan(plan: fullPlan), const [
        ScheduledAudioClip(
          filePath: 'a.wav',
          startFrame: 2,
          endFrameExclusive: 10,
          gain: 1.5,
          fadeInFrames: 4,
          fadeOutFrames: 2,
        ),
      ]);

      // Frames 4..9: the range trims 2 of the 4 fade-in frames — the
      // remainder ramps from the trimmed start; the fade-out anchors to
      // the audible end as before.
      final rangedPlan = buildExportFramePlan(
        project: project([
          Track(id: const TrackId('track'), name: 'Track', cuts: [shapedCut]),
        ]),
        activeCutId: const CutId('a'),
        range: ExportRange.frameRange,
        rangeStartFrame: 4,
        rangeEndFrame: 9,
      );
      expect(buildExportAudioPlan(plan: rangedPlan), const [
        ScheduledAudioClip(
          filePath: 'a.wav',
          startFrame: 0,
          endFrameExclusive: 6,
          offsetFrames: 2,
          gain: 1.5,
          fadeInFrames: 2,
          fadeOutFrames: 2,
        ),
      ]);
    });
  });
}
