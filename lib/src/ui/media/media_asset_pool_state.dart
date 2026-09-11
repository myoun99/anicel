import '../../models/media_asset.dart';
import '../text/app_strings.dart';

/// The word for WHERE a pool file's bytes live — 「품음」 or 「참조」.
///
/// 🚨ONE ANSWER FOR TWO PLACES. The pool row's subtitle leads with it (유저
/// 2026-08-31: 「해당 파일이 품어진 상태인지 참조인지 모르겠음. 그걸
/// 텍스트로 적어두고」), and the reference button's popover writes it beside
/// the file's name (유저 2026-09-11, 미디어 배치 라운드 5). 「참조」 means two
/// things — the POOL's is "the file lives outside the project", a LAYER's
/// is "not baked yet" — so the popover names the pool's beside the file
/// instead of leaving the one word to answer both.
String mediaAssetPoolState(MediaAsset asset) => asset.carried
    ? AppText.strings.mediaCarriedState
    : AppText.strings.mediaReferencedState;
