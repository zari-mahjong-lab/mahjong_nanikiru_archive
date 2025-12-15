// ... 既存の import はそのまま ...
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:collection/collection.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';

import '../models/post.dart';
import '../widgets/base_scaffold.dart';
import '../utils/tile_matcher.dart'; // extractBottomTiles を含む

// -----------------------------
// 🔷 追加：トップレベル定義
// -----------------------------
enum MeldAction { none, chi, pon, minkan, ankan }

class _MeldGroup {
  /// UIに並べる表示用の牌
  final List<String> displayTiles; // 暗カンは ['0', x, x, '0']、明カンは4枚表示
  /// 解除時に手牌へ戻す実牌3枚（選択したそのまま）
  final List<String> restoreTiles; // 解除で戻すのは必ず3枚
  /// 種別（chi / pon / minkan / ankan）
  final String type;
  const _MeldGroup({
    required this.displayTiles,
    required this.restoreTiles,
    required this.type,
  });
}

class PostEditPage extends StatefulWidget {
  final File imageFile;
  final List<String> tiles; // ← ここで tiles を受け取る

  const PostEditPage({
    Key? key,
    required this.imageFile,
    required this.tiles, // ← これを追加
  }) : super(key: key);

  @override
  State<PostEditPage> createState() => _PostEditPageState();
}

class _PostEditPageState extends State<PostEditPage> {
  // 並び替え
  void _onReorderTiles(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    setState(() {
      final moved = _tiles.removeAt(oldIndex);
      _tiles.insert(newIndex, moved);

      if (_postType == '副露判断') {
        _meldIndices.clear();
        _discardIndex = null;
      }
    });
    _applyDesiredCount();
  }

  // 13/14 自動切替に合わせて null を許容（未設定スロット）
  List<String?> _tiles = [];

  // 🔷 副露関連の状態
  final List<_MeldGroup> _meldGroups = []; // 右側に表示する副露グループ
  int get _meldMinus => _meldGroups.length * 3; // 副露1回ごとに -3 スロット

  bool _isLoading = true;
  String? _error;

  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _answerCommentController =
      TextEditingController();

  // 初期は「牌効率」
  String _postType = '牌効率';
  String _ruleType = '四麻・半荘';

  // 通常系（牌効率/押し引き/リーチ判断/アシスト/その他）
  String? _answerTile;

  // リーチ判断の選択
  bool? _reachChoice;

  // 副露判断：鳴く(true) / スルー(false) / 未選択(null)
  bool? _callChoice;

  // 副露判断専用（インデックスで管理）
  final List<int> _meldIndices = []; // 2枚（順不同）
  int? _discardIndex; // 1枚

  // 圧縮済みの手牌（null を除いた見た目通り）
  List<String> get _hand => _tiles.whereType<String>().toList();

  @override
  void initState() {
    super.initState();

    // 🔹 PostCreationPage から牌配列が渡ってきた場合、それを優先表示
    if (widget.tiles.isNotEmpty) {
      _tiles = List<String?>.from(widget.tiles);
      _applyDesiredCount(seed: _tiles);
      _isLoading = false;
    } else {
      // 🔹 何も渡っていない場合のみローカル再解析を実行
      _processImage();
    }
  }

  // 🔷 牌表示スロットは副露数 * 3 減らす
  int get _desiredCount {
    final base = _postType == '副露判断' ? 13 : 14;
    final v = base - _meldMinus;
    return v < 0 ? 0 : v;
  }

  void _applyDesiredCount({List<String?>? seed}) {
    final current = seed ?? _tiles;
    var next = List<String?>.from(current.take(_desiredCount));
    while (next.length < _desiredCount) {
      next.add(null);
    }
    _tiles = next;

    if (_postType == '副露判断') {
      final handLen = _hand.length;
      _meldIndices.removeWhere((i) => i < 0 || i >= handLen);
      if (_discardIndex != null &&
          (_discardIndex! < 0 || _discardIndex! >= handLen)) {
        _discardIndex = null;
      }
      if (_discardIndex != null && _meldIndices.contains(_discardIndex)) {
        _discardIndex = null;
      }
    }
  }

  Future<void> _processImage() async {
    try {
      final rawBytes = await widget.imageFile.readAsBytes();
      final image = img.decodeImage(rawBytes);
      if (image == null) throw Exception('画像の読み込みに失敗しました');

      final tileImages = extractBottomTiles(image, count: 14);
      final matcher = TileMatcher();
      final results = await Future.wait(tileImages.map(matcher.matchTile));
      final detected = results.whereNotNull().toList();

      setState(() {
        final seed = List<String?>.from(detected);
        _applyDesiredCount(seed: seed);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = '画像処理中にエラーが発生しました: $e';
        _isLoading = false;
      });
    }
  }

  static String tileAsset(String id) => 'assets/tiles/$id.png';

  static const List<String> kAllTileIds = [
    // 萬子
    '1m', '2m', '3m', '4m', '5m', '6m', '7m', '8m', '9m', 'r5m',
    // 筒子
    '1p', '2p', '3p', '4p', '5p', '6p', '7p', '8p', '9p', 'r5p',
    // 索子
    '1s', '2s', '3s', '4s', '5s', '6s', '7s', '8s', '9s', 'r5s',
    // 字牌
    't', 'n', 's', 'p', 'h', 'r', 'c',
  ];

  Future<void> _pickTileAt(int index) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF0B1114),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        const heightFactor = 0.72;
        const crossCount = 8;

        return FractionallySizedBox(
          heightFactor: heightFactor,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 46,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              const Text('牌を選択', style: TextStyle(color: Colors.white)),
              const SizedBox(height: 8),
              const Divider(color: Colors.white12, height: 1),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossCount,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 2 / 3,
                  ),
                  itemCount: kAllTileIds.length,
                  itemBuilder: (context, i) {
                    final id = kAllTileIds[i];
                    return InkWell(
                      onTap: () => Navigator.pop(context, id),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          border: Border.all(color: Colors.white24),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Image.asset(
                            tileAsset(id),
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(
                                id,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (result != null) {
      setState(() {
        _tiles[index] = result;
        if (_postType == '副露判断') {
          _meldIndices.clear();
          _discardIndex = null;
        }
      });
      _applyDesiredCount();
    }
  }

  /// 未ログインなら匿名でログイン
  Future<User> _ensureSignedIn() async {
    final auth = FirebaseAuth.instance;
    User? user = auth.currentUser;
    if (user == null) {
      final cred = await auth.signInAnonymously();
      user = cred.user;
    }
    if (user == null) {
      throw Exception('匿名ログインに失敗しました');
    }
    return user;
  }

  // -----------------------------
  // 🔷 副露ボタン→選択→確定
  // -----------------------------
  Future<void> _startMeld(MeldAction action) async {
    if (action == MeldAction.none) return;

    // ※ ここで返るのは「_tiles のインデックス」
    final pickedTileIndices = await _showMeldPicker(action);
    if (pickedTileIndices == null) return; // キャンセル

    // 選んだ3枚の実牌（id）
    final pickedTiles = pickedTileIndices.map((i) => _tiles[i]!).toList();

    // 妥当性チェック & 表示/復元データ生成
    final group = _buildMeldGroup(action, pickedTiles);
    if (group == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('選択が不正です')));
      return;
    }

    // 手牌から「選択したその3枚“だけ”」をインデックスで削除
    _consumeTilesFromHandByIndices(pickedTileIndices);

    setState(() {
      // 🔸 新しい副露は「左側」に追加
      _meldGroups.insert(0, group);
      _applyDesiredCount(); // -3 が効く（＋スロットも減る）
    });
  }

  // 選択UI（_tiles のインデックスを返す）
  Future<List<int>?> _showMeldPicker(MeldAction action) async {
    // 明カンも3選択に統一
    const need = 3;
    final title = switch (action) {
      MeldAction.chi => 'チーする牌を3枚選択',
      MeldAction.pon => 'ポンする牌を3枚選択',
      MeldAction.minkan => '明カンする牌を3枚選択',
      MeldAction.ankan => '暗カンする牌を3枚選択',
      _ => '',
    };

    // 表示に使う「非null の _tiles インデックス一覧」を作る
    final visibleTileIndices = <int>[];
    for (int i = 0; i < _tiles.length; i++) {
      if (_tiles[i] != null) visibleTileIndices.add(i);
    }

    final selected = <int>{}; // ここに入れるのも _tiles のインデックス

    return showModalBottomSheet<List<int>>(
      context: context,
      useSafeArea: true,
      backgroundColor: const Color(0xFF0B1114),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: List.generate(visibleTileIndices.length, (i) {
                        final tilesIndex = visibleTileIndices[i];
                        final id = _tiles[tilesIndex]!;
                        final on = selected.contains(tilesIndex);
                        return GestureDetector(
                          onTap: () {
                            setSt(() {
                              if (on) {
                                selected.remove(tilesIndex);
                              } else if (selected.length < need) {
                                selected.add(tilesIndex);
                              }
                            });
                          },
                          child: Container(
                            width: 36,
                            height: 54,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: on ? Colors.cyanAccent : Colors.white24,
                                width: on ? 2 : 0.5,
                              ),
                              color: Colors.black26,
                            ),
                            child: Image.asset(
                              tileAsset(id),
                              fit: BoxFit.contain,
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, null),
                          child: const Text('キャンセル'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            if (selected.length == need) {
                              final res = selected.toList()..sort();
                              Navigator.pop(ctx, res); // ← _tiles の index を返す
                            }
                          },
                          child: const Text('確定'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 表示/復元グループを作る（妥当性チェック込み）
  _MeldGroup? _buildMeldGroup(MeldAction a, List<String> tiles) {
    int _num(String id) =>
        int.parse(id.startsWith('r') ? id.substring(1, 2) : id.substring(0, 1));
    String _suit(String id) => id.characters.last;

    // Chi: 同色数字の連続3
    if (a == MeldAction.chi) {
      if (tiles.length != 3) return null;
      final s = _suit(tiles.first);
      if (!tiles.every((t) => _suit(t) == s)) return null;
      final nums = tiles.map(_num).toList()..sort();
      if (!(nums[1] == nums[0] + 1 && nums[2] == nums[1] + 1)) return null;

      final display = tiles.toList()
        ..sort(
          (a, b) => (_suit(a) + _num(a).toString()).compareTo(
            _suit(b) + _num(b).toString(),
          ),
        );
      return _MeldGroup(
        displayTiles: display,
        restoreTiles: tiles,
        type: 'chi',
      );
    }

    // Pon: 同一3
    if (a == MeldAction.pon) {
      if (tiles.length != 3) return null;
      final key = _normalizeId(tiles.first);
      if (!tiles.every((t) => _normalizeId(t) == key)) return null;
      return _MeldGroup(displayTiles: tiles, restoreTiles: tiles, type: 'pon');
    }

    // 明カン: 3枚選択 → 表示は4枚（最後を複製）
    if (a == MeldAction.minkan) {
      if (tiles.length != 3) return null;
      final key = _normalizeId(tiles.first);
      if (!tiles.every((t) => _normalizeId(t) == key)) return null;
      final display = [...tiles]..sort();
      display.add(display.last); // 4枚目を複製して見せる
      return _MeldGroup(
        displayTiles: display,
        restoreTiles: tiles,
        type: 'minkan',
      );
    }

    // 暗カン: 同一3選択 → 表示は [0, x, x, 0]
    if (a == MeldAction.ankan) {
      if (tiles.length != 3) return null;
      final key = _normalizeId(tiles.first);
      if (!tiles.every((t) => _normalizeId(t) == key)) return null;
      final x = tiles.first;
      final display = ['0', x, x, '0'];
      return _MeldGroup(
        displayTiles: display,
        restoreTiles: tiles,
        type: 'ankan',
      );
    }

    return null;
  }

  // r5p → 5p（比較用）
  String _normalizeId(String id) => id.startsWith('r') ? id.substring(1) : id;

  // 🔸「選択した _tiles のインデックス」を“そのまま”削除
  void _consumeTilesFromHandByIndices(List<int> indices) {
    if (indices.isEmpty) return;
    final sorted = [...indices]..sort(); // 小さい順に
    int shift = 0;
    for (final idx in sorted) {
      final real = idx - shift;
      if (real >= 0 && real < _tiles.length) {
        _tiles.removeAt(real);
        shift++;
      }
    }
  }

  // 🔴 右上の丸い赤×で副露解除（上段だけ）
  void _removeMeldAt(int index) {
    if (index < 0 || index >= _meldGroups.length) return;
    final g = _meldGroups[index];
    setState(() {
      _meldGroups.removeAt(index);
      // 解除：実牌3枚を手牌に戻す（末尾に追加）
      _tiles.addAll(g.restoreTiles);
      _applyDesiredCount(); // +3 分スロットが戻る（未設定スロットがあれば埋まる）
    });
  }

  // 🔹 牌姿画像タップで拡大表示
  void _showFullImage() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (ctx) {
        return GestureDetector(
          onTap: () => Navigator.of(ctx).pop(), // どこタップでも閉じる
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(color: Colors.black.withOpacity(0.95)),
              ),
              Center(
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: Image.file(
                    widget.imageFile,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Positioned(
                top: 24,
                right: 16,
                child: Icon(
                  Icons.close,
                  color: Colors.white70,
                  size: 28,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _savePost() async {
    try {
      // 🔸 未設定牌チェック
      final missing = _tiles.indexWhere((e) => e == null);
      if (missing != -1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未設定の牌があります。すべて選択してください。')),
        );
        return;
      }

      // 🔸 共通チェック：切る牌必須（副露判断以外）
      if (_postType != '副露判断' &&
          (_answerTile == null || _answerTile!.isEmpty)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('切る牌を1枚選択してください。')));
        return;
      }

      // 🔸 リーチ判断 → 「する／しない」選択必須
      if (_postType == 'リーチ判断' && _reachChoice == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('「リーチする」または「しない」を選択してください。')),
        );
        return;
      }

      // 🔸 副露判断のバリデーション
      if (_postType == '副露判断') {
        // 鳴く／スルー選択必須
        if (_callChoice == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('「鳴く」または「スルー」を選択してください。')),
          );
          return;
        }

        // 鳴くを選んだ場合は 2 枚 + 切る牌必須
        if (_callChoice == true) {
          if (_meldIndices.length != 2) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('鳴きに使う牌を2枚選択してください。')));
            return;
          }
          if (_discardIndex == null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('切る牌を1枚選択してください。')));
            return;
          }
        }
      }

      setState(() => _isLoading = true);

      // 🔹 Firebase 認証（匿名OK）
      final user = await _ensureSignedIn();

      // 🔹 画像アップロード
      final ref = FirebaseStorage.instance.ref().child(
        'post_images/${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await ref.putFile(widget.imageFile);
      final imageUrl = await ref.getDownloadURL();

      // 🔹 投稿データ構築
      final tilesToSave = _tiles.whereType<String>().toList();

      String? discardTileForSave;
      List<String>? meldTilesForSave;

      if (_postType == '副露判断') {
        if (_callChoice == true &&
            _meldIndices.length == 2 &&
            _discardIndex != null) {
          final hand = _hand;
          final pair = [hand[_meldIndices[0]], hand[_meldIndices[1]]]..sort();
          final cut = hand[_discardIndex!];

          _answerTile = cut;
          discardTileForSave = cut;
          meldTilesForSave = pair;
        }
      }

      final post = Post(
        imageUrl: imageUrl,
        description: _descriptionController.text,
        postType: _postType,
        tiles: tilesToSave,
        createdAt: Timestamp.now(),
        userId: user.uid,
        userName: user.displayName ?? '匿名',
        ruleType: _ruleType,
        answerTile: _answerTile,
        answerComment: _answerCommentController.text.trim(),
      );

      // 🔹 副露グループの Firestore 保存用整形
      final meldGroupsForSave = _meldGroups
          .map(
            (g) => {
              'type': g.type,
              'displayTiles': g.displayTiles,
              'restoreTiles': g.restoreTiles,
            },
          )
          .toList();

      final extra = <String, dynamic>{
        if (_postType == 'リーチ判断') 'reach': _reachChoice,
        if (_postType == '副露判断') 'call': _callChoice,
        if (meldTilesForSave != null) 'callTiles': meldTilesForSave,
        if (discardTileForSave != null) 'callDiscard': discardTileForSave,
        'meldGroups': meldGroupsForSave,
      };

      final data = <String, dynamic>{...post.toMap(), ...extra};

      // 🔹 Firestore 書き込み
      final postsCol = FirebaseFirestore.instance.collection('posts');
      final newDoc = await postsCol.add(data);
      final postId = newDoc.id;

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'myPosts': FieldValue.arrayUnion([postId]),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('投稿を保存しました')));
        Navigator.pop(context);
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        final mess = (e.code == 'unauthorized')
            ? '保存権限がありません（Storage ルール / 認証設定を確認してください）'
            : e.message ?? e.code;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('投稿保存エラー: $mess')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('投稿保存エラー: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: '投稿編集',
      currentIndex: 1,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child:
                        Text(_error!, style: const TextStyle(color: Colors.red)),
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 🔹 牌姿画像タップで拡大
                        GestureDetector(
                          onTap: _showFullImage,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              widget.imageFile,
                              width: double.infinity,
                              fit: BoxFit.fitWidth,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        _buildLabel('ルール'),
                        Wrap(
                          spacing: 16,
                          children: [
                            '四麻・半荘',
                            '四麻・東風',
                            '三麻',
                          ].map((label) => _buildRuleRadio(label)).toList(),
                        ),
                        const SizedBox(height: 24),

                        _buildLabel('問題タイプ'),
                        Wrap(
                          spacing: 16,
                          children: [
                            '牌効率',
                            '押し引き',
                            'リーチ判断',
                            '副露判断',
                            'アシスト',
                            'その他',
                          ].map((label) => _buildRadio(label)).toList(),
                        ),
                        const SizedBox(height: 16),

                        _buildLabel('問題の補足'),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _descriptionController,
                          maxLength: 200, // 🔹 200文字制限
                          maxLines: 4, // 🔴 ここを 3 → 4 に変更
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration(
                            '例：ラス回避ルール、1-3 チップ5000点相当、一発裏無し など（200文字以内）',
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ====== 手牌編集 + 副露ボタン ======
                        _buildLabel('牌を確認・修正してください'),
                        const SizedBox(height: 8),

                        // 副露ボタン（ラベルの直下）
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _meldBtn('チー', () => _startMeld(MeldAction.chi)),
                            _meldBtn('ポン', () => _startMeld(MeldAction.pon)),
                            _meldBtn(
                                '明カン', () => _startMeld(MeldAction.minkan)),
                            _meldBtn('暗カン', () => _startMeld(MeldAction.ankan)),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // 左：手牌編集　右：副露表示（解除ボタンあり）
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end, // ★底辺揃え
                          children: [
                            Expanded(
                              child: _HandStripEditor(
                                tiles: _tiles,
                                onPickAt: _pickTileAt,
                                onReorder: _onReorderTiles,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _MeldDisplayColumn(
                              groups: _meldGroups,
                              showRemove: true, // ← 上段は解除可能
                              onRemove: _removeMeldAt,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // ====== /手牌編集 ======

                        // リーチ判断のときだけ「する/しない」
                        if (_postType == 'リーチ判断') ...[
                          _buildLabel('リーチする？'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            children: [
                              ChoiceChip(
                                selected: _reachChoice == true,
                                label: const Text('する'),
                                onSelected: (_) =>
                                    setState(() => _reachChoice = true),
                                selectedColor:
                                    Colors.cyanAccent.withOpacity(0.25),
                                labelStyle: TextStyle(
                                  color: _reachChoice == true
                                      ? Colors.cyanAccent
                                      : Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              ChoiceChip(
                                selected: _reachChoice == false,
                                label: const Text('しない'),
                                onSelected: (_) =>
                                    setState(() => _reachChoice = false),
                                selectedColor:
                                    Colors.cyanAccent.withOpacity(0.25),
                                labelStyle: TextStyle(
                                  color: _reachChoice == false
                                      ? Colors.cyanAccent
                                      : Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],

                        // 副露判断 UI（既存）
                        if (_postType == '副露判断') ...[
                          _buildLabel('鳴く？'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            children: [
                              ChoiceChip(
                                selected: _callChoice == true,
                                label: const Text('鳴く'),
                                onSelected: (_) => setState(() {
                                  _callChoice = true;
                                }),
                                selectedColor:
                                    Colors.cyanAccent.withOpacity(0.25),
                                labelStyle: TextStyle(
                                  color: _callChoice == true
                                      ? Colors.cyanAccent
                                      : Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              ChoiceChip(
                                selected: _callChoice == false,
                                label: const Text('スルー'),
                                onSelected: (_) => setState(() {
                                  _callChoice = false;
                                  _meldIndices.clear();
                                  _discardIndex = null;
                                }),
                                selectedColor:
                                    Colors.cyanAccent.withOpacity(0.25),
                                labelStyle: TextStyle(
                                  color: _callChoice == false
                                      ? Colors.cyanAccent
                                      : Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          if (_callChoice == true) ...[
                            _buildLabel('鳴きに使う牌を2枚選んでください'),
                            const SizedBox(height: 8),
                            _MeldPickerRowCheckMark(
                              // ← チェックマーク表示（下端そろえ）
                              tiles: _hand,
                              selectedIndices: _meldIndices,
                              onToggle: (i) {
                                setState(() {
                                  if (_meldIndices.contains(i)) {
                                    _meldIndices.remove(i);
                                  } else if (_meldIndices.length < 2) {
                                    _meldIndices.add(i);
                                  }
                                  if (_discardIndex != null &&
                                      _meldIndices.contains(_discardIndex)) {
                                    _discardIndex = null;
                                  }
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                            _buildLabel('切る牌を1枚選んでください'),
                            const SizedBox(height: 8),

                            // 左：選択列　右：副露表示（解除ボタンなし）
                            Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.end, // ★底辺揃え
                              children: [
                                Expanded(
                                  child: _AnswerTileSelectorRowIndexed(
                                    tiles: _hand,
                                    disabled: _meldIndices.toSet(),
                                    selectedIndex: _discardIndex,
                                    onSelectedIndex: (i) =>
                                        setState(() => _discardIndex = i),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _MeldDisplayColumn(
                                  groups: _meldGroups,
                                  showRemove: false, // ← 下段は解除表示なし
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                          ],
                        ],

                        // 通常系の「あなたが切った牌」
                        if (_postType != '副露判断') ...[
                          _buildLabel('切る牌を1枚選んでください'),
                          const SizedBox(height: 8),

                          // 左：選択列　右：副露表示（解除ボタンなし）
                          Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.end, // ★底辺揃え
                            children: [
                              Expanded(
                                child: _AnswerTileSelectorRow(
                                  tiles: _hand,
                                  selected: _answerTile,
                                  onSelected: (id) =>
                                      setState(() => _answerTile = id),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _MeldDisplayColumn(
                                groups: _meldGroups,
                                showRemove: false,
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),
                        ],

                        _buildLabel('コメント（理由など）'),
                        TextField(
                          controller: _answerCommentController,
                          maxLength: 200, // 🔹 200文字制限を追加
                          maxLines: 2,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration(
                            '例：受け入れ枚数では劣るが打点差が大きく、局収支期待値では勝ると判断した など（200文字以内）',
                          ),
                        ),

                        const SizedBox(height: 32),
                        Center(
                          child: ElevatedButton.icon(
                            onPressed: _savePost,
                            icon: const Icon(Icons.save),
                            label: const Text('投稿内容を保存する'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyanAccent,
                              foregroundColor: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _meldBtn(String text, VoidCallback onTap) => ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1A2530),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(text),
      );

  Widget _buildLabel(String text) =>
      Text(text, style: const TextStyle(fontSize: 16, color: Colors.white));

  Widget _buildRadio(String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Radio<String>(
          value: label,
          groupValue: _postType,
          activeColor: Colors.cyanAccent,
          onChanged: (value) {
            setState(() {
              _postType = value!;
              _applyDesiredCount();
              if (_postType != 'リーチ判断') _reachChoice = null;

              if (_postType != '副露判断') {
                _callChoice = null;
                _meldIndices.clear();
                _discardIndex = null;
              }

              if (_answerTile != null && !_hand.contains(_answerTile)) {
                _answerTile = null;
              }
            });
          },
        ),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    );
  }

  Widget _buildRuleRadio(String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Radio<String>(
          value: label,
          groupValue: _ruleType,
          activeColor: Colors.cyanAccent,
          onChanged: (value) => setState(() => _ruleType = value!),
        ),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: Colors.black87,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.cyanAccent),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.cyanAccent),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.cyan),
      ),
    );
  }
}

/// =====================
/// 編集帯：横幅いっぱいに等幅で詰める（タップ＝選択 / 触ってドラッグ）
/// =====================
class _HandStripEditor extends StatelessWidget {
  final List<String?> tiles;
  final Future<void> Function(int index) onPickAt;
  final void Function(int oldIndex, int newIndex) onReorder;

  const _HandStripEditor({
    required this.tiles,
    required this.onPickAt,
    required this.onReorder,
  });

  static String _asset(String id) => 'assets/tiles/$id.png';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final count = tiles.isEmpty ? 1 : tiles.length;
        final tileW = c.maxWidth / count;
        final tileH = tileW * 3 / 2;

        return SizedBox(
          width: c.maxWidth,
          height: tileH,
          child: ReorderableListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: tiles.length,
            onReorder: onReorder,
            buildDefaultDragHandles: false,
            physics: const NeverScrollableScrollPhysics(),
            primary: false,
            dragStartBehavior: DragStartBehavior.down,
            itemBuilder: (context, i) {
              final id = tiles[i];
              final key = ValueKey('tile_${i}_${id ?? "empty"}');

              final tileView = AspectRatio(
                aspectRatio: 2 / 3,
                child: id == null
                    ? const _EmptySlot()
                    : Image.asset(
                        _asset(id),
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) => Center(
                          child: Text(
                            id,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
              );

              return SizedBox(
                key: key,
                width: tileW,
                child: ReorderableDragStartListener(
                  index: i,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onPickAt(i),
                    child: tileView,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(Icons.add, color: Colors.cyanAccent.withOpacity(0.9)),
    );
  }
}

/// =====================
/// 右側の副露表示（横並び・下寄せ・丸ボタンのヒット範囲一致）
/// =====================
class _MeldDisplayColumn extends StatelessWidget {
  final List<_MeldGroup> groups;
  final bool showRemove; // 上段は true、下段は false
  final void Function(int index)? onRemove;

  const _MeldDisplayColumn({
    required this.groups,
    required this.showRemove,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) return const SizedBox.shrink();

    // 牌サイズ（必要ならここで微調整）
    const double tileW = 18;
    const double tileH = 27;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end, // 🔹列全体を下寄せに揃える
        children: List.generate(groups.length, (gi) {
          final g = groups[gi];

          // グループを下寄せで横並び表示
          final tilesRow = Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end, // 🔹更に下寄せ
            children: g.displayTiles.map((id) {
              return SizedBox(
                width: tileW,
                height: tileH,
                child: Align(
                  // 🔹画像自体も下に吸着
                  alignment: Alignment.bottomCenter,
                  child: Image.asset(
                    'assets/tiles/$id.png',
                    fit: BoxFit.contain,
                  ),
                ),
              );
            }).toList(),
          );

          return Padding(
            padding: EdgeInsets.only(right: gi == groups.length - 1 ? 0 : 6),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomRight, // 🔹基準点を右下に（見た目どおり）
              children: [
                tilesRow,

                // 🔴 副露解除ボタン（右上寄り・当たり判定は丸と一致）
                if (showRemove)
                  Positioned(
                    right: 2.0, // 少し内側へ
                    top: -tileH * 0.30, // 行の右上
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        customBorder: const CircleBorder(), // 🔥丸と同じヒット領域
                        onTap: () => onRemove?.call(gi),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black54,
                                blurRadius: 4,
                                offset: Offset(1, 1),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.close,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// =====================
/// あなたが切った牌（通常系）
/// =====================
class _AnswerTileSelectorRow extends StatelessWidget {
  final List<String> tiles;
  final String? selected;
  final ValueChanged<String> onSelected;

  const _AnswerTileSelectorRow({
    required this.tiles,
    required this.selected,
    required this.onSelected,
  });

  static String _asset(String id) => 'assets/tiles/$id.png';

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end, // 下端そろえ
      children: tiles.map((tileId) {
        final isSelected = selected == tileId;
        return Expanded(
          child: GestureDetector(
            onTap: () => onSelected(tileId),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected ? Colors.cyanAccent : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Image.asset(
                    _asset(tileId),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Center(
                      child: Text(
                        tileId,
                        style: TextStyle(
                          color: isSelected ? Colors.cyanAccent : Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// =====================
/// 副露判断：鳴き2枚（チェックマーク表示・下端そろえ）
/// =====================
class _MeldPickerRowCheckMark extends StatelessWidget {
  final List<String> tiles; // 圧縮済み手牌
  final List<int> selectedIndices;
  final ValueChanged<int> onToggle;

  const _MeldPickerRowCheckMark({
    required this.tiles,
    required this.selectedIndices,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end, // 下寄せ
      children: List.generate(tiles.length, (i) {
        final id = tiles[i];
        final isSelected = selectedIndices.contains(i);

        return Expanded(
          child: GestureDetector(
            onTap: () => onToggle(i),
            child: Stack(
              alignment: Alignment.topRight,
              children: [
                AspectRatio(
                  aspectRatio: 2 / 3,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Image.asset(
                      'assets/tiles/$id.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Center(
                        child: Text(
                          id,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
                if (isSelected)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withOpacity(0.9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 14,
                        color: Colors.black,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// =====================
/// 副露判断：切る牌（インデックス指定・無効マスク・水色アンダーライン付き）
/// =====================
class _AnswerTileSelectorRowIndexed extends StatelessWidget {
  final List<String> tiles; // 圧縮済み手牌
  final Set<int> disabled; // 鳴きに使った index を無効化
  final int? selectedIndex;
  final ValueChanged<int> onSelectedIndex;

  const _AnswerTileSelectorRowIndexed({
    required this.tiles,
    required this.disabled,
    required this.selectedIndex,
    required this.onSelectedIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end, // 下端そろえ
      children: List.generate(tiles.length, (i) {
        final id = tiles[i];
        final isDisabled = disabled.contains(i);
        final isSelected = selectedIndex == i;

        return Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: isDisabled ? null : () => onSelectedIndex(i),
            child: Opacity(
              opacity: isDisabled ? 0.35 : 1.0,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isSelected
                          ? Colors.cyanAccent
                          : Colors.transparent,
                      width: 3, // 🔹 水色アンダーライン
                    ),
                  ),
                ),
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDisabled
                              ? Colors.white24
                              : Colors.transparent,
                          width: 0.5,
                        ),
                      ),
                      child: Image.asset(
                        'assets/tiles/$id.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Center(
                          child: Text(
                            id,
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.cyanAccent
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
