import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../screens/detail_page.dart';
import '../widgets/base_scaffold.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AudioPlayer _player = AudioPlayer();

  // ---- Users 取得の簡易キャッシュ（同一 userId を何度も読まない）----
  static final Map<String, Future<_UserProfile?>> _profileCache = {};

  Future<_UserProfile?> _getUserProfile(String userId) {
    if (userId.isEmpty) return Future.value(null);
    if (_profileCache.containsKey(userId)) return _profileCache[userId]!;
    final fut = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get()
        .then((snap) => snap.exists ? _UserProfile.fromMap(snap.data()!) : null)
        .catchError((_) => null);
    _profileCache[userId] = fut;
    return fut;
  }

  Future<void> _playSE() async {
    await _player.play(AssetSource('sounds/cyber_click.mp3'));
  }

  /// 並び順どおりの postId リスト(navPostIds) と
  /// 現在タップしたインデックス(currentIndex) を DetailPage に渡す
  void _navigateToDetail(
    BuildContext context,
    String postId,
    List<String> navPostIds,
    int currentIndex,
  ) async {
    await _playSE();
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => DetailPage(
          postId: postId,
          source: 'home',
          currentIndex: 0, // 0 = Homeタブを光らせる
          navContext: {
            'sortKey': _sortKey,
            'ascending': _ascending,
            'selectedLeague': _selectedLeague,
            'selectedRank': _selectedRank,
            'nicknameQuery': _nicknameQuery,
            'selectedRule': _selectedRule,
            'selectedPostType': _selectedPostType,
            'navPostIds': navPostIds,
          },
          // DetailPage 側でそのまま前/次ナビに使う用
          navIds: navPostIds,
          navIndex: currentIndex,
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  // ===== ソート & フィルタ & 検索 状態 =====
  String _sortKey = '投稿順'; // or 'お気に入り数順'
  bool _ascending = false; // false=降順（新しい・多い順）
  String _selectedLeague = '未選択';
  String _selectedRank = '未選択';
  String _nicknameQuery = '';

  // ルール / 問題タイプのプルダウン用
  String _selectedRule = '未選択';
  String _selectedPostType = '未選択';

  static const List<String> ruleOptions = [
    '未選択',
    '四麻・半荘',
    '四麻・東風',
    '三麻',
  ];

  static const List<String> postTypeOptions = [
    '未選択',
    '牌効率',
    '押し引き',
    'リーチ判断',
    '副露判断',
    'アシスト',
    'その他',
  ];

  // リーグ→段位表
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

  // rank の序列（高いほど小さい index）を返す（見つからなければ大きい値）
  int _rankOrderIndex(String league, String rank) {
    final list = leagueRanks[league];
    if (list == null) return 1 << 30;
    final idx = list.indexOf(rank);
    if (idx < 0) return 1 << 30;
    return idx == 0 ? (1 << 29) : idx; // '未選択' を最下位
  }

  // affiliations の中から、その league の rank を取得（最も高いランク＝最小 index）
  String? _extractRankForLeague(
    List<Map<String, dynamic>>? affiliations,
    String league,
  ) {
    if (affiliations == null || affiliations.isEmpty) return null;
    String? best;
    var bestIdx = 1 << 30;
    for (final a in affiliations) {
      final aff = a['affiliation']?.toString();
      final rank = a['rank']?.toString();
      if (aff == league && rank != null && rank.isNotEmpty) {
        final idx = _rankOrderIndex(league, rank);
        if (idx < bestIdx) {
          bestIdx = idx;
          best = rank;
        }
      }
    }
    return best;
  }

  // affiliations(List<Map<String,String>>) → "A(段位)・B(段位)"
  String _stringifyAffiliations(dynamic affListDyn) {
    if (affListDyn is! List) return '';
    final List<String> parts = [];
    for (final a in affListDyn) {
      if (a is Map) {
        final aff = a['affiliation']?.toString();
        final rank = a['rank']?.toString();
        if (aff != null && aff.isNotEmpty) {
          parts.add(rank != null && rank.isNotEmpty ? '$aff($rank)' : aff);
        }
      }
    }
    return parts.join('・');
  }

  // RichText（1行目: ルール/タイプ、2行目: 名前/所属/最高ランク）
  Widget _buildMetaRichText({
    required String ruleType,
    required String postType,
    required String userName,
    required String affiliations,
    required String? highestRank,
  }) {
    final line2 = [
      if (userName.isNotEmpty) userName,
      if (affiliations.isNotEmpty) affiliations,
      if (highestRank != null && highestRank.isNotEmpty) highestRank,
    ].join(' / ');

    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.white70, fontSize: 13),
        children: [
          if (ruleType.isNotEmpty || postType.isNotEmpty)
            TextSpan(
              text: [ruleType, postType].where((e) => e.isNotEmpty).join(' / '),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          if (ruleType.isNotEmpty || postType.isNotEmpty)
            const TextSpan(text: '\n'),
          TextSpan(
            text: line2,
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Future<Map<String, _UserProfile?>> _loadProfiles(Set<String> userIds) async {
    final entries = await Future.wait(
      userIds.map((id) async {
        final p = await _getUserProfile(id);
        return MapEntry(id, p);
      }),
    );
    return Map<String, _UserProfile?>.fromEntries(entries);
  }

  // 右上ボタン → モーダルを開いて選択値を受け取り反映
  Future<void> _openControlsSheet() async {
    final rankOptions = leagueRanks[_selectedLeague] ?? const ['未選択'];
    final result = await showModalBottomSheet<_ControlsResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B1114),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ControlsSheet(
        sortKey: _sortKey,
        ascending: _ascending,
        selectedLeague: _selectedLeague,
        selectedRank: _selectedRank,
        nicknameQuery: _nicknameQuery,
        rankOptions: rankOptions,
        selectedRule: _selectedRule,
        selectedPostType: _selectedPostType,
      ),
    );

    if (result != null) {
      setState(() {
        _sortKey = result.sortKey;
        _ascending = result.ascending;
        _selectedLeague = result.selectedLeague;
        _selectedRank = result.selectedRank;
        _nicknameQuery = result.nicknameQuery;
        _selectedRule = result.selectedRule;
        _selectedPostType = result.selectedPostType;
      });
    }
  }

  // ★ エラー表示（ページ完成扱いなのでローディングではなくメッセージ）
  Widget _buildErrorPage(String message) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.cyan.withOpacity(0.15),
            Colors.black.withOpacity(0.6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.cyanAccent, width: 1.5),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      ),
    );
  }

  // ★ 投稿ゼロ／フィルタでゼロのとき
  Widget _buildMessagePage(String message) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.cyan.withOpacity(0.15),
            Colors.black.withOpacity(0.6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.cyanAccent, width: 1.5),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      ),
    );
  }

  // ★ 実データで描画する部分（ページ完成後にのみ呼ばれる）
  Widget _buildPostListPage(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Map<String, _UserProfile?> profiles,
  ) {
    // フィルタ
    List<QueryDocumentSnapshot<Map<String, dynamic>>> filtered =
        docs.where((doc) {
      final data = doc.data();
      final userId = (data['userId'] ?? '') as String;
      final prof = profiles[userId];

      // ルール / 問題タイプ
      final String ruleType = (data['ruleType'] ?? '').toString();
      final String postType = (data['postType'] ?? '').toString();

      // ニックネーム検索
      final nameSource = prof?.nickname ?? (data['userName'] as String?);
      final userName = (nameSource ?? '').trim();
      if (_nicknameQuery.trim().isNotEmpty) {
        final q = _nicknameQuery.trim().toLowerCase();
        if (!userName.toLowerCase().contains(q)) {
          return false;
        }
      }

      // ルールフィルタ
      if (_selectedRule != '未選択') {
        if (ruleType != _selectedRule) {
          return false;
        }
      }

      // 問題タイプフィルタ
      if (_selectedPostType != '未選択') {
        if (postType != _selectedPostType) {
          return false;
        }
      }

      // 所属・段位フィルタ
      if (_selectedLeague != '未選択') {
        final affiliations = prof?.affiliations;
        final rankStr = _extractRankForLeague(
          affiliations,
          _selectedLeague,
        );

        if (_selectedRank == '未選択') {
          // 所属のみ指定 → そのリーグに所属していない人は除外
          if (rankStr == null) return false;
        } else {
          if (rankStr == null || rankStr.isEmpty) {
            return false;
          }
          final needIdx = _rankOrderIndex(_selectedLeague, _selectedRank);
          final userIdx = _rankOrderIndex(_selectedLeague, rankStr);
          if (userIdx > needIdx) {
            // 「以上」ではない → 除外
            return false;
          }
        }
      }

      return true;
    }).toList();

    // ソート
    filtered.sort((a, b) {
      final da = a.data();
      final db = b.data();
      int cmp;
      if (_sortKey == 'お気に入り数順') {
        final la = (da['likes'] ?? 0) as int;
        final lb = (db['likes'] ?? 0) as int;
        cmp = la.compareTo(lb);
      } else {
        final ta = da['createdAt'];
        final tb = db['createdAt'];
        final va =
            (ta is Timestamp) ? ta.toDate().millisecondsSinceEpoch : 0;
        final vb =
            (tb is Timestamp) ? tb.toDate().millisecondsSinceEpoch : 0;
        cmp = va.compareTo(vb);
      }
      return _ascending ? cmp : -cmp;
    });

    if (filtered.isEmpty) {
      // フィルタで 0 件になった場合は「ページ完成」扱いでメッセージ表示
      return _buildMessagePage('条件に一致する投稿がありません');
    }

    // 現在の並び順の postId リスト
    final navPostIds = filtered.map((d) => d.id).toList();

    // 実際の UI
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.cyan.withOpacity(0.15),
                        Colors.black.withOpacity(0.6),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: Colors.cyanAccent, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.cyanAccent.withOpacity(0.5),
                        blurRadius: 18,
                        spreadRadius: 2,
                        offset: const Offset(4, 6),
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.8),
                        blurRadius: 6,
                        offset: const Offset(-4, -4),
                      ),
                    ],
                  ),
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) => const Divider(
                      color: Colors.cyanAccent,
                      height: 1,
                      thickness: 1,
                      indent: 16,
                      endIndent: 16,
                    ),
                    itemBuilder: (context, index) {
                      final doc = filtered[index];
                      final data = doc.data();

                      // 牌姿（ベース手牌：そのまま表示して二重減算を防ぐ）
                      final List<dynamic> tilesDyn =
                          (data['tiles'] ?? []) as List<dynamic>;
                      final tiles = tilesDyn
                          .map((e) => e?.toString() ?? '')
                          .where((e) => e.isNotEmpty)
                          .toList();

                      // 🔷 meldGroups から右側表示用の displayTiles を抽出
                      final List<List<String>> meldDisplayGroups = [];
                      final mgDyn = data['meldGroups'];
                      if (mgDyn is List) {
                        for (final g in mgDyn) {
                          if (g is Map) {
                            List<dynamic>? dispDyn;
                            if (g['displayTiles'] is List) {
                              dispDyn = g['displayTiles'] as List;
                            } else if (g['tiles'] is List) {
                              // 互換キー（旧データ）
                              dispDyn = g['tiles'] as List;
                            }
                            if (dispDyn != null) {
                              final disp = dispDyn
                                  .map((e) => e?.toString() ?? '')
                                  .where((e) => e.isNotEmpty)
                                  .toList();
                              if (disp.isNotEmpty) {
                                meldDisplayGroups.add(disp);
                              }
                            }
                          }
                        }
                      }

                      // メタ
                      final String ruleType =
                          (data['ruleType'] ?? '').toString();
                      final String postType =
                          (data['postType'] ?? '').toString();
                      final userId = (data['userId'] ?? '') as String;

                      // プロフィール
                      final prof = profiles[userId];
                      final nameSource =
                          prof?.nickname ?? (data['userName'] as String?);
                      final userName =
                          (nameSource ?? '').trim().isNotEmpty
                              ? nameSource!.trim()
                              : '匿名';
                      final affiliations =
                          _stringifyAffiliations(prof?.affiliations);
                      final highestRank = prof?.highestRank;

                      return InkWell(
                        onTap: () => _navigateToDetail(
                          context,
                          doc.id,
                          navPostIds,
                          index,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _TileStrip(
                                tiles: tiles,
                                meldDisplayGroups: meldDisplayGroups,
                                meldScale: 0.68,
                              ),
                              const SizedBox(height: 8),
                              _buildMetaRichText(
                                ruleType: ruleType,
                                postType: postType,
                                userName: userName,
                                affiliations: affiliations,
                                highestRank: highestRank,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        // 右上の小さいボタン（設定モーダルを開く）
        Positioned(
          right: 12,
          top: 12,
          child: Material(
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
                tooltip: 'ソート・フィルタ・検索',
                icon: const Icon(
                  Icons.tune,
                  size: 20,
                  color: Colors.cyanAccent,
                ),
                onPressed: _openControlsSheet,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // 所属変更時に rank が不正になった場合のケア
    final rankOptions = leagueRanks[_selectedLeague] ?? ['未選択'];
    if (!rankOptions.contains(_selectedRank)) {
      _selectedRank = '未選択';
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        final postsLoading =
            snapshot.connectionState == ConnectionState.waiting;

        if (snapshot.hasError) {
          return BaseScaffold(
            title: '投稿一覧',
            currentIndex: 0,
            body: _buildErrorPage('読み込みエラー: ${snapshot.error}'),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        // 投稿 0 件（データは取得済み）
        if (!postsLoading && docs.isEmpty) {
          return BaseScaffold(
            title: '投稿一覧',
            currentIndex: 0,
            body: _buildMessagePage('投稿がまだありません'),
          );
        }

        // posts 取得中で、まだ中身がないとき → オーバーレイだけ出す
        if (postsLoading && docs.isEmpty) {
          return const BaseScaffold(
            title: '投稿一覧',
            currentIndex: 0,
            showLoading: true,
            body: SizedBox.shrink(),
          );
        }

        // Users のプロフィールが揃うまで、BaseScaffold のオーバーレイでローディング
        final userIds = <String>{
          for (final d in docs) (d.data()['userId'] ?? '') as String,
        }..removeWhere((e) => e.isEmpty);

        return FutureBuilder<Map<String, _UserProfile?>>(
          future: _loadProfiles(userIds),
          builder: (context, profSnap) {
            final profilesLoading =
                profSnap.connectionState == ConnectionState.waiting;
            final showLoadingOverlay = postsLoading || profilesLoading;

            if (profSnap.hasError) {
              return BaseScaffold(
                title: '投稿一覧',
                currentIndex: 0,
                showLoading: showLoadingOverlay,
                body: _buildErrorPage(
                  'ユーザープロフィール読み込みエラー: ${profSnap.error}',
                ),
              );
            }

            final profiles = profSnap.data ?? {};
            return BaseScaffold(
              title: '投稿一覧',
              currentIndex: 0,
              showLoading: showLoadingOverlay,
              body: _buildPostListPage(docs, profiles),
            );
          },
        );
      },
    );
  }
}

// ====== コントロールモーダル ======

// （以下は元コードから変更なし）
class _ControlsResult {
  final String sortKey;
  final bool ascending;
  final String selectedLeague;
  final String selectedRank;
  final String nicknameQuery;
  // ルール / 問題タイプ
  final String selectedRule;
  final String selectedPostType;

  _ControlsResult({
    required this.sortKey,
    required this.ascending,
    required this.selectedLeague,
    required this.selectedRank,
    required this.nicknameQuery,
    required this.selectedRule,
    required this.selectedPostType,
  });
}

class _ControlsSheet extends StatefulWidget {
  final String sortKey; // '投稿順' | 'お気に入り数順'
  final bool ascending;
  final String selectedLeague;
  final String selectedRank;
  final String nicknameQuery;
  final List<String> rankOptions;

  // ルール / 問題タイプ
  final String selectedRule;
  final String selectedPostType;

  const _ControlsSheet({
    Key? key,
    required this.sortKey,
    required this.ascending,
    required this.selectedLeague,
    required this.selectedRank,
    required this.nicknameQuery,
    required this.rankOptions,
    required this.selectedRule,
    required this.selectedPostType,
  }) : super(key: key);

  @override
  State<_ControlsSheet> createState() => _ControlsSheetState();
}

class _ControlsSheetState extends State<_ControlsSheet> {
  late String _sortKey;
  late bool _ascending;
  late String _selectedLeague;
  late String _selectedRank;
  late TextEditingController _nickCtrl;

  // ルール / 問題タイプ
  late String _selectedRule;
  late String _selectedPostType;

  List<String> get _rankOptions =>
      _HomePageState.leagueRanks[_selectedLeague] ?? const ['未選択'];

  @override
  void initState() {
    super.initState();
    _sortKey = widget.sortKey;
    _ascending = widget.ascending;
    _selectedLeague = widget.selectedLeague;
    _selectedRank = widget.selectedRank;
    _nickCtrl = TextEditingController(text: widget.nicknameQuery);
    _selectedRule = widget.selectedRule;
    _selectedPostType = widget.selectedPostType;
  }

  @override
  void dispose() {
    _nickCtrl.dispose();
    super.dispose();
  }

  void _apply() {
    Navigator.pop(
      context,
      _ControlsResult(
        sortKey: _sortKey,
        ascending: _ascending,
        selectedLeague: _selectedLeague,
        selectedRank: _selectedRank,
        nicknameQuery: _nickCtrl.text,
        selectedRule: _selectedRule,
        selectedPostType: _selectedPostType,
      ),
    );
  }

  void _reset() {
    setState(() {
      _sortKey = '投稿順';
      _ascending = false;
      _selectedLeague = '未選択';
      _selectedRank = '未選択';
      _nickCtrl.text = '';
      _selectedRule = '未選択';
      _selectedPostType = '未選択';
    });
  }

  @override
  Widget build(BuildContext context) {
    final leagues = _HomePageState.leagueRanks.keys.toList();

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
            // ドラッグハンドル
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
                    size: 18,
                  ),
                  label: const Text(
                    'リセット',
                    style: TextStyle(color: Colors.cyanAccent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

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

            // ルール／問題タイプ
            Row(
              children: [
                Expanded(
                  child: _boxedDropdown<String>(
                    label: 'ルール',
                    value: _selectedRule,
                    items: _HomePageState.ruleOptions,
                    onChanged: (v) => setState(() => _selectedRule = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _boxedDropdown<String>(
                    label: '問題タイプ',
                    value: _selectedPostType,
                    items: _HomePageState.postTypeOptions,
                    onChanged: (v) => setState(() => _selectedPostType = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 所属／最高ランク
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
            const SizedBox(height: 12),

            // ニックネーム検索
            TextField(
              controller: _nickCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                prefixIcon:
                    const Icon(Icons.search, color: Colors.cyanAccent),
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
            const SizedBox(height: 8),
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
              color: Colors.black87,
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

// ===== 牌帯ウィジェット（手牌 + 副露を1列で描画：副露は縮小） =====
class _TileStrip extends StatelessWidget {
  final List<String> tiles; // 手牌（そのまま表示）
  final List<List<String>> meldDisplayGroups; // 右側に表示する displayTiles 群
  final double meldScale; // 副露の縮小率（手牌=1.0）

  const _TileStrip({
    required this.tiles,
    this.meldDisplayGroups = const <List<String>>[],
    this.meldScale = 0.68,
  });

  static String _asset(String id) => 'assets/tiles/$id.png';

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty && meldDisplayGroups.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, c) {
        final handCount = tiles.length;
        final double meldUnits = meldDisplayGroups.fold<double>(
          0,
          (sum, g) => sum + g.length * meldScale,
        );

        // 手牌↔副露／グループ間の小さな隙間（牌幅に対する割合）
        const double gapUnit = 0.45;
        final gapCount =
            meldDisplayGroups.isEmpty ? 0 : meldDisplayGroups.length;
        final totalUnits =
            handCount.toDouble() + meldUnits + gapCount * gapUnit;

        final baseW = c.maxWidth / (totalUnits <= 0 ? 1 : totalUnits);
        final handW = baseW; // 手牌の1枚幅
        final meldW = baseW * meldScale; // 副露の1枚幅（縮小）
        final height = handW * 3 / 2; // 列の高さは手牌基準

        Widget tileBox(String id, double w) => SizedBox(
              width: w,
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Image.asset(
                    _asset(id),
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

        Widget gapBox() => SizedBox(width: baseW * gapUnit);

        final children = <Widget>[];

        // 左：手牌（詰めてそのまま表示）
        for (final id in tiles) {
          children.add(tileBox(id, handW));
        }

        // 右：副露（縮小して横並び。グループごとに少し隙間）
        for (final g in meldDisplayGroups) {
          children.add(gapBox());
          for (final id in g) {
            children.add(tileBox(id, meldW));
          }
        }

        return SizedBox(
          width: c.maxWidth,
          height: height,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end, // 下端そろえ
              children: children,
            ),
          ),
        );
      },
    );
  }
}

// ---- Users ドキュメントの軽量モデル ----
class _UserProfile {
  final String? nickname;
  final List<Map<String, dynamic>>? affiliations;
  final String? highestRank;

  _UserProfile({this.nickname, this.affiliations, this.highestRank});

  factory _UserProfile.fromMap(Map<String, dynamic> map) {
    return _UserProfile(
      nickname: map['nickname'] as String?,
      affiliations: map['affiliations'] != null
          ? List<Map<String, dynamic>>.from(
              (map['affiliations'] as List).map(
                (e) => Map<String, dynamic>.from(e as Map),
              ),
            )
          : null,
      highestRank: map['highestRank'] as String?,
    );
  }
}
