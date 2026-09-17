/// reverse geocoding の生フィールドから、投稿へ保存してよい程度に粗い
/// 撮影地ラベルを組み立てる(B2)。
///
/// 緯度経度・番地・施設名は一切扱わない(そもそも受け取らない)。特定の
/// 国の住所形式にハードコードしすぎないよう、
/// 「市区町村」「市 + 区」「都道府県 + 市区町村」の3パターンへ一般化した
/// フォールバックにしている。該当する情報が何も無ければ null を返す
/// (空文字や例外にはしない)。
///
/// 純粋関数にしてあるので、`geocoding` プラグイン(プラットフォーム
/// チャンネル)なしに unit test できる。
String? buildAreaLabel({
  String? locality,
  String? subLocality,
  String? subAdministrativeArea,
  String? administrativeArea,
}) {
  final loc = _clean(locality);
  final subLoc = _clean(subLocality);
  final subAdmin = _clean(subAdministrativeArea);
  final admin = _clean(administrativeArea);

  // 「市」相当。多くの国で locality がこれにあたる
  // (東京23区のように locality 自体が区の場合もある)。
  final city = loc ?? subAdmin;

  // 「区」相当。city と同じ文字列なら重複表示にしない。
  final ward = (subLoc != null && subLoc != city) ? subLoc : null;

  if (city != null && ward != null) return '$city $ward';
  if (city != null) return city;

  // city 相当の情報が無いときだけ、都道府県 (+ あれば追加の行政区分名)。
  if (admin != null && subAdmin != null && subAdmin != admin) {
    return '$admin $subAdmin';
  }
  if (admin != null) return admin;

  return null;
}

String? _clean(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}
