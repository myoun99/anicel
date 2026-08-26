import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/pixel_verb_subject.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/services/cel_pixel_overwrite.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/editor_workspace.dart';

/// The two PIXEL verbs — 색 변환 and 픽셀 비우기 — and the ladder that decides
/// what a press touches.
///
/// 유저 2026-08-26: 「조작은 무조건 서있는 레이어에 조작하게 하는거야. 그러니
/// **선택범위 있으면 그거 전부, 아니면 서있는곳** 조작하는거야」.
void main() {
  /// A project whose drawing row already HAS a cel.
  ///
  /// ⚠️A default project has none — every layer arrives with
  /// `frames: const []` — so a fixture that skipped this would be measuring
  /// the ladder's empty answer and calling it the ladder.
  Project projectWithACel() {
    final base = createDefaultProject();
    final track = base.tracks.first;
    final cut = track.cuts.first;
    // 🚨EVERY layer gets one, the camera row included. If only the drawable
    // ones had cels then the gate test would pass with the gate DELETED —
    // what refused the camera row would be its emptiness, not the predicate.
    // Verified by mutation: without this, removing `layerAcceptsBrushInput`
    // left the suite green.
    final drawn = [
      for (final layer in cut.layers)
        if (layer.frames.isEmpty)
          // 🚨THREE distinct cels, one frame each — not one four-frame hold.
          // A hold would let the range rung and the standing rung answer with
          // the same single cel, and the range test could not tell them
          // apart. Verified by mutation: with a hold, deleting the range rung
          // outright left the suite green.
          layer.copyWith(
            frames: [
              for (var i = 0; i < 3; i++)
                Frame(
                  id: FrameId('${layer.id.value}-cel-$i'),
                  duration: 1,
                  strokes: const [],
                ),
            ],
            timeline: {
              for (var i = 0; i < 3; i++)
                i: TimelineExposure.drawing(
                  FrameId('${layer.id.value}-cel-$i'),
                  length: 1,
                ),
            },
          )
        else
          layer,
    ];
    return base.copyWith(
      tracks: [
        track.copyWith(
          cuts: [cut.copyWith(layers: drawn)],
        ),
      ],
    );
  }

  Future<EditorSessionManager> pump(
    WidgetTester tester, {
    Project? project,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(initialProject: project ?? projectWithACel()),
      ),
    );
    await tester.pumpAndSettle();
    return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
  }

  /// A default project has NO cels — every layer arrives with
  /// `frames: const []`. So a row has to be given one before a pixel verb
  /// has anything to answer with, which is itself the first thing worth
  /// pinning (see the empty-row test).
  Future<Layer> drawableRow(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    final row = session.layers.firstWhere(
      (l) => layerAcceptsBrushInput(l) && l.frames.isNotEmpty,
    );
    session.selectLayer(row.id);
    session.selectFrameIndex(0);
    await tester.pump();
    return row;
  }

  testWidgets('an EMPTY row has nothing to recolour — the buttons dim',
      (tester) async {
    // A DEFAULT project, deliberately: every layer arrives with no frames, so
    // this is the state a new file is in. A verb that answered 「standing」
    // here would be naming a cel that does not exist.
    final session = await pump(tester, project: createDefaultProject());
    final empty = session.layers.firstWhere(layerAcceptsBrushInput);
    expect(empty.frames, isEmpty);
    session.selectLayer(empty.id);
    await tester.pump();
    expect(session.pixelVerbSubject, PixelVerbSubject.nothing);
  });

  testWidgets('standing is one cel — the ladder does not reach for neighbours',
      (tester) async {
    final session = await pump(tester);
    await drawableRow(tester, session);
    expect(session.pixelVerbSubject, PixelVerbSubject.standing);
    expect(session.pixelVerbCellKeys(), hasLength(1));
  });

  testWidgets(
      'a ROW SELECTION does not fan the verb out — 유저: 「내가 비슷한얘기 '
      '옛날에 했다가 폐기했어」', (tester) async {
    final session = await pump(tester);
    await drawableRow(tester, session);
    final standing = session.pixelVerbCellKeys();
    expect(standing, hasLength(1));

    // Select every row there is. Under the discarded design this would have
    // named one cel per row; the verb still answers with the one you are
    // standing on.
    session.rowSelection.value = [
      for (final layer in session.layers) LayerRowAddress(layer.id),
    ];
    await tester.pump();
    expect(session.rowSelection.value.length, greaterThan(1));

    expect(
      session.pixelVerbSubject,
      PixelVerbSubject.standing,
      reason: 'selecting rows says which rows are selected, not '
          '「recolour all of their drawings」',
    );
    expect(
      session.pixelVerbCellKeys().map((k) => k.frameId).toList(),
      standing.map((k) => k.frameId).toList(),
    );
  });

  testWidgets('a FRAME RANGE is the one rung that touches more than one cel',
      (tester) async {
    final session = await pump(tester);
    final layer = await drawableRow(tester, session);

    session.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: layer.id,
      startIndex: 0,
      endIndexExclusive: 4,
    );
    await tester.pump();

    expect(session.pixelVerbSubject, PixelVerbSubject.range);
    // 🚨COUNTED, not just non-empty. `isNotEmpty` passed with the range rung
    // deleted, because the standing rung answers with one — the assertion has
    // to say 「more than standing would give you」 or it is not about the range
    // at all.
    expect(
      session.pixelVerbCellKeys().length,
      greaterThan(1),
      reason: 'a range is drawn ACROSS the cels, which is why it is the one '
          'rung allowed to name more than one',
    );
  });

  testWidgets('the gate is the existing predicate — a camera row has no pixels',
      (tester) async {
    final session = await pump(tester);
    final camera = session.layers
        .where((l) => l.kind == LayerKind.camera)
        .toList();
    if (camera.isEmpty) {
      return; // No camera row in the default project; nothing to assert.
    }
    session.selectLayer(camera.first.id);
    await tester.pump();
    expect(
      session.pixelVerbSubject,
      PixelVerbSubject.nothing,
      reason: 'layerAcceptsBrushInput already refuses this — ⛔no new predicate',
    );
  });

  testWidgets('the buttons dim rather than the press throwing when no canvas '
      'coordinator has been published', (tester) async {
    final session = await pump(tester);
    session.pixelEditingCoordinator = null;
    expect(session.canRunPixelVerb, isFalse);
    // ⛔And the press is a no-op rather than an exception: a gate and a verb
    // that disagree is the bug T25 exists to prevent.
    expect(
      () => session.runPixelVerb(CelPixelChannel.colour),
      returnsNormally,
    );
  });
}
