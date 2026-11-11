// Tipovi artikla iz API-ja.
const String tipRepromaterijal = 'raw_material';
const String tipGotovProizvod = 'finished_product';

// API vraća iznose kao stringove ("1.0059"), a neke kao null.
double? _broj(Object? value) =>
    value == null ? null : double.tryParse(value.toString());

// Artikal se u prikazu označava svojim ID-em (#12); šifra se ne prikazuje.
String idArtikla(int? id) => id == null ? '' : '#$id';

String nazivSaId(int? id, String naziv, {String razmak = ' — '}) =>
    id == null ? naziv : '#$id$razmak$naziv';

// Jedinice mjere koje API prihvata (šifarnik).
const List<String> jediniceMjereApi = [
  'pcs',
  'kg',
  'g',
  't',
  'l',
  'ml',
  'm',
  'm2',
  'm3',
  'h',
  'pkg',
];

// Jedinice mjere iz API-ja (pcs, pkg...) prikazane kao u aplikaciji.
String jmIzApi(String jm) => switch (jm) {
  'pcs' => 'kom',
  'pkg' => 'pak',
  _ => jm,
};

// Obrnuto: jedinica iz aplikacije kako je API očekuje.
String jmZaApi(String jm) => switch (jm) {
  'kom' => 'pcs',
  'pak' => 'pkg',
  _ => jm,
};

// Jedan red normativa: koliko čega (sirovine) ulazi u artikal. Stavka se
// veže za sirovinu preko materialId; naziv, cijenu i JM server preuzima od
// sirovine i vraća samo za prikaz.
class Normativ {
  final int? id;
  final int? materialId;
  final String naziv;
  final double cijena;
  final double kolicina;
  final String jm;

  // Iznos stavke (total) kako ga računa server; null za lokalne stavke.
  final double? _ukupno;

  const Normativ({
    this.id,
    this.materialId,
    required this.naziv,
    required this.cijena,
    required this.kolicina,
    required this.jm,
    double? ukupno,
  }) : _ukupno = ukupno;

  factory Normativ.fromJson(Map<String, dynamic> json) {
    return Normativ(
      id: json['id'] as int?,
      materialId: json['material_id'] as int?,
      naziv: json['name'] as String? ?? '',
      cijena: _broj(json['price']) ?? 0,
      kolicina: _broj(json['quantity']) ?? 0,
      jm: jmIzApi(json['unit_of_measure'] as String? ?? ''),
      ukupno: _broj(json['total']),
    );
  }

  double get iznos => _ukupno ?? cijena * kolicina;

  // Stare stavke nisu vezane za sirovinu; dok se ne povežu, radni nalog za
  // proizvod se ne može obraditi.
  bool get jePovezan => materialId != null;
}

class Artikal {
  final int? id;
  final String? tip;
  final String sifra;
  final String naziv;
  final String jm;

  // Repromaterijal: prosječna nabavna cijena; gotov proizvod: cijena
  // koštanja po normativu. Null dok se ne proknjiži kalkulacija.
  final double? cijena;
  final int? _brojNormativa;
  final List<Normativ> normativi;
  final DateTime? obrisan;

  // Repromaterijal: prag zalihe (minimum_quantity). Kad količina na stanju
  // padne ispod njega, aplikacija prikazuje upozorenje. Null = bez praga.
  final double? minimalnaKolicina;

  const Artikal({
    this.id,
    this.tip,
    required this.sifra,
    required this.naziv,
    required this.jm,
    this.cijena,
    int? brojNormativa,
    this.normativi = const [],
    this.obrisan,
    this.minimalnaKolicina,
  }) : _brojNormativa = brojNormativa;

  factory Artikal.fromJson(Map<String, dynamic> json) {
    final bomItems = json['bom_items'] as List?;

    return Artikal(
      id: json['id'] as int,
      tip: json['type'] as String?,
      sifra: json['code'] as String? ?? '',
      naziv: json['name'] as String,
      jm: jmIzApi(json['unit_of_measure'] as String),
      // Repromaterijal: average_purchase_price; gotov proizvod: cost_price.
      cijena: _broj(json['average_purchase_price'] ?? json['cost_price']),
      brojNormativa: json['bom_items_count'] as int?,
      normativi: bomItems == null
          ? const []
          : bomItems
                .map((e) => Normativ.fromJson(e as Map<String, dynamic>))
                .toList(),
      obrisan: DateTime.tryParse(json['deleted_at'] as String? ?? ''),
      minimalnaKolicina: _broj(json['minimum_quantity']),
    );
  }

  bool get jeObrisan => obrisan != null;

  bool get imaMinimalnuKolicinu =>
      minimalnaKolicina != null && minimalnaKolicina! > 0;

  // Količina je ispod praga minimalne zalihe.
  bool ispodMinimuma(double kolicina) =>
      imaMinimalnuKolicinu && kolicina < minimalnaKolicina!;

  int get brojNormativa => _brojNormativa ?? normativi.length;

  // Lista ne mora vratiti bom_items_count; tada se broj zna tek iz detalja.
  bool get poznatBrojNormativa =>
      _brojNormativa != null || normativi.isNotEmpty;

  bool get imaNepovezanihNormativa => normativi.any((n) => !n.jePovezan);

  double get cijenaNormativa =>
      cijena ?? normativi.fold<double>(0, (suma, n) => suma + n.iznos);
}
