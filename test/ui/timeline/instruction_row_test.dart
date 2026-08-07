import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/home_page.dart';

import 'timeline_cell_probe.dart';

const _cutId = CutId('inst-cut');
const _camLayerId = LayerId('inst-cam');
const _celLayerId = LayerId('inst-cel');

Project _project({Map<int, InstructionEvent>? instructions}) {
  return Project(
    id: const ProjectId('inst-project'),
    name: 'Instruction Project',
    createdAt: DateTime.utc(2026, 7, 8),
    tracks: [
      Track(
        id: const TrackId('inst-track'),
        name: 'Video',
        cuts: [
          Cut(
            id: _cutId,
            name: 'Instruction Cut',
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
                id: _camLayerId,
                name: 'CAM 1',
                kind: LayerKind.instruction,
                frames: const [],
                timeline: const {},
                instructions:
                    instructions ??
                    {
                      2: const InstructionEvent(
                        instructionId: 'pan',
                        length: 6,
                        valueA: 'A',
                        valueB: 'B',
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

// No ensureVisible here: cell-level ensureVisible over-scrolls the custom
// frame viewport and virtualizes earlier cells out of the window. The
// instruction row sits at the top of the display order, always on screen.
Future<void> _doubleTapCell(
  WidgetTester tester,
  String layerId,
  int frameIndex,
) async {
  // The instruction row paints its cells (R28 #4) — the tap point comes
  // from the painter probe, not a cell widget.
  final target = timelineCellCenter(tester, layerId, frameIndex);
  await tester.tapAt(target);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tapAt(target);
  await tester.pumpAndSettle();
}

Layer _camLayer(ProjectRepository repository) {
  return repository
      .requireProject()
      .tracks
      .single
      .cuts
      .single
      .layers
      .firstWhere((layer) => layer.id == _camLayerId);
}

void main() {
  testWidgets('instruction row shows the [icon+name] chip, A/B values and '
      'span overlay', (tester) async {
    await _pumpHome(tester, _project());

    expect(
      find.byKey(const ValueKey<String>('timeline-instruction-inst-cam-2')),
      findsOneWidget,
    );
    expect(find.text('PAN'), findsOneWidget);
    expect(find.text('A'), findsWidgets);
    expect(find.text('B'), findsOneWidget);
    // No X cells on instruction rows.
    final rowArea = find.byKey(
      const ValueKey<String>('timeline-frame-row-area-inst-cam'),
    );
    expect(
      find.descendant(of: rowArea, matching: find.text('X')),
      findsNothing,
    );
  });

  testWidgets('XSheet instruction column shows the same overlay', (
    tester,
  ) async {
    await _pumpHome(tester, _project());

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('xsheet-instruction-inst-cam-2')),
      findsOneWidget,
    );
    // Vertical writing stacks the name per glyph — assert via semantics.
    expect(
      find.bySemanticsLabel('instruction PAN from A to B'),
      findsOneWidget,
    );
  });

  testWidgets('double-tap on an empty instruction cell adds a ONE-frame '
      'event in one undo (the grips own the length)', (tester) async {
    late ProjectRepository repository;
    await _pumpHome(
      tester,
      _project(instructions: const {}),
      onRepositoryCreated: (repo) => repository = repo,
    );

    // Double-tap on the EMPTY cell creates a default-vocabulary event
    // DIRECTLY — no dialog (UI-R25 #2, 조작 통일화).
    await _doubleTapCell(tester, 'inst-cam', 4);
    expect(find.text('Add instruction'), findsNothing);
    var event = _camLayer(repository).instructions[4]!;
    expect(event.length, 1, reason: 'new instances are one frame long');

    // The SECOND double-tap (covered now) opens the editor: swap it to
    // PAN with endpoint values — editing stays the dialog's job.
    await _doubleTapCell(tester, 'inst-cam', 4);
    expect(find.text('Edit instruction'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('instruction-def-dropdown')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('instruction-option-pan')).last,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('instruction-value-a-field')),
      '0%',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('instruction-value-b-field')),
      '100%',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('instance-edit-ok-button')),
    );
    await tester.pumpAndSettle();

    event = _camLayer(repository).instructions[4]!;
    expect(event.instructionId, 'pan');
    expect(event.valueA, '0%');
    expect(event.valueB, '100%');
    expect(find.text('PAN'), findsWidgets);

    // Undo pops the edit, then the creation.
    await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
    await tester.pumpAndSettle();
    expect(_camLayer(repository).instructions, isEmpty);
  });

  testWidgets('free event text shows over the vocabulary name and edits '
      'through the dialog', (tester) async {
    late ProjectRepository repository;
    await _pumpHome(
      tester,
      _project(
        instructions: {
          2: const InstructionEvent(
            instructionId: 'pan',
            length: 6,
            text: 'メモリPAN',
          ),
        },
      ),
      onRepositoryCreated: (repo) => repository = repo,
    );

    // The chip prints the free text, not 'PAN'.
    expect(find.text('メモリPAN'), findsOneWidget);
    expect(find.text('PAN'), findsNothing);

    await _doubleTapCell(tester, 'inst-cam', 2);
    await tester.enterText(
      find.byKey(const ValueKey<String>('instruction-text-field')),
      '早いPAN',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('instance-edit-ok-button')),
    );
    await tester.pumpAndSettle();

    expect(_camLayer(repository).instructions[2]!.text, '早いPAN');
    expect(find.text('早いPAN'), findsOneWidget);
  });

  testWidgets('double-tap on an existing event edits it; Delete removes', (
    tester,
  ) async {
    late ProjectRepository repository;
    await _pumpHome(
      tester,
      _project(),
      onRepositoryCreated: (repo) => repository = repo,
    );

    // Edit the B value on the covering cell (not the start).
    await _doubleTapCell(tester, 'inst-cam', 5);
    expect(find.text('Edit instruction'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey<String>('instruction-value-b-field')),
      'B2',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('instance-edit-ok-button')),
    );
    await tester.pumpAndSettle();

    var event = _camLayer(repository).instructions[2]!;
    expect(event.valueB, 'B2');
    expect(event.length, 6, reason: 'length stays grip-owned');

    // Delete via the same dialog.
    await _doubleTapCell(tester, 'inst-cam', 2);
    await tester.tap(
      find.byKey(const ValueKey<String>('instance-edit-delete-button')),
    );
    await tester.pumpAndSettle();
    expect(_camLayer(repository).instructions, isEmpty);
  });

  testWidgets('end grip resizes an instruction span with one undo', (
    tester,
  ) async {
    // A window the default arrangement fits in. The floating region opens
    // at 2/3 of the width now, so at the 800px test default the strip is
    // narrow enough that this block's end grip lands under the panel's own
    // right edge and the drag never reaches it. The test is about the grip,
    // not about how much of it a small window shows.
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late ProjectRepository repository;
    await _pumpHome(
      tester,
      _project(),
      onRepositoryCreated: (repo) => repository = repo,
    );

    final endGrip = find.byKey(
      const ValueKey<String>('timeline-block-edge-grip-end-inst-cam-0'),
    );
    expect(endGrip, findsOneWidget);

    // Lengthen by 2 frames (24px slim cells). R10: the pixels the drag
    // spends winning the arena are TRAVEL, not overhead, so the TOTAL is
    // what counts — 19 + 29 = 48 = two cells exactly.
    final gesture = await tester.startGesture(tester.getCenter(endGrip));
    await gesture.moveBy(const Offset(19, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(29, 0));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_camLayer(repository).instructions[2]!.length, 8);

    await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
    await tester.pumpAndSettle();
    expect(_camLayer(repository).instructions[2]!.length, 6);
  });

  testWidgets('the vocabulary editor adds a custom instruction', (
    tester,
  ) async {
    late ProjectRepository repository;
    await _pumpHome(
      tester,
      _project(instructions: const {}),
      onRepositoryCreated: (repo) => repository = repo,
    );

    // First double-tap CREATES the default event silently (UI-R25 #2);
    // the second (covered cell) opens the editor the vocabulary button
    // lives in.
    await _doubleTapCell(tester, 'inst-cam', 0);
    await _doubleTapCell(tester, 'inst-cam', 0);
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('instruction-edit-set-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('instruction-edit-set-button')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('instruction-def-add-button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('instruction-def-name-field')),
      'ブレ',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('instruction-icon-shake')),
    );
    // Chip tint: pick the red preset (colors are display-only sugar; the
    // default swatch clears back to the row text color). The dialog body
    // scrolls, so bring each section on screen first.
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('instruction-color-ffe57373')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('instruction-color-ffe57373')),
    );
    // Mark: opt the custom term into the FI fade wedge.
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('instruction-mark-fi')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('instruction-mark-fi')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('instruction-def-save-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('instruction-set-save-button')),
    );
    await tester.pumpAndSettle();

    final defs = repository.requireProject().cameraInstructions.defs;
    final custom = defs.firstWhere((def) => def.name == 'ブレ');
    expect(custom.iconKey, 'shake');
    expect(custom.colorValue, 0xFFE57373);
    expect(custom.markType, CameraInstructionMarkType.fi);
    expect(defs.length, CameraInstructionSet.standard.defs.length + 1);

    // Close the still-open event picker.
    await tester.tap(
      find.byKey(const ValueKey<String>('instance-edit-cancel-button')),
    );
    await tester.pumpAndSettle();
  });
}
