import 'article.dart';
import 'work_order.dart';

// Kalkulacija nabavnih cijena: /companies/{company}/purchase-calculations.
// Sve vrijednosti (zavisni troškovi, nabavne cijene, rekapitulaciju) računa
// server; klijent šalje samo zaglavlje, troškove i stavke.

// Statusi kalkulacije iz API-ja.
const String statusKalkulacijeNacrt = 'draft';
const String statusKalkulacijeProknjizena = 'booked';

// API vraća iznose kao stringove ("502.94"), a neke kao null.
double? _broj(Object? value) =>
    value == null ? null : double.tryParse(value.toString());

DateTime? _datum(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());

class StavkaKalkulacije {
  final int? id;
  final int articleId;
  final String sifra;
  final String naziv;
  final String? dokument;
  final String jm;
  final double kolicina;
  final double fakturnaCijena;
  final double fakturnaVrijednost;
  final double zavisniTrosak;
  final double nabavnaCijena;
  final double nabavnaVrijednost;

  const StavkaKalkulacije({
    this.id,
    required this.articleId,
    required this.sifra,
    required this.naziv,
    this.dokument,
    required this.jm,
    required this.kolicina,
    required this.fakturnaCijena,
    required this.fakturnaVrijednost,
    required this.zavisniTrosak,
    required this.nabavnaCijena,
    required this.nabavnaVrijednost,
  });

  factory StavkaKalkulacije.fromJson(Map<String, dynamic> json) {
    return StavkaKalkulacije(
      id: json['id'] as int?,
      articleId: json['article_id'] as int,
      sifra: json['article_code'] as String? ?? '',
      naziv: json['article_name'] as String? ?? '',
      dokument: json['document'] as String?,
      jm: jmIzApi(json['unit_of_measure'] as String? ?? ''),
      kolicina: _broj(json['quantity']) ?? 0,
      fakturnaCijena: _broj(json['invoice_price']) ?? 0,
      fakturnaVrijednost: _broj(json['invoice_value']) ?? 0,
      zavisniTrosak: _broj(json['dependent_cost']) ?? 0,
      nabavnaCijena: _broj(json['purchase_price']) ?? 0,
      nabavnaVrijednost: _broj(json['purchase_value']) ?? 0,
    );
  }
}

class RekapitulacijaKalkulacije {
  final double prevoz;
  final double spedicija;
  final double carina;
  final double fakturnaVrijednost;
  final double zavisniTroskovi;
  final double nabavnaVrijednost;
  final String? kalkulisao;
  final String? robuPrimio;

  const RekapitulacijaKalkulacije({
    this.prevoz = 0,
    this.spedicija = 0,
    this.carina = 0,
    this.fakturnaVrijednost = 0,
    this.zavisniTroskovi = 0,
    this.nabavnaVrijednost = 0,
    this.kalkulisao,
    this.robuPrimio,
  });

  factory RekapitulacijaKalkulacije.fromJson(Map<String, dynamic> json) {
    return RekapitulacijaKalkulacije(
      prevoz: _broj(json['transport_cost']) ?? 0,
      spedicija: _broj(json['forwarding_cost']) ?? 0,
      carina: _broj(json['customs_cost']) ?? 0,
      fakturnaVrijednost: _broj(json['invoice_value']) ?? 0,
      zavisniTroskovi: _broj(json['dependent_costs']) ?? 0,
      nabavnaVrijednost: _broj(json['purchase_value']) ?? 0,
      kalkulisao: json['calculated_by'] as String?,
      robuPrimio: json['received_by'] as String?,
    );
  }
}

class Kalkulacija {
  final int id;
  final String status;
  final DateTime? datum;
  final int? supplierId;
  final String? dobavljac;
  final String brojFakture;
  final String brojPrijemnice;
  final Skladiste? skladiste;
  final RekapitulacijaKalkulacije rekapitulacija;
  final int? _brojStavki;
  final DateTime? proknjizenaU;
  final DateTime? obrisana;

  // Lista kalkulacija ne vraća stavke, samo prikaz/kreiranje/izmjena.
  final List<StavkaKalkulacije> stavke;

  const Kalkulacija({
    required this.id,
    required this.status,
    this.datum,
    this.supplierId,
    this.dobavljac,
    required this.brojFakture,
    required this.brojPrijemnice,
    this.skladiste,
    this.rekapitulacija = const RekapitulacijaKalkulacije(),
    int? brojStavki,
    this.proknjizenaU,
    this.obrisana,
    this.stavke = const [],
  }) : _brojStavki = brojStavki;

  factory Kalkulacija.fromJson(Map<String, dynamic> json) {
    final skladiste = json['warehouse'] as Map<String, dynamic>?;
    final rekapitulacija = json['recapitulation'] as Map<String, dynamic>?;
    final stavke = json['items'] as List? ?? const [];

    return Kalkulacija(
      id: json['id'] as int,
      status: json['status'] as String,
      datum: _datum(json['date']),
      supplierId: json['supplier_id'] as int?,
      dobavljac: json['supplier_name'] as String?,
      brojFakture: json['invoice_number'] as String? ?? '',
      brojPrijemnice: json['receipt_number'] as String? ?? '',
      skladiste: skladiste == null ? null : Skladiste.fromJson(skladiste),
      rekapitulacija: rekapitulacija == null
          ? const RekapitulacijaKalkulacije()
          : RekapitulacijaKalkulacije.fromJson(rekapitulacija),
      brojStavki: json['items_count'] as int?,
      proknjizenaU: _datum(json['booked_at']),
      obrisana: _datum(json['deleted_at']),
      stavke: stavke
          .map((e) => StavkaKalkulacije.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  bool get jeProknjizena => status == statusKalkulacijeProknjizena;

  bool get jeObrisana => obrisana != null;

  int get brojStavki => _brojStavki ?? stavke.length;
}

// Stavka koja se šalje pri kreiranju/izmjeni kalkulacije.
class StavkaKalkulacijeZahtjev {
  final int articleId;
  final String? dokument;
  final double kolicina;
  final double fakturnaCijena;

  const StavkaKalkulacijeZahtjev({
    required this.articleId,
    this.dokument,
    required this.kolicina,
    required this.fakturnaCijena,
  });

  Map<String, dynamic> toJson() {
    final dok = dokument?.trim() ?? '';
    return {
      'article_id': articleId,
      'document': dok.isEmpty ? null : dok,
      'quantity': kolicina,
      'invoice_price': fakturnaCijena,
    };
  }
}
