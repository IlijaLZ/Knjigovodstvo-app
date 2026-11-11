import 'work_order.dart';

// Kartica artikla: GET /companies/{company}/articles/{article}/stock-card.
// Svaki red je jedna promjena na zalihi (ulaz/izlaz) sa saldom nakon nje.

double _broj(Object? value) =>
    value == null ? 0 : double.tryParse(value.toString()) ?? 0;

class PromjenaKartice {
  final int id;
  final DateTime? datum;
  final String vrsta;
  final Skladiste? skladiste;
  final String? vrstaDokumenta;
  final int? dokumentId;
  final String? brojDokumenta;
  final double ulaz;
  final double izlaz;
  final double cijena;
  final double vrijednostUlaz;
  final double vrijednostIzlaz;
  final double saldoKolicina;
  final double saldoVrijednost;

  const PromjenaKartice({
    required this.id,
    this.datum,
    required this.vrsta,
    this.skladiste,
    this.vrstaDokumenta,
    this.dokumentId,
    this.brojDokumenta,
    required this.ulaz,
    required this.izlaz,
    required this.cijena,
    required this.vrijednostUlaz,
    required this.vrijednostIzlaz,
    required this.saldoKolicina,
    required this.saldoVrijednost,
  });

  factory PromjenaKartice.fromJson(Map<String, dynamic> json) {
    final skladiste = json['warehouse'] as Map<String, dynamic>?;

    return PromjenaKartice(
      id: json['id'] as int,
      datum: DateTime.tryParse(json['date'] as String? ?? ''),
      vrsta: json['type'] as String? ?? '',
      skladiste: skladiste == null ? null : Skladiste.fromJson(skladiste),
      vrstaDokumenta: json['document_type'] as String?,
      dokumentId: json['document_id'] as int?,
      brojDokumenta: json['document_number'] as String?,
      ulaz: _broj(json['quantity_in']),
      izlaz: _broj(json['quantity_out']),
      cijena: _broj(json['price']),
      vrijednostUlaz: _broj(json['value_in']),
      vrijednostIzlaz: _broj(json['value_out']),
      saldoKolicina: _broj(json['balance_quantity']),
      saldoVrijednost: _broj(json['balance_value']),
    );
  }

  // Ista promjena sa zadatim saldom (tekući saldo izračunat u aplikaciji).
  PromjenaKartice saSaldom(double kolicina, double vrijednost) {
    return PromjenaKartice(
      id: id,
      datum: datum,
      vrsta: vrsta,
      skladiste: skladiste,
      vrstaDokumenta: vrstaDokumenta,
      dokumentId: dokumentId,
      brojDokumenta: brojDokumenta,
      ulaz: ulaz,
      izlaz: izlaz,
      cijena: cijena,
      vrijednostUlaz: vrijednostUlaz,
      vrijednostIzlaz: vrijednostIzlaz,
      saldoKolicina: kolicina,
      saldoVrijednost: vrijednost,
    );
  }

  // Prosječna nabavna cijena nakon ove promjene (saldo vrijednosti / saldo
  // količine). Polje `price` to nije uvijek: na prijemu je nabavna cijena
  // tog prijema, a na izdavanju prosjek prije izdavanja. Kad je zaliha 0,
  // prosjek se ne može izračunati, pa se prikazuje `price`.
  double get prosjecnaCijena =>
      saldoKolicina == 0 ? cijena : saldoVrijednost / saldoKolicina;

  // Naziv promjene za prikaz (šifarnik "Vrsta promjene na zalihi").
  String get nazivDokumenta => switch (vrsta) {
    'purchase_receipt' => 'Kalkulacija',
    'requisition_issue' => 'Trebovanje (izlaz)',
    'production_receipt' => 'Trebovanje (ulaz u proizvodnju)',
    _ => vrsta,
  };
}

// Stanje kartice na dan (meta.opening_balance / meta.closing_balance).
// datum je null kod završnog stanja bez date_to (trenutno stanje).
class StanjeKartice {
  final DateTime? datum;
  final double kolicina;
  final double vrijednost;

  const StanjeKartice({
    this.datum,
    required this.kolicina,
    required this.vrijednost,
  });

  static StanjeKartice? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return StanjeKartice(
      datum: DateTime.tryParse(json['date'] as String? ?? ''),
      kolicina: _broj(json['quantity']),
      vrijednost: _broj(json['value']),
    );
  }

  // Prosječna nabavna cijena stanja (0 kad nema zalihe).
  double get prosjecnaCijena => kolicina == 0 ? 0 : vrijednost / kolicina;
}

// Jedna stranica kartice sa podacima iz `meta` paginacije.
class StranicaKartice {
  final List<PromjenaKartice> promjene;
  final int stranica;
  final int zadnjaStranica;
  final int ukupno;
  final int? od;
  final int? doBroja;

  // Stanje prije date_from (null bez date_from).
  final StanjeKartice? pocetnoStanje;

  // Stanje na kraju dana date_to; bez date_to trenutno stanje.
  final StanjeKartice? zavrsnoStanje;

  StranicaKartice({
    required this.promjene,
    required this.stranica,
    required this.zadnjaStranica,
    required this.ukupno,
    this.od,
    this.doBroja,
    this.pocetnoStanje,
    this.zavrsnoStanje,
  });
}

double _zaokruzi(double v, int decimale) =>
    double.parse(v.toStringAsFixed(decimale));

// Tekući saldo: od stanja [pocetak] (količina, vrijednost) svaki red dodaje
// ulaz i oduzima izlaz, redom kojim su promjene prikazane. Saldo redova sa
// servera se ne koristi, pa saldo uvijek odgovara prometu u tabeli.
// Vraća promjene sa saldom i stanje nakon zadnje promjene.
(List<PromjenaKartice>, (double, double)) tekuciSaldo(
  List<PromjenaKartice> promjene,
  (double, double) pocetak,
) {
  var (kolicina, vrijednost) = pocetak;
  final rezultat = <PromjenaKartice>[];
  for (final p in promjene) {
    kolicina = _zaokruzi(kolicina + p.ulaz - p.izlaz, 4);
    vrijednost = _zaokruzi(
      vrijednost + p.vrijednostUlaz - p.vrijednostIzlaz,
      2,
    );
    rezultat.add(p.saSaldom(kolicina, vrijednost));
  }
  return (rezultat, (kolicina, vrijednost));
}
