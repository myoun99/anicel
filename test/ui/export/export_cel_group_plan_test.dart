import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_overrides.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/export_cel_naming.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/export/export_cel_group_plan.dart';

void main() {
  const key = LayerMark(process: LayerProcess.key);
  const layout = LayerMark(process: LayerProcess.layout);
  const paper = LayerMark(process: LayerProcess.paper);
  const art = LayerMark(process: LayerProcess.art);
  // 디렉션 alone: the drawing filters off, the direction rows added.
  const direction = CelsExportSpec(
    base: false,
    attach: false,
    addDirection: true,
  );
  // 부속 alone: the base filter off — the base still numbers the cels.
  const attach = CelsExportSpec(base: false);

  // A cel carries its number as the frame name; an unnamed frame is the
  // in-between mark and exports nothing. The fixture ids' digits double as
  // the cel number ('f1' → '1') unless a test names the frame itself, and
  // `unnamed: true` builds the mark on purpose.
  Frame frame(String id, {String? name, bool unnamed = false}) => Frame(
    id: FrameId(id),
    duration: 1,
    strokes: const [],
    name: unnamed ? null : (name ?? id.replaceAll(RegExp('[^0-9]'), '')),
  );

  /// Each frame exposed once, in order, from frame 0.
  Map<int, TimelineExposure> exposed(List<Frame> frames) => {
    for (var i = 0; i < frames.length; i += 1)
      i: TimelineExposure.drawing(frames[i].id, length: 1),
  };

  Layer base(
    String id,
    String name,
    List<Frame> frames, {
    LayerMark mark = key,
    bool timeline = false,
  }) => Layer(
    id: LayerId(id),
    name: name,
    frames: frames,
    mark: mark,
    timeline: timeline ? exposed(frames) : const {},
  );

  Project projectWith(List<Layer> layers, {CameraInstructionSet? defs}) =>
      Project(
        id: const ProjectId('project'),
        name: 'Project',
        cameraInstructions: defs,
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [
              Cut(
                id: const CutId('cut'),
                name: 'CUT1',
                duration: 4,
                canvasSize: const CanvasSize(width: 8, height: 8),
                layers: [
                  ...layers,
                  createCameraLayer(cutId: const CutId('cut')),
                ],
              ),
            ],
          ),
        ],
        createdAt: DateTime.utc(2026),
      );

  ExportCelGroupPlan plan(
    List<Layer> layers, {
    CelsExportSpec spec = const CelsExportSpec(),
    ExportProjectOverrides? overrides,
  }) => buildExportCelGroupPlan(
    project: projectWith(layers),
    activeCutId: const CutId('cut'),
    spec: spec,
    overrides: overrides,
  );

  List<String> names(Iterable<Layer> layers) => [
    for (final layer in layers) layer.name,
  ];

  List<String> files(ExportCelGroupPlan plan) => [
    for (final task in plan.cels) task.fileName,
  ];

  Layer instructionRow({String id = 'inst', String name = 'Camera'}) => Layer(
    id: LayerId(id),
    name: name,
    frames: const [],
    kind: LayerKind.instruction,
    instructions: {
      0: const InstructionEvent(instructionId: 'pan', length: 12, text: 'PAN'),
    },
  );

  test('a bundle composites its synced riders through the cell links', () {
    final sync = Layer(
      id: const LayerId('a-color'),
      name: 'A색',
      frames: [frame('c1'), frame('c2')],
      mark: key,
      attachedToLayerId: const LayerId('a'),
      attachedMode: AttachedMode.synced,
      baseFrameLinks: {
        const FrameId('f1'): const FrameId('c1'),
        const FrameId('f2'): const FrameId('c2'),
      },
    );
    final built = plan([base('a', 'A', [frame('f1'), frame('f2')]), sync]);

    expect(built.cels, hasLength(2));
    final first = built.cels.first;
    expect(names(first.members), ['A', 'A색']);
    expect(first.memberFrames.map((frame) => frame?.id.value), ['f1', 'c1']);
    expect(first.fileName, 'A1.png');
    expect(built.cels.last.memberFrames.last?.id.value, 'c2');
    expect(built.bundles.single.axis.name, 'A');
    expect(built.bundles.single.sheets, hasLength(2));
  });

  test('a rider wearing another label is not in the bundle; the delta puts '
      'it back', () {
    final sync = Layer(
      id: const LayerId('a-color'),
      name: 'A색',
      frames: [frame('c1')],
      mark: layout,
      attachedToLayerId: const LayerId('a'),
      attachedMode: AttachedMode.synced,
      baseFrameLinks: {const FrameId('f1'): const FrameId('c1')},
    );
    final layers = [base('a', 'A', [frame('f1')]), sync];

    expect(names(plan(layers).cels.single.members), ['A']);
    final restored = plan(
      layers,
      overrides: ExportProjectOverrides().withCelsDelta(
        const CutId('cut'),
        ExportCelsCutDelta().withLayerOverride(const LayerId('a-color'), true),
      ),
    );
    expect(names(restored.cels.single.members), ['A', 'A색']);
  });

  test('a FREE rider maps through what it exposes at the axis cel', () {
    final baseA = Layer(
      id: const LayerId('a'),
      name: 'A',
      frames: [frame('f1'), frame('f2')],
      mark: key,
      timeline: {
        0: const TimelineExposure.drawing(FrameId('f1'), length: 2),
        2: const TimelineExposure.drawing(FrameId('f2'), length: 2),
      },
    );
    final free = Layer(
      id: const LayerId('shadow'),
      name: 'Ashadow',
      frames: [frame('s1'), frame('s2')],
      mark: key,
      attachedToLayerId: const LayerId('a'),
      attachedMode: AttachedMode.free,
      timeline: {
        0: const TimelineExposure.drawing(FrameId('s1'), length: 3),
        3: const TimelineExposure.drawing(FrameId('s2'), length: 1),
      },
    );
    final built = plan([baseA, free]);
    // Base cel f1 first shows at 0 → the free row exposes s1 there; f2
    // first shows at 2 → still s1 (its own block runs to 3).
    expect(built.cels[0].memberFrames.last?.id.value, 's1');
    expect(built.cels[1].memberFrames.last?.id.value, 's1');
  });

  test('부속: the base off and a rider on still numbers by the BASE — and '
      'only the cels the rider has a picture for are planned', () {
    // 유저 2026-09-09: 「기준레이어 출력off라면 … 기준레이어의 프레임을 기준으로
    // 생각하되, 그림이 존재하는 영역만 출력」.
    final baseA = base('a', 'A', [frame('f1'), frame('f2'), frame('f3')]);
    final sync = Layer(
      id: const LayerId('a-color'),
      name: 'A색',
      frames: [frame('c1'), frame('c3')],
      mark: key,
      attachedToLayerId: const LayerId('a'),
      attachedMode: AttachedMode.synced,
      baseFrameLinks: {
        const FrameId('f1'): const FrameId('c1'),
        const FrameId('f3'): const FrameId('c3'),
      },
    );
    final built = plan([baseA, sync], spec: attach);

    expect(built.cels.map((task) => task.celName), ['1', '3']);
    expect(built.cels.first.baseLayer.name, 'A');
    expect(names(built.cels.first.members), ['A색']);
    expect(files(built), ['A1.png', 'A3.png']);
  });

  test('a FREE rider alone in its bundle is its own axis: its frames, its '
      'name', () {
    // 유저 2026-09-09: 「여러개 선택되면 기준레이어 따라가고 프리부속 단독이면
    // 단독 기준」.
    final baseA = base('a', 'A', [frame('f1'), frame('f2')], timeline: true);
    final free = Layer(
      id: const LayerId('shadow'),
      name: 'Ashadow',
      frames: [frame('s1'), frame('s2')],
      mark: key,
      attachedToLayerId: const LayerId('a'),
      attachedMode: AttachedMode.free,
      timeline: {
        0: const TimelineExposure.drawing(FrameId('s1'), length: 2),
        2: const TimelineExposure.drawing(FrameId('s2'), length: 2),
      },
    );

    final alone = plan([baseA, free], spec: attach);
    expect(alone.cels.map((task) => task.baseLayer.name).toSet(), {'Ashadow'});
    expect(files(alone), ['Ashadow1.png', 'Ashadow2.png']);
    expect(names(alone.cels.first.members), ['Ashadow']);

    // With the base on too, the base is the axis again.
    final together = plan([baseA, free]);
    expect(together.cels.map((task) => task.baseLayer.name).toSet(), {'A'});
    expect(files(together), ['A1.png', 'A2.png']);
  });

  test('paper rides every cel and is never a bundle of its own', () {
    final paperRow = Layer(
      id: const LayerId('p'),
      name: 'Paper',
      frames: [frame('p1')],
      mark: paper,
      timeline: {0: const TimelineExposure.drawing(FrameId('p1'), length: 4)},
    );
    final baseA = Layer(
      id: const LayerId('a'),
      name: 'A',
      frames: [frame('f1'), frame('f2')],
      mark: key,
      timeline: {
        0: const TimelineExposure.drawing(FrameId('f1'), length: 2),
        2: const TimelineExposure.drawing(FrameId('f2'), length: 2),
      },
    );

    final applied = plan([paperRow, baseA]);
    expect(applied.bundles.map((bundle) => bundle.axis.name), ['A']);
    expect(applied.cels, hasLength(2));
    for (final task in applied.cels) {
      expect(names(task.members), ['Paper', 'A']);
      expect(task.memberFrames.first?.id.value, 'p1');
    }

    final raw = plan([paperRow, baseA], spec: const CelsExportSpec(applyPaper: false));
    expect(names(raw.cels.first.members), ['A']);
  });

  test('🚨paper alone does not keep a cel alive — 「그림이 존재하는 영역만」 '
      'counts PICTURES', () {
    // 감사 2026-09-09: the rule was written and nothing measured it. With the
    // picture check dropped, every axis frame the paper covers became a cel
    // — a delivery folder full of blank paper — and the suite stayed green.
    //
    // ⚠️The base is EXPOSED: an applied paper row has no cell link, so it
    // resolves through the timeline, and without exposure it would come back
    // null too — the fixture would then pass whatever the code did.
    final baseA = base('a', 'A', [
      frame('f1'),
      frame('f2'),
      frame('f3'),
    ], timeline: true);
    final sync = Layer(
      id: const LayerId('a-color'),
      name: 'A색',
      frames: [frame('c1'), frame('c3')],
      mark: key,
      attachedToLayerId: const LayerId('a'),
      attachedMode: AttachedMode.synced,
      baseFrameLinks: {
        const FrameId('f1'): const FrameId('c1'),
        const FrameId('f3'): const FrameId('c3'),
      },
    );
    final paperRow = Layer(
      id: const LayerId('p'),
      name: 'Paper',
      frames: [frame('p1')],
      mark: paper,
      timeline: {0: const TimelineExposure.drawing(FrameId('p1'), length: 4)},
    );

    final built = plan([paperRow, baseA, sync], spec: attach);
    expect(
      built.cels.map((task) => task.celName),
      ['1', '3'],
      reason: 'cel 2 has paper under it and no picture — it is not a cel',
    );
    for (final task in built.cels) {
      expect(names(task.members), ['Paper', 'A색']);
    }
  });

  test('an unticked bundle stays planned and listed, and is not written', () {
    final built = plan(
      [base('a', 'A', [frame('f1')]), base('b', 'B', [frame('g1')])],
      overrides: ExportProjectOverrides().withCelsDelta(
        const CutId('cut'),
        ExportCelsCutDelta().withBaseSkipped(const LayerId('a'), true),
      ),
    );
    expect(built.cels, hasLength(2));
    expect(built.cels.first.skipped, isTrue);
    expect(built.bundles, hasLength(2));
    expect(names(built.writtenCels.map((task) => task.baseLayer)), ['B']);
    expect(built.length, 1);
  });

  test('the cel number IS the frame name; an unnamed frame is the '
      'in-between mark and has no file', () {
    // 유저 2026-09-09: 「프레임 이름을 그대로 셀 번호로 출력시키고, 이름 없으면
    // 출력 안 하도록 — 이름 없으면 중간나누기 마크인 거니까」.
    final built = plan(
      [
        base('a', 'A', [
          frame('f1', name: '3'),
          frame('f2', unnamed: true),
          frame('f3', name: '  '),
        ]),
      ],
      spec: const CelsExportSpec(
        naming: ExportCelNaming(includeCutName: true, frameDigits: 3),
      ),
    );
    expect(files(built), ['CUT1_A003.png']);
    expect(built.cels.single.baseFrame.id.value, 'f1');
  });

  test('the sheet and the export agree on which drawing is a cel', () {
    // One getter answers both — a blank name is the mark on either side.
    expect(frame('f1', name: '12').celNumber, '12');
    expect(frame('f1', name: ' 12 ').celNumber, '12');
    expect(frame('f1', unnamed: true).celNumber, isNull);
    expect(frame('f1', name: '').celNumber, isNull);
    expect(frame('f1', name: '\t').celNumber, isNull);
  });

  test('디렉션 추가: instruction rows export per event with the row text; '
      'without it they stay out; it takes nothing away from the drawings', () {
    final layers = [base('a', 'A', [frame('f1')]), instructionRow()];

    final built = plan(layers, spec: direction);
    expect(built.cels, isEmpty, reason: 'the drawing filters are off');
    expect(built.instructions, hasLength(1));
    expect(built.instructions.single.label, 'PAN');
    expect(built.instructions.single.length, 12);
    expect(built.instructions.single.fileName, 'Camera1.png');
    expect(built.length, 1);

    expect(plan(layers).instructions, isEmpty);
    final added = plan(layers, spec: const CelsExportSpec(addDirection: true));
    expect(added.cels, hasLength(1));
    expect(added.instructions, hasLength(1));
  });

  test('🚨the preview key is the picture, not the file name — two labels '
      'naming their cel A1.png get two keys', () {
    // 유저 2026-09-09: 「작감수정 고른상태서 LO로 고르고 나니까 미리보기화면이
    // 갱신안되서 여전히 작감수정그림있던데」 — the cache keyed on the name.
    const keyAd = LayerMark(
      process: LayerProcess.key,
      revise: LayerRevise.animationDirector,
    );
    final rider = Layer(
      id: const LayerId('a-ad'),
      name: 'A-ad',
      frames: [frame('d1')],
      mark: keyAd,
      attachedToLayerId: const LayerId('a'),
      attachedMode: AttachedMode.synced,
      baseFrameLinks: {const FrameId('f1'): const FrameId('d1')},
    );
    final layers = [base('a', 'A', [frame('f1')]), rider];
    final plain = plan(layers).cels.single;
    final corrected = plan(
      layers,
      spec: const CelsExportSpec(label: keyAd),
    ).cels.single;
    expect(plain.fileName, corrected.fileName, reason: 'same axis, same cel');
    expect(names(plain.members), ['A']);
    expect(names(corrected.members), ['A-ad']);

    String keyOf(ExportCelGroupTask task, {bool fx = true}) =>
        celGroupPreviewKey(
          task,
          sizeMode: 'canvas',
          backgroundKey: -1,
          applyLayerFx: fx,
        );
    expect(keyOf(plain), isNot(keyOf(corrected)));
    expect(keyOf(plain), isNot(keyOf(plain, fx: false)));
    expect(keyOf(plain), keyOf(plan(layers).cels.single));
  });

  test('미술 추가: an art row makes a bundle of its own', () {
    final layers = [
      base('a', 'A', [frame('f1')]),
      base('bg', 'BG', [frame('b1')], mark: art),
    ];
    expect(files(plan(layers)), ['A1.png']);
    expect(files(plan(layers, spec: const CelsExportSpec(addArt: true))), [
      'A1.png',
      'BG1.png',
    ]);
  });

  test('project scope honors the cut checks', () {
    final project = Project(
      id: const ProjectId('project'),
      name: 'Project',
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Track',
          cuts: [
            for (final id in ['c1', 'c2'])
              Cut(
                id: CutId(id),
                name: id.toUpperCase(),
                duration: 2,
                canvasSize: const CanvasSize(width: 8, height: 8),
                layers: [
                  base('$id-a', 'A', [frame('$id-f1', name: '1')]),
                  createCameraLayer(cutId: CutId(id)),
                ],
              ),
          ],
        ),
      ],
      createdAt: DateTime.utc(2026),
    );
    final built = buildExportCelGroupPlan(
      project: project,
      activeCutId: const CutId('c1'),
      spec: const CelsExportSpec(scope: ExportScopeKind.project),
      overrides: ExportProjectOverrides().withCutIncluded(
        const CutId('c2'),
        false,
      ),
    );
    expect(built.cels.map((task) => task.cut.id.value).toSet(), {'c1'});
  });

  test('겸용: a link group is ONE cut — exported once, from its owner, under '
      'the joined name', () {
    // 유저 2026-09-09: 「겸용컷은 하나라는 느낌이야 … 겸용컷 비포함이란게
    // 불가능하도록」.
    final project = Project(
      id: const ProjectId('project'),
      name: 'Project',
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Track',
          cuts: [
            for (final id in ['c1', 'c2', 'c3'])
              Cut(
                id: CutId(id),
                name: id.toUpperCase(),
                duration: 2,
                canvasSize: const CanvasSize(width: 8, height: 8),
                layers: [
                  base('$id-a', 'A', [frame('$id-f1', name: '1')]),
                  createCameraLayer(cutId: CutId(id)),
                ],
              ),
          ],
        ),
      ],
      linkRegistry: LayerLinkRegistry(
        groups: [
          LayerLinkGroup(
            id: 'group-1',
            members: const [
              LayerLinkMember(
                trackId: TrackId('track'),
                cutId: CutId('c1'),
                layerId: LayerId('c1-a'),
              ),
              LayerLinkMember(
                trackId: TrackId('track'),
                cutId: CutId('c2'),
                layerId: LayerId('c2-a'),
              ),
            ],
          ),
        ],
      ),
      createdAt: DateTime.utc(2026),
    );
    final built = buildExportCelGroupPlan(
      project: project,
      activeCutId: const CutId('c2'),
      spec: const CelsExportSpec(
        scope: ExportScopeKind.project,
        naming: ExportCelNaming(includeCutName: true),
      ),
    );

    expect(built.cels.map((task) => task.cut.id.value), ['c1', 'c3']);
    expect(files(built), ['C1-C2_A1.png', 'C3_A1.png']);
    // The cut scope, opened on the sibling, still names the whole group.
    final fromSibling = buildExportCelGroupPlan(
      project: project,
      activeCutId: const CutId('c2'),
      spec: const CelsExportSpec(naming: ExportCelNaming(includeCutName: true)),
    );
    expect(files(fromSibling), ['C1-C2_A1.png']);
  });

  /// 🚨A FILE NAME THAT REPEATS IS A FILE THAT DISAPPEARS.
  ///
  /// Two bundles can each hold a cel called `1`, and a naming that leaves
  /// the label out puts both in one folder under one name. The bump
  /// (`_2`, `_3`, …) is what the user sees instead of one of the two
  /// cels simply not being written. Nothing checked it until
  /// 2026-09-05: the whole uniqueness loop could be deleted and the
  /// suite stayed green.
  test('🚨two bundles holding a cel of the same name get two FILES', () {
    final built = plan(
      [base('a', 'A', [frame('f1')]), base('b', 'B', [frame('g1')])],
      spec: const CelsExportSpec(
        naming: ExportCelNaming(includeLayerName: false),
      ),
    );

    final written = files(built);
    expect(written, hasLength(2));
    expect(
      written.toSet(),
      hasLength(2),
      reason: 'the second write would have replaced the first: $written',
    );
    expect(written.last, contains('_2'));
  });

  test('🚨the folders are folders, not prefixes, and nest project → cut → '
      'label', () {
    final layers = [base('a', 'A', [frame('f1')])];
    expect(
      plan(
        layers,
        spec: const CelsExportSpec(naming: ExportCelNaming(layerFolder: true)),
      ).cels.single.fileName,
      'A/A1.png',
    );
    expect(
      plan(
        layers,
        spec: const CelsExportSpec(
          naming: ExportCelNaming(
            projectFolder: true,
            cutFolder: true,
            layerFolder: true,
          ),
        ),
      ).cels.single.fileName,
      'Project/CUT1/A/A1.png',
    );
  });

  test('🚨an instruction file shares the run\'s names — a camera event and '
      'a cel cannot collide either', () {
    final built = plan(
      [base('a', 'A', [frame('f1')]), instructionRow(id: 'i', name: 'A')],
      spec: const CelsExportSpec(
        addDirection: true,
        naming: ExportCelNaming(includeLayerName: false),
      ),
    );

    final written = [
      ...files(built),
      ...built.instructions.map((task) => task.fileName),
    ];
    expect(written, hasLength(2));
    expect(written.toSet(), hasLength(written.length), reason: '$written');
  });

  /// 🚨F-177 (유저 2026-09-22): 「A1,2,2a,3 이렇게 됬으면하는게
  /// A1,2,3,4,5,6,7,8,9,2a 이렇게 됨. 즉 정렬을 윈도우 기준? 으로
  /// 해줬으면함」 — the cels are listed, previewed and written in the order a
  /// file browser lists their names, not the order they were drawn in.
  group('the cels come in file-browser order', () {
    List<String> celNames(ExportCelGroupPlan built) => [
      for (final task in built.cels) task.celName,
    ];

    test('an insertion drawn last sits after its number — 1, 2, 2a, 3', () {
      final a = base('a', 'A', [
        for (var n = 1; n <= 9; n += 1) frame('f$n'),
        frame('f2a', name: '2a'),
      ]);

      expect(celNames(plan([a])), [
        '1', '2', '2a', '3', '4', '5', '6', '7', '8', '9', //
      ]);
    });

    test('numbers by value, whatever order they were drawn in — C2, 3, 1 '
        'reads 1, 2, 3, and 10 comes after 9', () {
      final c = base('c', 'C', [
        frame('f2'),
        frame('f3'),
        frame('f1'),
        frame('f10'),
        frame('f9'),
      ]);

      expect(celNames(plan([c])), ['1', '2', '3', '9', '10']);
    });

    test('⚠️two drawings with ONE name keep the order they were made in — '
        'the namer\'s _2 does not move', () {
      final a = base('a', 'A', [
        frame('x', name: '1'),
        frame('f2'),
        frame('y', name: '1'),
      ]);

      expect(
        [
          for (final task in plan([a]).cels)
            (task.baseFrame.id.value, task.fileName),
        ],
        [('x', 'A1.png'), ('y', 'A1_2.png'), ('f2', 'A2.png')],
      );
    });
  });
}
