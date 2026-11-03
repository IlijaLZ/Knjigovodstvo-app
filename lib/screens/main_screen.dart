import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:knjigovodstvo_app/screens/osnovni_podaci/objekti/magacin_gotovih_proizvoda.dart';
import 'package:knjigovodstvo_app/screens/osnovni_podaci/objekti/magacin_repro.dart';
import 'package:knjigovodstvo_app/screens/osnovni_podaci/objekti/proizvodnja_utoku.dart';

import '../controllers/firma_controller.dart';
import '../controllers/navigation_controller.dart';
import '../models/article.dart';
import '../models/company.dart';
import 'osnovni_podaci/o_firmi_screen.dart';
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

class MainScreen extends StatelessWidget {
  MainScreen({super.key});

  final List<Widget> screens = [
    const Center(
      child: Text(
        'Knjigovodstvo',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
      ),
    ),

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
    const StanjeMagacinaScreen(),

    const MagacinRepromaterijala(),
    const ProizvodnjaUToku(),
    const MagacinGotovihProizvoda(),

    const ArtikliScreen(key: ValueKey(tipGotovProizvod), tip: tipGotovProizvod),
  ];

  @override
  Widget build(BuildContext context) {
    final NavigationController controller = Get.put(NavigationController());
    final FirmaController firmaController = Get.put(FirmaController());

    return Scaffold(
      body: Column(
        children: [
          Container(
            height: 64,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                _buildOsnovniPodaciMenu(controller),

                _buildDropdown(
                  title: 'Dokumenta',
                  items: [
                    _MenuItem(
                      title: 'Kalkulacija nabavnih cijena',
                      onTap: controller.openKalkulacijaNabavnihCijena,
                    ),
                    _MenuItem(
                      title: 'Radni nalog',
                      onTap: controller.openRadniNalog,
                    ),
                    _MenuItem(
                      title: 'Trebovanje',
                      onTap: controller.openTrebovanje,
                    ),
                    _MenuItem(
                      title: 'Kalk. cijene koštanja',
                      onTap: controller.openKalkulacijaCijeneKostanja,
                    ),
                    _MenuItem(
                      title: 'Otpremnica',
                      onTap: controller.openOtpremnica,
                    ),
                  ],
                ),

                _buildNavigationItem(
                  'Knjiženje naloga',
                  controller.openKnjizenjeNaloga,
                ),

                _buildNavigationItem(
                  'Stanje magacina repromaterijala',
                  controller.openKarticaGlavneKnjige,
                ),

                _buildNavigationItem(
                  'Stanje magacina proizvodnje u toku',
                  controller.openStanjeMagacina,
                ),

                _buildNavigationItem(
                  'Stanje magacina gotovih proizvoda',
                  controller.openStanjeMagacina,
                ),

                // --------------------------------------------------
                // FIRMA (gornji desni ugao)
                // --------------------------------------------------
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _buildFirmaSelector(firmaController),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: Obx(() => screens[controller.selectedIndex.value])),
        ],
      ),
    );
  }

  Widget _buildNavigationItem(String title, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        alignment: Alignment.center,
        child: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String title,
    required List<_MenuItem> items,
  }) {
    return PopupMenuButton<_MenuItem>(
      offset: const Offset(0, 60),

      onSelected: (item) {
        item.onTap();
      },

      itemBuilder: (context) {
        return items.map((item) {
          return PopupMenuItem<_MenuItem>(value: item, child: Text(item.title));
        }).toList();
      },

      child: Container(
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        alignment: Alignment.center,
        child: Row(
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),

            const SizedBox(width: 4),

            const Icon(Icons.keyboard_arrow_down, size: 18),
          ],
        ),
      ),
    );
  }

  // Naziv izabrane firme + strelica; dropdown prikazuje ostale firme.
  Widget _buildFirmaSelector(FirmaController firmaController) {
    return Obx(() {
      final izabrana = firmaController.izabranaFirma.value;
      final ostale = firmaController.firme.where((f) => f != izabrana).toList();

      final naziv =
          izabrana?.name ??
          (firmaController.isLoading.value
              ? 'Učitavanje firmi...'
              : firmaController.errorMessage.value ?? 'Nema firmi');

      return PopupMenuButton<Company>(
        tooltip: 'Promijeni firmu',
        offset: const Offset(0, 60),

        onSelected: firmaController.izaberiFirmu,

        itemBuilder: (context) {
          if (ostale.isEmpty) {
            return const [
              PopupMenuItem<Company>(
                enabled: false,
                child: Text('Nema drugih firmi'),
              ),
            ];
          }

          return ostale.map((firma) {
            return PopupMenuItem<Company>(
              value: firma,
              child: Text(firma.name),
            );
          }).toList();
        },

        child: Container(
          height: double.infinity,
          padding: const EdgeInsets.only(left: 24, right: 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.business_outlined, size: 18),

              const SizedBox(width: 8),

              Flexible(
                child: Text(
                  naziv,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(width: 4),

              const Icon(Icons.keyboard_arrow_down, size: 18),
            ],
          ),
        ),
      );
    });
  }
}

class _MenuItem {
  final String title;
  final VoidCallback onTap;

  _MenuItem({required this.title, required this.onTap});
}

Widget _buildOsnovniPodaciMenu(NavigationController controller) {
  return MenuAnchor(
    menuChildren: [
      MenuItemButton(
        onPressed: controller.openOFirmi,
        child: const Text('O firmi'),
      ),

      SubmenuButton(
        menuChildren: [
          MenuItemButton(
            onPressed: controller.openMagacinRepromaterijala,
            child: const Text('Magacin repromaterijala'),
          ),
          MenuItemButton(
            onPressed: controller.openProizvodnjaUToku,
            child: const Text('Proizvodnja u toku'),
          ),
          MenuItemButton(
            onPressed: controller.openMagacinGotovihProizvoda,
            child: const Text('Magacin gotovih proizvoda'),
          ),
        ],
        child: const Text('Objekti'),
      ),

      MenuItemButton(
        onPressed: controller.openArtikliRepromaterijala,
        child: const Text('Artikli repromaterijala'),
      ),

      MenuItemButton(
        onPressed: controller.openArtikliGotovihProizvoda,
        child: const Text('Artikli gotovih proizvoda'),
      ),

      MenuItemButton(
        onPressed: controller.openOFirmi,
        child: const Text('Glavna knjiga'),
      ),
      MenuItemButton(
        onPressed: controller.openOFirmi,
        child: const Text('Dobavljači'),
      ),
      MenuItemButton(
        onPressed: controller.openOFirmi,
        child: const Text('Kupci'),
      ),
    ],
    builder: (context, menuController, child) {
      return InkWell(
        onTap: () {
          if (menuController.isOpen) {
            menuController.close();
          } else {
            menuController.open();
          }
        },
        child: Container(
          height: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          alignment: Alignment.center,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Osnovni podaci',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down, size: 18),
            ],
          ),
        ),
      );
    },
  );
}
