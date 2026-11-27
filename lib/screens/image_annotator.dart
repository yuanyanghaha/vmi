import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImageAnnotatorScreen extends StatefulWidget {
  const ImageAnnotatorScreen({super.key, required this.path});
  final String path;

  @override
  State<ImageAnnotatorScreen> createState() => _ImageAnnotatorScreenState();
}

class _Stroke {
  final Color color;
  final double width;
  final List<Offset> points;
  _Stroke(this.color, this.width, this.points);
}

class _ImageAnnotatorScreenState extends State<ImageAnnotatorScreen> {
  static const _colors = <Color>[
    Color(0xFFE5484D),
    Color(0xFF2F6BFF),
    Color(0xFF12B76A),
    Color(0xFFF79009),
    Color(0xFFFFFFFF),
    Color(0xFF101828),
  ];

  final _boundary = GlobalKey();
  final List<_Stroke> _strokes = [];
  ui.Image? _image;
  Size _imageSize = const Size(1, 1);
  Color _color = _colors[0];
  double _width = 4;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    final bytes = await File(widget.path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() {
      _image = frame.image;
      _imageSize =
          Size(frame.image.width.toDouble(), frame.image.height.toDouble());
    });
    codec.dispose();
  }

  void _start(DragStartDetails details, Size display) {
    final point = _normalized(details.localPosition, display);
    if (point == null) return;
    setState(() {
      _strokes.add(_Stroke(_color, _width, <Offset>[point]));
    });
  }

  void _update(DragUpdateDetails details, Size display) {
    if (_strokes.isEmpty) return;
    final point = _normalized(details.localPosition, display);
    if (point == null) return;
    setState(() => _strokes.last.points.add(point));
  }

  Offset? _normalized(Offset local, Size display) {
    if (display.width <= 0 || display.height <= 0) return null;
    if (local.dx < 0 ||
        local.dy < 0 ||
        local.dx > display.width ||
        local.dy > display.height) {
      return null;
    }
    return Offset(local.dx / display.width, local.dy / display.height);
  }

  Future<void> _save() async {
    if (_busy) return;
    final boundary =
        _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    setState(() => _busy = true);
    try {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('导出图片失败');
      final root = await getApplicationDocumentsDirectory();
      final folder = Directory(p.join(root.path, 'catalog_images'));
      await folder.create(recursive: true);
      final target = p.join(folder.path,
          'annotated_${DateTime.now().microsecondsSinceEpoch}.png');
      await File(target).writeAsBytes(data.buffer.asUint8List());
      image.dispose();
      if (mounted) Navigator.pop(context, target);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存标注失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        foregroundColor: Colors.white,
        title: const Text('图片标注'),
        actions: [
          IconButton(
            tooltip: '撤销',
            onPressed: _strokes.isEmpty
                ? null
                : () => setState(() => _strokes.removeLast()),
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: '清空',
            onPressed: _strokes.isEmpty
                ? null
                : () => setState(() => _strokes.clear()),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          TextButton(
            onPressed: _busy || _image == null ? null : _save,
            child: Text(_busy ? '保存中...' : '保存',
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _image == null
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final scale = math.min(
                        constraints.maxWidth / _imageSize.width,
                        constraints.maxHeight / _imageSize.height,
                      );
                      final display = Size(
                        _imageSize.width * scale,
                        _imageSize.height * scale,
                      );
                      return Center(
                        child: GestureDetector(
                          onPanStart: (d) => _start(d, display),
                          onPanUpdate: (d) => _update(d, display),
                          child: RepaintBoundary(
                            key: _boundary,
                            child: SizedBox(
                              width: display.width,
                              height: display.height,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(File(widget.path), fit: BoxFit.fill),
                                  CustomPaint(
                                    painter: _StrokePainter(_strokes),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            color: const Color(0xFF1B2433),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text('画笔颜色',
                          style: TextStyle(fontSize: 11, color: Colors.white70)),
                      const SizedBox(width: 10),
                      for (final color in _colors)
                        GestureDetector(
                          onTap: () => setState(() => _color = color),
                          child: Container(
                            width: 26,
                            height: 26,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _color == color
                                    ? Colors.white
                                    : Colors.white24,
                                width: _color == color ? 2.5 : 1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('粗细',
                          style: TextStyle(fontSize: 11, color: Colors.white70)),
                      Expanded(
                        child: Slider(
                          value: _width,
                          min: 2,
                          max: 16,
                          divisions: 7,
                          label: _width.round().toString(),
                          onChanged: (value) => setState(() => _width = value),
                        ),
                      ),
                      Text('${_width.round()}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white70)),
                    ],
                  ),
                  const Text('在图片上拖动即可画线，保存后会生成新图片',
                      style: TextStyle(fontSize: 10, color: Colors.white38)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.strokes);
  final List<_Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path()
        ..moveTo(stroke.points.first.dx * size.width,
            stroke.points.first.dy * size.height);
      for (var i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].dx * size.width,
            stroke.points[i].dy * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) => true;
}
