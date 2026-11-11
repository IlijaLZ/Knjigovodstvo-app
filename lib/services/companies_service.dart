import '../models/company.dart';
import 'api_client.dart';

// Upravljanje firmama prijavljenog korisnika: /companies.

// Jedna stranica liste firmi sa podacima iz `meta` paginacije.
class StranicaFirmi {
  final List<Company> firme;
  final int stranica;
  final int zadnjaStranica;
  final int ukupno;
  final int? od;
  final int? doBroja;

  StranicaFirmi({
    required this.firme,
    required this.stranica,
    required this.zadnjaStranica,
    required this.ukupno,
    this.od,
    this.doBroja,
  });
}

class CompaniesService {
  final ApiClient _client = ApiClient();

  // GET /companies
  // search: naziv ili PIB (server dozvoljava max 100 znakova).
  // trashed: 'with' uključuje obrisane, 'only' samo obrisane.
  Future<StranicaFirmi> fetchCompanies({
    int page = 1,
    String? search,
    String? trashed,
  }) async {
    final pretraga = search?.trim() ?? '';

    final body = await _client.get(
      '/companies',
      query: {
        'sort': 'name',
        'page': '$page',
        if (pretraga.isNotEmpty)
          'search': pretraga.length > 100
              ? pretraga.substring(0, 100)
              : pretraga,
        'trashed': ?trashed,
      },
    );

    final meta = body['meta'] as Map<String, dynamic>? ?? const {};

    return StranicaFirmi(
      firme: (body['data'] as List)
          .map((e) => Company.fromJson(e as Map<String, dynamic>))
          .toList(),
      stranica: meta['current_page'] as int? ?? page,
      zadnjaStranica: meta['last_page'] as int? ?? page,
      ukupno: meta['total'] as int? ?? 0,
      od: meta['from'] as int?,
      doBroja: meta['to'] as int?,
    );
  }

  // POST /companies — server pravi i tri skladišta firme.
  Future<Company> createCompany(Company firma) async {
    final body = await _client.post(
      '/companies',
      firma.toJson()..removeWhere((_, v) => v == null),
    );
    return _firmaIz(body);
  }

  // PATCH /companies/{company} — šalju se samo izmijenjena polja.
  Future<Company> updateCompany(int id, Map<String, dynamic> izmjene) async {
    final body = await _client.patch('/companies/$id', izmjene);
    return _firmaIz(body);
  }

  // DELETE /companies/{company} — meko brisanje.
  Future<void> deleteCompany(int id) => _client.delete('/companies/$id');

  // POST /companies/{company}/restore
  Future<Company> restoreCompany(int id) async {
    final body = await _client.post('/companies/$id/restore');
    return _firmaIz(body);
  }

  Company _firmaIz(Map<String, dynamic> body) =>
      Company.fromJson(body['data'] as Map<String, dynamic>);
}
