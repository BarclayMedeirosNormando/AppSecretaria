import 'dart:typed_data';

import 'package:app_secretaria/models/report_model.dart';
import 'package:app_secretaria/utils/pdf_generator.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PdfGenerator', () {
    test('generates PDFs for required report scenarios', () async {
      final signatureBytes = Uint8List.sublistView(
        await rootBundle.load('assets/images/brasao_pb.png'),
      );

      final scenarios = [
        _report(id: 'normal', isTechnicalAnalysis: false),
        _report(id: 'analise-tecnica'),
        _report(
          id: 'materiais-ti',
          tiMaterials: const [
            TiMaterialItem(
              ambiente: 'Laboratório de Informática',
              equipamento: 'Switch',
              marcaModelo: '24 portas gigabit',
              quantidade: '2',
              observacao: 'Para adequação da rede cabeada',
            ),
          ],
        ),
        _report(
          id: 'com-fotos',
          photos: [
            PhotoItem(
              path: 'assets/images/brasao_pb.png',
              comment: 'Rack principal',
            ),
          ],
          signatureBytes: signatureBytes,
        ),
        _report(
          id: 'com-multiplas-assinaturas',
          signatureBytesList: [signatureBytes, signatureBytes],
          technicians: const ['Técnico A', 'Técnico B'],
        ),
        _report(id: 'sem-fotos', photos: const []),
      ];

      for (final report in scenarios) {
        final bytes = await PdfGenerator.buildPdfBytesForTesting(report);

        expect(bytes, isNotEmpty, reason: report.id);
        expect(bytes.length, greaterThan(1000), reason: report.id);
      }
    });
  });
}

ReportModel _report({
  required String id,
  bool isTechnicalAnalysis = true,
  List<TiMaterialItem> tiMaterials = const [],
  List<PhotoItem> photos = const [],
  Uint8List? signatureBytes,
  List<Uint8List>? signatureBytesList,
  List<String> technicians = const ['José de Sena Brito Junior'],
}) {
  return ReportModel(
    id: id,
    reportNumber: 'RVT-2026-002',
    isTechnicalAnalysis: isTechnicalAnalysis,
    creator: 'Teste',
    schoolName: 'Escola Estadual de Teste',
    schoolCity: 'João Pessoa',
    schoolInep: '25000000',
    visitDate: DateTime(2026, 4, 18),
    subjects: const ['Análise técnica', 'Rede Wi-Fi'],
    observations: 'Observações técnicas preservadas no relatório.',
    tiMaterials: tiMaterials,
    gre: '01ª GRE',
    photos: photos,
    technicians: technicians,
    responsiblePerson: 'Maria da Silva',
    signatureBytes: signatureBytes,
    signatureBytesList: signatureBytesList,
  );
}
