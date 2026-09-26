import 'package:flutter/foundation.dart';

import 'package:anicel/src/ui/storyboard_cut_thumbnail_store.dart';

/// Panel pictures that are all there already: [resolve] as given, and
/// nothing ever lands — for a test that asks what is drawn, not when.
StoryboardThumbnails fixedThumbnails(StoryboardThumbnailResolver resolve) =>
    (resolve: resolve, landed: _nothingLands);

final Listenable _nothingLands = ValueNotifier<int>(0);
