import 'article.dart';

// Utrošak materijala: GET /companies/{company}/reports/material-consumption.
// Samo izdati, neobrisani nalozi; period po datumu izdavanja (issued_at).

double _broj(Object? value) =>
    value == null ? 0 : double.tryParse(value.toString()) ?? 0;

DateTime? _datum(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());

// Jedan red po materijalu.
class UtrosakMaterijala {
  final int? materialId;
  final String sifra;
  final String naziv;
  final String jm;
  final double kolicina;
  final double vrijednost;
  final int brojNaloga;

  const UtrosakMaterijala({
    this.materialId,
    required this.sifra,
    required this.naziv,
    required this.jm,
    required this.kolicina,
    required this.vrijednost,
    required this.brojNaloga,
  });

  factory UtrosakMaterijala.fromJson(Map<String, dynamic> json) {
    return UtrosakMaterijala(
      materialId: json['material_id'] as int?,
      sifra: json['code'] as String? ?? '',
      naziv: json['name'] as String? ?? '',
      jm: jmIzApi(json['unit_of_measure'] as String? ?? ''),
      kolicina: _broj(json['issued_quantity']),
      vrijednost: _broj(json['issued_value']),
      brojNaloga: json['work_orders_count'] as int? ?? 0,
    );
  }

  double? get prosjecnaCijena => kolicina == 0 ? null : vrijednost / kolicina;
}

// Jedan red po nalogu, proizvodu i materijalu (group_by=work_order).
class UtrosakPoNalogu {
  final int workOrderId;
  final String brojNaloga;
  final DateTime? datum;
  final DateTime? izdatU;
  final String? kupac;
  final String? sifraProizvoda;
  final String? proizvod;
  final double kolicinaProizvoda;
  final String sifra;
  final String naziv;
  final String jm;
  final double kolicina;
  final double vrijednost;

  const UtrosakPoNalogu({
    required this.workOrderId,
    required this.brojNaloga,
    this.datum,
    this.izdatU,
    this.kupac,
    this.sifraProizvoda,
    this.proizvod,
    required this.kolicinaProizvoda,
    required this.sifra,
    required this.naziv,
    required this.jm,
    required this.kolicina,
    required this.vrijednost,
  });

  factory UtrosakPoNalogu.fromJson(Map<String, dynamic> json) {
    return UtrosakPoNalogu(
      workOrderId: json['work_order_id'] as int,
      brojNaloga: json['order_number'] as String? ?? '',
      datum: _datum(json['date']),
      izdatU: _datum(json['issued_at']),
      kupac: json['customer_name'] as String?,
      sifraProizvoda: json['product_code'] as String?,
      proizvod: json['product_name'] as String?,
      kolicinaProizvoda: _broj(json['product_quantity']),
      sifra: json['code'] as String? ?? '',
      naziv: json['name'] as String? ?? '',
      jm: jmIzApi(json['unit_of_measure'] as String? ?? ''),
      kolicina: _broj(json['issued_quantity']),
      vrijednost: _broj(json['issued_value']),
    );
  }
}

class IzvjestajUtroska {
  final List<UtrosakMaterijala> materijali;
  final List<UtrosakPoNalogu> poNalozima;
  final double ukupnaVrijednost;

  const IzvjestajUtroska({
    required this.materijali,
    this.poNalozima = const [],
    required this.ukupnaVrijednost,
  });

  factory IzvjestajUtroska.fromJson(Map<String, dynamic> json) {
    final materijali = (json['data'] as List? ?? const [])
        .map((e) => UtrosakMaterijala.fromJson(e as Map<String, dynamic>))
        .toList();
    final meta = json['meta'] as Map<String, dynamic>? ?? const {};
    return IzvjestajUtroska(
      materijali: materijali,
      poNalozima: (json['work_orders'] as List? ?? const [])
          .map((e) => UtrosakPoNalogu.fromJson(e as Map<String, dynamic>))
          .toList(),
      ukupnaVrijednost: meta.containsKey('issued_value')
          ? _broj(meta['issued_value'])
          : materijali.fold(0, (s, m) => s + m.vrijednost),
    );
  }
}
