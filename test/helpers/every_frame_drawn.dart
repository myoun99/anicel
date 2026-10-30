import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';

/// The plan's `CelDrawn` for a project a test builds, whose every frame
/// stands for a drawing: there is no store to ask, and the plan's own laws
/// are what such a test measures.
bool everyFrameDrawn(Cut cut, LayerId row, FrameId cel) => true;
