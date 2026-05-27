import 'dart:convert';
import 'dart:io';

void main() async {
  final request = await HttpClient().getUrl(Uri.parse('https://servicodados.ibge.gov.br/api/v1/localidades/estados/25/municipios'));
  final response = await request.close();
  final stringData = await response.transform(utf8.decoder).join();
  final List<dynamic> jsonList = jsonDecode(stringData);
  
  final municipalities = jsonList.map((e) => e['nome'].toString()).toList();
  municipalities.sort();

  final regionals = [
    '01ª GRE (João Pessoa)',
    '02ª GRE (Guarabira)',
    '03ª GRE (Campina Grande)',
    '04ª GRE (Cuité)',
    '05ª GRE (Monteiro)',
    '06ª GRE (Patos)',
    '07ª GRE (Itaporanga)',
    '08ª GRE (Catolé do Rocha)',
    '09ª GRE (Cajazeiras)',
    '10ª GRE (Sousa)',
    '11ª GRE (Princesa Isabel)',
    '12ª GRE (Itabaiana)',
    '13ª GRE (Pombal)',
    '14ª GRE (Mamanguape)',
    '15ª GRE (Queimadas)',
    '16ª GRE (João Pessoa)'
  ];

  final file = File(r'c:\Users\barclaym\Documents\AppSecretaria\lib\utils\constants.dart');
  
  var content = '''
class Constants {
  static const List<String> paraibaMunicipalities = [
${municipalities.map((e) => "    '${e.replaceAll("'", "\\'")}',").join('\n')}
  ];

  static const List<String> regionals = [
${regionals.map((e) => "    '$e',").join('\n')}
  ];
}
''';

  await file.writeAsString(content);
  stdout.writeln('Done.');
}
