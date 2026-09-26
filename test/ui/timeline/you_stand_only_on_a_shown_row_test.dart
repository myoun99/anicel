import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart' show createFolderLayer;
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/layer_section_defaults.dart'
    show createTrackSeLayer;
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart'
    show createCameraLayer;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart'
    show PlaybackScope;
import 'package:anicel/src/ui/timeline/timeline_row_filter.dart';

/// 🚨★★F-169 — THE STANDING LAW (유저 2026-09-24): ①「보이는거만 선택가능하고
/// 안보이는거 선택되는상황엔 다른 보이는레이어 선택하도록」 ②「언두시에 접혀있는
/// 레이어로 이동하면 펼치고 해당 레이어에 서게」.
///
/// The report: A at the bottom, B above it with B-1 attached below, B's
/// group folded. Standing on A, Add Layer makes C; deleting C — or undoing
/// it — stood you on B-1 and the folded group showed that row, 「펼쳐지고
/// 거기 서있게됨」. The hand-off picked B-1 blind, and the rail's exemption
/// for the active attach row put it on the screen.
///
/// Every door runs through the real app: the twirl, the legend's filter and
/// section menus, the verbs the buttons call. Each pin names the source of a
/// landing and the reason a row is off the screen — the matrix, not the one
/// symptom.
const _cut = CutId('cut');
const _a = LayerId('a');
const _b = LayerId('b');
const _bMinus1 = LayerId('b-1');
const _bMinus2 = LayerId('b-2');

Layer _drawing(
  String id, {
  LayerId? attachedTo,
  AttachedPlacement placement = AttachedPlacement.below,
  LayerId? folderId,
  LayerMark mark = LayerMark.none,
}) => Layer(
  id: LayerId(id),
  name: id,
  frames: [Frame(id: FrameId('$id-cel'), duration: 1, strokes: const [])],
  timeline: const {},
  attachedToLayerId: attachedTo,
  attachedPlacement: placement,
  folderId: folderId,
  mark: mark,
);

Project _project(
  List<Layer> layers, {
  List<Layer> secondCut = const [],
  List<Layer> seLayers = const [],
}) => Project(
  id: const ProjectId('standing-law'),
  name: 'Standing law',
  createdAt: DateTime.utc(2026, 9, 24),
  tracks: [
    Track(
      id: const TrackId('track'),
      name: 'Video',
      seLayers: seLayers,
      cuts: [
        Cut(
          id: _cut,
          name: 'Cut',
          duration: 12,
          canvasSize: const CanvasSize(width: 640, height: 360),
          layers: layers,
        ),
        if (secondCut.isNotEmpty)
          Cut(
            id: const CutId('cut-2'),
            name: 'Cut 2',
            duration: 12,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: secondCut,
          ),
      ],
    ),
  ],
);

Future<EditorSessionManager> _open(WidgetTester tester, Project project) async {
  await tester.pumpWidget(MaterialApp(home: HomePage(initialProject: project)));
  await tester.pumpAndSettle();
  return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
}

Finder _row(LayerId id) =>
    find.byKey(ValueKey<String>('timeline-layer-row-${id.value}'));

Future<void> _twirl(WidgetTester tester, LayerId base) async {
  await tester.tap(
    find.byKey(ValueKey<String>('timeline-attach-twirl-${base.value}')),
  );
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, String flyout, String item) async {
  await tester.tap(find.byKey(ValueKey<String>(flyout)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey<String>(item)));
  await tester.pumpAndSettle();
}

/// The report's stack: A, then B's group with B-1 below B.
final _reported = [
  _drawing('a'),
  _drawing('b-1', attachedTo: _b),
  _drawing('b'),
];

void main() {
  group('① a HAND-OFF lands on a shown row', () {
    testWidgets('deleting the row above a folded group stands on its BASE, '
        'and the group stays shut (the report)', (tester) async {
      final session = await _open(tester, _project(_reported));
      await _twirl(tester, _b);
      session.selectLayer(_a);
      session.layerStack.addLayerOfKind(LayerKind.animation);
      await tester.pumpAndSettle();
      final c = session.activeLayerId;
      expect(c, isNot(_a), reason: 'Add Layer stood on the new row');

      session.layerVerbs.deleteActiveLayer();
      await tester.pumpAndSettle();

      expect(session.activeLayerId, _b);
      expect(_row(_bMinus1), findsNothing, reason: 'the group stays shut');
      expect(session.railView.collapsedAttachBaseIds.value, {_b});
    });

    testWidgets('undoing the Add Layer stands on the base too — and the redo '
        'brings you back to the row it made', (tester) async {
      final session = await _open(tester, _project(_reported));
      await _twirl(tester, _b);
      session.selectLayer(_a);
      session.layerStack.addLayerOfKind(LayerKind.animation);
      await tester.pumpAndSettle();
      final c = session.activeLayerId!;

      session.undo();
      await tester.pumpAndSettle();
      expect(session.activeLayerId, _b);
      expect(_row(_bMinus1), findsNothing);

      session.redo();
      await tester.pumpAndSettle();
      expect(session.activeLayerId, c);
      expect(_row(c), findsOneWidget);
    });

    testWidgets('a hand-off into a COLLAPSED FOLDER stands on the folder row',
        (tester) async {
      const folder = LayerId('f');
      final session = await _open(
        tester,
        _project([
          _drawing('a'),
          _drawing('m', folderId: folder),
          createFolderLayer(id: folder, name: 'F').copyWith(collapsed: true),
        ]),
      );
      session.selectLayer(_a);
      session.layerStack.addLayerOfKind(LayerKind.animation);
      await tester.pumpAndSettle();

      session.layerVerbs.deleteActiveLayer();
      await tester.pumpAndSettle();

      expect(session.activeLayerId, folder);
      expect(_row(const LayerId('m')), findsNothing);
    });

    testWidgets('a hand-off onto a row the FILTER hides takes the nearest '
        'shown row — the exemption is for the row you are on, not a way onto '
        'the screen', (tester) async {
      const red = LayerMark(process: LayerProcess.layout);
      const blue = LayerMark(process: LayerProcess.conte);
      final session = await _open(
        tester,
        _project([
          _drawing('red-a', mark: red),
          _drawing('blue-x', mark: blue),
          _drawing('red-r', mark: red),
        ]),
      );
      session.selectLayer(const LayerId('red-r'));
      await _pick(tester, 'legend-mark', 'legend-filter-mark-layout');
      expect(_row(const LayerId('blue-x')), findsNothing);

      // The walk hands red-r's place to blue-x, which the filter hides.
      session.layerVerbs.deleteActiveLayer();
      await tester.pumpAndSettle();

      expect(session.activeLayerId, const LayerId('red-a'));
      expect(_row(const LayerId('blue-x')), findsNothing);
    });

    testWidgets('undoing a new row hands off past a row the FILTER hides', (
      tester,
    ) async {
      const red = LayerMark(process: LayerProcess.layout);
      const blue = LayerMark(process: LayerProcess.conte);
      final session = await _open(
        tester,
        _project([
          _drawing('red-a', mark: red),
          _drawing('blue-x', mark: blue),
        ]),
      );
      await _pick(tester, 'legend-mark', 'legend-filter-mark-layout');
      session.selectLayer(const LayerId('red-a'));
      // A drawing row is born LO (F-76), so the new row passes the filter.
      session.layerStack.addLayerOfKind(LayerKind.animation);
      await tester.pumpAndSettle();

      // The walk hands the new row's place to blue-x, which the filter hides.
      session.undo();
      await tester.pumpAndSettle();

      expect(session.activeLayerId, const LayerId('red-a'));
      expect(_row(const LayerId('blue-x')), findsNothing);
    });

    testWidgets('deleting the SELECTED rows hands off past a row the FILTER '
        'hides', (tester) async {
      const red = LayerMark(process: LayerProcess.layout);
      const blue = LayerMark(process: LayerProcess.conte);
      final session = await _open(
        tester,
        _project([
          _drawing('red-a', mark: red),
          _drawing('red-1', mark: red),
          _drawing('blue-x', mark: blue),
          _drawing('red-2', mark: red),
        ]),
      );
      await _pick(tester, 'legend-mark', 'legend-filter-mark-layout');
      session.selectLayer(const LayerId('red-1'));
      session.rowSelection.value = const [
        LayerRowAddress(LayerId('red-1')),
        LayerRowAddress(LayerId('red-2')),
      ];

      // The walk hands the lowest deleted row's place to blue-x.
      session.layerVerbs.deleteSelectedLayers();
      await tester.pumpAndSettle();

      expect(session.activeLayerId, const LayerId('red-a'));
      expect(_row(const LayerId('blue-x')), findsNothing);
    });

    testWidgets('deleting a track SE row hands off past an SE row the FILTER '
        'hides', (tester) async {
      const red = LayerMark(process: LayerProcess.layout);
      const blue = LayerMark(process: LayerProcess.conte);
      const track = TrackId('track');
      Layer se(int slot, LayerMark mark) =>
          createTrackSeLayer(trackId: track, slot: slot).copyWith(mark: mark);
      final session = await _open(
        tester,
        _project(
          [_drawing('red-a', mark: red)],
          seLayers: [se(1, red), se(2, blue), se(3, red)],
        ),
      );
      final first = se(1, red).id;
      final filtered = se(2, blue).id;
      await _pick(tester, 'legend-mark', 'legend-filter-mark-layout');
      session.selectLayer(first);
      await tester.pumpAndSettle();

      // The track's walk hands S1's place to S2, which the filter hides.
      session.layerVerbs.deleteActiveLayer();
      await tester.pumpAndSettle();

      expect(session.activeLayerId, isNot(filtered));
      expect(_row(filtered), findsNothing);
      expect(_row(session.activeLayerId!), findsOneWidget);
    });

    testWidgets('coming back to a cut whose row the filter now hides stands '
        'on a shown one', (tester) async {
      const red = LayerMark(process: LayerProcess.layout);
      const blue = LayerMark(process: LayerProcess.conte);
      final session = await _open(
        tester,
        _project(
          [_drawing('red-a', mark: red), _drawing('blue-x', mark: blue)],
          secondCut: [_drawing('red-2', mark: red)],
        ),
      );
      session.selectLayer(const LayerId('blue-x'));
      session.selectCut(const CutId('cut-2'));
      await tester.pumpAndSettle();
      await _pick(tester, 'legend-mark', 'legend-filter-mark-layout');

      session.selectCut(_cut);
      await tester.pumpAndSettle();

      expect(session.activeLayerId, const LayerId('red-a'));
      expect(_row(const LayerId('blue-x')), findsNothing);
    });
  });

  group('① the stand-in is the fold\'s head, not merely the row above', () {
    // An ABOVE attach sits over its base on screen, so the row above it is
    // someone else's — and the fold law hands to the base (UI-R24 #4).
    const plusOne = LayerId('b+1');
    EditorSessionManager session(List<Layer> layers) {
      final s = EditorSessionManager(initialProject: _project(layers));
      addTearDown(s.dispose);
      return s;
    }

    test('a row inside a folded group above its base stands on the base',
        () {
      final s = session([
        _drawing('a'),
        _drawing('b'),
        _drawing('b+1', attachedTo: _b, placement: AttachedPlacement.above),
        _drawing('x'),
      ]);
      s.selectLayer(plusOne);
      s.railView.collapsedAttachBaseIds.value = {_b};
      final reveals = s.rangeSelections.revealSelectionTick.value;

      s.standing.keepStandingShown();

      expect(s.activeLayerId, _b, reason: 'x is the row above, b the head');
      // ③: the row it hands to may sit past the scroll, and nothing was
      // pointing at it — the rails are asked to bring it into view.
      expect(s.rangeSelections.revealSelectionTick.value, reveals + 1);

      s.standing.keepStandingShown();
      expect(
        s.rangeSelections.revealSelectionTick.value,
        reveals + 1,
        reason: 'a row already on screen moves nothing, so asks no scroll',
      );
    });

    test('③ a group opened for where you went asks for the scroll too', () {
      final s = session(_reported);
      s.selectLayer(_bMinus1);
      s.railView.collapsedAttachBaseIds.value = {_b};
      final reveals = s.rangeSelections.revealSelectionTick.value;

      s.standing.keepStandingShown(reveal: true);

      expect(s.activeLayerId, _bMinus1);
      expect(s.railView.collapsedAttachBaseIds.value, isEmpty);
      expect(s.rangeSelections.revealSelectionTick.value, reveals + 1);
    });

    test('a head the filter hides hands on to the nearest shown row above IT',
        () {
      const red = LayerMark(process: LayerProcess.layout);
      const blue = LayerMark(process: LayerProcess.conte);
      final s = session([
        _drawing('a', mark: red),
        _drawing('b', mark: blue),
        _drawing(
          'b+1',
          attachedTo: _b,
          placement: AttachedPlacement.above,
          mark: red,
        ),
        _drawing('x', mark: red),
      ]);
      s.selectLayer(plusOne);
      s.railView.collapsedAttachBaseIds.value = {_b};
      s.railView.rowFilter.value = TimelineRowFilter(markColors: {red});

      s.standing.keepStandingShown();

      expect(s.activeLayerId, const LayerId('x'));
    });
  });

  group('① the rail\'s own view changes hand the standing on', () {
    testWidgets('hiding the section you stand in', (tester) async {
      final camera = createCameraLayer(cutId: _cut);
      final session = await _open(
        tester,
        _project([_drawing('a'), camera]),
      );
      session.selectLayer(camera.id);
      await tester.pumpAndSettle();

      await _pick(tester, 'legend-sections', 'legend-section-camera');

      expect(session.activeLayerId, _a);
      expect(_row(camera.id), findsNothing);
    });

    testWidgets('setting a filter the row you stand on fails (UI-R6 #3)', (
      tester,
    ) async {
      const red = LayerMark(process: LayerProcess.layout);
      const blue = LayerMark(process: LayerProcess.conte);
      final session = await _open(
        tester,
        _project([
          _drawing('red-a', mark: red),
          _drawing('blue-x', mark: blue),
        ]),
      );
      session.selectLayer(const LayerId('blue-x'));
      await tester.pumpAndSettle();

      await _pick(tester, 'legend-mark', 'legend-filter-mark-layout');

      expect(session.activeLayerId, const LayerId('red-a'));
      expect(_row(const LayerId('blue-x')), findsNothing);
    });
  });

  group('② where you WENT opens', () {
    testWidgets('an undo that brings a row back into a folded group unfolds '
        'the group and stands there', (tester) async {
      final session = await _open(
        tester,
        _project([
          _drawing('a'),
          _drawing('b-2', attachedTo: _b),
          _drawing('b-1', attachedTo: _b),
          _drawing('b'),
        ]),
      );
      session.selectLayer(_bMinus1);
      session.layerVerbs.deleteActiveLayer();
      await tester.pumpAndSettle();
      await _twirl(tester, _b);
      expect(_row(_bMinus2), findsNothing);

      session.undo();
      await tester.pumpAndSettle();

      expect(session.activeLayerId, _bMinus1);
      expect(session.railView.collapsedAttachBaseIds.value, isEmpty);
      expect(_row(_bMinus1), findsOneWidget);
      expect(_row(_bMinus2), findsOneWidget);
    });

    testWidgets('a new attach row made on a folded group\'s base opens the '
        'group — the whole group, not the one row', (tester) async {
      final session = await _open(tester, _project(_reported));
      session.selectLayer(_b);
      await _twirl(tester, _b);

      session.folders.addAttachedLayer(AttachedPlacement.below);
      await tester.pumpAndSettle();
      final made = session.activeLayerId!;

      expect(made, isNot(_b));
      expect(session.railView.collapsedAttachBaseIds.value, isEmpty);
      expect(_row(made), findsOneWidget);
      expect(_row(_bMinus1), findsOneWidget);
    });

    testWidgets('a new row in a hidden section shows the section', (
      tester,
    ) async {
      final session = await _open(tester, _project([_drawing('a')]));
      await _pick(tester, 'legend-sections', 'legend-section-camera');

      session.layerStack.addLayerOfKind(LayerKind.instruction);
      await tester.pumpAndSettle();
      final made = session.activeLayerId!;

      expect(made, isNot(_a));
      expect(session.railView.hiddenSections.value, isEmpty);
      expect(_row(made), findsOneWidget);
    });

    testWidgets('…and the filter spares it there, the way it spares the row '
        'you are on — the section opening does not hand it off', (
      tester,
    ) async {
      final session = await _open(
        tester,
        _project([
          _drawing('a', mark: const LayerMark(process: LayerProcess.layout)),
        ]),
      );
      await _pick(tester, 'legend-mark', 'legend-filter-mark-layout');
      await _pick(tester, 'legend-sections', 'legend-section-camera');

      // An instruction row carries no mark: the LO filter refuses it.
      session.layerStack.addLayerOfKind(LayerKind.instruction);
      await tester.pumpAndSettle();
      final made = session.activeLayerId!;

      expect(made, isNot(_a));
      expect(_row(made), findsOneWidget);
    });
  });

  group('the doors that seat a row outside the session\'s rebuild', () {
    // 🪦② 「a file opens standing where it was saved — a rail view that folds
    // that row away opens for it」 lived here, while an open came INTO a
    // session whose rail view could still be folding the saved row away. A
    // file opens as a session of its own now (I-7), born with nothing
    // folded; `a_project_opens_where_it_was_saved_test` pins where it stands.

    test('① a playback that follows into another cut stops on a row the '
        'rail shows', () async {
      const base = LayerId('c');
      final s = EditorSessionManager(
        initialProject: _project(
          [_drawing('a')],
          secondCut: [_drawing('c-1', attachedTo: base), _drawing('c')],
        ),
      );
      addTearDown(s.dispose);
      s.railView.collapsedAttachBaseIds.value = {base};
      s.playbackRig.playback.play(scope: PlaybackScope.allCuts);
      s.playbackRig.playback.seekToGlobalFrame(12);
      expect(
        s.activeCutId,
        const CutId('cut-2'),
        reason: 'fixture: the follow crossed into the second cut',
      );
      expect(
        s.activeLayerId,
        const LayerId('c-1'),
        reason: 'fixture: the quiet follow seats the bottom row, folded away',
      );

      s.playbackRig.playback.stop();
      await pumpEventQueue();

      expect(s.activeLayerId, base);
    });
  });
}
