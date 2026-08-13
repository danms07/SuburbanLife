import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_html/html.dart' as html;
import 'package:path_provider/path_provider.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';

class AdminBulkUserImportScreen extends StatefulWidget {
  const AdminBulkUserImportScreen({super.key});

  @override
  State<AdminBulkUserImportScreen> createState() => _AdminBulkUserImportScreenState();
}

class _AdminBulkUserImportScreenState extends State<AdminBulkUserImportScreen> {
  String? _fileName;
  List<Map<String, String>> _parsedUsers = [];
  bool _isProcessing = false;
  Map<String, dynamic>? _importResult;
  bool _isSmtpConfigured = false;

  @override
  void initState() {
    super.initState();
    _checkSmtpStatus();
  }

  void _checkSmtpStatus() async {
    try {
      final doc = await DatabaseService().getDocument('config', 'smtp_settings');
      if (doc != null && doc['enabled'] == true && (doc['host'] ?? '').toString().isNotEmpty) {
        if (mounted) {
          setState(() {
            _isSmtpConfigured = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking SMTP status: $e');
    }
  }

  void _pickCsvFile() async {
    try {
      String? selectedFileName;
      Uint8List? rawBytes;

      if (kIsWeb) {
        debugPrint('[BulkUserImport] Web platform: launching html.FileUploadInputElement...');
        final uploadInput = html.FileUploadInputElement()
          ..accept = '.csv,text/csv,text/plain,.txt';
        uploadInput.click();

        await uploadInput.onChange.first;
        if (uploadInput.files == null || uploadInput.files!.isEmpty) {
          debugPrint('[BulkUserImport] Web picker: user cancelled.');
          return;
        }

        final file = uploadInput.files!.first;
        selectedFileName = file.name;
        final reader = html.FileReader();
        reader.readAsArrayBuffer(file);
        await reader.onLoadEnd.first;

        final result = reader.result;
        if (result != null) {
          if (result is Uint8List) {
            rawBytes = result;
          } else if (result is ByteBuffer) {
            rawBytes = result.asUint8List();
          } else if (result is List<int>) {
            rawBytes = Uint8List.fromList(result);
          }
        }
        debugPrint('[BulkUserImport] Web file read: name="$selectedFileName", bytes=${rawBytes?.length}');
      } else {
        debugPrint('[BulkUserImport] Native platform: launching FilePicker...');
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['csv', 'txt'],
          withData: true,
        );

        if (result == null || result.files.isEmpty) return;

        final file = result.files.first;
        selectedFileName = file.name;
        rawBytes = file.bytes;
      }

      if (rawBytes == null || rawBytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.invalidCsvFormat),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      final csvContent = utf8.decode(rawBytes, allowMalformed: true);
      final parsedRows = _parseCsv(csvContent);

      if (parsedRows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.invalidCsvFormat),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      setState(() {
        _fileName = selectedFileName;
        _parsedUsers = parsedRows;
        _importResult = null;
      });
    } catch (e) {
      debugPrint('Error picking or parsing CSV file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reading file: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  List<Map<String, String>> _parseCsv(String csvContent) {
    final List<Map<String, String>> result = [];
    final lines = const LineSplitter().convert(csvContent);
    if (lines.isEmpty) return result;

    int nameCol = -1;
    int emailCol = -1;
    int passwordCol = -1;
    int streetCol = -1;
    int numberCol = -1;

    final firstRowCells = _splitCsvLine(lines[0]);
    final lowerHeaders = firstRowCells.map((c) => c.toLowerCase().trim()).toList();

    for (int i = 0; i < lowerHeaders.length; i++) {
      final h = lowerHeaders[i];
      if (h == 'name' || h == 'nombre' || h == 'full_name' || h == 'fullname' || h == 'display_name') {
        nameCol = i;
      } else if (h == 'email' || h == 'correo' || h == 'email_address') {
        emailCol = i;
      } else if (h == 'password' || h == 'contraseña' || h == 'contrasena' || h == 'pass') {
        passwordCol = i;
      } else if (h == 'street' || h == 'street_name' || h == 'calle' || h == 'streetname') {
        streetCol = i;
      } else if (h == 'number' || h == 'house_number' || h == 'numero' || h == 'número' || h == 'housenumber') {
        numberCol = i;
      }
    }

    int startIndex = 1;
    // Fallback positional indexing if header row is missing or not detected
    if (nameCol == -1 && emailCol == -1) {
      startIndex = 0;
      nameCol = 0;
      emailCol = 1;
      passwordCol = 2;
      streetCol = 3;
      numberCol = 4;
    }

    for (int i = startIndex; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final cells = _splitCsvLine(line);
      String name = nameCol >= 0 && nameCol < cells.length ? cells[nameCol] : '';
      String email = emailCol >= 0 && emailCol < cells.length ? cells[emailCol] : '';
      String password = passwordCol >= 0 && passwordCol < cells.length ? cells[passwordCol] : '';
      String street = streetCol >= 0 && streetCol < cells.length ? cells[streetCol] : '';
      String number = numberCol >= 0 && numberCol < cells.length ? cells[numberCol] : '';

      if (name.isNotEmpty && email.contains('@')) {
        result.add({
          'name': name,
          'email': email,
          'password': password,
          'streetName': street,
          'number': number,
        });
      }
    }

    return result;
  }

  List<String> _splitCsvLine(String line) {
    final List<String> cells = [];
    final StringBuffer buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        cells.add(_cleanCell(buffer.toString()));
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    cells.add(_cleanCell(buffer.toString()));
    return cells;
  }

  String _cleanCell(String val) {
    String trimmed = val.trim();
    if (trimmed.startsWith('"') && trimmed.endsWith('"') && trimmed.length >= 2) {
      trimmed = trimmed.substring(1, trimmed.length - 1).trim();
    }
    return trimmed;
  }

  void _copyCsvTemplate() {
    const template = 'name,email,password,street,number\nJohn Doe,john.doe@example.com,,1st Avenue,101\nJane Smith,jane.smith@example.com,SecretPass123!,Oak Street,12\n';
    Clipboard.setData(const ClipboardData(text: template));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.csvTemplateCopiedSnackbar),
        backgroundColor: AppConfig.secondaryColor,
      ),
    );
  }

  void _processImport() async {
    if (_parsedUsers.isEmpty) return;

    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isProcessing = true;
    });

    try {
      final response = await FunctionsService().callFunction('adminBulkImportResidents', {
        'users': _parsedUsers,
      });

      if (response != null && response is Map) {
        setState(() {
          _importResult = Map<String, dynamic>.from(response);
        });
      } else {
        throw Exception('Invalid response format received from server.');
      }

      final successCount = _importResult?['successCount'] ?? 0;
      final failureCount = _importResult?['failureCount'] ?? 0;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.importSummaryText(successCount as int, failureCount as int)),
            backgroundColor: failureCount == 0 ? AppConfig.secondaryColor : Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error processing bulk user import: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  String _generateResultCsvString() {
    if (_importResult == null) return '';
    final results = List<Map<String, dynamic>>.from(
      (_importResult!['results'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
    );

    final buffer = StringBuffer();
    buffer.writeln('name,email,password,street,number,status,assigned_password,email_sent,error');

    for (var r in results) {
      final name = (r['name'] ?? '').toString().replaceAll('"', '""');
      final email = (r['email'] ?? '').toString().replaceAll('"', '""');
      final inputPass = (r['password'] ?? '').toString().replaceAll('"', '""');
      final street = (r['streetName'] ?? '').toString().replaceAll('"', '""');
      final numStr = (r['number'] ?? '').toString().replaceAll('"', '""');
      final status = (r['status'] ?? '').toString().replaceAll('"', '""');
      final assignedPass = (r['assignedPassword'] ?? '').toString().replaceAll('"', '""');
      final emailSent = (r['emailSent'] == true) ? 'yes' : 'no';
      final error = (r['error'] ?? '').toString().replaceAll('"', '""');

      buffer.writeln('"$name","$email","$inputPass","$street","$numStr","$status","$assignedPass","$emailSent","$error"');
    }

    return buffer.toString();
  }

  void _downloadResultCsv() async {
    final csvString = _generateResultCsvString();
    if (csvString.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;

    try {
      if (kIsWeb) {
        final bytes = utf8.encode(csvString);
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', 'resident_import_results_${DateTime.now().millisecondsSinceEpoch}.csv')
          ..click();
        html.Url.revokeObjectUrl(url);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.csvDownloadedSuccess), backgroundColor: AppConfig.secondaryColor),
          );
        }
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final String filePath = '${directory.path}/resident_import_results_${DateTime.now().millisecondsSinceEpoch}.csv';
        final File file = File(filePath);
        await file.writeAsString(csvString);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${l10n.csvDownloadedSuccess} Saved to: $filePath'), backgroundColor: AppConfig.secondaryColor),
          );
        }
      }
    } catch (e) {
      debugPrint('Error saving result CSV: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving file: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _copyResultCsv() {
    final csvString = _generateResultCsvString();
    if (csvString.isEmpty) return;

    Clipboard.setData(ClipboardData(text: csvString));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.csvCopiedSuccess),
        backgroundColor: AppConfig.secondaryColor,
      ),
    );
  }

  void _copyAllPasswords() {
    if (_importResult == null) return;
    final results = List<Map<String, dynamic>>.from(
      (_importResult!['results'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    final buffer = StringBuffer();
    buffer.writeln('Email, Name, Assigned Password, Status, Linked Address');

    for (var r in results) {
      if (r['status'] == 'ok' || r['status'] == 'created') {
        buffer.writeln('${r['email']}, ${r['name']}, ${r['assignedPassword']}, Created, ${r['addressLinked'] ?? 'None'}');
      }
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.passwordsCopiedSnackbar),
        backgroundColor: AppConfig.secondaryColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.bulkUserImportTitle),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.file_upload, color: AppConfig.primaryColor, size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l10n.uploadCsvButton,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppConfig.primaryColor,
                              fontFamily: AppConfig.fontFamily,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.csvColumnsHint,
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _isSmtpConfigured
                            ? Colors.green.withValues(alpha: 0.1)
                            : Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _isSmtpConfigured ? Colors.green : Colors.orange,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isSmtpConfigured ? Icons.mark_email_read : Icons.mail_lock_outlined,
                            size: 16,
                            color: _isSmtpConfigured ? Colors.green.shade800 : Colors.orange.shade800,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isSmtpConfigured ? l10n.smtpBadgeActive : l10n.smtpBadgeInactive,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _isSmtpConfigured ? Colors.green.shade800 : Colors.orange.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isProcessing ? null : _pickCsvFile,
                            icon: const Icon(Icons.folder_open),
                            label: Text(l10n.uploadCsvButton),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppConfig.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: _copyCsvTemplate,
                          icon: const Icon(Icons.copy),
                          label: Text(l10n.copyCsvTemplateButton),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                          ),
                        ),
                      ],
                    ),
                    if (_fileName != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppConfig.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.insert_drive_file, color: AppConfig.primaryColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${_fileName!} (${_parsedUsers.length} records)',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            if (_parsedUsers.isNotEmpty && _importResult == null) ...[
              Text(
                'Preview Parsed Accounts (${_parsedUsers.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppConfig.primaryColor,
                ),
              ),
              const SizedBox(height: 10),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _parsedUsers.length,
                itemBuilder: (context, index) {
                  final user = _parsedUsers[index];
                  final hasPass = (user['password'] ?? '').trim().isNotEmpty;
                  final hasAddr = (user['streetName'] ?? '').trim().isNotEmpty;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppConfig.primaryColor.withValues(alpha: 0.1),
                        child: Text(
                          user['name']!.isNotEmpty ? user['name']![0].toUpperCase() : 'U',
                          style: const TextStyle(color: AppConfig.primaryColor, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(user['name']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Email: ${user['email']}'),
                          Text(
                            hasPass
                                ? 'Password: ${user['password']}'
                                : 'Password: Deterministic Temp Pass (Suburban#${user['email']!.split('@')[0]}2026)',
                            style: TextStyle(
                              fontSize: 12,
                              color: hasPass ? Colors.blue : Colors.deepOrange,
                            ),
                          ),
                          if (hasAddr)
                            Text(
                              'Address: ${user['streetName']} #${user['number']}',
                              style: const TextStyle(fontSize: 12, color: Colors.green),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _isProcessing ? null : _processImport,
                icon: _isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add),
                label: Text(
                  _isProcessing
                      ? 'Creating accounts...'
                      : l10n.processImportButton(_parsedUsers.length),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConfig.secondaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],

            if (_importResult != null) ...[
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.importSuccessTitle,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppConfig.primaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.importSummaryText(
                          _importResult!['successCount'] as int? ?? 0,
                          _importResult!['failureCount'] as int? ?? 0,
                        ),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _downloadResultCsv,
                            icon: const Icon(Icons.download),
                            label: Text(l10n.downloadResultCsvButton),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppConfig.secondaryColor,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _copyResultCsv,
                            icon: const Icon(Icons.copy),
                            label: Text(l10n.copyResultCsvButton),
                          ),
                          OutlinedButton.icon(
                            onPressed: _copyAllPasswords,
                            icon: const Icon(Icons.content_copy),
                            label: Text(l10n.copyPasswordsButton),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: (_importResult!['results'] as List? ?? []).length,
                        itemBuilder: (context, index) {
                          final item = Map<String, dynamic>.from(_importResult!['results'][index] as Map);
                          final isSuccess = item['status'] == 'ok' || item['status'] == 'created';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: isSuccess ? Colors.green.withValues(alpha: 0.05) : Colors.red.withValues(alpha: 0.05),
                            child: ListTile(
                              leading: Icon(
                                isSuccess ? Icons.check_circle : Icons.error,
                                color: isSuccess ? Colors.green : Colors.red,
                              ),
                              title: Text(item['name'] ?? item['email'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Email: ${item['email']}'),
                                  Text('Status: ${isSuccess ? "ok" : "error"}', style: TextStyle(fontWeight: FontWeight.bold, color: isSuccess ? Colors.green : Colors.red)),
                                  if (isSuccess) ...[
                                    Text('Assigned Password: ${item['assignedPassword']}'),
                                    if (item['addressLinked'] != null)
                                      Text('Linked Address: ${item['addressLinked']}', style: const TextStyle(color: Colors.green)),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          item['emailSent'] == true ? Icons.mark_email_read : Icons.mail_outline,
                                          size: 14,
                                          color: item['emailSent'] == true ? Colors.blue.shade700 : Colors.grey.shade700,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          item['emailSent'] == true
                                              ? l10n.emailSentStatus
                                              : ((item['emailError'] != null && item['emailError'].toString().isNotEmpty)
                                                  ? '${l10n.emailFailedStatus}: ${item['emailError']}'
                                                  : l10n.emailSkippedStatus),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: item['emailSent'] == true ? Colors.blue.shade700 : Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ] else
                                    Text('Error: ${item['error']}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _parsedUsers = [];
                              _fileName = null;
                              _importResult = null;
                            });
                          },
                          icon: const Icon(Icons.refresh),
                          label: Text(l10n.importAnotherFileButton),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
