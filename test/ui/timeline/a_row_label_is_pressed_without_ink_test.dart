import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/input/arena_tap_hold.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/storyboard_host.dart';
import '../../helpers/timeline_host.dart';

/// F-132 — a rail row's label is pressed without ink, on every rail.
///
/// 유저 2026-09-14: 「x시트 레이어라벨만 클릭했을때 흰색으로 채워지는
/// 애니메이션 없는데, 이거 맘에듬. 일단 그부분 타임라인이랑 스토리보드패널이랑
/// 법 하나로 통일시키고, 애니메이션 없도록 하도록」.
///
/// The labels press through an [InkWell] for its place in the gesture arena;
/// what the user saw was that InkWell's splash and highlight filling the row.
/// The timeline and the x-sheet share one row widget, so the timeline's labels
/// and the storyboard's are read here.
///
/// ↩️**IT ASKED HOW, AND THE HOW MOVED** (F-138, 2026-09-17). This read each
/// InkWell's OWN `splashFactory`, which is where F-132 had put the answer —
/// three widgets spelling it by hand. 유저 then widened the law to the whole
/// app (「이 앱은 기본적으로 이런거 off임. 없는채로 통일」) and it went to the
/// THEME, so the widget's own field is null now and this failed while the
/// product was right. ⚠️The harness had the same shape of mistake: it pumped a
/// bare `MaterialApp`, whose theme is Flutter's own — so it could never have
/// noticed a label that stopped turning the ink off for itself either.
/// ★It asks what the PRESS resolves to now, under the app's real theme.
///
/// ↩️**AND THEN THE INK WENT** (I-57 ①, 2026-10-10): the label bodies were
/// `InkWell`s held only for their place in the arena — ~20 elements a row,
/// mounted anew on every cut switch — and hold that tap with no ink at all
/// now ([ArenaTapHold]). So it reads that each body IS that: no theme can
/// lend a splash to what has no ink.
void main() {
  Finder labelBodies(bool Function(String key) isLabel) =>
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            isLabel((widget.key! as ValueKey<String>).value),
      );

  void expectInkless(Finder labels) {
    final found = labels.evaluate().toList();
    expect(found, isNotEmpty, reason: 'fixture: the rail draws labels');
    for (final label in found) {
      expect(
        label.widget,
        isA<ArenaTapHold>(),
        reason:
            '${nameOf(label) ?? label.widget.key}: the body holds its tap '
            'with no ink to spread',
      );
    }
  }

  testWidgets('the timeline\'s layer labels press without ink', (
    tester,
  ) async {
    await pumpTimelineHost(
      tester,
      createDefaultProject(),
      surface: const Size(800, 600),
      pixelsPerFrame: 24,
    );

    expectInkless(
      find.namedWhere((name) => name.startsWith('timeline-layer-row-')),
    );

    // Drain the prerender scheduler's debounced warming.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets('the storyboard\'s track and S-row labels press without ink', (
    tester,
  ) async {
    final session = await pumpStoryboardHost(
      tester,
      createDefaultProject(),
      surface: const Size(1600, 900),
      pixelsPerFrame: 12,
    );

    expectInkless(
      labelBodies((key) => key.startsWith('storyboard-track-select-')),
    );
    // ↩️The S rows were labels of this rail's own, read by their keys. They
    // wear the timeline's row now (I-89 ①), and its body goes by the row's
    // name, as on the timeline.
    final seRows = [
      for (final track in session.repository.requireProject().tracks)
        for (final row in track.seLayers)
          'storyboard-layer-row-${row.id.value}',
    ];
    expect(seRows, isNotEmpty, reason: 'fixture: the track has S rows');
    expectInkless(find.namedWhere(seRows.contains));
  });
}
