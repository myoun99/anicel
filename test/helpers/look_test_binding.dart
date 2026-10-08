import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/look_only_frames.dart';

/// Counts the frames that are DRAWN: `drawFrame` as it stands UNDER the
/// law — a frame the law lets pass never gets here.
class _CountsDrawnFrames extends AutomatedTestWidgetsFlutterBinding {
  int drawnFrames = 0;

  @override
  void drawFrame() {
    drawnFrames += 1;
    super.drawFrame();
  }
}

/// The test binding with the PRODUCTION law mixed in ([LookOnlyFrames]) —
/// as `ScaledTestBinding` wears the UI scale's.
///
/// 🚨Without this a test of 「the screen is redrawn as often as the frame
/// changes」 has nothing to count. `flutter_test` installs its own binding,
/// which draws every frame it begins: under it a clock that asks only to
/// look is drawn like anything else, and the law could be deleted with
/// every test green.
///
/// [drawnFrames] is what it adds: the frames that reached the framework's
/// own `drawFrame`.
class LookTestBinding extends _CountsDrawnFrames with LookOnlyFrames {
  static LookTestBinding ensureInitialized() {
    if (_instance == null) {
      LookTestBinding();
    }
    return _instance!;
  }

  static LookTestBinding? _instance;

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
  }
}
