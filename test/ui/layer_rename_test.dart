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
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/home_page.dart';

import 'flyout_test_helpers.dart';

const _renameButtonKey = ValueKey<String>('rename-layer-button');
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
  testWidgets('Rename Layer lives in the Layer flyout and opens a '
      'prefilled dialog', (tester) async {
    await tester.pumpWidget(const AnicelApp());

    expect(find.byKey(_renameButtonKey), findsNothing);
    expect(await readCommandEnabled(tester, _renameButtonKey), isTrue);

    await _tapKey(tester, _renameButtonKey);

    expect(find.byKey(_dialogKey), findsOneWidget);
    expect(_fieldText(tester), 'A');
  });

  testWidgets('Rename Layer is disabled without an active layer', (
    tester,
  ) async {
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
    expect(_layerKindIcon(tester, _layerAId), Icons.brush_outlined);

    await _renameLayer(tester, 'BG');

    expect(
      find.byKey(const ValueKey<String>('timeline-layer-kind-icon-layer-a')),
      findsOneWidget,
    );
    expect(_layerKindIcon(tester, _layerAId), Icons.brush_outlined);
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

Future<void> _renameLayer(WidgetTester tester, String name) async {
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
