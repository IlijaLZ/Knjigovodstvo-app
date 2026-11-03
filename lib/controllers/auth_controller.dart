import 'package:get/get.dart';

import '../models/auth_models.dart';
import '../routes/app_routes.dart';
import '../services/auth_service.dart';

class AuthController extends GetxController {
  final AuthService _service = AuthService();

  final Rxn<User> user = Rxn<User>();
  final Rxn<AuthTokens> tokens = Rxn<AuthTokens>();

  final RxBool isLoading = false.obs;
  final RxnString errorMessage = RxnString();
  final RxnString emailError = RxnString();
  final RxnString passwordError = RxnString();

  bool get isLoggedIn =>
      tokens.value != null && !tokens.value!.isRefreshExpired;

  // Učitava sačuvanu sesiju pri pokretanju aplikacije.
  Future<void> restoreSession() async {
    final saved = await _service.savedTokens();
    if (saved == null || saved.isRefreshExpired) return;

    tokens.value = saved;
    user.value = await _service.savedUser();
  }

  Future<void> login(String email, String password) async {
    errorMessage.value = null;
    emailError.value = null;
    passwordError.value = null;

    if (!GetUtils.isEmail(email.trim())) {
      emailError.value = 'Unesite ispravan email.';
    }
    if (password.isEmpty) {
      passwordError.value = 'Unesite lozinku.';
    }
    if (emailError.value != null || passwordError.value != null) return;

    isLoading.value = true;

    try {
      final (loggedUser, newTokens) = await _service.login(
        email: email,
        password: password,
      );
      user.value = loggedUser;
      tokens.value = newTokens;
      Get.offAllNamed(AppRoutes.main);
    } on ApiException catch (e) {
      errorMessage.value = e.message;
      passwordError.value = e.fieldError('password');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> logout() async {
    await _service.logout();
    user.value = null;
    tokens.value = null;
    Get.offAllNamed(AppRoutes.login);
  }
}
