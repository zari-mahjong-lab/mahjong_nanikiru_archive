import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';                    // kReleaseMode
import 'package:flutter/services.dart';                      // 画面向き固定
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'package:mahjong_nanikiru_archive/providers/answer_provider.dart';
import 'package:mahjong_nanikiru_archive/providers/guest_provider.dart';
import 'package:mahjong_nanikiru_archive/providers/premium_provider.dart'; // ★ 追加

import 'package:mahjong_nanikiru_archive/screens/title_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // App Check を起動。デバッグ時は Debug、リリースは Play Integrity / DeviceCheck。
  await FirebaseAppCheck.instance.activate(
    androidProvider:
        kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug,
    appleProvider:
        kReleaseMode ? AppleProvider.deviceCheck : AppleProvider.debug,
    // web を使う場合は webProvider を別途設定
  );

  // 縦画面固定
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    // DeviceOrientation.portraitDown,
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
        ChangeNotifierProvider(create: (_) => PremiumProvider()), // ★ 追加
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
