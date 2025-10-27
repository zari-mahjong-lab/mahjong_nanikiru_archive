import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';

import '../widgets/base_scaffold.dart';
import 'post_edit_page.dart';
import '../services/api_client.dart';

class PostCreationPage extends StatefulWidget {
  const PostCreationPage({super.key});

  @override
  State<PostCreationPage> createState() => _PostCreationPageState();
}

class _PostCreationPageState extends State<PostCreationPage> {
  Future<void> _testConnection() async {
    await _playSE(); // SE効果音もつけられる
    try {
      final res = await ApiClient.healthz();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('通信成功'),
          content: Text('サーバ応答: $res'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('通信失敗'),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  File? selectedImage;
  final ImagePicker _picker = ImagePicker();
  final AudioPlayer _player = AudioPlayer();
  bool _loading = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _playSE() async {
    // エラーは無視して良い（音源が無い環境も想定）
    try {
      await _player.play(AssetSource('sounds/cyber_click.mp3'));
    } catch (_) {}
  }

  /// 画像選択 UI（ギャラリー/カメラ）
  Future<void> _showPickSheet() async {
    await _playSE();
    if (!mounted) return;

    final source = await showModalBottomSheet<ImageSource?>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('ギャラリーから選択'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('カメラで撮影'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;
    await _pickImage(source);
  }

  /// 画像読み込み（サイズをある程度圧縮）
  Future<void> _pickImage(ImageSource source) async {
    final XFile? picked = await _picker.pickImage(
      source: source,
      // 画像を軽くしてアップロード高速化（端末負荷軽減）
      imageQuality: 85, // 0-100 (圧縮率). 85くらいがバランス良い
      maxWidth: 1600, // 横長画像の幅上限
      maxHeight: 1600, // 縦長画像の高さ上限
    );
    if (picked == null) return;

    setState(() {
      selectedImage = File(picked.path);
    });
  }

  Future<void> _goToEditPage() async {
    if (selectedImage == null) return;
    if (_loading) return; // 二重起動防止

    setState(() => _loading = true);
    try {
      final result = await ApiClient.analyzeImage(
        selectedImage!,
      ).timeout(const Duration(seconds: 60));

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PostEditPage(
            imageFile: selectedImage!,
            tiles: result.tiles,
            // band / boxes を渡したくなったら以下を追加
            // band: result.band,
            // boxes: result.boxes,
          ),
        ),
      );
    } on TimeoutException catch (_) {
      _showError('解析がタイムアウトしました。ネットワーク状況をご確認ください。');
    } on SocketException catch (_) {
      _showError('サーバーに接続できませんでした。端末とPCが同一ネットワークか、URL設定をご確認ください。');
    } catch (e) {
      _showError('解析エラー: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('エラー'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contentPadding = const EdgeInsets.all(24.0);

    return BaseScaffold(
      title: '投稿作成',
      currentIndex: 1,
      body: SafeArea(
        child: Stack(
          children: [
            IgnorePointer(
              ignoring: _loading, // ローディング中はタップ無効
              child: SingleChildScrollView(
                padding: contentPadding,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.cyan.withOpacity(0.1),
                          Colors.black.withOpacity(0.5),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: Colors.cyanAccent, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.cyanAccent.withOpacity(0.5),
                          blurRadius: 16,
                          spreadRadius: 2,
                          offset: const Offset(3, 6),
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.6),
                          blurRadius: 6,
                          offset: const Offset(-3, -3),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        selectedImage != null
                            ? Image.file(selectedImage!)
                            : const Text(
                                '画像が未選択です',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                  shadows: [
                                    Shadow(color: Colors.cyan, blurRadius: 4),
                                  ],
                                ),
                              ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _showPickSheet,
                          icon: const Icon(Icons.image),
                          label: const Text('画像を選択'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyanAccent,
                            foregroundColor: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: (selectedImage == null || _loading)
                              ? null
                              : _goToEditPage,
                          icon: const Icon(Icons.edit),
                          label: const Text('編集へ'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyanAccent,
                            foregroundColor: Colors.black,
                          ),
                        ),
                        // 🧭 ここに追加 ↓↓↓
                        ElevatedButton.icon(
                          onPressed: _testConnection,
                          icon: const Icon(Icons.wifi_tethering),
                          label: const Text('サーバ疎通テスト'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ローディングオーバーレイ
            if (_loading)
              Container(
                color: Colors.black54,
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}
