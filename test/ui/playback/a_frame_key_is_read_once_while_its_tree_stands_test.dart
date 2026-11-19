import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart' show defaultCelTileSize;
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/fx_plugin_run.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart'
    show debugCompositeTreesLaid;
import 'package:anicel/src/services/playback/cut_composite_structure.dart';
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_pictures.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/a_fill_on_a_session.dart';
import '../../helpers/a_plugin_that_shifts.dart';
import '../../helpers/cels_parked_cold.dart';
import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/fx_plugin_file.dart';

/// 🔬H57 (11-14, S5_BA cut 352 · 68 rows, windowless): the walk, the
/// ruler's bar and the weighing asked every frame's standing, and each
/// asking stacked the frame's tree and signed it anew — 42% of the UI
/// thread's samples while the frames refilled after a stroke. A frame's key
/// is read once while what its tree reads stays (`FramePictures.treeStamp`)
/// and its cut, its page and every cel it stacks stand as they did.
void main() {
  opensTheEnginesScreens();
  const tileSize = defaultCelTileSize;
  const canvasSize = CanvasSize(width: 2 * tileSize, height: 2 * tileSize);

  Cut aCut() => Cut(
    id: const CutId('c'),
    name: 'c',
    duration: 4,
    canvasSize: canvasSize,
    layers: const [],
  );

  BrushFrameKey keyOf(String cel) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(cel),
  );

  void ink(BrushFrameStore store, String cel, CanvasPoint at) => inkCelIn(
    store,
    keyOf(cel),
    canvasSize: canvasSize,
    at: at,
    size: 2,
    tipShape: BrushTipShape.square,
    tileSize: tileSize,
  );

  late BrushFrameStore cels;
  late LayerFrameImageCache images;
  setUp(() {
    // The suite stacks every tree handed back anew to check it
    // (flutter_test_config.dart): these count the stackings themselves.
    final checked = debugCheckFrameStanding;
    expect(checked, isTrue, reason: 'flutter_test_config.dart turns it on');
    debugCheckFrameStanding = false;
    addTearDown(() => debugCheckFrameStanding = checked);
    cels = BrushFrameStore();
    ink(cels, 'a', CanvasPoint(x: 1, y: 1));
    images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
  });

  /// Pictures whose frames stack cel a — or each of [rows] — under a
  /// plugin's step run as [run] answers, where it answers one — counting
  /// each stacking in [stacked], under the stamp [stamp] answers; [paper]
  /// is the page's.
  ({FramePictures pictures, List<int> stacked}) picturesOf({
    required Object? Function() stamp,
    FxPluginRun? Function()? run,
    ProjectBackground Function()? paper,
    List<String> rows = const ['a'],
  }) {
    final stacked = [0];
    final store = aStoreOfPictures();
    addTearDown(store.dispose);
    final pictures = FramePictures(
      store: store,
      layerImages: images,
      stackOf: (picture) {
        stacked[0] += 1;
        return [
          for (final row in rows)
            CompositeLeaf(
              CanvasLayerImageRequest(
                frameKey: keyOf(row),
                opacity: 1,
                effects: [
                  if (run?.call() case final run?)
                    ResolvedLayerEffect(
                      kind: EffectKind.plugin,
                      plugin: shiftingFxPluginDescription,
                      values: const [],
                      run: run,
                    ),
                ],
              ),
            ),
        ];
      },
      pageOf: (picture) => (
        canvasSize: picture.cut.canvasSize,
        pasteboardReach: PasteboardReach.whole,
        paintPaper: picture.paintPaper,
        paperBackground:
            paper?.call() ?? ProjectBackground.defaultBackground,
      ),
      treeStamp: () => stamp() ?? Object(),
    );
    return (pictures: pictures, stacked: stacked);
  }

  DemandedPicture at(Cut cut, int frame) => (
    cut: cut,
    frameIndex: frame,
    paintPaper: true,
    ghosts: FrameGhosts.none,
  );

  test('a frame\'s tree is stacked once while nothing it reads moves — the '
      'walk, the bar and the weighing ask one reading', () {
    final cut = aCut();
    final (:pictures, :stacked) = picturesOf(stamp: () => 'still');

    final key = pictures.keyOf(at(cut, 0));
    pictures.standingOf(at(cut, 0));
    pictures.has(at(cut, 0));
    pictures.partsToMake(at(cut, 0));

    expect(stacked.single, 1);
    expect(pictures.keyOf(at(cut, 0)), key);
    pictures.keyOf(at(cut, 1));
    expect(stacked.single, 2, reason: 'each frame its own reading');
  });

  // 🔬The band asked the frames it shows at every landing, and each
  // asking read every row's cel again — 8,179 readings, 77 µs each, while
  // S5_BA cut 352's band filled (11-15, main PC, debug).
  test('🚨a frame asked again while nothing its cels move with moved reads '
      'none of them again', () {
    final cut = aCut();
    final (:pictures, :stacked) = picturesOf(stamp: () => 'still');

    pictures.keyOf(at(cut, 0));
    pictures.keyOf(at(cut, 0));
    pictures.has(at(cut, 0));

    expect(stacked.single, 1);
    expect(pictures.celsReadAgain, 0);
  });

  // 🔬Card an-eye-toggle-holds-the-ui-thread (11-18): every frame a ruler's
  // bar keyed after an edit asked each cel's drawn-ness and revision of the
  // store twice — once for the key, once for what is kept of it.
  test('a frame read anew asks each cel it stacks once whether it is drawn '
      'and at what revision', () {
    final asked = _CelsAsked();
    ink(asked, 'a', CanvasPoint(x: 1, y: 1));
    images = LayerFrameImageCache(frameStore: asked);
    addTearDown(images.dispose);
    final (:pictures, :stacked) = picturesOf(stamp: () => 'still');
    asked
      ..drawn = 0
      ..revisions = 0;

    final key = pictures.keyOf(at(aCut(), 0));

    expect(stacked.single, 1);
    expect(asked.drawn, 1);
    expect(asked.revisions, 1);
    expect(
      key.signature.nodes,
      hasLength(1),
      reason: '⛔CONTROL: the drawn cel signs the key',
    );
  });

  test('a cel another frame stacks moving reads this frame\'s cels once '
      'more — and they stand, and are not read again after', () {
    final cut = aCut();
    final (:pictures, :stacked) = picturesOf(stamp: () => 'still');
    final key = pictures.keyOf(at(cut, 0));

    ink(cels, 'b', CanvasPoint(x: 5, y: 5));
    expect(pictures.keyOf(at(cut, 0)), key);
    pictures.keyOf(at(cut, 0));

    expect(stacked.single, 1);
    expect(pictures.celsReadAgain, 1);
  });

  // A copy kept at its source's size gives its cel a revision and announces
  // no pixels (the store's `_keepCopy`): a key kept under that bump alone
  // would go on naming the cel it was.
  test('🚨a cel another was copied onto is read anew — its revision moved '
      'with no pixels announced', () {
    final cut = aCut();
    ink(cels, 'b', CanvasPoint(x: 5, y: 5));
    parkCold(cels, {
      keyOf('a'): cels.bakedSurfaceOrNull(keyOf('a'))!,
      keyOf('b'): cels.bakedSurfaceOrNull(keyOf('b'))!,
    });
    final (:pictures, :stacked) = picturesOf(stamp: () => 'still');
    final before = pictures.keyOf(at(cut, 0));
    final pixels = cels.celPixelRevision.value;

    cels.copyCel(keyOf('b'), keyOf('a'));
    expect(cels.celPixelRevision.value, pixels, reason: '⛔premise: no bump');
    final after = pictures.keyOf(at(cut, 0));

    expect(stacked.single, 2);
    expect(after, isNot(before));
  });

  group("every move of a cel's revision moves the store's count — what a "
      "kept key's cels are read again under", () {
    /// [move] moves a revision of cel a, b or c — and the count with it.
    void countsTheMove(void Function() move) {
      final keys = [keyOf('a'), keyOf('b'), keyOf('c')];
      final revisions = [for (final key in keys) cels.sourceRevisionOf(key)];
      final counted = cels.revisionsMoved;

      move();

      final now = [for (final key in keys) cels.sourceRevisionOf(key)];
      expect(now, isNot(revisions), reason: '⛔premise: a revision moved');
      expect(cels.revisionsMoved, isNot(counted));
    }

    test('an edit', () {
      countsTheMove(() => ink(cels, 'b', CanvasPoint(x: 5, y: 5)));
    });

    test('a cel moved to another key', () {
      countsTheMove(() => cels.rekeyFrames([(keyOf('a'), keyOf('c'))]));
    });

    test('a cel another was copied onto', () {
      ink(cels, 'b', CanvasPoint(x: 5, y: 5));
      parkCold(cels, {
        keyOf('a'): cels.bakedSurfaceOrNull(keyOf('a'))!,
        keyOf('b'): cels.bakedSurfaceOrNull(keyOf('b'))!,
      });

      countsTheMove(() => cels.copyCel(keyOf('b'), keyOf('a')));
    });

    test('every cel let go as the store is laid anew with none', () {
      countsTheMove(() => parkCold(cels, {}));
    });
  });

  // A crop keeps a hot cel's revision and stores it anew at the new size
  // (the store's resizeBakedSurfaces): only the crossing it announces says
  // the cel is drawn no more.
  test('🚨a cel a crop leaves empty is read anew — its revision stands, '
      'the content of the store moved', () {
    final cut = aCut();
    parkCold(cels, {});
    ink(cels, 'a', CanvasPoint(x: 2 * tileSize - 3, y: 2 * tileSize - 3));
    final (:pictures, :stacked) = picturesOf(stamp: () => 'still');
    final before = pictures.keyOf(at(cut, 0));
    final revision = cels.sourceRevisionOf(keyOf('a'));
    final moved = cels.revisionsMoved;

    // Its pasteboard, a canvas wide on each edge, reaches no tile but the
    // first.
    cels.resizeBakedSurfaces(
      const CanvasSize(width: 8, height: 8),
      cutId: const CutId('c'),
    );
    expect(cels.celHasRenderableContent(keyOf('a')), isFalse);
    expect(cels.sourceRevisionOf(keyOf('a')), revision, reason: '⛔premise');
    expect(cels.revisionsMoved, moved, reason: '⛔premise');
    final after = pictures.keyOf(at(cut, 0));

    expect(stacked.single, 2);
    expect(after, isNot(before), reason: 'a is drawn no more');
  });

  // The making notes such a cel as drawing nothing, with no revision and
  // no content of the store moved: only that note says it is no part of
  // the frame.
  testWidgets('🚨a cel the making found recorded at another canvas size is '
      'read anew — and the key leaves it out', (tester) async {
    await tester.runAsync(() async {
      final cut = Cut(
        id: const CutId('c'),
        name: 'c',
        duration: 4,
        canvasSize: const CanvasSize(width: 4 * tileSize, height: 4 * tileSize),
        layers: const [],
      );
      final (:pictures, stacked: _) = picturesOf(stamp: () => 'still');
      final before = pictures.keyOf(at(cut, 0));
      final moved = (cels.revisionsMoved, cels.celContentRevision.value);

      expect(await pictures.make(at(cut, 0), shouldAbort: () => false), isTrue);
      expect(
        (cels.revisionsMoved, cels.celContentRevision.value),
        moved,
        reason: '⛔premise',
      );
      final after = pictures.keyOf(at(cut, 0));

      expect(after, isNot(before), reason: 'a is no part of it');
    });
  });

  // 🔬Card baking-ahead-allocates-the-ui-isolate-into-gc (11-19, S5_BA cut
  // 352 copy · 37 rows): the walk weighed, read in and made each frame from
  // a tree it stacked again, and the making signed it again once drawn.
  testWidgets('the walk weighs, reads in and makes a frame from the one '
      'tree its key was read from — and lays it under that key', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final cut = aCut();
      final (:pictures, :stacked) = picturesOf(stamp: () => 'still');
      pictures.keyOf(at(cut, 0));
      final signed = pictures.keysSigned;

      await pictures.bytesToMake(at(cut, 0));
      await pictures.readIn(at(cut, 0));
      final made = await pictures.make(at(cut, 0), shouldAbort: () => false);

      expect(made, isTrue, reason: '⛔premise');
      expect(stacked.single, 1);
      expect(pictures.keysSigned, signed);
      expect(
        pictures.has(at(cut, 0)),
        isTrue,
        reason: '⛔CONTROL: laid under the key it is asked by',
      );
    });
  });

  // The drawing notes a cel recorded at another canvas size as drawing
  // nothing, and moves no revision: only that note says the frame is laid
  // without it.
  testWidgets('🚨a frame whose making finds a cel drawing nothing is laid '
      'under the key read once it is drawn — not the one read before', (
    tester,
  ) async {
    await tester.runAsync(() async {
      inkCelIn(
        cels,
        keyOf('b'),
        canvasSize: const CanvasSize(width: 4 * tileSize, height: 4 * tileSize),
        at: CanvasPoint(x: 1, y: 1),
        size: 2,
        tipShape: BrushTipShape.square,
        tileSize: tileSize,
      );
      final cut = aCut();
      final (:pictures, stacked: _) = picturesOf(
        stamp: () => 'still',
        rows: const ['a', 'b'],
      );
      final before = pictures.keyOf(at(cut, 0));
      expect(before.signature.nodes, hasLength(2), reason: '⛔premise');

      final made = await pictures.make(at(cut, 0), shouldAbort: () => false);

      expect(made, isTrue, reason: '⛔premise');
      expect(pictures.keyOf(at(cut, 0)).signature.nodes, hasLength(1));
      expect(pictures.has(at(cut, 0)), isTrue);
    });
  });

  test('LIVENESS — a stamp that is never the same stacks the frame at every '
      'asking, as the rig did before it said one', () {
    final cut = aCut();
    final (:pictures, :stacked) = picturesOf(stamp: () => null);

    pictures.keyOf(at(cut, 0));
    pictures.standingOf(at(cut, 0));
    pictures.has(at(cut, 0));

    expect(stacked.single, 3);
  });

  test('a stamp that moves stacks every frame anew', () {
    final cut = aCut();
    var news = 0;
    final (:pictures, :stacked) = picturesOf(stamp: () => news);

    pictures.keyOf(at(cut, 0));
    news += 1;
    pictures.keyOf(at(cut, 0));

    expect(stacked.single, 2);
  });

  test('a cel that moves is read anew, and the key moves with it', () {
    final cut = aCut();
    final (:pictures, :stacked) = picturesOf(stamp: () => 'still');
    final before = pictures.keyOf(at(cut, 0));

    ink(cels, 'a', CanvasPoint(x: 3, y: 3));
    final after = pictures.keyOf(at(cut, 0));

    expect(stacked.single, 2);
    expect(after, isNot(before), reason: 'the cel\'s revision signs it');
  });

  test('a cel that will not read is read anew — its revision stands, and '
      'the key leaves it out', () {
    final cut = aCut();
    final (:pictures, :stacked) = picturesOf(stamp: () => 'still');
    final before = pictures.keyOf(at(cut, 0));

    images.unreadable.note(keyOf('a'));
    final after = pictures.keyOf(at(cut, 0));

    expect(stacked.single, 2);
    expect(after, isNot(before), reason: 'the picture is made without it');
  });

  test('a cut written anew is read anew — the same id, another cut', () {
    final (:pictures, :stacked) = picturesOf(stamp: () => 'still');

    pictures.keyOf(at(aCut(), 0));
    pictures.keyOf(at(aCut(), 0));

    expect(stacked.single, 2);
  });

  test('a page that moves is read anew — its paper signs the key', () {
    final cut = aCut();
    var paper = ProjectBackground.defaultBackground;
    final (:pictures, :stacked) = picturesOf(
      stamp: () => 'still',
      paper: () => paper,
    );
    final before = pictures.keyOf(at(cut, 0));

    paper = const ProjectBackground.color(0xFF102030);
    final after = pictures.keyOf(at(cut, 0));

    expect(stacked.single, 2);
    expect(after, isNot(before));
  });

  // 🔬The bar read its window again at each landing, and a frame whose
  // chain runs a plugin was stacked anew at every asking — 1.1–1.3 s of
  // the UI thread a band on S5_BA cut 352 with an invert on a row
  // (11-17, main PC, a-plugin-step-is-keyed-by-a-moment-it-may-not-read).
  test('🚨a frame whose chain runs a plugin is stacked once while its run '
      'stands as bound — the walk, the bar and the weighing ask one '
      'reading', () {
    final cut = aCut();
    final run = fxPluginRunOf(ShiftingFxPlugin());
    final (:pictures, :stacked) = picturesOf(
      stamp: () => 'still',
      run: () => run,
    );

    final key = pictures.keyOf(at(cut, 0));
    pictures.standingOf(at(cut, 0));
    pictures.has(at(cut, 0));

    expect(stacked.single, 1);
    expect(pictures.keyOf(at(cut, 0)), key);
  });

  test('a frame whose plugin\'s run stands no more is stacked anew — its '
      'key signs the run bound now', () {
    final cut = aCut();
    final runner = ShiftingFxPlugin();
    var run = fxPluginRunOf(runner);
    final (:pictures, :stacked) = picturesOf(
      stamp: () => 'still',
      run: () => run,
    );
    final before = pictures.keyOf(at(cut, 0));

    runner.close();
    run = fxPluginRunOf(ShiftingFxPlugin());
    final after = pictures.keyOf(at(cut, 0));

    expect(stacked.single, 2);
    expect(after, isNot(before), reason: 'another runner signs it');
  });

  test('a frame whose plugin\'s run reads rows its binding says moved is '
      'stacked anew', () {
    final cut = aCut();
    var rowsStand = true;
    final run = FxPluginRun(
      runner: ShiftingFxPlugin(),
      moment: (frameIndex: 0, time: 0, frameRate: 24, scale: 1),
      rows: {const LayerId('m'): null},
      rowsAsBound: () => rowsStand,
    );
    final (:pictures, :stacked) = picturesOf(
      stamp: () => 'still',
      run: () => run,
    );

    pictures.keyOf(at(cut, 0));
    pictures.keyOf(at(cut, 0));
    expect(stacked.single, 1);
    rowsStand = false;
    pictures.keyOf(at(cut, 0));

    expect(stacked.single, 2);
  });

  test('LIVENESS — a frame whose plugin\'s run cannot say it stands is '
      'stacked at every asking, as every such frame was', () {
    final cut = aCut();
    final run = fxPluginRunOf(
      ShiftingFxPlugin(),
      rows: {const LayerId('m'): null},
    );
    final (:pictures, :stacked) = picturesOf(
      stamp: () => 'still',
      run: () => run,
    );

    pictures.keyOf(at(cut, 0));
    pictures.keyOf(at(cut, 0));

    expect(stacked.single, 2);
  });

  test('the suite\'s check throws where an input of the tree moves past the '
      'stamp', () {
    debugCheckFrameStanding = true;
    final cut = aCut();
    var plugin = false;
    final run = fxPluginRunOf(ShiftingFxPlugin());
    final (:pictures, :stacked) = picturesOf(
      stamp: () => 'still',
      run: () => plugin ? run : null,
    );
    pictures.keyOf(at(cut, 0));

    // The tree reads a plugin now, and the stamp did not move.
    plugin = true;

    expect(() => pictures.keyOf(at(cut, 0)), throwsStateError);
  });

  // 🔬Card an-eye-toggle-holds-the-ui-thread (11-18): after every edit a
  // ruler's bar laid each frame's tree where the cut's spans were found,
  // and again where the span's picture was keyed.
  testWidgets('a frame whose span the bar found is keyed from the tree that '
      'found it', (tester) async {
    const row = LayerId('a');
    final session = sessionOfRows(
      [drawingRow('a')],
      canvasSize: canvasSize,
      cels: const {},
      standOn: row,
    );
    final cut = session.requireActiveCut;
    inkCel(
      session,
      session.brushFrameKeyForCut(cut, row, theCel),
      canvasSize: canvasSize,
      at: CanvasPoint(x: 1, y: 1),
      size: 2,
    );
    final [span, ...] = compositeStructureSpansIn(cut, start: 0, end: 1);
    final before = debugCompositeTreesLaid;

    final key = session.playbackRig.framePictures.keyOf(at(cut, span.start));

    expect(debugCompositeTreesLaid - before, 0);
    expect(
      key.signature.nodes,
      isNotEmpty,
      reason: '⛔CONTROL: the frame stacks its row',
    );
  });

  testWidgets('a plugin installed under a frame that names it reads the '
      'frame anew — a word to every screen, which no write to the project '
      'carries', (tester) async {
    final plugins = await installedShiftingFxPlugin(tester);
    await tester.runAsync(
      () => plugins.uninstall(shiftingFxPluginDescription.id),
    );
    const row = LayerId('a');
    final session = sessionOfRows(
      [
        drawingRow('a').copyWith(effects: [shiftingFxPluginLayerEffect()]),
      ],
      canvasSize: canvasSize,
      cels: const {},
      standOn: row,
      fxPlugins: plugins,
    );
    final cut = session.requireActiveCut;
    inkCel(
      session,
      session.brushFrameKeyForCut(cut, row, theCel),
      canvasSize: canvasSize,
      at: CanvasPoint(x: 1, y: 1),
      size: 2,
    );
    final pictures = session.playbackRig.framePictures;
    final before = pictures.keyOf(at(cut, 0));

    await tester.runAsync(
      () => plugins.install(
        fxPluginFileOf(shiftingFxPluginDescription),
        confirm: (_, {required replacing}) async => true,
      ),
    );

    expect(
      pictures.keyOf(at(cut, 0)),
      isNot(before),
      reason: 'the device\'s build of it signs the key',
    );
  });
}

/// A store that counts how often a cel's drawn-ness
/// ([celHasRenderableContent]) and revision ([sourceRevisionOf]) are asked.
final class _CelsAsked extends BrushFrameStore {
  int drawn = 0;
  int revisions = 0;

  @override
  bool celHasRenderableContent(BrushFrameKey key) {
    drawn += 1;
    return super.celHasRenderableContent(key);
  }

  @override
  int sourceRevisionOf(BrushFrameKey key) {
    revisions += 1;
    return super.sourceRevisionOf(key);
  }
}
