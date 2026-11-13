import '../models/article.dart';
import '../models/auth_models.dart';
import '../models/company.dart';
import '../models/stock_card.dart';
import '../models/work_order.dart' show datumZaApi;
import 'api_client.dart';

// Firme, artikli i normativi prijavljenog korisnika.

// Jedna stranica liste artikala sa podacima iz `meta` paginacije.
class StranicaArtikala {
  final List<Artikal> artikli;
  final int stranica;
  final int zadnjaStranica;
  final int ukupno;
  final int poStranici;
  final int? od;
  final int? doBroja;

  StranicaArtikala({
    required this.artikli,
    required this.stranica,
    required this.zadnjaStranica,
    required this.ukupno,
    required this.poStranici,
    this.od,
    this.doBroja,
  });
}

class ArticlesService {
  final ApiClient _client = ApiClient();

  // GET /companies — sve stranice.
  Future<List<Company>> fetchCompanies() async {
    final data = await _sveStranice('/companies', {'sort': 'name'});
    return data.map(Company.fromJson).toList();
  }

  // GET /companies/{company}/articles?type=...&page=...
  // Veličinu stranice određuje server (per_page se ne šalje, čita se iz meta).
  // search: početak šifre ili dio naziva (server dozvoljava max 100 znakova).
  // trashed: 'with' uključuje obrisane, 'only' samo obrisane.
  Future<StranicaArtikala> fetchArticles(
    int companyId, {
    required String type,
    int page = 1,
    String? search,
    String? trashed,
    int? perPage,
    // Gotovi proizvodi sa aktivnim stavkama normativa (include=bom_items).
    bool saNormativima = false,
  }) async {
    final pretraga = search?.trim() ?? '';

    final body = await _client.get(
      '/companies/$companyId/articles',
      query: {
        if (saNormativima) 'include': 'bom_items',
        'type': type,
        'sort': 'code',
        'page': '$page',
        if (pretraga.isNotEmpty)
          'search': pretraga.length > 100
              ? pretraga.substring(0, 100)
              : pretraga,
        'trashed': ?trashed,
        if (perPage != null) 'per_page': '$perPage',
      },
    );

    final meta = body['meta'] as Map<String, dynamic>? ?? const {};

    return StranicaArtikala(
      artikli: (body['data'] as List)
          .map((e) => Artikal.fromJson(e as Map<String, dynamic>))
          .toList(),
      stranica: meta['current_page'] as int? ?? page,
      zadnjaStranica: meta['last_page'] as int? ?? page,
      ukupno: meta['total'] as int? ?? 0,
      poStranici: meta['per_page'] as int? ?? 0,
      od: meta['from'] as int?,
      doBroja: meta['to'] as int?,
    );
  }

  // Sirovine za izbor u stavci normativa: samo aktivni repromaterijal iste
  // firme (server druge odbija sa 422).
  // GET /companies/{company}/articles?type=raw_material&search=...&per_page=20
  Future<List<Artikal>> fetchMaterials(int companyId, {String? search}) async {
    final stranica = await fetchArticles(
      companyId,
      type: tipRepromaterijal,
      search: search,
      perPage: 20,
    );
    return stranica.artikli.where((a) => !a.jeObrisan).toList();
  }

  // GET /companies/{company}/articles/{article} — gotov proizvod dolazi sa
  // stavkama normativa.
  Future<Artikal> fetchArticle(int companyId, int articleId) async {
    final body = await _client.get(_artikal(companyId, articleId));
    return _artikalIz(body);
  }

  // POST /companies/{company}/articles
  // Gotov proizvod se kreira zajedno sa normativom (1–200 stavki, sirovina i
  // količina; ista sirovina se ne smije ponoviti).
  Future<Artikal> createArticle(
    int companyId, {
    required String type,
    String? code,
    required String name,
    required String unitOfMeasure,
    double? minimumQuantity,
    List<Normativ> bomItems = const [],
  }) async {
    final body = await _client.post('/companies/$companyId/articles', {
      'type': type,
      'code': ?code,
      'name': name,
      'unit_of_measure': jmZaApi(unitOfMeasure),
      if (type == tipRepromaterijal) 'minimum_quantity': minimumQuantity,
      if (type == tipGotovProizvod) 'bom_items': bomItems.map(_stavka).toList(),
    });
    return _artikalIz(body);
  }

  // PATCH /companies/{company}/articles/{article}
  // Mijenjaju se šifra, naziv, JM i minimalna količina (repromaterijal);
  // normativ ima svoje rute. Minimalna količina se šalje samo kad je
  // izmijenjena (izmijenjenMinimum); null tada briše prag.
  // Šifra se šalje samo kad je izmijenjena (izmijenjenaSifra); null je briše.
  Future<Artikal> updateArticle(
    int companyId,
    int articleId, {
    bool izmijenjenaSifra = false,
    String? code,
    String? name,
    String? unitOfMeasure,
    bool izmijenjenMinimum = false,
    double? minimumQuantity,
  }) async {
    final body = await _client.patch(_artikal(companyId, articleId), {
      if (izmijenjenaSifra) 'code': code,
      'name': ?name,
      if (unitOfMeasure != null) 'unit_of_measure': jmZaApi(unitOfMeasure),
      if (izmijenjenMinimum) 'minimum_quantity': minimumQuantity,
    });
    return _artikalIz(body);
  }

  // DELETE /companies/{company}/articles/{article} — meko brisanje.
  // GET /companies/{company}/articles/{article}/stock-card
  // Bez warehouseId vide se promjene na svim skladištima.
  // Sa dateFrom/dateTo meta nosi i početno stanje (prije dateFrom) i stanje
  // na kraju dana dateTo (bez dateTo: trenutno stanje).
  Future<StranicaKartice> fetchStockCard(
    int companyId,
    int articleId, {
    int? warehouseId,
    DateTime? dateFrom,
    DateTime? dateTo,
    int page = 1,
    int perPage = 50,
  }) async {
    final body = await _client.get(
      '/companies/$companyId/articles/$articleId/stock-card',
      query: {
        'page': '$page',
        'per_page': '$perPage',
        if (warehouseId != null) 'warehouse_id': '$warehouseId',
        if (dateFrom != null) 'date_from': datumZaApi(dateFrom),
        if (dateTo != null) 'date_to': datumZaApi(dateTo),
      },
    );

    final meta = body['meta'] as Map<String, dynamic>? ?? const {};

    return StranicaKartice(
      pocetnoStanje: StanjeKartice.fromJson(meta['opening_balance']),
      zavrsnoStanje: StanjeKartice.fromJson(meta['closing_balance']),
      promjene: (body['data'] as List)
          .map((e) => PromjenaKartice.fromJson(e as Map<String, dynamic>))
          .toList(),
      stranica: meta['current_page'] as int? ?? page,
      zadnjaStranica: meta['last_page'] as int? ?? page,
      ukupno: meta['total'] as int? ?? 0,
      od: meta['from'] as int?,
      doBroja: meta['to'] as int?,
    );
  }

  Future<void> deleteArticle(int companyId, int articleId) {
    return _client.delete(_artikal(companyId, articleId));
  }

  // POST /companies/{company}/articles/{article}/restore
  Future<Artikal> restoreArticle(int companyId, int articleId) async {
    final body = await _client.post(
      '${_artikal(companyId, articleId)}/restore',
    );
    return _artikalIz(body);
  }

  // GET /companies/{company}/articles/{article}/bom-items
  Future<List<Normativ>> fetchBomItems(int companyId, int articleId) async {
    final body = await _client.get(_normativi(companyId, articleId));
    return (body['data'] as List)
        .map((e) => Normativ.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // GET /companies/{company}/articles/{article}/bom-items/{bomItem}
  Future<Normativ> fetchBomItem(
    int companyId,
    int articleId,
    int bomItemId,
  ) async {
    final body = await _client.get(
      '${_normativi(companyId, articleId)}/$bomItemId',
    );
    return _normativIz(body);
  }

  // POST /companies/{company}/articles/{article}/bom-items
  Future<Normativ> addBomItem(
    int companyId,
    int articleId, {
    required int materialId,
    required double quantity,
  }) async {
    final body = await _client.post(_normativi(companyId, articleId), {
      'material_id': materialId,
      'quantity': quantity,
    });
    return _normativIz(body);
  }

  // PATCH /companies/{company}/articles/{article}/bom-items/{bomItem}
  // Šalje se sirovina, količina ili oboje; ovako se i stara (nepovezana)
  // stavka veže za sirovinu.
  Future<Normativ> updateBomItem(
    int companyId,
    int articleId,
    int bomItemId, {
    int? materialId,
    double? quantity,
  }) async {
    final body = await _client.patch(
      '${_normativi(companyId, articleId)}/$bomItemId',
      {'material_id': ?materialId, 'quantity': ?quantity},
    );
    return _normativIz(body);
  }

  // DELETE /companies/{company}/articles/{article}/bom-items/{bomItem}
  // Meko brisanje; posljednja stavka se ne može obrisati (422).
  Future<void> deleteBomItem(int companyId, int articleId, int bomItemId) {
    return _client.delete('${_normativi(companyId, articleId)}/$bomItemId');
  }

  // POST /companies/{company}/articles/{article}/bom-items/{bomItem}/restore
  Future<Normativ> restoreBomItem(
    int companyId,
    int articleId,
    int bomItemId,
  ) async {
    final body = await _client.post(
      '${_normativi(companyId, articleId)}/$bomItemId/restore',
    );
    return _normativIz(body);
  }

  String _artikal(int companyId, int articleId) =>
      '/companies/$companyId/articles/$articleId';

  String _normativi(int companyId, int articleId) =>
      '${_artikal(companyId, articleId)}/bom-items';

  // Stavka normativa je sirovina i količina; naziv, cijenu i JM server
  // preuzima od sirovine.
  Map<String, dynamic> _stavka(Normativ n) => {
    'material_id': n.materialId,
    'quantity': n.kolicina,
  };

  Artikal _artikalIz(Map<String, dynamic> body) =>
      Artikal.fromJson(body['data'] as Map<String, dynamic>);

  Normativ _normativIz(Map<String, dynamic> body) =>
      Normativ.fromJson(body['data'] as Map<String, dynamic>);

  Future<List<Map<String, dynamic>>> _sveStranice(
    String path,
    Map<String, String> query,
  ) async {
    final rezultat = <Map<String, dynamic>>[];
    var stranica = 1;
    var zadnja = 1;

    do {
      final body = await _client.get(
        path,
        query: {...query, 'page': '$stranica'},
      );
      // Odgovor bez liste se javlja kao ApiException (kontroleri je hvataju),
      // umjesto TypeError-a koji ruši učitavanje firmi.
      final data = body['data'];
      if (data is! List) {
        throw ApiException('Server je vratio neočekivan odgovor za $path.');
      }
      rezultat.addAll(data.cast<Map<String, dynamic>>());
      zadnja = (body['meta']?['last_page'] as int?) ?? stranica;
      stranica++;
    } while (stranica <= zadnja);

    return rezultat;
  }
}
