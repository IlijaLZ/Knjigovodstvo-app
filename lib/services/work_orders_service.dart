import '../models/article.dart';
import '../models/utrosak.dart';
import '../models/work_order.dart';
import 'api_client.dart';

// Radni nalozi, njihova trebovanja i kupci za izbor na nalogu.

// Jedna stranica liste radnih naloga sa podacima iz `meta` paginacije.
class StranicaNaloga {
  final List<RadniNalog> nalozi;
  final int stranica;
  final int zadnjaStranica;
  final int ukupno;
  final int poStranici;
  final int? od;
  final int? doBroja;

  StranicaNaloga({
    required this.nalozi,
    required this.stranica,
    required this.zadnjaStranica,
    required this.ukupno,
    required this.poStranici,
    this.od,
    this.doBroja,
  });
}

class WorkOrdersService {
  final ApiClient _client = ApiClient();

  // GET /companies/{company}/customers — sve stranice, po nazivu.
  Future<List<Kupac>> fetchCustomers(int companyId) async {
    final rezultat = <Kupac>[];
    var stranica = 1;
    var zadnja = 1;

    do {
      final body = await _client.get(
        '/companies/$companyId/customers',
        query: {'sort': 'name', 'per_page': '100', 'page': '$stranica'},
      );
      rezultat.addAll(
        (body['data'] as List).map(
          (e) => Kupac.fromJson(e as Map<String, dynamic>),
        ),
      );
      zadnja = (body['meta']?['last_page'] as int?) ?? stranica;
      stranica++;
    } while (stranica <= zadnja);

    return rezultat;
  }

  // GET /companies/{company}/work-orders/articles?search=...&limit=...
  // Samo gotovi proizvodi sa normativom, zajedno sa stavkama normativa.
  Future<List<Artikal>> searchProducts(
    int companyId, {
    String? search,
    int limit = 20,
  }) async {
    final pretraga = search?.trim() ?? '';

    final body = await _client.get(
      '${_nalozi(companyId)}/articles',
      query: {
        if (pretraga.isNotEmpty)
          'search': pretraga.length > 100
              ? pretraga.substring(0, 100)
              : pretraga,
        'limit': '$limit',
      },
    );

    return (body['data'] as List)
        .map((e) => Artikal.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // GET /companies/{company}/work-orders
  // search: naziv kupca ili početak broja naloga.
  // status: draft | issued; trashed: with | only.
  Future<StranicaNaloga> fetchWorkOrders(
    int companyId, {
    int page = 1,
    String? search,
    String? status,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? trashed,
    String sort = 'date',
    String direction = 'desc',
    int? perPage,
  }) async {
    final pretraga = search?.trim() ?? '';

    final body = await _client.get(
      _nalozi(companyId),
      query: {
        'page': '$page',
        if (perPage != null) 'per_page': '$perPage',
        'sort': sort,
        'direction': direction,
        if (pretraga.isNotEmpty) 'search': pretraga,
        'status': ?status,
        if (dateFrom != null) 'date_from': datumZaApi(dateFrom),
        if (dateTo != null) 'date_to': datumZaApi(dateTo),
        'trashed': ?trashed,
      },
    );

    final meta = body['meta'] as Map<String, dynamic>? ?? const {};

    return StranicaNaloga(
      nalozi: (body['data'] as List)
          .map((e) => RadniNalog.fromJson(e as Map<String, dynamic>))
          .toList(),
      stranica: meta['current_page'] as int? ?? page,
      zadnjaStranica: meta['last_page'] as int? ?? page,
      ukupno: meta['total'] as int? ?? 0,
      poStranici: meta['per_page'] as int? ?? 0,
      od: meta['from'] as int?,
      doBroja: meta['to'] as int?,
    );
  }

  // GET /companies/{company}/reports/material-consumption
  // Utrošak materijala izdatih (neobrisanih) naloga; period po datumu
  // izdavanja. Bez paginacije. Sa poNalozima vraća i redove po nalogu,
  // proizvodu i materijalu. warehouseId je izvorni magacin naloga.
  Future<IzvjestajUtroska> fetchUtrosak(
    int companyId, {
    required DateTime dateFrom,
    required DateTime dateTo,
    int? warehouseId,
    bool poNalozima = false,
  }) async {
    final body = await _client.get(
      '/companies/$companyId/reports/material-consumption',
      query: {
        'date_from': datumZaApi(dateFrom),
        'date_to': datumZaApi(dateTo),
        if (warehouseId != null) 'warehouse_id': '$warehouseId',
        if (poNalozima) 'group_by': 'work_order',
      },
    );
    return IzvjestajUtroska.fromJson(body);
  }

  // GET /companies/{company}/work-orders/{workOrder} — sa trebovanjem.
  Future<RadniNalog> fetchWorkOrder(int companyId, int workOrderId) async {
    final body = await _client.get(_nalog(companyId, workOrderId));
    return _nalogIz(body);
  }

  // POST /companies/{company}/work-orders
  // Kreira nalog u statusu draft zajedno sa trebovanjem.
  Future<RadniNalog> createWorkOrder(
    int companyId, {
    required int customerId,
    required String orderNumber,
    required List<StavkaNaloga> items,
    DateTime? date,
    String? issuedBy,
    String? signedBy,
  }) async {
    final body = await _client.post(_nalozi(companyId), {
      'customer_id': customerId,
      if (date != null) 'date': datumZaApi(date),
      'order_number': orderNumber,
      'issued_by': _prazno(issuedBy),
      'signed_by': _prazno(signedBy),
      'items': items.map((s) => s.toJson()).toList(),
    });
    return _nalogIz(body);
  }

  // PATCH /companies/{company}/work-orders/{workOrder} — samo draft.
  // Ako se pošalje items, zamjenjuju se sve stavke i materijali trebovanja.
  Future<RadniNalog> updateWorkOrder(
    int companyId,
    int workOrderId, {
    int? customerId,
    String? orderNumber,
    List<StavkaNaloga>? items,
    DateTime? date,
    String? issuedBy,
    String? signedBy,
  }) async {
    final body = await _client.patch(_nalog(companyId, workOrderId), {
      'customer_id': ?customerId,
      if (date != null) 'date': datumZaApi(date),
      'order_number': ?orderNumber,
      if (issuedBy != null) 'issued_by': _prazno(issuedBy),
      if (signedBy != null) 'signed_by': _prazno(signedBy),
      if (items != null) 'items': items.map((s) => s.toJson()).toList(),
    });
    return _nalogIz(body);
  }

  // POST /companies/{company}/work-orders/{workOrder}/issue
  // Skida materijal sa skladišta sirovina; 422 (errors.stock) ako nema
  // dovoljno zalihe — tada se ništa ne mijenja.
  Future<RadniNalog> issueWorkOrder(int companyId, int workOrderId) async {
    final body = await _client.post('${_nalog(companyId, workOrderId)}/issue');
    return _nalogIz(body);
  }

  // GET /companies/{company}/work-orders/{workOrder}/requisition
  Future<Trebovanje> fetchRequisition(int companyId, int workOrderId) async {
    final body = await _client.get(
      '${_nalog(companyId, workOrderId)}/requisition',
    );
    return Trebovanje.fromJson(body['data'] as Map<String, dynamic>);
  }

  // DELETE /companies/{company}/work-orders/{workOrder} — meko, samo draft.
  Future<void> deleteWorkOrder(int companyId, int workOrderId) {
    return _client.delete(_nalog(companyId, workOrderId));
  }

  // POST /companies/{company}/work-orders/{workOrder}/restore
  Future<RadniNalog> restoreWorkOrder(int companyId, int workOrderId) async {
    final body = await _client.post(
      '${_nalog(companyId, workOrderId)}/restore',
    );
    return _nalogIz(body);
  }

  String _nalozi(int companyId) => '/companies/$companyId/work-orders';

  String _nalog(int companyId, int workOrderId) =>
      '${_nalozi(companyId)}/$workOrderId';

  // Prazno polje se šalje kao null (server ga tada briše).
  String? _prazno(String? tekst) {
    final t = tekst?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  RadniNalog _nalogIz(Map<String, dynamic> body) =>
      RadniNalog.fromJson(body['data'] as Map<String, dynamic>);
}
