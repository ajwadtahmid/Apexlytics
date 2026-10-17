import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'app_logger.dart';

/// Renders the [RepaintBoundary] behind [key] to PNG bytes. [pixelRatio] scales
/// its logical size, so a 360 px wide card at 3 comes out 1080 px wide.
Future<Uint8List> captureBoundaryAsPng(
  GlobalKey key, {
  double pixelRatio = 3,
}) async {
  final boundary =
      key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) throw StateError('Nothing to capture');
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Could not encode the image');
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Writes [png] to a temporary file, opens the share sheet for it and deletes
/// the file again. True only when the sheet reports the user completed an
/// action. [share] and [dir] are test seams.
@visibleForTesting
Future<bool> shareImageFile(
  Uint8List png, {
  String name = 'apexlytics_card.png',
  Future<ShareResult> Function(ShareParams params)? share,
  Directory? dir,
}) async {
  final folder = dir ?? await getTemporaryDirectory();
  final file = File('${folder.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(png);
  try {
    final result = await (share ?? SharePlus.instance.share)(
      ShareParams(files: [XFile(file.path, mimeType: 'image/png')]),
    );
    return result.status == ShareResultStatus.success;
  } finally {
    try {
      if (await file.exists()) await file.delete();
    } catch (e) {
      log.w('Share image cleanup failed', error: e);
    }
  }
}

/// Captures [key] and shares it as an image.
Future<bool> shareBoundary(
  GlobalKey key, {
  Future<ShareResult> Function(ShareParams params)? share,
  Directory? dir,
}) async =>
    shareImageFile(await captureBoundaryAsPng(key), share: share, dir: dir);
