import 'dart:io';
import 'package:excel/excel.dart';

void main() {
  var file = r'c:\Users\barclaym\Downloads\Nexus Educacional.xlsx';
  var bytes = File(file).readAsBytesSync();
  var excel = Excel.decodeBytes(bytes);
  
  var sheet = excel.tables['ESCOLAS'];
  if (sheet != null) {
    if (sheet.rows.isNotEmpty) {
      stdout.writeln(sheet.rows[0].map((e) => e?.value.toString()).toList());
    } else {
      stdout.writeln('Aba vazia');
    }
  } else {
    stdout.writeln('Sheet ESCOLAS not found. Available sheets: ${excel.tables.keys.toList()}');
  }
}
