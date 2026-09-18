import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:sensors_plus/sensors_plus.dart';

/// 端末をどちら向きに持っているか。
///
/// 横向きは2方向を区別する。カメラの自動起動は「端末上部を左へ倒す＝
/// 反時計回り90°、シャッターが右側に来る向き」（[landscapeShutterRight]）
/// のときだけ行うため。
enum DeviceTilt { portrait, landscapeShutterRight, landscapeOther }

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

  /// `event.x` の符号と「シャッターが右側に来る向き」の対応。
  /// 実機で確認できるまでの仮の値。逆だった場合はここだけ反転すればよい
  /// （呼び出し側のロジックには影響しない）。
  static const bool _positiveXIsShutterRight = true;

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

  /// [_current] の初期値は [DeviceTilt.portrait] だが、start() 時点で
  /// 実際に縦向きとは限らない。以前はここに「最初のサンプルは較正だけに
  /// 使い、`changes` へは流さない」という特別扱いがあったが、それだと
  /// 起動・再開の瞬間にすでに横向きだった場合、
  /// [MainShell._onTiltChanged] のような「`changes` イベントでしか
  /// 状態を持たない」呼び出し側が起動時点の向きを一切知らされないまま
  /// になってしまっていた(tilt-to-camera の UI 回転補正が効かない
  /// 不具合の原因)。
  ///
  /// 今は最初のサンプルも他と区別せず、通常の判定(`observed == _current`
  /// の比較・pending・holdFor)にそのまま流す。起動時に本当に縦向きなら
  /// `observed == _current` となり何も起きない(意図通り)。起動時に
  /// すでに横向きなら、holdFor 分待ったうえで正しく `changes` イベントが
  /// 飛ぶ。
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
    final x = event.x;
    final y = event.y;
    final ax = x.abs();
    final ay = y.abs();

    // 平らに置いているときは重力が z に寄って x,y が小さくなる。
    // そこで判定すると誤検知するので、傾きが十分なときだけ見る。
    if (math.sqrt(ax * ax + ay * ay) < 4.5) {
      _pending = null;
      _pendingSince = null;
      return;
    }

    final bool isLandscape;
    if (_current == DeviceTilt.portrait) {
      // 縦のときは、横だと自信を持って言えるまで切り替えない。
      isLandscape = ax > ay * toLandscapeRatio;
    } else {
      isLandscape = !(ay > ax * toPortraitRatio);
    }

    final observed =
        isLandscape ? _landscapeDirection(x) : DeviceTilt.portrait;

    // TODO(実機確認後に削除): _positiveXIsShutterRight は仮値。
    // 実機でこのログの x/y と observed を見て、実際に端末上部を左へ倒した
    // （シャッターが右側に来る）ときに landscapeShutterRight になっているか
    // 確認し、逆なら _positiveXIsShutterRight を反転してから本ログを消す。
    if (kDebugMode) {
      debugPrint(
        '[TiltWatcher] x=${x.toStringAsFixed(2)} y=${y.toStringAsFixed(2)} '
        'isLandscape=$isLandscape observed=$observed current=$_current',
      );
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

  DeviceTilt _landscapeDirection(double x) {
    final isShutterRight = (x > 0) == _positiveXIsShutterRight;
    return isShutterRight
        ? DeviceTilt.landscapeShutterRight
        : DeviceTilt.landscapeOther;
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
