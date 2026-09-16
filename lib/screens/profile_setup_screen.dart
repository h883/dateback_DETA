import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  });

  final BloomApi api;

  /// 保存が終わったら、確定したプロフィールを渡して呼ばれる。
  final void Function(Profile profile) onDone;

  /// 既存プロフィールの編集時に渡す。新規なら null。
  final Profile? initial;

  /// Google アカウントの表示名。初期値の候補に使う。
  final String? suggestedName;

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
    _username = TextEditingController(
      text: widget.initial?.username ?? _sanitize(widget.suggestedName ?? ''),
    );
    _bio = TextEditingController(text: widget.initial?.bio ?? '');
    _existingAvatarPath = widget.initial?.avatarPath;
  }

  /// Google の表示名には空白や記号が入るので、使える文字だけ残す。
  static String _sanitize(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9_.\-]'), '');
    return cleaned.length > 20 ? cleaned.substring(0, 20) : cleaned;
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

    return Scaffold(
      backgroundColor: BloomColors.surface,
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
                style: BloomText.headlineLg,
              ),
              const SizedBox(height: BloomSpace.sm),
              Text(
                'フレンドに表示される名前とアイコンです。あとから変更できます。',
                style: BloomText.bodySm.copyWith(color: BloomColors.secondary),
              ),
              const SizedBox(height: BloomSpace.xl),
              Center(child: _avatarPicker()),
              const SizedBox(height: BloomSpace.xl),
              _label('ユーザー名'),
              const SizedBox(height: BloomSpace.sm),
              TextFormField(
                controller: _username,
                style: BloomText.bodyLg,
                autocorrect: false,
                maxLength: 20,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_.\-]')),
                ],
                decoration: _fieldDecoration('sora'),
                validator: (value) {
                  final v = (value ?? '').trim();
                  if (v.length < 2) return '2文字以上で入力してください';
                  return null;
                },
              ),
              const SizedBox(height: BloomSpace.sm),
              _label('自己紹介'),
              const SizedBox(height: BloomSpace.sm),
              TextFormField(
                controller: _bio,
                style: BloomText.bodyMd,
                maxLines: 3,
                maxLength: 160,
                decoration: _fieldDecoration('静かな写真だけ残す。文章は少なめ。'),
              ),
              if (_error != null) ...[
                const SizedBox(height: BloomSpace.sm),
                Text(
                  _error!,
                  style: BloomText.bodySm.copyWith(color: BloomColors.error),
                ),
              ],
              const SizedBox(height: BloomSpace.lg),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: BloomColors.primaryContainer,
                  foregroundColor: BloomColors.onPrimaryContainer,
                  disabledBackgroundColor: BloomColors.surfaceContainerHigh,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: const StadiumBorder(),
                ),
                child: _saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: BloomColors.onSurface,
                        ),
                      )
                    : Text(
                        isEdit ? '保存する' : 'はじめる',
                        style: BloomText.labelLg.copyWith(
                          color: BloomColors.onPrimaryContainer,
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

  Widget _label(String text) => Text(
        text,
        style: BloomText.labelMd.copyWith(color: BloomColors.onSurfaceVariant),
      );

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: BloomText.bodyMd.copyWith(color: BloomColors.secondary),
        counterStyle: BloomText.labelSm.copyWith(color: BloomColors.secondary),
        filled: true,
        fillColor: BloomColors.surfaceContainerLow,
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
          borderSide:
              const BorderSide(color: BloomColors.primaryContainer, width: 1.5),
        ),
      );

  Widget _avatarPicker() {
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
              color: BloomColors.surfaceContainerLow,
              shape: BoxShape.circle,
              border: Border.all(color: BloomColors.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: picked != null
                ? Image.memory(picked, fit: BoxFit.cover)
                : existing != null
                    ? RemoteImage(api: widget.api, path: existing)
                    : const Icon(
                        Icons.add_a_photo_outlined,
                        color: BloomColors.secondary,
                        size: 28,
                      ),
          ),
        ),
        const SizedBox(height: BloomSpace.sm),
        TextButton(
          onPressed: _pickAvatar,
          child: Text(
            'アイコンを選ぶ',
            style: BloomText.labelMd.copyWith(color: BloomColors.primary),
          ),
        ),
      ],
    );
  }
}
