import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

/// A cut that counts what its hash costs: it walks every layer held.
class _CountedCut extends Cut {
  _CountedCut({required String id, required super.layers})
    : super(
        id: CutId(id),
        name: id,
        duration: 12,
        canvasSize: const CanvasSize(width: 640, height: 360),
        camera: CutCamera.empty(),
      );

  static int hashes = 0;

  @override
  // The hash is what this counts: equality stands as the cut's.
  // ignore: hash_and_equals
  int get hashCode {
    hashes += 1;
    return super.hashCode;
  }
}

/// 🚨I-22: THE RAIL'S PASS OVER ITS SEATS HASHES NO CUT.
///
/// It keeps a folder index a head cut, and a host's build asks it several
/// times over: a cut's hash walking 68 layers, once a seat, was 213ms of the
/// 2,475ms sixteen presses on the film's ruler took (S5 cut 352, debug).
void main() {
  testWidgets('a rebuild of the film hashes no cut', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Layer conte(String id) => Layer(
      id: LayerId('$id-conte'),
      name: 'Conte',
      kind: LayerKind.storyboard,
      frames: const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          initialProject: Project(
            id: const ProjectId('seats'),
            name: 'Seats',
            createdAt: DateTime.utc(2026, 10, 31),
            tracks: [
              Track(
                id: const TrackId('t'),
                name: 'V',
                cuts: [
                  for (final id in const ['one', 'two'])
                    _CountedCut(id: id, layers: [conte(id)]),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find
          .byKey(const ValueKey<String>('timeline-mode-storyboard-button'))
          .first,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    _CountedCut.hashes = 0;
    session.selectCut(const CutId('two'));
    await tester.pump();
    expect(session.activeCutId, const CutId('two'));
    expect(_CountedCut.hashes, 0);
  });
}
