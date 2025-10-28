import 'dart:math' as math;
import 'dart:async'; // ← StreamSubscription 用
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ← 3投稿ごとの広告カウント用

import '../widgets/base_scaffold.dart';

// ===== Mini profile (トップレベル) =====
class _MiniProfile {
  final String? nickname;
  final List<Map<String, dynamic>>? affiliations;

  _MiniProfile({this.nickname, this.affiliations});

  factory _MiniProfile.fromMap(Map<String, dynamic> map) => _MiniProfile(
    nickname: map['nickname'] as String?,
    affiliations: map['affiliations'] == null
        ? null
        : List<Map<String, dynamic>>.from(
            (map['affiliations'] as List).map(
              (e) => Map<String, dynamic>.from(e as Map),
            ),
          ),
  );
}

class DetailPage extends StatefulWidget {
  final String postId;
  final String source;
  final int currentIndex;

  // ホームで使ったソート/フィルタ/検索の状態（必要なら）
  final Map<String, dynamic>? navContext;

  // ★ 追加: ホーム側で「今画面に見えている投稿IDの並び」と、その中のインデックス
  final List<String>? navIds;
  final int? navIndex;

  const DetailPage({
    super.key,
    required this.postId,
    this.source = 'unknown',
    this.currentIndex = 0,
    this.navContext,
    this.navIds, // ★ 追加
    this.navIndex, // ★ 追加
  });

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  // === 既存 ===
  final ValueNotifier<String?> _selectedTile = ValueNotifier<String?>(null);
  final ValueNotifier<bool> _showResults = ValueNotifier<bool>(false);
  final TextEditingController commentController = TextEditingController();
  final AudioPlayer _player = AudioPlayer();

  // タイプ別回答UI用
  final ValueNotifier<bool?> _reach = ValueNotifier<bool?>(null);
  final ValueNotifier<bool?> _call = ValueNotifier<bool?>(null);
  final ValueNotifier<Set<String>> _selectedCallTiles =
      ValueNotifier<Set<String>>(<String>{});

  // ===== 回答コメントのソート・フィルタ状態 =====
  String _commentSortKey = '投稿順'; // or 'お気に入り数順'
  bool _commentAscending = false; // false=降順
  String _commentNicknameQuery = '';
  String _commentSelectedLeague = '未選択';
  String _commentSelectedRank = '未選択';

  // ===== サブスク状態（簡易：ユーザーDocの isPremium/bool を参照。なければ false）=====
  bool _isPremium = false;
  Future<void> _loadPremiumFlag() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isPremium = false);
      return;
    }
    try {
      final s = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final m = s.data() ?? const {};
      final v = (m['isPremium'] ?? false) as bool;
      if (mounted) setState(() => _isPremium = v);
    } catch (_) {
      if (mounted) setState(() => _isPremium = false);
    }
  }

  // ===== 初期ローディング制御用（Firestore + 画像） =====
  bool _postLoaded = false; // posts/{postId} の取得が完了したら true
  bool _imageFinished = false; // 牌姿画像の表示まで完了したら true
  bool get _showInitialLoading => !_postLoaded || !_imageFinished;

  // ===== 「みんなの回答を見る」→ 3投稿ごとにアップセル =====
  static const _kViewedSetKey = 'detail_unique_posts_seen';
  Future<void> _maybeUpsellEvery3UniquePosts() async {
    if (_isPremium) return; // 課金済はスキップ
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kViewedSetKey) ?? <String>[];
    if (!list.contains(widget.postId)) {
      list.add(widget.postId);
      await prefs.setStringList(_kViewedSetKey, list);
      if (list.length % 3 == 0) {
        if (!mounted) return;
        await showModalBottomSheet<void>(
          context: context,
          backgroundColor: const Color(0xFF0B1114),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (_) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.workspace_premium,
                  color: Colors.cyanAccent,
                  size: 28,
                ),
                const SizedBox(height: 10),
                const Text(
                  '広告の代わりにサブスクで快適に！',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'サブスク登録すると回答入力・詳細操作が解放され、広告も非表示になります。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.cyanAccent),
                          foregroundColor: Colors.cyanAccent,
                        ),
                        child: const Text('あとで'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          // 購入ページがある場合はここで遷移を実装してください
                          // Navigator.of(context).pushNamed('/purchase');
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('マイページから購読設定が可能です')),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                          foregroundColor: Colors.black,
                        ),
                        child: const Text('サブスクを見る'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }
    }
  }

  Future<void> _playSE() async {
    await _player.play(AssetSource('sounds/cyber_click.mp3'));
  }

  void _resetCommentFilters() {
    setState(() {
      _commentSortKey = '投稿順';
      _commentAscending = false;
      _commentNicknameQuery = '';
      _commentSelectedLeague = '未選択';
      _commentSelectedRank = '未選択';
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('表示設定をリセットしました')));
  }

  // ★ HomePage / MyPage と同じテイストの「ページ全体ローディング」
  Widget _buildFullPageLoading() {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/background.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
            ),
            SizedBox(height: 16),
            Text('Now Loading...', style: TextStyle(color: Colors.cyanAccent)),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadPremiumFlag();

    // ★ ホーム側から navIds/navIndex が渡されていれば、それをそのまま使う
    if (widget.navIds != null && widget.navIds!.isNotEmpty) {
      _navIds = List<String>.from(widget.navIds!);
      _navIndex =
          widget.navIndex ??
          widget.navIds!.indexOf(widget.postId); // 念のため postId から再計算
    } else {
      // ★ ブックマーク／直接リンク等、navIds がない場合だけ従来のロジックで並び構築
      _buildNavOrder();
    }
  }

  @override
  void dispose() {
    _selectedTile.dispose();
    _showResults.dispose();
    commentController.dispose();
    _player.dispose();
    _reach.dispose();
    _call.dispose();
    _selectedCallTiles.dispose();
    super.dispose();
  }

  /// users/{uid} を1回だけ読んで、ニックネームと所属(複数)を組み立てて返す
  Future<({String nickname, String affiliationsText})> _loadPosterMeta(
    String uid,
  ) async {
    if (uid.isEmpty) {
      return (nickname: '（未設定）', affiliationsText: '（所属未設定）');
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final Map<String, dynamic> data = snap.data() ?? <String, dynamic>{};

      final nickname = (data['nickname'] as String?)?.trim();
      final rawAffs = (data['affiliations'] as List?) ?? const [];

      // affiliations は [{affiliation: 〇〇, rank: △△}, ...] を想定
      final parts = <String>[];
      for (final e in rawAffs) {
        if (e is Map<String, dynamic>) {
          final aff = (e['affiliation'] ?? '').toString().trim();
          final rank = (e['rank'] ?? '').toString().trim();
          if (aff.isEmpty && rank.isEmpty) continue;
          parts.add(rank.isEmpty ? aff : '$aff($rank)');
        } else if (e is String) {
          final s = e.trim();
          if (s.isNotEmpty) parts.add(s);
        }
      }

      return (
        nickname: nickname?.isNotEmpty == true ? nickname! : '（未設定）',
        affiliationsText: parts.isEmpty ? '（所属未設定）' : parts.join('・'),
      );
    } catch (_) {
      return (nickname: '（未設定）', affiliationsText: '（所属未設定）');
    }
  }

  // 回答送信（課金ユーザーのみボタン表示。実装は従来どおり）
  Future<void> _submitAnswer({required String postType}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('回答を保存するにはログインが必要です')));
      return;
    }
    if (!_isPremium) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('回答はサブスク登録で利用できます')));
      return;
    }

    // --- バリデーション ---
    final bool requireTile = postType != '副露判断';
    final tile = _selectedTile.value ?? '';

    if (requireTile && tile.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('牌を選択してください')));
      return;
    }

    if (postType == 'リーチ判断' && _reach.value == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('「する／しない」を選択してください')));
      return;
    }

    if (postType == '副露判断') {
      if (_call.value == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('鳴く／スルーを選択してください')));
        return;
      }
      if (_call.value == true) {
        if (_selectedCallTiles.value.length != 2) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('鳴く場合は副露に使う2枚を選んでください')));
          return;
        }
        if (tile.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('鳴く場合は打牌も選んでください')));
          return;
        }
      }
    }

    await _playSE();

    final answersRef = FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .collection('answers')
        .doc(uid);

    final now = FieldValue.serverTimestamp();

    List<String> callTilesToSave = <String>[];
    if (postType == '副露判断' && _call.value == true) {
      callTilesToSave = _selectedCallTiles.value.toList()..sort();
    }
    final baseData = <String, dynamic>{
      'tile': tile,
      'comment': commentController.text.trim(),
      'userId': uid,
      'reach': postType == 'リーチ判断' ? _reach.value : null,
      'call': postType == '副露判断' ? _call.value : null,
      'callTiles': postType == '副露判断' ? callTilesToSave : <String>[],
    };

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(answersRef);

      if (snap.exists) {
        final createdAt = snap.data()?['createdAt'];
        tx.set(answersRef, {
          ...baseData,
          'createdAt': createdAt,
          'updatedAt': now,
        }, SetOptions(merge: true));
      } else {
        tx.set(answersRef, {
          ...baseData,
          'createdAt': now,
          'updatedAt': now,
        }, SetOptions(merge: false));
      }
    });

    _showResults.value = true;
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('回答しました')));
  }

  // 画像のポップアップ（ページ遷移しない）
  Future<void> _openImagePopup(String url) async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '閉じる',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, anim, secondary) {
        final size = MediaQuery.of(context).size;
        return Center(
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  Container(
                    color: Colors.black,
                    constraints: BoxConstraints(
                      maxWidth: size.width * 0.95,
                      maxHeight: size.height * 0.85,
                    ),
                    child: InteractiveViewer(
                      maxScale: 5,
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim, _, child) => ScaleTransition(
        scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
        child: child,
      ),
    );
  }

  Future<void> _openCommentSortSheet() async {
    final result = await showModalBottomSheet<_CommentSortResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B1114),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _CommentSortSheet(
        sortKey: _commentSortKey,
        ascending: _commentAscending,
        nicknameQuery: _commentNicknameQuery,
        selectedLeague: _commentSelectedLeague,
        selectedRank: _commentSelectedRank,
      ),
    );
    if (result != null) {
      setState(() {
        _commentSortKey = result.sortKey;
        _commentAscending = result.ascending;
        _commentNicknameQuery = result.nicknameQuery;
        _commentSelectedLeague = result.selectedLeague;
        _commentSelectedRank = result.selectedRank;
      });
    }
  }

  // ======== 前/次ナビ用ユーティリティ ========
  static const Map<String, List<String>> _leagueRanks = {
    '未選択': ['未選択'],
    '天鳳': [
      '未選択',
      '天鳳位',
      '十段',
      '九段',
      '八段',
      '七段',
      '六段',
      '五段',
      '四段',
      '三段',
      '二段',
      '初段',
    ],
    '雀魂': [
      '未選択',
      '魂天20',
      '魂天19',
      '魂天18',
      '魂天17',
      '魂天16',
      '魂天15',
      '魂天14',
      '魂天13',
      '魂天12',
      '魂天11',
      '魂天10',
      '魂天9',
      '魂天8',
      '魂天7',
      '魂天6',
      '魂天5',
      '魂天4',
      '魂天3',
      '魂天2',
      '魂天1',
      '雀聖3',
      '雀聖2',
      '雀聖1',
      '雀豪3',
      '雀豪2',
      '雀豪1',
      '雀傑3',
      '雀傑2',
      '雀傑1',
      '雀士3',
      '雀士2',
      '雀士1',
      '初心3',
      '初心2',
      '初心1',
    ],
    '日本プロ麻雀連盟': [
      '未選択',
      'A1リーグ',
      'A2リーグ',
      'B1リーグ',
      'B2リーグ',
      'C1リーグ',
      'C2リーグ',
      'C3リーグ',
      'D1リーグ',
      'D2リーグ',
      'D3リーグ',
      'E1リーグ',
      'E2リーグ',
      'E3リーグ',
    ],
    '最高位戦日本プロ麻雀協会': [
      '未選択',
      'A1リーグ',
      'A2リーグ',
      'B1リーグ',
      'B2リーグ',
      'C1リーグ',
      'C2リーグ',
      'C3リーグ',
      'D1リーグ',
      'D2リーグ',
      'D3リーグ',
    ],
    '日本プロ麻雀協会': [
      '未選択',
      'A1リーグ',
      'A2リーグ',
      'B1リーグ',
      'B2リーグ',
      'C1リーグ',
      'C2リーグ',
      'C3リーグ',
      'D1リーグ',
      'D2リーグ',
      'D3リーグ',
      'E1リーグ',
      'E2リーグ',
      'E3リーグ',
      'F1リーグ',
    ],
    '麻将連合': ['未選択', 'μリーグ', 'μ2リーグ'],
    'RMU': [
      '未選択',
      'A1リーグ',
      'A2リーグ',
      'B1リーグ',
      'B2リーグ',
      'C1リーグ',
      'C2リーグ',
      'C3リーグ',
      'D1リーグ',
      'D2リーグ',
      'D3リーグ',
    ],
  };

  List<String>? _navIds;
  int? _navIndex;
  bool _navLoading = false;

  int _rankOrderIndex(String league, String rank) {
    final list = _leagueRanks[league];
    if (list == null) return 1 << 30;
    final idx = list.indexOf(rank);
    if (idx < 0) return 1 << 30;
    return idx == 0 ? (1 << 29) : idx;
  }

  String? _bestRankForLeague(List<Map<String, dynamic>>? affs, String league) {
    if (affs == null) return null;
    String? best;
    var bestIdx = 1 << 30;
    for (final a in affs) {
      final aff = a['affiliation']?.toString();
      final rk = a['rank']?.toString();
      if (aff == league && rk != null && rk.isNotEmpty) {
        final idx = _rankOrderIndex(league, rk);
        if (idx < bestIdx) {
          bestIdx = idx;
          best = rk;
        }
      }
    }
    return best;
  }

  Future<void> _buildNavOrder() async {
    if (_navLoading) return;
    _navLoading = true;
    try {
      // ★ navContext があればそれを優先。なければデフォルト値。
      final params =
          widget.navContext ??
          const {
            'sortKey': '投稿順',
            'ascending': false,
            'selectedLeague': '未選択',
            'selectedRank': '未選択',
            'nicknameQuery': '',
            'ruleFilter': 'すべて',
            'typeFilter': 'すべて',
          };

      // ---- navContext のキーを柔軟に読むためのヘルパー ----
      String _readString(List<String> keys, String fallback) {
        for (final k in keys) {
          final v = params[k];
          if (v is String && v.isNotEmpty) return v;
        }
        return fallback;
      }

      bool _readBool(List<String> keys, bool fallback) {
        for (final k in keys) {
          final v = params[k];
          if (v is bool) return v;
        }
        return fallback;
      }

      // ---- 並び替え条件の取得（複数候補キーをサポート） ----
      final String sortKey = _readString([
        'sortKey',
        'postSortKey',
        'sortBy',
      ], '投稿順');
      final bool ascending = _readBool([
        'ascending',
        'postAscending',
        'isAscending',
      ], false);
      final String selectedLeague = _readString([
        'selectedLeague',
        'leagueFilter',
        'postLeague',
      ], '未選択');
      final String selectedRank = _readString([
        'selectedRank',
        'rankFilter',
        'postRank',
      ], '未選択');
      final String nicknameQuery = _readString([
        'nicknameQuery',
        'searchNickname',
        'postNicknameQuery',
      ], '');

      // ★ 追加：ルール & 問題タイプのフィルタ値（キーが違っても拾えるように）
      final String ruleFilter = _readString([
        'ruleFilter',
        'postRuleFilter',
        'ruleTypeFilter',
      ], 'すべて');
      final String typeFilter = _readString([
        'typeFilter',
        'postTypeFilter',
        'problemTypeFilter',
      ], 'すべて');

      // ---- posts 全件取得（※ 必要なら将来 where で絞ることも可能）----
      final postsSnap = await FirebaseFirestore.instance
          .collection('posts')
          .get();
      final docs = postsSnap.docs;

      // ---- 投稿者プロフィールをまとめて取得 ----
      final userIds = <String>{
        for (final d in docs) ((d.data()['userId'] ?? '') as String),
      }..removeWhere((e) => e.isEmpty);

      final profMap = <String, _MiniProfile>{};
      await Future.wait(
        userIds.map((uid) async {
          try {
            final s = await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .get();
            if (s.exists) {
              profMap[uid] = _MiniProfile.fromMap(s.data()!);
            }
          } catch (_) {}
        }),
      );

      // ---- ホームと同じ条件でフィルタリング ----
      final filtered = docs.where((d) {
        final data = d.data();
        final uid = (data['userId'] ?? '') as String;
        final prof = profMap[uid];

        // --- ニックネーム検索 ---
        if (nicknameQuery.isNotEmpty) {
          final name = (prof?.nickname ?? (data['userName'] as String? ?? ''))
              .trim();
          if (!name.toLowerCase().contains(nicknameQuery.toLowerCase())) {
            return false;
          }
        }

        // --- 所属/ランクフィルタ ---
        if (selectedLeague != '未選択') {
          final best = _bestRankForLeague(prof?.affiliations, selectedLeague);
          if (selectedRank == '未選択') {
            if (best == null) return false;
          } else {
            if (best == null) return false;
            final need = _rankOrderIndex(selectedLeague, selectedRank);
            final mine = _rankOrderIndex(selectedLeague, best);
            if (mine > need) return false; // 「以上」判定
          }
        }

        // --- ルールフィルタ（"すべて" 以外なら完全一致） ---
        if (ruleFilter != 'すべて') {
          final rule = (data['ruleType'] as String?) ?? '';
          if (rule != ruleFilter) {
            return false;
          }
        }

        // --- 問題タイプフィルタ（"すべて" 以外なら完全一致） ---
        if (typeFilter != 'すべて') {
          final t = (data['postType'] as String?) ?? '';
          if (t != typeFilter) {
            return false;
          }
        }

        return true;
      }).toList();

      // ---- 並び替え（投稿順 or お気に入り数順） ----
      filtered.sort((a, b) {
        int cmp;
        if (sortKey == 'お気に入り数順') {
          final la = (a.data()['likes'] ?? 0) as int;
          final lb = (b.data()['likes'] ?? 0) as int;
          cmp = la.compareTo(lb);
        } else {
          final ta = a.data()['createdAt'];
          final tb = b.data()['createdAt'];
          final va = (ta is Timestamp) ? ta.toDate().millisecondsSinceEpoch : 0;
          final vb = (tb is Timestamp) ? tb.toDate().millisecondsSinceEpoch : 0;
          cmp = va.compareTo(vb);
        }
        return ascending ? cmp : -cmp;
      });

      // ---- 現在の postId が並びの何番目かを計算 ----
      final ids = filtered.map((e) => e.id).toList();
      final idx = ids.indexOf(widget.postId);
      if (mounted) {
        setState(() {
          _navIds = ids;
          _navIndex = (idx >= 0) ? idx : null;
        });
      }
    } finally {
      _navLoading = false;
    }
  }

  bool get _hasPrev => _navIds != null && _navIndex != null && _navIndex! > 0;
  bool get _hasNext =>
      _navIds != null && _navIndex != null && _navIndex! < _navIds!.length - 1;

  Future<void> _goToIndex(int idx) async {
    if (_navIds == null || idx < 0 || idx >= _navIds!.length) return;
    final nextPostId = _navIds![idx];
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => DetailPage(
          postId: nextPostId,
          source: widget.source,
          currentIndex: widget.currentIndex,
          navContext: widget.navContext, // （必要なら）ホームの条件も引き継ぎ
          // ★ ここがポイント：同じ navIds を引き継いで、インデックスだけ更新
          navIds: _navIds,
          navIndex: idx,
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  Future<void> _goPrev() async {
    if (_hasPrev) await _goToIndex(_navIndex! - 1);
  }

  Future<void> _goNext() async {
    if (_hasNext) await _goToIndex(_navIndex! + 1);
  }

  @override
  Widget build(BuildContext context) {
    // 見出し共通スタイル
    const headerStyle = TextStyle(
      color: Colors.white,
      fontSize: 20,
      fontWeight: FontWeight.bold,
      shadows: [Shadow(color: Colors.cyan, blurRadius: 6)],
    );

    return BaseScaffold(
      title: '問題の詳細',
      currentIndex: widget.currentIndex,
      body: Stack(
        children: [
          // ===== 本文 =====
          FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: FirebaseFirestore.instance
                .collection('posts')
                .doc(widget.postId)
                .get(),
            builder: (context, snap) {
              // ===== Firestore 読み込み中 =====
              if (snap.connectionState == ConnectionState.waiting) {
                // ローディング画面は Stack のオーバーレイ側で出すので、ここは空でOK
                return const SizedBox.expand();
              }

              // ===== Firestore 読み込みが完了したタイミングで一度だけフラグON =====
              if (!_postLoaded) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() => _postLoaded = true);
                  }
                });
              }

              // ===== エラー時：画像も来ないので画像側フラグも完了扱い =====
              if (snap.hasError) {
                if (!_imageFinished) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() => _imageFinished = true);
                    }
                  });
                }
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '読み込みエラー: ${snap.error}',
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                );
              }

              // ===== 投稿が存在しない：こちらも画像は来ないので完了扱い =====
              if (!snap.hasData || !snap.data!.exists) {
                if (!_imageFinished) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() => _imageFinished = true);
                    }
                  });
                }
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '投稿が見つかりませんでした',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                );
              }

              final data = snap.data!.data()!;

              final List<String> tiles = ((data['tiles'] as List?) ?? [])
                  .map((e) => e?.toString() ?? '')
                  .where((e) => e.isNotEmpty)
                  .cast<String>()
                  .toList();

              // 🔷 meldGroups から display/restore を取り出す（Homeと同様）
              final List<List<String>> meldDisplayGroups = [];
              final List<List<String>> meldRestoreGroups = [];
              final mgDyn = data['meldGroups'];
              if (mgDyn is List) {
                for (final g in mgDyn) {
                  if (g is Map) {
                    if (g['displayTiles'] is List) {
                      final disp = (g['displayTiles'] as List)
                          .map((e) => e?.toString() ?? '')
                          .where((e) => e.isNotEmpty)
                          .toList();
                      if (disp.isNotEmpty) meldDisplayGroups.add(disp);
                    } else if (g['tiles'] is List) {
                      final disp = (g['tiles'] as List)
                          .map((e) => e?.toString() ?? '')
                          .where((e) => e.isNotEmpty)
                          .toList();
                      if (disp.isNotEmpty) meldDisplayGroups.add(disp);
                    }
                    if (g['restoreTiles'] is List) {
                      final rt = (g['restoreTiles'] as List)
                          .map((e) => e?.toString() ?? '')
                          .where((e) => e.isNotEmpty)
                          .toList();
                      if (rt.isNotEmpty) meldRestoreGroups.add(rt);
                    } else if (g['tiles'] is List) {
                      final rt = (g['tiles'] as List)
                          .map((e) => e?.toString() ?? '')
                          .where((e) => e.isNotEmpty && e != '0')
                          .take(3)
                          .toList();
                      if (rt.isNotEmpty) meldRestoreGroups.add(rt);
                    }
                  }
                }
              }

              // 副露消費後の手牌（実際に選べるのはこれ）
              final List<String> handForChoice = _applyMeldRemovals(
                tiles,
                meldRestoreGroups,
              );

              final String description =
                  (data['description'] as String?)?.trim().isNotEmpty == true
                  ? (data['description'] as String).trim()
                  : '局面の補足説明（例：南3局 供託2本など）';

              final String authorAnswerTile =
                  (data['answerTile'] as String?)?.trim() ?? '';
              final String authorAnswerComment =
                  (data['answerComment'] as String?)?.trim() ?? '';
              final String authorUserId = (data['userId'] as String?) ?? '';

              final String ruleType =
                  ((data['ruleType'] as String?)?.trim().isNotEmpty ?? false)
                  ? (data['ruleType'] as String).trim()
                  : '不明';
              final String postType =
                  ((data['postType'] as String?)?.trim().isNotEmpty ?? false)
                  ? (data['postType'] as String).trim()
                  : '不明';

              final String displayPostType = postType;

              final bool? authorReach = data['reach'] as bool?;
              final bool? authorCall = data['call'] as bool?;
              final List<String>? authorCallTiles =
                  ((data['callTiles'] as List?) ?? [])
                      .map((e) => e?.toString() ?? '')
                      .where((e) => e.isNotEmpty)
                      .cast<String>()
                      .toList();

              final String? myUid = FirebaseAuth.instance.currentUser?.uid;
              final Stream<DocumentSnapshot<Map<String, dynamic>>>?
              myAnswerStream = myUid == null
                  ? null
                  : FirebaseFirestore.instance
                        .collection('posts')
                        .doc(widget.postId)
                        .collection('answers')
                        .doc(myUid)
                        .snapshots();

              return _OneStreamBuilder(
                myStream: myAnswerStream,
                builder: (mySnap) {
                  // 既存回答の復元
                  if (mySnap != null &&
                      mySnap.hasData &&
                      (mySnap.data?.exists ?? false)) {
                    _showResults.value = true;

                    final a = mySnap.data!.data()!;
                    final prevTile = (a['tile'] as String?) ?? '';
                    final prevComment = (a['comment'] as String?) ?? '';
                    final prevReach = a['reach'];
                    final prevCall = a['call'];
                    final prevCallTilesRaw =
                        (a['callTiles'] as List?) ?? const [];
                    final prevCallTiles = prevCallTilesRaw
                        .map((e) => e?.toString() ?? '')
                        .where((e) => e.isNotEmpty)
                        .cast<String>()
                        .toSet();

                    if (_selectedTile.value == null && prevTile.isNotEmpty) {
                      _selectedTile.value = prevTile;
                    }
                    if (_reach.value == null && prevReach is bool) {
                      _reach.value = prevReach;
                    }
                    if (_call.value == null && prevCall is bool) {
                      _call.value = prevCall;
                    }
                    if (_selectedCallTiles.value.isEmpty &&
                        prevCallTiles.isNotEmpty) {
                      _selectedCallTiles.value = prevCallTiles;
                    }
                    if (commentController.text.isEmpty &&
                        prevComment.isNotEmpty) {
                      commentController.text = prevComment;
                    }
                  }

                  Future<String?> _resolveImageUrl() async {
                    final direct = (data['imageUrl'] as String?)?.trim();
                    if (direct != null && direct.isNotEmpty) return direct;
                    final path = (data['imagePath'] as String?)?.trim();
                    if (path != null && path.isNotEmpty) {
                      try {
                        return await FirebaseStorage.instance
                            .ref(path)
                            .getDownloadURL();
                      } catch (_) {
                        return null;
                      }
                    }
                    return null;
                  }

                  // 牌選択ブロック（手牌＋右側に小さな副露表示を同一行に）
                  Widget buildTileSelector() => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('どれを切る？', style: headerStyle),
                      const SizedBox(height: 12),
                      if (tiles.isEmpty)
                        const Text(
                          '選択肢の牌が未設定です',
                          style: TextStyle(color: Colors.white70),
                        )
                      else
                        ValueListenableBuilder<String?>(
                          valueListenable: _selectedTile,
                          builder: (context, sel, _) {
                            final selector = Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.end, // ★底辺そろえ
                              children: [
                                // 左：手牌
                                Expanded(
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: tiles.map((tileId) {
                                      final isSelected = sel == tileId;
                                      return Expanded(
                                        child: GestureDetector(
                                          onTap: () async {
                                            await _playSE();
                                            _selectedTile.value = (isSelected
                                                ? null
                                                : tileId);
                                          },
                                          child: Container(
                                            decoration: BoxDecoration(
                                              border: Border(
                                                bottom: BorderSide(
                                                  color: isSelected
                                                      ? Colors.cyanAccent
                                                      : Colors.transparent,
                                                  width: 3,
                                                ),
                                              ),
                                            ),
                                            child: AspectRatio(
                                              aspectRatio: 2 / 3,
                                              child: Align(
                                                alignment:
                                                    Alignment.bottomCenter,
                                                child: Image.asset(
                                                  'assets/tiles/$tileId.png',
                                                  fit: BoxFit.contain,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                                // 右：副露（小サイズ）
                                if (meldDisplayGroups.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  _SmallMeldGroupsRow(
                                    groups: meldDisplayGroups,
                                  ),
                                ],
                              ],
                            );

                            // 非課金は見せるだけ（タップ無効）
                            return _isPremium
                                ? selector
                                : AbsorbPointer(
                                    child: Opacity(
                                      opacity: 0.95,
                                      child: selector,
                                    ),
                                  );
                          },
                        ),
                    ],
                  );

                  return SingleChildScrollView(
                    key: PageStorageKey('detail_scroll_${widget.postId}'),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ① 投稿者（ニックネーム / 所属(ランク)）
                        FutureBuilder<
                          ({String nickname, String affiliationsText})
                        >(
                          future: _loadPosterMeta(authorUserId),
                          builder: (context, metaSnap) {
                            final nickname = metaSnap.data?.nickname ?? '（未設定）';
                            final affs =
                                metaSnap.data?.affiliationsText ?? '（所属未設定）';
                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.25),
                                border: Border.all(
                                  color: Colors.cyanAccent,
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.zero,
                              ),
                              child: Text(
                                '$nickname / $affs',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 8),

                        // ② 牌姿画像
                        FutureBuilder<String?>(
                          future: _resolveImageUrl(),
                          builder: (context, imgSnap) {
                            Widget _fallbackBox(String text) => Container(
                              width: double.infinity,
                              alignment: Alignment.center,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.2),
                                border: Border.all(
                                  color: Colors.cyanAccent,
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.zero,
                              ),
                              child: Text(
                                text,
                                style: const TextStyle(color: Colors.white70),
                              ),
                            );

                            // ===== Storage の URL 解決中 =====
                            if (imgSnap.connectionState ==
                                ConnectionState.waiting) {
                              return _fallbackBox('読み込み中…');
                            }

                            final url = imgSnap.data;

                            // ===== URL が無い場合：画像はこれ以上来ないので完了扱い =====
                            if (url == null || url.isEmpty) {
                              if (!_imageFinished) {
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (mounted) {
                                    setState(() => _imageFinished = true);
                                  }
                                });
                              }
                              return _fallbackBox('牌姿画像が登録されていません');
                            }

                            // ===== URL が取れた場合：Image.network の描画完了でフラグON =====
                            final bordered = Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.cyanAccent,
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.zero,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.zero,
                                child: Image.network(
                                  url,
                                  fit: BoxFit.contain,
                                  width: double.infinity,
                                  gaplessPlayback: true,
                                  loadingBuilder:
                                      (ctx, child, loadingProgress) {
                                        if (loadingProgress == null) {
                                          // 画像のデコードとレイアウトが終わったタイミング
                                          if (!_imageFinished) {
                                            WidgetsBinding.instance
                                                .addPostFrameCallback((_) {
                                                  if (mounted) {
                                                    setState(
                                                      () =>
                                                          _imageFinished = true,
                                                    );
                                                  }
                                                });
                                          }
                                          return child;
                                        }
                                        // 読み込み中：裏で読み込みだけ進める（表はローディングオーバーレイ）
                                        return child;
                                      },
                                  errorBuilder: (ctx, error, stack) {
                                    // エラーでももうこれ以上は読み込まれないので完了扱い
                                    if (!_imageFinished) {
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            if (mounted) {
                                              setState(
                                                () => _imageFinished = true,
                                              );
                                            }
                                          });
                                    }
                                    return _fallbackBox('画像を読み込めませんでした');
                                  },
                                ),
                              ),
                            );

                            return GestureDetector(
                              onTap: () => _openImagePopup(url),
                              child: bordered,
                            );
                          },
                        ),

                        const SizedBox(height: 12),

                        // ③ ルール/タイプ + 説明
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            border: Border.all(
                              color: Colors.cyanAccent,
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.zero,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$ruleType / $displayPostType',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                description,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // タイプ選択（非課金はトグル非表示）
                        const SizedBox(height: 16),
                        if (_isPremium)
                          _AnswerTypeCard(
                            postType: postType,
                            tiles: handForChoice,
                            reach: _reach,
                            call: _call,
                            selectedCallTiles: _selectedCallTiles,
                            selectedTile: _selectedTile,
                            onSound: _playSE,
                          )
                        else
                          const SizedBox.shrink(),

                        // ④ 牌選択（非課金でも表示はするがタップ不可）
                        const SizedBox(height: 20),
                        if (postType != '副露判断') ...[
                          buildTileSelector(),
                        ] else ...[
                          ValueListenableBuilder<bool?>(
                            valueListenable: _call,
                            builder: (context, v, _) {
                              if (v == false) {
                                return const SizedBox.shrink();
                              }
                              return buildTileSelector();
                            },
                          ),
                        ],

                        const SizedBox(height: 24),

                        // コメント欄（課金のみ）
                        if (_isPremium) ...[
                          TextField(
                            controller: commentController,
                            maxLength: 200,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              filled: true,
                              fillColor: Color.fromRGBO(0, 0, 0, 0.3),
                              hintText: '理由・補足など（任意・200文字以内）',
                              hintStyle: TextStyle(color: Colors.white54),
                              counterStyle: TextStyle(color: Colors.white54),
                              border: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Colors.cyanAccent,
                                ),
                                borderRadius: BorderRadius.zero,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // アクションボタン（課金: 回答する / 非課金: みんなの回答を見る）
                        Center(
                          child: _isPremium
                              ? ElevatedButton.icon(
                                  onPressed: () =>
                                      _submitAnswer(postType: postType),
                                  icon: const Icon(Icons.send),
                                  label: const Text('回答する'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.cyanAccent,
                                    foregroundColor: Colors.black,
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                )
                              : ElevatedButton.icon(
                                  onPressed: () async {
                                    _showResults.value = true;
                                    await _maybeUpsellEvery3UniquePosts();
                                  },
                                  icon: const Icon(Icons.visibility),
                                  label: const Text('みんなの回答を見る'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.cyanAccent,
                                    foregroundColor: Colors.black,
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                ),
                        ),

                        const SizedBox(height: 24),

                        // ================== 以下、集計UI ==================
                        ValueListenableBuilder<bool>(
                          valueListenable: _showResults,
                          builder: (context, show, _) {
                            if (!show) return const SizedBox(height: 0);

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('回答集計結果', style: headerStyle),
                                const SizedBox(height: 12),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final double pieSide =
                                        (constraints.maxWidth * 0.86).clamp(
                                          160.0,
                                          420.0,
                                        );

                                    final Color lineColor = Colors.cyanAccent
                                        .withOpacity(0.9);
                                    const double lineThickness = 1.5;

                                    return Container(
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.3,
                                        ),
                                        border: Border.all(
                                          color: Colors.cyanAccent,
                                          width: 1.5,
                                        ),
                                        borderRadius: BorderRadius.zero,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          // 上段：円グラフ
                                          Padding(
                                            padding: const EdgeInsets.all(4),
                                            child: Center(
                                              child: _CombinedAnswersPie(
                                                postId: widget.postId,
                                                postType: postType,
                                                size: pieSide,
                                                authorAnswerTile:
                                                    authorAnswerTile,
                                                authorReach: authorReach,
                                                authorCall: authorCall,
                                                authorCallTiles:
                                                    authorCallTiles,
                                              ),
                                            ),
                                          ),

                                          Divider(
                                            height: lineThickness,
                                            thickness: lineThickness,
                                            color: lineColor,
                                          ),

                                          // 下段：投稿者の選択/コメント
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              8,
                                              6,
                                              8,
                                              12,
                                            ),
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                minHeight: 140,
                                              ),
                                              child: IntrinsicHeight(
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    // 左：選択
                                                    Expanded(
                                                      flex: 4,
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets.fromLTRB(
                                                              8,
                                                              8,
                                                              12,
                                                              8,
                                                            ),
                                                        child: _AuthorOnlyTileBox(
                                                          tile:
                                                              authorAnswerTile,
                                                          postType: postType,
                                                          authorReach:
                                                              authorReach,
                                                          authorCall:
                                                              authorCall,
                                                          authorCallTiles:
                                                              authorCallTiles,
                                                        ),
                                                      ),
                                                    ),
                                                    // 境界線
                                                    Container(
                                                      width: lineThickness,
                                                      color: lineColor,
                                                    ),
                                                    // 右：コメント
                                                    Expanded(
                                                      flex: 6,
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets.fromLTRB(
                                                              12,
                                                              8,
                                                              8,
                                                              8,
                                                            ),
                                                        child: _AuthorOnlyCommentBox(
                                                          comment:
                                                              authorAnswerComment,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                            );
                          },
                        ),

                        const SizedBox(height: 24),

                        // ======== コメント欄（タブ化） ========
                        ValueListenableBuilder<bool>(
                          valueListenable: _showResults,
                          builder: (context, show, _) {
                            if (!show) return const SizedBox(height: 0);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text('回答コメント', style: headerStyle),
                                    const Spacer(),
                                    const SizedBox(width: 8),
                                    // ソートボタン
                                    Material(
                                      color: Colors.transparent,
                                      child: Ink(
                                        decoration: const ShapeDecoration(
                                          color: Color(0xFF0B1114),
                                          shape: CircleBorder(
                                            side: BorderSide(
                                              color: Colors.cyanAccent,
                                              width: 1,
                                            ),
                                          ),
                                        ),
                                        child: IconButton(
                                          tooltip: 'ソート設定',
                                          icon: const Icon(
                                            Icons.tune,
                                            size: 20,
                                            color: Colors.cyanAccent,
                                          ),
                                          onPressed: _openCommentSortSheet,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    border: Border.all(
                                      color: Colors.cyanAccent,
                                      width: 1.5,
                                    ),
                                    borderRadius: BorderRadius.zero,
                                  ),
                                  child: _GroupedAnswerComments(
                                    postId: widget.postId,
                                    postType: postType,
                                    sortKey: _commentSortKey,
                                    ascending: _commentAscending,
                                    nicknameQuery: _commentNicknameQuery,
                                    selectedLeague: _commentSelectedLeague,
                                    selectedRank: _commentSelectedRank,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),

                        // ====== 前/次ナビ（常時表示） ======
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            if (_hasPrev)
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _goPrev,
                                  icon: const Icon(Icons.chevron_left),
                                  label: const Text('前の問題'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.cyanAccent,
                                    side: const BorderSide(
                                      color: Colors.cyanAccent,
                                    ),
                                  ),
                                ),
                              ),
                            if (_hasPrev && _hasNext) const SizedBox(width: 12),
                            if (_hasNext)
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _goNext,
                                  icon: const Icon(Icons.chevron_right),
                                  label: const Text('次の問題'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.cyanAccent,
                                    foregroundColor: Colors.black,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),

          // 右上固定 ☆ ボタン
          const Positioned(top: 4, right: 4, child: _FavButtonOverlay()),

          // ★ Firestore or 画像がまだ終わっていない間は、
          //   Home/MyPage と同じローディング画面をページ全体にかぶせる
          if (_showInitialLoading)
            Positioned.fill(child: _buildFullPageLoading()),
        ],
      ),
    );
  }
}

//// =============== 補助ウィジェット群（このファイル内に必ず置く） ===============

class _AnswerTypeCard extends StatelessWidget {
  final String postType; // 'リーチ判断' / '副露判断'
  final List<String> tiles;
  final ValueNotifier<bool?> reach;
  final ValueNotifier<bool?> call;
  final ValueNotifier<Set<String>> selectedCallTiles;
  final ValueNotifier<String?> selectedTile; // ★ スルー時に打牌選択もクリア
  final Future<void> Function() onSound;

  // ★追加：非課金は選択UIを出さない（見出しだけ表示）
  final bool readonly;

  const _AnswerTypeCard({
    super.key,
    required this.postType,
    required this.tiles,
    required this.reach,
    required this.call,
    required this.selectedCallTiles,
    required this.selectedTile,
    required this.onSound,
    this.readonly = false,
  });

  @override
  Widget build(BuildContext context) {
    const headerStyle = TextStyle(
      color: Colors.white,
      fontSize: 20,
      fontWeight: FontWeight.bold,
      shadows: [Shadow(color: Colors.cyan, blurRadius: 6)],
    );

    if (postType != 'リーチ判断' && postType != '副露判断') {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(postType == 'リーチ判断' ? 'リーチする？' : '鳴く？', style: headerStyle),
        const SizedBox(height: 8),

        // ▼ 課金のみ：トグルと副露2枚選択を表示
        if (postType == 'リーチ判断' && !readonly)
          ValueListenableBuilder<bool?>(
            valueListenable: reach,
            builder: (context, v, _) => Row(
              children: [
                Expanded(
                  child: _ToggleButton(
                    label: 'する',
                    selected: v == true,
                    onTap: () async {
                      await onSound();
                      reach.value = true;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ToggleButton(
                    label: 'しない',
                    selected: v == false,
                    onTap: () async {
                      await onSound();
                      reach.value = false;
                    },
                  ),
                ),
              ],
            ),
          ),

        if (postType == '副露判断' && !readonly) ...[
          ValueListenableBuilder<bool?>(
            valueListenable: call,
            builder: (context, v, _) => Row(
              children: [
                Expanded(
                  child: _ToggleButton(
                    label: '鳴く',
                    selected: v == true,
                    onTap: () async {
                      await onSound();
                      call.value = true;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ToggleButton(
                    label: 'スルー',
                    selected: v == false,
                    onTap: () async {
                      await onSound();
                      // ★ スルーを選択したら鳴き2枚と打牌選択を解除
                      call.value = false;
                      selectedCallTiles.value = <String>{};
                      selectedTile.value = null;
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<bool?>(
            valueListenable: call,
            builder: (context, v, _) {
              if (v != true) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '鳴く2枚を選択（最大2枚）',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  ValueListenableBuilder<Set<String>>(
                    valueListenable: selectedCallTiles,
                    builder: (context, selSet, __) => Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: tiles.map((tileId) {
                        final isSelected = selSet.contains(tileId);
                        return Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              await onSound();
                              final next = Set<String>.from(selSet);
                              if (isSelected) {
                                next.remove(tileId);
                              } else {
                                if (next.length >= 2) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('選択は最大2枚です')),
                                  );
                                } else {
                                  next.add(tileId);
                                }
                              }
                              selectedCallTiles.value = next;
                            },
                            child: Stack(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: isSelected
                                            ? Colors.cyanAccent
                                            : Colors.transparent,
                                        width: 3,
                                      ),
                                    ),
                                  ),
                                  child: AspectRatio(
                                    aspectRatio: 2 / 3,
                                    child: Image.asset(
                                      'assets/tiles/$tileId.png',
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  const Positioned(
                                    right: 4,
                                    top: 4,
                                    child: Icon(
                                      Icons.check_circle,
                                      size: 18,
                                      color: Colors.cyanAccent,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

/// 同一行で右側に小さく副露を並べる表示（暗カンの '0' は背面色で描画）
class _SmallMeldGroupsRow extends StatelessWidget {
  final List<List<String>> groups;
  const _SmallMeldGroupsRow({super.key, required this.groups});

  // 牌画像パス
  static String _asset(String id) => 'assets/tiles/$id.png';

  @override
  Widget build(BuildContext context) {
    // 小さめ
    const double tileW = 18;
    const double tileH = 27;

    Widget tileView(String id) {
      return SizedBox(
        width: tileW,
        height: tileH,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Image.asset(
            _asset(id),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(groups.length, (gi) {
          final g = groups[gi];
          return Padding(
            padding: EdgeInsets.only(right: gi == groups.length - 1 ? 0 : 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: g.map(tileView).toList(),
            ),
          );
        }),
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        color: selected ? Colors.cyanAccent : Colors.transparent,
        border: Border.all(color: Colors.cyanAccent, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.black : Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 丸い半透明コンテナに入った☆ボタン
class _StarCircle extends StatelessWidget {
  final bool isFav;
  final bool busy;
  final VoidCallback? onTap;

  const _StarCircle({
    super.key,
    required this.isFav,
    required this.busy,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      isFav ? Icons.star : Icons.star_border,
      color: isFav ? Colors.yellowAccent : Colors.white70,
      size: 22,
    );

    return Opacity(
      opacity: busy ? 0.6 : 1.0,
      child: InkResponse(
        onTap: busy ? null : onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.30),
            border: Border.all(color: Colors.white24, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: icon,
        ),
      ),
    );
  }
}

/// お気に入りボタン（users/{uid}.favoritePosts を Map で管理）
class _FavButtonOverlay extends StatefulWidget {
  const _FavButtonOverlay({super.key});
  @override
  State<_FavButtonOverlay> createState() => _FavButtonOverlayState();
}

class _FavButtonOverlayState extends State<_FavButtonOverlay> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final postId =
        (context.findAncestorStateOfType<_DetailPageState>()?.widget.postId) ??
        '';
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null || postId.isEmpty) {
      return _StarCircle(
        isFav: false,
        busy: false,
        onTap: () => ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('お気に入りはログイン後に利用できます'))),
      );
    }

    final db = FirebaseFirestore.instance;
    final postRef = db.collection('posts').doc(postId);
    final userRef = db.collection('users').doc(uid);

    // ★ ユーザードキュメントを監視して isFav をライブ反映
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userRef.snapshots(),
      builder: (context, snap) {
        final favMap =
            (snap.data?.data()?['favoritePosts'] as Map?)
                ?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        final isFav = favMap[postId] == true;

        Future<void> _toggle() async {
          if (_busy) return;
          setState(() => _busy = true);
          try {
            await db.runTransaction((tx) async {
              // 先に現状を取得（ルール: posts.likes は ±1 のみ許可）
              final postSnap = await tx.get(postRef);
              final userSnap = await tx.get(userRef);

              final currLikes = (postSnap.data()?['likes'] ?? 0) as int;
              final currFavMap =
                  (userSnap.data()?['favoritePosts'] as Map?)
                      ?.cast<String, dynamic>() ??
                  const <String, dynamic>{};
              final isFavNow = currFavMap[postId] == true;
              final wantFav = !isFavNow;

              // posts.likes を ±1（0未満にしない）
              final nextLikes = wantFav
                  ? currLikes + 1
                  : (currLikes > 0 ? currLikes - 1 : 0);
              tx.update(postRef, {'likes': nextLikes});

              // users/{uid}.favoritePosts の該当キーを追加/削除（Map の部分更新）
              if (wantFav) {
                tx.set(userRef, {
                  'favoritePosts': {postId: true},
                }, SetOptions(merge: true));
              } else {
                tx.set(userRef, {
                  'favoritePosts': {postId: FieldValue.delete()},
                }, SetOptions(merge: true));
              }
            });

            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(isFav ? 'お気に入りを解除しました' : 'お気に入りに追加しました')),
            );
          } catch (e) {
            if (!mounted) return;
            final msg = e is FirebaseException ? e.code : e.toString();
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('お気に入り更新失敗 ($msg)')));
          } finally {
            if (mounted) setState(() => _busy = false);
          }
        }

        return _StarCircle(isFav: isFav, busy: _busy, onTap: _toggle);
      },
    );
  }
}

/// 投稿者の「選択」
class _AuthorOnlyTileBox extends StatelessWidget {
  final String tile; // 打牌選択
  final String postType;
  final bool? authorReach; // リーチ判断用
  final bool? authorCall; // 副露判断：鳴く/スルー
  final List<String>? authorCallTiles; // 副露に使う牌（2枚想定）

  const _AuthorOnlyTileBox({
    super.key,
    required this.tile,
    required this.postType,
    required this.authorReach,
    this.authorCall,
    this.authorCallTiles,
  });

  @override
  Widget build(BuildContext context) {
    const titleStyle = TextStyle(
      color: Colors.white,
      fontSize: 13,
      fontWeight: FontWeight.bold,
      decoration: TextDecoration.underline,
      decorationColor: Colors.cyanAccent,
      decorationThickness: 2,
    );

    // リーチ判断タグ
    String? reachTag;
    if (postType == 'リーチ判断' && authorReach != null) {
      reachTag = authorReach! ? 'リーチ：する' : 'リーチ：しない';
    }

    // 副露判断タグ
    String? callTag;
    if (postType == '副露判断' && authorCall != null) {
      callTag = authorCall! ? '鳴く' : 'スルー';
    }

    Widget pill(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.cyanAccent.withOpacity(0.95),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          height: 1.2,
        ),
      ),
    );

    // --- 副露判断でスルーの時は「スルー」のみ表示 ---
    if (postType == '副露判断' && authorCall == false) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('投稿者の選択', style: titleStyle, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          pill('スルー'),
        ],
      );
    }

    // 縦並び UI（鳴く時やその他の場合）
    Widget buildCallTilesRow(List<String> pair) {
      final tiles = pair.where((e) => e.trim().isNotEmpty).toList();
      if (tiles.isEmpty) return const SizedBox.shrink();
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < tiles.length && i < 2; i++) ...[
            SizedBox(
              width: 36,
              height: 54,
              child: Image.asset(
                'assets/tiles/${tiles[i]}.png',
                fit: BoxFit.contain,
              ),
            ),
            if (i == 0 && tiles.length >= 2) const SizedBox(width: 6),
          ],
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('投稿者の選択', style: titleStyle, textAlign: TextAlign.center),
        const SizedBox(height: 6),

        // リーチ判断：上部にリーチピル
        if (reachTag != null && postType == 'リーチ判断') ...[
          pill(reachTag!),
          const SizedBox(height: 8),
        ],

        // 副露判断（鳴く時）：鳴く → 副露に使う牌 → 打牌画像
        if (postType == '副露判断' && authorCall == true) ...[
          // 1) 鳴く
          pill('鳴く'),
          const SizedBox(height: 6),

          // 2) 副露に使う牌（2枚）
          if ((authorCallTiles ?? const []).isNotEmpty) ...[
            buildCallTilesRow(authorCallTiles!),
            const SizedBox(height: 6),
          ],

          // 3) 打牌
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 90, maxHeight: 120),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: Center(
                child: tile.isNotEmpty
                    ? Image.asset('assets/tiles/$tile.png', fit: BoxFit.contain)
                    : const Icon(
                        Icons.help_outline,
                        color: Colors.white54,
                        size: 28,
                      ),
              ),
            ),
          ),
        ] else ...[
          // 通常：打牌のみ
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 90, maxHeight: 120),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: Center(
                child: tile.isNotEmpty
                    ? Image.asset('assets/tiles/$tile.png', fit: BoxFit.contain)
                    : const Icon(
                        Icons.help_outline,
                        color: Colors.white54,
                        size: 28,
                      ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 投稿者のコメント（中央寄せ・折り返し）
class _AuthorOnlyCommentBox extends StatelessWidget {
  final String comment;
  const _AuthorOnlyCommentBox({super.key, required this.comment});

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(
      color: Colors.white,
      fontSize: 13,
      fontWeight: FontWeight.bold,
      decoration: TextDecoration.underline,
      decorationColor: Colors.cyanAccent,
      decorationThickness: 2,
    );

    final text = (comment.isNotEmpty) ? comment : '（コメントなし）';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('投稿者のコメント', style: labelStyle, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(
          text,
          textAlign: TextAlign.center,
          softWrap: true,
          maxLines: 8,
          overflow: TextOverflow.fade,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

typedef OneDocBuilder =
    Widget Function(AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>>?);

class _OneStreamBuilder extends StatelessWidget {
  final Stream<DocumentSnapshot<Map<String, dynamic>>>? myStream;
  final OneDocBuilder builder;

  const _OneStreamBuilder({
    super.key,
    required this.myStream,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: myStream,
      builder: (context, mySnap) => builder(mySnap),
    );
  }
}

// ===============================================
// 手牌から副露の消費分(restoreTilesの合計)を引いた配列を返す
// ===============================================
List<String> _applyMeldRemovals(List<String> src, List<List<String>> groups) {
  if (groups.isEmpty) return List<String>.from(src);
  final Map<String, int> need = {};
  for (final g in groups) {
    for (final id in g) {
      if (id.isEmpty) continue;
      need.update(id, (v) => v + 1, ifAbsent: () => 1);
    }
  }
  final out = <String>[];
  for (final id in src) {
    final n = need[id];
    if (n != null && n > 0) {
      need[id] = n - 1; // 消費
    } else {
      out.add(id);
    }
  }
  return out;
}

// =====================================================
// 単一列の牌帯（使い所があれば利用）：左=手牌 / 右=副露
// =====================================================
class _SelectableTileStrip extends StatelessWidget {
  final List<String> handTiles;
  final List<List<String>> meldDisplayGroups;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _SelectableTileStrip({
    super.key,
    required this.handTiles,
    required this.meldDisplayGroups,
    required this.selected,
    required this.onSelect,
  });

  static String _asset(String id) => 'assets/tiles/$id.png';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const gapUnit = 0.6;
        const meldScale = 0.82;

        final handCount = handTiles.length;
        final meldTilesTotal = meldDisplayGroups.fold<int>(
          0,
          (s, g) => s + g.length,
        );
        final gapCount = meldDisplayGroups.isEmpty
            ? 0
            : meldDisplayGroups.length;

        final totalUnits =
            handCount * 1.0 + meldTilesTotal * meldScale + gapCount * gapUnit;

        final baseW = c.maxWidth / (totalUnits == 0 ? 1 : totalUnits);
        final handW = baseW * 1.0;
        final meldW = baseW * meldScale;
        final height = (handW * 3 / 2).clamp(28.0, 96.0);

        Widget handTile(String id, bool isSel) => SizedBox(
          width: handW,
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: InkWell(
              onTap: () => onSelect(id),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isSel ? Colors.cyanAccent : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Image.asset(
                    _asset(id),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Center(
                      child: Text(
                        id,
                        style: TextStyle(
                          color: isSel ? Colors.cyanAccent : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        Widget meldTile(String id) => SizedBox(
          width: meldW,
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Image.asset(
                _asset(id),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(id, style: const TextStyle(color: Colors.white)),
                ),
              ),
            ),
          ),
        );

        Widget gapBox() => SizedBox(width: baseW * gapUnit);

        final children = <Widget>[];

        for (final id in handTiles) {
          children.add(handTile(id, selected == id));
        }
        for (int gi = 0; gi < meldDisplayGroups.length; gi++) {
          children.add(gapBox());
          for (final id in meldDisplayGroups[gi]) {
            children.add(meldTile(id));
          }
        }

        return SizedBox(
          width: c.maxWidth,
          height: height,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: children,
            ),
          ),
        );
      },
    );
  }
}

//// ================== 円グラフ ==================

class _SliceEntry {
  final String label; // 例: 'する・5m' / '鳴く・[3m+3m]・5p' / 'スルー・[-]・(未選択)' / 'その他'
  final int value;
  final String? tileId; // 画像に使う牌ID。その他は null
  _SliceEntry(this.label, this.value, this.tileId);
}

class _CombinedAnswersPie extends StatelessWidget {
  final String postId;
  final String postType; // 'リーチ判断' / '副露判断' / その他
  final String authorAnswerTile;
  final bool? authorReach;
  final bool? authorCall;
  final List<String>? authorCallTiles;
  final double size;

  const _CombinedAnswersPie({
    super.key,
    required this.postId,
    required this.postType,
    required this.size,
    required this.authorAnswerTile,
    required this.authorReach,
    required this.authorCall,
    required this.authorCallTiles,
  });

  String _pairKeyFromList(List list) {
    final arr = list
        .map((e) => e?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .cast<String>()
        .toList();
    if (arr.length < 2) return '';
    arr.sort();
    return '${arr[0]}+${arr[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final answersStream = FirebaseFirestore.instance
        .collection('posts')
        .doc(postId)
        .collection('answers')
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: answersStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return SizedBox(
            width: size,
            height: size,
            child: const Center(
              child: SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (snap.hasError) {
          return Text(
            '集計エラー: ${snap.error}',
            style: const TextStyle(color: Colors.redAccent),
          );
        }

        final Map<String, int> counts = {};
        final Map<String, String?> labelToTile = {};

        void addLabel(String label, String? tileId) {
          if (label.isEmpty) return;
          counts.update(label, (v) => v + 1, ifAbsent: () => 1);
          labelToTile.putIfAbsent(label, () => tileId);
        }

        for (final d in (snap.data?.docs ?? [])) {
          final data = d.data();
          final tile = (data['tile'] as String?)?.trim() ?? '';

          if (postType == 'リーチ判断') {
            final r = data['reach'];
            if (r is bool && tile.isNotEmpty) {
              final decision = r ? 'する' : 'しない';
              addLabel('$decision・$tile', tile);
            }
          } else if (postType == '副露判断') {
            final c = data['call'];
            final pair = _pairKeyFromList(
              (data['callTiles'] as List?) ?? const [],
            );
            final pairText = (c == true)
                ? (pair.isNotEmpty ? '[${pair}]' : '[不明]')
                : '[-]';
            final t = tile.isNotEmpty ? tile : '(未選択)';
            if (c is bool) {
              final head = c ? '鳴く' : 'スルー';
              addLabel('$head・$pairText・$t', tile.isNotEmpty ? tile : null);
            }
          } else {
            if (tile.isNotEmpty) addLabel(tile, tile);
          }
        }

        // 投稿者の選択も加味
        if (postType == 'リーチ判断' &&
            authorReach is bool &&
            authorAnswerTile.isNotEmpty) {
          final decision = authorReach == true ? 'する' : 'しない';
          addLabel('$decision・${authorAnswerTile}', authorAnswerTile);
        } else if (postType == '副露判断' && authorCall is bool) {
          final pair = _pairKeyFromList(authorCallTiles ?? const []);
          final pairText = (authorCall == true)
              ? (pair.isNotEmpty ? '[${pair}]' : '[不明]')
              : '[-]';
          final t = authorAnswerTile.isNotEmpty ? authorAnswerTile : '(未選択)';
          final head = authorCall == true ? '鳴く' : 'スルー';
          addLabel(
            '$head・$pairText・$t',
            authorAnswerTile.isNotEmpty ? authorAnswerTile : null,
          );
        } else if (postType != 'リーチ判断' && postType != '副露判断') {
          if (authorAnswerTile.isNotEmpty)
            addLabel(authorAnswerTile, authorAnswerTile);
        }

        if (counts.isEmpty) {
          return SizedBox(
            width: size,
            height: size,
            child: const Center(
              child: Text(
                'まだ回答がありません',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          );
        }

        final entries = counts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        // 上位1〜3位 + その他
        final top = entries.take(3).toList();
        final othersSum = entries.skip(3).fold<int>(0, (s, e) => s + e.value);

        final List<_SliceEntry> slices = [
          ...top.map((e) => _SliceEntry(e.key, e.value, labelToTile[e.key])),
          if (othersSum > 0) _SliceEntry('その他', othersSum, null),
        ];

        return _PieWithIcons(slices: slices, size: size, postType: postType);
      },
    );
  }
}

/// 円グラフ本体：％は白字＋黒縁。四隅は非重なり縦積み。
/// 副露判断は円内画像を出さず、四隅で「鳴く」→副露2枚→打牌画像。
class _PieWithIcons extends StatefulWidget {
  final List<_SliceEntry> slices;
  final double size;
  final String postType;
  const _PieWithIcons({
    super.key,
    required this.slices,
    required this.size,
    required this.postType,
  });

  @override
  State<_PieWithIcons> createState() => _PieWithIconsState();
}

class _PieWithIconsState extends State<_PieWithIcons> {
  bool _overlaps(Rect a, Rect b) => a.overlaps(b);

  Color _colorForIndex(int i) {
    switch (i) {
      case 0:
        return Colors.red;
      case 1:
        return Colors.blue;
      case 2:
        return Colors.yellow;
      default:
        return Colors.green;
    }
  }

  ({double w, double h, double pad}) _cornerIconMetrics(double boxSize) {
    final double w = (boxSize * 0.16).clamp(26.0, 54.0);
    final double h = w * 1.5;
    const pad = 8.0;
    return (w: w, h: h, pad: pad);
  }

  String? _tagFromSliceLabel(String label) {
    if (label == 'その他') return 'その他';
    if (widget.postType == 'リーチ判断') {
      if (label.startsWith('する')) return 'リーチ: する';
      if (label.startsWith('しない')) return 'リーチ: しない';
    } else if (widget.postType == '副露判断') {
      if (label.startsWith('鳴く')) return '鳴く';
      if (label.startsWith('スルー')) return 'スルー';
    }
    return null;
  }

  List<String> _extractCallPair(String label) {
    final m = RegExp(r'\[([^\]]+)\]').firstMatch(label);
    if (m == null) return const [];
    return m
        .group(1)!
        .split('+')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Widget _safeTile(String id, {double? w, double? h, Key? key}) {
    return Image.asset(
      'assets/tiles/$id.png',
      key: key,
      width: w,
      height: h,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }

  // 画像中心・ピル中心を取るためのキー
  final _imgKeyTR = GlobalKey();
  final _imgKeyBR = GlobalKey();
  final _imgKeyBL = GlobalKey();
  final _imgKeyTL = GlobalKey();

  final _pillKeyTR = GlobalKey();
  final _pillKeyBR = GlobalKey();
  final _pillKeyBL = GlobalKey();
  final _pillKeyTL = GlobalKey();

  bool _postFrameRequested = false;

  Offset? _centerOf(GlobalKey key) {
    final ctx = key.currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    final parent = context.findRenderObject() as RenderBox?;
    if (ctx == null ||
        box == null ||
        parent == null ||
        !box.attached ||
        !parent.attached)
      return null;
    final g = box.localToGlobal(box.size.center(Offset.zero));
    return parent.globalToLocal(g);
  }

  // 四隅の縦積み（ピル→（副露2枚）→打牌画像）
  // スルーのみの場合にピルへ key を付与して座標取得
  Widget _cornerColumn({
    required _SliceEntry? slice,
    required String? pill,
    required GlobalKey? imgKey,
    required GlobalKey? pillKey,
  }) {
    final m = _cornerIconMetrics(widget.size);
    if (slice == null) return const SizedBox.shrink();

    if (slice.label == 'その他') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.cyanAccent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'その他',
          style: TextStyle(
            color: Colors.black,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            height: 1.2,
          ),
          softWrap: false,
        ),
      );
    }

    final mainImg = (slice.tileId == null || slice.tileId!.isEmpty)
        ? const SizedBox.shrink()
        : _safeTile(slice.tileId!, w: m.w, h: m.h, key: imgKey);

    // 「スルー」だけ（画像なし）なら pill に key を付与
    final isTextOnly =
        (widget.postType == '副露判断') &&
        slice.label.startsWith('スルー') &&
        (slice.tileId == null || slice.tileId!.isEmpty);

    final pillWidget = (pill == null || pill.isEmpty)
        ? const SizedBox.shrink()
        : Container(
            key: isTextOnly ? pillKey : null,
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.cyanAccent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              pill,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.black,
                height: 1.2,
              ),
              softWrap: false,
            ),
          );

    final pair = (widget.postType == '副露判断')
        ? _extractCallPair(slice.label)
        : const <String>[];
    final pairRow = (pair.isEmpty)
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: pair.take(2).map((id) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _safeTile(id, w: m.w * 0.42, h: m.h * 0.42),
                );
              }).toList(),
            ),
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [pillWidget, if (pair.isNotEmpty) pairRow, mainImg],
    );
  }

  @override
  Widget build(BuildContext context) {
    final slices = widget.slices;
    final size = widget.size;

    final total = slices.fold<int>(0, (s, e) => s + e.value);
    if (total == 0) return SizedBox(width: size, height: size);

    final paintEntries = slices
        .map((s) => MapEntry(s.label, s.value))
        .toList(growable: false);
    final colors = List<Color>.generate(
      slices.length,
      (i) => _colorForIndex(i),
    );

    final m = _cornerIconMetrics(size);
    final double safePad = (m.h + 6.0).clamp(14.0, size * 0.24);

    final center = size / 2;
    final innerSide = (size - safePad * 2).clamp(120.0, size);
    final double radius = innerSide / 2;

    final bool twoOnly = slices.length == 2;
    final idxEtc = slices.indexWhere((e) => e.label == 'その他');

    _SliceEntry? sTR = slices.isNotEmpty ? slices[0] : null;
    _SliceEntry? sBR = (slices.length >= 2 && !twoOnly) ? slices[1] : null;
    _SliceEntry? sBL = slices.length >= 3 ? slices[2] : null;
    _SliceEntry? sTL = (idxEtc >= 0)
        ? slices[idxEtc]
        : (twoOnly && slices.length >= 2 ? slices[1] : null);

    // ％の配置
    double start = -math.pi / 2;
    final percentWidgets = <Widget>[];
    final placedPercents = <Rect>[]; // 衝突回避のため記録
    final percentCenters = <Offset>[]; // リーダー線の宛先

    const textW = 46.0;
    const textH = 22.0;
    final double rPercentInner = radius * 0.42;
    final double rPercentOuter = radius * 0.60;

    for (int i = 0; i < slices.length; i++) {
      final e = slices[i];
      final sweep = (e.value / total) * 2 * math.pi;
      final mid = start + sweep / 2;
      start += sweep;

      // ラベル（％）の衝突回避
      final narrowSlice = sweep < 0.35;
      double rText = narrowSlice ? rPercentInner : rPercentOuter;
      Rect percentRect;
      int attempts = 0;
      while (true) {
        final tx = center + rText * math.cos(mid);
        final ty = center + rText * math.sin(mid);
        percentRect = Rect.fromLTWH(
          tx - textW / 2,
          ty - textH / 2,
          textW,
          textH,
        );

        bool hit = false;
        if (percentRect.left < 2 ||
            percentRect.top < 2 ||
            percentRect.right > size - 2 ||
            percentRect.bottom > size - 2) {
          hit = true;
        }
        if (!hit) {
          for (final r in placedPercents) {
            if (_overlaps(r.inflate(8), percentRect)) {
              hit = true;
              break;
            }
          }
        }
        if (!hit) break;

        if (attempts++ > 16) break;
        if (rText > rPercentInner + 2) {
          rText -= 6;
        } else {
          final shift = (attempts.isEven ? 0.12 : -0.12);
          final tx2 = center + rText * math.cos(mid + shift);
          final ty2 = center + rText * math.sin(mid + shift);
          percentRect = Rect.fromLTWH(
            tx2 - textW / 2,
            ty2 - textH / 2,
            textW,
            textH,
          );
        }
      }
      placedPercents.add(percentRect);
      percentCenters.add(percentRect.center);

      final percent = (slices[i].value * 100 / total).toStringAsFixed(0) + '%';

      percentWidgets.add(
        Positioned(
          left: percentRect.left,
          top: percentRect.top,
          width: percentRect.width,
          height: percentRect.height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                percent,
                textAlign: TextAlign.center,
                style: TextStyle(
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 3
                    ..color = Colors.black,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox.shrink(),
              Text(
                percent,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ピル文言
    final pillTR = sTR != null ? _tagFromSliceLabel(sTR.label) : null;
    final pillBR = sBR != null ? _tagFromSliceLabel(sBR.label) : null;
    final pillBL = sBL != null ? _tagFromSliceLabel(sBL.label) : null;
    final pillTL = sTL != null ? _tagFromSliceLabel(sTL.label) : null;

    // まずベース（円）を描く
    final base = SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 円グラフ（最背面）
          Positioned.fill(
            left: safePad,
            right: safePad,
            top: safePad,
            bottom: safePad,
            child: CustomPaint(painter: _PiePainter(paintEntries, colors)),
          ),
          // ％
          ...percentWidgets,
          // 四隅（最前面）
          if (sTR != null)
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.all(m.pad),
                child: _cornerColumn(
                  slice: sTR,
                  pill: pillTR,
                  imgKey: _imgKeyTR,
                  pillKey: _pillKeyTR,
                ),
              ),
            ),
          if (sBR != null)
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: EdgeInsets.all(m.pad),
                child: _cornerColumn(
                  slice: sBR,
                  pill: pillBR,
                  imgKey: _imgKeyBR,
                  pillKey: _pillKeyBR,
                ),
              ),
            ),
          if (sBL != null)
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: EdgeInsets.all(m.pad),
                child: _cornerColumn(
                  slice: sBL,
                  pill: pillBL,
                  imgKey: _imgKeyBL,
                  pillKey: _pillKeyBL,
                ),
              ),
            ),
          if (sTL != null)
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: EdgeInsets.all(m.pad),
                child: _cornerColumn(
                  slice: sTL,
                  pill: pillTL,
                  imgKey: _imgKeyTL,
                  pillKey: _pillKeyTL,
                ),
              ),
            ),
        ],
      ),
    );

    // 打牌画像中心 or 「スルー」ピル中心
    Offset? fromTR = _centerOf(_imgKeyTR);
    Offset? fromBR = _centerOf(_imgKeyBR);
    Offset? fromBL = _centerOf(_imgKeyBL);
    Offset? fromTL = _centerOf(_imgKeyTL);

    // スルー文字だけの場合はピルを起点に置き換え
    if (sTR != null &&
        sTR.label.startsWith('スルー') &&
        (sTR.tileId == null || sTR.tileId!.isEmpty)) {
      fromTR = _centerOf(_pillKeyTR) ?? fromTR;
    }
    if (sBR != null &&
        sBR.label.startsWith('スルー') &&
        (sBR.tileId == null || sBR.tileId!.isEmpty)) {
      fromBR = _centerOf(_pillKeyBR) ?? fromBR;
    }
    if (sBL != null &&
        sBL.label.startsWith('スルー') &&
        (sBL.tileId == null || sBL.tileId!.isEmpty)) {
      fromBL = _centerOf(_pillKeyBL) ?? fromBL;
    }
    if (sTL != null &&
        sTL.label.startsWith('スルー') &&
        (sTL.tileId == null || sTL.tileId!.isEmpty)) {
      fromTL = _centerOf(_pillKeyTL) ?? fromTL;
    }

    // 初回に中心が取れない場合は1度だけ再描画
    final needRetry =
        (sTR != null && fromTR == null) ||
        (sBR != null && fromBR == null) ||
        (sBL != null && fromBL == null) ||
        (sTL != null && fromTL == null);

    if (needRetry && !_postFrameRequested) {
      _postFrameRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _postFrameRequested = false);
      });
    }

    // % の中心
    final to0 = percentCenters.isNotEmpty ? percentCenters[0] : null;
    final to1 = percentCenters.length >= 2 ? percentCenters[1] : null;
    final to2 = percentCenters.length >= 3 ? percentCenters[2] : null;

    final toEtc = (idxEtc >= 0 && idxEtc < percentCenters.length)
        ? percentCenters[idxEtc]
        : (twoOnly && percentCenters.length >= 2 ? percentCenters[1] : null);

    // リーダー線（起点→％文字）
    final leaderLines = <({Offset from, Offset to})>[];
    if (sTR != null && fromTR != null && to0 != null)
      leaderLines.add((from: fromTR, to: to0));
    if (sBR != null && fromBR != null && to1 != null)
      leaderLines.add((from: fromBR, to: to1));
    if (sBL != null && fromBL != null && to2 != null)
      leaderLines.add((from: fromBL, to: to2));
    if (sTL != null && fromTL != null && toEtc != null)
      leaderLines.add((from: fromTL, to: toEtc));

    // ==== レイヤー順序 ====
    // [最背面] 円グラフ → リーダー線 → ％文字 → 四隅 [最前面]
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 円グラフ（最背面）
          Positioned.fill(
            left: safePad,
            right: safePad,
            top: safePad,
            bottom: safePad,
            child: CustomPaint(painter: _PiePainter(paintEntries, colors)),
          ),

          // ％文字の背面にリーダー線を描画（円の前面）
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _CornerLeadersToPercentPainter(
                  lines: leaderLines,
                  strokeColor: Colors.cyanAccent,
                ),
              ),
            ),
          ),

          // ％文字（リーダー線の前面）
          ...percentWidgets,

          // 四隅（最前面）
          if (sTR != null)
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.all(m.pad),
                child: _cornerColumn(
                  slice: sTR,
                  pill: pillTR,
                  imgKey: _imgKeyTR,
                  pillKey: _pillKeyTR,
                ),
              ),
            ),
          if (sBR != null)
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: EdgeInsets.all(m.pad),
                child: _cornerColumn(
                  slice: sBR,
                  pill: pillBR,
                  imgKey: _imgKeyBR,
                  pillKey: _pillKeyBR,
                ),
              ),
            ),
          if (sBL != null)
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: EdgeInsets.all(m.pad),
                child: _cornerColumn(
                  slice: sBL,
                  pill: pillBL,
                  imgKey: _imgKeyBL,
                  pillKey: _pillKeyBL,
                ),
              ),
            ),
          if (sTL != null)
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: EdgeInsets.all(m.pad),
                child: _cornerColumn(
                  slice: sTL,
                  pill: pillTL,
                  imgKey: _imgKeyTL,
                  pillKey: _pillKeyTL,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PiePainter extends CustomPainter {
  final List<MapEntry<String, int>> data;
  final List<Color> colors;
  _PiePainter(this.data, this.colors);

  static Color _fallbackColor(int i) {
    const palette = [Colors.red, Colors.blue, Colors.yellow, Colors.green];
    return palette[i % palette.length];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final total = data.fold<int>(0, (s, e) => s + e.value);
    if (total == 0) return;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final center = Offset(cx, cy);

    final radius = math.min(size.width, size.height) / 2 - 2;
    final arcRect = Rect.fromCircle(center: center, radius: radius);

    // 立体感の陰影
    final Shader shade = RadialGradient(
      center: const Alignment(-0.35, 0.35),
      radius: 0.95,
      colors: [Colors.black.withOpacity(0.12), Colors.transparent],
      stops: const [0.0, 1.0],
    ).createShader(arcRect);

    // セグメント塗り
    var start = -math.pi / 2;
    for (int i = 0; i < data.length; i++) {
      final e = data[i];
      final sweep = (e.value / total) * 2 * math.pi;
      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = (i < colors.length) ? colors[i] : _fallbackColor(i);

      canvas.drawArc(arcRect, start, sweep, true, fill);

      canvas.saveLayer(arcRect.inflate(2), Paint());
      final shadowPaint = Paint()..shader = shade;
      canvas.drawArc(arcRect, start, sweep, true, shadowPaint);
      canvas.restore();

      start += sweep;
    }

    // 外周と区切り線
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.cyanAccent
      ..isAntiAlias = true;

    canvas.drawCircle(center, radius, border);

    start = -math.pi / 2;
    for (final e in data) {
      final sweep = (e.value / total) * 2 * math.pi;
      final p1 = Offset(
        cx + radius * math.cos(start),
        cy + radius * math.sin(start),
      );
      canvas.drawLine(center, p1, border);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter old) {
    if (old.data.length != data.length) return true;
    if (old.colors.length != colors.length) return true;
    for (var i = 0; i < data.length; i++) {
      if (old.data[i].key != data[i].key ||
          old.data[i].value != data[i].value) {
        return true;
      }
    }
    for (var i = 0; i < colors.length; i++) {
      if (old.colors[i] != colors[i]) return true;
    }
    return false;
  }
}

/// 四隅基準点（今回は打牌画像 or 「スルー」ピルの中心） → ％テキスト中心にリーダー線
class _CornerLeadersToPercentPainter extends CustomPainter {
  final List<({Offset from, Offset to})> lines;
  final Color strokeColor;

  _CornerLeadersToPercentPainter({
    required this.lines,
    required this.strokeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (lines.isEmpty) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = strokeColor
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    for (final l in lines) {
      canvas.drawLine(l.from, l.to, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CornerLeadersToPercentPainter old) {
    if (old.lines.length != lines.length) return true;
    if (old.strokeColor != strokeColor) return true;
    for (var i = 0; i < lines.length; i++) {
      final a = lines[i], b = old.lines[i];
      if (a.from != b.from || a.to != b.to) return true;
    }
    return false;
  }
}

/// =====================
/// 回答コメント：集計ラベルごとのタブ表示（円グラフと同じラベル）
/// =====================
class _GroupedAnswerComments extends StatelessWidget {
  final String postId;
  final String postType;
  final String sortKey; // '投稿順' | 'お気に入り数順'
  final bool ascending;
  // 追加：フィルタ
  final String nicknameQuery;
  final String selectedLeague;
  final String selectedRank;

  const _GroupedAnswerComments({
    super.key,
    required this.postId,
    required this.postType,
    required this.sortKey,
    required this.ascending,
    this.nicknameQuery = '',
    this.selectedLeague = '未選択',
    this.selectedRank = '未選択',
  });

  // ランク順（高い→低い）
  static const Map<String, List<String>> leagueRanks = {
    '未選択': ['未選択'],
    '天鳳': ['天鳳位', '十段', '九段', '八段', '七段', '六段', '五段', '四段', '三段', '二段', '初段'],
    '雀魂': [
      '魂天20',
      '魂天19',
      '魂天18',
      '魂天17',
      '魂天16',
      '魂天15',
      '魂天14',
      '魂天13',
      '魂天12',
      '魂天11',
      '魂天10',
      '魂天9',
      '魂天8',
      '魂天7',
      '魂天6',
      '魂天5',
      '魂天4',
      '魂天3',
      '魂天2',
      '魂天1',
      '雀聖3',
      '雀聖2',
      '雀聖1',
      '雀豪3',
      '雀豪2',
      '雀豪1',
      '雀傑3',
      '雀傑2',
      '雀傑1',
      '雀士3',
      '雀士2',
      '雀士1',
      '初心3',
      '初心2',
      '初心1',
    ],
    '日本プロ麻雀連盟': [
      'A1リーグ',
      'A2リーグ',
      'B1リーグ',
      'B2リーグ',
      'C1リーグ',
      'C2リーグ',
      'C3リーグ',
      'D1リーグ',
      'D2リーグ',
      'D3リーグ',
      'E1リーグ',
      'E2リーグ',
      'E3リーグ',
    ],
    '最高位戦日本プロ麻雀協会': [
      'A1リーグ',
      'A2リーグ',
      'B1リーグ',
      'B2リーグ',
      'C1リーグ',
      'C2リーグ',
      'C3リーグ',
      'D1リーグ',
      'D2リーグ',
      'D3リーグ',
    ],
    '日本プロ麻雀協会': [
      'A1リーグ',
      'A2リーグ',
      'B1リーグ',
      'B2リーグ',
      'C1リーグ',
      'C2リーグ',
      'C3リーグ',
      'D1リーグ',
      'D2リーグ',
      'D3リーグ',
      'E1リーグ',
      'E2リーグ',
      'E3リーグ',
      'F1リーグ',
    ],
    '麻将連合': ['μリーグ', 'μ2リーグ'],
    'RMU': [
      'A1リーグ',
      'A2リーグ',
      'B1リーグ',
      'B2リーグ',
      'C1リーグ',
      'C2リーグ',
      'C3リーグ',
      'D1リーグ',
      'D2リーグ',
      'D3リーグ',
    ],
  };

  List<String> _orderFor(String league) => leagueRanks[league] ?? const ['未選択'];

  String _pairKeyFromList(List list) {
    final arr = list
        .map((e) => e?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .cast<String>()
        .toList();
    if (arr.length < 2) return '';
    arr.sort();
    return '${arr[0]}+${arr[1]}';
  }

  String _buildLabel(Map<String, dynamic> a) {
    final tile = (a['tile'] as String?)?.trim() ?? '';

    if (postType == 'リーチ判断') {
      final r = a['reach'];
      if (r is bool && tile.isNotEmpty) {
        final decision = r ? 'する' : 'しない';
        return '$decision・$tile';
      }
      return '';
    }

    if (postType == '副露判断') {
      final c = a['call'];
      final pair = _pairKeyFromList((a['callTiles'] as List?) ?? const []);
      final pairText = (c == true)
          ? (pair.isNotEmpty ? '[${pair}]' : '[不明]')
          : '[-]';
      final t = tile.isNotEmpty ? tile : '(未選択)';
      if (c is bool) {
        final head = c ? '鳴く' : 'スルー';
        return '$head・$pairText・$t';
      }
      return '';
    }

    return tile.isNotEmpty ? tile : '';
  }

  /// タブラベル生成（塗りピル＋縦に収めるサイズ）
  Widget _buildTabLabel(String label) {
    Widget pillFilled(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.cyanAccent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          height: 1.2,
        ),
        softWrap: false,
      ),
    );

    if (label == 'その他') {
      return pillFilled('その他');
    }

    final parts = label.split('・');

    if (postType == 'リーチ判断' && parts.length == 2) {
      final decision = parts[0];
      final tile = parts[1];
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 120),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            pillFilled(decision),
            const SizedBox(height: 2),
            Image.asset(
              'assets/tiles/$tile.png',
              width: 26,
              height: 38,
              fit: BoxFit.contain,
            ),
          ],
        ),
      );
    }

    if (postType == '副露判断' && parts.length == 3) {
      final head = parts[0];
      final pairText = parts[1];
      final tile = parts[2];

      final pairTiles = pairText
          .replaceAll('[', '')
          .replaceAll(']', '')
          .split('+')
          .where((e) => e.isNotEmpty)
          .toList();

      if (head == '鳴く') {
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 190),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  pillFilled('鳴く'),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final id in pairTiles)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: Image.asset(
                            'assets/tiles/$id.png',
                            width: 18,
                            height: 27,
                            fit: BoxFit.contain,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              if (tile != '(未選択)') ...[
                const SizedBox(width: 6),
                Image.asset(
                  'assets/tiles/$tile.png',
                  width: 24,
                  height: 36,
                  fit: BoxFit.contain,
                ),
              ],
            ],
          ),
        );
      }

      return pillFilled('スルー');
    }

    return Image.asset(
      'assets/tiles/$label.png',
      width: 26,
      height: 38,
      fit: BoxFit.contain,
    );
  }

  Future<({String nickname, String affiliationsText})> _loadUserMeta(
    String uid,
  ) async {
    if (uid.isEmpty) return (nickname: '匿名', affiliationsText: '所属不明');
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = snap.data() ?? {};
      final nickname = (data['nickname'] as String?)?.trim();
      final rawAffs = (data['affiliations'] as List?) ?? const [];
      final parts = <String>[];
      for (final e in rawAffs) {
        if (e is Map<String, dynamic>) {
          final aff = (e['affiliation'] ?? '').toString().trim();
          final rank = (e['rank'] ?? '').toString().trim();
          if (aff.isNotEmpty && rank.isNotEmpty) {
            parts.add('$aff($rank)');
          } else if (aff.isNotEmpty) {
            parts.add(aff);
          }
        }
      }
      return (
        nickname: nickname?.isNotEmpty == true ? nickname! : '匿名',
        affiliationsText: parts.isEmpty ? '所属不明' : parts.join('・'),
      );
    } catch (_) {
      return (nickname: '匿名', affiliationsText: '所属不明');
    }
  }

  // 指定リーグで「minRank 以上」かどうか判定
  bool _rankAtLeast(String affs, String league, String minRank) {
    if (league == '未選択' || minRank == '未選択') return true;
    final order = _orderFor(league);
    final minIdx = order.indexOf(minRank);
    if (minIdx < 0) return true;

    final pattern = RegExp(RegExp.escape(league) + r'\(([^)]+)\)');
    final match = pattern.firstMatch(affs);
    if (match == null) return false;
    final userRank = match.group(1)!;
    final userIdx = order.indexOf(userRank);
    if (userIdx < 0) return false;

    // インデックス小ほど上位 → userIdx <= minIdx なら「以上」
    return userIdx <= minIdx;
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('posts')
        .doc(postId)
        .collection('answers')
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;
        final entries = <Map<String, dynamic>>[];
        for (final d in docs) {
          final data = d.data();
          final label = _buildLabel(data);
          final comment = (data['comment'] as String?)?.trim() ?? '';
          if (label.isEmpty || comment.isEmpty) continue;
          entries.add({
            'label': label,
            'comment': comment,
            'createdAt': data['createdAt'],
            'likes': (data['likes'] ?? 0) as int,
            'userId': data['userId'],
          });
        }

        if (entries.isEmpty) {
          return const Text(
            'まだコメントがありません',
            style: TextStyle(color: Colors.white70),
          );
        }

        final Map<String, int> counts = {};
        for (final e in entries) {
          counts.update(e['label'] as String, (v) => v + 1, ifAbsent: () => 1);
        }

        final sortedLabels = counts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final topLabels = sortedLabels.take(3).map((e) => e.key).toList();
        final hasOthers = counts.length > topLabels.length;
        final labels = <String>[...topLabels, if (hasOthers) 'その他'];

        // タブを作成（仕切り線なし）
        final tabCount = labels.length;
        final tabWidgets = List<Tab>.generate(tabCount, (i) {
          return Tab(height: 68, child: _buildTabLabel(labels[i]));
        });

        return DefaultTabController(
          length: tabCount,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: Colors.cyanAccent,
                  labelPadding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  labelColor: Colors.cyanAccent,
                  unselectedLabelColor: Colors.white70,
                  tabs: tabWidgets,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 260,
                child: TabBarView(
                  children: labels.map((tabLabel) {
                    final list = (tabLabel == 'その他')
                        ? entries
                              .where((e) => !topLabels.contains(e['label']))
                              .toList()
                        : entries.where((e) => e['label'] == tabLabel).toList();

                    // ソート
                    list.sort((a, b) {
                      int cmp;
                      if (sortKey == 'お気に入り数順') {
                        final la = (a['likes'] as int);
                        final lb = (b['likes'] as int);
                        cmp = la.compareTo(lb);
                      } else {
                        final ta = a['createdAt'];
                        final tb = b['createdAt'];
                        final sa = (ta is Timestamp)
                            ? ta.toDate().millisecondsSinceEpoch
                            : 0;
                        final sb = (tb is Timestamp)
                            ? tb.toDate().millisecondsSinceEpoch
                            : 0;
                        cmp = sa.compareTo(sb);
                      }
                      return ascending ? cmp : -cmp;
                    });

                    return ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final e = list[i];
                        final targetUid = ((e['userId'] as String?) ?? '')
                            .trim();
                        return FutureBuilder<
                          ({String nickname, String affiliationsText})
                        >(
                          future: _loadUserMeta(targetUid),
                          builder: (context, userSnap) {
                            final nickname = userSnap.data?.nickname ?? '匿名';
                            final affs =
                                userSnap.data?.affiliationsText ?? '所属不明';

                            // フィルタ（ニックネーム/所属・ランクの部分一致＋「最高ランク（以上）」）
                            final nq = nicknameQuery.trim();
                            if (nq.isNotEmpty && !nickname.contains(nq)) {
                              return const SizedBox.shrink();
                            }
                            if (selectedLeague != '未選択' &&
                                !affs.contains(selectedLeague)) {
                              return const SizedBox.shrink();
                            }
                            if (selectedLeague != '未選択' &&
                                selectedRank != '未選択' &&
                                !_rankAtLeast(
                                  affs,
                                  selectedLeague,
                                  selectedRank,
                                )) {
                              return const SizedBox.shrink();
                            }

                            return Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.25),
                                border: Border.all(color: Colors.white24),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 追加: その他タブだけ、ラベルと同じデザインの選択肢画像を左に表示
                                  if (tabLabel == 'その他')
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        right: 8.0,
                                      ),
                                      child: _buildTabLabel(
                                        (e['label'] as String?) ?? '',
                                      ),
                                    ),

                                  // 左：本文＋投稿者
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e['comment'] as String,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            height: 1.35,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '$nickname / $affs',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // 右：丸いハートいいね（回答単位）
                                  if (targetUid.isNotEmpty)
                                    LikeHeartButton(
                                      postId: postId,
                                      answerUserId: targetUid,
                                      size: 36,
                                      borderColor: Colors.white24,
                                    )
                                  else
                                    const SizedBox.shrink(),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// ===== 回答いいね（answers.likes を ±1 だけ更新） =====
/// サブコレは使わず、users/{myUid}.likedAnswers で二重押し防止
class LikeHeartButton extends StatefulWidget {
  final String postId;
  final String answerUserId; // answers/{answerUserId}
  final double size;
  final Color borderColor;

  const LikeHeartButton({
    super.key,
    required this.postId,
    required this.answerUserId,
    this.size = 36,
    this.borderColor = Colors.white24,
  });

  @override
  State<LikeHeartButton> createState() => _LikeHeartButtonState();
}

class _LikeHeartButtonState extends State<LikeHeartButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || myUid == widget.answerUserId) {
      return _disabledHeart(widget.size, widget.borderColor);
    }

    final db = FirebaseFirestore.instance;
    final answerRef = db
        .collection('posts')
        .doc(widget.postId)
        .collection('answers')
        .doc(widget.answerUserId);
    final meRef = db.collection('users').doc(myUid);
    final targetRef = db.collection('users').doc(widget.answerUserId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: meRef.snapshots(),
      builder: (context, snap) {
        final likedMap =
            (snap.data?.data()?['likedAnswers'] as Map?)
                ?.cast<String, dynamic>() ??
            const {};
        final key = '${widget.postId}__${widget.answerUserId}';
        final liked = likedMap[key] == true;
        final color = liked ? Colors.pinkAccent : Colors.white70;

        return Opacity(
          opacity: _busy ? 0.6 : 1.0,
          child: GestureDetector(
            onTap: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await db.runTransaction((tx) async {
                        final ansSnap = await tx.get(answerRef);
                        final meSnap = await tx.get(meRef);
                        final targetSnap = await tx.get(targetRef);

                        final currLikes =
                            (ansSnap.data()?['likes'] ?? 0) as int;
                        final currLiked =
                            ((meSnap.data()?['likedAnswers'] as Map?)
                                    ?.cast<String, dynamic>() ??
                                const {})[key] ==
                            true;

                        final wantLike = !currLiked;

                        // answers.likes を±1（0未満にしない）
                        final nextAnsLikes = wantLike
                            ? currLikes + 1
                            : (currLikes > 0 ? currLikes - 1 : 0);
                        tx.update(answerRef, {'likes': nextAnsLikes});

                        // users.likesReceived を±1（ターゲット側）
                        final lr =
                            (targetSnap.data()?['likesReceived'] ?? 0) as int;
                        final nextLR = wantLike
                            ? lr + 1
                            : (lr > 0 ? lr - 1 : 0);
                        tx.set(targetRef, {
                          'likesReceived': nextLR,
                        }, SetOptions(merge: true));

                        // 自分の押下履歴（解除時は false にして削除扱い）
                        final map = Map<String, dynamic>.from(
                          ((meSnap.data()?['likedAnswers'] as Map?)
                                  ?.cast<String, dynamic>() ??
                              const {}),
                        );
                        map[key] = wantLike; // true or false を格納
                        tx.set(meRef, {
                          'likedAnswers': map,
                        }, SetOptions(merge: true));
                      });
                    } catch (e) {
                      final msg = e is FirebaseException
                          ? e.code
                          : e.toString();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('いいねの更新に失敗しました ($msg)')),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.30),
                border: Border.all(color: widget.borderColor, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(
                liked ? Icons.favorite : Icons.favorite_border,
                color: color,
                size: (widget.size * 0.52).clamp(14, 22),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _disabledHeart(double size, Color borderColor) {
    return Opacity(
      opacity: 0.6,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.30),
          border: Border.all(color: borderColor, width: 1),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.favorite_border,
          color: Colors.white38,
          size: (size * 0.52).clamp(14, 22),
        ),
      ),
    );
  }
}

/// ===== コメント用のソートモーダル =====
class _CommentSortResult {
  final String sortKey; // '投稿順' | 'お気に入り数順'
  final bool ascending;
  final String nicknameQuery;
  final String selectedLeague;
  final String selectedRank;

  _CommentSortResult({
    required this.sortKey,
    required this.ascending,
    required this.nicknameQuery,
    required this.selectedLeague,
    required this.selectedRank,
  });
}

class _CommentSortSheet extends StatefulWidget {
  final String sortKey;
  final bool ascending;
  final String nicknameQuery;
  final String selectedLeague;
  final String selectedRank;

  const _CommentSortSheet({
    super.key,
    required this.sortKey,
    required this.ascending,
    this.nicknameQuery = '',
    this.selectedLeague = '未選択',
    this.selectedRank = '未選択',
  });

  @override
  State<_CommentSortSheet> createState() => _CommentSortSheetState();
}

class _CommentSortSheetState extends State<_CommentSortSheet> {
  late String _sortKey;
  late bool _ascending;
  late TextEditingController _nickCtrl;
  late String _selectedLeague;
  late String _selectedRank;

  static const Map<String, List<String>> leagueRanks = {
    '未選択': ['未選択'],
    '天鳳': [
      '未選択',
      '天鳳位',
      '十段',
      '九段',
      '八段',
      '七段',
      '六段',
      '五段',
      '四段',
      '三段',
      '二段',
      '初段',
    ],
    '雀魂': [
      '未選択',
      '魂天20',
      '魂天19',
      '魂天18',
      '魂天17',
      '魂天16',
      '魂天15',
      '魂天14',
      '魂天13',
      '魂天12',
      '魂天11',
      '魂天10',
      '魂天9',
      '魂天8',
      '魂天7',
      '魂天6',
      '魂天5',
      '魂天4',
      '魂天3',
      '魂天2',
      '魂天1',
      '雀聖3',
      '雀聖2',
      '雀聖1',
      '雀豪3',
      '雀豪2',
      '雀豪1',
      '雀傑3',
      '雀傑2',
      '雀傑1',
      '雀士3',
      '雀士2',
      '雀士1',
      '初心3',
      '初心2',
      '初心1',
    ],
    '日本プロ麻雀連盟': [
      '未選択',
      'A1リーグ',
      'A2リーグ',
      'B1リーグ',
      'B2リーグ',
      'C1リーグ',
      'C2リーグ',
      'C3リーグ',
      'D1リーグ',
      'D2リーグ',
      'D3リーグ',
      'E1リーグ',
      'E2リーグ',
      'E3リーグ',
    ],
    '最高位戦日本プロ麻雀協会': [
      '未選択',
      'A1リーグ',
      'A2リーグ',
      'B1リーグ',
      'B2リーグ',
      'C1リーグ',
      'C2リーグ',
      'C3リーグ',
      'D1リーグ',
      'D2リーグ',
      'D3リーグ',
    ],
    '日本プロ麻雀協会': [
      '未選択',
      'A1リーグ',
      'A2リーグ',
      'B1リーグ',
      'B2リーグ',
      'C1リーグ',
      'C2リーグ',
      'C3リーグ',
      'D1リーグ',
      'D2リーグ',
      'D3リーグ',
      'E1リーグ',
      'E2リーグ',
      'E3リーグ',
      'F1リーグ',
    ],
    '麻将連合': ['未選択', 'μリーグ', 'μ2リーグ'],
    'RMU': [
      '未選択',
      'A1リーグ',
      'A2リーグ',
      'B1リーグ',
      'B2リーグ',
      'C1リーグ',
      'C2リーグ',
      'C3リーグ',
      'D1リーグ',
      'D2リーグ',
      'D3リーグ',
    ],
  };

  List<String> get _rankOptions =>
      leagueRanks[_selectedLeague] ?? const ['未選択'];

  @override
  void initState() {
    super.initState();
    _sortKey = widget.sortKey;
    _ascending = widget.ascending;
    _nickCtrl = TextEditingController(text: widget.nicknameQuery);
    _selectedLeague = widget.selectedLeague;
    _selectedRank = widget.selectedRank;
  }

  void _apply() {
    Navigator.pop(
      context,
      _CommentSortResult(
        sortKey: _sortKey,
        ascending: _ascending,
        nicknameQuery: _nickCtrl.text,
        selectedLeague: _selectedLeague,
        selectedRank: _selectedRank,
      ),
    );
  }

  void _reset() {
    setState(() {
      _sortKey = '投稿順';
      _ascending = false;
      _nickCtrl.text = '';
      _selectedLeague = '未選択';
      _selectedRank = '未選択';
    });
  }

  @override
  Widget build(BuildContext context) {
    final leagues = leagueRanks.keys.toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text(
                  '表示設定',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _reset,
                  icon: const Icon(
                    Icons.refresh,
                    color: Colors.cyanAccent,
                    size: 16,
                  ),
                  label: const Text(
                    'リセット',
                    style: TextStyle(color: Colors.cyanAccent),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ニックネーム検索
            TextField(
              controller: _nickCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, color: Colors.cyanAccent),
                hintText: 'ニックネームで検索',
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
              ),
            ),

            const SizedBox(height: 12),

            // ソート＆昇順降順
            Row(
              children: [
                Expanded(
                  child: _boxedDropdown<String>(
                    label: 'ソート',
                    value: _sortKey,
                    items: const ['投稿順', 'お気に入り数順'],
                    onChanged: (v) => setState(() => _sortKey = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _boxedDropdown<bool>(
                    label: '並び',
                    value: _ascending,
                    items: const [true, false],
                    itemTextBuilder: (v) => v ? '昇順' : '降順',
                    onChanged: (v) => setState(() => _ascending = v!),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 所属／ランクフィルタ（ランクは「以上」）
            Row(
              children: [
                Expanded(
                  child: _boxedDropdown<String>(
                    label: '所属',
                    value: _selectedLeague,
                    items: leagues,
                    onChanged: (v) {
                      setState(() {
                        _selectedLeague = v!;
                        _selectedRank = '未選択';
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _boxedDropdown<String>(
                    label: '最高ランク',
                    value: _selectedRank,
                    items: _rankOptions,
                    onChanged: (v) => setState(() => _selectedRank = v!),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('適用する'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                ),
                onPressed: _apply,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boxedDropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
    String Function(T)? itemTextBuilder,
  }) {
    String textOf(T v) =>
        itemTextBuilder != null ? itemTextBuilder(v) : v.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 6),
        DropdownButtonHideUnderline(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1114),
              border: Border.all(color: Colors.cyanAccent),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF0B1114),
              iconEnabledColor: Colors.cyanAccent,
              items: items
                  .map(
                    (e) => DropdownMenuItem<T>(
                      value: e,
                      child: Text(
                        textOf(e),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

/// =====================
/// Detail: どれを切る？ 牌列（等幅・下端揃え・水色下線で選択）
/// =====================
class _DetailAnswerTileRow extends StatelessWidget {
  final List<String> tiles;
  final String? selected;
  final ValueChanged<String> onSelected;

  const _DetailAnswerTileRow({
    required this.tiles,
    required this.selected,
    required this.onSelected,
  });

  static String _asset(String id) => 'assets/tiles/$id.png';

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, c) {
        // 横幅から 1 枚の幅・高さを決めて、全体の高さを先に確保
        final count = tiles.length;
        final tileW = c.maxWidth / (count == 0 ? 1 : count);
        final tileH = tileW * 3 / 2;

        return SizedBox(
          width: c.maxWidth,
          height: tileH,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end, // 下端そろえ
            children: tiles.map((tileId) {
              final isSelected = selected == tileId;
              return SizedBox(
                width: tileW,
                child: GestureDetector(
                  onTap: () => onSelected(tileId),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isSelected
                              ? Colors.cyanAccent
                              : Colors.transparent,
                          width: 3, // 水色アンダーライン
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
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(
                              tileId,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.cyanAccent
                                    : Colors.white,
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
          ),
        );
      },
    );
  }
}

/// Homeでも使っている「手牌＋右側に副露」を1行で描画する帯
class _TileStrip extends StatelessWidget {
  final List<String> tiles;
  final List<List<String>>? meldRestoreGroups; // 手牌から除去する実牌
  final List<List<String>>? meldDisplayGroups; // 右側に表示する displayTiles 群

  const _TileStrip({
    required this.tiles,
    this.meldRestoreGroups,
    this.meldDisplayGroups,
  });

  static String _asset(String id) => 'assets/tiles/$id.png';

  @override
  Widget build(BuildContext context) {
    final hand = (meldRestoreGroups == null || meldRestoreGroups!.isEmpty)
        ? tiles
        : _applyMeldRemovals(tiles, meldRestoreGroups!);
    final groups = meldDisplayGroups ?? const <List<String>>[];

    if (hand.isEmpty && groups.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, c) {
        // 手牌＋副露の総牌枚数に合わせて自動サイズ
        final handCount = hand.length;
        final meldTilesTotal = groups.fold<int>(0, (sum, g) => sum + g.length);
        final gapCount = groups.isEmpty ? 0 : groups.length;
        const gapUnit = 0.6; // 牌の 0.6 枚ぶんの隙間
        final totalUnits = handCount + meldTilesTotal + (gapCount * gapUnit);

        final tileW = c.maxWidth / (totalUnits == 0 ? 1 : totalUnits);
        final height = tileW * 3 / 2;

        Widget tileBox(String id) => SizedBox(
          width: tileW,
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Image.asset(
                _asset(id),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(id, style: const TextStyle(color: Colors.white)),
                ),
              ),
            ),
          ),
        );

        Widget gapBox() => SizedBox(width: tileW * gapUnit);

        final children = <Widget>[];
        for (final id in hand) {
          children.add(tileBox(id));
        }
        for (int gi = 0; gi < groups.length; gi++) {
          children.add(gapBox());
          for (final id in groups[gi]) {
            children.add(tileBox(id));
          }
        }

        return SizedBox(
          width: c.maxWidth,
          height: height,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: children,
            ),
          ),
        );
      },
    );
  }
}
