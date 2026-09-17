import 'dart:async';

/// 近距離検知の状態（仕様書 15 の画面状態に対応）。
enum ProximityStatus {
  /// まだ何もしていない。
  idle,

  /// スキャン中。
  scanning,

  /// Bluetooth が OFF。
  bluetoothOff,

  /// Bluetooth の権限が無い。
  permissionDenied,

  /// この端末が BLE に対応していない。
  unsupported,
}

/// 近距離で見つかった相手。
class NearbyPeer {
  const NearbyPeer({required this.beaconId, required this.seenAt, this.rssi});

  /// 電波に載っている 4 バイトの識別子（仕様書 3.15）。
  /// uid はここには含まれない。サーバーで解決する。
  final String beaconId;
  final DateTime seenAt;
  final int? rssi;
}

/// 閲覧権限の交換が成立したときの通知。
class ProximityExchange {
  const ProximityExchange({required this.peerName, required this.at});

  final String peerName;
  final DateTime at;
}

/// 近距離検知の口。
///
/// BLE の実装（[BleProximityService]）と、実機が無くても画面を確かめられる
/// ダミー（[FakeProximityService]）の2つが同じ形で使える。
abstract class ProximityService {
  /// 自分の beaconId をアドバタイズしつつ、周囲をスキャンする。
  ///
  /// 仕様書 18.1 のとおりフォアグラウンドの間だけ動かす想定。
  Future<void> start({required String myBeaconId});

  /// サーバー側で beaconId がローテーションされたときに、広告中の値を
  /// 差し替える。start() 前や値が変わっていないときは何もしない。
  Future<void> updateBeaconId(String myBeaconId);

  Future<void> stop();

  /// 一度だけスキャンして、見つかった相手を返す（仕様書 10.3 手動検索）。
  Future<List<NearbyPeer>> scanOnce({Duration timeout});

  Stream<ProximityStatus> get status;

  /// 近くで検知した相手。継続検知中は同じ相手が繰り返し流れる。
  Stream<List<NearbyPeer>> get peers;

  void dispose();
}

/// BLE を使わずに各状態を再現するダミー。
///
/// 仕様書 15 の「Bluetooth の内部実装完成を待たず、ダミーデータで画面を
/// 確認できるようにしてよい」に対応する。デバッグメニューから切り替える。
class FakeProximityService implements ProximityService {
  FakeProximityService({this.scenario = FakeScenario.foundFriend});

  FakeScenario scenario;

  final _status = StreamController<ProximityStatus>.broadcast();
  final _peers = StreamController<List<NearbyPeer>>.broadcast();

  /// ダミーが返す beaconId。サーバーに実在する値を入れれば解決まで通せる。
  static const fakeBeaconId = 'deadbeef';

  @override
  Stream<ProximityStatus> get status => _status.stream;

  @override
  Stream<List<NearbyPeer>> get peers => _peers.stream;

  @override
  Future<void> start({required String myBeaconId}) async {
    _status.add(_statusFor(scenario));
  }

  @override
  Future<void> updateBeaconId(String myBeaconId) async {}

  @override
  Future<void> stop() async => _status.add(ProximityStatus.idle);

  @override
  Future<List<NearbyPeer>> scanOnce({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    _status.add(_statusFor(scenario));
    await Future<void>.delayed(const Duration(milliseconds: 900));

    if (scenario != FakeScenario.foundFriend &&
        scenario != FakeScenario.foundStranger) {
      _status.add(ProximityStatus.idle);
      return const [];
    }

    final found = [
      NearbyPeer(beaconId: fakeBeaconId, seenAt: DateTime.now(), rssi: -55),
    ];
    _peers.add(found);
    _status.add(ProximityStatus.idle);
    return found;
  }

  ProximityStatus _statusFor(FakeScenario s) => switch (s) {
        FakeScenario.bluetoothOff => ProximityStatus.bluetoothOff,
        FakeScenario.permissionDenied => ProximityStatus.permissionDenied,
        _ => ProximityStatus.scanning,
      };

  @override
  void dispose() {
    _status.close();
    _peers.close();
  }
}

/// ダミーで再現したい状況。
enum FakeScenario {
  foundFriend,
  foundStranger,
  notFound,
  bluetoothOff,
  permissionDenied,
}
