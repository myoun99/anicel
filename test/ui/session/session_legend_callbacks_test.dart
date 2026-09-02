import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/session_legend_callbacks.dart';
import 'package:anicel/src/ui/timeline/timeline_row_filter.dart';

/// The legend wiring both rails share (the audit's clone scan, 2026-09-03).
/// A "show all hides" mutant survived every legend test: none drove the
/// verbs through the host's wiring into the session, so the wiring itself
/// is measured here.
void main() {
  EditorSessionManager session() {
    final manager = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('legend'),
        name: 'Legend',
        createdAt: DateTime.utc(2026, 9, 3),
        tracks: [
          Track(
            id: const TrackId('v'),
            name: 'V',
            cuts: [
              Cut(
                id: const CutId('cut'),
                name: '1',
                duration: 8,
                canvasSize: const CanvasSize(width: 32, height: 32),
                layers: [
                  Layer(
                    id: const LayerId('a'),
                    name: 'A',
                    frames: const [],
                    timeline: {},
                  ),
                  Layer(
                    id: const LayerId('b'),
                    name: 'B',
                    frames: const [],
                    timeline: {},
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(manager.dispose);
    return manager;
  }

  test('hide all, then show all, reach every layer through the session', () {
    final s = session();
    final legend = sessionLegendCallbacks(
      s,
      rowFilter: TimelineRowFilter.none,
      onSetRowFilter: null,
    );

    legend.onHideAllLayers();
    expect(s.layers.any((layer) => layer.isVisible), isFalse);

    legend.onShowAllLayers();
    expect(s.layers.every((layer) => layer.isVisible), isTrue);
  });

  test('a filter toggle hands the host the TOGGLED filter', () {
    TimelineRowFilter? handed;
    final legend = sessionLegendCallbacks(
      session(),
      rowFilter: TimelineRowFilter.none,
      onSetRowFilter: (filter) => handed = filter,
    );

    legend.onToggleSheetOnlyFilter();
    expect(handed?.onTimesheetOnly, isTrue);

    legend.onToggleFxOnlyFilter();
    expect(
      handed?.fxOnly,
      isTrue,
      reason: 'each toggle starts from the host\'s filter',
    );
  });

  test('a host that names no onion or blend verb gets none', () {
    final legend = sessionLegendCallbacks(
      session(),
      rowFilter: TimelineRowFilter.none,
      onSetRowFilter: null,
    );
    expect(legend.onToggleOnionSkinForDisplayed, isNull);
    expect(legend.onRevealOnionSkinPanel, isNull);
    expect(legend.onSetBlendModeForDisplayed, isNull);
  });
}
