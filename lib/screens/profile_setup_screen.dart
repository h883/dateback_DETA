import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../api/bloom_api.dart';
import '../models/models.dart';
import '../theme/bloom_theme.dart';
import '../widgets/remote_image.dart';

/// Google ログイン直後、プロフィールが未設定のときに通す画面。
/// ユーザー名・アイコン・自己紹介文をここで決める。
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    super.key,
    required this.api,
    required this.onDone,
    this.initial,
    this.suggestedName,
    this.suggestedAvatarUrl,
  });

  final BloomApi api;

  /// 保存が終わったら、確定したプロフィールを渡して呼ばれる。
  final void Function(Profile profile) onDone;

  /// 既存プロフィールの編集時に渡す。新規なら null。
  final Profile? initial;

  /// Google アカウントの表示名。初期値に使う。
  final String? suggestedName;

  /// Google アカウントのプロフィール写真。初期のアイコンに使う。
  final String? suggestedAvatarUrl;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _username;
  late final TextEditingController _bio;

  Uint8List? _pickedAvatar;
  String? _pickedAvatarType;
  String? _existingAvatarPath;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Google アカウントの表示名をそのまま初期値にする。日本語も通す。
    final suggested = (widget.suggestedName ?? '').trim();
    _username = TextEditingController(
      text: widget.initial?.username ??
          (suggested.characters.length > 20
              ? suggested.characters.take(20).toString()
              : suggested),
    );
    _bio = TextEditingController(text: widget.initial?.bio ?? '');
    _existingAvatarPath = widget.initial?.avatarPath;

    // 新規で自分のアイコンが無ければ、Google の写真を取り込む。
    if (widget.initial?.avatarPath == null) {
      _loadGoogleAvatar();
    }
  }

  /// Google のプロフィール写真を落としてアイコンの初期値にする。
  /// 失敗しても黙って諦める（本人が選び直せる）。
  Future<void> _loadGoogleAvatar() async {
    final url = widget.suggestedAvatarUrl;
    if (url == null || url.isEmpty) return;
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return;
      if (!mounted || _pickedAvatar != null) return;
      setState(() {
        _pickedAvatar = res.bodyBytes;
        _pickedAvatarType = res.headers['content-type'] ?? 'image/jpeg';
      });
    } catch (_) {
      // 取れなければアイコン未設定のまま。
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 88,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pickedAvatar = bytes;
      _pickedAvatarType = picked.mimeType ?? 'image/jpeg';
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      var profile = await widget.api.saveMyProfile(
        username: _username.text.trim(),
        bio: _bio.text.trim(),
      );
      // アイコンは本体の保存が通ってから送る。失敗しても名前は残る。
      if (_pickedAvatar != null) {
        profile = await widget.api.uploadAvatar(
          _pickedAvatar!,
          _pickedAvatarType ?? 'image/jpeg',
        );
      }
      if (!mounted) return;
      widget.onDone(profile);
    } on BloomApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '保存できませんでした: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              BloomSpace.margin,
              BloomSpace.lg,
              BloomSpace.margin,
              40,
            ),
            children: [
              Text(
                isEdit ? 'プロフィールを編集' : 'プロフィールを設定',
                style: BloomText.headlineLg.copyWith(color: colors.onSurface),
              ),
              const SizedBox(height: BloomSpace.sm),
              Text(
                'フレンドに表示される名前とアイコンです。あとから変更できます。',
                style: BloomText.bodySm.copyWith(color: colors.secondary),
              ),
              const SizedBox(height: BloomSpace.xl),
              Center(child: _avatarPicker(colors)),
              const SizedBox(height: BloomSpace.xl),
              _label('名前', colors),
              const SizedBox(height: BloomSpace.sm),
              TextFormField(
                controller: _username,
                style: BloomText.bodyLg.copyWith(color: colors.onSurface),
                maxLength: 20,
                decoration: _fieldDecoration('そら', colors),
                validator: (value) {
                  final v = (value ?? '').trim();
                  if (v.isEmpty) return '名前を入力してください';
                  return null;
                },
              ),
              const SizedBox(height: BloomSpace.sm),
              _label('自己紹介', colors),
              const SizedBox(height: BloomSpace.sm),
              TextFormField(
                controller: _bio,
                style: BloomText.bodyMd.copyWith(color: colors.onSurface),
                maxLines: 3,
                maxLength: 160,
                decoration: _fieldDecoration('静かな写真だけ残す。文章は少なめ。', colors),
              ),
              if (_error != null) ...[
                const SizedBox(height: BloomSpace.sm),
                Text(
                  _error!,
                  style: BloomText.bodySm.copyWith(color: colors.error),
                ),
              ],
              const SizedBox(height: BloomSpace.lg),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primaryContainer,
                  foregroundColor: colors.onPrimaryContainer,
                  disabledBackgroundColor: colors.surfaceContainerHigh,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: const StadiumBorder(),
                ),
                child: _saving
                    ? SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: colors.onSurface,
                        ),
                      )
                    : Text(
                        isEdit ? '保存する' : 'はじめる',
                        style: BloomText.labelLg.copyWith(
                          color: colors.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text, BloomColorsExt colors) => Text(
        text,
        style: BloomText.labelMd.copyWith(color: colors.onSurfaceVariant),
      );

  InputDecoration _fieldDecoration(String hint, BloomColorsExt colors) =>
      InputDecoration(
        hintText: hint,
        hintStyle: BloomText.bodyMd.copyWith(color: colors.secondary),
        counterStyle: BloomText.labelSm.copyWith(color: colors.secondary),
        filled: true,
        fillColor: colors.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BloomRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BloomRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BloomRadius.md),
          borderSide: BorderSide(color: colors.primaryContainer, width: 1.5),
        ),
      );

  Widget _avatarPicker(BloomColorsExt colors) {
    final picked = _pickedAvatar;
    final existing = _existingAvatarPath;

    return Column(
      children: [
        GestureDetector(
          onTap: _pickAvatar,
          child: Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              shape: BoxShape.circle,
              border: Border.all(color: colors.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: picked != null
                ? Image.memory(picked, fit: BoxFit.cover)
                : existing != null
                    ? RemoteImage(api: widget.api, path: existing)
                    : Icon(
                        Icons.add_a_photo_outlined,
                        color: colors.secondary,
                        size: 28,
                      ),
          ),
        ),
        const SizedBox(height: BloomSpace.sm),
        TextButton(
          onPressed: _pickAvatar,
          child: Text(
            'アイコンを選ぶ',
            style: BloomText.labelMd.copyWith(color: colors.primary),
          ),
        ),
      ],
    );
  }
}
