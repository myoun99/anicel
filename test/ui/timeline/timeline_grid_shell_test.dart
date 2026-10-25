import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/rail_eyes.dart';
import 'package:anicel/src/ui/timeline/stylus_glide_stop.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_shell.dart';

/// The chrome both grids wrap their tree in (the audit's clone scan,
/// 2026-09-06): the grid law with the ground and fps, the stylus glide
/// stop over the grid's controllers, and a scroll configuration with no
/// overscroll — PEN-12 #7's hard clamp.
void main() {
  testWidgets('publishes the law, stops the glide and clamps overscroll', (
    tester,
  ) async {
    late BuildContext inner;
    final folder = Layer(
      id: const LayerId('f'),
      name: 'F',
      kind: LayerKind.folder,
      frames: const [],
      isVisible: false,
    );
    final member = Layer(
      id: const LayerId('m'),
      name: 'M',
      frames: const [],
      folderId: const LayerId('f'),
    );
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineGridShell(
          ground: const Color(0xFF123456),
          framesPerSecond: 30,
          layers: [folder, member],
          controllers: [controller],
          child: Builder(
            builder: (context) {
              inner = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    final law = TimelineGridLaw.maybeOf(inner);
    expect(law, isNotNull, reason: 'the law is published above the tree');
    expect(law!.ground, const Color(0xFF123456));
    expect(law.framesPerSecond, 30);

    // 🗣️I-129: the rows' eyes reach the frame rows as the rail's do — a
    // row whose own eye is on, hidden by the folder above it.
    expect(
      RailEyes.of(inner, member),
      (on: true, hiddenAbove: true),
      reason: 'the eyes are published above the tree, folders gating them',
    );

    expect(find.byType(StylusGlideStop), findsOneWidget);
    expect(
      tester.widget<StylusGlideStop>(find.byType(StylusGlideStop)).controllers,
      [controller],
    );

    // PEN-12 #7: the overscroll indicator is the child itself — no glow,
    // no stretch — where the app's default behaviour would have wrapped it.
    const probe = SizedBox();
    const details = ScrollableDetails(direction: AxisDirection.down);
    expect(
      identical(
        ScrollConfiguration.of(
          inner,
        ).buildOverscrollIndicator(inner, probe, details),
        probe,
      ),
      isTrue,
    );
  });
}
