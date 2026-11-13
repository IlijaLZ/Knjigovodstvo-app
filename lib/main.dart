import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'controllers/auth_controller.dart';
import 'glasovne_komande/zec_panel.dart';
import 'routes/app_routes.dart';
import 'widgets/magacin_ui.dart';

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

      title: 'Kalkulino',

      theme: ThemeData(
        useMaterial3: true,

        colorScheme: ColorScheme.fromSeed(
          seedColor: akcentAplikacije,
          primary: akcentAplikacije,
          secondary: mint,
          onSecondary: akcentTamni,
        ),

        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      ),

      initialRoute: Get.find<AuthController>().isLoggedIn
          ? AppRoutes.main
          : AppRoutes.login,

      getPages: AppRoutes.pages,

      // Zec Kalkulino (glasovne komande) iznad svih ekrana.
      builder: (context, child) => ZecSloj(child: child!),
    );
  }
}
