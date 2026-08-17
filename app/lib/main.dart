import 'package:flutter/material.dart';

import 'notify.dart';
import 'pages/startup_page.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  await AppStore.instance.init();
  runApp(const DshGatewayApp());
}

class DshGatewayApp extends StatelessWidget {
  const DshGatewayApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2ECC71),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'DSH 网关',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      home: const StartupPage(),
    );
  }
}
