import '../models/fiscal_year.dart';
import 'api_client.dart';

// Poslovne godine: GET /companies/{company}/fiscal-years (najnovija prva,
// bez paginacije), zaključivanje i ponovno otvaranje. Akcija koja nije
// dozvoljena vraća 422 sa porukom u errors.year[0].
class FiscalYearsService {
  final ApiClient _client = ApiClient();

  Future<List<PoslovnaGodina>> fetchFiscalYears(int companyId) async {
    final body = await _client.get(_godine(companyId));
    return (body['data'] as List)
        .map((e) => PoslovnaGodina.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PoslovnaGodina> fetchFiscalYear(int companyId, int year) async {
    final body = await _client.get('${_godine(companyId)}/$year');
    return _godinaIz(body);
  }

  // POST /fiscal-years/{year}/close (bez body-ja).
  Future<PoslovnaGodina> closeFiscalYear(int companyId, int year) async {
    final body = await _client.post('${_godine(companyId)}/$year/close');
    return _godinaIz(body);
  }

  // POST /fiscal-years/{year}/reopen (bez body-ja).
  Future<PoslovnaGodina> reopenFiscalYear(int companyId, int year) async {
    final body = await _client.post('${_godine(companyId)}/$year/reopen');
    return _godinaIz(body);
  }

  String _godine(int companyId) => '/companies/$companyId/fiscal-years';

  PoslovnaGodina _godinaIz(Map<String, dynamic> body) =>
      PoslovnaGodina.fromJson(body['data'] as Map<String, dynamic>);
}
