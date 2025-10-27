import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'bottom_nav_bar.dart';

class BaseScaffold extends StatefulWidget {
  final String title;
  final Widget body;
  final int currentIndex;

  const BaseScaffold({
    Key? key,
    required this.title,
    required this.body,
    required this.currentIndex,
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
  Widget build(BuildContext context) {
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
          // 背景グラデーション
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
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              top: kToolbarHeight + 16,
              bottom: 16,
            ),
            child: widget.body,
          ),
        ],
      ),
      // 縦固定：常にボトムナビ表示
      bottomNavigationBar: BottomNavBar(currentIndex: widget.currentIndex),
    );
  }
}
