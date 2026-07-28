import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_cut_helpers.dart';
import 'package:anicel/src/controllers/default_layer_helpers.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/cut_command_coordinator.dart';

/// The cut NAME is the cut number: a free string the user owns. Naming a
/// new cut therefore offers candidates and takes the first free one, so a
/// hand-written name never breaks the rule — it just is not a candidate.
void main() {
  Project projectNamed(List<String> names) {
    var sequence = 0;
    Cut cutNamed(String name) {
      sequence += 1;
      return createDefaultCut(
        cutId: CutId('cut-$sequence'),
        name: name,
        layerId: defaultLayerIdForSequence(sequence),
      );
    }

    return Project(
      id: const ProjectId('naming-project'),
      name: 'Naming',
      createdAt: DateTime.utc(2026, 7, 25),
      tracks: [
        Track(
          id: const TrackId('track-a'),
          name: 'A',
          cuts: [for (final name in names) cutNamed(name)],
        ),
      ],
    );
  }

  String nameAfter(List<String> existing, String? reference) =>
      CutCommandCoordinator.nextCutNameAfter(projectNamed(existing), reference);

  test('the next number, when nobody holds it', () {
    expect(nameAfter(['1', '2', '3'], '3'), '4');
  });

  test('a split marker is not part of the count', () {
    expect(nameAfter(['39A'], '39A'), '40');
  });

  test('a taken number turns the insert into a split', () {
    // Slipping a cut between 39 and 40 is exactly where 39A comes from.
    expect(nameAfter(['39', '40'], '39'), '39A');
  });

  test('a split continues its own series rather than nesting', () {
    expect(nameAfter(['39', '39A', '40'], '39A'), '39B');
  });

  test('a prefix rides along with the number', () {
    expect(nameAfter(['C39'], 'C39'), 'C40');
  });

  test('a name with no digits takes a suffix directly', () {
    expect(nameAfter(['オープニング'], 'オープニング'), 'オープニングA');
  });

  test('an empty track counts up from one', () {
    expect(nameAfter(const [], null), '1');
  });

  test('a project of only non-numeric names still counts up from one', () {
    // The old rule read the highest NUMERIC name and answered '1' here even
    // though it was appending to a numbered show.
    expect(nameAfter(['39A', '39B'], null), '1');
    expect(nameAfter(['39A', '39B'], '39B'), '40');
  });

  test('the suffix cycles past Z into numbered variants', () {
    final taken = [
      '39',
      for (var letter = 65; letter <= 90; letter += 1)
        '39${String.fromCharCode(letter)}',
      '40',
    ];

    expect(nameAfter(taken, '39'), '39A1');
  });
}
