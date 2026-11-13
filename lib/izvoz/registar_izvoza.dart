import 'package:flutter/foundation.dart';

// Registar izvoza: svako vidljivo dugme "Excel" (DugmeIzvoza) se ovdje
// prijavi dok je na ekranu i odjavi kad nestane. Zadnja prijava je izvoz
// ekrana koji je trenutno navrhu (npr. kartica otvorena preko stanja
// magacina), pa ga glasovna komanda "izvezi u excel" može pokrenuti.

enum IshodIzvoza { sacuvano, odustao, greska, vecRadi }

class PrijavaIzvoza {
  // Šta se izvozi (naziv fajla bez datuma), za poruku korisniku.
  final String Function() opis;
  final Future<IshodIzvoza> Function() izvezi;

  // Redni broj prijave; veći = prijavljen kasnije.
  final int broj;

  PrijavaIzvoza._(this.opis, this.izvezi, this.broj);
}

class RegistarIzvoza {
  RegistarIzvoza._();

  static final List<PrijavaIzvoza> _prijave = [];
  static int _brojac = 0;

  // Mijenja se pri svakoj prijavi/odjavi (za čekanje novog ekrana).
  static final ValueNotifier<int> promjene = ValueNotifier(0);

  static PrijavaIzvoza prijavi({
    required String Function() opis,
    required Future<IshodIzvoza> Function() izvezi,
  }) {
    final p = PrijavaIzvoza._(opis, izvezi, ++_brojac);
    _prijave.add(p);
    promjene.value++;
    return p;
  }

  static void odjavi(PrijavaIzvoza p) {
    if (_prijave.remove(p)) promjene.value++;
  }

  // Izvoz ekrana navrhu, ili null ako na ekranu nema izvoza.
  static PrijavaIzvoza? get trenutna => _prijave.lastOrNull;

  static int get zadnjiBroj => _brojac;

  @visibleForTesting
  static void ocisti() {
    _prijave.clear();
    promjene.value++;
  }
}
