import 'frame_id.dart';
import 'layer_id.dart';

/// A cel a move carries onto another row: its pixels are stored under the
/// row that owns it, so they stay under [from] until the release re-keys
/// them to [to] — and until then, whatever shows the cel on [to] reads them
/// under [from] (F-313).
typedef CelRekey = ({LayerId from, LayerId to, FrameId frameId});

/// A PICTURE a move hangs in another cel, the cels staying where they are
/// (F-330): the pixels of [fromCel] on [fromRow] go to [toCel] on [toRow]
/// on the release — and until then, whatever shows [toCel] on [toRow]
/// reads them where they still are.
typedef CelPictureMove = ({
  LayerId fromRow,
  FrameId fromCel,
  LayerId toRow,
  FrameId toCel,
});
