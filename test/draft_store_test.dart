import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sns_novahack/drafts/draft_store.dart';
import 'package:sns_novahack/models/models.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('draft_store_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      if (call.method == 'getApplicationSupportDirectory') {
        return tempDir.path;
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('save してから loadAll で読み直せる', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final saved = await DraftStore.instance.save(
      bytes: bytes,
      kind: PostKind.film35mm,
      contentType: 'image/jpeg',
    );

    final loaded = await DraftStore.instance.loadAll();
    expect(loaded, hasLength(1));
    expect(loaded.first.id, saved.id);
    expect(await DraftStore.instance.readBytes(loaded.first), bytes);
  });

  test('locationLabel を保持する', () async {
    await DraftStore.instance.save(
      bytes: Uint8List.fromList([1]),
      kind: PostKind.film8mm,
      contentType: 'video/mp4',
      locationLabel: '大阪市 中央区',
    );

    final loaded = await DraftStore.instance.loadAll();
    expect(loaded.single.locationLabel, '大阪市 中央区');
  });

  test('delete で manifest と media ファイルの両方が消える(他へは影響しない)', () async {
    final a = await DraftStore.instance.save(
      bytes: Uint8List.fromList([1, 2]),
      kind: PostKind.film35mm,
      contentType: 'image/jpeg',
    );
    final b = await DraftStore.instance.save(
      bytes: Uint8List.fromList([3, 4]),
      kind: PostKind.film35mm,
      contentType: 'image/jpeg',
    );
    final aFile = await DraftStore.instance.mediaFile(a);
    expect(await aFile.exists(), isTrue);

    await DraftStore.instance.delete(a);

    expect(await aFile.exists(), isFalse);
    final remaining = await DraftStore.instance.loadAll();
    expect(remaining, hasLength(1));
    expect(remaining.single.id, b.id);
  });

  test('locationLabel の無い古い manifest 形式も読み込める', () async {
    final dir = Directory('${tempDir.path}/drafts');
    await dir.create(recursive: true);
    await File('${dir.path}/old.jpg').writeAsBytes([9, 9, 9]);
    await File('${dir.path}/manifest.json').writeAsString(jsonEncode({
      'drafts': [
        {
          'id': 'old-1',
          'fileName': 'old.jpg',
          'kind': '35mm',
          'contentType': 'image/jpeg',
          'createdAt': DateTime(2026, 1, 1).millisecondsSinceEpoch,
          // locationLabel キー自体が無い、B2 以前の manifest を模擬。
        },
      ],
    }));

    final loaded = await DraftStore.instance.loadAll();
    expect(loaded, hasLength(1));
    expect(loaded.single.locationLabel, isNull);
  });

  test('メディアが無い壊れた entry は無視し、正常な entry だけ返す', () async {
    final dir = Directory('${tempDir.path}/drafts');
    await dir.create(recursive: true);
    await File('${dir.path}/exists.jpg').writeAsBytes([1]);
    await File('${dir.path}/manifest.json').writeAsString(jsonEncode({
      'drafts': [
        {
          'id': 'missing-media',
          'fileName': 'does-not-exist.jpg',
          'kind': '35mm',
          'contentType': 'image/jpeg',
          'createdAt': DateTime(2026, 1, 1).millisecondsSinceEpoch,
        },
        {
          'id': 'ok',
          'fileName': 'exists.jpg',
          'kind': '35mm',
          'contentType': 'image/jpeg',
          'createdAt': DateTime(2026, 1, 2).millisecondsSinceEpoch,
        },
      ],
    }));

    final loaded = await DraftStore.instance.loadAll();
    expect(loaded, hasLength(1));
    expect(loaded.single.id, 'ok');
  });

  test('壊れた entry(型不正)があっても他の正常な entry は読み込める', () async {
    final dir = Directory('${tempDir.path}/drafts');
    await dir.create(recursive: true);
    await File('${dir.path}/exists.jpg').writeAsBytes([1]);
    await File('${dir.path}/manifest.json').writeAsString(jsonEncode({
      'drafts': [
        'this is not a map',
        {
          'id': 'ok',
          'fileName': 'exists.jpg',
          'kind': '35mm',
          'contentType': 'image/jpeg',
          'createdAt': DateTime(2026, 1, 2).millisecondsSinceEpoch,
        },
      ],
    }));

    final loaded = await DraftStore.instance.loadAll();
    expect(loaded, hasLength(1));
    expect(loaded.single.id, 'ok');
  });

  test('新しい順(createdAt 降順)で返る', () async {
    final dir = Directory('${tempDir.path}/drafts');
    await dir.create(recursive: true);
    await File('${dir.path}/a.jpg').writeAsBytes([1]);
    await File('${dir.path}/b.jpg').writeAsBytes([2]);
    await File('${dir.path}/manifest.json').writeAsString(jsonEncode({
      'drafts': [
        {
          'id': 'older',
          'fileName': 'a.jpg',
          'kind': '35mm',
          'contentType': 'image/jpeg',
          'createdAt': DateTime(2026, 1, 1).millisecondsSinceEpoch,
        },
        {
          'id': 'newer',
          'fileName': 'b.jpg',
          'kind': '35mm',
          'contentType': 'image/jpeg',
          'createdAt': DateTime(2026, 1, 2).millisecondsSinceEpoch,
        },
      ],
    }));

    final loaded = await DraftStore.instance.loadAll();
    expect(loaded.map((d) => d.id).toList(), ['newer', 'older']);
  });
}
