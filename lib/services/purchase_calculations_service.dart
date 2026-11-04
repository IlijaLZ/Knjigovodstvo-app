import '../models/article.dart';
import '../models/partner.dart';
import '../models/purchase_calculation.dart';
import '../models/work_order.dart';
import 'api_client.dart';

// Kalkulacije nabavnih cijena, skladišta i dobavljači za izbor na kalkulaciji.

// Jedna stranica liste kalkulacija sa podacima iz `meta` paginacije.
class StranicaKalkulacija {
  final List<Kalkulacija> kalkulacije;
  final int stranica;
  final int zadnjaStranica;
  final int ukupno;
  final int? od;
  final int? doBroja;

  StranicaKalkulacija({
    required this.kalkulacije,
    required this.stranica,
    required this.zadnjaStranica,
    required this.ukupno,
    this.od,
    this.doBroja,
  });
}

class PurchaseCalculationsService {
  final ApiClient _client = ApiClient();

  // GET /companies/{company}/warehouses — sva tri skladišta firme.
  Future<List<Skladiste>> fetchWarehouses(int companyId) async {
    final body = await _client.get('/companies/$companyId/warehouses');
    return (body['data'] as List)
        .map((e) => Skladiste.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // GET /companies/{company}/suppliers — sve stranice, po nazivu.
  Future<List<Partner>> fetchSuppliers(int companyId) async {
    final rezultat = <Partner>[];
    var stranica = 1;
    var zadnja = 1;

    do {
      final body = await _client.get(
        '/companies/$companyId/suppliers',
        query: {'sort': 'name', 'per_page': '100', 'page': '$stranica'},
      );
      rezultat.addAll(
        (body['data'] as List).map(
          (e) => Partner.fromJson(e as Map<String, dynamic>),
        ),
      );
      zadnja = (body['meta']?['last_page'] as int?) ?? stranica;
      stranica++;
    } while (stranica <= zadnja);

    return rezultat;
  }

  // GET /companies/{company}/purchase-calculations/articles?search=&limit=
  // Artikli bilo kog tipa, po šifri ili nazivu.
  Future<List<Artikal>> searchArticles(
    int companyId, {
    String? search,
    int limit = 20,
  }) async {
    final pretraga = search?.trim() ?? '';

    final body = await _client.get(
      '${_kalkulacije(companyId)}/articles',
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

  // GET /companies/{company}/purchase-calculations
  // search: naziv dobavljača, početak broja fakture ili prijemnice.
  // status: draft | booked; trashed: with | only.
  Future<StranicaKalkulacija> fetchCalculations(
    int companyId, {
    int page = 1,
    String? search,
    String? status,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? trashed,
    String sort = 'date',
    String direction = 'desc',
  }) async {
    final pretraga = search?.trim() ?? '';

    final body = await _client.get(
      _kalkulacije(companyId),
      query: {
        'page': '$page',
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

    return StranicaKalkulacija(
      kalkulacije: (body['data'] as List)
          .map((e) => Kalkulacija.fromJson(e as Map<String, dynamic>))
          .toList(),
      stranica: meta['current_page'] as int? ?? page,
      zadnjaStranica: meta['last_page'] as int? ?? page,
      ukupno: meta['total'] as int? ?? 0,
      od: meta['from'] as int?,
      doBroja: meta['to'] as int?,
    );
  }

  // GET /companies/{company}/purchase-calculations/{id}
  Future<Kalkulacija> fetchCalculation(int companyId, int id) async {
    final body = await _client.get(_kalkulacija(companyId, id));
    return _kalkulacijaIz(body);
  }

  // POST /companies/{company}/purchase-calculations — kreira draft.
  Future<Kalkulacija> createCalculation(
    int companyId, {
    required int warehouseId,
    required int supplierId,
    required DateTime date,
    required String invoiceNumber,
    required String receiptNumber,
    double transportCost = 0,
    double forwardingCost = 0,
    double customsCost = 0,
    String? calculatedBy,
    String? receivedBy,
    required List<StavkaKalkulacijeZahtjev> items,
  }) async {
    final body = await _client.post(_kalkulacije(companyId), {
      'warehouse_id': warehouseId,
      'supplier_id': supplierId,
      'date': datumZaApi(date),
      'invoice_number': invoiceNumber,
      'receipt_number': receiptNumber,
      'transport_cost': transportCost,
      'forwarding_cost': forwardingCost,
      'customs_cost': customsCost,
      'calculated_by': _prazno(calculatedBy),
      'received_by': _prazno(receivedBy),
      'items': items.map((s) => s.toJson()).toList(),
    });
    return _kalkulacijaIz(body);
  }

  // PATCH /companies/{company}/purchase-calculations/{id} — samo draft.
  // Ako se pošalje items, zamjenjuju se sve postojeće stavke.
  Future<Kalkulacija> updateCalculation(
    int companyId,
    int id, {
    int? warehouseId,
    int? supplierId,
    DateTime? date,
    String? invoiceNumber,
    String? receiptNumber,
    double? transportCost,
    double? forwardingCost,
    double? customsCost,
    String? calculatedBy,
    String? receivedBy,
    List<StavkaKalkulacijeZahtjev>? items,
  }) async {
    final body = await _client.patch(_kalkulacija(companyId, id), {
      'warehouse_id': ?warehouseId,
      'supplier_id': ?supplierId,
      if (date != null) 'date': datumZaApi(date),
      'invoice_number': ?invoiceNumber,
      'receipt_number': ?receiptNumber,
      'transport_cost': ?transportCost,
      'forwarding_cost': ?forwardingCost,
      'customs_cost': ?customsCost,
      if (calculatedBy != null) 'calculated_by': _prazno(calculatedBy),
      if (receivedBy != null) 'received_by': _prazno(receivedBy),
      if (items != null) 'items': items.map((s) => s.toJson()).toList(),
    });
    return _kalkulacijaIz(body);
  }

  // POST /companies/{company}/purchase-calculations/{id}/book
  // Roba ulazi na zalihu, kalkulacija se zaključava (403 ako je već
  // proknjižena).
  Future<Kalkulacija> bookCalculation(int companyId, int id) async {
    final body = await _client.post('${_kalkulacija(companyId, id)}/book');
    return _kalkulacijaIz(body);
  }

  // DELETE /companies/{company}/purchase-calculations/{id} — meko, samo draft.
  Future<void> deleteCalculation(int companyId, int id) {
    return _client.delete(_kalkulacija(companyId, id));
  }

  // POST /companies/{company}/purchase-calculations/{id}/restore
  Future<Kalkulacija> restoreCalculation(int companyId, int id) async {
    final body = await _client.post('${_kalkulacija(companyId, id)}/restore');
    return _kalkulacijaIz(body);
  }

  String _kalkulacije(int companyId) =>
      '/companies/$companyId/purchase-calculations';

  String _kalkulacija(int companyId, int id) =>
      '${_kalkulacije(companyId)}/$id';

  // Prazno polje se šalje kao null.
  String? _prazno(String? tekst) {
    final t = tekst?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  Kalkulacija _kalkulacijaIz(Map<String, dynamic> body) =>
      Kalkulacija.fromJson(body['data'] as Map<String, dynamic>);
}
