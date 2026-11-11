import '../models/article.dart';
import '../models/stock.dart';
import 'api_client.dart';
import 'articles_service.dart';

class StocksService {
  final ApiClient _client = ApiClient();
  final ArticlesService _articles = ArticlesService();

  // GET /companies/{company}/stocks?warehouse_id=...&search=...&page=...
  // search: šifra ili naziv artikla (server dozvoljava max 100 znakova).
  Future<StranicaStanja> fetchStocks(
    int companyId, {
    int? warehouseId,
    String? search,
    int page = 1,
    int perPage = 15,
  }) async {
    final pretraga = search?.trim() ?? '';

    final body = await _client.get(
      '/companies/$companyId/stocks',
      query: {
        'page': '$page',
        'per_page': '$perPage',
        if (warehouseId != null) 'warehouse_id': '$warehouseId',
        if (pretraga.isNotEmpty)
          'search': pretraga.length > 100
              ? pretraga.substring(0, 100)
              : pretraga,
      },
    );

    final meta = body['meta'] as Map<String, dynamic>? ?? const {};

    return StranicaStanja(
      stanja: (body['data'] as List)
          .map((e) => StanjeArtikla.fromJson(e as Map<String, dynamic>))
          .toList(),
      stranica: meta['current_page'] as int? ?? page,
      zadnjaStranica: meta['last_page'] as int? ?? page,
      ukupno: meta['total'] as int? ?? 0,
      od: meta['from'] as int?,
      doBroja: meta['to'] as int?,
    );
  }

  // GET /companies/{company}/articles/low-stock — repromaterijal sa pragom
  // čija je količina na magacinu repromaterijala ispod praga (artikli koji
  // nikad nisu bili na stanju dolaze sa 0). Sve stranice; sortirano od
  // najkritičnijeg (najmanji udio stanja u pragu).
  Future<List<NiskaZaliha>> fetchIspodMinimuma(int companyId) async {
    final rezultat = <NiskaZaliha>[];
    var stranica = 1;
    var zadnja = 1;

    do {
      final body = await _client.get(
        '/companies/$companyId/articles/low-stock',
        query: {'page': '$stranica', 'per_page': '100'},
      );
      for (final e in (body['data'] as List).cast<Map<String, dynamic>>()) {
        rezultat.add(
          NiskaZaliha(
            artikal: Artikal.fromJson(e),
            kolicina: double.tryParse('${e['stock_quantity']}') ?? 0,
          ),
        );
      }
      zadnja = (body['meta']?['last_page'] as int?) ?? stranica;
      stranica++;
    } while (stranica <= zadnja);

    double udio(NiskaZaliha z) => z.minimum <= 0 ? 1 : z.kolicina / z.minimum;
    rezultat.sort((a, b) => udio(a).compareTo(udio(b)));
    return rezultat;
  }

  // Sabira sve promjene kartice artikla na skladištu
  // (GET …/articles/{article}/stock-card, po 200 promjena po stranici).
  Future<SumeKartice> fetchSume(
    int companyId,
    int articleId, {
    int? warehouseId,
  }) async {
    DateTime? zadnjiDatum;
    double ulaz = 0, izlaz = 0, vrijednostUlaz = 0, vrijednostIzlaz = 0;

    var stranica = 1;
    var zadnja = 1;

    do {
      final rezultat = await _articles.fetchStockCard(
        companyId,
        articleId,
        warehouseId: warehouseId,
        page: stranica,
        perPage: 200,
      );

      for (final p in rezultat.promjene) {
        ulaz += p.ulaz;
        izlaz += p.izlaz;
        vrijednostUlaz += p.vrijednostUlaz;
        vrijednostIzlaz += p.vrijednostIzlaz;
        if (p.datum != null &&
            (zadnjiDatum == null || p.datum!.isAfter(zadnjiDatum))) {
          zadnjiDatum = p.datum;
        }
      }

      zadnja = rezultat.zadnjaStranica;
      stranica++;
    } while (stranica <= zadnja);

    return SumeKartice(
      zadnjiDatum: zadnjiDatum,
      ulaz: ulaz,
      izlaz: izlaz,
      vrijednostUlaz: vrijednostUlaz,
      vrijednostIzlaz: vrijednostIzlaz,
    );
  }
}
