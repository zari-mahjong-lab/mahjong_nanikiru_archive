// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // kReleaseMode
import 'package:flutter/services.dart'; // 画面向き固定
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:provider/provider.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:audioplayers/audioplayers.dart'; // ★ 追加：オーディオ設定用

import 'firebase_options.dart';

import 'providers/answer_provider.dart';
import 'providers/guest_provider.dart';
import 'providers/premium_provider.dart';

import 'screens/title_page.dart';
import 'services/interstitial_ad_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ★ オーディオコンテキストを設定
  //  - iOS: サイレントスイッチ ON なら鳴らさない (ambient)
  //         かつ他アプリの音声を止めない
  //  - Android: デフォルト設定を使用（ここでは特にいじらない）
  await AudioPlayer.global.setAudioContext(
    AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.ambient,
        // options は指定しない（mixWithOthers を明示すると assertion になるため）
      ),
      // android は指定しなくて OK（デフォルト動作）
    ),
  );

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // App Check を起動。デバッグ時は Debug、リリースは Play Integrity / DeviceCheck。
  await FirebaseAppCheck.instance.activate(
    androidProvider: kReleaseMode
        ? AndroidProvider.playIntegrity
        : AndroidProvider.debug,
    appleProvider: kReleaseMode
        ? AppleProvider.deviceCheck
        : AppleProvider.debug,
  );

  // ★ AdMob 初期化
  await MobileAds.instance.initialize();

  // ★ インタースティシャル広告を先読み（アプリ起動直後に一度）
  InterstitialAdService.instance.preload();

  // 縦画面固定
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);

  runApp(const ZariMahjongApp());
}

class ZariMahjongApp extends StatelessWidget {
  const ZariMahjongApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AnswerProvider()),
        ChangeNotifierProvider(create: (_) => GuestProvider()),
        ChangeNotifierProvider(create: (_) => PremiumProvider()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '麻雀立体何切るアーカイブ',
        theme: ThemeData.dark(),
        home: const TitlePage(),
      ),
    );
  }
}
