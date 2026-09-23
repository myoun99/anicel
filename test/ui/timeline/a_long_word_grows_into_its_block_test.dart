/// 🚨THE 30-SECOND DEFAULT IS NOT THIS FILE'S BOUND (2026-09-16).
///
/// These cases raster tiles for real and wait for the landing off-frame.
/// Alone they are slow but green; under load — another lane gating on the
/// same machine — they cross the test package's DEFAULT 30s and die with a
/// bare `TimeoutException` that says nothing about what was being waited
/// for. Three landings lost a cycle to that in one evening (i22a, f95,
/// f101), each time with the product perfectly green on the re-run.
///
/// ⛔This is not 「상한을 올려 숨긴다」. The default was never chosen for a
/// rasterising test; the real bound is stated here, and the COST itself —
/// 4m27s for three cases, measured — stays open as its own round
/// (`tile-count-timeout-under-load`).
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_glyph_cache.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_row_run_labels_painter.dart';

import '../../helpers/native_engine_path.dart';
import 'timeline_frame_geometry_probe.dart';

/// 🗣️F-96 (유저 2026-09-12): 「프레임 블록의 텍스트, 프레임 이름은 해당 칸에
/// 존재하는데 왼쪽정렬? 그니까 텍스트 길어지면 해당 칸에서 좌우로 늘어나는데,
/// 그게아니라 해당 칸에서 오른쪽으로 늘어나도록. 그리고 코마 텍스트는 오른쪽에
/// 있는거니까 오른쪽정렬. 해당 칸에서 왼쪽으로 늘어나도록. 결과적으로 텍스트가
/// 길어져도 해당 블록에서 보이게 하고싶음이 목적」.
///
/// A block's name starts at its cell and grows on into the block; its length
/// ends at its last cell and grows back into it — on every pass that draws
/// them: the classic foreground, a painted window that begins after the name,
/// the baked tile after the name's own, and the storyboard panel's comma.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const cell = 24.0;
  const crossExtent = 28.0;
  const longName = 'A-123456789';

  TimelineCellExposureState stateFor(Layer layer, int frameIndex) {
    if (layer.timeline[frameIndex]?.isDrawing ?? false) {
      return TimelineCellExposureState.drawingStart;
    }
    if (coveringDrawingBlockAt(layer.timeline, frameIndex) != null) {
      return TimelineCellExposureState.held;
    }
    return TimelineCellExposureState.uncovered;
  }

  // A four-cell block from frame 2, named wider than its first cell.
  final layer = Layer(
    id: const LayerId('layer-a'),
    name: 'A',
    frames: [Frame(id: const FrameId('f1'), duration: 1, strokes: const [])],
    timeline: {2: const TimelineExposure.drawing(FrameId('f1'), length: 4)},
  );

  TimelineRowCellsPainter cellsPainter({
    TimelineGridTileStore? store,
    ValueNotifier<int>? bucket,
    double viewport = 0,
  }) => TimelineRowCellsPainter(
    layer: layer,
    geometry: testFrameGeometry(
      frameCellExtent: cell,
      frameEndIndexExclusive: 40,
    ),
    crossAxisExtent: crossExtent,
    exposureStateForLayer: stateFor,
    frameNameForLayer: (_, frameIndex) => frameIndex == 2 ? longName : null,
    colorScheme: const ColorScheme.dark(),
    baseTextStyle: const TextStyle(fontSize: 11),
    tileStore: store,
    substrateGeneration: 'g1',
    windowBucket: bucket,
    viewportMainExtent: viewport,
  );

  /// The name's laid-out width, through the painter's own style.
  double nameWidth(TimelineRowCellsPainter painter) {
    final model = painter.cellModelAt(2);
    return timelineGlyphPainter(model.glyph, painter.glyphStyleFor(model))
        .width;
  }

  test('a name wider than its cell starts at the cell and grows into its '
      'block', () {
    final painter = cellsPainter();
    expect(painter.cellModelAt(2).glyph, longName, reason: 'fixture');
    expect(nameWidth(painter), greaterThan(cell), reason: 'fixture');
    final spy = _Spy();
    painter.paint(spy, const Size(cell * 40, crossExtent));
    // In frame order: the X opening the empty run at 0, then the name.
    expect(spy.texts.length, greaterThanOrEqualTo(2), reason: 'fixture');
    expect(
      spy.texts[1].dx,
      closeTo(painter.cellRectFor(2).left, 0.5),
      reason: 'the name starts at its own cell instead of spilling back '
          'over the cells before its block',
    );
    // B (유저 2026-09-24): 「이름은 블록안에서만」 — and it ends inside it.
    expect(
      spy.boxes[1].right,
      lessThanOrEqualTo(painter.cellRectFor(6).left + 0.5),
      reason: 'the name stops at its block\'s end instead of running on '
          'over the cells after it',
    );
  });

  test('a name that starts before the painted window still shows the part '
      'that grows into it', () {
    final bucket = ValueNotifier<int>(2);
    addTearDown(bucket.dispose);
    final painter = cellsPainter(bucket: bucket, viewport: 96);
    final window = painter.visibleFrameWindow();
    expect(window.startIndex, greaterThan(2), reason: 'fixture');
    expect(
      painter.cellRectFor(2).left + nameWidth(painter),
      greaterThan(painter.cellRectFor(window.startIndex).left),
      reason: 'fixture: the name reaches into the window',
    );
    final spy = _Spy();
    painter.paint(spy, const Size(cell * 40, crossExtent));
    expect(
      spy.texts.map((offset) => offset.dx),
      anyElement(closeTo(painter.cellRectFor(2).left, 0.5)),
      reason: 'the window lays the word that grows into it',
    );
  });

  test('a name that grows past its tile is baked into the next tile '
      'too', () async {
    final dllPath = nativeEngineLibraryPathOrNull();
    if (dllPath == null) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;
    final store = TimelineGridTileStore.instance..clear();
    addTearDown(() {
      QaNativeEngine.debugResetForTests();
      debugQaEngineLibraryPathOverride = null;
      QaNativeEngine.debugForceDartFallback = false;
      store.clear();
    });
    final painter = cellsPainter(store: store);
    var landings = 0;
    void count() => landings += 1;
    store.revision.addListener(count);
    addTearDown(() => store.revision.removeListener(count));

    // At 24px a tile is four cells: the name lives in [0, 4) and runs on
    // through [4, 8) — row pixels [48, 48 + width).
    ui.Image? nextTile() => store.tileFor(
      painter: painter,
      spanStartIndex: 4,
      spanEndIndexExclusive: 8,
      devicePixelRatio: 1.0,
    );
    expect(
      painter.cellRectFor(2).left + nameWidth(painter),
      greaterThan(painter.cellRectFor(4).left + 22),
      reason: 'fixture: the name covers the first cell of the next tile',
    );
    expect(nextTile(), isNull, reason: 'fixture: the store starts cold');
    while (landings == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final image = nextTile();
    expect(image, isNotNull, reason: 'fixture: the tile landed');
    final bytes = (await image!.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    int sumAt(int x, int y) {
      final i = (y * image.width + x) * 4;
      return bytes.getUint8(i) + bytes.getUint8(i + 1) + bytes.getUint8(i + 2);
    }

    // Frame 4 is a held cell of the block: paper, with a seam at each end.
    // Between the seams and above the row's bottom seam, only the name can
    // put ink on it (the X of the empty run sits over frame 6).
    final paper = sumAt(12, 25);
    var inked = 0;
    for (var y = 6; y < 22; y += 1) {
      for (var x = 2; x < 22; x += 1) {
        if ((sumAt(x, y) - paper).abs() > 60) {
          inked += 1;
        }
      }
    }
    expect(
      inked,
      greaterThan(4),
      reason: 'the part of the name past its own tile is baked into the '
          'next one instead of stopping at the tile edge',
    );
  });

  test('a length wider than its last cell ends at that cell and grows back '
      'into the block', () {
    const smallCell = 12.0;
    final painter = TimelineRowRunLabelsPainter(
      baseTextStyle: const TextStyle(fontSize: 14),
      layer: layer,
      geometry: testFrameGeometry(
        frameCellExtent: smallCell,
        frameEndIndexExclusive: 40,
      ),
      crossAxisExtent: crossExtent,
      showSeconds: true,
      countingBase: 24,
    );
    final label = painter.runLabels().single;
    final width = timelineGlyphPainter(label.text, painter.labelStyle).width;
    expect(width, greaterThan(smallCell), reason: 'fixture');
    final spy = _Spy();
    painter.paint(spy, const Size(smallCell * 40, crossExtent));
    const blockEnd = smallCell * 6;
    expect(
      spy.texts.single.dx + width,
      closeTo(blockEnd, 0.001),
      reason: 'the length ends at its last cell instead of running past '
          'the block it counts',
    );
  });

  test('the storyboard panel\'s comma asks the same law', () {
    final source = File(
      'lib/src/ui/storyboard_cut_blocks_painter.dart',
    ).readAsStringSync();
    expect(
      source,
      isNot(contains('lastCellCentre - glyph.width / 2')),
      reason: 'the comma no longer centres on its last cell by hand',
    );
    expect(source, contains('timelineBlockWordLayout('));
    expect(
      source,
      contains('growth: TimelineBlockWordGrowth.towardBlockStart'),
      reason: 'a count grows back into its panel, as the run label does',
    );
  });
}

/// Records the box each paragraph is PAINTED in, following the transforms —
/// a word narrowed into its block (B) is drawn at the origin of a scaled
/// canvas, so its offset alone says nothing about where it lands.
class _Spy implements Canvas {
  final boxes = <Rect>[];
  final _saved = <Matrix4>[];
  var _transform = Matrix4.identity();

  List<Offset> get texts => [for (final box in boxes) box.topLeft];

  @override
  void save() => _saved.add(_transform.clone());

  @override
  void restore() => _transform = _saved.removeLast();

  @override
  void translate(double dx, double dy) =>
      _transform = _transform.multiplied(Matrix4.translationValues(dx, dy, 0));

  @override
  void scale(double sx, [double? sy]) => _transform = _transform.multiplied(
    Matrix4.diagonal3Values(sx, sy ?? sx, 1),
  );

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) => boxes.add(
    MatrixUtils.transformRect(
      _transform,
      offset & Size(paragraph.maxIntrinsicWidth, paragraph.height),
    ),
  );

  @override
  int getSaveCount() => _saved.length + 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
