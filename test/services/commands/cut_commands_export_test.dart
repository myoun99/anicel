import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/commands/cut_commands.dart';

void main() {
  test('exports user-level cut command types', () {
    expect(
      <Type>[
        CreateCutCommand,
        RenameCutCommand,
        DeleteCutCommand,
        DuplicateCutCommand,
        SetCutOrderCommand,
        UpdateCutNoteCommand,
        UpdateLayerKindCommand,
        DeleteLayerCommand,
        UpdateExposureMemoCommand,
        CutCommandCoordinator,
        CutPosition,
        CutReorderPlanner,
      ],
      containsAll(<Type>[
        CreateCutCommand,
        RenameCutCommand,
        DeleteCutCommand,
        DuplicateCutCommand,
        SetCutOrderCommand,
        UpdateCutNoteCommand,
        UpdateLayerKindCommand,
        DeleteLayerCommand,
        UpdateExposureMemoCommand,
        CutCommandCoordinator,
        CutPosition,
        CutReorderPlanner,
      ]),
    );
  });
}
