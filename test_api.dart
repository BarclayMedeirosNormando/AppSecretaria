import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  final url = 'https://script.google.com/macros/s/AKfycbxw2FWbqnNvCdnMORY4BMg44mfplFi8YQ838GNhKFQUBMfsI3HMyISq742LxKoWqqp5/exec';
  final data = {'acao': 'buscar_relatorios'};
  
  stdout.writeln('Enviando...');
  try {
    final res = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data)
    );
    stdout.writeln('Status: ${res.statusCode}');
    stdout.writeln('Body: ${res.body}');
  } catch (e) {
    stdout.writeln('Erro: $e');
  }
}
