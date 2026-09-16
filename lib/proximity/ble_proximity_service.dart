import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'proximity_service.dart';

/// BLE による近距離検知。
///
/// 相手を見つけるには双方が「広告を出しつつ相手を探す」必要があるので、
/// ペリフェラル（アドバタイズ）とセントラル（スキャン）を同時に動かす。
///
/// 電波に載せるのはサーバー発行の 4 バイト beaconId だけで、uid は載せない
/// （仕様書 3.15）。beaconId から uid への解決はサーバーが行う。
class BleProximityService implements ProximityService {
  /// 本SNS を示すサービス UUID。この値でスキャンを絞る。
  static final Guid serviceUuid =
      Guid('0000b100-0000-1000-8000-00805f9b34fb');

  final _peripheral = FlutterBlePeripheral();
  final _status = StreamController<ProximityStatus>.broadcast();
  final _peers = StreamController<List<NearbyPeer>>.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  Timer? _rescanTimer;
  bool _advertising = false;

  @override
  Stream<ProximityStatus> get status => _status.stream;

  @override
  Stream<List<NearbyPeer>> get peers => _peers.stream;

  @override
  Future<void> start({required String myBeaconId}) async {
    if (!await FlutterBluePlus.isSupported) {
      _status.add(ProximityStatus.unsupported);
      return;
    }
    if (!await _ensurePermissions()) {
      _status.add(ProximityStatus.permissionDenied);
      return;
    }

    _adapterSub ??= FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.off) {
        _status.add(ProximityStatus.bluetoothOff);
      }
    });

    if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.off) {
      _status.add(ProximityStatus.bluetoothOff);
      return;
    }

    await _advertise(myBeaconId);

    // 継続検知。スキャンは電池を食うので、短く回して間を空ける。
    _rescanTimer?.cancel();
    _rescanTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(scanOnce());
    });
    unawaited(scanOnce());
  }

  /// beaconId を製造者データに載せて広告する。
  Future<void> _advertise(String myBeaconId) async {
    if (_advertising) return;
    try {
      await _peripheral.start(
        advertiseData: AdvertiseDataCore(
          serviceUuid: serviceUuid.str,
          manufacturerId: _manufacturerId,
          manufacturerData: _hexToBytes(myBeaconId),
        ),
        androidSettings: const AndroidAdvertiseSettings(
          advertiseSettings: AdvertiseSettings(
            // 相手に早く見つけてもらう。すれ違いは一瞬なので遅延を優先する。
            advertiseMode: AdvertiseMode.advertiseModeLowLatency,
            txPowerLevel: AdvertiseTxPower.advertiseTxPowerHigh,
            // 接続はさせない。beaconId を広告で配るだけ。
            connectable: false,
          ),
        ),
      );
      _advertising = true;
    } catch (_) {
      // 広告に失敗しても、相手が広告できていればこちらのスキャンで拾える。
      _advertising = false;
    }
  }

  @override
  Future<List<NearbyPeer>> scanOnce({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.off) {
      _status.add(ProximityStatus.bluetoothOff);
      return const [];
    }
    if (!await _ensurePermissions()) {
      _status.add(ProximityStatus.permissionDenied);
      return const [];
    }

    _status.add(ProximityStatus.scanning);
    final found = <String, NearbyPeer>{};

    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final beaconId = _beaconIdOf(r);
        if (beaconId == null) continue;
        found[beaconId] = NearbyPeer(
          beaconId: beaconId,
          seenAt: DateTime.now(),
          rssi: r.rssi,
        );
      }
    });

    try {
      await FlutterBluePlus.startScan(
        withServices: [serviceUuid],
        timeout: timeout,
      );
      await FlutterBluePlus.isScanning.where((s) => s == false).first;
    } catch (_) {
      // スキャンに失敗したら見つからなかった扱いにする。
    } finally {
      await _scanSub?.cancel();
      _scanSub = null;
      _status.add(ProximityStatus.idle);
    }

    final peers = found.values.toList();
    if (peers.isNotEmpty) _peers.add(peers);
    return peers;
  }

  /// 広告から beaconId を取り出す。本SNS の広告でなければ null。
  String? _beaconIdOf(ScanResult result) {
    final data = result.advertisementData.manufacturerData[_manufacturerId];
    if (data == null || data.length != 4) return null;
    return data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<bool> _ensurePermissions() async {
    // Android 12 以降はスキャン/広告が個別の権限。12 未満は位置情報が要る。
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    // 位置情報は Android 12 未満でのみ必須なので、BLE 側が通れば良しとする。
    return statuses[Permission.bluetoothScan]?.isGranted != false &&
        statuses[Permission.bluetoothAdvertise]?.isGranted != false;
  }

  @override
  Future<void> stop() async {
    _rescanTimer?.cancel();
    _rescanTimer = null;
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {
      // 既に止まっている。
    }
    if (_advertising) {
      try {
        await _peripheral.stop();
      } catch (_) {
        // 既に止まっている。
      }
      _advertising = false;
    }
    _status.add(ProximityStatus.idle);
  }

  @override
  void dispose() {
    _rescanTimer?.cancel();
    _scanSub?.cancel();
    _adapterSub?.cancel();
    _status.close();
    _peers.close();
  }

  /// 製造者データの ID。実運用では Bluetooth SIG に登録された値を使うが、
  /// ここでは衝突しにくい値を借りている。
  static const _manufacturerId = 0xB100;

  static Uint8List _hexToBytes(String hex) {
    final bytes = <int>[];
    for (var i = 0; i + 1 < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }
}
