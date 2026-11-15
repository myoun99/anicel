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
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
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

  /// Pictures whose frames stack cel a — under a plugin's chain where
  /// [plugin] says — counting each stacking in [stacked], under the stamp
  /// [stamp] answers; [paper] is the page's.
  ({FramePictures pictures, List<int> stacked}) picturesOf({
    required Object? Function() stamp,
    bool Function()? plugin,
    ProjectBackground Function()? paper,
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
          CompositeLeaf(
            CanvasLayerImageRequest(
              frameKey: keyOf('a'),
              opacity: 1,
              effects: [
                if (plugin?.call() ?? false)
                  ResolvedLayerEffect(
                    kind: EffectKind.plugin,
                    plugin: shiftingFxPluginDescription,
                    values: const [],
                    run: fxPluginRunOf(ShiftingFxPlugin()),
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
      countsTheMove(() => cels.restoreBaked({}));
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

  test('a frame whose chain runs a plugin is stacked at every asking — its '
      'key signs the run, which no stamp follows', () {
    final cut = aCut();
    final (:pictures, :stacked) = picturesOf(
      stamp: () => 'still',
      plugin: () => true,
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
    final (:pictures, :stacked) = picturesOf(
      stamp: () => 'still',
      plugin: () => plugin,
    );
    pictures.keyOf(at(cut, 0));

    // The tree reads a plugin now, and the stamp did not move.
    plugin = true;

    expect(() => pictures.keyOf(at(cut, 0)), throwsStateError);
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
