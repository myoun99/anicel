import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';

/// HOW FAR A ROW'S OWN AXIS RUNS AHEAD OF THE CUT'S — ASKED IN ONE PLACE.
///
/// A track-owned SE row is keyed on its track's GLOBAL frames; every other
/// row is keyed on the cut's own. So every verb that turns a cut-local frame
/// into a row's frame, or back, adds one offset — and six places wrote that
/// conditional out by hand (`isTrackSeLayerId(id) ? activeCutGlobalStartFrame
/// : 0`): the controllers' frame offset, the lane verbs' write axis, the lane
/// selection's hit test and its drag, the SE fill's pre-subtraction and the
/// cut-local lane range. F-102 (keys erased in an earlier cut) and F-115 (a
/// paste landing on the wrong global frame) are both mistakes on this axis.
///
/// ⛔This scans SOURCE on purpose, like
/// `the_frame_axis_is_asked_in_one_place_test`: six copies that agree today
/// pass every behavioural test, and six copies that agree today are the
/// state this exists to end.
void main() {
  test('the SE row axis offset is written out in ONE place — every other '
      'verb asks `rowAxisOffset`', () {
    const home = 'lib/src/ui/session/track_se_display.dart';
    final sites = <String>[];

    for (final entity in dartFilesUnder('lib')) {
      final path = entity.path.replaceAll(r'\', '/');
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        final line = lines[i].trim();
        if (!line.contains('activeCutGlobalStartFrame')) {
          continue;
        }
        // A role DECLARES the member; declaring is not answering.
        if (line == 'int get activeCutGlobalStartFrame;') {
          continue;
        }
        final from = i - 4 < 0 ? 0 : i - 4;
        final to = i + 4 >= lines.length ? lines.length - 1 : i + 4;
        final nearTheKindQuestion = [
          for (var j = from; j <= to; j += 1) lines[j],
        ].any((near) => near.contains('isTrackSe'));
        if (nearTheKindQuestion) {
          sites.add('$path:${i + 1}  $line');
        }
      }
    }

    expect(
      sites,
      hasLength(1),
      reason:
          'The offset is written out somewhere other than its home. Ask '
          '`rowAxisOffset(layerId)` instead — two hand-written copies that '
          'agree today are the ones that stop agreeing later.\n'
          '${sites.join('\n')}',
    );
    expect(sites.single, startsWith(home), reason: 'and that place is the home');
  });
}
