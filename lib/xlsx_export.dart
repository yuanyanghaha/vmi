import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'models.dart';

/// Minimal XLSX writer: one sheet, inline strings, no external native code.
class InventoryXlsx {
  static Uint8List build(List<InventoryRecord> records,
      [List<String> supplierCodes = const []]) {
    final headers = <String>[
      '录入时间',
      '系统库存',
      '实际库存',
      '物料代码',
      '包装数量',
      '物料描述',
      'XS批次号',
      '供应商编码',
    ];
    final rows = <List<dynamic>>[headers];
    for (var i = 0; i < records.length; i++) {
      final record = records[i];
      rows.add(<dynamic>[
        _formatTime(record.createdAt),
        record.systemStock,
        record.actualStock,
        record.materialCode,
        record.perBox,
        record.description,
        record.batch,
        i < supplierCodes.length ? supplierCodes[i] : '',
      ]);
    }
    final sheetRows = StringBuffer();
    for (var r = 0; r < rows.length; r++) {
      sheetRows.write('<row r="${r + 1}">');
      for (var c = 0; c < rows[r].length; c++) {
        final ref = '${String.fromCharCode(65 + c)}${r + 1}';
        final value = rows[r][c];
        if (value is int || value is double) {
          sheetRows.write('<c r="$ref"><v>$value</v></c>');
        } else {
          sheetRows.write('<c r="$ref" t="inlineStr"><is><t xml:space="preserve">'
              '${_escape('$value')}</t></is></c>');
        }
      }
      sheetRows.write('</row>');
    }

    final files = <String, String>{
      '[Content_Types].xml': '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>''',
      '_rels/.rels': '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''',
      'xl/workbook.xml': '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets><sheet name="库存统计" sheetId="1" r:id="rId1"/></sheets>
</workbook>''',
      'xl/_rels/workbook.xml.rels': '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''',
      'xl/styles.xml': '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>
<fills count="1"><fill><patternFill patternType="none"/></fill></fills>
<borders count="1"><border/></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>''',
      'xl/worksheets/sheet1.xml': '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<cols><col min="1" max="8" width="20" customWidth="1"/></cols>
<sheetData>$sheetRows</sheetData>
</worksheet>''',
    };

    final archive = Archive();
    files.forEach((name, content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile.bytes(name, bytes));
    });
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _formatTime(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
  }
}
