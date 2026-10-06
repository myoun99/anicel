import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_overrides.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/ui/export/export_cels_selection.dart';

/// The Cels tab's row set: the KINDS first (F-289, 2026-10-06) — a row of a
/// kind the export does not write is neither written nor listed — then the
/// filters of 2026-09-09: ONE colour label over the cel rows, a take (or
/// 「최신」), 기준 · 어태치 · 시트만, paper applied rather than exported — and
/// the cut's hand delta last.
void main() {
  const withDirection = {
    ExportCelKind.cel,
    ExportCelKind.art,
    ExportCelKind.direction,
  };
  const key = LayerMark(process: LayerProcess.key);
  const keyAd = LayerMark(
    process: LayerProcess.key,
    revise: LayerRevise.animationDirector,
  );
  const layout = LayerMark(process: LayerProcess.layout);
  const paper = LayerMark(process: LayerProcess.paper);
  const art = LayerMark(process: LayerProcess.art);

  Layer layer(
    String id, {
    String? name,
    LayerKind kind = LayerKind.animation,
    LayerMark mark = key,
    bool isVisible = true,
    bool onTimesheet = true,
    String? attachedTo,
    AttachedMode attachedMode = AttachedMode.synced,
    String? folder,
  }) => Layer(
    id: LayerId(id),
    name: name ?? id.toUpperCase(),
    frames: const [],
    kind: kind,
    mark: mark,
    isVisible: isVisible,
    onTimesheet: onTimesheet,
    attachedToLayerId: attachedTo == null ? null : LayerId(attachedTo),
    attachedMode: attachedMode,
    folderId: folder == null ? null : LayerId(folder),
  );

  Cut cut(List<Layer> layers) => Cut(
    id: const CutId('cut'),
    name: 'CUT1',
    duration: 12,
    canvasSize: const CanvasSize(width: 8, height: 8),
    layers: layers,
  );

  List<String> ids(Iterable<Layer> layers) => [
    for (final layer in layers) layer.id.value,
  ];

  ExportCelsSelection resolve(
    List<Layer> layers, {
    CelsExportSpec spec = const CelsExportSpec(),
    ExportCelsCutDelta? delta,
  }) => resolveExportCelsSelection(cut: cut(layers), spec: spec, delta: delta);

  List<String> cels(
    List<Layer> layers, {
    CelsExportSpec spec = const CelsExportSpec(),
    ExportCelsCutDelta? delta,
  }) => ids(resolve(layers, spec: spec, delta: delta).celLayers);

  test('the label is a row filter: a row exports when its OWN mark wears '
      'the export label, whatever kind of drawing it is', () {
    final layers = [
      layer('a'),
      layer('lo', mark: layout),
      layer('ad', mark: keyAd),
      layer('bg', kind: LayerKind.image),
      layer('plain', mark: LayerMark.none),
      layer('se', kind: LayerKind.se),
      layer('inst', kind: LayerKind.instruction),
      layer('cam', kind: LayerKind.camera),
    ];

    // 원화(上がり) is the default label.
    expect(cels(layers), ['a', 'bg']);
    // 「원화 작감」 is ONE item — not 원화 plus a revise filter.
    expect(cels(layers, spec: const CelsExportSpec(label: keyAd)), ['ad']);
    // 「라벨 없음」 exports the unlabelled rows.
    expect(
      cels(layers, spec: const CelsExportSpec(label: LayerMark.none)),
      ['plain'],
    );
  });

  test('markWearsLabel compares process and revise, never the take', () {
    expect(markWearsLabel(key.withTake(3), key), isTrue);
    expect(markWearsLabel(keyAd, key), isFalse);
    expect(markWearsLabel(key, keyAd), isFalse);
    expect(markWearsLabel(LayerMark.none, LayerMark.none), isTrue);
  });

  test('an attach row answers for its own mark, not its base\'s', () {
    final layers = [layer('a'), layer('ac', attachedTo: 'a', mark: keyAd)];
    expect(cels(layers), ['a']);
    expect(cels(layers, spec: const CelsExportSpec(label: keyAd)), ['ac']);
  });

  test('take: a number keeps that take; 「최신」 keeps the highest take per '
      'NAME (A T1 + A T2 → T2; A T1 + B T2 → both)', () {
    final layers = [
      layer('a1', name: 'A'),
      layer('a2', name: 'A', mark: key.withTake(2)),
      layer('b1', name: 'B'),
    ];
    expect(cels(layers), ['a2', 'b1']);
    expect(cels(layers, spec: const CelsExportSpec(take: 1)), ['a1', 'b1']);
    expect(cels(layers, spec: const CelsExportSpec(take: 2)), ['a2']);
  });

  test('the filters STACK: 기준 keeps the bases, 부속 keeps the attach rows, '
      '시트 keeps, of those, the ones on the sheet — and a direction row is '
      'neither a base nor an attach', () {
    // 유저 2026-09-09: 「단일선택이 아니라 중첩가능이야 … 진짜 여러 항목이
    // 필터로 작동하는거지」.
    final layers = [
      layer('a'),
      layer('ac', attachedTo: 'a'),
      layer('b', onTimesheet: false),
      layer('bf', attachedTo: 'b', attachedMode: AttachedMode.free),
      layer('inst', kind: LayerKind.instruction),
    ];

    expect(cels(layers), ['a', 'ac', 'b', 'bf']);
    expect(cels(layers, spec: const CelsExportSpec(base: false)), ['ac', 'bf']);
    expect(cels(layers, spec: const CelsExportSpec(attach: false)), ['a', 'b']);
    // An attach row never takes a sheet column of its own; it is on the
    // sheet when its base is.
    expect(cels(layers, spec: const CelsExportSpec(sheetOnly: true)), [
      'a',
      'ac',
    ]);
    expect(
      cels(layers, spec: const CelsExportSpec(base: false, sheetOnly: true)),
      ['ac'],
    );
    expect(
      cels(layers, spec: const CelsExportSpec(base: false, attach: false)),
      isEmpty,
    );

    expect(
      cels(layers, spec: const CelsExportSpec(kinds: withDirection)),
      ['a', 'ac', 'b', 'bf', 'inst'],
      reason: 'a kind turned on takes nothing away',
    );
    expect(
      cels(
        layers,
        spec: const CelsExportSpec(kinds: withDirection, sheetOnly: true),
      ),
      ['a', 'ac', 'inst'],
      reason: 'the direction row is on the sheet by default',
    );
    expect(
      cels(
        layers,
        spec: const CelsExportSpec(
          kinds: withDirection,
          base: false,
          attach: false,
        ),
      ),
      ['inst'],
      reason: '기준 and 어태치 are not asked of a direction row',
    );
  });

  test('paper is APPLIED, never a cel: listed while applyPaper, eye or no '
      'eye, and no delta makes it a cel', () {
    final layers = [
      layer('p', mark: paper),
      layer('ph', mark: paper, isVisible: false),
      layer('a'),
    ];
    final selection = resolve(layers);
    expect(ids(selection.celLayers), ['a']);
    expect(ids(selection.paperLayers), ['p', 'ph']);
    expect(
      resolve(layers, spec: const CelsExportSpec(applyPaper: false)).paperLayers,
      isEmpty,
    );
    expect(
      cels(
        layers,
        delta: ExportCelsCutDelta().withLayerOverride(const LayerId('p'), true),
      ),
      ['a'],
    );
  });

  group('the kinds come first', () {
    const conte = LayerMark(process: LayerProcess.conte);

    test('which kind a row is: a direction row, the conte row, a row '
        'labelled 미술, and every other drawing row a cel — an attach row of '
        'its BASE\'s kind, and the rows that export nothing of none', () {
      final layers = [
        layer('a'),
        layer('still', kind: LayerKind.image),
        layer('bg', mark: art),
        layer('bgc', attachedTo: 'bg', mark: keyAd),
        layer('ac', attachedTo: 'a', mark: art),
        layer('s', kind: LayerKind.storyboard, mark: conte),
        layer('inst', kind: LayerKind.instruction),
        layer('p', mark: paper),
        layer('se', kind: LayerKind.se),
        layer('cam', kind: LayerKind.camera),
        createFolderLayer(id: const LayerId('f'), name: 'F'),
      ];
      expect(
        {
          for (final each in layers)
            each.id.value: exportCelKindOf(each, layers),
        },
        {
          'a': ExportCelKind.cel,
          'still': ExportCelKind.cel,
          'bg': ExportCelKind.art,
          'bgc': ExportCelKind.art,
          'ac': ExportCelKind.cel,
          's': ExportCelKind.conte,
          'inst': ExportCelKind.direction,
          'p': null,
          'se': null,
          'cam': null,
          'f': null,
        },
      );
    });

    test('미술: art rows are written whatever the label, and what rides them '
        'with them — and not at all while the kind is off', () {
      // 유저 2026-10-06: 「기본값은 셀/미술/시트 체크」 — art is on from the
      // start, where it used to be a switch that added it.
      final layers = [
        layer('a'),
        layer('bg', mark: art),
        layer('bgc', attachedTo: 'bg', mark: layout),
      ];
      expect(cels(layers), ['a', 'bg', 'bgc']);
      expect(
        cels(layers, spec: const CelsExportSpec(label: keyAd)),
        ['bg', 'bgc'],
        reason: 'the label is the cel rows\' filter — art does not wear it',
      );
      expect(
        cels(layers, spec: const CelsExportSpec(kinds: {ExportCelKind.cel})),
        ['a'],
      );
      expect(
        cels(layers, spec: const CelsExportSpec(attach: false)),
        ['a', 'bg'],
        reason: '어태치 is asked of every row that rides one',
      );
    });

    test('셀: with the kind off no cel row goes out, whatever it wears', () {
      final layers = [layer('a'), layer('ad', mark: keyAd), layer('bg', mark: art)];
      expect(
        cels(layers, spec: const CelsExportSpec(kinds: {ExportCelKind.art})),
        ['bg'],
      );
      expect(
        cels(
          layers,
          spec: const CelsExportSpec(kinds: {ExportCelKind.art}, label: keyAd),
        ),
        ['bg'],
      );
    });

    test('콘티: the conte row is off from the start, and on it goes out '
        'whatever the label — a cel like any other', () {
      // 유저 2026-10-06: 「진짜 그냥 셀 출력하듯이 … 일반 셀이랑 똑같이」.
      final layers = [layer('a'), layer('s', kind: LayerKind.storyboard, mark: conte)];
      expect(cels(layers), ['a']);
      expect(
        cels(
          layers,
          spec: const CelsExportSpec(
            kinds: {ExportCelKind.cel, ExportCelKind.conte},
          ),
        ),
        ['a', 's'],
      );
      expect(
        cels(layers, spec: const CelsExportSpec(label: conte)),
        isEmpty,
        reason: '↩️the conte label used to be the way to reach it',
      );
    });

    test('the hand cannot bring back a row whose kind is off — and its '
        'answer is still there when the kind comes back', () {
      final layers = [layer('a'), layer('ad', mark: keyAd), layer('bg', mark: art)];
      final delta = ExportCelsCutDelta()
          .withLayerOverride(const LayerId('ad'), true)
          .withLayerOverride(const LayerId('bg'), true);
      expect(
        cels(
          layers,
          spec: const CelsExportSpec(kinds: {ExportCelKind.art}),
          delta: delta,
        ),
        ['bg'],
      );
      expect(cels(layers, delta: delta), ['a', 'ad', 'bg']);
    });

    test('the list: a row of a kind that is written, and a folder holding '
        'one — never the paper, the camera or an SE row', () {
      final layers = [
        layer('a', folder: 'f'),
        createFolderLayer(id: const LayerId('f'), name: 'F'),
        layer('bg', mark: art, folder: 'g'),
        createFolderLayer(id: const LayerId('g'), name: 'G'),
        layer('ac', attachedTo: 'a', mark: keyAd),
        layer('inst', kind: LayerKind.instruction),
        layer('p', mark: paper),
        layer('se', kind: LayerKind.se),
        layer('cam', kind: LayerKind.camera),
        createFolderLayer(id: const LayerId('empty'), name: 'E'),
      ];
      List<String> listed(CelsExportSpec spec) => [
        for (final each in layers)
          if (exportCelsListsRow(each, layers, spec)) each.id.value,
      ];
      expect(listed(const CelsExportSpec()), ['a', 'f', 'bg', 'g', 'ac']);
      expect(
        listed(const CelsExportSpec(kinds: {ExportCelKind.art})),
        ['bg', 'g'],
        reason: 'a kind that is off takes its rows — and the folder that '
            'held only those — out of the list',
      );
      expect(
        listed(const CelsExportSpec(kinds: withDirection)),
        ['a', 'f', 'bg', 'g', 'ac', 'inst'],
      );
      expect(
        listed(const CelsExportSpec(label: keyAd, base: false)),
        ['a', 'f', 'bg', 'g', 'ac'],
        reason: 'a FILTER turns a row off where it stands — it stays listed',
      );
    });
  });

  test('the timeline\'s eye does NOT count — a hidden row, or a row inside a '
      'hidden folder, exports like any other', () {
    // 유저 2026-09-09: 「타임라인에서 비지블off면 출력에 off인채로 있는데,
    // 그게아니라 상태에 따라 안바뀌도록」 — the eye is view state; the
    // filters decide. (Until this day the eye did count, folder and all.)
    final layers = [
      layer('a', folder: 'f'),
      createFolderLayer(
        id: const LayerId('f'),
        name: 'F',
      ).copyWith(isVisible: false),
      layer('dark', isVisible: false),
      layer('c'),
    ];
    expect(cels(layers), ['a', 'dark', 'c']);
  });

  test('delta wins last: force-exclude a rule pick, force-include a hidden '
      'row, never a row that holds no cel', () {
    final layers = [
      layer('a'),
      layer('hidden', isVisible: false),
      layer('se', kind: LayerKind.se),
    ];
    final delta = ExportCelsCutDelta()
        .withLayerOverride(const LayerId('a'), false)
        .withLayerOverride(const LayerId('hidden'), true)
        .withLayerOverride(const LayerId('se'), true);
    expect(cels(layers, delta: delta), ['hidden']);
  });

  test('the delta beats the filters too — a base forced in with 기준 off '
      'exports', () {
    final layers = [layer('a'), layer('inst', kind: LayerKind.instruction)];
    final selection = resolve(
      layers,
      spec: const CelsExportSpec(
        kinds: withDirection,
        base: false,
        attach: false,
      ),
      delta: ExportCelsCutDelta().withLayerOverride(const LayerId('a'), true),
    );
    expect(ids(selection.celLayers), ['a', 'inst']);
  });
}
