import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'bottom_nav_bar.dart';

class BaseScaffold extends StatefulWidget {
  final String title;
  final Widget body;
  final int currentIndex;

  /// true のとき、本文の上にローディングオーバーレイを表示
  final bool showLoading;

  /// showLoading が true のときに使うカスタムローディングウィジェット
  /// null の場合はデフォルトの "Now Loading..." オーバーレイを表示
  final Widget? loadingChild;

  const BaseScaffold({
    Key? key,
    required this.title,
    required this.body,
    required this.currentIndex,
    this.showLoading = false,
    this.loadingChild,
  }) : super(key: key);

  @override
  State<BaseScaffold> createState() => _BaseScaffoldState();
}

class _BaseScaffoldState extends State<BaseScaffold> {
  final AudioPlayer _player = AudioPlayer();

  Future<void> _playSEAndPop() async {
    await _player.play(AssetSource('sounds/cyber_click.mp3'));
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  /// デフォルトのローディングオーバーレイ
  /// 背景に background.png を敷く
  Widget _buildDefaultLoadingOverlay() {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/background.png'),
          fit: BoxFit.cover,
        ),
      ),
      // 少し暗くしてスピナーを目立たせる
      child: Container(
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
              ),
              SizedBox(height: 16),
              Text(
                'Now Loading...',
                style: TextStyle(color: Colors.cyanAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ★ BottomNavigationBar のタブ数（ホーム / 投稿 / マイページ）
    const int bottomNavItemCount = 3;

    // currentIndex を 0〜(bottomNavItemCount-1) の範囲に収める
    final int safeIndex =
        widget.currentIndex.clamp(0, bottomNavItemCount - 1) as int;

    // ステータスバー高
    final double topInset = MediaQuery.of(context).padding.top;
    // AppBar 高さ + ステータスバー高
    final double contentTopPadding = topInset + kToolbarHeight;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: ModalRoute.of(context)?.canPop == true
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _playSEAndPop,
              )
            : null,
        iconTheme: const IconThemeData(color: Colors.cyanAccent),
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Colors.cyanAccent,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(color: Colors.cyan, blurRadius: 10)],
          ),
        ),
      ),
      body: Stack(
        children: [
          // 背景グラデーション（AppBar 背後まで）
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0A0E21), Color(0xFF001F2F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          // 本文
          Padding(
            padding: EdgeInsets.only(top: contentTopPadding),
            child: widget.body,
          ),

          // ★ ローディングオーバーレイ（AppBar & BottomNavBar よりは後ろ）
          if (widget.showLoading)
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true, // 下のウィジェットを触れないようにする
                child: widget.loadingChild ?? _buildDefaultLoadingOverlay(),
              ),
            ),
        ],
      ),
      bottomNavigationBar: BottomNavBar(currentIndex: safeIndex),
    );
  }
}
