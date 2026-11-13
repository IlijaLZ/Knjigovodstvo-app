import 'package:flutter_test/flutter_test.dart';
import 'package:knjigovodstvo_app/glasovne_komande/diktat.dart';

void main() {
  group('brojčano polje', () {
    final slucajevi = {
      '1232': '1232',
      '1232 ne nego 1234': '1234',
      '1232 ne 1234': '1234',
      '1232, ne nego 1234': '1234',
      '1232 izvini 1234': '1234',
      '1232 ustvari 1234 pardon 1235': '1235',
      '1232 ne nego': '1232', // uživo: ispravka još nije izgovorena
      'hiljadu dvjesto trideset četiri': '1234',
      'dvije hiljade tristo': '2300',
      'sto dvadeset': '120',
      'jedan dva tri četiri': '1234',
      'dva zarez pet': '2,5',
      'dva i po': '2,5',
      'nula zarez sedam': '0,7',
      '2,5': '2,5',
      '2.5': '2,5',
      '1.232': '1232',
      '1.232,50': '1232,50',
      '12 34': '1234',
      'dvadeset i pet': '25',
      'Količina je 15 kila': '15',
      'obriši': '',
      'pet ne nego šest': '6',
    };
    slucajevi.forEach((ulaz, izlaz) {
      test('"$ulaz" -> "$izlaz"', () {
        expect(obradiDiktat(ulaz, VrstaPolja.broj).tekst, izlaz);
      });
    });

    test('obriši je komanda, ne prazan diktat', () {
      expect(obradiDiktat('obriši', VrstaPolja.broj).obrisi, isTrue);
      expect(obradiDiktat('obriši sve', VrstaPolja.tekst).obrisi, isTrue);
      expect(obradiDiktat('', VrstaPolja.tekst).prazno, isTrue);
    });
  });

  group('tekstualno polje', () {
    final slucajevi = {
      'Marko Marković': 'Marko Marković',
      'Marko ne nego Ivan': 'Ivan',
      'Marko, ustvari Ivan Ivić': 'Ivan Ivić',
      // "ne" samo po sebi je dio teksta, nije ispravka.
      'ne radi mašina': 'ne radi mašina',
      'sto dvadeset': '120',
      'račun 1232 ne nego 1234': '1234',
      'RN-55.': 'RN-55',
      'obriši polje': '',
    };
    slucajevi.forEach((ulaz, izlaz) {
      test('"$ulaz" -> "$izlaz"', () {
        expect(obradiDiktat(ulaz, VrstaPolja.tekst).tekst, izlaz);
      });
    });
  });

  group('izgovoreni znakovi (tekstualno polje)', () {
    final slucajevi = {
      '318 kroz 20': '318/20',
      'tristo osamnaest kroz dvadeset': '318/20',
      'račun 318 kroz 20': 'račun 318/20',
      '318 / 20': '318/20',
      'RN crtica 55': 'RN-55',
      'RN - 55': 'RN-55',
      '12 kosa crta 2026': '12/2026',
      '15 tačka 11 tačka 2026': '15.11.2026',
      'broj 7 donja crta A': 'broj 7_A',
      '15.11.2026': '15.11.2026',
      '20 posto': '20%',
      '2 puta 3': '2x3',
      '10 minus 2': '10-2',
      'otvorena zagrada 5 zatvorena zagrada': '(5)',
      'Marko zarez Ivan': 'Marko, Ivan',
      // "kroz" kao obična riječ ostaje riječ.
      'prolaz kroz magacin': 'prolaz kroz magacin',
      'minus na računu': 'minus na računu',
      // Mali broj riječju u rečenici ostaje riječ, veći postaje cifre.
      'jedan radnik': 'jedan radnik',
      'račun broj sto dvadeset': 'račun broj 120',
      // Ispravka i znakovi zajedno.
      '318 kroz 20 ne nego 318 kroz 21': '318/21',
    };
    slucajevi.forEach((ulaz, izlaz) {
      test('"$ulaz" -> "$izlaz"', () {
        expect(obradiDiktat(ulaz, VrstaPolja.tekst).tekst, izlaz);
      });
    });
  });

  group('naziv polja se izbacuje', () {
    final slucajevi = <(String, String), String>{
      ('Marko je izdao', 'Izdao'): 'Marko',
      ('izdao je Marko', 'Izdao'): 'Marko',
      ('Izdao: Marko Marković', 'Izdao'): 'Marko Marković',
      ('izdala je Ana', 'Izdao'): 'Ana',
      ('neka bude Marko izdao', 'Izdao'): 'Marko',
      ('potpisao Ivan ne nego Marko je potpisao', 'Potpisao'): 'Marko',
      ('broj računa je 318 kroz 20', 'Broj računa'): '318/20',
      ('robu je primio Ivan', 'Robu primio'): 'Ivan',
      // Bez naziva u rečenici ništa se ne dira.
      ('Marko i Ivan', 'Izdao'): 'Marko i Ivan',
      ('da', 'Izdao'): 'da',
      // Rečen samo naziv: ostaje kako je (bolje nego prazno).
      ('izdao', 'Izdao'): 'izdao',
    };
    slucajevi.forEach((ulaz, izlaz) {
      test('"${ulaz.$1}" [${ulaz.$2}] -> "$izlaz"', () {
        expect(
          obradiDiktat(ulaz.$1, VrstaPolja.tekst, oznaka: ulaz.$2).tekst,
          izlaz,
        );
      });
    });
    test('količina u brojčanom polju', () {
      expect(
        obradiDiktat(
          'količina je 15',
          VrstaPolja.broj,
          oznaka: 'Količina',
        ).tekst,
        '15',
      );
    });
  });

  group('više polja (dalje)', () {
    test('dijeli po "dalje" i "sljedeće polje"', () {
      expect(podijeliNaPolja('1234 dalje Marko sljedeće polje Ivan'), [
        '1234',
        'Marko',
        'Ivan',
      ]);
      expect(podijeliNaPolja('Marko'), ['Marko']);
      expect(podijeliNaPolja('1234 dalje'), ['1234', '']);
    });
  });
}
