import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models/models.dart';

/// 投稿に失敗して「下書きとして残す」を選んだメディア1件。
///
/// マニフェスト(JSON)にはファイル名だけを持たせ、絶対パスは読むたびに
/// 現在のアプリ用ディレクトリから組み立てる(インストール場所が変わっても
/// 参照が壊れないように)。
class PostDraft {
  const PostDraft({
    required this.id,
    required this.fileName,
    required this.kind,
    required this.contentType,
    required this.createdAt,
    this.locationLabel,
  });

  final String id;
  final String fileName;
  final PostKind kind;
  final String contentType;
  final DateTime createdAt;

  /// 撮影時に取得済みだった撮影地(B2)。再試行時に位置を取り直さず、
  /// これをそのまま使う。あとから設定の自動追加をOFFにしても、
  /// 保存済みのこの値は書き換えない。
  final String? locationLabel;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'kind': kind.wire,
        'contentType': contentType,
        'createdAt': createdAt.millisecondsSinceEpoch,
        if (locationLabel != null) 'locationLabel': locationLabel,
      };

  factory PostDraft.fromJson(Map<String, dynamic> json) => PostDraft(
        id: json['id'] as String,
        fileName: json['fileName'] as String,
        kind: PostKind.fromWire(json['kind'] as String),
        contentType: json['contentType'] as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        locationLabel: json['locationLabel'] as String?,
      );
}

/// 投稿の下書きをローカルへ永続化する。
///
/// 方針(仕様どおり):
/// - 撮影済みメディアはアプリの support ディレクトリ配下にファイルとして
///   コピーする(RAM だけに保持しない。アプリ再起動後も残る)。
/// - どの下書きがあるかは同じディレクトリの `manifest.json` に記録する。
/// - 書き込み順は「メディアファイル → マニフェスト」。マニフェスト更新が
///   失敗したら、書きかけのメディアファイルを削除して孤立させない。
/// - マニフェスト自体は一時ファイルに書いてからリネームし、書き込み途中の
///   破損を避ける。
class DraftStore {
  DraftStore._();

  static final DraftStore instance = DraftStore._();

  Future<Directory> _draftsDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/drafts');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  File _manifestFile(Directory dir) => File('${dir.path}/manifest.json');

  /// [draft] のメディア実体への絶対パス。サムネイル表示・再投稿の
  /// どちらもこれを経由する(パスの組み立て方をここ1箇所にまとめる)。
  Future<File> mediaFile(PostDraft draft) async {
    final dir = await _draftsDir();
    return File('${dir.path}/${draft.fileName}');
  }

  /// 保存済みの下書き一覧(新しい順)。
  ///
  /// マニフェスト全体が読めない・壊れている場合は空扱いにする(下書きが
  /// 読めないだけでアプリ起動を止めたくない)。マニフェスト自体は読めても
  /// 一部の entry だけが壊れている(必須フィールド欠落・型不正)場合や、
  /// entry はあるのに対応するメディアファイルが無い場合は、その entry
  /// だけを無視して残りは正常に返す(マニフェストは書き換えない。読み込み
  /// のたびに正常な下書きを勝手に消さないため)。
  Future<List<PostDraft>> loadAll() async {
    try {
      final dir = await _draftsDir();
      final file = _manifestFile(dir);
      if (!await file.exists()) return const [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const [];
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final rawList = json['drafts'] as List? ?? const [];

      final drafts = <PostDraft>[];
      for (final entry in rawList) {
        try {
          if (entry is! Map<String, dynamic>) continue;
          final draft = PostDraft.fromJson(entry);
          if (!await File('${dir.path}/${draft.fileName}').exists()) {
            continue; // メディアが無い壊れた entry。この1件だけ無視する。
          }
          drafts.add(draft);
        } catch (_) {
          // この entry だけ壊れている(欠落フィールド等)。他へは影響させない。
        }
      }
      drafts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return drafts;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeManifest(Directory dir, List<PostDraft> drafts) async {
    final file = _manifestFile(dir);
    final tmp = File('${file.path}.tmp');
    final body = jsonEncode({'drafts': drafts.map((d) => d.toJson()).toList()});
    await tmp.writeAsString(body, flush: true);
    await tmp.rename(file.path);
  }

  /// 撮影済みメディアを下書きとして保存する。
  Future<PostDraft> save({
    required Uint8List bytes,
    required PostKind kind,
    required String contentType,
    String? locationLabel,
  }) async {
    final dir = await _draftsDir();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final ext = kind.isVideo ? 'mp4' : 'jpg';
    final fileName = '$id.$ext';
    final file = File('${dir.path}/$fileName');

    // 1. まずメディアをファイルへコピーする。
    await file.writeAsBytes(bytes, flush: true);

    final draft = PostDraft(
      id: id,
      fileName: fileName,
      kind: kind,
      contentType: contentType,
      createdAt: DateTime.now(),
      locationLabel: locationLabel,
    );

    // 2. マニフェストを更新する。失敗したら孤立ファイルを残さない。
    try {
      final drafts = await loadAll();
      await _writeManifest(dir, [...drafts, draft]);
    } catch (e) {
      try {
        await file.delete();
      } catch (_) {
        // 削除も失敗したら諦める(次回起動時のマニフェストには載らないので
        // 参照は残らない。孤立ファイルは残り得るが実害はない)。
      }
      rethrow;
    }

    return draft;
  }

  Future<Uint8List> readBytes(PostDraft draft) async {
    final dir = await _draftsDir();
    return File('${dir.path}/${draft.fileName}').readAsBytes();
  }

  /// 下書きを1件削除する(マニフェストとファイルの両方)。
  Future<void> delete(PostDraft draft) async {
    final dir = await _draftsDir();
    final drafts = await loadAll();
    final remaining = drafts.where((d) => d.id != draft.id).toList();
    await _writeManifest(dir, remaining);
    try {
      await File('${dir.path}/${draft.fileName}').delete();
    } catch (_) {
      // 既に無ければそれでよい。
    }
  }
}
