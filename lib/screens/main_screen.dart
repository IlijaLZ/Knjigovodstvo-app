import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:knjigovodstvo_app/screens/osnovni_podaci/objekti/magacin_gotovih_proizvoda.dart';
import 'package:knjigovodstvo_app/screens/osnovni_podaci/objekti/magacin_repro.dart';
import 'package:knjigovodstvo_app/screens/osnovni_podaci/objekti/proizvodnja_utoku.dart';

import '../controllers/firma_controller.dart';
import '../controllers/navigation_controller.dart';
import '../controllers/niske_zalihe_controller.dart';
import '../controllers/poslovne_godine_controller.dart';
import '../models/article.dart';
import '../models/partner.dart';
import 'osnovni_podaci/firme_screen.dart';
import 'osnovni_podaci/o_firmi_screen.dart';
import 'osnovni_podaci/partneri_screen.dart';
import 'osnovni_podaci/poslovne_godine_screen.dart';
import 'osnovni_podaci/objekti/objekti_screen.dart';
import 'osnovni_podaci/artikli_screen.dart';

import 'dokumenta/kalkulacija_nabavnih_cijena/kalkulacija_nabavnih_cijena_screen.dart';
import 'dokumenta/radni_nalog/radni_nalog_screen.dart';
import 'dokumenta/trebovanje_screen.dart';
import 'dokumenta/kalkulacija_cijene_kostanja_screen.dart';
import 'dokumenta/otpremnica_screen.dart';

import 'knjizenje_naloga/knjizenje_naloga_screen.dart';
import 'glavna_knjiga/glavna_knjiga_screen.dart';
import 'kartica_glavne_knjige/kartica_glavne_knjige_screen.dart';
import 'stanje_magacina/stanje_magacina_screen.dart';
import 'pocetna/pocetna_screen.dart';
import '../widgets/glavni_header.dart';

class MainScreen extends StatelessWidget {
  MainScreen({super.key});

  final List<Widget> screens = [
    const PocetnaScreen(),

    OFirmiScreen(),
    const ObjektiScreen(),
    const ArtikliScreen(
      key: ValueKey(tipRepromaterijal),
      tip: tipRepromaterijal,
    ),

    const KalkulacijaNabavnihCijenaScreen(),
    const RadniNalogScreen(),
    TrebovanjeScreen(),
    const KalkulacijaCijeneKostanjaScreen(),
    const OtpremnicaScreen(),

    const KnjizenjeNalogaScreen(),
    const GlavnaKnjigaScreen(),
    const KarticaGlavneKnjigeScreen(),
    const StanjeMagacinaScreen(
      key: ValueKey('raw_materials'),
      tipSkladista: 'raw_materials',
    ),

    const MagacinRepromaterijala(),
    const ProizvodnjaUToku(),
    const MagacinGotovihProizvoda(),

    const ArtikliScreen(key: ValueKey(tipGotovProizvod), tip: tipGotovProizvod),

    const PartneriScreen(
      key: ValueKey('suppliers'),
      vrsta: VrstaPartnera.dobavljac,
    ),
    const PartneriScreen(
      key: ValueKey('customers'),
      vrsta: VrstaPartnera.kupac,
    ),

    const FirmeScreen(),

    const StanjeMagacinaScreen(
      key: ValueKey('production'),
      tipSkladista: 'production',
    ),
    const StanjeMagacinaScreen(
      key: ValueKey('finished_goods'),
      tipSkladista: 'finished_goods',
    ),

    const PoslovneGodineScreen(),
  ];

  // Ključ za otvaranje bočnog menija iz headera (uzak ekran).
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final NavigationController controller = Get.put(NavigationController());
    Get.put(FirmaController());
    Get.put(NiskeZaliheController());
    Get.put(PoslovneGodineController());
    final usko = MediaQuery.sizeOf(context).width < sirinaUskogHeadera;

    return Scaffold(
      key: _scaffoldKey,
      drawer: usko ? const GlavniMeniDrawer() : null,
      body: Column(
        children: [
          GlavniHeader(onMeni: () => _scaffoldKey.currentState?.openDrawer()),
          Expanded(child: Obx(() => screens[controller.selectedIndex.value])),
        ],
      ),
    );
  }
}
