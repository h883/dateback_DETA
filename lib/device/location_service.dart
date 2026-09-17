import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'location_label.dart';

/// 撮影地(粗いエリア名)の取得(B2)。
///
/// 呼び出し側([SettingsStore.autoLocationEnabled] を見ている PostTab)が
/// ON のときだけこれを呼ぶ。ここでは ON/OFF の判断はせず、呼ばれたら
/// 「今すぐ現在地から粗いエリア名を1回だけ取る」ことだけをする
/// (Camera を開いただけで常時位置取得を始めたりはしない)。
///
/// 初回セットアップの Consent 画面で位置情報の許可は既に一度求めている
/// ため、ここでは新たに `requestPermission()` は呼ばない(不要な許可
/// ループを増やさない)。permission denied・GPS/位置情報サービス OFF・
/// reverse geocoding 失敗・タイムアウトなど、理由を問わずすべて null を
/// 返すだけにして、呼び出し元の撮影・投稿自体を失敗させない。
abstract final class LocationService {
  static const _timeout = Duration(seconds: 6);

  static Future<String?> currentAreaLabel() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          // 市区町村レベルの粗いラベルにしか使わないので、高精度は不要。
          accuracy: LocationAccuracy.low,
          timeLimit: _timeout,
        ),
      );

      final placemarks = await Geocoding()
          .placemarkFromCoordinates(position.latitude, position.longitude)
          .timeout(_timeout);
      if (placemarks.isEmpty) return null;

      final p = placemarks.first;
      return buildAreaLabel(
        locality: p.locality,
        subLocality: p.subLocality,
        subAdministrativeArea: p.subAdministrativeArea,
        administrativeArea: p.administrativeArea,
      );
    } catch (_) {
      return null;
    }
  }
}
