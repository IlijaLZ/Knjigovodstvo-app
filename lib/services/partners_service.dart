import '../models/partner.dart';
import 'api_client.dart';

// Dobavljači i kupci firme: /companies/{company}/suppliers|customers.

// Jedna stranica liste partnera sa podacima iz `meta` paginacije.
class StranicaPartnera {
  final List<Partner> partneri;
  final int stranica;
  final int zadnjaStranica;
  final int ukupno;
  final int? od;
  final int? doBroja;

  StranicaPartnera({
    required this.partneri,
    required this.stranica,
    required this.zadnjaStranica,
    required this.ukupno,
    this.od,
    this.doBroja,
  });
}

class PartnersService {
  final ApiClient _client = ApiClient();

  // GET /companies/{company}/{vrsta}
  // search: dio naziva ili početak PIB-a (server dozvoljava max 100 znakova).
  // trashed: 'with' uključuje obrisane, 'only' samo obrisane.
  Future<StranicaPartnera> fetchPartners(
    int companyId,
    VrstaPartnera vrsta, {
    int page = 1,
    String? search,
    String? trashed,
    int? perPage,
  }) async {
    final pretraga = search?.trim() ?? '';

    final body = await _client.get(
      _lista(companyId, vrsta),
      query: {
        'sort': 'name',
        'page': '$page',
        if (perPage != null) 'per_page': '$perPage',
        if (pretraga.isNotEmpty)
          'search': pretraga.length > 100
              ? pretraga.substring(0, 100)
              : pretraga,
        'trashed': ?trashed,
      },
    );

    final meta = body['meta'] as Map<String, dynamic>? ?? const {};

    return StranicaPartnera(
      partneri: (body['data'] as List)
          .map((e) => Partner.fromJson(e as Map<String, dynamic>))
          .toList(),
      stranica: meta['current_page'] as int? ?? page,
      zadnjaStranica: meta['last_page'] as int? ?? page,
      ukupno: meta['total'] as int? ?? 0,
      od: meta['from'] as int?,
      doBroja: meta['to'] as int?,
    );
  }

  // POST /companies/{company}/{vrsta}
  Future<Partner> createPartner(
    int companyId,
    VrstaPartnera vrsta,
    Partner partner,
  ) async {
    final body = await _client.post(
      _lista(companyId, vrsta),
      partner.toJson()..removeWhere((_, v) => v == null),
    );
    return _partnerIz(body);
  }

  // PATCH /companies/{company}/{vrsta}/{id} — šalju se samo izmijenjena polja.
  Future<Partner> updatePartner(
    int companyId,
    VrstaPartnera vrsta,
    int partnerId,
    Map<String, dynamic> izmjene,
  ) async {
    final body = await _client.patch(
      _partner(companyId, vrsta, partnerId),
      izmjene,
    );
    return _partnerIz(body);
  }

  // DELETE /companies/{company}/{vrsta}/{id} — meko brisanje.
  Future<void> deletePartner(int companyId, VrstaPartnera vrsta, int id) {
    return _client.delete(_partner(companyId, vrsta, id));
  }

  // POST /companies/{company}/{vrsta}/{id}/restore
  Future<Partner> restorePartner(
    int companyId,
    VrstaPartnera vrsta,
    int id,
  ) async {
    final body = await _client.post(
      '${_partner(companyId, vrsta, id)}/restore',
    );
    return _partnerIz(body);
  }

  String _lista(int companyId, VrstaPartnera vrsta) =>
      '/companies/$companyId/${vrsta.ruta}';

  String _partner(int companyId, VrstaPartnera vrsta, int id) =>
      '${_lista(companyId, vrsta)}/$id';

  Partner _partnerIz(Map<String, dynamic> body) =>
      Partner.fromJson(body['data'] as Map<String, dynamic>);
}
