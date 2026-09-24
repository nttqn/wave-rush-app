import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';
import 'services/ads_service.dart';
import 'services/progress_service.dart';
import 'services/sound_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The genre is played sideways: long horizontal view ahead of the wave.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await ProgressService.instance.load();
  unawaited(AdsService.instance.initialize());
  // Unawaited on purpose — see SoundService's doc comment.
  unawaited(SoundService.instance.init());
  runApp(const WaveRushApp());
}

class WaveRushApp extends StatelessWidget {
  const WaveRushApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wave Rush',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3FE0FF),
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF050A1F),
      ),
      home: const HomeScreen(),
    );
  }
}
