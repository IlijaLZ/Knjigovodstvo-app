import '../models/article.dart';
import '../models/company.dart';
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
  }) async {
    final pretraga = search?.trim() ?? '';

    final body = await _client.get(
      '/companies/$companyId/articles',
      query: {
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

  // GET /companies/{company}/articles/{article} — gotov proizvod dolazi sa
  // stavkama normativa.
  Future<Artikal> fetchArticle(int companyId, int articleId) async {
    final body = await _client.get(_artikal(companyId, articleId));
    return _artikalIz(body);
  }

  // POST /companies/{company}/articles
  // Gotov proizvod se kreira zajedno sa normativom (material_id + quantity);
  // naziv, JM i cijenu stavke server preuzima sa repromaterijala.
  Future<Artikal> createArticle(
    int companyId, {
    required String type,
    required String code,
    required String name,
    required String unitOfMeasure,
    List<Normativ> bomItems = const [],
  }) async {
    final body = await _client.post('/companies/$companyId/articles', {
      'type': type,
      'code': code,
      'name': name,
      'unit_of_measure': jmZaApi(unitOfMeasure),
      if (type == tipGotovProizvod) 'bom_items': bomItems.map(_stavka).toList(),
    });
    return _artikalIz(body);
  }

  // PATCH /companies/{company}/articles/{article}
  // Mijenjaju se samo šifra, naziv i JM; normativ ima svoje rute.
  Future<Artikal> updateArticle(
    int companyId,
    int articleId, {
    String? code,
    String? name,
    String? unitOfMeasure,
  }) async {
    final body = await _client.patch(_artikal(companyId, articleId), {
      'code': ?code,
      'name': ?name,
      if (unitOfMeasure != null) 'unit_of_measure': jmZaApi(unitOfMeasure),
    });
    return _artikalIz(body);
  }

  // DELETE /companies/{company}/articles/{article} — meko brisanje.
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
      rezultat.addAll((body['data'] as List).cast<Map<String, dynamic>>());
      zadnja = (body['meta']?['last_page'] as int?) ?? stranica;
      stranica++;
    } while (stranica <= zadnja);

    return rezultat;
  }
}
