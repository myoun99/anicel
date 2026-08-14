import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart';

import 'flyout_test_helpers.dart';

// ⑰ (2026-08-12): Delete Layer left the Layer FLYOUT, then left its own
// button too. 유저: 「딜리트 = 버튼 하나 … 레이어를 선택했으면 레이어 삭제」.
//
// The verb never changed and nothing below it did either — only the door,
// twice: a menu entry, then the bar button beside the `＋`, and now the ONE
// delete in the shared pill, which asks what is selected. Everything this
// file pins (enablement, the dialog, cancel, confirm, undo/redo, the rail
// afterwards) is the same flow through that door.
const _deleteButtonKey = ValueKey<String>('shared-delete-button');
const _dialogKey = ValueKey<String>('delete-layer-dialog');
const _cancelButtonKey = ValueKey<String>('delete-layer-cancel-button');
const _confirmButtonKey = ValueKey<String>('delete-layer-confirm-button');
/// T25 folded the loose `rename-layer-button` into the shared pill's Edit
/// Instance, which takes its subject from the selection — the same two-step
/// flow (select the row, then the one verb) this file's DELETE already uses.
const _renameButtonKey = ValueKey<String>('shared-edit-button');
const _renameTextFieldKey = ValueKey<String>('rename-layer-text-field');
const _renameOkButtonKey = ValueKey<String>('rename-layer-ok-button');
const _undoKey = ValueKey<String>('undo-button');
const _redoKey = ValueKey<String>('redo-button');
const _orientationToggleKey = ValueKey<String>(
  'timeline-orientation-toggle-button',
);
const _cutId = CutId('delete-cut');
const _layerAId = LayerId('layer-a');
const _layerBId = LayerId('layer-b');
const _layerCId = LayerId('layer-c');
const _frameId = FrameId('frame-a');

/// Enablement of a BAR button — the delete moved out of the flyout, so it is
/// no longer a `PopupMenuItem` and `readCommandEnabled` (which opens a menu)
/// cannot answer for it.
bool _barButtonEnabled(WidgetTester tester, ValueKey<String> key) =>
    tester.widget<IconButton>(find.byKey(key)).onPressed != null;

void main() {
  testWidgets('ONE delete: no layer button of its own, and no menu entry '
      'either', (tester) async {
    await tester.pumpWidget(const AnicelApp());

    // The shared pill's delete is the only door left.
    expect(find.byKey(_deleteButtonKey), findsOneWidget);
    // ⑰ removed the menu entry first…
    expect(
      find.byKey(const ValueKey<String>('delete-layer-button')),
      findsNothing,
    );
    // …and then the loose bar button, once ⑨ gave the shared verb a way to
    // name a layer at all.
    expect(
      find.byKey(const ValueKey<String>('timeline-delete-layer-button')),
      findsNothing,
    );
  });

  testWidgets('R28 #14: deleting is ENABLED with one layer — the cut '
      'may end up empty', (tester) async {
    await _pumpHome(
      tester,
      project: _project(layers: [_layerModel(_layerAId, 'A')]),
    );
    await _selectActiveRow(tester);

    expect(
      _barButtonEnabled(tester, _deleteButtonKey),
      isTrue,
      reason: 'R28 #14: the drawing floor that greyed this command is gone',
    );
  });

  testWidgets('deleting is enabled with two or more layers', (tester) async {
    await _pumpHome(tester);
    await _selectActiveRow(tester);

    expect(_barButtonEnabled(tester, _deleteButtonKey), isTrue);
  });

  testWidgets('confirmation dialog opens and cancel changes nothing', (
    tester,
  ) async {
    late ProjectRepository repository;
    await _pumpHome(tester, onRepositoryCreated: (repo) => repository = repo);
    // Name the row first: with nothing selected the one delete answers a
    // lower rung (the frame block under the playhead), which is a different
    // verb and asks nothing.
    await _selectActiveRow(tester);

    await _tapKey(tester, _deleteButtonKey);

    expect(find.byKey(_dialogKey), findsOneWidget);
    expect(find.text('Delete layer "A"?'), findsOneWidget);

    await _tapKey(tester, _cancelButtonKey);

    expect(find.byKey(_dialogKey), findsNothing);
    expect(_layerNames(repository), ['A', 'B', 'C']);
  });

  testWidgets('confirm deletes active layer and selects stable nearby layer', (
    tester,
  ) async {
    late ProjectRepository repository;
    await _pumpHome(tester, onRepositoryCreated: (repo) => repository = repo);
    await _selectLayer(tester, _layerBId);
    expect(_selectedLayerName(tester), 'B');

    await _deleteActiveLayer(tester);

    expect(_layerNames(repository), ['A', 'C']);
    expect(_selectedLayerName(tester), 'C');
    expect(
      find.byKey(const ValueKey<String>('timeline-layer-row-layer-b')),
      findsNothing,
    );
    expect(_selectedLayerName(tester), 'C');
  });

  testWidgets('undo and redo layer delete from the UI', (tester) async {
    late ProjectRepository repository;
    await _pumpHome(tester, onRepositoryCreated: (repo) => repository = repo);
    await _selectLayer(tester, _layerBId);
    expect(_selectedLayerName(tester), 'B');
    await _deleteActiveLayer(tester);

    await _tapKey(tester, _undoKey);
    expect(_layerNames(repository), ['A', 'B', 'C']);
    expect(_selectedLayerName(tester), 'B');

    await _tapKey(tester, _redoKey);
    expect(_layerNames(repository), ['A', 'C']);
    expect(_selectedLayerName(tester), 'C');
  });

  testWidgets(
    'horizontal and XSheet display order remain correct after delete',
    (tester) async {
      await _pumpHome(tester);
      await _selectLayer(tester, _layerBId);
      expect(_selectedLayerName(tester), 'B');
      await _deleteActiveLayer(tester);

      expect(_visibleTimelineLayerNames(tester), ['C', 'A']);
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey<String>('timeline-layer-row-layer-c')),
            )
            .dy,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(
                  const ValueKey<String>('timeline-layer-row-layer-a'),
                ),
              )
              .dy,
        ),
      );

      await _tapKey(tester, _orientationToggleKey);

      expect(_visibleXSheetLayerNames(tester), ['A', 'C']);
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey<String>('xsheet-layer-header-layer-a')),
            )
            .dx,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(
                  const ValueKey<String>('xsheet-layer-header-layer-c'),
                ),
              )
              .dx,
        ),
      );
    },
  );

  testWidgets('icons remain visible and rename still works after delete', (
    tester,
  ) async {
    late ProjectRepository repository;
    await _pumpHome(tester, onRepositoryCreated: (repo) => repository = repo);
    await _selectLayer(tester, _layerBId);
    expect(_selectedLayerName(tester), 'B');
    await _deleteActiveLayer(tester);

    expect(
      find.byKey(const ValueKey<String>('timeline-layer-kind-icon-layer-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-layer-kind-icon-layer-c')),
      findsOneWidget,
    );

    await _selectActiveRow(tester);
    await _tapKey(tester, _renameButtonKey);
    await tester.enterText(find.byKey(_renameTextFieldKey), 'BG');
    await _tapKey(tester, _renameOkButtonKey);

    expect(_layer(repository, _layerCId).name, 'BG');
    expect(_selectedLayerName(tester), 'BG');
  });
}

Future<void> _pumpHome(
  WidgetTester tester, {
  Project? project,
  void Function(ProjectRepository repository)? onRepositoryCreated,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: HomePage(
        initialProject: project ?? _project(),
        onRepositoryCreated: onRepositoryCreated,
      ),
    ),
  );
}

// Menu-aware (R-toolbar round): the layer commands live in the Layer ▾
// flyout; direct keys pass through unchanged.
Future<void> _tapKey(WidgetTester tester, ValueKey<String> key) =>
    tapCommandButton(tester, key);

Future<void> _selectLayer(WidgetTester tester, LayerId layerId) async {
  await _tapKey(tester, ValueKey<String>('timeline-layer-name-$layerId'));
  await tester.pumpAndSettle();
}

/// ⑰/F: deleting a layer is now SELECT THE ROW, then press the one delete.
///
/// Standing on a row is not selecting it — ⑨ made those two states
/// independent on purpose — so the flow has a step the old loose button did
/// not. The selection is set through the session rather than nudged through
/// the rail here: how a row GETS selected is `row_selection_test`'s subject
/// (and it drives the real drag), while this file's subject is what the
/// delete then does.
Future<void> _selectActiveRow(WidgetTester tester) async {
  final session = tester
      .widget<EditorWorkspace>(find.byType(EditorWorkspace))
      .session;
  // The real verb, not the notifier: `beginRowSelection` is what the rail's
  // select drag calls, and it claims the selection domain as well as filling
  // it — poking the notifier alone leaves the rest of the session behind.
  session.beginRowSelection(LayerRowAddress(session.activeLayerId!));
  await tester.pumpAndSettle();
}

Future<void> _deleteActiveLayer(WidgetTester tester) async {
  await _selectActiveRow(tester);
  await _tapKey(tester, _deleteButtonKey);
  await _tapKey(tester, _confirmButtonKey);
}

List<String> _layerNames(ProjectRepository repository) {
  return repository
      .requireProject()
      .tracks
      .single
      .cuts
      .single
      .layers
      .map((layer) => layer.name)
      .toList();
}

Layer _layer(ProjectRepository repository, LayerId layerId) {
  return repository
      .requireProject()
      .tracks
      .single
      .cuts
      .single
      .layers
      .singleWhere((layer) => layer.id == layerId);
}

String _selectedLayerName(WidgetTester tester) {
  final selected = find.byKey(
    const ValueKey<String>('timeline-selected-layer'),
  );
  final texts = find.descendant(of: selected, matching: find.byType(Text));
  // Skip the section gutter label (ACTION/SE/CAM) that leads a
  // section's first row; the layer name is the next text.
  const gutterLabels = {'ACTION', 'SE', 'CAM'};
  return tester
      .widgetList<Text>(texts)
      .map((text) => text.data)
      .firstWhere((data) => data != null && !gutterLabels.contains(data))!;
}

List<String> _visibleTimelineLayerNames(WidgetTester tester) {
  return [_layerText(tester, _layerCId), _layerText(tester, _layerAId)];
}

List<String> _visibleXSheetLayerNames(WidgetTester tester) {
  return [
    _xsheetLayerText(tester, _layerAId),
    _xsheetLayerText(tester, _layerCId),
  ];
}

String _layerText(WidgetTester tester, LayerId layerId) {
  final textFinder = find.descendant(
    of: find.byKey(ValueKey<String>('timeline-layer-name-$layerId')),
    matching: find.byType(Text),
  );
  return tester.widget<Text>(textFinder.first).data!;
}

/// R10 R6: a column name reads DOWN its 28px column, so it is vertical
/// writing rather than a `Text` — one painter draws the whole stack.
String _xsheetLayerText(WidgetTester tester, LayerId layerId) {
  final textFinder = find.descendant(
    of: find.byKey(ValueKey<String>('xsheet-layer-name-$layerId')),
    matching: find.byType(VerticalWritingText),
  );
  return tester.widget<VerticalWritingText>(textFinder.first).text;
}

Project _project({List<Layer>? layers}) {
  return Project(
    id: const ProjectId('delete-project'),
    name: 'Delete Project',
    createdAt: DateTime.utc(2026, 6, 12),
    tracks: [
      Track(
        id: const TrackId('delete-track'),
        name: 'Track',
        cuts: [
          Cut(
            id: _cutId,
            name: 'Cut',
            duration: 3,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            layers:
                layers ??
                [
                  _layerModel(_layerAId, 'A'),
                  _layerModel(_layerBId, 'B'),
                  _layerModel(_layerCId, 'C'),
                ],
          ),
        ],
      ),
    ],
  );
}

Layer _layerModel(LayerId id, String name) {
  return Layer(
    id: id,
    name: name,
    kind: id == _layerCId ? LayerKind.storyboard : LayerKind.animation,
    frames: [Frame(id: _frameId, duration: 1, strokes: const [])],
    timeline: const {},
  );
}
