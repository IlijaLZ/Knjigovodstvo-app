import 'package:flutter_test/flutter_test.dart';
import 'package:knjigovodstvo_app/models/stock_card.dart';

PromjenaKartice _red(
  int id, {
  double ulaz = 0,
  double izlaz = 0,
  double saldo = 999,
}) => PromjenaKartice(
  id: id,
  vrsta: 'x',
  ulaz: ulaz,
  izlaz: izlaz,
  cijena: 2,
  vrijednostUlaz: ulaz * 2,
  vrijednostIzlaz: izlaz * 2,
  saldoKolicina: saldo,
  saldoVrijednost: saldo * 2,
);

void main() {
  test('tekući saldo ide od početnog stanja i ignoriše saldo sa servera', () {
    final (redovi, kraj) = tekuciSaldo(
      [
        _red(1, ulaz: 200, saldo: 300),
        _red(2, izlaz: 100, saldo: 400), // pogrešan saldo sa servera
        _red(3, izlaz: 50, saldo: 250),
      ],
      (100, 200),
    );

    expect(redovi.map((r) => r.saldoKolicina), [300, 200, 150]);
    expect(redovi.map((r) => r.saldoVrijednost), [600, 400, 300]);
    expect(kraj, (150.0, 300.0));
  });
}
