import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';

/// 🚨★★★ T2·T3 — THE ONE SPLICE, through the session.
///
/// 유저 확정 2026-08-13: 「N칸을 들어내고 클립을 넣는다」에서 N만 다르다.
/// The model-level proof lives in `test/models/timeline_splice_test.dart`;
/// this file proves the SESSION picks the right N and the right index —
/// which is the half that used to be three placement rules, and the half
/// the user was actually complaining about.
///
/// ⛔The retired rules, so a future round does not restore them by accident:
/// relink on a block start, split-and-take-the-rest inside a hold, fill an
/// empty cell up to the next block. All three decided the LENGTH at the
/// destination. 「코마까지 포함해서 블록 자체를 복붙」 means the clip decides.
const _layerId = LayerId('draw');

void main() {
  testWidgets('a copied block pastes 코마째 and pushes the tail — '
      '유저 예시 A A A B B → A A A P P P B B', (tester) async {
    final session = await _pump(tester, 'AAABB');

    _stand(session, 0);
    session.copyFrameAtCurrentFrame();
    _stand(session, 3);
    session.pasteIndependentFrameAtCurrentFrame();

    expect(_row(session), 'AAAPPPBB');
  });

  testWidgets('the linked paste places the SAME cel, and the run is still '
      'the clip\'s length', (tester) async {
    final session = await _pump(tester, 'AAABB');

    _stand(session, 0);
    session.copyFrameAtCurrentFrame();
    _stand(session, 3);
    session.pasteLinkedFrameAtCurrentFrame();

    expect(_row(session), 'AAAAAABB');
    expect(
      _layer(session).frames.length,
      2,
      reason: 'a link makes no new cel',
    );
  });

  testWidgets('⛔the relink is gone: pasting on a block start no longer '
      'replaces that block', (tester) async {
    final session = await _pump(tester, 'AAABB');

    _stand(session, 0);
    session.copyFrameAtCurrentFrame();
    _stand(session, 3);
    session.pasteLinkedFrameAtCurrentFrame();

    expect(
      _row(session).contains('BB'),
      isTrue,
      reason: 'B survived; the old rule would have overwritten it',
    );
  });

  testWidgets('a SELECTION replaces what it covers, and the tail absorbs '
      'the difference', (tester) async {
    final session = await _pump(tester, 'AABBBCC');

    // Copy the 2-cell A block…
    _stand(session, 0);
    session.copyFrameAtCurrentFrame();
    // …over the 3-cell B block. 2 in, 3 out: C pulls one to the left.
    _select(session, 2, 5);
    session.pasteLinkedFrameAtCurrentFrame();

    expect(_row(session), 'AAAACC');
  });

  testWidgets('⛔the surplus outside the selection is never overwritten — '
      '「선택범위를 조절하는 의미가 통째로 사라지잖아」', (tester) async {
    final session = await _pump(tester, 'AAAAABC');

    // A 5-cell clip over a 1-cell selection: B goes, C must not.
    _stand(session, 0);
    session.copyFrameAtCurrentFrame();
    _select(session, 5, 6);
    session.pasteLinkedFrameAtCurrentFrame();

    expect(_row(session), 'AAAAAAAAAAC');
  });

  testWidgets('잘라내기 stores the clip AND takes the original out', (
    tester,
  ) async {
    final session = await _pump(tester, 'AABBBCC');

    _select(session, 2, 5);
    session.cutRunAtCurrentFrame();

    expect(_row(session), 'AACC', reason: 'the hole closed');

    // What came out is on the clipboard, at its own length.
    _stand(session, 0);
    session.pasteLinkedFrameAtCurrentFrame();
    expect(_row(session), 'BBBAACC');
  });

  testWidgets('the cut length is never asked: a push past the end line '
      'stays past the end line', (tester) async {
    final session = await _pump(tester, 'AAAA', duration: 4);

    _stand(session, 0);
    session.copyFrameAtCurrentFrame();
    _stand(session, 3);
    session.pasteLinkedFrameAtCurrentFrame();

    expect(_row(session), 'AAAAAAAA');
    expect(
      _cut(session).duration,
      4,
      reason: '컷 길이는 소재와 관계없다 — the 尺 did not move',
    );
  });

  testWidgets('undo puts the whole splice back in one step', (tester) async {
    final session = await _pump(tester, 'AABBBCC');

    _select(session, 2, 5);
    session.cutRunAtCurrentFrame();
    expect(_row(session), 'AACC');

    session.undo();
    expect(_row(session), 'AABBBCC');
  });
}

Future<EditorSessionManager> _pump(
  WidgetTester tester,
  String cells, {
  int? duration,
}) async {
  late ProjectRepository repository;
  await tester.pumpWidget(
    MaterialApp(
      home: HomePage(
        initialProject: _project(cells, duration ?? cells.length + 8),
        onRepositoryCreated: (repo) => repository = repo,
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(repository.requireProject().tracks, isNotEmpty);
  return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
}

void _stand(EditorSessionManager session, int frameIndex) {
  session.clearAllSelections();
  session.selectLayer(_layerId);
  session.selectFrameIndex(frameIndex);
}

void _select(EditorSessionManager session, int start, int endExclusive) {
  session.selectLayer(_layerId);
  session.selectFrameIndex(start);
  session.frameRangeSelection.value = TimelineFrameRangeSelection(
    layerId: _layerId,
    startIndex: start,
    endIndexExclusive: endExclusive,
  );
}

Cut _cut(EditorSessionManager session) =>
    session.repository.requireProject().tracks.single.cuts.single;

Layer _layer(EditorSessionManager session) =>
    _cut(session).layers.firstWhere((layer) => layer.id == _layerId);

/// The row as `AABBB…`, so a failure prints the timeline rather than a map.
String _row(EditorSessionManager session) {
  final timeline = _layer(session).timeline;
  final last = timeline.entries.fold<int>(
    0,
    (at, entry) => at > entry.key + (entry.value.length ?? 1)
        ? at
        : entry.key + (entry.value.length ?? 1),
  );
  final out = List<String>.filled(last, '.');
  // ⚠️The letter comes from the cel's OWN id, never from its position in
  // `layer.frames`. A splice that orphans a cel drops it from that list, and
  // position-based letters would silently re-letter every cel after it — the
  // row would read as changed where nothing moved.
  var pasted = 0;
  final letters = <FrameId, String>{};
  for (final frame in _layer(session).frames) {
    letters[frame.id] = frame.id.value.startsWith('cel-')
        ? frame.id.value.substring(4)
        : String.fromCharCode(80 + pasted++); // P, Q… = minted by a paste
  }
  for (final entry in timeline.entries) {
    final symbol = letters[entry.value.frameId] ?? '?';
    for (var at = entry.key; at < entry.key + (entry.value.length ?? 1); at++) {
      if (at >= 0 && at < last) {
        out[at] = symbol;
      }
    }
  }
  return out.join();
}

Project _project(String cells, int duration) {
  final frames = <Frame>[];
  final timeline = <int, TimelineExposure>{};
  var index = 0;
  while (index < cells.length) {
    final symbol = cells[index];
    if (symbol == '.') {
      index += 1;
      continue;
    }
    var length = 1;
    while (index + length < cells.length && cells[index + length] == symbol) {
      length += 1;
    }
    final id = FrameId('cel-$symbol');
    if (!frames.any((frame) => frame.id == id)) {
      frames.add(Frame(id: id, duration: length, strokes: const []));
    }
    timeline[index] = TimelineExposure.drawing(id, length: length);
    index += length;
  }
  return Project(
    id: const ProjectId('splice-project'),
    name: 'Splice Project',
    createdAt: DateTime.utc(2026, 8, 14),
    tracks: [
      Track(
        id: const TrackId('splice-track'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('splice-cut'),
            name: 'Cut',
            duration: duration,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              Layer(
                id: _layerId,
                name: 'Draw',
                frames: frames,
                timeline: timeline,
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
