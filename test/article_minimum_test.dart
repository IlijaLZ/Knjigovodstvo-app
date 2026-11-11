import 'package:flutter_test/flutter_test.dart';
import 'package:knjigovodstvo_app/models/article.dart';

Map<String, dynamic> _artikal(Object? minimum) => {
  'id': 12,
  'type': 'raw_material',
  'code': 'FL-001',
  'name': 'Brašno T-400',
  'unit_of_measure': 'kg',
  'minimum_quantity': minimum,
};

void main() {
  test('čita minimum_quantity iz data objekta (GET/PATCH odgovor)', () {
    final body = {'data': _artikal('50.0000')};
    final a = Artikal.fromJson(body['data']!);

    expect(a.minimalnaKolicina, 50);
    expect(a.ispodMinimuma(49.9), isTrue);
    expect(a.ispodMinimuma(50), isFalse);
  });

  test('null znači bez praga', () {
    final a = Artikal.fromJson(_artikal(null));

    expect(a.minimalnaKolicina, isNull);
    expect(a.ispodMinimuma(0), isFalse);
  });

  test('code može biti null', () {
    final a = Artikal.fromJson({..._artikal(null), 'code': null});

    expect(a.sifra, '');
    expect(nazivSaId(null, a.naziv), 'Brašno T-400');
    expect(nazivSaId(a.id, a.naziv), '#12 — Brašno T-400');
  });

  test('PATCH sa 12.5 vraća "12.5000"', () {
    expect(Artikal.fromJson(_artikal('12.5000')).minimalnaKolicina, 12.5);
  });
}
