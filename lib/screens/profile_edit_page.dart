import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // 追加：Web判定
import '../screens/my_page.dart';
import '../widgets/base_scaffold.dart';

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({Key? key}) : super(key: key);

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  File? selectedImage;
  String? uploadedImageUrl; // 既存のURL（Firestore or Auth）
  final AudioPlayer _player = AudioPlayer();
  final TextEditingController _nameController = TextEditingController();
  bool _saving = false;

  /// 所属/最高ランクの選択肢（初期1行）
  List<Map<String, String>> rankSelections = [
    {'affiliation': '未選択', 'rank': '未選択'},
  ];

  final List<String> affiliationOptions = const [
    '未選択', '雀魂', '天鳳', '日本プロ麻雀連盟', '最高位戦日本プロ麻雀協会',
    'Mリーグ', '日本プロ麻雀協会', '麻将連合', 'RMU'
  ];

  final Map<String, List<String>> rankMap = const {
    '未選択': ['未選択'],
    '天鳳': ['未選択', '天鳳位', '十段', '九段', '八段', '七段', '六段', '五段', '四段', '三段', '二段', '初段'],
    '雀魂': [
      '未選択',
      '魂天20','魂天19','魂天18','魂天17','魂天16','魂天15','魂天14','魂天13','魂天12','魂天11','魂天10',
      '魂天9','魂天8','魂天7','魂天6','魂天5','魂天4','魂天3','魂天2','魂天1',
      '雀聖3','雀聖2','雀聖1','雀豪3','雀豪2','雀豪1','雀傑3','雀傑2','雀傑1','雀士3','雀士2','雀士1','初心3','初心2','初心1'
    ],
    '日本プロ麻雀連盟': ['未選択','A1リーグ','A2リーグ','B1リーグ','B2リーグ','C1リーグ','C2リーグ','C3リーグ','D1リーグ','D2リーグ','D3リーグ','E1リーグ','E2リーグ','E3リーグ'],
    '最高位戦日本プロ麻雀協会': ['未選択','A1リーグ','A2リーグ','B1リーグ','B2リーグ','C1リーグ','C2リーグ','C3リーグ','D1リーグ','D2リーグ','D3リーグ'],
    '日本プロ麻雀協会': ['未選択','A1リーグ','A2リーグ','B1リーグ','B2リーグ','C1リーグ','C2リーグ','C3リーグ','D1リーグ','D2リーグ','D3リーグ','E1リーグ','E2リーグ','E3リーグ','F1リーグ'],
    '麻将連合': ['未選択','μリーグ','μ2リーグ'],
    'RMU': ['未選択','A1リーグ','A2リーグ','B1リーグ','B2リーグ','C1リーグ','C2リーグ','C3リーグ','D1リーグ','D2リーグ','D3リーグ']
  };

  @override
  void initState() {
    super.initState();
    _loadCurrentUserProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // 効果音の安全再生（失敗は握りつぶす）
  Future<void> _safeClick() async {
    try {
      if (kIsWeb) return; // Webはスキップ
      await _player.play(AssetSource('sounds/cyber_click.mp3'));
    } catch (e) {
      debugPrint('click sound skipped: $e');
    }
  }

  Future<void> _loadCurrentUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _nameController.text = user.displayName ?? '';

    final doc =
        await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (!doc.exists) {
      setState(() => uploadedImageUrl = user.photoURL);
      return;
    }

    final data = doc.data()!;
    setState(() {
      uploadedImageUrl = (data['iconUrl'] as String?) ?? user.photoURL;
      final raw = (data['affiliations'] as List?) ?? const [];
      rankSelections = raw
          .whereType<Map>()
          .map((m) => {
                'affiliation': (m['affiliation'] ?? '未選択').toString(),
                'rank': (m['rank'] ?? '未選択').toString(),
              })
          .toList();
      if (rankSelections.isEmpty) {
        rankSelections = [
          {'affiliation': '未選択', 'rank': '未選択'}
        ];
      }
    });
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => selectedImage = File(picked.path));
    }
  }

  Future<String?> _uploadImage(File imageFile) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final ref = FirebaseStorage.instance.ref().child('users/$uid/icon.jpg');
    await ref.putFile(imageFile);
    return await ref.getDownloadURL();
  }

  Future<void> _saveProfile() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      await _safeClick(); // 効果音は try の中で

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw '未ログインです。';

      // 画像アップロード
      String? iconUrl = uploadedImageUrl;
      if (selectedImage != null) {
        iconUrl = await _uploadImage(selectedImage!);
      }

      // Firestore 保存（マージ）
      final payload = {
        'nickname': _nameController.text.trim(),
        'iconUrl': iconUrl ?? '',
        'affiliations': rankSelections
            .map((e) => {
                  'affiliation': e['affiliation'] ?? '未選択',
                  'rank': e['rank'] ?? '未選択',
                })
            .toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(payload, SetOptions(merge: true));

      // Auth プロフィールも同期
      await user.updateDisplayName(_nameController.text.trim());
      if ((iconUrl ?? '').isNotEmpty) {
        await user.updatePhotoURL(iconUrl);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('プロフィールを保存しました')),
      );

      // ★ スタックを全消去して MyPage だけにする（戻る矢印が出ない）
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => MyPage()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存に失敗しました: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: 'プロフィール編集',
      currentIndex: 2,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: CircleAvatar(
                radius: 48,
                backgroundColor: Colors.cyanAccent,
                backgroundImage: selectedImage != null
                    ? FileImage(selectedImage!)
                    : (uploadedImageUrl != null
                        ? NetworkImage(uploadedImageUrl!)
                        : null) as ImageProvider<Object>?,
                child: selectedImage == null && uploadedImageUrl == null
                    ? const Icon(Icons.person, size: 48, color: Colors.black)
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'ニックネーム',
                labelStyle: const TextStyle(color: Colors.cyanAccent),
                filled: true,
                fillColor: Colors.black87,
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.cyanAccent),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.cyan),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 所属/最高ランク（最大3件、2件以上あれば削除可）
            ...List.generate(rankSelections.length, (index) {
              final aff = rankSelections[index]['affiliation'] ?? '未選択';
              final rank = rankSelections[index]['rank'] ?? '未選択';
              final rankOptions = rankMap[aff] ?? const ['未選択'];
              final canRemove = rankSelections.length > 1;

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: aff,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: '所属',
                          labelStyle: const TextStyle(color: Colors.cyanAccent),
                          filled: true,
                          fillColor: Colors.black87,
                          enabledBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: Colors.cyanAccent),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        dropdownColor: Colors.black87,
                        style: const TextStyle(color: Colors.white),
                        items: affiliationOptions.map((a) {
                          return DropdownMenuItem<String>(
                            value: a,
                            child: Text(a, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            rankSelections[index]['affiliation'] = value;
                            final validRanks = rankMap[value] ?? const ['未選択'];
                            if (!validRanks.contains(rankSelections[index]['rank'])) {
                              rankSelections[index]['rank'] = '未選択';
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: rank,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: '最高ランク',
                          labelStyle: const TextStyle(color: Colors.cyanAccent),
                          filled: true,
                          fillColor: Colors.black87,
                          enabledBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: Colors.cyanAccent),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        dropdownColor: Colors.black87,
                        style: const TextStyle(color: Colors.white),
                        items: rankOptions.map((r) {
                          return DropdownMenuItem<String>(
                            value: r,
                            child: Text(r, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => rankSelections[index]['rank'] = value);
                          }
                        },
                      ),
                    ),

                    if (canRemove) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'この行を削除',
                        onPressed: () async {
                          await _safeClick();
                          setState(() {
                            if (rankSelections.length > 1) {
                              rankSelections.removeAt(index);
                            }
                          });
                        },
                        icon: const Icon(Icons.delete_outline, color: Colors.cyanAccent),
                      ),
                    ],
                  ],
                ),
              );
            }),

            // 追加ボタン（最大3件）
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (rankSelections.length < 3)
                  TextButton.icon(
                    onPressed: () async {
                      await _safeClick();
                      setState(() {
                        rankSelections.add({'affiliation': '未選択', 'rank': '未選択'});
                      });
                    },
                    icon: const Icon(Icons.add, color: Colors.cyanAccent),
                    label: const Text('追加', style: TextStyle(color: Colors.cyanAccent)),
                  ),
              ],
            ),

            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _saving ? null : _saveProfile,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.save),
              label: Text(_saving ? '保存中...' : '保存する'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
