import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_selector/file_selector.dart' as file_selector;
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

/// Whether the platform's share can send a file. It can't on Linux, where
/// share_plus only shares text, so a card is saved to a file there instead.
bool get canShareFiles => debugCanShareFiles ?? !Platform.isLinux;

/// Overrides [canShareFiles] in tests, which run on whatever host they are on.
@visibleForTesting
bool? debugCanShareFiles;

/// Asks where to put [png] and writes it there. Resolves to the path saved to,
/// or null when the user cancelled. [pickPath] is a test seam in place of the
/// system save dialog; it is given the suggested file name.
Future<String?> saveImageFile(
  Uint8List png, {
  String name = 'apexlytics_card.png',
  Future<String?> Function(String suggestedName)? pickPath,
}) async {
  final path = await (pickPath ?? _pickSavePath)(name);
  if (path == null) return null;
  await File(path).writeAsBytes(png);
  return path;
}

Future<String?> _pickSavePath(String suggestedName) async {
  final location = await file_selector.getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: const [
      file_selector.XTypeGroup(label: 'PNG image', extensions: ['png']),
    ],
  );
  return location?.path;
}

/// Captures [key] and saves it as an image file.
Future<String?> saveBoundary(
  GlobalKey key, {
  Future<String?> Function(String suggestedName)? pickPath,
}) async => saveImageFile(await captureBoundaryAsPng(key), pickPath: pickPath);

/// Captures [key] and shares it as an image.
Future<bool> shareBoundary(
  GlobalKey key, {
  Future<ShareResult> Function(ShareParams params)? share,
  Directory? dir,
}) async =>
    shareImageFile(await captureBoundaryAsPng(key), share: share, dir: dir);
