import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_overrides.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/exposure_instruction.dart';
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
import 'package:anicel/src/models/timeline_run_behavior.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/export/export_cel_group_plan.dart';

void main() {
  const key = LayerMark(process: LayerProcess.key);
  const layout = LayerMark(process: LayerProcess.layout);
  const paper = LayerMark(process: LayerProcess.paper);
  const art = LayerMark(process: LayerProcess.art);
  const withDirection = {
    ExportCelKind.cel,
    ExportCelKind.art,
    ExportCelKind.direction,
  };
  // 디렉션 alone: the drawing filters off, the direction kind written.
  const direction = CelsExportSpec(
    base: false,
    attach: false,
    kinds: withDirection,
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

  /// A base row whose [frames] are each shown once, in order — or, with
  /// [shown] false, a row that shows none of them (a cel no cut shows is no
  /// cel of an export: F-289 ⑥).
  Layer base(
    String id,
    String name,
    List<Frame> frames, {
    LayerMark mark = key,
    bool shown = true,
  }) => Layer(
    id: LayerId(id),
    name: name,
    frames: frames,
    mark: mark,
    timeline: shown ? exposed(frames) : const {},
  );

  /// An IMAGE row holding [cel] — a picture row wears 미술, as Add Layer
  /// makes one ([LayerMark.bornOfKind]).
  Layer image(String id, String name, Frame cel) => Layer(
    id: LayerId(id),
    name: name,
    kind: LayerKind.image,
    frames: [cel],
    mark: art,
    timeline: exposed([cel]),
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

  /// A direction row with ONE block, saying [says] — its span laid down as
  /// the block it is, with a drawing of its own under it.
  Layer instructionRow({
    String id = 'inst',
    String name = 'Camera',
    InstructionEvent says = const InstructionEvent(
      instructionId: 'pan',
      length: 12,
      text: 'PAN',
    ),
  }) => Layer(
    id: LayerId(id),
    name: name,
    frames: const [],
    kind: LayerKind.instruction,
    instructions: {0: says},
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
    final baseA = base('a', 'A', [frame('f1'), frame('f2')]);
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
    ]);
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

  test('🗣️an IMAGE row\'s unnamed cel files under the layer\'s name alone '
      '— an animation row\'s still files nothing', () {
    // 유저 2026-09-25: 「이름없어도 출력은 이 규칙은 이미지레이어에만 적용.
    // 애니메이션레이어는 이름없으면 출력안함」 · 「이름없이 BOOK 그대로 출력」.
    final layers = [
      base('a', 'A', [frame('f1', unnamed: true)]),
      image('bg', 'BG', frame('b1', unnamed: true)),
      image('book', 'BOOK', frame('k1', name: 'BOOK1')),
    ];
    final built = plan(layers, spec: const CelsExportSpec());
    expect(
      files(built),
      ['_BG.png', '_BOOKBOOK1.png'],
      reason: 'a named image cel is layer + frame name, as every cel is',
    );
    expect(built.cels.first.celName, isEmpty);
    expect(
      files(
        plan(
          layers,
          spec: const CelsExportSpec(
            naming: ExportCelNaming(includeLayerName: false),
          ),
        ),
      ),
      ['_BG.png', '_BOOK1.png'],
      reason:
          'with the label switched off, the layer\'s name is still the '
          'unnamed cel\'s only name — a file must have one',
    );
  });

  test('🗣️rows stacked under ONE name file their unnamed cel ONCE — the '
      'first the walk meets, not a BOOK_2 nobody named', () {
    // 유저 2026-09-25: 「같은 이름 레이어가 존재하고 똑같이 이름없는게
    // 존재하면 거기서 순서상 첫 블록만. 하나만 출력되면되」.
    final built = plan([
      image('k1', 'BOOK', frame('p1', unnamed: true)),
      image('k2', 'BOOK', frame('p2', unnamed: true)),
      image('k3', 'BOOK', frame('p3', name: '2')),
    ], spec: const CelsExportSpec());
    expect(files(built), ['_BOOK.png', '_BOOK2.png']);
    expect(built.cels.first.baseLayer.id.value, 'k1');
  });

  test('…and ONCE per CUT: another cut\'s unnamed BG is another picture', () {
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
                  image('$id-bg', 'BG', frame('$id-b', unnamed: true)),
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
      spec: const CelsExportSpec(
        scope: ExportScopeKind.project,
        naming: ExportCelNaming(includeCutName: true),
      ),
    );
    expect(files(built), ['_C1_BG.png', '_C2_BG.png']);
  });

  test('⛔the unnamed cel that IS the layer is the one the row SHOWS — a 겸용 '
      'cut\'s unnamed picture in the same bank is no cel of this cut', () {
    // 유저 2026-09-12 (F-98): 「이름 안정해지면 별개것임」. The bank is the
    // link group's: each 겸용 cut's row is born with a picture of its own,
    // and every member's bank holds all of them.
    final mine = frame('mine', unnamed: true);
    final theirs = frame('theirs', unnamed: true);
    final built = plan([
      Layer(
        id: const LayerId('bg'),
        name: 'BG',
        kind: LayerKind.image,
        frames: [theirs, mine],
        mark: art,
        timeline: exposed([mine]),
      ),
    ], spec: const CelsExportSpec());
    expect(files(built), ['_BG.png']);
    expect(built.cels.single.baseFrame.id.value, 'mine');
  });

  test('🗣️a kind\'s files start with its prefix — 미술 with `_` until the '
      'naming says otherwise, a cel with none; a folder never wears it', () {
    // 유저 2026-10-06: 「접두사는 각각 _로하거나 커스텀으로 텍스트 지정가능 …
    // 기본값은 셀:없음, 미술:_, 디렉션:_, 시트:_, 컷봉투:_」.
    final layers = [
      base('a', 'A', [frame('f1')]),
      image('bg', 'BG', frame('b1')),
    ];
    List<String> filesWith(ExportCelNaming naming) =>
        files(plan(layers, spec: CelsExportSpec(naming: naming)));

    expect(filesWith(const ExportCelNaming()), ['A1.png', '_BG1.png']);
    expect(
      filesWith(const ExportCelNaming().withPrefix(ExportCelKind.art, '')),
      ['A1.png', 'BG1.png'],
    );
    expect(
      filesWith(
        const ExportCelNaming()
            .withPrefix(ExportCelKind.cel, 'x-')
            .withPrefix(ExportCelKind.art, 'bg_'),
      ),
      ['x-A1.png', 'bg_BG1.png'],
    );
    expect(
      filesWith(const ExportCelNaming(includeCutName: true, layerFolder: true)),
      ['A/CUT1_A1.png', 'BG/_CUT1_BG1.png'],
      reason: 'the prefix leads the FILE\'s name; the folder is the row\'s',
    );
  });

  test('the sheet and the export agree on which drawing is a cel', () {
    // One getter answers both — a blank name is the mark on either side.
    expect(frame('f1', name: '12').celNumber, '12');
    expect(frame('f1', name: ' 12 ').celNumber, '12');
    expect(frame('f1', unnamed: true).celNumber, isNull);
    expect(frame('f1', name: '').celNumber, isNull);
    expect(frame('f1', name: '\t').celNumber, isNull);
  });

  group('디렉션: a direction row\'s DRAWINGS are cels (F-289)', () {
    // 유저 2026-10-05: 「디렉션레이어 출력시, 그림이 디렉션레이어의 지시인데,
    // 그게아니라 그림 그릴수있는 레이어니 거기 있는 그림 출력하도록」.
    test('each block\'s drawing is a cel of the row\'s own bundle — the '
        'picture that was drawn, composited as every cel is; off, the kind '
        'writes nothing, and on it takes nothing from the drawings', () {
      final row = instructionRow();
      final layers = [base('a', 'A', [frame('f1')]), row];

      final built = plan(layers, spec: direction);
      expect(built.cels, hasLength(1), reason: 'the drawing filters are off');
      final cel = built.cels.single;
      expect(cel.baseLayer.id.value, 'inst');
      expect(
        cel.baseFrame.id,
        row.frames.single.id,
        reason: 'the drawing under the block — not a picture of its writing',
      );
      expect(names(cel.members), ['Camera']);
      expect(cel.memberFrames, [cel.baseFrame]);
      expect(built.length, 1);

      expect(files(plan(layers)), ['A1.png'], reason: 'the kind is off');
      expect(
        files(plan(layers, spec: const CelsExportSpec(kinds: withDirection))),
        ['A1.png', '_Camera_PAN.png'],
      );
    });

    test('the file is the row\'s name, what the block says, and the ends it '
        'runs between — `Camera_T.U_A-B` — behind the kind\'s prefix', () {
      // 유저 2026-10-06: 「첫이름이 A고 끝이름이 B고 지시이름이 T.U면,
      // T.U_A-B … 디렉션레이어는 프레임이름이랑 레이어이름사이에 _ 넣고,
      // 지시랑 첫/끝이름 사이에 _ 넣는거지. 거기서 유저가 추가로 접두사 _」.
      String fileOf(InstructionEvent says, {ExportCelNaming? naming}) => files(
        plan(
          [instructionRow(says: says)],
          spec: CelsExportSpec(
            kinds: withDirection,
            naming: naming ?? const ExportCelNaming(),
          ),
        ),
      ).single;
      const tu = InstructionEvent(
        instructionId: 'tu',
        length: 12,
        text: 'T.U',
        valueA: 'A',
        valueB: 'B',
      );
      expect(fileOf(tu), '_Camera_T.U_A-B.png');
      expect(
        fileOf(tu, naming: const ExportCelNaming().withPrefix(
          ExportCelKind.direction,
          '',
        )),
        'Camera_T.U_A-B.png',
      );
      expect(
        fileOf(tu.copyWith(valueB: () => null)),
        '_Camera_T.U_A.png',
        reason: 'an end that is not written is left out',
      );
      expect(
        fileOf(tu.copyWith(valueA: () => ' ', valueB: () => 'B')),
        '_Camera_T.U_B.png',
      );
      expect(
        fileOf(tu.copyWith(valueA: () => null, valueB: () => null)),
        '_Camera_T.U.png',
      );
      expect(
        fileOf(tu, naming: const ExportCelNaming(includeLayerName: false)),
        '_T.U_A-B.png',
        reason: 'with the row\'s name off the name stands alone',
      );
      expect(
        fileOf(tu, naming: const ExportCelNaming(frameDigits: 4)),
        '_Camera_T.U_A-B.png',
        reason: 'a name is not a number: nothing in it is padded',
      );
    });

    test('a block that says nothing is the row\'s name alone, and two of '
        'them are two files', () {
      final a = frame('d1', unnamed: true);
      final b = frame('d2', unnamed: true);
      final row = Layer(
        id: const LayerId('inst'),
        name: 'Camera',
        kind: LayerKind.instruction,
        frames: [a, b],
        timeline: {
          0: TimelineExposure.drawing(a.id, length: 2),
          2: TimelineExposure.drawing(b.id, length: 2),
          4: TimelineExposure.drawing(a.id, length: 2),
        },
      );
      expect(
        files(plan([row], spec: const CelsExportSpec(kinds: withDirection))),
        ['_Camera.png', '_Camera_2.png'],
        reason: 'one cel a DRAWING — the block that shows the first again '
            'adds none',
      );
    });

    test('a block\'s ghost is not the block: the drawing is called by what '
        'ITS block says, though the ghost stands before it', () {
      final drawn = frame('d1', unnamed: true);
      final row = Layer(
        id: const LayerId('inst'),
        name: 'Camera',
        kind: LayerKind.instruction,
        frames: [drawn],
        timeline: {
          0: TimelineExposure.drawing(
            drawn.id,
            length: 2,
            ghostOf: const TimelineRunEdgeGhost(
              side: TimelineRunEdgeSide.start,
              mode: TimelineRunEdgeMode.hold,
            ),
          ),
          2: TimelineExposure.drawing(
            drawn.id,
            length: 2,
            instruction: const ExposureInstruction(
              instructionId: 'tu',
              text: 'T.U',
            ),
          ),
        },
      );
      expect(
        files(plan([row], spec: const CelsExportSpec(kinds: withDirection))),
        ['_Camera_T.U.png'],
        reason: 'the ghost says nothing — walked first, it named the file '
            '`_Camera`',
      );
    });
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
    expect(files(plan(layers)), ['A1.png', '_BG1.png']);
    expect(
      files(
        plan(layers, spec: const CelsExportSpec(kinds: {ExportCelKind.cel})),
      ),
      ['A1.png'],
    );
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

  group('🚨F-300 (유저 2026-10-05): a 겸용 group\'s cel is composited where it '
      'is SHOWN — 「현재 컷에 BG1이면 용지 적용되고 현재컷이아닌 BG2쪽은 용지가 '
      '빠짐 … 렌더에 현재컷 관련 로직 있는건 이상하니 근본/구조적으로 해결」 · '
      '「애니메이션레이어도 현재컷이 아니면 용지가 빠짐」', () {
    // Two 겸용 cuts sharing three rows. Each row's BANK is the link
    // group's — both cuts hold every cel — and each cut's own timeline
    // shows one of them: C1 shows BG 1 and A 1, C2 shows BG 2 and A 2. The
    // paper lies under the whole of either cut.
    Layer rowOf(String cut, String row) => switch (row) {
      'paper' => Layer(
        id: LayerId('$cut-paper'),
        name: 'Paper',
        frames: [frame('p1')],
        mark: paper,
        timeline: {
          0: const TimelineExposure.drawing(FrameId('p1'), length: 4),
        },
      ),
      'bg' => Layer(
        id: LayerId('$cut-bg'),
        name: 'BG',
        kind: LayerKind.image,
        frames: [frame('bg1'), frame('bg2')],
        mark: art,
        timeline: {
          0: TimelineExposure.drawing(
            FrameId(cut == 'c1' ? 'bg1' : 'bg2'),
            length: 1,
          ),
        },
      ),
      _ => Layer(
        id: LayerId('$cut-a'),
        name: 'A',
        frames: [frame('a1'), frame('a2')],
        mark: key,
        // On C2 the cel first shows on the cut's THIRD frame.
        timeline: cut == 'c1'
            ? {0: const TimelineExposure.drawing(FrameId('a1'), length: 4)}
            : {2: const TimelineExposure.drawing(FrameId('a2'), length: 2)},
      ),
    };

    /// C1 and C2 as a 겸용 pair: each holds [rowsOf] its own id, and the
    /// rows named `<cut>-<row>` for each of [rows] are linked across them.
    Project pairOf(List<Layer> Function(String cut) rowsOf, List<String> rows) =>
        Project(
          id: const ProjectId('project'),
          name: 'Project',
          tracks: [
            Track(
              id: const TrackId('track'),
              name: 'Track',
              cuts: [
                for (final cut in ['c1', 'c2'])
                  Cut(
                    id: CutId(cut),
                    name: cut.toUpperCase(),
                    duration: 4,
                    canvasSize: const CanvasSize(width: 8, height: 8),
                    layers: [
                      ...rowsOf(cut),
                      createCameraLayer(cutId: CutId(cut)),
                    ],
                  ),
              ],
            ),
          ],
          linkRegistry: LayerLinkRegistry(
            groups: [
              for (final row in rows)
                LayerLinkGroup(
                  id: 'group-$row',
                  members: [
                    for (final cut in ['c1', 'c2'])
                      LayerLinkMember(
                        trackId: const TrackId('track'),
                        cutId: CutId(cut),
                        layerId: LayerId('$cut-$row'),
                      ),
                  ],
                ),
            ],
          ),
          createdAt: DateTime.utc(2026),
        );

    final linked = pairOf(
      (cut) => [rowOf(cut, 'paper'), rowOf(cut, 'bg'), rowOf(cut, 'a')],
      ['paper', 'bg', 'a'],
    );

    ExportCelGroupPlan planFrom(
      String activeCut, {
      ExportScopeKind scope = ExportScopeKind.cut,
    }) => buildExportCelGroupPlan(
      project: linked,
      activeCutId: CutId(activeCut),
      spec: CelsExportSpec(scope: scope),
    );

    /// Each cel as `file: the cut it is composited in / the paper under it`.
    Map<String, String> stacks(ExportCelGroupPlan plan) => {
      for (final task in plan.cels)
        task.fileName:
            '${task.cut.id.value} / '
            '${[
              for (var i = 0; i < task.members.length; i += 1)
                if (task.members[i].name == 'Paper')
                  task.memberFrames[i]?.id.value ?? 'NO PAPER',
            ].join()}',
    };

    const everyCel = {
      '_BG1.png': 'c1 / p1',
      '_BG2.png': 'c2 / p1',
      'A1.png': 'c1 / p1',
      'A2.png': 'c2 / p1',
    };

    test('every cel of the group wears the paper of the cut that shows it '
        '— whichever sibling the export window stands on', () {
      expect(stacks(planFrom('c1')), everyCel);
      expect(stacks(planFrom('c2')), everyCel);
    });

    test('…and under the project scope, where the group is walked once from '
        'its owner', () {
      expect(stacks(planFrom('c2', scope: ExportScopeKind.project)), everyCel);
    });

    test('a cel is its showing cut\'s stack: that cut\'s rows, and the '
        'frame it first shows on there', () {
      final a2 = planFrom(
        'c1',
      ).cels.singleWhere((task) => task.fileName == 'A2.png');

      expect(a2.cut.id.value, 'c2');
      expect(a2.baseLayer.id.value, 'c2-a');
      expect([for (final member in a2.members) member.id.value], [
        'c2-paper',
        'c2-a',
      ]);
      expect(a2.baseFrame.id.value, 'a2');
      expect(
        identical(a2.baseFrame, a2.baseLayer.frameById(const FrameId('a2'))),
        isTrue,
        reason: 'the cel is the showing cut\'s own row\'s — not the copy the '
            'window\'s cut holds of it',
      );
      expect(celGroupFirstExposure(a2), 2);
    });

    test('a cel BOTH cuts show is composited in the first of them in track '
        'order — one picture, whichever sibling is open', () {
      // The same rows with BG 1 shown by C2 as well, ahead of its BG 2.
      final both = linked.copyWith(
        tracks: [
          linked.tracks.single.copyWith(
            cuts: [
              for (final cut in linked.tracks.single.cuts)
                cut.copyWith(
                  layers: [
                    for (final layer in cut.layers)
                      if (layer.name == 'BG' && cut.id.value == 'c2')
                        layer.copyWith(
                          timeline: {
                            0: const TimelineExposure.drawing(
                              FrameId('bg1'),
                              length: 1,
                            ),
                            1: const TimelineExposure.drawing(
                              FrameId('bg2'),
                              length: 1,
                            ),
                          },
                        )
                      else
                        layer,
                  ],
                ),
            ],
          ),
        ],
      );

      for (final standingOn in ['c1', 'c2']) {
        final built = buildExportCelGroupPlan(
          project: both,
          activeCutId: CutId(standingOn),
          spec: const CelsExportSpec(),
        );
        expect(
          stacks(built)['_BG1.png'],
          'c1 / p1',
          reason: 'standing on $standingOn',
        );
      }
    });

    test('the rows riding a cel ride it in the cut that shows it: a SYNCED '
        'row by its cell link, a FREE row by what that cut exposes there', () {
      // A holds cels 1 and 2 — C1 shows 1, C2 shows 2 — with a synced row
      // and a free row riding it. The free row's bank is the group's too,
      // and each cut shows its own cel of it.
      List<Layer> rowsOf(String cut) {
        final shown = cut == 'c1' ? '1' : '2';
        return [
          Layer(
            id: LayerId('$cut-a'),
            name: 'A',
            frames: [frame('a1'), frame('a2')],
            mark: key,
            timeline: {
              0: TimelineExposure.drawing(FrameId('a$shown'), length: 4),
            },
          ),
          Layer(
            id: LayerId('$cut-color'),
            name: 'A색',
            frames: [frame('s1'), frame('s2')],
            mark: key,
            attachedToLayerId: LayerId('$cut-a'),
            attachedMode: AttachedMode.synced,
            baseFrameLinks: {
              const FrameId('a1'): const FrameId('s1'),
              const FrameId('a2'): const FrameId('s2'),
            },
          ),
          Layer(
            id: LayerId('$cut-shadow'),
            name: 'Ashadow',
            frames: [frame('h1'), frame('h2')],
            mark: key,
            attachedToLayerId: LayerId('$cut-a'),
            attachedMode: AttachedMode.free,
            timeline: {
              0: TimelineExposure.drawing(FrameId('h$shown'), length: 4),
            },
          ),
        ];
      }

      final riders = pairOf(rowsOf, ['a', 'color', 'shadow']);

      for (final standingOn in ['c1', 'c2']) {
        final built = buildExportCelGroupPlan(
          project: riders,
          activeCutId: CutId(standingOn),
          spec: const CelsExportSpec(),
        );
        expect(
          {
            for (final task in built.cels)
              task.fileName: [
                for (var i = 0; i < task.members.length; i += 1)
                  '${task.members[i].id.value}='
                      '${task.memberFrames[i]?.id.value}',
              ],
          },
          {
            'A1.png': ['c1-a=a1', 'c1-color=s1', 'c1-shadow=h1'],
            'A2.png': ['c2-a=a2', 'c2-color=s2', 'c2-shadow=h2'],
          },
          reason: 'standing on $standingOn',
        );
      }
    });

    test('with 용지 적용 off no cel of the group wears a paper — a '
        'sibling\'s cels included', () {
      final bare = buildExportCelGroupPlan(
        project: linked,
        activeCutId: const CutId('c1'),
        spec: const CelsExportSpec(applyPaper: false),
      );

      expect(stacks(bare), {
        '_BG1.png': 'c1 / ',
        '_BG2.png': 'c2 / ',
        'A1.png': 'c1 / ',
        'A2.png': 'c2 / ',
      });
    });

    test('the list still shows ONE bundle a row — the cels of both cuts '
        'under the row of the cut the window stands on', () {
      final built = planFrom('c2');

      expect(
        [for (final bundle in built.bundles) bundle.axis.id.value],
        ['c2-bg', 'c2-a'],
      );
      // Every cel is listed in the cut the window stands on, whichever cut
      // it is composited in.
      expect({for (final task in built.cels) task.listedCut.id.value}, {'c2'});
      expect({for (final task in built.cels) task.cut.id.value}, {'c1', 'c2'});
      expect(
        [
          for (final bundle in built.bundles)
            [for (final sheet in bundle.sheets) sheet.fileName],
        ],
        [
          ['_BG1.png', '_BG2.png'],
          ['A1.png', 'A2.png'],
        ],
      );
    });

    test('unticking the bundle on the window\'s cut skips its cels from '
        'both cuts', () {
      final built = buildExportCelGroupPlan(
        project: linked,
        activeCutId: const CutId('c2'),
        spec: const CelsExportSpec(),
        overrides: ExportProjectOverrides().withCelsDelta(
          const CutId('c2'),
          ExportCelsCutDelta().withBaseSkipped(const LayerId('c2-a'), true),
        ),
      );

      expect(
        {for (final task in built.cels) task.fileName: task.skipped},
        {
          '_BG1.png': false,
          '_BG2.png': false,
          'A1.png': true,
          'A2.png': true,
        },
      );
    });

    test('🗣️a cel no cut of the group shows is no cel of the export (F-289 '
        '⑥, 유저 2026-10-06: 「애초에 타임라인에 안놓은 셀은 출력에 '
        '포함하지않음」)', () {
      // The same rows with A 2 shown nowhere.
      final unshown = linked.copyWith(
        tracks: [
          linked.tracks.single.copyWith(
            cuts: [
              for (final cut in linked.tracks.single.cuts)
                cut.copyWith(
                  layers: [
                    for (final layer in cut.layers)
                      if (layer.name == 'A' && cut.id.value == 'c2')
                        layer.copyWith(timeline: const {})
                      else
                        layer,
                  ],
                ),
            ],
          ),
        ],
      );
      final built = buildExportCelGroupPlan(
        project: unshown,
        activeCutId: const CutId('c2'),
        spec: const CelsExportSpec(),
      );

      expect(
        stacks(built).keys,
        isNot(contains('A2.png')),
        reason: '↩️it went out from the window\'s cut, with no paper under it',
      );
      expect(stacks(built)['A1.png'], 'c1 / p1');
    });
  });

  test('a cel its row never shows is not planned; the ones it shows are', () {
    final one = frame('f1');
    final two = frame('f2');
    final a = Layer(
      id: const LayerId('a'),
      name: 'A',
      frames: [one, two],
      mark: key,
      timeline: exposed([two]),
    );
    expect(files(plan([a])), ['A2.png']);
    expect(
      files(plan([base('b', 'B', [frame('g1')], shown: false)])),
      isEmpty,
    );
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
        kinds: withDirection,
        naming: ExportCelNaming(includeLayerName: false),
      ),
    );

    final written = files(built);
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
