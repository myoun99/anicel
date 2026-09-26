import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/cut_verbs.dart';

import '../../helpers/draw_on_current_frame.dart';

/// 🗣️cut-duplicate-sheet-ink (유저 2026-09-26, answering its Q1:
/// 「따라간다 — 복제는 전부 복사」): a duplicated cut starts with the
/// handwriting of the cut it came from — on the conte's cells, on its
/// envelope, on its timesheet — and from there the two are apart.
///
/// The verb this lives in — named so `tool/mutation_run.dart` runs this
/// file for it.
CutVerbs cutVerbsOf(EditorSessionManager session) => session.cutVerbs;

void main() {
  late EditorSessionManager session;
  late BitmapSurface ink;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    // Any picture is ink to a store: the drawing's own surface stands in.
    drawOnCurrentFrame(session);
    final cut = session.requireActiveCut;
    final drawn = cut.layers.firstWhere((layer) => layer.frames.isNotEmpty);
    ink = session.renderCaches.brushFrameStore.bakedSurfaceOrNull(
      session.brushFrameKeyForCut(cut, drawn.id, drawn.frames.single.id),
    )!;
  });
  tearDown(() => session.dispose());

  BrushFrameStore storeOf(BrushFrameKey key) =>
      session.renderCaches.sheetInkStoreFor(key)!;
  void write(BrushFrameKey key) =>
      storeOf(key).storeBakedSurface(key, ink);
  Object? read(BrushFrameKey key) => storeOf(key).bakedSurfaceOrNull(key);

  test('every sheet\'s writing of the cut is on the copy\'s sheets', () {
    final source = session.requireActiveCut;
    // A block written on on the conte: its handwriting is kept under the id
    // its memo carries (`ExposureMemo.inkId`).
    final drawn = source.layers.firstWhere((layer) => layer.frames.isNotEmpty);
    session.cutCommandCoordinator.updateExposureMemo(
      cutId: source.id,
      layerId: drawn.id,
      blockStartIndex: drawn.timeline.keys.first,
      memo: const ExposureMemo(inkId: 'ink-1'),
    );
    write(conteInkRowKey(source.id, 'ink-1'));
    write(envelopeInkBoxKey(source.id, 'memo'));
    write(timesheetInkStripKey(source.id, 2));
    write(timesheetInkPageKey(source.id, 1));

    session.cutVerbs.duplicateActiveCut();
    final copy = session.requireActiveCut;
    expect(copy.id, isNot(source.id), reason: 'the copy is where you stand');

    expect(
      read(conteInkRowKey(copy.id, 'ink-1')),
      same(ink),
      reason: 'the copied block keeps its id, on the copy\'s cut',
    );
    expect(read(envelopeInkBoxKey(copy.id, 'memo')), same(ink));
    expect(read(timesheetInkStripKey(copy.id, 2)), same(ink));
    expect(read(timesheetInkPageKey(copy.id, 1)), same(ink));
    expect(
      read(timesheetInkStripKey(copy.id, 1)),
      isNull,
      reason: 'band for band — nothing written where the source had none',
    );
    expect(
      read(conteInkRowKey(source.id, 'ink-1')),
      same(ink),
      reason: 'the source keeps its own',
    );
  });

  test('the paper\'s own ink belongs to no cut and is not doubled', () {
    final page = conteInkPageKey(0);
    write(page);
    final store = storeOf(page);
    expect(
      store.bakedSurfacesForCut(conteInkCutId).keys,
      [page],
      reason: 'fixture premise',
    );

    session.cutVerbs.duplicateActiveCut();

    expect(store.bakedSurfacesForCut(conteInkCutId).keys, [page]);
  });

  test('a shared envelope\'s writing comes from the cut that owns it — the '
      'copy of a sibling starts with what that sibling showed', () {
    final owner = session.requireActiveCut.id;
    session.cutVerbs.createLinkedCutFromActiveCut();
    final sibling = session.requireActiveCut.id;
    expect(sibling, isNot(owner), reason: 'fixture premise: a sibling');
    write(envelopeInkBoxKey(owner, 'memo'));

    session.cutVerbs.duplicateActiveCut();
    final copy = session.requireActiveCut.id;

    expect(copy, isNot(sibling), reason: 'CONTROL: the copy is new');
    expect(read(envelopeInkBoxKey(copy, 'memo')), same(ink));
  });

  test('a key of another cut is left alone', () {
    const elsewhere = CutId('another-cut');
    write(envelopeInkBoxKey(elsewhere, 'memo'));
    write(timesheetInkStripKey(elsewhere, 0));

    session.cutVerbs.duplicateActiveCut();
    final copy = session.requireActiveCut.id;

    expect(read(envelopeInkBoxKey(copy, 'memo')), isNull);
    expect(read(timesheetInkStripKey(copy, 0)), isNull);
  });
}
