import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/storyboard_cut_blocks_painter.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';

import '../../helpers/fixed_thumbnails.dart';
import '../timeline/timeline_frame_geometry_probe.dart';

/// 🚨I-57 (10-14): THE CUT ROW ASKS WHERE YOU STAND ONCE A PASS — AND WHAT
/// IT SAYS ASKS ONLY WHAT IT SAYS.
///
/// A cut crossed under the playhead repaints the V row — the cut you stand
/// on moved — and describes it to a screen reader again. Where you stand
/// is a walk of the track's rows ([StandingCut.value]), and every block
/// asked it: 🔬a fifth of a crossing's paint on the AMMI OP, and a tenth of
/// its semantics. The sentences asked each block for its whole picture —
/// its panels' thumbnails too — for a name and a length.
void main() {
  const trackId = TrackId('t');

  Cut cut(String id) => Cut(
    id: CutId(id),
    name: id,
    duration: 12,
    canvasSize: const CanvasSize(width: 8, height: 8),
    layers: [Layer(id: LayerId('cel-$id'), name: 'A', frames: const [])],
  );

  final entries = buildStoryboardTimelineLayout(
    Project(
      id: const ProjectId('p'),
      name: 'P',
      createdAt: DateTime.utc(2026, 10, 14),
      tracks: [
        Track(
          id: trackId,
          name: 'T',
          cuts: [for (var i = 0; i < 5; i += 1) cut('c$i')],
        ),
      ],
    ),
  );

  /// The row of five cuts, standing on the third, its pictures counted as
  /// they are asked for.
  ({
    StoryboardCutBlocksPainter painter,
    _Counted standing,
    List<int> pictures,
  })
  countedRow() {
    final standing = _Counted(const CutId('c2'));
    final pictures = [0];
    final hovered = ValueNotifier<CutId?>(null);
    addTearDown(hovered.dispose);
    return (
      painter: StoryboardCutBlocksPainter(
        entries: entries,
        storyboardCellsByCut: storyboardCellsByCut(entries),
        geometry: testFrameGeometry(
          frameCellExtent: 8,
          frameEndIndexExclusive: 60,
        ),
        crossAxisExtent: 70,
        minBlockWidth: 1,
        selectedRange: null,
        rowAddress: const TrackRowAddress(trackId),
        hoveredCutId: hovered,
        standingCutId: standing,
        colorScheme: const ColorScheme.dark(),
        baseTextStyle: const TextStyle(fontSize: 11),
        showSeconds: false,
        countingBase: 1,
        thumbnails: fixedThumbnails((
          cut,
          frameIndex, {
          required shownHeight,
          region,
        }) {
          pictures[0] += 1;
          return null;
        }),
        devicePixelRatio: 1,
      ),
      standing: standing,
      pictures: pictures,
    );
  }

  test('a pass asks where you stand once — however many blocks it draws', () {
    final (:painter, :standing, pictures: _) = countedRow();

    final blocks = painter.blocks();

    expect(blocks, hasLength(5), reason: 'premise: every cut is a block');
    expect(
      [
        for (final block in blocks)
          if (block.isStanding) block.cutId,
      ],
      [const CutId('c2')],
      reason: 'premise: the cut you stand on wears it',
    );
    expect(
      standing.reads,
      1,
      reason: '↩️asked of every block: a walk of the track\'s rows each, '
          'on every paint of a crossing',
    );
  });

  test('🚨what the row says to a screen reader asks for no picture and not '
      'where you stand — and says what each block prints', () {
    final (:painter, :standing, :pictures) = countedRow();

    final said = painter.semanticsBuilder(const Size(480, 70));

    expect(said, hasLength(5), reason: 'premise: a sentence a block');
    expect(pictures.single, 0, reason: 'a sentence shows no picture');
    expect(standing.reads, 0, reason: 'nor says where you stand');

    final blocks = painter.blocks();
    expect(pictures.single, greaterThan(0), reason: 'premise: they paint');
    expect([for (final node in said) node.rect], [
      for (final block in blocks) block.rect,
    ]);
    expect([for (final node in said) node.properties.label], [
      for (final block in blocks) [block.title, ?block.total].join(' '),
    ]);
  });
}

/// Where you stand, counting how often it is asked.
class _Counted implements ValueListenable<CutId?> {
  _Counted(this._value);

  final CutId? _value;
  int reads = 0;

  @override
  CutId? get value {
    reads += 1;
    return _value;
  }

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
