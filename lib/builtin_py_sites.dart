import 'dart:async';

import 'package:flutter/services.dart';

import 'import_file_store.dart';
import 'models.dart';
import 'py_bridge.dart';

/// 内置 py 插件的一条站点记录：一个 py 文件对应一条，jinguo.py 对应两条。
class BuiltinPyEntry {
  const BuiltinPyEntry({
    required this.siteId,
    required this.site,
    required this.assetPath,
    required this.fileId,
  });

  final String siteId;
  final SourceSite site;
  final String assetPath;
  final String fileId;
}

class BuiltinPySites {
  BuiltinPySites._();

  /// 以下三个站 id 仅作女优库跨站探针的候选名单（adult_scrape_service
  /// 引用）：站点本体已随 2026-11-26 空壳片库剥离，候选查不到可用站
  /// 会自动跳过，保留常量只是不让探针名单断链。
  static const javmenuSiteId = 'javmenu';
  static const avdbSiteId = 'avdb';
  static const memojavSiteId = 'memojav';

  /// 全部内置 py 插件条目：2026-11-26 空壳片库定版，原 127 条内置 py
  /// 站登记与 assets/py_spiders/ 资源全部剥离（站点改从插件市场安装、
  /// 外部导入），本表清空；注册/安装/卸载机器保留，清单为空即无操作。
  static const List<BuiltinPyEntry> entries = [];

  static BuiltinPyEntry? entryFor(String siteId) {
    for (final entry in entries) {
      if (entry.siteId == siteId) return entry;
    }
    return null;
  }

  static Future<void> _install(BuiltinPyEntry entry) async {
    final bytes = await rootBundle.load(entry.assetPath);
    final fileName = await ImportFileStore.save(
      entry.fileId,
      'py',
      bytes.buffer.asUint8List(),
    );
    SourceSite.importedSites[entry.siteId] = entry.site;
    SourceSite.importedPyFiles[entry.siteId] = fileName;
  }

  static Future<bool> register() => registerSkipping(const {});

  /// 注册全部内置 py 插件，跳过 [skipSiteIds]（用户已卸载的插件的站点）。
  static Future<bool> registerSkipping(Set<String> skipSiteIds) async {
    try {
      for (final entry in entries) {
        if (skipSiteIds.contains(entry.siteId)) continue;
        try {
          await _install(entry);
        } catch (_) {}
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 安装单个内置 py 站点（插件重装时用）。失败返回 false。
  static Future<bool> installEntry(String siteId) async {
    final entry = entryFor(siteId);
    if (entry == null) return false;
    try {
      await _install(entry);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 卸载单个内置 py 站点：撤登记 + 释放该文件的解释器会话 +
  /// 删落盘文件副本，不留残影。
  static Future<void> uninstallEntry(String siteId) async {
    final entry = entryFor(siteId);
    SourceSite.importedSites.remove(siteId);
    final fileName = SourceSite.importedPyFiles.remove(siteId);
    final target = fileName ?? (entry == null ? '' : '${entry.fileId}.py');
    if (target.isNotEmpty) {
      final path = await ImportFileStore.pathOf(target);
      unawaited(PyBridge.dispose(path));
    }
    await ImportFileStore.delete(target);
  }
}
