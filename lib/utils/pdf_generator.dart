import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/report_model.dart';
import '../services/employee_service.dart';
import '../services/technician_service.dart';

class PdfGenerator {
  static String _s(String value) => value.trim();

  static Future<bool> generateAndPreviewPdf(
    ReportModel report, {
    bool includeImages = true,
  }) async {
    final regularFont = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final boldFont = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: regularFont,
        bold: boldFont,
      ),
    );

    debugPrint('Gerando PDF relatorio: ${report.id}');
    debugPrint('Fotos no report: ${report.photos.length}');
    debugPrint('Assinatura bytes: ${report.signatureBytes != null}');
    debugPrint('Assinatura URL: ${report.signatureUrl}');
    debugPrint('includeImages: $includeImages');

    Uint8List? brasaoBytes;
    try {
      final byteData = await rootBundle.load('assets/images/brasao_pb.png');
      brasaoBytes = byteData.buffer.asUint8List();
    } catch (e) {
      debugPrint('Nao foi possivel carregar brasao: $e');
    }

    final pdfPhotos = <MapEntry<pw.MemoryImage, String?>>[];
    if (includeImages && report.photos.isNotEmpty) {
      for (final photo in report.photos) {
        try {
          final bytes = await _loadImageBytes(photo.path);
          if (bytes != null && bytes.isNotEmpty) {
            pdfPhotos.add(MapEntry(pw.MemoryImage(bytes), photo.comment));
          }
        } catch (e) {
          debugPrint('Falha ao carregar foto para PDF (${photo.path}): $e');
        }
      }
    }

    Uint8List? signatureBytes = report.signatureBytes;
    if ((signatureBytes == null || signatureBytes.isEmpty) &&
        report.signatureUrl != null &&
        report.signatureUrl!.trim().isNotEmpty) {
      signatureBytes = await _loadImageBytes(report.signatureUrl!);
      if (signatureBytes == null || signatureBytes.isEmpty) {
        debugPrint('Nao foi possivel carregar assinatura remota: ${report.signatureUrl}');
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 32),
        build: (pw.Context context) => [
          _buildInstitutionalHeader(brasaoBytes),
          pw.SizedBox(height: 28),
          pw.Divider(thickness: 0.5, color: PdfColors.grey400),
          pw.SizedBox(height: 20),
          _buildReportTitle(report),
          pw.SizedBox(height: 16),
          _buildReportDetails(report),
          if (report.observations != null && report.observations!.trim().isNotEmpty) ...[
            pw.SizedBox(height: 20),
            ..._buildObservations(report),
          ],
          if (report.isTechnicalAnalysis && report.tiMaterials.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            ..._buildTiMaterials(report),
          ],
          pw.SizedBox(height: 48),
          _buildSignatureSection(report, signatureBytes),
        ],
      ),
    );

    if (pdfPhotos.isNotEmpty) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 32),
          build: (pw.Context context) => [
            pw.Text(
              'Anexos - Fotos da Visita',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 16),
            ...pdfPhotos.map(
              (entry) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 240,
                    child: pw.Image(entry.key, fit: pw.BoxFit.contain),
                  ),
                  if (entry.value != null && entry.value!.trim().isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    pw.Text('Comentário: ${_s(entry.value!)}', style: const pw.TextStyle(fontSize: 11)),
                  ],
                  pw.SizedBox(height: 16),
                  pw.Divider(color: PdfColors.grey300),
                  pw.SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      );
    }

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Relatorio_${_s(report.schoolName).replaceAll(' ', '_')}.pdf',
    );

    return includeImages && report.photos.isNotEmpty && pdfPhotos.isEmpty;
  }

  static Future<Uint8List?> _loadImageBytes(String source) async {
    try {
      final trimmed = source.trim();
      if (trimmed.isEmpty) return null;

      if (trimmed.startsWith('data:image') ||
          (RegExp(r'^[a-zA-Z0-9+/=]+$').hasMatch(trimmed) && trimmed.length > 100)) {
        try {
          final cleanBase64 = trimmed.contains(',') ? trimmed.split(',').last : trimmed;
          return base64Decode(cleanBase64.trim());
        } catch (e) {
          debugPrint('Imagem base64 invalida: $e');
        }
      }

      if (trimmed.startsWith('http://') || trimmed.startsWith('https://') || trimmed.contains('drive.google.com')) {
        final driveId = _extractDriveFileId(trimmed);
        final urls = <String>[
          if (driveId != null) 'https://drive.google.com/uc?export=download&id=$driveId',
          trimmed,
          if (driveId != null) 'https://drive.google.com/thumbnail?id=$driveId&sz=w1000',
        ];

        for (final url in urls.toSet()) {
          try {
            final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
            final contentType = response.headers['content-type'] ?? '';
            if (response.statusCode == 200 &&
                response.bodyBytes.isNotEmpty &&
                !contentType.toLowerCase().contains('text/html')) {
              return response.bodyBytes;
            }
          } catch (e) {
            debugPrint('Falha ao baixar imagem $url: $e');
          }
        }
        return null;
      }

      if (!kIsWeb) {
        try {
          final file = io.File(trimmed);
          if (await file.exists()) {
            return await file.readAsBytes();
          }
        } catch (e) {
          debugPrint('Falha ao ler arquivo de imagem $trimmed: $e');
        }
      }

      try {
        return await XFile(trimmed).readAsBytes();
      } catch (e) {
        debugPrint('Falha ao ler XFile $trimmed: $e');
      }
    } catch (e) {
      debugPrint('Erro ao carregar imagem ($source): $e');
    }
    return null;
  }

  static String? _extractDriveFileId(String url) {
    final fileMatch = RegExp(r'/file/d/([a-zA-Z0-9_-]+)').firstMatch(url) ??
        RegExp(r'/d/([a-zA-Z0-9_-]+)').firstMatch(url);
    if (fileMatch != null) return fileMatch.group(1);

    final idMatch = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)').firstMatch(url);
    return idMatch?.group(1);
  }

  static pw.Widget _buildInstitutionalHeader(Uint8List? brasaoBytes) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('Secretaria de Estado', style: const pw.TextStyle(fontSize: 9)),
            pw.Text('da Educação', style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
        pw.SizedBox(width: 10),
        if (brasaoBytes != null)
          pw.Container(
            width: 52,
            height: 52,
            child: pw.Image(pw.MemoryImage(brasaoBytes), fit: pw.BoxFit.contain),
          )
        else
          pw.Container(width: 52, height: 52),
        pw.SizedBox(width: 10),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('GOVERNO', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.Text('DA PARAÍBA', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildReportTitle(ReportModel report) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'RELATÓRIO DE ANÁLISE E INTERVENÇÃO TÉCNICA',
          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          _s(report.reportNumber),
          style: pw.TextStyle(fontSize: 11, fontStyle: pw.FontStyle.italic),
        ),
      ],
    );
  }

  static pw.Widget _buildReportDetails(ReportModel report) {
    final cleanTechnicians = report.technicians
        .map((t) => t.trim().replaceAll(RegExp(r'^,\s*'), ''))
        .where((t) => t.isNotEmpty)
        .toList();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _richLine('Escola: ', _s(report.schoolName)),
        if (report.gre != null && report.gre!.trim().isNotEmpty) _richLine('GRE: ', _s(report.gre!)),
        if (report.schoolCity != null && report.schoolCity!.trim().isNotEmpty)
          _richLine('Município: ', _s(report.schoolCity!)),
        if (report.schoolInep != null && report.schoolInep!.trim().isNotEmpty) _richLine('INEP: ', _s(report.schoolInep!)),
        _richLine('Data do Atendimento: ', DateFormat('dd/MM/yyyy').format(report.visitDate)),
        _richLine('Motivo do Chamado: ', _s(report.subjects.join(', '))),
        _richLine('Técnicos Presentes: ', cleanTechnicians.isEmpty ? 'Não informado' : _s(cleanTechnicians.join(', '))),
        if (!report.isTechnicalAnalysis && report.responsiblePerson != null && report.responsiblePerson!.trim().isNotEmpty)
          _richLine('Responsável: ', _s(report.responsiblePerson!)),
      ],
    );
  }

  static pw.Widget _richLine(String boldPart, String normalPart) {
    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 0.5),
      child: pw.RichText(
        textAlign: pw.TextAlign.left,
        text: pw.TextSpan(
          children: [
            pw.TextSpan(text: boldPart, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
            pw.TextSpan(text: normalPart, style: const pw.TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  static List<pw.Widget> _buildObservations(ReportModel report) {
    var obs = report.observations ?? '';
    obs = obs.replaceAllMapped(RegExp(r'\S{40,}'), (match) {
      final word = match.group(0)!;
      return word.replaceAllMapped(RegExp(r'.{40}'), (m) => '${m.group(0)} ');
    });

    return [
      pw.Text(
        'Observações / Diagnóstico Técnico:',
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
      pw.Paragraph(
        text: _s(obs),
        style: const pw.TextStyle(fontSize: 11),
        textAlign: pw.TextAlign.left,
      ),
    ];
  }

  static List<pw.Widget> _buildTiMaterials(ReportModel report) {
    final grouped = <String, List<TiMaterialItem>>{};
    for (final item in report.tiMaterials) {
      grouped.putIfAbsent(item.ambiente, () => []).add(item);
    }

    return [
      pw.Text(
        'Materiais de TI necessários',
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 8),
      ...grouped.entries.expand((entry) => [
            pw.Text(
              _s(entry.key),
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(2),
                1: pw.FlexColumnWidth(2),
                2: pw.FlexColumnWidth(1.2),
                3: pw.FlexColumnWidth(2.2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _tableCell('Equipamento/Material', bold: true),
                    _tableCell('Marca/Modelo', bold: true),
                    _tableCell('Quantidade', bold: true),
                    _tableCell('Observação', bold: true),
                  ],
                ),
                ...entry.value.map((item) => pw.TableRow(
                      children: [
                        _tableCell(item.equipamento),
                        _tableCell(item.marcaModelo),
                        _tableCell(item.quantidade),
                        _tableCell(item.observacao),
                      ],
                    )),
              ],
            ),
            pw.SizedBox(height: 10),
          ]),
    ];
  }

  static pw.Widget _tableCell(String value, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        _s(value),
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static pw.Widget _buildSignatureSection(ReportModel report, Uint8List? signatureBytes) {
    final label = _signatureLabel(report);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (signatureBytes != null && signatureBytes.isNotEmpty)
          pw.Container(
            height: 44,
            child: pw.Image(pw.MemoryImage(signatureBytes), fit: pw.BoxFit.contain),
          )
        else
          pw.SizedBox(height: 50),
        pw.Container(width: 260, height: 1, color: PdfColors.black),
        pw.SizedBox(height: 6),
        pw.Text(label, style: const pw.TextStyle(fontSize: 11)),
      ],
    );
  }

  static String _signatureLabel(ReportModel report) {
    if (report.isTechnicalAnalysis) {
      var nome = '';
      var matricula = '';
      if (report.technicians.isNotEmpty) {
        nome = report.technicians.first.trim().replaceAll(RegExp(r'^,\s*'), '');
        try {
          final tech = TechnicianService().technicians.firstWhere((t) => t.name == nome);
          matricula = tech.registration;
        } catch (_) {}
      }
      if (matricula.isNotEmpty) return '$nome - Matrícula: $matricula';
      return nome.isNotEmpty ? nome : 'Assinatura do Técnico Responsável';
    }

    final nome = report.responsiblePerson ?? '';
    var matricula = '';
    if (nome.isNotEmpty) {
      try {
        final emp = EmployeeService().all.firstWhere((e) => e.name == nome);
        matricula = emp.matricula;
      } catch (_) {}
    }
    if (matricula.isNotEmpty) return '$nome - Matrícula: $matricula';
    return nome.isNotEmpty ? nome : 'Assinatura do Responsável da Escola';
  }
}
