import 'package:flutter/material.dart';

// Ako je width == null, input se rasteže (koristi se unutar Expanded).
// readOnly = true -> polje samo za prikaz (sivo, bez fokusa).

Widget buildInput({
  required String label,
  required TextEditingController controller,
  double? width = 320,
  bool readOnly = false,
  ValueChanged<String>? onChanged,
}) {
  final field = TextField(
    controller: controller,
    readOnly: readOnly,
    onChanged: onChanged,
    style: readOnly ? const TextStyle(fontWeight: FontWeight.w600) : null,
    decoration: InputDecoration(
      labelText: label,
      filled: true,
      fillColor: readOnly ? Colors.grey.shade200 : Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: readOnly
            ? BorderSide(color: Colors.grey.shade300)
            : const BorderSide(color: Colors.blue, width: 2),
      ),
    ),
  );

  if (width == null) return field;

  return SizedBox(width: width, child: field);
}
