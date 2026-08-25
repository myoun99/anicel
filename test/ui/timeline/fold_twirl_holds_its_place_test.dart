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

/// F-29 — **the fold twirl holds its place.**
///
/// 유저 2026-08-24: 「어태치나 폴더의 접기 펼치기 아이콘 위치 조정. 지금
/// 레이어이름 옆에 붙어있는데, 그게아니라 위치는 항상 고정으로 두고싶기때문에
/// 레이어 이름영역의 오른쪽정렬로 고정」.
///
/// It was the last child of a MIN-width Row inside a left `Align`, so it sat
/// wherever the name happened to end — a different x on every row, and a
/// moving x on a rename.
///
/// ⚠️Measured in PIXELS, because that is the whole complaint. Asserting that
/// the widget exists, or that it comes after the name in the tree, is what the
/// old layout would also have passed.
void main() {
  const trackId = TrackId('fold-track');
  const shortName = LayerId('fold-short');
  const longName = LayerId('fold-long');

  Layer folder(LayerId id, String name) => Layer(
    id: id,
    name: name,
    kind: LayerKind.folder,
    frames: const [],
    timeline: const {},
  );

  Project project() => Project(
    id: const ProjectId('fold-project'),
    name: 'Fold',
    createdAt: DateTime.utc(2026, 8, 25),
    tracks: [
      Track(
        id: trackId,
        name: 'V',
        cuts: [
          Cut(
            id: const CutId('c'),
            name: '1',
            duration: 8,
            canvasSize: const CanvasSize(width: 64, height: 64),
            layers: [
              folder(shortName, 'A'),
              folder(
                longName,
                'a folder whose name runs most of the way across',
              ),
              Layer(
                id: const LayerId('fold-cel'),
                name: 'Cel',
                frames: const [],
                timeline: const {},
              ),
            ],
          ),
        ],
      ),
    ],
  );

  testWidgets('two folders with very different names put their twirl on the '
      'same x', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();

    final short = find.byKey(
      const ValueKey<String>('timeline-folder-twirl-fold-short'),
    );
    final long = find.byKey(
      const ValueKey<String>('timeline-folder-twirl-fold-long'),
    );
    expect(short, findsOneWidget, reason: 'fixture: both folders draw one');
    expect(long, findsOneWidget);

    expect(
      tester.getTopLeft(short).dx,
      closeTo(tester.getTopLeft(long).dx, 0.5),
      reason: 'the name takes the space and the twirl trails it at the '
          'region right edge — so the name it trails cannot move it',
    );
  });

  testWidgets('and it sits at the RIGHT end of the name region, not beside '
      'the letters', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();

    final nameRegion = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-layer-name-fold-short')),
    );
    final twirl = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-folder-twirl-fold-short')),
    );

    expect(
      twirl.right,
      closeTo(nameRegion.right, 1.0),
      reason: 'right-aligned inside the name region',
    );
    // The premise the first test rests on: the short name really is short,
    // so "beside the letters" and "at the right edge" are far apart here.
    expect(
      twirl.left - nameRegion.left,
      greaterThan(60),
      reason: 'fixture: a one-letter name would have parked the old twirl '
          'near the left edge',
    );
  });
}
