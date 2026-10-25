import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/frame.dart' show InbetweenMark;
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️I-130 (유저 2026-10-25): 「타임시트 용지패널이나 다른곳에서도 제대로
/// 되도록 알아서」 — the canvas's frame label on a cell inside a block writes
/// the mark that cell wears, after the drawing's cel number when it has one:
/// ○ for mark 1, ● for mark 2.
void main() {
  test('the frame label on a dotted cell writes its mark, alone or after '
      'the cel number', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    session.edgeDrag.setCommaForTimelineCursor(4);
    session.selectFrameIndex(2);
    String label() => session.canvasSelectionLabels.frameLabel;

    session.layerMarks.toggleMarkAtCurrentFrame(InbetweenMark.one);
    expect(label(), '○');
    session.layerMarks.toggleMarkAtCurrentFrame(InbetweenMark.two);
    expect(label(), '●');

    session.selectFrameIndex(0);
    session.frameVerbs.renameSelectedFrame('A1');
    session.selectFrameIndex(2);
    expect(label(), 'A1 ●');
    session.layerMarks.toggleMarkAtCurrentFrame(InbetweenMark.one);
    expect(label(), 'A1 ○');
  });
}
