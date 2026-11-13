import 'package:flutter_test/flutter_test.dart';
import 'package:knjigovodstvo_app/izvoz/trebovanje_excel.dart';
import 'package:knjigovodstvo_app/models/utrosak.dart';
import 'package:knjigovodstvo_app/models/work_order.dart';

var _id = 0;

MaterijalTrebovanja _m(
  int? materialId,
  String naziv, {
  double trazeno = 0,
  double? izdato,
  double? vrijednost,
}) => MaterijalTrebovanja(
  id: ++_id,
  bomItemId: ++_id,
  materialId: materialId,
  naziv: naziv,
  jm: 'm',
  norma: 1,
  trazeno: trazeno,
  izdato: izdato,
  vrijednost: vrijednost,
);

(RadniNalog, Trebovanje) _par(
  int id,
  DateTime datum,
  List<MaterijalTrebovanja> materijali, {
  String status = statusIzdat,
}) {
  final nalog = RadniNalog(
    id: id,
    status: status,
    broj: 'RN-$id',
    kupac: 'Hotel',
    datum: datum,
  );
  return (
    nalog,
    Trebovanje(
      id: id,
      workOrderId: id,
      stavke: [
        StavkaTrebovanja(
          id: id,
          articleId: 100,
          sifra: 'P1',
          naziv: 'Posteljina',
          jm: 'kom',
          kolicina: 10,
          materijali: materijali,
        ),
      ],
    ),
  );
}

void main() {
  test('utrošak iz izvještaja servera: parsiranje i listovi', () {
    final izvjestaj = IzvjestajUtroska.fromJson({
      'data': [
        {
          'material_id': 11,
          'code': 'K1',
          'name': 'Konac',
          'unit_of_measure': 'pcs',
          'issued_quantity': '2.0000',
          'issued_value': '6.00',
          'work_orders_count': 1,
        },
        {
          'material_id': 10,
          'code': 'T1',
          'name': 'Tkanina',
          'unit_of_measure': 'm',
          'issued_quantity': '80.0000',
          'issued_value': '335.00',
          'work_orders_count': 2,
        },
      ],
      'meta': {'issued_value': '341.00'},
      'work_orders': [
        {
          'work_order_id': 2,
          'order_number': 'RN-2',
          'date': '2026-11-01',
          'issued_at': '2026-11-05',
          'customer_name': 'Hotel',
          'product_name': 'Posteljina',
          'product_quantity': '10',
          'code': 'T1',
          'name': 'Tkanina',
          'unit_of_measure': 'm',
          'issued_quantity': '30',
          'issued_value': '135.00',
        },
        {
          'work_order_id': 1,
          'order_number': 'RN-1',
          'date': '2026-11-01',
          'issued_at': '2026-11-03',
          'product_name': 'Posteljina',
          'product_quantity': '10',
          'code': 'T1',
          'name': 'Tkanina',
          'unit_of_measure': 'm',
          'issued_quantity': '50',
          'issued_value': '200.00',
        },
      ],
    });

    final listovi = utrosakListovi(
      izvjestaj: izvjestaj,
      firma: 'La Vista',
      od: DateTime(2026, 11, 1),
      doDatuma: DateTime(2026, 11, 30),
    );

    final utrosak = listovi.first;
    // Najveća vrijednost prva; JM iz API-ja u oznaku aplikacije.
    expect(utrosak.redovi.first, [
      'T1',
      'Tkanina',
      'm',
      80.0,
      4.1875,
      335.0,
      2,
    ]);
    expect(utrosak.redovi[1][2], 'kom');
    expect(utrosak.ukupno![5], 341.0);
    expect(utrosak.podnaslovi[1], contains('izdatih naloga: 2'));

    // Po nalozima: po datumu izdavanja.
    final poNalozima = listovi[1];
    expect(poNalozima.redovi.map((r) => r[2]), ['RN-1', 'RN-2']);
    expect(poNalozima.ukupno!.last, 335.0);
  });

  test('trebovanje u pripremi: izdato = traženo osim ručnih izmjena', () {
    final (nalog, t) = _par(1, DateTime(2026, 11, 3), [
      _m(10, 'Tkanina', trazeno: 52),
      _m(11, 'Konac', trazeno: 3, izdato: 4),
    ], status: statusNacrt);

    final list = trebovanjeList(trebovanje: t, nalog: nalog, firma: 'F');
    expect(list.redovi[0][6], 52);
    expect(list.redovi[1][6], 4);
    expect(list.podnaslovi[1], contains('U pripremi'));
  });
}
