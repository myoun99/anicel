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
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart'
    show createCameraLayer;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

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
  LayerId? folderId,
  LayerMark mark = LayerMark.none,
}) => Layer(
  id: LayerId(id),
  name: id,
  frames: [Frame(id: FrameId('$id-cel'), duration: 1, strokes: const [])],
  timeline: const {},
  attachedToLayerId: attachedTo,
  attachedPlacement: AttachedPlacement.below,
  folderId: folderId,
  mark: mark,
);

Project _project(List<Layer> layers, {List<Layer> secondCut = const []}) =>
    Project(
      id: const ProjectId('standing-law'),
      name: 'Standing law',
      createdAt: DateTime.utc(2026, 9, 24),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Video',
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
final _reported = [_drawing('a'), _drawing('b-1', attachedTo: _b), _drawing('b')];

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
  });
}
