import 'dart:async';

import 'package:get/get.dart';

import '../controllers/navigation_controller.dart';
import '../izvoz/registar_izvoza.dart';
import 'glasovne_komande.dart' show ZecKaze, ZecRaspolozenje;

// Izvoz u Excel glasom: "izvezi u excel" izvozi ekran koji je otvoren, a
// "izvezi stanje magacina u excel" prvo otvori ekran pa izveze. Izvoz ide
// preko istog dugmeta "Excel" (RegistarIzvoza), pa se otvara i isti prozor
// "Sačuvaj kao".

// Koliko se čeka da se dugme "Excel" pojavi na upravo otvorenom ekranu.
const Duration cekanjeEkrana = Duration(seconds: 5);

// "Stanje magacina 12-11-2026" -> "Stanje magacina" (za poruku).
String _bezDatuma(String opis) =>
    opis.replaceFirst(RegExp(r'\s+\d{1,2}-\d{1,2}-\d{4}.*$'), '').trim();

Future<void> _pokreni(PrijavaIzvoza prijava, ZecKaze kaze) async {
  final opis = _bezDatuma(prijava.opis());
  kaze(
    'Spremam Excel${opis.isEmpty ? '' : ': $opis'}… Izaberi gdje da ga '
    'sačuvam.',
    ZecRaspolozenje.racuna,
  );
  switch (await prijava.izvezi()) {
    case IshodIzvoza.sacuvano:
      kaze('Klik! Excel je sačuvan.', ZecRaspolozenje.klik);
    case IshodIzvoza.odustao:
      kaze('Dobro, ništa nisam sačuvao.', ZecRaspolozenje.prica);
    case IshodIzvoza.greska:
      kaze(
        'Izvoz nije uspio. Probaj ponovo za koji trenutak.',
        ZecRaspolozenje.greska,
      );
    case IshodIzvoza.vecRadi:
      kaze('Već spremam taj Excel, samo malo.', ZecRaspolozenje.racuna);
  }
}

// "Izvezi u excel": izvoz ekrana koji je navrhu.
Future<void> izveziTrenutni(String _, ZecKaze kaze) async {
  final prijava = RegistarIzvoza.trenutna;
  if (prijava == null) {
    kaze(
      'Na ovom ekranu nema izvoza u Excel. Reci npr. „izvezi stanje '
      'magacina u excel”.',
      ZecRaspolozenje.zbunjen,
    );
    return;
  }
  await _pokreni(prijava, kaze);
}

// Čeka prijavu izvoza novijeg od [poslije] (dugme na novom ekranu).
Future<PrijavaIzvoza?> _cekajNovuPrijavu(int poslije, Duration rok) {
  bool nova() => (RegistarIzvoza.trenutna?.broj ?? 0) > poslije;
  if (nova()) return Future.value(RegistarIzvoza.trenutna);

  final gotovo = Completer<PrijavaIzvoza?>();
  void slusaj() {
    if (nova() && !gotovo.isCompleted) {
      gotovo.complete(RegistarIzvoza.trenutna);
    }
  }

  RegistarIzvoza.promjene.addListener(slusaj);
  final tajmer = Timer(rok, () {
    if (!gotovo.isCompleted) gotovo.complete(null);
  });
  return gotovo.future.whenComplete(() {
    tajmer.cancel();
    RegistarIzvoza.promjene.removeListener(slusaj);
  });
}

// "Izvezi <ekran> u excel": otvori ekran (ako već nije otvoren), sačekaj
// njegovo dugme "Excel" i pokreni izvoz.
Future<void> izveziNaEkranu(
  String naziv,
  void Function(NavigationController c) otvori,
  ZecKaze kaze, {
  Duration rok = cekanjeEkrana,
}) async {
  final nav = Get.find<NavigationController>();
  final prije = nav.selectedIndex.value;
  final zadnjaPrijava = RegistarIzvoza.zadnjiBroj;

  otvori(nav);

  // Ekran je već bio otvoren: njegovo dugme je već prijavljeno.
  if (nav.selectedIndex.value == prije && RegistarIzvoza.trenutna != null) {
    await _pokreni(RegistarIzvoza.trenutna!, kaze);
    return;
  }

  kaze('Otvaram $naziv…', ZecRaspolozenje.racuna);
  final prijava = await _cekajNovuPrijavu(zadnjaPrijava, rok);
  if (prijava == null) {
    kaze(
      'Otvorio sam $naziv, ali izvoz još nije spreman. Klikni „Excel” ili '
      'reci „izvezi u excel”.',
      ZecRaspolozenje.zbunjen,
    );
    return;
  }
  await _pokreni(prijava, kaze);
}
