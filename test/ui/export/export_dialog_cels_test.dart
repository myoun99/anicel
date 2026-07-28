import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_cut_helpers.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/camera_instruction.dart';
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
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';

void main() {
  setUp(() => AppExport.settings.value = AppExportSettings());
  tearDown(() => AppExport.settings.value = AppExportSettings());

  Frame frame(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const []);

  /// CUT1: base A (2 cels) + a synced color row + a hidden base B + an
  /// instruction row. CUT2 exists for the scope grid.
  EditorSessionManager celsSession() {
    return EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'Project',
        cameraSize: const CanvasSize(width: 32, height: 18),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [
              Cut(
                id: const CutId('cut'),
                name: 'CUT1',
                duration: 4,
                canvasSize: const CanvasSize(width: 8, height: 8),
                layers: [
                  Layer(
                    id: const LayerId('a'),
                    name: 'A',
                    frames: [frame('f1'), frame('f2')],
                  ),
                  Layer(
                    id: const LayerId('a-color'),
                    name: 'A색',
                    frames: [frame('c1'), frame('c2')],
                    attachedToLayerId: const LayerId('a'),
                    attachedMode: AttachedMode.synced,
                    baseFrameLinks: {
                      const FrameId('f1'): const FrameId('c1'),
                      const FrameId('f2'): const FrameId('c2'),
                    },
                  ),
                  Layer(
                    id: const LayerId('b'),
                    name: 'B',
                    frames: [frame('b1')],
                    isVisible: false,
                  ),
                  Layer(
                    id: const LayerId('inst'),
                    name: 'Camera',
                    frames: const [],
                    kind: LayerKind.instruction,
                    instructions: {
                      0: const InstructionEvent(
                        instructionId: 'pan',
                        length: 4,
                        text: 'PAN',
                      ),
                    },
                  ),
                  createCameraLayer(cutId: const CutId('cut')),
                ],
              ),
              Cut(
                id: const CutId('cut-b'),
                name: 'CUT2',
                duration: 2,
                canvasSize: const CanvasSize(width: 8, height: 8),
                layers: [
                  Layer(
                    id: const LayerId('b-a'),
                    name: 'A',
                    frames: [frame('bf1')],
                  ),
                  createCameraLayer(cutId: const CutId('cut-b')),
                ],
              ),
            ],
          ),
        ],
        createdAt: DateTime.utc(2026),
      ),
    );
  }

  Future<ExportDialogState> pumpCels(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1120, 660));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session,
            formatAvailability: ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('export-tab-cels')));
    await tester.pump();
    return tester.state<ExportDialogState>(find.byType(ExportDialog));
  }

  testWidgets('the label list shows bases + Instructions; members show '
      'their tags', (tester) async {
    await pumpCels(tester, celsSession());
    expect(
      find.byKey(const ValueKey<String>('export-cels-label-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('export-cels-label-inst')),
      findsOneWidget,
    );
    // The hidden base B is not a label — it waits in Add from timeline.
    expect(
      find.byKey(const ValueKey<String>('export-cels-label-b')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('export-cels-add-b')),
      findsOneWidget,
    );
    // The member list of label A carries the base and the synced row.
    expect(
      find.byKey(const ValueKey<String>('export-cels-member-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('export-cels-member-a-color')),
      findsOneWidget,
    );
    expect(find.text('sync'), findsOneWidget);
    expect(find.text('기준'), findsOneWidget);
  });

  testWidgets('the label × writes a project-side delta; Reset clears it',
      (tester) async {
    final session = celsSession();
    final state = await pumpCels(tester, session);
    expect(state.debugFlushPreview, isNotNull);

    // Remove label A by its ×.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('export-cels-label-a')),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pump();
    final overrides = session.repository
        .requireProject()
        .exportOverrides;
    expect(
      overrides.deltaFor(const CutId('cut'))?.layerOverrides[const LayerId(
        'a',
      )],
      isFalse,
    );
    expect(
      find.byKey(const ValueKey<String>('export-cels-label-a')),
      findsNothing,
    );
    // A now sits in Add from timeline; its dot re-includes it (the
    // override drops because the wish equals the rule again).
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('export-cels-add-a')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('export-cels-adddot-a')),
      warnIfMissed: false,
    );
    await tester.pump();
    final after = session.repository.requireProject().exportOverrides;
    expect(after.deltaFor(const CutId('cut')), isNull);
  });

  testWidgets('the hidden base joins by hand and the plan grows',
      (tester) async {
    final session = celsSession();
    await pumpCels(tester, celsSession());
    // Fresh session per pump above; use a single session for assertions.
    final state = await pumpCels(tester, session);
    final before = tester
        .widget<Text>(
          find.byKey(const ValueKey<String>('export-transport-line')),
        )
        .data;
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('export-cels-add-b')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('export-cels-adddot-b')),
      warnIfMissed: false,
    );
    await tester.pump();
    final overrides = session.repository.requireProject().exportOverrides;
    expect(
      overrides
          .deltaFor(const CutId('cut'))
          ?.layerOverrides[const LayerId('b')],
      isTrue,
    );
    final after = tester
        .widget<Text>(
          find.byKey(const ValueKey<String>('export-transport-line')),
        )
        .data;
    expect(after, isNot(before));
    expect(state.debugImageFrame, isNotNull);
  });

  testWidgets('the project-scope cut grid excludes a cut and saves it',
      (tester) async {
    final session = celsSession();
    await pumpCels(tester, session);
    // The Cels Scope accordion sits collapsed by default — open it.
    await tester.ensureVisible(find.textContaining('Scope'));
    await tester.tap(find.textContaining('Scope'));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('export-scope-project')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('export-scope-project')));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('export-cut-cell-2')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('export-cut-cell-2')));
    await tester.pump();
    expect(
      session.repository
          .requireProject()
          .exportOverrides
          .cutIncluded(const CutId('cut-b')),
      isFalse,
    );
    expect(find.text('1 / 2 cuts'), findsOneWidget);
  });
}
