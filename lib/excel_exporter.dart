import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'database_helper.dart';

class ExcelExporter {
  static Future<String> exportGamingData() async {
    final excel = Excel.createExcel();
    final Sheet sheet = excel['PlayWell Usage Report'];

    sheet.appendRow([
      TextCellValue('Profile Name'),
      TextCellValue('Package Name'),
      TextCellValue('Date'),
      TextCellValue('Time Played (Minutes)'),
    ]);

    final logs = await DatabaseHelper.instance.getAllLogs();

    for (var log in logs) {
      sheet.appendRow([
        TextCellValue(log['profile_name'].toString()),
        TextCellValue(log['package_name'].toString()),
        TextCellValue(log['date'].toString()),
        IntCellValue((log['seconds_played'] as int) ~/ 60),
      ]);
    }

    final directory = await getApplicationDocumentsDirectory();
    final filePath =
        "${directory.path}/PlayWell_Report_${DateTime.now().millisecondsSinceEpoch}.xlsx";
    final file = File(filePath);

    await file.writeAsBytes(excel.save()!);
    return filePath;
  }
}
