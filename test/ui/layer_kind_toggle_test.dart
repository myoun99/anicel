import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/stroke.dart';
import 'package:anicel/src/models/stroke_id.dart';
import 'package:anicel/src/models/stroke_point.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/brush/main_canvas_brush_host.dart';
import 'package:anicel/src/ui/home_page.dart';

import 'flyout_test_helpers.dart';
import '../helpers/home_page_probes.dart' show pickLayerKind;
import '../helpers/named_finders.dart';
import '../helpers/room_for_the_pills.dart';
import '../helpers/timeline_host.dart';

const _seToggleKey = ValueKey<String>('toggle-se-layer-button');
const _artToggleKey = ValueKey<String>('toggle-art-layer-button');
const _undoKey = ValueKey<String>('undo-button');
const _redoKey = ValueKey<String>('redo-button');
const _cutId = CutId('phase-73-cut');
const _layerId = LayerId('phase-73-layer');
const _frameId = FrameId('phase-73-frame');

/// The timeline tab alone ([pumpTimelineHost]) — the Layer flyout and the
/// `＋`'s band are the tab's — with room for its pills unless [surface] says
/// another. ↩️It stood as the app's window of 800 × 600 laid it, where the
/// pills have 34px now ([timelineTabWithRoomForItsPills]).
Future<void> _pumpHome(
  WidgetTester tester, {
  Project? project,
  void Function(ProjectRepository repository)? onRepositoryCreated,
  Size surface = timelineTabWithRoomForItsPills,
}) async {
  final session = await pumpTimelineHost(
    tester,
    project ?? _projectWithLayer(),
    surface: surface,
  );
  onRepositoryCreated?.call(session.repository);
}

/// The app, for its undo and redo buttons and the canvas they retarget,
/// with room for the pills ([appWindowWithRoomForItsPills]).
Future<void> _pumpApp(
  WidgetTester tester, {
  Project? project,
  void Function(ProjectRepository repository)? onRepositoryCreated,
}) async {
  await tester.binding.setSurfaceSize(appWindowWithRoomForItsPills);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: HomePage(
        initialProject: project ?? _projectWithLayer(),
        onRepositoryCreated: onRepositoryCreated,
      ),
    ),
  );
}

CutId? _mainCanvasCutId(WidgetTester tester) {
  final host = tester.widget<MainCanvasBrushHost>(
    find.byType(MainCanvasBrushHost),
  );
  return host.selection?.cutId;
}

// Menu-aware (R-toolbar round): a command in a flyout opens it first.
Future<void> _tapKey(WidgetTester tester, ValueKey<String> key) =>
    tapCommandButton(tester, key);

/// ⑥ (2026-08-12): the `＋` makes an ANIMATION layer now, whatever is selected
/// (유저: 「레이어 +버튼, 선택된 레이어 기준이아니라 애니메이션레이어 생성」).
///
/// The PLACEMENT rules these tests pin — S-numbering, insertion order, landing
/// above the active row — did not change and are still worth holding. Asking
/// for a particular KIND simply moved to the band above the `＋`, so that is
/// where the tests ask from.
Future<void> _addLayerOfKind(WidgetTester tester, String kind) async {
  await _tapKey(
    tester,
    const ValueKey<String>('timeline-toolbar-add-layer-menu'),
  );
  await tester.pumpAndSettle();
  await _tapKey(tester, ValueKey<String>('add-layer-kind-$kind'));
  await tester.pumpAndSettle();
}

Layer _layer(ProjectRepository repository) {
  return repository.requireProject().tracks.single.cuts.single.layers.single;
}

/// Turns the row into [kind] through its type button's list — the one
/// door since F-613 (↩️a toggle in the Layer ▾ flyout, whose ring read
/// whether the row was the conte).
Future<void> _pickKind(WidgetTester tester, LayerKind kind) =>
    pickLayerKind(tester, '$_layerId', kind);

Project _projectWithLayer({
  LayerKind kind = LayerKind.animation,
  // Default hidden: the preservation tests pin that a kind toggle keeps
  // the eye state. The canvas-retarget pins pass true — a hidden layer
  // yields NO brush selection now (R4 #1).
  bool isVisible = false,
}) {
  return Project(
    id: const ProjectId('phase-73-project'),
    name: 'Phase 73 Project',
    createdAt: DateTime.utc(2026, 6, 11),
    tracks: [
      Track(
        id: const TrackId('phase-73-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: _cutId,
            name: 'Phase 73 Cut',
            duration: 2,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            metadata: const CutMetadata(pageNotes: ['cut note only']),
            layers: [
              Layer(
                id: _layerId,
                name: 'Target Layer',
                kind: kind,
                isVisible: isVisible,
                opacity: 0.5,
                frames: [
                  Frame(
                    id: _frameId,
                    duration: 2,
                    name: 'A1',
                    strokes: [
                      Stroke(
                        id: const StrokeId('stroke-1'),
                        points: const [
                          StrokePoint(x: 1, y: 2),
                          StrokePoint(x: 3, y: 4),
                        ],
                        brushSettings: BrushSettings(
                          color: 0xFF112233,
                          size: 7,
                          opacity: 0.75,
                        ),
                      ),
                    ],
                  ),
                ],
                timeline: {0: const TimelineExposure.drawing(_frameId, length: 1)},
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

void main() {
  testWidgets('the type button turns an animation row into the conte', (
    tester,
  ) async {
    late ProjectRepository repository;
    await _pumpHome(tester, onRepositoryCreated: (repo) => repository = repo);

    expect(_layer(repository).kind, LayerKind.animation);
    expect(find.bySemanticsLabel('Animation layer'), findsOneWidget);

    await _pickKind(tester, LayerKind.storyboard);

    expect(_layer(repository).kind, LayerKind.storyboard);
    expect(find.bySemanticsLabel('Storyboard layer'), findsOneWidget);
  });

  // storyboard→animation (model + metadata) is covered at the service level by
  // UpdateLayerKindCommand's 'changes storyboard layer back to animation'
  // test; the forward gesture above anchors the display-label contract, which
  // reads layer.kind through the same widget code in either direction.

  testWidgets('undo and redo work after turning the row into the conte', (
    tester,
  ) async {
    late ProjectRepository repository;
    await _pumpApp(
      tester,
      project: _projectWithLayer(isVisible: true),
      onRepositoryCreated: (repo) => repository = repo,
    );

    await _pickKind(tester, LayerKind.storyboard);
    expect(_layer(repository).kind, LayerKind.storyboard);
    expect(_mainCanvasCutId(tester), _cutId);

    await _tapKey(tester, _undoKey);
    expect(_layer(repository).kind, LayerKind.animation);
    expect(_mainCanvasCutId(tester), _cutId);

    await _tapKey(tester, _redoKey);
    expect(_layer(repository).kind, LayerKind.storyboard);
    expect(_mainCanvasCutId(tester), _cutId);
  });

  // The reverse-direction undo/redo adds nothing over the forward case above
  // (same command, same canvas-retarget path); the model undo/redo itself is
  // covered by UpdateLayerKindCommand's 'undo restores previous kind' test.

  // Data preservation across the kind change (metadata, strokes, frames,
  // timeline, visibility, opacity, cut metadata) is pinned more thoroughly at
  // the service level by UpdateLayerKindCommand's 'preserves data' test.

  // The SE kind toggle is retired (entrance unification): SE rows are
  // created by the unified Add Layer with an SE row active, never by
  // converting a cel.
  testWidgets('the SE kind toggle is gone', (tester) async {
    await _pumpHome(tester, project: _projectWithLayer(kind: LayerKind.se));

    expect(find.byKey(_seToggleKey), findsNothing);
  });

  // The ART kind (and its toggle) is retired: art always behaved exactly
  // like animation, so the kind collapsed into it. Picture rows are the
  // IMAGE kind now, created through Add Layer — never by conversion.
  testWidgets('the art and conte toggles are gone from the Layer flyout', (
    tester,
  ) async {
    // The floating region opens at 2/3 of the window now, so at the 800px
    // test default the timeline toolbar compresses far enough to shed the
    // Layer flyout's own button — the tab as the app's window of 1600 × 900
    // laid it.
    await _pumpHome(tester, surface: const Size(1003, 396));

    // Flyout items only exist while the popup is open — open it, then
    // assert the retired toggle is not among the items.
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-layer-menu-button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('timeline-rename-layer-button')),
      findsOneWidget,
      reason: 'the flyout is open (its surviving sibling shows)',
    );
    expect(find.byKey(_artToggleKey), findsNothing);
    // 🗣️F-613 (유저 2026-11-19): 「레이어버튼의 콘티레이어로 변경은 입구
    // 대체되니 삭제」 — the row's type button turns it now.
    expect(
      find.byKey(const ValueKey<String>('toggle-storyboard-layer-button')),
      findsNothing,
    );
  });

  // The dedicated instruction-add button is retired: the unified Add Layer
  // duplicates the ACTIVE row's kind directly above it, named by the
  // section's own scheme.
  testWidgets('Add Layer with an instruction row active adds another Direction '
      'row above it', (tester) async {
    late ProjectRepository repository;
    await _pumpHome(
      tester,
      project: _projectWithLayer(kind: LayerKind.instruction),
      onRepositoryCreated: (repo) => repository = repo,
    );

    expect(
      find.byKey(const ValueKey<String>('add-instruction-layer-button')),
      findsNothing,
    );

    await _addLayerOfKind(tester, 'instruction');

    final layers = repository.requireProject().tracks.single.cuts.single.layers;
    expect(layers, hasLength(2));
    // Raw list order is reversed for the timeline display: raw index+1 =
    // directly ABOVE the previously active row on screen.
    expect(layers[0].name, 'Target Layer');
    expect(layers[1].kind, LayerKind.instruction);
    expect(layers[1].name, 'Direction 1');
  });

  testWidgets('Add Layer with an SE row active adds the next S-numbered '
      'row to the TRACK above it', (tester) async {
    late ProjectRepository repository;
    await _pumpHome(
      tester,
      project: _projectWithLayer(kind: LayerKind.se),
      onRepositoryCreated: (repo) => repository = repo,
    );
    // SE rows are TRACK-owned: the add lands on the track's SE list (the
    // cut's legacy fixture row stays untouched); the new row takes the
    // first free S-number.
    await _addLayerOfKind(tester, 'se');

    var track = repository.requireProject().tracks.single;
    expect(track.cuts.single.layers, hasLength(1));
    expect(track.seLayers, hasLength(1));
    expect(track.seLayers[0].kind, LayerKind.se);
    expect(track.seLayers[0].name, 'S1');

    // Adding again with the new S1 active skips to S2, inserted above it.
    await _addLayerOfKind(tester, 'se');
    track = repository.requireProject().tracks.single;
    expect(track.seLayers.map((layer) => layer.name), ['S1', 'S2']);
  });

  testWidgets('adding an SE row between S1 and S2 keeps insertion order '
      '(S1, S3, S2 — the ordering every panel shows)', (tester) async {
    late ProjectRepository repository;
    await _pumpHome(
      tester,
      // The default project's track carries the S1·S2 fixtures.
      project: createDefaultProject(),
      onRepositoryCreated: (repo) => repository = repo,
    );

    // Select the default track's S1 row (tap its NAME — the row center
    // lands on the opacity slider), then Add Layer.
    final s1Row = find.named('timeline-layer-row-default-track-se-1');
    await tester.ensureVisible(s1Row);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: s1Row, matching: find.text('S1')));
    await tester.pumpAndSettle();
    await _addLayerOfKind(tester, 'se');

    final track = repository.requireProject().tracks.single;
    expect(track.seLayers.map((layer) => layer.name), ['S1', 'S3', 'S2']);
  });
}
