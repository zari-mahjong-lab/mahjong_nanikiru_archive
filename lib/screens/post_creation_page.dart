// lib/screens/post_creation_page.dart
import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/premium_provider.dart';
import '../services/api_client.dart';
import '../services/purchase_service.dart';
import '../widgets/base_scaffold.dart';
import 'login_selection_page.dart';
import 'post_edit_page.dart';

class PostCreationPage extends StatefulWidget {
  const PostCreationPage({super.key});

  @override
  State<PostCreationPage> createState() => _PostCreationPageState();
}

class _PostCreationPageState extends State<PostCreationPage> {
  File? selectedImage;
  final ImagePicker _picker = ImagePicker();
  final AudioPlayer _player = AudioPlayer();

  bool _loading = false; // 解析中スピナー
  bool _billingBusy = false; // 購入処理中スピナー

  // ★ 共通ローディング画面（メッセージ差し替え可）
  Widget _buildFullPageLoading({String message = 'Now Loading...'}) {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/background.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(
                color: Colors.cyanAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // 購入ストリーム購読の初期化（複数回呼んでも安全）
    PurchaseService.I.init();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  // ====== 効果音 ======
  Future<void> _playSE() async {
    try {
      await _player.play(AssetSource('sounds/cyber_click.mp3'));
    } catch (_) {}
  }

  // ====== 画像選択関連 ======
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

  Future<void> _pickImage(ImageSource source) async {
    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (picked == null) return;

    setState(() {
      selectedImage = File(picked.path);
    });
  }

  Future<void> _goToEditPage() async {
    if (selectedImage == null || _loading) return;

    setState(() => _loading = true);
    try {
      // ApiClient 側で: multipart/form-data + 'file' フィールド + x-api-key を付与
      final result = await ApiClient.analyzeImage(selectedImage!);

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PostEditPage(
            imageFile: selectedImage!,
            tiles: result.tiles,
            // band / boxes を渡す場合は以下を有効化
            // band: result.band,
            // boxes: result.boxes,
          ),
        ),
      );
    } on TimeoutException catch (_) {
      _showError('解析がタイムアウトしました。ネットワーク状況をご確認ください。');
    } on SocketException catch (_) {
      _showError(
        'サーバーに接続できませんでした。Cloud Run の稼働/ネットワーク、'
        'あるいは --dart-define=API_BASE=... の設定をご確認ください。',
      );
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

  // ====== ストア購入/復元 ======
  Future<void> _buyPremium() async {
    if (_billingBusy) return;
    setState(() => _billingBusy = true);
    try {
      await PurchaseService.I.buyPremium();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('購入処理を開始しました。')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('購入に失敗: $e')));
    } finally {
      if (mounted) setState(() => _billingBusy = false);
    }
  }

  Future<void> _restore() async {
    if (_billingBusy) return;
    setState(() => _billingBusy = true);
    try {
      await PurchaseService.I.restore();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('購入情報を復元しました。')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('復元に失敗: $e')));
    } finally {
      if (mounted) setState(() => _billingBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final premiumProvider = context.watch<PremiumProvider>();

    // 未ログイン：ログイン誘導
    if (user == null) {
      return BaseScaffold(
        title: '投稿作成',
        currentIndex: 1,
        body: Center(
          child: _LoginCallout(
            onTapLogin: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginSelectionPage()),
            ),
          ),
        ),
      );
    }

    final isPremium = premiumProvider.isPremium;

    // ====== 非課金：ペイウォールを表示 ======
    if (!isPremium) {
      return BaseScaffold(
        title: '投稿作成',
        currentIndex: 1,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: _Paywall(
              busy: _billingBusy,
              priceText: PurchaseService.I.formattedPrice(),
              onBuy: _buyPremium,
              onRestore: _restore,
              // デバッグビルドのときだけ強制ON/OFFを有効化
              onDebugOn:
                  kDebugMode ? () => premiumProvider.setDebugPremium(true) : null,
              onDebugOff:
                  kDebugMode ? () => premiumProvider.setDebugPremium(false) : null,
            ),
          ),
        ),
      );
    }

    // ====== プレミアム：本来の投稿作成画面 ======
    final contentPadding = const EdgeInsets.all(24.0);
    return BaseScaffold(
      title: '投稿作成',
      currentIndex: 1,
      // ★ ここで画面全体ローディングを BaseScaffold に任せる
      showLoading: _loading,
      loadingChild: _buildFullPageLoading(message: '画像を解析中...'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: contentPadding,
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.cyan.withValues(alpha: 0.10),
                    // ignore: deprecated_member_use_from_same_package
                    Colors.black.withValues(alpha: 0.50),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: Colors.cyanAccent,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.cyanAccent.withValues(alpha: 0.50),
                    blurRadius: 16,
                    spreadRadius: 2,
                    offset: const Offset(3, 6),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.60),
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
                              Shadow(
                                color: Colors.cyan,
                                blurRadius: 4,
                              ),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ------- 以下、補助ウィジェット -------

class _LoginCallout extends StatelessWidget {
  final VoidCallback onTapLogin;
  const _LoginCallout({required this.onTapLogin});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.30),
        border: Border.all(color: Colors.cyanAccent, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.lock_outline, color: Colors.cyanAccent, size: 40),
          const SizedBox(height: 12),
          const Text(
            '投稿作成はログインとプレミアム登録が必要です',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'ログインとプレミアム登録をすると、画像解析から何切る問題の手牌を作成し、投稿できるようになります。',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onTapLogin,
            icon: const Icon(Icons.login),
            label: const Text('ログイン / 新規登録へ'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
              foregroundColor: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _Paywall extends StatelessWidget {
  final bool busy;
  final String? priceText;
  final VoidCallback onBuy;
  final VoidCallback onRestore;
  // デバッグ用（null の場合は表示しない）
  final VoidCallback? onDebugOn;
  final VoidCallback? onDebugOff;

  const _Paywall({
    required this.busy,
    required this.priceText,
    required this.onBuy,
    required this.onRestore,
    this.onDebugOn,
    this.onDebugOff,
  });

  @override
  Widget build(BuildContext context) {
    final priceLabel = priceText ?? '¥---/月';
    final showDebug = onDebugOn != null && onDebugOff != null;

    return Container(
      constraints: const BoxConstraints(maxWidth: 640),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.30),
        border: Border.all(color: Colors.cyanAccent, width: 1.5),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x8020FFFF),
            blurRadius: 14,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.workspace_premium, color: Colors.cyanAccent, size: 28),
              SizedBox(width: 8),
              Text(
                'プレミアムで投稿作成を解放',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '・画像から牌を自動解析して何切る問題の手牌を作成（手動で修正も可能）\n'
            '・何切る問題の補足情報、投稿者の選択とコメントの記載も可能',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),

          // 購入/復元
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: busy ? null : onBuy,
                  icon: const Icon(Icons.lock_open),
                  label: Text('購入する ($priceLabel)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: Colors.black,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: busy ? null : onRestore,
                icon: const Icon(Icons.refresh, color: Colors.cyanAccent),
                label: const Text('復元'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.cyanAccent,
                  side: const BorderSide(color: Colors.cyanAccent, width: 1.4),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          if (busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: CircularProgressIndicator(),
              ),
            ),

          if (showDebug) ...[
            const Divider(height: 24, color: Colors.cyanAccent),
            const Text(
              'デバッグ（開発/エミュ用）',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : onDebugOn,
                  icon: const Icon(Icons.bolt, color: Colors.greenAccent),
                  label: const Text(
                    'プレミアム有効化（テスト）',
                    style: TextStyle(color: Colors.greenAccent),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.greenAccent),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onDebugOff,
                  icon: const Icon(Icons.block, color: Colors.redAccent),
                  label: const Text(
                    'プレミアム無効化（テスト）',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '※ ストア接続できないエミュレータでも、上記テストボタンで挙動確認できます。',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
