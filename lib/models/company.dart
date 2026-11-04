// Firma prijavljenog korisnika (/companies). Pri kreiranju firme server
// automatski pravi njena tri skladišta.
class Company {
  final int id;
  final String name;
  final String? address;
  final String? taxId;
  final String? vatNumber;
  final bool isVatRegistered;
  final String? authorizedPerson;
  final int articlesCount;
  final DateTime? deletedAt;

  Company({
    required this.id,
    required this.name,
    this.address,
    this.taxId,
    this.vatNumber,
    this.isVatRegistered = false,
    this.authorizedPerson,
    this.articlesCount = 0,
    this.deletedAt,
  });

  bool get jeObrisana => deletedAt != null;

  factory Company.fromJson(Map<String, dynamic> json) {
    final deletedAt = json['deleted_at'] as String?;

    return Company(
      id: json['id'] as int,
      name: json['name'] as String,
      address: json['address'] as String?,
      taxId: json['tax_id'] as String?,
      vatNumber: json['vat_number'] as String?,
      isVatRegistered: json['is_vat_registered'] as bool? ?? false,
      authorizedPerson: json['authorized_person'] as String?,
      articlesCount: json['articles_count'] as int? ?? 0,
      deletedAt: deletedAt == null ? null : DateTime.tryParse(deletedAt),
    );
  }

  // Polja za POST/PATCH; prazan PDV broj se šalje kao null.
  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'tax_id': taxId,
    'vat_number': vatNumber,
    'authorized_person': authorizedPerson,
  };

  @override
  bool operator ==(Object other) => other is Company && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
