import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/frame_clipboard.dart';
import 'package:anicel/src/ui/session/frame_verbs.dart';
import 'package:anicel/src/ui/session/layer_clipboard.dart';

import '../../helpers/draw_on_current_frame.dart';

/// 🚨A COPIED BLOCK STARTS WITH ITS SOURCE'S HANDWRITING, UNDER AN ID OF
/// ITS OWN.
///
/// 유저 2026-09-26 (cut-duplicate-sheet-ink-Q1) 「복제는 전부 복사」 — a
/// copy starts with the same writing, and from there the two are apart;
/// and 2026-09-25 (conte-drawing-target): blocks of the same name are not
/// linked. So every copy of a block — linked or not, duplicated or pasted,
/// alone or with its row — writes on the conte under an id of its own.
///
/// The verbs these live in — named so `tool/mutation_run.dart` runs this
/// file for them.
FrameVerbs frameVerbsOf(EditorSessionManager session) => session.frameVerbs;
FrameClipboard frameBoardOf(EditorSessionManager session) => session.clipboard;
LayerClipboard layerBoardOf(EditorSessionManager session) =>
    session.layerClipboard;

void main() {
  late EditorSessionManager session;
  late BitmapSurface handwriting;
  late LayerId row;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    drawOnCurrentFrame(session);
    row = session.activeLayerId!;
    final cut = session.requireActiveCut;
    final layer = cut.layers.firstWhere((layer) => layer.id == row);
    // Any surface is ink to a store: the drawing's own stands in.
    handwriting = session.renderCaches.brushFrameStore.bakedSurfaceOrNull(
      session.brushFrameKeyForCut(cut, row, layer.frames.single.id),
    )!;
    session.cutCommandCoordinator.updateExposureMemo(
      cutId: cut.id,
      layerId: row,
      blockStartIndex: layer.timeline.keys.first,
      memo: const ExposureMemo(inkId: 'ink-src'),
    );
    session.renderCaches.conteInkRowStore.storeBakedSurface(
      conteInkRowKey(cut.id, 'ink-src'),
      handwriting,
    );
  });
  tearDown(() => session.dispose());

  Layer rowNamed(LayerId id) =>
      session.requireActiveCut.layers.firstWhere((layer) => layer.id == id);

  /// The handwriting ids [layer]'s blocks write under.
  List<String> writtenIn(Layer layer) => [
    for (final exposure in layer.timeline.values)
      if (exposure.memo?.inkId case final inkId? when inkId.isNotEmpty) inkId,
  ];

  Object? handwritingOf(String inkId) => session.renderCaches.conteInkRowStore
      .bakedSurfaceOrNull(conteInkRowKey(session.requireActiveCut.id, inkId));

  /// [written] holds the source's id and ONE other, whose handwriting is
  /// the source's — and the source's is still there.
  void expectAnOwnCopy(List<String> written) {
    expect(written, contains('ink-src'), reason: 'the source keeps its id');
    final copies = [
      for (final inkId in written)
        if (inkId != 'ink-src') inkId,
    ];
    expect(copies, hasLength(1), reason: 'the copy writes for itself');
    expect(
      handwritingOf(copies.single),
      same(handwriting),
      reason: 'starting with its source\'s handwriting',
    );
    expect(handwritingOf('ink-src'), same(handwriting));
  }

  /// The run of the block that opens the row — a drawing's exposure, which
  /// always has its length.
  ({int start, int end}) theBlock() {
    final first = rowNamed(row).timeline.entries.first;
    return (start: first.key, end: first.key + first.value.length!);
  }

  for (final linked in [false, true]) {
    final how = linked ? 'linked' : 'independent';

    test('a block duplicated $how writes under an id of its own, starting '
        'with its source\'s handwriting', () {
      session.frameVerbs.duplicateActiveBlock(linked: linked);

      expectAnOwnCopy(writtenIn(rowNamed(row)));
    });

    test('a block copied and pasted $how does too', () {
      final block = theBlock();
      session.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: row,
        startIndex: block.start,
        endIndexExclusive: block.end,
      );
      session.clipboard.copyFrameAtCurrentFrame();
      session.frameRangeSelection.value = null;
      session.selectFrameIndex(block.end);

      if (linked) {
        session.clipboard.pasteLinkedFrameAtCurrentFrame();
      } else {
        session.clipboard.pasteIndependentFrameAtCurrentFrame();
      }

      expectAnOwnCopy(writtenIn(rowNamed(row)));
    });
  }

  test('a row copied and pasted brings its blocks\' handwriting, each '
      'under an id of its own', () {
    final before = {
      for (final layer in session.requireActiveCut.layers) layer.id,
    };
    session.layerClipboard.copyActiveLayer();
    session.layerClipboard.pasteLayerFromClipboard();
    final pasted = session.requireActiveCut.layers
        .where((layer) => !before.contains(layer.id))
        .single;

    expectAnOwnCopy([...writtenIn(rowNamed(row)), ...writtenIn(pasted)]);
  });

  test('a copy made standing — one comma of the drawing — brings none: the '
      'handwriting is the block\'s, like its ACTION', () {
    session.clipboard.copyFrameAtCurrentFrame();
    session.selectFrameIndex(theBlock().end);
    session.clipboard.pasteIndependentFrameAtCurrentFrame();

    expect(writtenIn(rowNamed(row)), ['ink-src']);
  });
}
