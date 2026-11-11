import 'article.dart';

// Statusi radnog naloga iz API-ja.
const String statusNacrt = 'draft';
const String statusIzdat = 'issued';

// API vraća iznose kao stringove ("200.0000"), a neke kao null.
double? _broj(Object? value) =>
    value == null ? null : double.tryParse(value.toString());

DateTime? _datum(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());

// Datum dokumenta kako ga API očekuje: YYYY-MM-DD.
String datumZaApi(DateTime datum) {
  final m = datum.month.toString().padLeft(2, '0');
  final d = datum.day.toString().padLeft(2, '0');
  return '${datum.year}-$m-$d';
}

class Kupac {
  final int id;
  final String naziv;
  final String? pib;
  final String? grad;

  const Kupac({required this.id, required this.naziv, this.pib, this.grad});

  factory Kupac.fromJson(Map<String, dynamic> json) {
    return Kupac(
      id: json['id'] as int,
      naziv: json['name'] as String,
      pib: json['tax_id'] as String?,
      grad: json['city'] as String?,
    );
  }
}

class Skladiste {
  final int id;
  final String tip;
  final String naziv;

  const Skladiste({required this.id, required this.tip, required this.naziv});

  factory Skladiste.fromJson(Map<String, dynamic> json) {
    return Skladiste(
      id: json['id'] as int,
      tip: json['type'] as String,
      naziv: nazivSkladista(json['type'] as String, json['name'] as String),
    );
  }
}

// API vraća engleske nazive skladišta; prikazuju se po tipu, kao u meniju.
String nazivSkladista(String tip, String naziv) => switch (tip) {
  'raw_materials' => 'Magacin repromaterijala',
  'production' => 'Proizvodnja u toku',
  'finished_goods' => 'Magacin gotovih proizvoda',
  _ => naziv,
};

// Jedan materijal trebovanja: stavka normativa pomnožena količinom proizvoda.
class MaterijalTrebovanja {
  final int id;
  final int bomItemId;
  final int? materialId;
  final String naziv;
  final String jm;
  final double norma;
  final double trazeno;

  // Ručno unesena (u pripremi) ili stvarno izdata količina (izdat nalog).
  final double? izdato;

  // Vrijednost po prosječnoj cijeni; postavlja se tek izdavanjem.
  final double? vrijednost;

  const MaterijalTrebovanja({
    required this.id,
    required this.bomItemId,
    this.materialId,
    required this.naziv,
    required this.jm,
    required this.norma,
    required this.trazeno,
    this.izdato,
    this.vrijednost,
  });

  factory MaterijalTrebovanja.fromJson(Map<String, dynamic> json) {
    return MaterijalTrebovanja(
      id: json['id'] as int,
      bomItemId: json['bom_item_id'] as int,
      materialId: json['material_id'] as int?,
      naziv: json['name'] as String,
      jm: jmIzApi(json['unit_of_measure'] as String),
      norma: _broj(json['norm_quantity']) ?? 0,
      trazeno: _broj(json['requested_quantity']) ?? 0,
      izdato: _broj(json['issued_quantity']),
      vrijednost: _broj(json['issued_value']),
    );
  }
}

// Jedan gotov proizvod na trebovanju sa svojim materijalima.
class StavkaTrebovanja {
  final int id;
  final int articleId;
  final String sifra;
  final String naziv;
  final String jm;
  final double kolicina;
  final List<MaterijalTrebovanja> materijali;

  const StavkaTrebovanja({
    required this.id,
    required this.articleId,
    required this.sifra,
    required this.naziv,
    required this.jm,
    required this.kolicina,
    this.materijali = const [],
  });

  factory StavkaTrebovanja.fromJson(Map<String, dynamic> json) {
    final materijali = json['materials'] as List? ?? const [];

    return StavkaTrebovanja(
      id: json['id'] as int,
      articleId: json['article_id'] as int,
      sifra: json['article_code'] as String? ?? '',
      naziv: json['article_name'] as String,
      jm: jmIzApi(json['unit_of_measure'] as String),
      kolicina: _broj(json['quantity']) ?? 0,
      materijali: materijali
          .map((e) => MaterijalTrebovanja.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class Trebovanje {
  final int id;
  final int workOrderId;
  final DateTime? datum;
  final List<StavkaTrebovanja> stavke;

  // Dolazi samo sa rute .../requisition.
  final String? brojNaloga;
  final String? kupac;

  const Trebovanje({
    required this.id,
    required this.workOrderId,
    this.datum,
    this.stavke = const [],
    this.brojNaloga,
    this.kupac,
  });

  factory Trebovanje.fromJson(Map<String, dynamic> json) {
    final nalog = json['work_order'] as Map<String, dynamic>?;
    final stavke = json['items'] as List? ?? const [];

    return Trebovanje(
      id: json['id'] as int,
      workOrderId: json['work_order_id'] as int,
      datum: _datum(json['date']),
      stavke: stavke
          .map((e) => StavkaTrebovanja.fromJson(e as Map<String, dynamic>))
          .toList(),
      brojNaloga: nalog?['order_number'] as String?,
      kupac: nalog?['customer_name'] as String?,
    );
  }

  Iterable<MaterijalTrebovanja> get materijali =>
      stavke.expand((s) => s.materijali);

  // Null dok nalog nije izdat (server još nije obračunao vrijednost).
  double? get vrijednost {
    final vrijednosti = materijali.map((m) => m.vrijednost).toList();
    if (vrijednosti.isEmpty || vrijednosti.any((v) => v == null)) return null;
    return vrijednosti.fold<double>(0, (suma, v) => suma + v!);
  }
}

class RadniNalog {
  final int id;
  final String status;
  final DateTime? datum;
  final int? customerId;
  final String? kupac;
  final String broj;
  final String? izdao;
  final String? potpisao;
  final Skladiste? izvor;
  final Skladiste? odrediste;
  final int? _brojStavki;
  final DateTime? izdatU;
  final DateTime? obrisan;

  // Lista naloga ga ne vraća, samo prikaz/kreiranje/izmjena/izdavanje.
  final Trebovanje? trebovanje;

  const RadniNalog({
    required this.id,
    required this.status,
    this.datum,
    this.customerId,
    this.kupac,
    required this.broj,
    this.izdao,
    this.potpisao,
    this.izvor,
    this.odrediste,
    int? brojStavki,
    this.izdatU,
    this.obrisan,
    this.trebovanje,
  }) : _brojStavki = brojStavki;

  factory RadniNalog.fromJson(Map<String, dynamic> json) {
    final izvor = json['source_warehouse'] as Map<String, dynamic>?;
    final odrediste = json['destination_warehouse'] as Map<String, dynamic>?;
    final trebovanje = json['requisition'] as Map<String, dynamic>?;

    return RadniNalog(
      id: json['id'] as int,
      status: json['status'] as String,
      datum: _datum(json['date']),
      customerId: json['customer_id'] as int?,
      kupac: json['customer_name'] as String?,
      broj: json['order_number'] as String? ?? '',
      izdao: json['issued_by'] as String?,
      potpisao: json['signed_by'] as String?,
      izvor: izvor == null ? null : Skladiste.fromJson(izvor),
      odrediste: odrediste == null ? null : Skladiste.fromJson(odrediste),
      brojStavki: json['items_count'] as int?,
      izdatU: _datum(json['issued_at']),
      obrisan: _datum(json['deleted_at']),
      trebovanje: trebovanje == null ? null : Trebovanje.fromJson(trebovanje),
    );
  }

  bool get jeIzdat => status == statusIzdat;

  bool get jeObrisan => obrisan != null;

  int get brojStavki => _brojStavki ?? trebovanje?.stavke.length ?? 0;
}

// Stavka koja se šalje pri kreiranju/izmjeni naloga. U izdato idu samo
// ručno unesene količine (ključ = id stavke normativa); ostali materijali
// se izdaju kako je traženo.
class StavkaNaloga {
  final int articleId;
  final double kolicina;
  final Map<int, double> izdato;

  const StavkaNaloga({
    required this.articleId,
    required this.kolicina,
    this.izdato = const {},
  });

  Map<String, dynamic> toJson() => {
    'article_id': articleId,
    'quantity': kolicina,
    if (izdato.isNotEmpty)
      'materials': izdato.entries
          .map((e) => {'bom_item_id': e.key, 'issued_quantity': e.value})
          .toList(),
  };
}
