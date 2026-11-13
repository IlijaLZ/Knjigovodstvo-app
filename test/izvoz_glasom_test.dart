import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:knjigovodstvo_app/controllers/navigation_controller.dart';
import 'package:knjigovodstvo_app/glasovne_komande/glasovne_komande.dart';
import 'package:knjigovodstvo_app/glasovne_komande/izvoz_glasom.dart';
import 'package:knjigovodstvo_app/izvoz/dugme_izvoza.dart';
import 'package:knjigovodstvo_app/izvoz/registar_izvoza.dart';

void main() {
  group('fraze', () {
    final slucajevi = <String, String?>{
      'izvezi u excel': 'Izvoz u Excel',
      'Excel': 'Izvoz u Excel',
      'daj mi ovo u eksel': 'Izvoz u Excel',
      'izvoz': 'Izvoz u Excel',
      'izvezi stanje magacina u excel': 'Excel: Magacin repromaterijala',
      'izvezi stanje repromaterijala': 'Excel: Magacin repromaterijala',
      'excel zaliha': 'Excel: Magacin repromaterijala',
      'izvezi kalkulacije u excel': 'Excel: Kalkulacija nabavnih cijena',
      'izvezi radne naloge': 'Excel: Radni nalog',
      'izvezi artikle gotovih proizvoda': 'Excel: Artikli gotovih proizvoda',
      'izvezi artikle u excel': 'Excel: Artikli repromaterijala',
      'izvezi dobavljače': 'Excel: Dobavljači',
      'izvezi kupce u eksel': 'Excel: Kupci',
      'izvezi magacin gotovih proizvoda': 'Excel: Magacin gotovih proizvoda',
      'izvezi proizvodnju u toku': 'Excel: Magacin proizvodnje u toku',
      // Tačno kako je prepoznavač čuo (iz loga aplikacije).
      'Mi u Excel radne naloge': 'Excel: Radni nalog',
      'U Excel mi kalkulacije cijena': 'Excel: Kalkulacija nabavnih cijena',
      'Izvesti kalkulacije zabavnih cijena':
          'Excel: Kalkulacija nabavnih cijena',
      'Mi u Excel': 'Izvoz u Excel',
      // Trebovanje nema izvoz liste: otvori se (i sa "trebao").
      'Mi u Excel trebao': 'Trebovanje',
      'Svezi trebao Vanje u Excel': 'Trebovanje',
      'izvezi trebovanja': 'Trebovanje',
      'trebovanje u excel': 'Trebovanje',
      // "Excel" na kraju ili u sredini isto pravi Excel.
      'stanje magacina u excel': 'Excel: Magacin repromaterijala',
      'radni nalozi excel': 'Excel: Radni nalog',
      'radne naloge mi napravi u excelu': 'Excel: Radni nalog',
      'napravi radni nalog u excelu': 'Excel: Radni nalog',
      'nova kalkulacija u excel': 'Excel: Kalkulacija nabavnih cijena',
      'kupce mi stavi u eksel': 'Excel: Kupci',
      'dobavljače izvezi': 'Excel: Dobavljači',
      // "nalozi" se čuje kao "nalazi" (iz loga).
      'Radni nalazi u Excelu': 'Excel: Radni nalog',
      'Excel radni nalazi': 'Excel: Radni nalog',
      'radni nalazi': 'Radni nalog',
      'otvori radne naloge u excel': 'Excel: Radni nalog',
      // Bez riječi za izvoz: obično otvaranje.
      'otvori kalkulacije': 'Kalkulacija nabavnih cijena',
      'stanje magacina': 'Magacin repromaterijala',
      // Glagol ispred "u excel".
      'napravi mi u excelu radne naloge': 'Excel: Radni nalog',
      'napravi mi excel kalkulacija': 'Excel: Kalkulacija nabavnih cijena',
      'stavi u excel stanje magacina': 'Excel: Magacin repromaterijala',
      'sačuvaj u eksel dobavljače': 'Excel: Dobavljači',
      'prebaci mi u excel kupce': 'Excel: Kupci',
      'napravi mi tabelu kupaca': 'Excel: Kupci',
      'eksportuj artikle': 'Excel: Artikli repromaterijala',
      'napravi excel': 'Izvoz u Excel',
      'otvori mi u excelu radne naloge': 'Excel: Radni nalog',
      // Bez izvoza glagoli rade kao i prije.
      'napravi radni nalog': 'Novi radni nalog',
      'napravi mi novu kalkulaciju': 'Nova kalkulacija nabavnih cijena',
      'otvori radne naloge': 'Radni nalog',
      'prebaci me na kupce': 'Kupci',
      // "Zatvori" i dalje ima prednost.
      'zatvori excel': 'Zatvori',
    };

    slucajevi.forEach((izgovoreno, ocekivano) {
      test('"$izgovoreno" -> $ocekivano', () {
        expect(pronadjiKomandu(izgovoreno)?.naziv, ocekivano);
      });
    });

    test('ekran bez izvoza se samo otvori, uz objašnjenje', () {
      final k = pronadjiKomandu('Mi u Excel trebao')!;
      expect(k.akcija, isNull);
      expect(k.ruta, isNull);
      expect(k.napomena, contains('otvori jedno trebovanje'));
      // Bez riječi za izvoz: obično otvaranje, bez napomene.
      expect(pronadjiKomandu('otvori trebovanja')!.napomena, isNull);
    });

    test('ostatak bez riječi za izvoz', () {
      expect(ostatakBezIzvoza('u excel mi kalkulacije'), 'u mi kalkulacije');
      expect(ostatakBezIzvoza('stanje magacina u excelu'), 'stanje magacina u');
      expect(ostatakBezIzvoza('excel'), '');
      expect(ostatakBezIzvoza('sve kupce'), isNull);
    });

    test('ispravka prikaza: "svezi" -> "izvezi"', () {
      expect(ispraviPrikaz('Svezi trebao Vanje'), 'izvezi trebovanje');
      expect(ispraviPrikaz('Izvesti kalkulacije'), 'izvezi kalkulacije');
      expect(ispraviPrikaz('Radni nalazi u Excelu'), 'Radni nalozi u Excelu');
    });

    test('izvoz ekrana navrhu ne zatvara karticu/dijalog', () {
      expect(pronadjiKomandu('izvezi u excel')!.naGlavni, isFalse);
      expect(pronadjiKomandu('izvezi kupce')!.naGlavni, isTrue);
    });
  });

  group('izvoz', () {
    late List<(String, ZecRaspolozenje?)> poruke;
    void kaze(String t, [ZecRaspolozenje? r]) => poruke.add((t, r));

    setUp(() {
      poruke = [];
      RegistarIzvoza.ocisti();
      Get.reset();
      Get.put(NavigationController());
    });

    test('bez dugmeta na ekranu zec kaže da nema izvoza', () async {
      await izveziTrenutni('izvezi', kaze);
      expect(poruke.single.$2, ZecRaspolozenje.zbunjen);
    });

    test('izvozi ekran navrhu (zadnja prijava)', () async {
      var lista = 0, kartica = 0;
      RegistarIzvoza.prijavi(
        opis: () => 'Stanje magacina 12-11-2026',
        izvezi: () async {
          lista++;
          return IshodIzvoza.sacuvano;
        },
      );
      final p = RegistarIzvoza.prijavi(
        opis: () => 'Kartica Tkanina',
        izvezi: () async {
          kartica++;
          return IshodIzvoza.sacuvano;
        },
      );

      await izveziTrenutni('izvezi', kaze);
      expect((lista, kartica), (0, 1));
      expect(poruke.first.$1, contains('Kartica Tkanina'));
      expect(poruke.last.$2, ZecRaspolozenje.klik);

      // Kartica zatvorena: opet lista.
      RegistarIzvoza.odjavi(p);
      await izveziTrenutni('izvezi', kaze);
      expect((lista, kartica), (1, 1));
      // Datum se ne čita naglas.
      expect(poruke[2].$1, contains('Stanje magacina…'));
    });

    test('odustajanje i greška', () async {
      RegistarIzvoza.prijavi(
        opis: () => 'X',
        izvezi: () async => IshodIzvoza.odustao,
      );
      await izveziTrenutni('izvezi', kaze);
      expect(poruke.last.$2, ZecRaspolozenje.prica);

      RegistarIzvoza.prijavi(
        opis: () => 'Y',
        izvezi: () async => IshodIzvoza.greska,
      );
      await izveziTrenutni('izvezi', kaze);
      expect(poruke.last.$2, ZecRaspolozenje.greska);
    });

    test('otvori ekran, sačeka njegovo dugme i izveze', () async {
      var izvezeno = false;
      await izveziNaEkranu('Kupci', (c) {
        c.openKupci();
        // Dugme se pojavi kad se ekran napravi.
        Future.delayed(const Duration(milliseconds: 50), () {
          RegistarIzvoza.prijavi(
            opis: () => 'Kupci',
            izvezi: () async {
              izvezeno = true;
              return IshodIzvoza.sacuvano;
            },
          );
        });
      }, kaze);

      expect(Get.find<NavigationController>().selectedIndex.value, 18);
      expect(izvezeno, isTrue);
      expect(poruke.last.$2, ZecRaspolozenje.klik);
    });

    test('ekran već otvoren: odmah izvozi njegovo dugme', () async {
      Get.find<NavigationController>().openKupci();
      var izvezeno = false;
      RegistarIzvoza.prijavi(
        opis: () => 'Kupci',
        izvezi: () async {
          izvezeno = true;
          return IshodIzvoza.sacuvano;
        },
      );

      await izveziNaEkranu('Kupci', (c) => c.openKupci(), kaze);
      expect(izvezeno, isTrue);
    });

    test(
      'dugme se ne pojavi na vrijeme: zec javi, ništa se ne izvozi',
      () async {
        var izvezeno = false;
        RegistarIzvoza.prijavi(
          opis: () => 'Stari ekran',
          izvezi: () async {
            izvezeno = true;
            return IshodIzvoza.sacuvano;
          },
        );

        await izveziNaEkranu(
          'Kupci',
          (c) => c.openKupci(),
          kaze,
          rok: const Duration(milliseconds: 100),
        );
        expect(izvezeno, isFalse);
        expect(poruke.last.$2, ZecRaspolozenje.zbunjen);
      },
    );
  });

  testWidgets('dugme Excel se prijavi dok je na ekranu', (tester) async {
    RegistarIzvoza.ocisti();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DugmeIzvoza(
            nazivFajla: () => 'Kupci',
            pripremi: () async => [],
          ),
        ),
      ),
    );
    expect(RegistarIzvoza.trenutna?.opis(), 'Kupci');

    // Prazna lista = odustao, bez prozora za snimanje.
    expect(await RegistarIzvoza.trenutna!.izvezi(), IshodIzvoza.odustao);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(RegistarIzvoza.trenutna, isNull);
  });
}
