import 'dart:io';

/// Every file under [directory], by its path inside it — forward slashes,
/// in name order: what a run WROTE there. A folder that is not there holds
/// none.
///
/// ONE walk for the tests that read an output folder. Five of them spelled
/// it for themselves (the export window's, its queue's, the hand-over's,
/// the cels run's and the cut scope's), each with a line of its own in the
/// hand-walk ledger (`a_source_scan_walks_through_one_helper_test.dart`).
List<String> filesWrittenUnder(Directory directory) =>
    !directory.existsSync()
    ? const []
    : ([
        for (final file
            in directory.listSync(recursive: true).whereType<File>())
          file.path.substring(directory.path.length + 1).replaceAll('\\', '/'),
      ]..sort());
