import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';
import 'package:printing/printing.dart';

enum ReportPdfGenerationStatus { queued, processing, succeeded, failed }

class ReportPdfJob {
  const ReportPdfJob({
    required this.reportId,
    required this.status,
    this.templateVersion,
    this.attemptCount = 0,
    this.fileId,
    this.fileName,
    this.fileSizeBytes,
    this.fileHash,
    this.generatedAt,
    this.failureReason,
  });

  final String reportId;
  final ReportPdfGenerationStatus status;
  final String? templateVersion;
  final int attemptCount;
  final String? fileId;
  final String? fileName;
  final int? fileSizeBytes;
  final String? fileHash;
  final DateTime? generatedAt;
  final String? failureReason;

  factory ReportPdfJob.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['generation_status']?.toString();
    final status = switch (rawStatus) {
      // `pending` was used by the first contract draft. Keep accepting it while
      // the API and app roll out independently, but expose one queued state.
      'pending' || 'queued' => ReportPdfGenerationStatus.queued,
      'processing' => ReportPdfGenerationStatus.processing,
      'succeeded' => ReportPdfGenerationStatus.succeeded,
      'failed' => ReportPdfGenerationStatus.failed,
      _ => throw const ReportPdfFailure('服务器返回了未知的 PDF 任务状态'),
    };
    return ReportPdfJob(
      reportId: json['report_id'] as String,
      status: status,
      templateVersion: json['template_version'] as String?,
      attemptCount: json['attempt_count'] as int? ?? 0,
      fileId: json['file_id'] as String?,
      fileName: json['file_name'] as String?,
      fileSizeBytes: json['file_size_bytes'] as int?,
      fileHash: json['file_hash'] as String?,
      generatedAt: json['generated_at'] == null
          ? null
          : DateTime.parse(json['generated_at'] as String),
      failureReason: json['failure_reason'] as String?,
    );
  }
}

abstract interface class ReportPdfRepository {
  Future<ReportPdfJob> create(String reportId);
  Future<ReportPdfJob> getStatus(String reportId);
  Future<Uint8List> download(String reportId);
}

class FastApiReportPdfRepository implements ReportPdfRepository {
  FastApiReportPdfRepository(this.client);

  final PomiApiClient client;

  @override
  Future<ReportPdfJob> create(String reportId) async {
    try {
      final response = await client.dio.post<Map<String, dynamic>>(
        '/reports/$reportId/pdf',
        options: Options(
          headers: {'Idempotency-Key': 'report-pdf-$reportId-template-v1'},
        ),
      );
      return _job(response.data);
    } on DioException catch (error) {
      throw _failure(error, '无法创建 PDF 任务，请稍后重试');
    }
  }

  @override
  Future<ReportPdfJob> getStatus(String reportId) async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        '/reports/$reportId/pdf',
      );
      return _job(response.data);
    } on DioException catch (error) {
      throw _failure(error, '无法查询 PDF 任务状态，请稍后重试');
    }
  }

  @override
  Future<Uint8List> download(String reportId) async {
    try {
      final response = await client.dio.get<List<int>>(
        '/reports/$reportId/pdf/file',
        options: Options(
          responseType: ResponseType.bytes,
          headers: const {'Accept': 'application/pdf'},
        ),
      );
      final bytes = Uint8List.fromList(response.data ?? const []);
      if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
        throw const ReportPdfFailure('下载内容不是有效的 PDF 文件，请重试');
      }
      return bytes;
    } on ReportPdfFailure {
      rethrow;
    } on DioException catch (error) {
      throw _failure(error, 'PDF 下载失败，请检查网络后重试');
    }
  }

  ReportPdfJob _job(Map<String, dynamic>? envelope) {
    final data = envelope?['data'];
    if (data is! Map) {
      throw const ReportPdfFailure('服务器没有返回 PDF 任务数据');
    }
    return ReportPdfJob.fromJson(Map<String, dynamic>.from(data));
  }

  ReportPdfFailure _failure(DioException error, String fallback) {
    final body = error.response?.data;
    if (body is Map && body['error'] is Map) {
      final message = (body['error'] as Map)['message']?.toString();
      if (message != null && message.isNotEmpty) {
        return ReportPdfFailure(message);
      }
    }
    return ReportPdfFailure(fallback);
  }
}

class DemoReportPdfRepository implements ReportPdfRepository {
  ReportPdfJob _job(String reportId) => ReportPdfJob(
    reportId: reportId,
    status: ReportPdfGenerationStatus.succeeded,
    fileId: 'demo-pdf-$reportId',
    fileName: 'pomi-report-$reportId.pdf',
    fileSizeBytes: _demoPdf.length,
    fileHash: 'demo-file-hash',
    generatedAt: DateTime.now(),
  );

  @override
  Future<ReportPdfJob> create(String reportId) async => _job(reportId);

  @override
  Future<Uint8List> download(String reportId) async =>
      Uint8List.fromList(_demoPdf);

  @override
  Future<ReportPdfJob> getStatus(String reportId) async => _job(reportId);

  // Static fixture bytes represent a server response in demo mode. Production
  // never renders or rebuilds report PDFs on the device.
  static final List<int> _demoPdf =
      '%PDF-1.4\n% POMI demo server fixture\n%%EOF\n'.codeUnits;
}

typedef CacheDirectoryProvider = Future<Directory> Function();

class ReportPdfCache {
  ReportPdfCache({
    CacheDirectoryProvider? directoryProvider,
    this.maxAge = const Duration(hours: 24),
    this.maxFiles = 4,
  }) : _directoryProvider = directoryProvider ?? getTemporaryDirectory;

  final CacheDirectoryProvider _directoryProvider;
  final Duration maxAge;
  final int maxFiles;

  Future<File> store({
    required String reportId,
    required Uint8List bytes,
    String? suggestedName,
  }) async {
    final directory = await _cacheDirectory();
    await cleanup(directory: directory);
    final safeName = _safeName(
      suggestedName ?? 'pomi-report-${_compactId(reportId)}.pdf',
    );
    final target = File('${directory.path}${Platform.pathSeparator}$safeName');
    final temporary = File('${target.path}.part');
    await temporary.writeAsBytes(bytes, flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
    await target.setLastModified(DateTime.now());
    await cleanup(directory: directory);
    return target;
  }

  Future<void> cleanup({Directory? directory}) async {
    final cache = directory ?? await _cacheDirectory();
    if (!await cache.exists()) return;
    final now = DateTime.now();
    final files = <File>[];
    await for (final entity in cache.list(followLinks: false)) {
      if (entity is! File) continue;
      if (entity.path.endsWith('.part')) {
        await entity.delete();
        continue;
      }
      final modified = await entity.lastModified();
      if (now.difference(modified) > maxAge) {
        await entity.delete();
      } else {
        files.add(entity);
      }
    }
    files.sort((a, b) {
      final aTime = a.lastModifiedSync();
      final bTime = b.lastModifiedSync();
      return bTime.compareTo(aTime);
    });
    for (final file in files.skip(maxFiles)) {
      if (await file.exists()) await file.delete();
    }
  }

  Future<Directory> _cacheDirectory() async {
    final root = await _directoryProvider();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}pomi-report-pdf-cache',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  String _safeName(String value) {
    var name = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    while (name.contains('..')) {
      name = name.replaceAll('..', '_');
    }
    name = name.replaceFirst(RegExp(r'^\.+'), '');
    if (!name.toLowerCase().endsWith('.pdf')) name = '$name.pdf';
    return name.isEmpty ? 'pomi-report.pdf' : name;
  }

  String _compactId(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '');
}

abstract interface class ReportPdfSystemActions {
  Future<void> save(File file, String fileName);
  Future<void> share(File file, String fileName);
  Future<void> print(File file, String fileName);
}

class AndroidReportPdfSystemActions implements ReportPdfSystemActions {
  const AndroidReportPdfSystemActions();

  @override
  Future<void> save(File file, String fileName) async {
    final selected = await FilePicker.platform.saveFile(
      dialogTitle: '保存 POMI 报告',
      fileName: fileName,
      bytes: await file.readAsBytes(),
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (selected == null) {
      throw const ReportPdfFailure('已取消保存，App 内报告不受影响');
    }
  }

  @override
  Future<void> share(File file, String fileName) async {
    final opened = await Printing.sharePdf(
      bytes: await file.readAsBytes(),
      filename: fileName,
      subject: 'POMI 复诊准备报告',
    );
    if (!opened) {
      throw const ReportPdfFailure('未能打开系统分享面板，请重试');
    }
  }

  @override
  Future<void> print(File file, String fileName) async {
    final opened = await Printing.layoutPdf(
      name: fileName,
      onLayout: (_) => file.readAsBytes(),
    );
    if (!opened) {
      throw const ReportPdfFailure('未能打开系统打印服务，请重试');
    }
  }
}

class ReportPdfFailure implements Exception {
  const ReportPdfFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
