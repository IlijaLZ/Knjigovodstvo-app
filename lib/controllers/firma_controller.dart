import 'package:get/get.dart';

import '../models/auth_models.dart';
import '../models/company.dart';
import '../services/articles_service.dart';

// Firme prijavljenog korisnika i trenutno izabrana firma.
// Ekrani koji zavise od firme slušaju izabranaFirma i učitavaju svoje podatke.
class FirmaController extends GetxController {
  final ArticlesService _service = ArticlesService();

  final RxList<Company> firme = <Company>[].obs;
  final Rxn<Company> izabranaFirma = Rxn<Company>();

  final RxBool isLoading = false.obs;
  final RxnString errorMessage = RxnString();

  @override
  void onInit() {
    super.onInit();
    ucitajFirme();
  }

  Future<void> ucitajFirme() async {
    isLoading.value = true;
    errorMessage.value = null;

    try {
      firme.assignAll(await _service.fetchCompanies());

      // Firme su jednake po id-u, pa se izmijenjena izabrana firma
      // (npr. novi naziv) mora postaviti sa trigger da bi se prikaz osvježio.
      final stara = izabranaFirma.value;
      final nova = firme.where((f) => f == stara).firstOrNull;

      if (nova == null) {
        izabranaFirma.value = firme.firstOrNull;
      } else if (nova.name != stara!.name) {
        izabranaFirma.trigger(nova);
      }
    } on ApiException catch (e) {
      errorMessage.value = e.message;
    } finally {
      isLoading.value = false;
    }
  }

  void izaberiFirmu(Company firma) {
    izabranaFirma.value = firma;
  }
}
