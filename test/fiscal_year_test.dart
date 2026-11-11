import 'package:flutter_test/flutter_test.dart';
import 'package:knjigovodstvo_app/models/fiscal_year.dart';
import 'package:knjigovodstvo_app/models/stock_card.dart';

void main() {
  test('PoslovnaGodina čita zaključenu i otvorenu godinu', () {
    final zakljucena = PoslovnaGodina.fromJson({
      'year': 2026,
      'is_closed': true,
      'closed_at': '2027-02-15T10:00:00+00:00',
      'closed_by': {'id': 1, 'name': 'Ana Anić'},
      'drafts_count': 0,
    });
    expect(zakljucena.godina, 2026);
    expect(zakljucena.zakljucena, isTrue);
    expect(zakljucena.zakljucio, 'Ana Anić');
    expect(zakljucena.zakljucenaU!.toUtc(), DateTime.utc(2027, 2, 15, 10));

    final otvorena = PoslovnaGodina.fromJson({
      'year': 2025,
      'is_closed': false,
      'closed_at': null,
      'closed_by': null,
      'drafts_count': 3,
    });
    expect(otvorena.zakljucena, isFalse);
    expect(otvorena.zakljucio, isNull);
    expect(otvorena.zakljucenaU, isNull);
    expect(otvorena.brojNacrta, 3);
  });

  test('StanjeKartice čita početno i trenutno stanje', () {
    final pocetno = StanjeKartice.fromJson({
      'date': '2027-01-01',
      'quantity': '110.0000',
      'value': '240.00',
    })!;
    expect(pocetno.datum, DateTime(2027, 1, 1));
    expect(pocetno.kolicina, 110);
    expect(pocetno.vrijednost, 240);

    final trenutno = StanjeKartice.fromJson({
      'date': null,
      'quantity': '0.0000',
      'value': '0.00',
    })!;
    expect(trenutno.datum, isNull);
    expect(trenutno.prosjecnaCijena, 0);

    expect(StanjeKartice.fromJson(null), isNull);
  });
}
