import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/cell_instances.dart';
import 'package:anicel/src/ui/timeline/instance_editor_commands.dart';

/// 🚨F-105 — THE EDIT BUTTON EDITS WHAT A CELL HOLDS; IT NEVER CREATES.
///
/// 유저 2026-09-12: 「se행만 현재 인덱스 비어있을때 편집버튼이 활성화되는데다가,
/// 누르면 프레임이 생김. 대체 누가 이딴거 만들라했는지? 기존 로직대로 법
/// 통일하고 삭제」.
///
/// The drawing rows' Edit already went dark on an empty cell. The SE row's
/// gate asked 「could a drawing be created here」 and its editor created one;
/// the direction row's gate asked only 「is there a cell」 and its editor
/// created an event. Creating stays where it lives — the double tap's fork
/// (I-9) and the ＋ (`createActiveInstance`).
void main() {
  /// Held by its own type — `tool/mutation_run.dart` picks a file's
  /// witnesses by which tests IMPORT it.
  CellInstances cellInstancesOf(EditorSessionManager s) => s.cellInstances;

  /// A session standing on frame 0 of the track's first S row, which starts
  /// empty.
  EditorSessionManager standingOnAnEmptySeCell() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.selectLayer(s.activeTrack.seLayers.first.id);
    s.selectFrameIndex(0);
    expect(s.activeLayer?.kind, LayerKind.se, reason: 'the CONTROL — an S row');
    return s;
  }

  /// A session standing on frame 0 of a freshly added direction row.
  EditorSessionManager standingOnAnEmptyDirectionCell() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.layerStack.addLayerOfKind(LayerKind.instruction);
    s.selectFrameIndex(0);
    expect(
      s.activeLayer?.kind,
      LayerKind.instruction,
      reason: 'the CONTROL — the new direction row',
    );
    return s;
  }

  /// A context the editors could open a dialog from. None should open.
  Future<BuildContext> contextFrom(WidgetTester tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    return captured;
  }

  group('the SE row', () {
    test('Edit is dark on an EMPTY cell and lit on a covered one', () {
      final s = standingOnAnEmptySeCell();
      expect(s.selectedFrame, isNull, reason: 'the CONTROL — nothing here');

      expect(
        cellInstancesOf(s).canEditCellInstanceAtCurrentFrame,
        isFalse,
        reason: 'it lit because a drawing COULD be created here',
      );

      s.seEntries.createSeEntryAtCurrentFrame(name: '', lengthFrames: 1);
      expect(cellInstancesOf(s).canEditCellInstanceAtCurrentFrame, isTrue);
    });

    testWidgets('pressing Edit on an EMPTY cell makes nothing', (
      tester,
    ) async {
      final s = standingOnAnEmptySeCell();
      final row = s.activeLayerId!;
      final context = await contextFrom(tester);

      await editActiveInstance(context, s);
      await tester.pumpAndSettle();

      expect(
        s.activeTrack.seLayers.firstWhere((layer) => layer.id == row).frames,
        isEmpty,
        reason: 'the SE editor made a one-frame entry on the empty cell',
      );
    });
  });

  group('the direction row', () {
    test('Edit is dark on an EMPTY cell and lit on a covered one', () {
      final s = standingOnAnEmptyDirectionCell();
      final row = s.activeLayerId!;
      expect(
        s.instructionVerbs.instructionSpanAt(row, s.currentFrameIndex),
        isNull,
        reason: 'the CONTROL — nothing here',
      );

      expect(
        cellInstancesOf(s).canEditCellInstanceAtCurrentFrame,
        isFalse,
        reason: 'it lit on any cell at all',
      );

      s.instructionVerbs.createDefaultInstructionEventAtCurrentFrame();
      expect(cellInstancesOf(s).canEditCellInstanceAtCurrentFrame, isTrue);
    });

    testWidgets('pressing Edit on an EMPTY cell makes nothing', (
      tester,
    ) async {
      final s = standingOnAnEmptyDirectionCell();
      final row = s.activeLayerId!;
      final context = await contextFrom(tester);

      await editActiveInstance(context, s);
      await tester.pumpAndSettle();

      expect(
        s.layers.firstWhere((layer) => layer.id == row).instructions,
        isEmpty,
        reason: 'the span flow created an event on the empty cell',
      );
    });
  });

  /// The storyboard's Edit doors, called straight: the button's gate keeps
  /// them from an empty frame, and these say the doors would not create even
  /// if a gate ever let one through — creating is the double tap's door
  /// (`activate…Cell`) and the ＋'s.
  group('the storyboard\'s Edit doors', () {
    testWidgets('the transition row\'s opens nothing and makes nothing on an '
        'EMPTY frame', (tester) async {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      final context = await contextFrom(tester);
      expect(
        s.transitions.transitionSpanAt(s.editingGlobalFrame),
        isNull,
        reason: 'the CONTROL — nothing here',
      );

      await editTransitionSpanInstance(context, s);
      await tester.pumpAndSettle();

      expect(s.activeTrack.transitionLayer.instructions, isEmpty);
    });

    testWidgets('the S row\'s opens nothing and makes nothing on an EMPTY '
        'cell', (tester) async {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      final context = await contextFrom(tester);
      final row = s.activeTrack.seLayers.first.id;

      await editSeEntryInstance(context, s, layerId: row, globalFrame: 0);
      await tester.pumpAndSettle();

      expect(
        s.activeTrack.seLayers.firstWhere((layer) => layer.id == row).frames,
        isEmpty,
      );
    });
  });
}
