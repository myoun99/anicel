import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/open_project_file.dart';

import 'temp_dir.dart';

/// Removes [directory] once the test is over, ending the session's hold on
/// the `.anicel` inside it first.
///
/// 🚨★★★**A HELD PROJECT FILE BLOCKS DELETING THE FOLDER IT SITS IN — ON
/// PURPOSE.** A file-backed cel reads through [OpenProjectFile], which
/// keeps the project file open for the next read, and on Windows that also
/// stops the file (and its folder) from being deleted or moved. In the app
/// that IS the feature: the project cannot be pulled out from under the
/// session drawing into it, which used to cost a whole session's work.
///
/// The app's release point is the whole-store swap that opening the next
/// project performs. A test has no such moment — it drops its store on the
/// floor and Dart has no destructor — so it says so here, and the release
/// has to be part of THIS callback rather than a corpus-wide `tearDown`:
/// `addTearDown` callbacks all run before any `tearDown`, so a global one
/// fires long after the delete it was meant to unblock.
///
/// The delete itself is [deleteTempQuietly]'s: cleaning up is not the
/// test's result, so a handle the OS still holds must not fail it.
void deleteAfterSessionEnds(Directory directory) {
  addTearDown(() {
    OpenProjectFile.instance.release();
    deleteTempQuietly(directory);
  });
}
