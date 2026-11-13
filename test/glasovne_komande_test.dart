import 'package:flutter_test/flutter_test.dart';
import 'package:knjigovodstvo_app/glasovne_komande/analiticka_kartica_glasom.dart';
import 'package:knjigovodstvo_app/glasovne_komande/glasovne_komande.dart';

void main() {
  final slucajevi = <String, String?>{
    'Otvori mi sva trebovanja': 'Trebovanje',
    'отвори требовања': 'Trebovanje',
    'otvori radne naloge': 'Radni nalog',
    'knjiženje naloga': 'Knjiženje naloga',
    'kalkulacija nabavnih cijena': 'Kalkulacija nabavnih cijena',
    'kalkulacija cijene koštanja': 'Kalk. cijene koštanja',
    'pokaži otpremnice': 'Otpremnica',
    'kartica glavne knjige': 'Kartica glavne knjige',
    'glavna knjiga': 'Glavna knjiga',
    'artikli gotovih proizvoda': 'Artikli gotovih proizvoda',
    'otvori artikle': 'Artikli repromaterijala',
    'magacin gotovih proizvoda': 'Magacin gotovih proizvoda',
    'stanje proizvodnje u toku': 'Magacin proizvodnje u toku',
    'stanje magacina': 'Magacin repromaterijala',
    'otvori dobavljače': 'Dobavljači',
    'svi kupci': 'Kupci',
    'poslovne godine': 'Poslovne godine',
    'otvori firme': 'Firme',
    'idi na početnu': 'Početna',
    // Greške prepoznavača govora.
    'trebao Vanja': 'Trebovanje',
    'otvori mi sva trebao vanja': 'Trebovanje',
    'treba vanje': 'Trebovanje',
    'otpremnicu': 'Otpremnica',
    'otprem nice': 'Otpremnica',
    'dobavljaci': 'Dobavljači',
    'kalkulacije koštanja': 'Kalk. cijene koštanja',
    // Dodavanje.
    'hoću da dodam novo trebovanje': 'Novi radni nalog',
    'ocu da dodam novo trebovanje': 'Novi radni nalog',
    'novi radni nalog': 'Novi radni nalog',
    'napravi radni nalog': 'Novi radni nalog',
    'nova kalkulacija': 'Nova kalkulacija nabavnih cijena',
    'dodaj kalkulaciju nabavnih cijena': 'Nova kalkulacija nabavnih cijena',
    'nova kalkulacija cijene koštanja': 'Kalk. cijene koštanja',
    'ponovo otvori trebovanja': 'Trebovanje',
    'osnovni radni nalozi': 'Radni nalog',
    'otvori analitičku karticu': 'Analitička kartica',
    'analitička kartica brašna': 'Analitička kartica',
    'analiticna kartica': 'Analitička kartica',
    'otvori karticu glavne knjige': 'Kartica glavne knjige',
    // Apple čuje samo "trebao".
    'otvori mi sva trebao': 'Trebovanje',
    'trebao': 'Trebovanje',
    'otvori treba': 'Trebovanje',
    'dodaj novo trebao': 'Novi radni nalog',
    'trebao bih stanje magacina': 'Magacin repromaterijala',
    'trebao bih novi radni nalog': 'Novi radni nalog',
    // Iz logova.
    'Trebao bih novi nalog': 'Novi radni nalog',
    'Hoću da dodam novo trebao Vanje Vanje': 'Novi radni nalog',
    'Trebao Vanje otvori': 'Trebovanje',
    'Zatvori trebao trebao': 'Zatvori',
    'zatvori trebovanja': 'Zatvori',
    'nazad': 'Zatvori',
    'otvori nešto čudno': null,
    'nova knjiženja naloga': 'Knjiženje naloga',
  };

  slucajevi.forEach((izgovoreno, ocekivano) {
    test('"$izgovoreno" -> $ocekivano', () {
      expect(pronadjiKomandu(izgovoreno)?.naziv, ocekivano);
    });
  });

  test('nepoznato -> null', () {
    expect(pronadjiKomandu('kakvo je vrijeme danas'), isNull);
    expect(pronadjiKomandu(''), isNull);
    expect(pronadjiKomandu('dobar dan kako ste'), isNull);
    expect(pronadjiKomandu('hvala lijepa'), isNull);
  });

  group('naziv artikla iz govora', () {
    final slucajeviNaziva = {
      'analitička kartica brašna': 'brašna',
      'Otvori mi analitičku karticu za šećer.': 'šećer',
      'analitička kartica artikla ražano brašno': 'ražano brašno',
      'hoću da vidim analitičku karticu od kvasca': 'kvasca',
      'analitička kartica 1002': '1002',
      'otvori analitičku karticu': '',
    };
    slucajeviNaziva.forEach((izgovoreno, ocekivano) {
      test('"$izgovoreno" -> "$ocekivano"', () {
        expect(izdvojiNazivArtikla(izgovoreno), ocekivano);
      });
    });
  });

  group('ispravka prikaza', () {
    final ispravke = {
      'Otvori trebao Vanje': 'Otvori trebovanje',
      'otvori mi sva trebao vanja': 'otvori mi sva trebovanja',
      'treba vanja': 'trebovanja',
      'Treba mi nova kalkulacija zabavnih':
          'Treba mi nova kalkulacija nabavnih',
      'Trebao bih novi nalog': 'Trebao bih novi nalog',
    };
    ispravke.forEach((ulaz, izlaz) {
      test('"$ulaz" -> "$izlaz"', () => expect(ispraviPrikaz(ulaz), izlaz));
    });
  });
}
