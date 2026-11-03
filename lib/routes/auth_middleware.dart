import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/auth_controller.dart';
import 'app_routes.dart';

// Vraća na login ako korisnik nije prijavljen.
class AuthMiddleware extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) {
    final loggedIn = Get.find<AuthController>().isLoggedIn;
    return loggedIn ? null : const RouteSettings(name: AppRoutes.login);
  }
}
