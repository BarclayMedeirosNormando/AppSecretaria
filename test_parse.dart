import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  final url = 'https://script.google.com/macros/s/AKfycbxw2FWbqnNvCdnMORY4BMg44mfplFi8YQ838GNhKFQUBMfsI3HMyISq742LxKoWqqp5/exec';
  final data = {'acao': 'buscar_relatorios'};
  
  try {
    var request = http.Request('POST', Uri.parse(url));
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode(data);
    request.followRedirects = false; // We handle it manually
    
    var client = http.Client();
    var streamedResponse = await client.send(request);
    var response = await http.Response.fromStream(streamedResponse);
    
    stdout.writeln('POST Status: ${response.statusCode}');
    
    if (response.statusCode == 302 || response.statusCode == 303) {
      final location = response.headers['location'];
      stdout.writeln('Redirecting to: $location');
      if (location != null) {
        var getResponse = await http.get(Uri.parse(location));
        stdout.writeln('GET Status: ${getResponse.statusCode}');
        stdout.writeln('GET Body: ${getResponse.body}');
        
        final decoded = jsonDecode(getResponse.body);
        if (decoded['status'] == 'success') {
          stdout.writeln('Total reports: ${decoded['data'].length}');
        }
      }
    } else {
       stdout.writeln('Body: ${response.body}');
    }
  } catch(e) {
    stdout.writeln('Exception: $e');
  }
}
