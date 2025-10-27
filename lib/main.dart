import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';                    // kReleaseMode
import 'package:flutter/services.dart';                      // ★ 追加: 画面向き固定
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart'; // ★ 追加
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'package:zari_mahjong_lab/providers/answer_provider.dart';
import 'package:zari_mahjong_lab/providers/guest_provider.dart';
import 'package:zari_mahjong_lab/screens/login_selection_page.dart';
import 'package:zari_mahjong_lab/screens/title_page.dart';
import 'package:zari_mahjong_lab/screens/profile_edit_page.dart';
import 'package:zari_mahjong_lab/screens/home_page.dart';
import 'package:zari_mahjong_lab/screens/my_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // App Check を起動。デバッグ時は Debug プロバイダ、本番は Play Integrity / DeviceCheck。
  await FirebaseAppCheck.instance.activate(
    androidProvider:
        kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug,
    appleProvider:
        kReleaseMode ? AppleProvider.deviceCheck : AppleProvider.debug,
    // web を使う場合は webProvider を別途設定してください（ReCaptcha など）
  );

  // ★ 縦画面固定：ポートレートのみ許可（上下回転も許可するなら portraitDown を追加）
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
