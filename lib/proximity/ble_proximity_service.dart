import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../device/app_permissions.dart';
import 'proximity_service.dart';

/// BLE による近距離検知。
///
/// 相手を見つけるには双方が「広告を出しつつ相手を探す」必要があるので、
/// ペリフェラル（アドバタイズ）とセントラル（スキャン）を同時に動かす。
///
/// 電波に載せるのはサーバー発行の 4 バイト beaconId だけで、uid は載せない
/// （仕様書 3.15）。beaconId から uid への解決はサーバーが行う。
class BleProximityService implements ProximityService {
  /// サービス UUID の共通サフィックス。beaconId（8桁hex）を先頭に
  /// 埋め込んだ UUID を端末ごとに生成して広告する。
  ///
  /// 【既知の制約】iOS の CoreBluetooth はペリフェラル広告に製造者データを
  /// 一切含められない（Apple 全体の仕様上の制約で、サービス UUID と
  /// ローカルネームしか広告できない）。そのため beaconId を製造者データ
  /// だけに頼ると iOS 端末は一切検知できない（iOS→他端末はもちろん、
  /// iOS→iOS でも同様）。
  ///
  /// 対策として、beaconId をサービス UUID 自体に埋め込んで広告する。
  /// Android は今まで通り製造者データを見て検知できるので互換性を保ちつつ
  /// （Android⇄Android の挙動・プロトコルは変更しない）、製造者データが
  /// 読めない相手（iOS）に対してはサービス UUID から beaconId を読み取る
  /// フォールバックで検知する。
  static const _serviceUuidSuffix = '-0000-1000-8000-00805f9b34fb';

  static Guid _serviceUuidFor(String beaconId) =>
      Guid('$beaconId$_serviceUuidSuffix');

  /// スキャン結果のサービス UUID 一覧から beaconId を取り出す。
  /// 一致しなければ null。
  static String? _beaconIdFromServiceUuids(List<Guid> uuids) {
    for (final uuid in uuids) {
      final full = uuid.str128;
      if (full.length == 36 && full.endsWith(_serviceUuidSuffix)) {
        final id = full.substring(0, 8);
        if (RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(id)) return id.toLowerCase();
      }
    }
    return null;
  }

  final _peripheral = FlutterBlePeripheral();
  final _status = StreamController<ProximityStatus>.broadcast();
  final _peers = StreamController<List<NearbyPeer>>.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  bool _advertising = false;
  String? _currentBeaconId;

  /// 常時スキャン中に見つかった相手（beaconId → 直近の検知情報）。
  /// フォアグラウンドの間しか動かさない（[ProximityService.start] 参照）ので
  /// バッテリー消費は常時スキャンでも許容できる。
  final _liveFound = <String, NearbyPeer>{};
  Timer? _liveEmitTimer;
  Timer? _scanRefreshTimer;
  bool _continuousScanActive = false;

  /// この時間見つからなかった相手は「もういない」として一覧から外す。
  /// 【実験】毎秒フレッシュネスバイトを変えて広告し直しているので、
  /// 実際に近くにいれば毎秒検知され続けるはず。検知が本当に途切れたら
  /// 数秒で「もういない」と判定してよい。
  static const _peerTtl = Duration(seconds: 3);

  /// dispose() 後は、待機していた非同期処理が復帰しても何もしない。
  /// 待たずに閉じた StreamController に書き込むとクラッシュするため。
  bool _disposed = false;

  void _emitStatus(ProximityStatus s) {
    if (!_disposed) _status.add(s);
  }

  void _emitPeers(List<NearbyPeer> p) {
    if (!_disposed) _peers.add(p);
  }

  @override
  Stream<ProximityStatus> get status => _status.stream;

  @override
  Stream<List<NearbyPeer>> get peers => _peers.stream;

  @override
  Future<void> start({required String myBeaconId}) async {
    if (_disposed) return;
    try {
      if (!await FlutterBluePlus.isSupported) {
        _emitStatus(ProximityStatus.unsupported);
        return;
      }
      if (!await _hasPermissions()) {
        _emitStatus(ProximityStatus.permissionDenied);
        return;
      }
      if (_disposed) return;

      _adapterSub ??= FlutterBluePlus.adapterState.listen(
        (state) {
          if (state == BluetoothAdapterState.off) {
            _emitStatus(ProximityStatus.bluetoothOff);
          }
        },
        onError: (_) {
          // アダプタ状態の監視自体に失敗しても検知は諦めない。
        },
      );

      if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.off) {
        _emitStatus(ProximityStatus.bluetoothOff);
        return;
      }

      await _advertise(myBeaconId);
      await _startContinuousScan();
    } catch (_) {
      // この端末では BLE の初期化そのものが失敗した(非対応機種・OS制約等)。
      // アプリ本体を落とさず、近距離検知が使えないことだけ伝える。
      if (!_disposed) _emitStatus(ProximityStatus.unsupported);
    }
  }

  /// スキャンを止めずに回し続ける。すれ違いが一瞬でも取りこぼしにくくする。
  ///
  /// Android の「scanning too frequently」制限は start/stop を繰り返す
  /// 回数に対するものなので、1度 startScan したまま止めない分には
  /// むしろ引っかかりにくい。
  Future<void> _startContinuousScan() async {
    if (_disposed || _continuousScanActive) return;
    if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.off) {
      _emitStatus(ProximityStatus.bluetoothOff);
      return;
    }
    if (!await _hasPermissions()) {
      _emitStatus(ProximityStatus.permissionDenied);
      return;
    }
    if (_disposed) return;

    _emitStatus(ProximityStatus.scanning);
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      final now = DateTime.now();
      for (final r in results) {
        final beaconId = _beaconIdOf(r);
        if (beaconId == null) continue;
        _liveFound[beaconId] =
            NearbyPeer(beaconId: beaconId, seenAt: now, rssi: r.rssi);
      }
    });

    try {
      // beaconId をサービス UUID 自体に埋め込む端末（iOS）があるため、
      // UUID の完全一致では絞り込めない。フィルタ無しでスキャンし、
      // _beaconIdOf() 側で製造者データ／サービス UUID の両方から判定する。
      // timeout を指定しなければ stopScan() するまで回り続ける。
      await FlutterBluePlus.startScan();
      _continuousScanActive = true;
    } catch (_) {
      _continuousScanActive = false;
    }

    _liveEmitTimer?.cancel();
    _liveEmitTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _pruneAndEmit();
    });

    // BLEチップの重複除去フィルターが、内容の変わらない広告(同じ
    // beaconId)をずっと同じとみなして、途中から報告しなくなることが
    // ある（beaconIdをローテーションした瞬間だけ復活する、という
    // 症状から判明）。フィルターのキャッシュをリセットするため、
    // 「scanning too frequently」の閾値よりずっと低い頻度で
    // スキャンを定期的に作り直す。
    _scanRefreshTimer?.cancel();
    _scanRefreshTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      unawaited(_refreshScan());
    });
  }

  Future<void> _refreshScan() async {
    if (_disposed || !_continuousScanActive) return;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {
      // 既に止まっている。
    }
    _continuousScanActive = false;
    await _startContinuousScan();
  }

  void _pruneAndEmit() {
    if (_disposed) return;
    final cutoff = DateTime.now().subtract(_peerTtl);
    _liveFound.removeWhere((_, p) => p.seenAt.isBefore(cutoff));
    _emitPeers(_liveFound.values.toList());
  }

  /// サーバー側で beaconId がローテーションされたら、広告を新しい値で
  /// 出し直す。盗聴された旧IDをいつまでも送り続けないようにするため。
  /// スキャンは止めていないので、広告の付け替えだけで完結する。
  @override
  Future<void> updateBeaconId(String myBeaconId) async {
    if (_disposed || _currentBeaconId == myBeaconId) return;
    await _restartAdvertising(myBeaconId);
  }

  Future<void> _restartAdvertising(String myBeaconId) async {
    if (_advertising) {
      try {
        await _peripheral.stop();
      } catch (_) {
        // 既に止まっている。
      }
      _advertising = false;
    }
    await _advertise(myBeaconId);
  }

  /// 【実験】BLEチップの重複除去フィルターを高頻度で回避できるか試すための
  /// 1バイトカウンター。identity(beaconId本体)には影響しない。
  int _freshnessCounter = 0;
  Timer? _freshnessTimer;

  /// beaconId を製造者データに載せて広告する。
  Future<void> _advertise(String myBeaconId) async {
    if (_advertising) return;
    _currentBeaconId = myBeaconId;
    try {
      await _peripheral.start(
        advertiseData: AdvertiseDataCore(
          serviceUuid: _serviceUuidFor(myBeaconId).str,
          manufacturerId: _manufacturerId,
          manufacturerData: _withFreshnessByte(_hexToBytes(myBeaconId)),
        ),
        androidSettings: const AndroidAdvertiseSettings(
          advertiseSettings: AdvertiseSettings(
            // 相手に早く見つけてもらう。すれ違いは一瞬なので遅延を優先する。
            advertiseMode: AdvertiseMode.advertiseModeLowLatency,
            // 【実験】出力を下げて到達距離を絞る（1m程度の近距離想定）。
            txPowerLevel: AdvertiseTxPower.advertiseTxPowerUltraLow,
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

    // 【実験】1秒ごとに末尾1バイトだけ変えて広告を作り直す。
    //
    // iOS の CoreBluetooth は広告の stop/start を高頻度で繰り返すと
    // ピリフェラルマネージャが実際には広告を有効化しないまま失敗する
    // ことがある（実機で電波が一切出なくなる症状で判明）。この対策は
    // Android の BLE チップ重複除去フィルター回避が目的なので、iOS では
    // 行わない。
    _freshnessTimer?.cancel();
    if (!Platform.isIOS) {
      _freshnessTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (_disposed || _currentBeaconId == null) return;
        _freshnessCounter = (_freshnessCounter + 1) & 0xff;
        _advertising = false;
        try {
          await _peripheral.stop();
        } catch (_) {}
        await _advertise(_currentBeaconId!);
      });
    }
  }

  Uint8List _withFreshnessByte(Uint8List id) {
    return Uint8List.fromList([...id, _freshnessCounter]);
  }

  /// 手動検索（フレンド追加画面）用。常時スキャンが既に回っているので、
  /// その場のスナップショットを返すだけでよい。start() 直後などまだ何も
  /// 拾っていなければ、電波を拾う時間を少し確保してから返す。
  @override
  Future<List<NearbyPeer>> scanOnce({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (_disposed) return const [];
    if (!_continuousScanActive) {
      await _startContinuousScan();
    }
    if (_liveFound.isEmpty) {
      await Future.delayed(const Duration(seconds: 2));
    }
    if (_disposed) return const [];
    _pruneAndEmit();
    return _liveFound.values.toList();
  }

  /// 広告から beaconId を取り出す。本SNS の広告でなければ null。
  ///
  /// まず製造者データを見る（Android⇄Android はこれで従来通り検知できる）。
  /// 製造者データが読めない相手（iOS。CoreBluetooth の制約で製造者データを
  /// 広告できない）には、サービス UUID に埋め込まれた beaconId で判定する。
  String? _beaconIdOf(ScanResult result) {
    final data = result.advertisementData.manufacturerData[_manufacturerId];
    // 【実験】末尾1バイトはフレッシュネス用なので identity には含めない。
    if (data != null && data.length == 5) {
      return data
          .take(4)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
    }
    return _beaconIdFromServiceUuids(result.advertisementData.serviceUuids);
  }

  /// 現況を読むだけで、絶対に OS permission dialog は出さない
  /// (要求は初回 Consent/Permission 画面だけが行う)。
  /// Home 到達後や resumed のたびにここを通っても、ユーザーには何も
  /// ポップアップしない。
  Future<bool> _hasPermissions() =>
      AppPermissions.isGranted(AppPermissionKind.bluetooth);

  @override
  Future<void> stop() async {
    _liveEmitTimer?.cancel();
    _liveEmitTimer = null;
    _scanRefreshTimer?.cancel();
    _scanRefreshTimer = null;
    _freshnessTimer?.cancel();
    _freshnessTimer = null;
    _liveFound.clear();
    _continuousScanActive = false;
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
    _currentBeaconId = null;
    _emitStatus(ProximityStatus.idle);
  }

  @override
  void dispose() {
    _disposed = true;
    _liveEmitTimer?.cancel();
    _scanRefreshTimer?.cancel();
    _freshnessTimer?.cancel();
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
