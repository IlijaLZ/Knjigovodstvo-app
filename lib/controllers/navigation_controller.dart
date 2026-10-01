import 'package:get/get.dart';

class NavigationController extends GetxController {
  final RxInt selectedIndex = 0.obs;

  void openOFirmi() {
    selectedIndex.value = 1;
  }

  void openObjekti() {
    selectedIndex.value = 2;
  }

  void openArtikli() {
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

  void openStanjeMagacina() {
    selectedIndex.value = 12;
  }
}
