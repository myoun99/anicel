import 'package:anicel/src/models/media_asset.dart';

/// A carry of [poolPath] under a whole name — the shape every carry is
/// minted in ([mintMediaCarry]) — with [token] for its middle, so a test can
/// tell two carries of one file apart.
///
/// ⛔NEVER A BARE TOKEN. A token alone is a shape no project can hold any
/// more (its format is refused — card `old-project-shapes-are-not-read`),
/// and the staging room keeps no bytes under it ([isOneStoredName]): a test
/// built on one measures an asset that was never staged. Four framed-movie
/// pins skipped that way for an evening (10-08), their skip saying there
/// was no engine.
MediaCarry wholeCarry(String poolPath, String token) =>
    (poolPath: poolPath, token: mediaCarryNamed(poolPath, token));
