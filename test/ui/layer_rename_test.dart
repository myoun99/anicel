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

import 'flyout_test_helpers.dart';

/// 🚨T25 — renaming a layer goes through the SHARED pill's Edit Instance
/// now (유저 2026-08-14: 「인스턴스 편집 버튼도 공통버튼으로 이동 … 그러고
/// 레이어 이름변경 버튼 필요없어지니 삭제」).
///
/// ⛔`rename-layer-button` is gone, so this file follows the FLOW rather
/// than the widget: **select the row, then press the one verb** — the same
/// two steps the layer DELETE already took when ⑰ absorbed it. What the
/// rename does once it opens has not changed at all.
const _renameButtonKey = ValueKey<String>('shared-edit-button');
const _dialogKey = ValueKey<String>('rename-layer-dialog');
const _textFieldKey = ValueKey<String>('rename-layer-text-field');
const _cancelButtonKey = ValueKey<String>('rename-layer-cancel-button');
const _okButtonKey = ValueKey<String>('rename-layer-ok-button');
const _undoKey = ValueKey<String>('undo-button');
const _redoKey = ValueKey<String>('redo-button');
const _cutId = CutId('rename-cut');
const _layerAId = LayerId('layer-a');
const _layerBId = LayerId('layer-b');
const _frameId = FrameId('frame-a');

void main() {
  testWidgets('a selected row makes the shared Edit Instance rename it, '
      'prefilled', (tester) async {
    await tester.pumpWidget(const AnicelApp());

    // ① took it out of the menu; T25 took it out of the LAYER pill. It is
    // still reachable without opening anything — which is all 「밖으로」
    // ever asked for — but the door is the shared one now, and which noun
    // it means comes from the selection.
    expect(find.byKey(_renameButtonKey), findsOneWidget);

    await _selectActiveRow(tester);
    expect(await readCommandEnabled(tester, _renameButtonKey), isTrue);

    await _tapKey(tester, _renameButtonKey);

    expect(find.byKey(_dialogKey), findsOneWidget);
    expect(_fieldText(tester), 'A');
  });

  testWidgets('with no layer at all there is nothing to rename', (
    tester,
  ) async {
    // The subject ladder's bottom rung: no cut selection, no rows, no cell
    // to name — `EditInstanceSubject.nothing`, and the one verb dims. It
    // used to be the loose button's own `_canEditActiveLayer`; the answer
    // is the same and now only one thing computes it.
    await _pumpHome(tester, project: _project(layers: const []));

    expect(await readCommandEnabled(tester, _renameButtonKey), isFalse);
  });

  testWidgets('renaming A to BG updates label and keeps active selection', (
    tester,
  ) async {
    late ProjectRepository repository;
    await _pumpHome(tester, onRepositoryCreated: (repo) => repository = repo);

    expect(
      find.byKey(const ValueKey<String>('timeline-layer-name-layer-a')),
      findsOneWidget,
    );
    expect(_layerNameText(tester, _layerAId).data, 'A');

    await _renameLayer(tester, 'BG');

    expect(_layer(repository, _layerAId).name, 'BG');
    expect(_layerNameText(tester, _layerAId).data, 'BG');
    expect(find.text('BG'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('timeline-selected-layer')),
      findsOneWidget,
    );
    expect(_layerNameText(tester, _layerAId).data, 'BG');
  });

  testWidgets('cancel changes nothing', (tester) async {
    late ProjectRepository repository;
    await _pumpHome(tester, onRepositoryCreated: (repo) => repository = repo);

    await _selectActiveRow(tester);
    await _tapKey(tester, _renameButtonKey);
    await tester.enterText(find.byKey(_textFieldKey), 'BG');
    await _tapKey(tester, _cancelButtonKey);

    expect(_layer(repository, _layerAId).name, 'A');
    expect(_layerNameText(tester, _layerAId).data, 'A');
    expect(find.byKey(_dialogKey), findsNothing);
  });

  testWidgets('empty name keeps dialog open and duplicate name is allowed', (
    tester,
  ) async {
    late ProjectRepository repository;
    await _pumpHome(tester, onRepositoryCreated: (repo) => repository = repo);

    await _selectActiveRow(tester);
    await _tapKey(tester, _renameButtonKey);
    await tester.enterText(find.byKey(_textFieldKey), '   ');
    await _tapKey(tester, _okButtonKey);

    expect(find.byKey(_dialogKey), findsOneWidget);
    expect(find.text('Layer name cannot be empty.'), findsOneWidget);
    expect(_layer(repository, _layerAId).name, 'A');

    await tester.enterText(find.byKey(_textFieldKey), 'B');
    await _tapKey(tester, _okButtonKey);

    expect(find.byKey(_dialogKey), findsNothing);
    expect(_layer(repository, _layerAId).name, 'B');
    expect(_layer(repository, _layerBId).name, 'B');
  });

  testWidgets('undo and redo rename from the UI', (tester) async {
    late ProjectRepository repository;
    await _pumpHome(tester, onRepositoryCreated: (repo) => repository = repo);

    await _renameLayer(tester, 'BG');
    expect(_layer(repository, _layerAId).name, 'BG');

    await _tapKey(tester, _undoKey);
    expect(_layer(repository, _layerAId).name, 'A');
    expect(_layerNameText(tester, _layerAId).data, 'A');

    await _tapKey(tester, _redoKey);
    expect(_layer(repository, _layerAId).name, 'BG');
    expect(_layerNameText(tester, _layerAId).data, 'BG');
  });

  testWidgets('layer kind icon remains visible after rename', (tester) async {
    await _pumpHome(tester);

    expect(
      find.byKey(const ValueKey<String>('timeline-layer-kind-icon-layer-a')),
      findsOneWidget,
    );
    expect(_layerKindIcon(tester, _layerAId), Icons.filter_frames);

    await _renameLayer(tester, 'BG');

    expect(
      find.byKey(const ValueKey<String>('timeline-layer-kind-icon-layer-a')),
      findsOneWidget,
    );
    expect(_layerKindIcon(tester, _layerAId), Icons.filter_frames);
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

// Menu-aware (R-toolbar round): rename lives in the Layer ▾ flyout.
Future<void> _tapKey(WidgetTester tester, ValueKey<String> key) =>
    tapCommandButton(tester, key);

/// T25's first step. `beginRowSelection` is the real verb the rail's select
/// drag calls — it claims the selection domain as well as filling it, which
/// poking the notifier would skip. Lifted from `layer_delete_test`, where
/// the same two-step flow landed one rung earlier.
Future<void> _selectActiveRow(WidgetTester tester) async {
  final session = tester
      .widget<EditorWorkspace>(find.byType(EditorWorkspace))
      .session;
  session.beginRowSelection(LayerRowAddress(session.activeLayerId!));
  await tester.pumpAndSettle();
}

Future<void> _renameLayer(WidgetTester tester, String name) async {
  await _selectActiveRow(tester);
  await _tapKey(tester, _renameButtonKey);
  await tester.enterText(find.byKey(_textFieldKey), name);
  await _tapKey(tester, _okButtonKey);
}

String _fieldText(WidgetTester tester) {
  return tester.widget<TextField>(find.byKey(_textFieldKey)).controller!.text;
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

Text _layerNameText(WidgetTester tester, LayerId layerId) {
  final nameFinder = find.byKey(
    ValueKey<String>('timeline-layer-name-$layerId'),
  );
  final textFinder = find.descendant(
    of: nameFinder,
    matching: find.byType(Text),
  );
  return tester.widget<Text>(textFinder.first);
}

IconData _layerKindIcon(WidgetTester tester, LayerId layerId) {
  return tester
      .widget<Icon>(
        find.byKey(ValueKey<String>('timeline-layer-kind-icon-$layerId')),
      )
      .icon!;
}

Project _project({List<Layer>? layers}) {
  return Project(
    id: const ProjectId('rename-project'),
    name: 'Rename Project',
    createdAt: DateTime.utc(2026, 6, 12),
    tracks: [
      Track(
        id: const TrackId('rename-track'),
        name: 'Track',
        cuts: [
          Cut(
            id: _cutId,
            name: 'Cut',
            duration: 1,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            layers:
                layers ??
                [_layerModel(_layerAId, 'A'), _layerModel(_layerBId, 'B')],
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
    kind: LayerKind.animation,
    frames: [Frame(id: _frameId, duration: 1, strokes: const [])],
    timeline: const {},
  );
}
