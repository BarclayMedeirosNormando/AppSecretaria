import 'package:flutter_test/flutter_test.dart';
import 'package:app_secretaria/models/report_model.dart';

void main() {
  group('ReportModel Parser Tests', () {
    test('Should parse list subjects and technicians correctly', () {
      final jsonMap = {
        'id': 'test-1',
        'reportNumber': 'REL-123',
        'creator': 'Admin',
        'schoolName': 'Escola Teste',
        'visitDate': '2026-05-26T14:00:00Z',
        'subjects': ['Motivo A', 'Motivo B'],
        'technicians': ['Técnico 1', 'Técnico 2'],
      };

      final report = ReportModel.fromJson(jsonMap);

      expect(report.id, 'test-1');
      expect(report.subjects, ['Motivo A', 'Motivo B']);
      expect(report.technicians, ['Técnico 1', 'Técnico 2']);
    });

    test('Should parse string subjects and technicians separated by comma, semicolon or newline', () {
      final jsonMap = {
        'id': 'test-2',
        'reportNumber': 'REL-124',
        'creator': 'Admin',
        'schoolName': 'Escola Teste',
        'visitDate': '2026-05-26T14:00:00Z',
        'motivos': 'Motivo A; Motivo B\nMotivo C',
        'tecnicos': 'Técnico 1, Técnico 2',
      };

      final report = ReportModel.fromJson(jsonMap);

      expect(report.subjects, ['Motivo A', 'Motivo B', 'Motivo C']);
      expect(report.technicians, ['Técnico 1', 'Técnico 2']);
    });

    test('Should parse photos from list of strings or list of maps', () {
      final jsonMap = {
        'id': 'test-3',
        'reportNumber': 'REL-125',
        'creator': 'Admin',
        'schoolName': 'Escola Teste',
        'visitDate': '2026-05-26T14:00:00Z',
        'photos': [
          {'url': 'https://example.com/img1.jpg', 'comment': 'Legenda 1'},
          'https://example.com/img2.jpg',
        ],
      };

      final report = ReportModel.fromJson(jsonMap);

      expect(report.photos.length, 2);
      expect(report.photos[0].path, 'https://example.com/img1.jpg');
      expect(report.photos[0].comment, 'Legenda 1');
      expect(report.photos[1].path, 'https://example.com/img2.jpg');
      expect(report.photos[1].comment, isNull);
    });

    test('Should parse photos from stringified JSON array', () {
      final jsonMap = {
        'id': 'test-4',
        'reportNumber': 'REL-126',
        'creator': 'Admin',
        'schoolName': 'Escola Teste',
        'visitDate': '2026-05-26T14:00:00Z',
        'fotosJson': '[{"url":"https://example.com/img3.jpg","comment":"Legenda 3"}]',
      };

      final report = ReportModel.fromJson(jsonMap);

      expect(report.photos.length, 1);
      expect(report.photos[0].path, 'https://example.com/img3.jpg');
      expect(report.photos[0].comment, 'Legenda 3');
    });

    test('Should parse photos from single url or comma-separated urls and filter out folder urls', () {
      final jsonMap = {
        'id': 'test-5',
        'reportNumber': 'REL-127',
        'creator': 'Admin',
        'schoolName': 'Escola Teste',
        'visitDate': '2026-05-26T14:00:00Z',
        'urlFotos': 'https://example.com/img4.jpg, https://example.com/img5.jpg; https://drive.google.com/drive/folders/some-folder-id',
      };

      final report = ReportModel.fromJson(jsonMap);

      // Folder link is filtered out, leaving only the image links
      expect(report.photos.length, 2);
      expect(report.photos[0].path, 'https://example.com/img4.jpg');
      expect(report.photos[1].path, 'https://example.com/img5.jpg');
    });

    test('Should resolve Google Drive view links to direct download urls', () {
      final jsonMap = {
        'id': 'test-6',
        'reportNumber': 'REL-128',
        'creator': 'Admin',
        'schoolName': 'Escola Teste',
        'visitDate': '2026-05-26T14:00:00Z',
        'urlFotos': 'https://drive.google.com/file/d/1A2B3C4D5E/view?usp=sharing',
      };

      final report = ReportModel.fromJson(jsonMap);

      expect(report.photos.length, 1);
      expect(report.photos[0].path, 'https://drive.google.com/uc?export=download&id=1A2B3C4D5E');
    });
  });
}
