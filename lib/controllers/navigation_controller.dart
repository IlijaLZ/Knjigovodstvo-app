import 'package:get/get.dart';

class NavigationController extends GetxController {
  final RxInt selectedIndex = 0.obs;

  void openPocetna() {
    selectedIndex.value = 0;
  }

  void openOFirmi() {
    selectedIndex.value = 1;
  }

  void openObjekti() {
    selectedIndex.value = 2;
  }

  void openArtikliRepromaterijala() {
    selectedIndex.value = 3;
  }

  void openKalkulacijaNabavnihCijena() {
    selectedIndex.value = 4;
  }

  void openRadniNalog() {
    selectedIndex.value = 5;
  }

  void openTrebovanje() {
    selectedIndex.value = 6;
  }

  void openKalkulacijaCijeneKostanja() {
    selectedIndex.value = 7;
  }

  void openOtpremnica() {
    selectedIndex.value = 8;
  }

  void openKnjizenjeNaloga() {
    selectedIndex.value = 9;
  }

  void openGlavnaKnjiga() {
    selectedIndex.value = 10;
  }

  void openKarticaGlavneKnjige() {
    selectedIndex.value = 11;
  }

  // Stanje magacina repromaterijala.
  void openStanjeMagacina() {
    selectedIndex.value = 12;
  }

  void openMagacinRepromaterijala() {
    selectedIndex.value = 13;
  }

  void openProizvodnjaUToku() {
    selectedIndex.value = 14;
  }

  void openMagacinGotovihProizvoda() {
    selectedIndex.value = 15;
  }

  void openArtikliGotovihProizvoda() {
    selectedIndex.value = 16;
  }

  void openDobavljaci() {
    selectedIndex.value = 17;
  }

  void openKupci() {
    selectedIndex.value = 18;
  }

  void openFirme() {
    selectedIndex.value = 19;
  }

  void openStanjeProizvodnje() {
    selectedIndex.value = 20;
  }

  void openStanjeGotovihProizvoda() {
    selectedIndex.value = 21;
  }

  void openPoslovneGodine() {
    selectedIndex.value = 22;
  }
}
