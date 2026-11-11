import 'package:get/get.dart';

import '../models/auth_models.dart';
import '../models/fiscal_year.dart';
import '../services/fiscal_years_service.dart';
import 'firma_controller.dart';

// Poslovne godine izabrane firme. Učitavaju se pri promjeni firme, da ekrani
// dokumenata znaju koje su godine zaključene (i sakriju izmjenu, knjiženje,
// brisanje, a u date pickeru ne nude datume iz tih godina).
class PoslovneGodineController extends GetxController {
  final FiscalYearsService _service = FiscalYearsService();
  final FirmaController _firmaController = Get.find<FirmaController>();
  late final Worker _firmaWorker;

  final RxList<PoslovnaGodina> godine = <PoslovnaGodina>[].obs;
  final RxBool isLoading = false.obs;
  final RxnString errorMessage = RxnString();

  int _zahtjev = 0;

  // Bezbjedno i kad kontroler nije registrovan (npr. u testovima).
  static PoslovneGodineController? get instanca =>
      Get.isRegistered<PoslovneGodineController>()
      ? Get.find<PoslovneGodineController>()
      : null;

  // Da li datum pada u zaključenu godinu izabrane firme.
  static bool zakljucenDatum(DateTime? datum) =>
      datum != null && (instanca?.jeZakljucena(datum.year) ?? false);

  @override
  void onInit() {
    super.onInit();
    _firmaWorker = ever(_firmaController.izabranaFirma, (_) => ucitaj());
    ucitaj();
  }

  @override
  void onClose() {
    _firmaWorker.dispose();
    super.onClose();
  }

  bool jeZakljucena(int godina) =>
      godine.any((g) => g.godina == godina && g.zakljucena);

  Future<void> ucitaj() async {
    final firma = _firmaController.izabranaFirma.value;
    final zahtjev = ++_zahtjev;

    if (firma == null) {
      godine.clear();
      errorMessage.value = null;
      return;
    }

    isLoading.value = true;
    errorMessage.value = null;
    try {
      final rezultat = await _service.fetchFiscalYears(firma.id);
      if (zahtjev != _zahtjev) return;
      godine.assignAll(rezultat);
    } on ApiException catch (e) {
      if (zahtjev != _zahtjev) return;
      errorMessage.value = e.message;
    } finally {
      if (zahtjev == _zahtjev) isLoading.value = false;
    }
  }

  // Zaključuje godinu i zamjenjuje je u listi.
  // ApiException (422 sa razlogom) ide dalje, da ekran prikaže poruku.
  Future<PoslovnaGodina> zakljuci(int godina) =>
      _akcija(godina, _service.closeFiscalYear);

  Future<PoslovnaGodina> _akcija(
    int godina,
    Future<PoslovnaGodina> Function(int companyId, int year) poziv,
  ) async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) throw ApiException('Nije izabrana firma.');

    final nova = await poziv(firma.id, godina);
    final i = godine.indexWhere((g) => g.godina == nova.godina);
    if (i >= 0) {
      godine[i] = nova;
    } else {
      ucitaj();
    }
    return nova;
  }
}
