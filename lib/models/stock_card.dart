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

  // Naziv promjene za prikaz (šifarnik "Vrsta promjene na zalihi").
  String get nazivDokumenta => switch (vrsta) {
    'purchase_receipt' => 'Kalkulacija',
    'requisition_issue' => 'Trebovanje (izlaz)',
    'production_receipt' => 'Trebovanje (ulaz u proizvodnju)',
    _ => vrsta,
  };
}

// Jedna stranica kartice sa podacima iz `meta` paginacije.
class StranicaKartice {
  final List<PromjenaKartice> promjene;
  final int stranica;
  final int zadnjaStranica;
  final int ukupno;
  final int? od;
  final int? doBroja;

  StranicaKartice({
    required this.promjene,
    required this.stranica,
    required this.zadnjaStranica,
    required this.ukupno,
    this.od,
    this.doBroja,
  });
}
