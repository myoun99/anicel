import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/app_clipboard.dart';
import 'package:anicel/src/ui/session/frame_clipboard.dart';
import 'package:anicel/src/ui/session/layer_clipboard.dart';
import 'package:anicel/src/ui/session/project_file_door.dart';

import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/opened_session.dart';
import '../../helpers/project_scratch_folder.dart';
import '../../helpers/staged_carry.dart';

/// 🚨I-7 (유저 2026-09-26): 「탭사이에 복사나 붙여넣기 뭐든 가능. 앱 전체에
/// 하나. 레이어 id가 다른거?라던가 id늘리게한다던가 알아서 조심하고.」
///
/// The answer they picked: the last copy pastes in ANY open project; into
/// another project it pastes independent — cels of its own, ids that project
/// mints, the pictures with them — and a LINKED paste stays in the project
/// the copy came from, because a link is 「the same cel」.
///
/// ⚠️Every fixture here is two DEFAULT projects, and that is the point: they
/// share every id a default project is born with (the project, its cut, its
/// rows), the way two files that began as one do.
///
/// The boards the verbs live in — named so `tool/mutation_run.dart` runs
/// this file for them.
FrameClipboard frameBoardOf(EditorSessionManager session) => session.clipboard;
LayerClipboard layerBoardOf(EditorSessionManager session) =>
    session.layerClipboard;

void main() {
  late AppClipboard clipboard;
  setUp(() => clipboard = AppClipboard());

  EditorSessionManager open([EditorSessionManager? from]) {
    final session = EditorSessionManager(
      initialProject: from?.repository.requireProject() ?? createDefaultProject(),
      appClipboard: clipboard,
    );
    addTearDown(session.dispose);
    return session;
  }

  Object? pictureOf(EditorSessionManager session, Layer layer, Frame cel) =>
      session.renderCaches.brushFrameStore.bakedSurfaceOrNull(
        session.brushFrameKeyForCut(session.requireActiveCut, layer.id, cel.id),
      );

  Layer rowOf(EditorSessionManager session, LayerId id) =>
      session.requireActiveCut.layers.firstWhere((layer) => layer.id == id);

  group('FRAMES', () {
    test('copied in one project, they paste into ANOTHER as cels of its own '
        '— a new id, the picture with it, and the source left as it was', () {
      final a = open();
      final b = open();
      drawOnCurrentFrame(a);
      final row = a.activeLayer!;
      final cel = a.selectedFrame!;
      final picture = pictureOf(a, row, cel);
      expect(picture, isNotNull, reason: 'CONTROL: the source has ink');
      a.copyFrameAtCurrentFrame();

      final target = b.activeLayer!;
      final before = {for (final frame in target.frames) frame.id};
      expect(
        b.canPasteIndependentFrameAtCurrentFrame,
        isTrue,
        reason: 'the copy is the APP\'s — every open project holds it',
      );
      b.pasteIndependentFrameAtCurrentFrame();

      final born = rowOf(b, target.id).frames
          .where((frame) => !before.contains(frame.id))
          .toList();
      expect(born, hasLength(1));
      expect(born.single.id, isNot(cel.id), reason: 'minted HERE');
      expect(
        identical(pictureOf(b, rowOf(b, target.id), born.single), picture),
        isTrue,
        reason: 'the drawing comes with it (F-161: the copy holds it)',
      );
      expect(
        rowOf(a, row.id).frames.map((frame) => frame.id),
        [cel.id],
        reason: 'the project it came from is not touched',
      );

      b.historyManager.undo();
      expect(
        rowOf(b, target.id).frames.map((frame) => frame.id).toSet(),
        before,
        reason: 'one undo step, in the project it landed in',
      );
    });

    test('a LINKED paste stays in the project the copy came from — the same '
        'row id in another project is another row', () {
      final a = open();
      final b = open();
      drawOnCurrentFrame(a);
      a.copyFrameAtCurrentFrame();
      expect(
        a.canPasteLinkedFrameAtCurrentFrame,
        isTrue,
        reason: 'CONTROL: where it was copied, it links',
      );
      expect(
        b.activeLayer!.id,
        a.activeLayer!.id,
        reason: 'fixture premise: both projects stand on a row of that id',
      );
      expect(b.canPasteLinkedFrameAtCurrentFrame, isFalse);
      expect(
        b.canPasteIndependentFrameAtCurrentFrame,
        isTrue,
        reason: 'it still pastes there — as cels of its own',
      );
    });

    test('what pastes is what was COPIED — a cel of the target project that '
        'carries the copied cel\'s id is another drawing, never the source', () {
      final a = open();
      final se = a.activeTrack.seLayers.first.id;
      a
        ..clearAllSelections()
        ..selectLayer(se)
        ..selectFrameIndex(1);
      a.seEntries.createSeEntryAtCurrentFrame(
        name: 'from A',
        seName: 'A',
        lengthFrames: 2,
      );
      // B begins as A's document, so its entry carries the SAME cel id —
      // then says something else.
      final b = open(a);
      b
        ..clearAllSelections()
        ..selectLayer(se)
        ..selectFrameIndex(1);
      b.seEntries.updateSelectedSeEntry(dialogue: 'from B', seName: 'B');

      a.copyFrameAtCurrentFrame();
      b
        ..clearAllSelections()
        ..selectLayer(se)
        ..selectFrameIndex(8);
      b.pasteIndependentFrameAtCurrentFrame();

      final row = b.activeTrack.seLayers.first;
      final pastedId = row.timeline[8]?.frameId;
      expect(pastedId, isNotNull, reason: 'it landed at the playhead');
      final pasted = row.frames.firstWhere((frame) => frame.id == pastedId);
      expect(pasted.seName, 'A');
      expect(pasted.name, 'from A');
    });
  });

  group('LAYERS', () {
    test('copied in one project, a layer pastes into another under an id '
        'that project mints, with the pictures of its cels', () {
      final a = open();
      final b = open();
      drawOnCurrentFrame(a);
      final row = a.activeLayer!;
      final cel = rowOf(a, row.id).frames.single;
      final picture = pictureOf(a, row, cel);
      a.layerClipboard.copyActiveLayer();

      final before = {for (final layer in b.requireActiveCut.layers) layer.id};
      expect(before, contains(row.id), reason: 'fixture premise: the id is taken');
      b.layerClipboard.pasteLayerFromClipboard();
      final pasted = b.requireActiveCut.layers
          .where((layer) => !before.contains(layer.id))
          .single;
      expect(pasted.frames, hasLength(1));
      expect(
        identical(pictureOf(b, pasted, pasted.frames.single), picture),
        isTrue,
        reason: 'the drawing comes with the layer',
      );
    });
  });

  group('what a copy NAMES in its project comes with it', () {
    /// A project whose first cut ends in a row showing [path].
    Project withAReferenceRow(String path) {
      final base = createDefaultProject();
      final track = base.tracks.first;
      final cut = track.cuts.first;
      final row = Layer(
        id: const LayerId('shows-the-still'),
        name: 'Still',
        frames: const [],
        timeline: const {},
        kind: LayerKind.image,
        mediaReference: MediaReference(assetPath: path),
      );
      return base.copyWith(
        tracks: [
          track.copyWith(
            cuts: [
              cut.copyWith(layers: [...cut.layers, row]),
              ...track.cuts.skip(1),
            ],
          ),
          ...base.tracks.skip(1),
        ],
      );
    }

    Future<({EditorSessionManager a, String path})> aCarriedStill() async {
      final folder = Directory.systemTemp.createTempSync('anicel-clip-media');
      deleteAfterSessionEnds(folder);
      final path = '${folder.path.replaceAll(r'\', '/')}/still.bin';
      File(path).writeAsBytesSync(List<int>.generate(64, (i) => i));
      final a = EditorSessionManager(
        initialProject: withAReferenceRow(path),
        appClipboard: clipboard,
      );
      addTearDown(a.dispose);
      await a.mediaPool.addMediaAssets([path], carried: true);
      expect(stagedCopyIn(a, path), isNotNull, reason: 'fixture: A holds it');
      a.selectLayer(const LayerId('shows-the-still'));
      a.layerClipboard.copyActiveLayer();
      return (a: a, path: path);
    }

    test('a row showing a CARRIED medium pastes into another project with a '
        'carry of THAT project\'s own — its bytes held before anything '
        'records it, from where the source keeps them — and one undo takes '
        'the row and the medium', () async {
      final (:a, :path) = await aCarriedStill();
      // The original goes first: what the bytes come from is the source's
      // carry — the thing carrying exists to outlive the original for.
      File(path).deleteSync();
      final b = open();
      expect(b.layerClipboard.pasteMustHoldMedia, isTrue);
      await b.layerClipboard.holdWhatThePasteBrings();
      expect(b.layerClipboard.pasteMustHoldMedia, isFalse, reason: 'held');

      final before = {for (final layer in b.requireActiveCut.layers) layer.id};
      b.layerClipboard.pasteLayerFromClipboard();
      final mine = carryIn(b, path);
      expect(mine, isNotNull, reason: 'the pool lists it, carried');
      expect(mine, isNot(carryIn(a, path)), reason: 'a carry of its own');
      expect(stagedCopyIn(b, path), isNotNull, reason: 'its bytes are held');
      expect(
        b.projectFile.mediaByteSourceFor(path).readSync(),
        List<int>.generate(64, (i) => i),
      );
      final pasted = b.requireActiveCut.layers.firstWhere(
        (layer) => !before.contains(layer.id),
      );
      expect(pasted.mediaReference?.assetPath, path);

      b.historyManager.undo();
      expect(
        b.repository.requireProject().mediaAssetByPath(path),
        isNull,
        reason: 'one step: the medium went with the row',
      );
      expect({for (final layer in b.requireActiveCut.layers) layer.id}, before);
    });

    test('pasted WITHOUT the wait, a carried medium is not recorded — a pool '
        'entry that says carried is the promise the bytes are held', () async {
      final (a: _, :path) = await aCarriedStill();
      final b = open();
      b.layerClipboard.pasteLayerFromClipboard();
      expect(b.repository.requireProject().mediaAssetByPath(path), isNull);
    });

    test('at home nothing is brought — the pool already holds it', () async {
      final (:a, :path) = await aCarriedStill();
      expect(a.layerClipboard.pasteMustHoldMedia, isFalse);
      final pool = a.repository.requireProject().mediaAssets;
      a.layerClipboard.pasteLayerFromClipboard();
      expect(a.repository.requireProject().mediaAssets, pool);
      expect(carryIn(a, path), isNotNull);
    });

    /// [session]'s vocabulary with `custom-1` spelled [word].
    void spell(EditorSessionManager session, String word) =>
        session.cutCommandCoordinator.updateCameraInstructionSet(
          CameraInstructionSet(
            defs: [
              ...CameraInstructionSet.standard.defs,
              CameraInstructionDef(id: 'custom-1', name: word, iconKey: 'note'),
            ],
          ),
        );

    /// A new instruction row in [session] whose first block spells [term].
    LayerId aTermRow(EditorSessionManager session, String term) {
      session.layerStack.addLayerOfKind(LayerKind.instruction);
      final row = session.activeLayer!.id;
      session.instructionVerbs.upsertInstructionEventAt(
        row,
        0,
        InstructionEvent(instructionId: term, length: 2),
      );
      return row;
    }

    String? termAt(EditorSessionManager session, LayerId row, int frame) =>
        rowOf(session, row).timeline[frame]?.instruction?.instructionId;

    test('a custom term another project numbers the same but spells '
        'otherwise arrives under a number of its own, and the pasted row '
        'says it', () {
      final a = open();
      final b = open();
      spell(a, 'SHAKE');
      spell(b, 'BLUR');
      aTermRow(a, 'custom-1');
      a.layerClipboard.copyActiveLayer();

      final before = {for (final layer in b.requireActiveCut.layers) layer.id};
      b.layerClipboard.pasteLayerFromClipboard();
      final vocabulary = b.repository.requireProject().cameraInstructions;
      expect(vocabulary.defById('custom-1')!.name, 'BLUR', reason: 'kept');
      expect(vocabulary.defById('custom-2')!.name, 'SHAKE');
      final pasted = b.requireActiveCut.layers.firstWhere(
        (layer) => !before.contains(layer.id),
      );
      expect(termAt(b, pasted.id, 0), 'custom-2');
    });

    test('the same word under the same number is the same term — nothing is '
        'added — and a term the project lacks is added as it is', () {
      final a = open();
      final b = open();
      spell(a, 'SHAKE');
      spell(b, 'SHAKE');
      aTermRow(a, 'custom-1');
      a.layerClipboard.copyActiveLayer();
      b.layerClipboard.pasteLayerFromClipboard();
      expect(
        b.repository.requireProject().cameraInstructions.defs,
        hasLength(CameraInstructionSet.standard.defs.length + 1),
      );

      final c = open();
      c.layerClipboard.pasteLayerFromClipboard();
      expect(
        c.repository.requireProject().cameraInstructions
            .defById('custom-1')
            ?.name,
        'SHAKE',
      );
    });

    test('at home too a paste brings what the project LACKS — a term deleted '
        'since the copy comes back with the row that spells it', () {
      final a = open();
      spell(a, 'SHAKE');
      aTermRow(a, 'custom-1');
      a.layerClipboard.copyActiveLayer();
      a.cutCommandCoordinator.updateCameraInstructionSet(
        CameraInstructionSet.standard,
      );
      a.layerClipboard.pasteLayerFromClipboard();
      expect(
        a.repository.requireProject().cameraInstructions
            .defById('custom-1')
            ?.name,
        'SHAKE',
      );
    });

    test('a STANDARD term is its id — a project that labels it otherwise '
        'keeps its label, and gains no second term', () {
      final a = open();
      final b = open();
      b.cutCommandCoordinator.updateCameraInstructionSet(
        CameraInstructionSet(
          defs: [
            for (final term in CameraInstructionSet.standard.defs)
              if (term.id == 'pan') term.copyWith(name: '팬') else term,
          ],
        ),
      );
      aTermRow(a, 'pan');
      a.layerClipboard.copyActiveLayer();
      final before = {for (final layer in b.requireActiveCut.layers) layer.id};
      b.layerClipboard.pasteLayerFromClipboard();
      final vocabulary = b.repository.requireProject().cameraInstructions;
      expect(vocabulary.defs, hasLength(CameraInstructionSet.standard.defs.length));
      expect(vocabulary.defById('pan')!.name, '팬');
      final pasted = b.requireActiveCut.layers.firstWhere(
        (layer) => !before.contains(layer.id),
      );
      expect(termAt(b, pasted.id, 0), 'pan');
    });

    test('a FRAME block copied from another project spells its term this '
        'project\'s way too', () {
      final a = open();
      final b = open();
      spell(a, 'SHAKE');
      spell(b, 'BLUR');
      final from = aTermRow(a, 'custom-1');
      a
        ..selectLayer(from)
        ..selectFrameIndex(0);
      // A band takes the BLOCK, its term with it — copied standing, a cell
      // is one comma of its drawing and none of the block's own (F-152).
      a.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: from,
        startIndex: 0,
        endIndexExclusive: 2,
        layerIds: [from],
      );
      a.copyFrameAtCurrentFrame();

      final into = aTermRow(b, 'custom-1');
      b
        ..selectLayer(into)
        ..selectFrameIndex(4);
      b.pasteIndependentFrameAtCurrentFrame();
      expect(termAt(b, into, 0), 'custom-1', reason: 'its own block stays');
      expect(termAt(b, into, 4), 'custom-2');
      expect(
        b.repository.requireProject().cameraInstructions
            .defById('custom-2')
            ?.name,
        'SHAKE',
      );
    });
  });

  test('a picture pasted into a cut of ANOTHER canvas size is kept at that '
      'cut\'s size, its canvas numbers as they were — a cel of the wrong '
      'size opens BLANK and the next stroke makes that permanent', () {
    final a = open();
    drawOnCurrentFrame(a);
    final from = a.requireActiveCut;
    a.copyFrameAtCurrentFrame();
    a.cutVerbs.createCut();
    a.cutVerbs.resizeActiveCutCanvas(
      const CanvasSize(width: 640, height: 360),
    );
    final into = a.requireActiveCut;
    expect(
      into.canvasSize,
      isNot(from.canvasSize),
      reason: 'fixture premise: two sizes',
    );
    final row = a.activeLayer!;
    final before = {for (final frame in row.frames) frame.id};
    a.pasteIndependentFrameAtCurrentFrame();
    final born = rowOf(a, row.id).frames.firstWhere(
      (frame) => !before.contains(frame.id),
    );
    final picture = a.renderCaches.brushFrameStore.bakedSurfaceOrNull(
      a.brushFrameKeyForCut(into, row.id, born.id),
    )!;
    expect(picture.canvasSize, into.canvasSize);
    expect(
      picture.tiles.keys.map((tile) => (tile.x, tile.y)),
      contains((0, 0)),
      reason: 'the ink at (10, 10) is where it was on the canvas',
    );
  });

  test('a project opened into a new tab leaves the copy in hand — opening '
      'is not a reason for the app to forget', () async {
    final a = open();
    drawOnCurrentFrame(a);
    final folder = Directory.systemTemp.createTempSync('anicel-app-clipboard');
    deleteAfterSessionEnds(folder);
    final path = '${folder.path}${Platform.pathSeparator}saved.anicel';
    await a.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);
    a.copyFrameAtCurrentFrame();

    final opened = await openedSession(
      path,
      make: (project) {
        final session = EditorSessionManager(
          initialProject: project,
          appClipboard: clipboard,
        );
        addTearDown(session.dispose);
        return session;
      },
    );
    expect(opened.canPasteIndependentFrameAtCurrentFrame, isTrue);
  });
}
