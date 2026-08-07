import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/dialogue_fit_text.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart'
    show seNameBoxExtent;

import 'timeline_cell_probe.dart';

const _cutId = CutId('se-cut');
const _seLayerId = LayerId('se-voice');
const _celLayerId = LayerId('se-cel');

/// SE row fixture: one cel layer (empty) and one SE layer with a named
/// 3-frame entry at frame 1; the sheet fixtures (S1/S2/CAM) are omitted so
/// each behavior reads off exactly one row.
Project _project({
  Map<int, TimelineExposure>? seTimeline,
  List<Frame>? frames,
}) {
  return Project(
    id: const ProjectId('se-project'),
    name: 'SE Project',
    createdAt: DateTime.utc(2026, 7, 8),
    tracks: [
      Track(
        id: const TrackId('se-track'),
        name: 'Video',
        cuts: [
          Cut(
            id: _cutId,
            name: 'SE Cut',
            duration: 12,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              Layer(
                id: _celLayerId,
                name: 'A',
                frames: const [],
                timeline: const {},
              ),
              Layer(
                id: _seLayerId,
                name: 'S1',
                kind: LayerKind.se,
                frames:
                    frames ??
                    [
                      Frame(
                        id: const FrameId('se-f1'),
                        duration: 3,
                        name: 'Hello!',
                        strokes: const [],
                      ),
                    ],
                timeline:
                    seTimeline ??
                    {
                      1: const TimelineExposure.drawing(
                        FrameId('se-f1'),
                        length: 3,
                      ),
                    },
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

Future<void> _pumpHome(
  WidgetTester tester,
  Project project, {
  void Function(ProjectRepository repository)? onRepositoryCreated,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: HomePage(
        initialProject: project,
        onRepositoryCreated: onRepositoryCreated,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _ensureRowVisible(WidgetTester tester, LayerId layerId) async {
  await tester.ensureVisible(
    find.byKey(ValueKey<String>('timeline-layer-row-$layerId')),
  );
  await tester.pumpAndSettle();
}

Future<void> _doubleTapCell(
  WidgetTester tester,
  String layerId,
  int frameIndex,
) async {
  // The SE row paints its cells (R28 #4) — the tap point comes from the
  // painter probe, not a cell widget.
  final target = timelineCellCenter(tester, layerId, frameIndex);
  await tester.tapAt(target);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tapAt(target);
  await tester.pumpAndSettle();
}

/// The dialogue text carried by an SE span overlay — painted glyphs, so
/// find.text cannot see it; read the widget field instead.
String _seDialogueAt(WidgetTester tester, String overlayKey) {
  final fit = tester.widget<DialogueFitText>(
    find.descendant(
      of: find.byKey(ValueKey<String>(overlayKey)),
      matching: find.byType(DialogueFitText),
    ),
  );
  return fit.text;
}

List<String> _allSeDialogues(WidgetTester tester) {
  return [
    for (final widget in tester.widgetList<DialogueFitText>(
      find.byType(DialogueFitText),
    ))
      widget.text,
  ];
}

Layer _seLayer(ProjectRepository repository) {
  return repository
      .requireProject()
      .tracks
      .single
      .cuts
      .single
      .layers
      .firstWhere((layer) => layer.id == _seLayerId);
}

void main() {
  testWidgets(
    'SE row paints paper blocks with the fitted dialogue overlay, no cell '
    'glyphs or X',
    (tester) async {
      await _pumpHome(tester, _project());
      await _ensureRowVisible(tester, _seLayerId);

      // The dialogue rides the block-span overlay as painted fitted glyphs.
      expect(
        find.byKey(const ValueKey<String>('timeline-se-label-se-voice-1')),
        findsOneWidget,
      );
      expect(_seDialogueAt(tester, 'timeline-se-label-se-voice-1'), 'Hello!');
      // No Text glyph duplicates the dialogue on the start cell.
      expect(find.text('Hello!'), findsNothing);

      // Covered SE cells paint the same white paper as drawing blocks.
      // The SE row is PAINTED now (R28 #4) — read the painter's style.
      expect(
        timelineCellDecoration(tester, 'se-voice', 1).color,
        timelineDrawingHeldColor,
      );

      // No name box without a seName.
      expect(find.bySemanticsLabel(RegExp('^SE name')), findsNothing);

      // No X anywhere on the SE row; the empty cel row still gets its X.
      for (var frame = 0; frame < 8; frame += 1) {
        expect(
          timelineCellModel(tester, 'se-voice', frame).glyph,
          isNot('X'),
          reason: 'frame $frame',
        );
      }
      await _ensureRowVisible(tester, _celLayerId);
      // The cel row is PAINTED (UI-R9 #12b): the X reads off the painter.
      expect(timelineCellModel(tester, 'se-cel', 0).glyph, 'X');
    },
  );

  testWidgets('an entry with a seName shows the accent name box at the '
      'block start', (tester) async {
    await _pumpHome(
      tester,
      _project(
        frames: [
          Frame(
            id: const FrameId('se-f1'),
            duration: 3,
            name: '그건 아니라고 생각해',
            seName: '앨리스',
            strokes: const [],
          ),
        ],
      ),
    );
    await _ensureRowVisible(tester, _seLayerId);

    expect(find.bySemanticsLabel('SE name 앨리스'), findsOneWidget);
    expect(
      _seDialogueAt(tester, 'timeline-se-label-se-voice-1'),
      '그건 아니라고 생각해',
    );
  });

  testWidgets('the XSheet SE name box is a slim horizontal band, never a '
      'frame-cells-tall stack (R3 fix)', (tester) async {
    await _pumpHome(
      tester,
      _project(
        frames: [
          Frame(
            id: const FrameId('se-f1'),
            duration: 3,
            name: '그건 아니라고 생각해',
            seName: '앨리스',
            strokes: const [],
          ),
        ],
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();

    final nameBox = find.bySemanticsLabel('SE name 앨리스');
    expect(nameBox, findsOneWidget);
    final size = tester.getSize(nameBox);
    // A partial band of the first frame cell, written horizontally.
    expect(size.height, seNameBoxExtent);
    expect(size.width, greaterThan(size.height));
  });

  testWidgets('XSheet SE column shows the same label overlay', (tester) async {
    await _pumpHome(tester, _project());

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('xsheet-se-label-se-voice-1')),
      findsOneWidget,
    );
    expect(_seDialogueAt(tester, 'xsheet-se-label-se-voice-1'), 'Hello!');
  });

  testWidgets('SE empty stretches carry NO furniture on the editing grids '
      '(R5-② — dark uncovered cells already read as empty; the gray wash '
      'is print-sheet only)', (tester) async {
    await _pumpHome(tester, _project());
    await _ensureRowVisible(tester, _seLayerId);

    expect(
      find.byKey(const ValueKey<String>('timeline-se-empty-se-voice-0')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-se-empty-se-voice-4')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('xsheet-se-empty-se-voice-4')),
      findsNothing,
    );
  });

  testWidgets('double-tap on an empty SE cell creates a ONE-frame labeled '
      'entry in one undo (the grips own the length)', (tester) async {
    // A window the default arrangement fits in — the floating region opens
    // at 2/3 of the width, and this test zooms the axis out and then works
    // near the far end of it.
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late ProjectRepository repository;
    await _pumpHome(
      tester,
      _project(seTimeline: const {}, frames: const []),
      onRepositoryCreated: (repo) => repository = repo,
    );
    await _ensureRowVisible(tester, _seLayerId);
    // Zoom to classic 48px cells: a ONE-frame span at the slim 24px default
    // is narrower than the 32px name-box drop threshold (the overflow
    // invariant), and this test reads the name box.
    tester
        .widget<FieldSlider>(
          find.byKey(const ValueKey<String>('timeline-zoom-slider')),
        )
        .onChanged!(48);
    await tester.pumpAndSettle();

    // Double-tap on the EMPTY cell creates the default entry DIRECTLY —
    // no dialog (UI-R25 #2, 조작 통일화).
    await _doubleTapCell(tester, 'se-voice', 4);
    expect(find.text('New SE'), findsNothing, reason: 'creation is silent');
    var layer = _seLayer(repository);
    expect(layer.timeline[4]!.length, 1, reason: 'one frame, like cels');
    expect(layer.frames.single.name, isNull, reason: 'unlabeled default');

    // The SECOND double-tap (now a covered cell) opens the edit dialog —
    // labeling stays the dialog's job.
    await _doubleTapCell(tester, 'se-voice', 4);
    await tester.enterText(
      find.byKey(const ValueKey<String>('se-dialogue-field')),
      '와아!',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('se-name-field')),
      '앨리스',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('instance-edit-ok-button')),
    );
    await tester.pumpAndSettle();

    layer = _seLayer(repository);
    expect(layer.frames.single.name, '와아!');
    expect(layer.frames.single.seName, '앨리스');
    expect(_seDialogueAt(tester, 'timeline-se-label-se-voice-4'), '와아!');
    expect(find.bySemanticsLabel('SE name 앨리스'), findsOneWidget);

    // Undo pops the label edit, then the creation.
    await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
    await tester.pumpAndSettle();
    expect(_seLayer(repository).frames.single.name, isNull);
    await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
    await tester.pumpAndSettle();
    expect(_seLayer(repository).timeline, isEmpty);
    expect(_seLayer(repository).frames, isEmpty);
  });

  testWidgets('double-tap on an existing SE entry edits its label; duplicate '
      'dialogue is allowed', (tester) async {
    late ProjectRepository repository;
    await _pumpHome(
      tester,
      _project(
        frames: [
          Frame(
            id: const FrameId('se-f1'),
            duration: 3,
            name: 'Hello!',
            strokes: const [],
          ),
          Frame(
            id: const FrameId('se-f2'),
            duration: 2,
            name: 'Again',
            strokes: const [],
          ),
        ],
        seTimeline: {
          1: const TimelineExposure.drawing(FrameId('se-f1'), length: 3),
          6: const TimelineExposure.drawing(FrameId('se-f2'), length: 2),
        },
      ),
      onRepositoryCreated: (repo) => repository = repo,
    );
    await _ensureRowVisible(tester, _seLayerId);

    // Edit the second entry to the SAME text as the first: SE rows allow
    // duplicate dialogue (no link-conflict flow).
    await _doubleTapCell(tester, 'se-voice', 6);
    expect(find.text('Edit SE'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey<String>('se-dialogue-field')),
      'Hello!',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('instance-edit-ok-button')),
    );
    await tester.pumpAndSettle();

    final layer = _seLayer(repository);
    expect(layer.frames.map((frame) => frame.name), ['Hello!', 'Hello!']);
    expect(_allSeDialogues(tester).where((text) => text == 'Hello!').length, 2);
  });
}
