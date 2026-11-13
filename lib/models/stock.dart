import 'article.dart';
import 'work_order.dart';

// Stanje zaliha: GET /companies/{company}/stocks.
// Jedan red je jedan artikal na jednom skladištu (trenutna količina,
// prosječna cijena i vrijednost).

double _broj(Object? value) =>
    value == null ? 0 : double.tryParse(value.toString()) ?? 0;

class StanjeArtikla {
  final int id;
  final Skladiste? skladiste;
  final Artikal artikal;
  final double kolicina;
  final double prosjecnaCijena;
  final double vrijednost;

  // Ulazi/izlazi (za period, ako je zadat; inače sva kretanja). Null ako
  // ih server ne vrati — tada se sabiraju iz kartice artikla.
  final SumeKartice? sume;

  const StanjeArtikla({
    required this.id,
    this.skladiste,
    required this.artikal,
    required this.kolicina,
    required this.prosjecnaCijena,
    required this.vrijednost,
    this.sume,
  });

  factory StanjeArtikla.fromJson(Map<String, dynamic> json) {
    final skladiste = json['warehouse'] as Map<String, dynamic>?;

    return StanjeArtikla(
      id: json['id'] as int,
      skladiste: skladiste == null ? null : Skladiste.fromJson(skladiste),
      artikal: Artikal.fromJson(json['article'] as Map<String, dynamic>),
      kolicina: _broj(json['quantity']),
      prosjecnaCijena: _broj(json['average_price']),
      vrijednost: _broj(json['value']),
      sume: json.containsKey('in_quantity')
          ? SumeKartice(
              zadnjiDatum: DateTime.tryParse(
                json['last_movement_date'] as String? ?? '',
              ),
              ulaz: _broj(json['in_quantity']),
              izlaz: _broj(json['out_quantity']),
              vrijednostUlaz: _broj(json['in_value']),
              vrijednostIzlaz: _broj(json['out_value']),
            )
          : null,
    );
  }
}

// Repromaterijal čija je količina na stanju ispod minimalne količine.
class NiskaZaliha {
  final Artikal artikal;
  final double kolicina;

  const NiskaZaliha({required this.artikal, required this.kolicina});

  double get minimum => artikal.minimalnaKolicina ?? 0;

  // Koliko nedostaje do praga.
  double get nedostaje => minimum - kolicina;
}

// Sume ulaza i izlaza sa kartice artikla na jednom skladištu.
// API ih ne vraća u /stocks, pa se računaju iz svih promjena kartice.
class SumeKartice {
  final DateTime? zadnjiDatum;
  final double ulaz;
  final double izlaz;
  final double vrijednostUlaz;
  final double vrijednostIzlaz;

  const SumeKartice({
    this.zadnjiDatum,
    required this.ulaz,
    required this.izlaz,
    required this.vrijednostUlaz,
    required this.vrijednostIzlaz,
  });
}

// Jedna stranica stanja sa podacima iz `meta` paginacije.
class StranicaStanja {
  final List<StanjeArtikla> stanja;
  final int stranica;
  final int zadnjaStranica;
  final int ukupno;
  final int? od;
  final int? doBroja;

  StranicaStanja({
    required this.stanja,
    required this.stranica,
    required this.zadnjaStranica,
    required this.ukupno,
    this.od,
    this.doBroja,
  });
}
