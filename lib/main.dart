import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'controllers/auth_controller.dart';
import 'routes/app_routes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final authController = Get.put(AuthController(), permanent: true);
  await authController.restoreSession();

  runApp(const KnjigovodstvoApp());
}

class KnjigovodstvoApp extends StatelessWidget {
  const KnjigovodstvoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,

      title: 'Knjigovodstvo',

      theme: ThemeData(
        useMaterial3: true,

        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),

        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      ),

      initialRoute: Get.find<AuthController>().isLoggedIn
          ? AppRoutes.main
          : AppRoutes.login,

      getPages: AppRoutes.pages,
    );
  }
}
