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

/// The Cels tab's row set (v3, 2026-09-09): ONE colour label, a take (or
/// 「최신」), the four presets, paper applied rather than exported, 미술
/// added by a switch — and the cut's hand delta last.
void main() {
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
    expect(resolve(layers).instructionLayers, isEmpty);
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
      '시트 keeps, of those, the ones on the sheet — and 디렉션 is an addition',
      () {
    // 유저 2026-09-09: 「단일선택이 아니라 중첩가능이야 … 진짜 여러 항목이
    // 필터로 작동하는거지 … 디렉션은 선택항목말고 추가항목에」.
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

    expect(resolve(layers).instructionLayers, isEmpty);
    final added = resolve(layers, spec: const CelsExportSpec(addDirection: true));
    expect(
      ids(added.celLayers),
      ['a', 'ac', 'b', 'bf'],
      reason: 'an addition takes nothing away',
    );
    expect(ids(added.instructionLayers), ['inst']);
    expect(
      resolve(
        layers,
        spec: const CelsExportSpec(addDirection: true, sheetOnly: true),
      ).instructionLayers.map((layer) => layer.id.value),
      ['inst'],
      reason: 'the direction row is on the sheet by default',
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

  test('미술 추가: art rows join under any label; without it they stay out', () {
    final layers = [layer('a'), layer('bg', mark: art)];
    expect(cels(layers), ['a']);
    expect(cels(layers, spec: const CelsExportSpec(addArt: true)), ['a', 'bg']);
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
      spec: const CelsExportSpec(base: false, attach: false, addDirection: true),
      delta: ExportCelsCutDelta().withLayerOverride(const LayerId('a'), true),
    );
    expect(ids(selection.celLayers), ['a']);
    expect(ids(selection.instructionLayers), ['inst']);
  });
}
