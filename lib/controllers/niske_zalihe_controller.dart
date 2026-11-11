import 'dart:async';

import 'package:get/get.dart';

import '../models/stock.dart';
import '../services/stocks_service.dart';
import 'firma_controller.dart';

// Repromaterijal ispod minimalne količine za izabranu firmu
// (GET …/articles/low-stock). Dijele ga meni (crveni kružić kod "Stanja")
// i početna (lista upozorenja). Osvježava se pri promjeni firme, periodično
// i kad ekran javi da se stanje moglo promijeniti (osvjezi()).
class NiskeZaliheController extends GetxController {
  final StocksService _service = StocksService();

  final RxList<NiskaZaliha> stavke = <NiskaZaliha>[].obs;

  static const _interval = Duration(minutes: 5);

  late final Worker _firmaWorker;
  Timer? _timer;

  // Broj zadnjeg zahtjeva; stariji odgovori se ignorišu.
  int _zahtjev = 0;

  int get broj => stavke.length;

  FirmaController get _firme => Get.find<FirmaController>();

  @override
  void onInit() {
    super.onInit();
    _firmaWorker = ever(_firme.izabranaFirma, (_) => osvjezi());
    _timer = Timer.periodic(_interval, (_) => osvjezi());
    osvjezi();
  }

  @override
  void onClose() {
    _firmaWorker.dispose();
    _timer?.cancel();
    super.onClose();
  }

  // Upozorenje nije kritično: ako zahtjev ne uspije, ostaje zadnje stanje.
  Future<void> osvjezi() async {
    final firma = _firme.izabranaFirma.value;
    final zahtjev = ++_zahtjev;

    if (firma == null) {
      stavke.clear();
      return;
    }

    try {
      final rezultat = await _service.fetchIspodMinimuma(firma.id);
      if (zahtjev == _zahtjev) stavke.assignAll(rezultat);
    } catch (_) {
      // Upozorenje nije kritično; ostaje zadnje poznato stanje.
    }
  }
}
