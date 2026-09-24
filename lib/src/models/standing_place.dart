import 'cut_id.dart';
import 'layer_id.dart';

/// Where the user stood when an edit was made — the cut, the row and the
/// frame, and nothing else (I-41, 유저 2026-09-24: 「컷·레이어·프레임만 —
/// 화면 확대·스크롤·선택범위·도구는 그대로」).
///
/// The history keeps one beside every entry, so an undo can walk there
/// before it takes the edit back.
typedef StandingPlace = ({CutId cut, LayerId? layer, int frame});
