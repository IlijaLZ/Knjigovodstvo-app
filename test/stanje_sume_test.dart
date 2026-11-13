import 'package:flutter_test/flutter_test.dart';
import 'package:knjigovodstvo_app/models/stock.dart';

Map<String, dynamic> _red([Map<String, dynamic> dodatno = const {}]) => {
  'id': 1,
  'article': {'id': 40, 'name': 'Tkanina', 'unit_of_measure': 'm'},
  'quantity': '100.0000',
  'average_price': '51.50',
  'value': '5150.00',
  ...dodatno,
};

void main() {
  test('ulaz/izlaz iz /stocks', () {
    final s = StanjeArtikla.fromJson(
      _red({
        'in_quantity': '120.0000',
        'out_quantity': '20.0000',
        'in_value': '6180.00',
        'out_value': '1030.00',
        'last_movement_date': '2026-11-10',
      }),
    );
    expect(s.sume, isNotNull);
    expect(s.sume!.ulaz, 120);
    expect(s.sume!.izlaz, 20);
    expect(s.sume!.vrijednostUlaz, 6180);
    expect(s.sume!.vrijednostIzlaz, 1030);
    expect(s.sume!.zadnjiDatum, DateTime(2026, 11, 10));
  });

  test('bez kretanja u periodu: datum je null, sume 0', () {
    final s = StanjeArtikla.fromJson(
      _red({
        'in_quantity': '0',
        'out_quantity': '0',
        'in_value': '0',
        'out_value': '0',
        'last_movement_date': null,
      }),
    );
    expect(s.sume!.zadnjiDatum, isNull);
    expect(s.sume!.ulaz, 0);
  });

  test('stariji server bez polja: sume su null (sabiraju se iz kartice)', () {
    expect(StanjeArtikla.fromJson(_red()).sume, isNull);
  });
}
