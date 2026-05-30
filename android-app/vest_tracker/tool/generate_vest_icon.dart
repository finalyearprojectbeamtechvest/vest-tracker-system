import 'dart:io';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  final outPath = args.isNotEmpty ? args.first : 'assets/icons/vest_tracker_icon.png';
  final outFile = File(outPath);
  outFile.parent.createSync(recursive: true);

  const size = 1024;
  final background = img.ColorRgba8(10, 125, 132, 255); 
  final vestColor = img.ColorRgba8(255, 196, 0, 255); 
  final stripeColor = img.ColorRgba8(240, 240, 240, 255); 
  final outlineColor = img.ColorRgba8(15, 40, 45, 255);

  final canvas = img.Image(width: size, height: size);
  img.fill(canvas, color: background);

  
  final cx = size ~/ 2;
  final topY = (size * 0.15).round();
  final bottomY = (size * 0.88).round();

  final shoulderWidth = (size * 0.52).round();
  final bodyWidth = (size * 0.62).round();
  final neckWidth = (size * 0.20).round();
  final neckDepth = (size * 0.13).round();
  final armInsetY = (size * 0.30).round();
  final armInsetX = (size * 0.10).round();

  final left = cx - bodyWidth ~/ 2;
  final right = cx + bodyWidth ~/ 2;
  final leftShoulder = cx - shoulderWidth ~/ 2;
  final rightShoulder = cx + shoulderWidth ~/ 2;

  
  final outer = <img.Point>[
    img.Point(leftShoulder, topY),
    img.Point(cx - neckWidth ~/ 2, topY),
    img.Point(cx - neckWidth ~/ 2, topY + neckDepth),
    img.Point(cx + neckWidth ~/ 2, topY + neckDepth),
    img.Point(cx + neckWidth ~/ 2, topY),
    img.Point(rightShoulder, topY),
    img.Point(right, armInsetY),
    img.Point(right - armInsetX, bottomY),
    img.Point(left + armInsetX, bottomY),
    img.Point(left, armInsetY),
  ];

  img.fillPolygon(canvas, vertices: outer, color: vestColor);

  
  for (var i = 0; i < outer.length; i++) {
    final a = outer[i];
    final b = outer[(i + 1) % outer.length];
    img.drawLine(
      canvas,
      x1: a.xi,
      y1: a.yi,
      x2: b.xi,
      y2: b.yi,
      color: outlineColor,
      thickness: 10,
    );
  }

  
  final armRadius = (size * 0.18).round();
  img.fillCircle(
    canvas,
    x: left + armRadius,
    y: armInsetY + armRadius ~/ 3,
    radius: armRadius,
    color: background,
  );
  img.fillCircle(
    canvas,
    x: right - armRadius,
    y: armInsetY + armRadius ~/ 3,
    radius: armRadius,
    color: background,
  );

  
  img.drawLine(
    canvas,
    x1: cx,
    y1: topY + neckDepth,
    x2: cx,
    y2: bottomY,
    color: outlineColor,
    thickness: 8,
  );

  
  final stripeH = (size * 0.055).round();
  final stripeMargin = (size * 0.09).round();
  final stripeY1 = (size * 0.46).round();
  final stripeY2 = (size * 0.62).round();
  final stripeLeft = left + stripeMargin;
  final stripeRight = right - stripeMargin;

  void stripeRect(int x, int y, int w, int h) {
    img.fillRect(canvas, x1: x, y1: y, x2: x + w, y2: y + h, color: stripeColor);
    img.drawRect(canvas, x1: x, y1: y, x2: x + w, y2: y + h, color: outlineColor, thickness: 6);
  }

  stripeRect(stripeLeft, stripeY1, stripeRight - stripeLeft, stripeH);
  stripeRect(stripeLeft, stripeY2, stripeRight - stripeLeft, stripeH);

  final stripeVw = (size * 0.055).round();
  final stripeVyTop = (size * 0.33).round();
  final stripeVyBottom = (size * 0.84).round();
  stripeRect(cx - (size * 0.17).round(), stripeVyTop, stripeVw, stripeVyBottom - stripeVyTop);
  stripeRect(cx + (size * 0.11).round(), stripeVyTop, stripeVw, stripeVyBottom - stripeVyTop);

  
  final bytes = img.encodePng(canvas, level: 6);
  outFile.writeAsBytesSync(bytes, flush: true);

  stdout.writeln('Wrote icon to ${outFile.path} (${bytes.length} bytes)');
}

