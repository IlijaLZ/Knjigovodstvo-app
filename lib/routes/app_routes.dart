import 'package:get/get.dart';
import 'package:knjigovodstvo_app/screens/dokumenta/radni_nalog/dodaj_radni_nalog.dart';
import 'package:knjigovodstvo_app/screens/osnovni_podaci/o_firmi_screen.dart';
import 'package:knjigovodstvo_app/screens/dokumenta/kalkulacija_nabavnih_cijena/dodaj_kalkulaciju_nabavnu_cijenu.dart';

import '../screens/login_screen.dart';
import '../screens/main_screen.dart';
import 'auth_middleware.dart';

class AppRoutes {
  static const String login = '/login';
  static const String main = '/';
  static const String oFirmi = '/o-firmi';
  static const String dodajKalkulacijuNabavnuCijenu = '/dodaj-kalkulaciju';
  static const String dodajRadniNalog = '/dodaj-radni-nalog';

  static final List<GetPage> pages = [
    GetPage(name: login, page: () => const LoginScreen()),
    GetPage(
      name: main,
      page: () => MainScreen(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: oFirmi,
      page: () => OFirmiScreen(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: dodajKalkulacijuNabavnuCijenu,
      page: () => DodajKalkulacijuScreen(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: dodajRadniNalog,
      page: () => DodajRadniNalog(),
      middlewares: [AuthMiddleware()],
    ),
  ];
}
