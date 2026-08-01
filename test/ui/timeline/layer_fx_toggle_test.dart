import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/ui/home_page.dart';

Project _project() {
  return Project(
    id: const ProjectId('fx-project'),
    name: 'FX Project',
    createdAt: DateTime.utc(2026, 7, 10),
    tracks: [
      Track(
        id: const TrackId('fx-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('fx-cut'),
            name: 'FX Cut',
            duration: 12,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            layers: [
              Layer(
                id: const LayerId('fx-draw'),
                name: 'Drawing',
                frames: const [],
              ),
              Layer(
                id: const LayerId('fx-se'),
                name: 'S1',
                kind: LayerKind.se,
                frames: const [],
              ),
              Layer(
                id: const LayerId('fx-cam'),
                name: 'Camera',
                kind: LayerKind.camera,
                frames: const [],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

void main() {
  group('layer fx switch on the layer labels', () {
    testWidgets('EVERY row carries the fx switch (R4 unified controls); '
        'tapping flips the bypass', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: _project())),
      );
      await tester.pumpAndSettle();

      final fxButton = find.byKey(
        const ValueKey<String>('timeline-layer-fx-fx-draw'),
      );
      expect(fxButton, findsOneWidget);
      // SE rows bypass the dialogue transform, the camera row bypasses the
      // camera work on the render routes — the switch sits on every kind.
      expect(
        find.byKey(const ValueKey<String>('timeline-layer-fx-fx-se')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-layer-fx-fx-cam')),
        findsOneWidget,
      );

      // Applied by default; a tap bypasses (tooltip mirrors the state).
      expect(tester.widget<IconButton>(fxButton).tooltip, 'Bypass layer FX');
      await tester.tap(fxButton);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(fxButton).tooltip, 'Apply layer FX');

      await tester.tap(fxButton);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(fxButton).tooltip, 'Bypass layer FX');
    });

    testWidgets('the X-sheet header carries the same switch (Axis policy)', (
      tester,
    ) async {
      // R10 R6: the sheet's stood-up header sheds controls down a ladder
      // when the panel is too short to stack them, and the fx switch is on
      // that ladder. The bottom dock's default 350 is past it, so give the
      // dock the height a user working in the sheet would — this test is
      // about the Axis policy, not about what a cramped panel gives up
      // (that has its own tests).
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: _project())),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey<String>('dock-resize-bottom')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('timeline-orientation-toggle-button'),
        ),
      );
      await tester.pumpAndSettle();

      final fxButton = find.byKey(
        const ValueKey<String>('xsheet-layer-fx-fx-draw'),
      );
      expect(fxButton, findsOneWidget);
      await tester.tap(fxButton);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(fxButton).tooltip, 'Apply layer FX');
    });
  });
}
