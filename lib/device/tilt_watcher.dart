import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

/// 端末をどちら向きに持っているか。
enum DeviceTilt { portrait, landscape }

/// 端末の物理的な傾きを見張る。
///
/// アプリは縦画面固定なので、横に倒しても画面は回らず `didChangeMetrics` も
/// 発火しない。そこで加速度センサーの重力成分から傾きを求める。
///
/// 境目でばたつかないよう、判定にヒステリシスと保持時間を入れている。
class TiltWatcher {
  TiltWatcher({
    this.toLandscapeRatio = 1.4,
    this.toPortraitRatio = 1.4,
    this.holdFor = const Duration(milliseconds: 350),
  });

  /// 縦→横と判定する |x| / |y| の比。1 より大きくして余裕を持たせる。
  final double toLandscapeRatio;

  /// 横→縦と判定する |y| / |x| の比。
  final double toPortraitRatio;

  /// この時間だけ同じ向きが続いたら確定する。
  final Duration holdFor;

  final _controller = StreamController<DeviceTilt>.broadcast();
  StreamSubscription<AccelerometerEvent>? _sub;

  /// 確定している向き。
  DeviceTilt _current = DeviceTilt.portrait;

  /// 判定待ちの向きと、そうなり始めた時刻。
  DeviceTilt? _pending;
  DateTime? _pendingSince;

  DeviceTilt get current => _current;

  /// 向きが変わったときだけ流れる。
  Stream<DeviceTilt> get changes => _controller.stream;

  void start() {
    _sub ??= accelerometerEventStream().listen(_onEvent, onError: (_) {
      // センサーが無い端末では何も流さない。縦固定のまま使える。
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _pending = null;
    _pendingSince = null;
  }

  void _onEvent(AccelerometerEvent event) {
    final x = event.x.abs();
    final y = event.y.abs();

    // 平らに置いているときは重力が z に寄って x,y が小さくなる。
    // そこで判定すると誤検知するので、傾きが十分なときだけ見る。
    if (math.sqrt(x * x + y * y) < 4.5) {
      _pending = null;
      _pendingSince = null;
      return;
    }

    final DeviceTilt observed;
    if (_current == DeviceTilt.portrait) {
      // 縦のときは、横だと自信を持って言えるまで切り替えない。
      observed = x > y * toLandscapeRatio
          ? DeviceTilt.landscape
          : DeviceTilt.portrait;
    } else {
      observed =
          y > x * toPortraitRatio ? DeviceTilt.portrait : DeviceTilt.landscape;
    }

    if (observed == _current) {
      _pending = null;
      _pendingSince = null;
      return;
    }

    final nowAt = DateTime.now();
    if (_pending != observed) {
      _pending = observed;
      _pendingSince = nowAt;
      return;
    }

    // 一定時間続いたら確定する。持ち替えの一瞬では切り替わらない。
    if (nowAt.difference(_pendingSince!) < holdFor) return;

    _current = observed;
    _pending = null;
    _pendingSince = null;
    _controller.add(_current);
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
