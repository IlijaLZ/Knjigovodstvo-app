import 'package:get/get.dart';
import 'package:knjigovodstvo_app/screens/dokumenta/radni_nalog/dodaj_radni_nalog.dart';
import 'package:knjigovodstvo_app/screens/osnovni_podaci/o_firmi_screen.dart';
import 'package:knjigovodstvo_app/screens/dokumenta/kalkulacija_nabavnih_cijena/dodaj_kalkulaciju_nabavnu_cijenu.dart';

import '../screens/main_screen.dart';

class AppRoutes {
  static const String main = '/';
  static const String oFirmi = '/o-firmi';
  static const String dodajKalkulacijuNabavnuCijenu = '/dodaj-kalkulaciju';
  static const String dodajRadniNalog = '/dodaj-radni-nalog';

  static final List<GetPage> pages = [
    GetPage(name: main, page: () => MainScreen()),
    GetPage(name: oFirmi, page: () => OFirmiScreen()),
    GetPage(
      name: dodajKalkulacijuNabavnuCijenu,
      page: () => DodajKalkulacijuScreen(),
    ),
    GetPage(name: dodajRadniNalog, page: () => DodajRadniNalog()),
  ];
}
