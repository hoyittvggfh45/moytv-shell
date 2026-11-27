import '../cloud_drive/cloud_115_offline.dart';
import 'actress_magnet_library.dart';

/// 磁力作品走 115 网盘离线播放（2026-11-27 用户亲口钉死）：
/// 不做 P2P、不做本机种子引擎。点播链＝先按番号查网盘有没有
/// 这部片，有→取链直接播；没有→自动提交磁力离线（同番号多
/// 条逐条试、一条成功即止），下好后按番号找到文件再播。
/// 卡片/详情的三态（未下载／离线中／网盘可播）由网盘离线
/// 任务列表 + 本地已提交记录合成，详情页再按番号确认一次
/// 网盘里真有文件才算「网盘可播」。

/// 磁力作品在网盘侧的三态。
enum MagnetDriveState {
  /// 没提交过、网盘里也没有。
  notDownloaded,

  /// 已提交离线（任务在跑，或已提交但任务列表还没刷新出来）。
  downloading,

  /// 网盘里已有这部片，能直接播。
  readyInDrive,
}

extension MagnetDriveStateLabel on MagnetDriveState {
  String get label => switch (this) {
    MagnetDriveState.notDownloaded => '未下载',
    MagnetDriveState.downloading => '离线中',
    MagnetDriveState.readyInDrive => '网盘可播',
  };
}

/// 离线任务与番号是否对得上：任务名提码后与番号归一键比对
/// （与网盘文件按番号匹配同一把尺，见 pan115FileForCode）。
bool pan115TaskMatchesCode(Pan115OfflineTask task, String code) {
  final key = pan115CodeKeyOf(code);
  if (key.isEmpty) return false;
  final extracted = pan115ExtractCode(task.name);
  return extracted != null && pan115CodeKeyOf(extracted) == key;
}

/// 离线任务与某条磁力是否同一份：比 infohash。无番号作品
/// （如韩国主播，vod_id 是合成的 magnet-<哈希>）按名字对不
/// 上番号，只能靠这一路认任务。
bool pan115TaskMatchesMagnets(
  Pan115OfflineTask task,
  List<String> magnetUrls,
) {
  final hash = task.infoHash.trim().toLowerCase();
  if (hash.isEmpty) return false;
  return magnetUrls.any((url) => pan115InfoHashOf(url) == hash);
}

/// 任务是否属于这部作品：哈希命中或任务名番号命中任一即可。
bool pan115TaskMatchesWork(
  Pan115OfflineTask task,
  String code,
  List<String> magnetUrls,
) =>
    pan115TaskMatchesMagnets(task, magnetUrls) ||
    pan115TaskMatchesCode(task, code);

/// 三态合成器：网关可注入，测试用假网关验判定。
class MagnetDriveStateResolver {
  MagnetDriveStateResolver(this.gateway);

  final Pan115Gateway gateway;

  /// 一次取齐合成三态要的两份快照（任务列表 + 已提交记录）。
  Future<({Set<String> submitted, List<Pan115OfflineTask> tasks})>
  snapshot() async {
    var submitted = <String>{};
    var tasks = <Pan115OfflineTask>[];
    try {
      submitted = await gateway.submittedHashes();
    } catch (_) {
      // 读不到提交记录按没提交过走，不拦状态显示。
    }
    try {
      tasks = await gateway.listOfflineTasks();
    } catch (_) {
      // 任务列表拉不到按没有任务走。
    }
    return (submitted: submitted, tasks: tasks);
  }

  /// 纯合成（不发网盘请求）：任务命中番号优先——完成了算
  /// 网盘可播、在跑算离线中；没任务但磁力哈希在已提交记录
  /// 里算离线中；其余未下载。
  MagnetDriveState stateFromSnapshot({
    required String code,
    required List<String> magnetUrls,
    required Set<String> submitted,
    required List<Pan115OfflineTask> tasks,
  }) {
    for (final task in tasks) {
      if (!pan115TaskMatchesWork(task, code, magnetUrls)) continue;
      return task.done
          ? MagnetDriveState.readyInDrive
          : MagnetDriveState.downloading;
    }
    for (final url in magnetUrls) {
      final hash = pan115InfoHashOf(url);
      if (hash.isNotEmpty && submitted.contains(hash)) {
        return MagnetDriveState.downloading;
      }
    }
    return MagnetDriveState.notDownloaded;
  }

  /// 详情页口径：快照合成后不是「网盘可播」时，再按番号去
  /// 网盘确认一次——真有文件才升到网盘可播（用户可能在别处
  /// 早就下好了这部片，没有离线任务记录）。
  Future<MagnetDriveState> resolve({
    required String code,
    required List<String> magnetUrls,
  }) async {
    final snap = await snapshot();
    final state = stateFromSnapshot(
      code: code,
      magnetUrls: magnetUrls,
      submitted: snap.submitted,
      tasks: snap.tasks,
    );
    if (state == MagnetDriveState.readyInDrive) return state;
    try {
      final file = await gateway.findFileByCode(code);
      if (file != null) return MagnetDriveState.readyInDrive;
    } catch (_) {
      // 查不到不改合成结论。
    }
    return state;
  }
}

/// 点播结果的五种走向。
enum MagnetPlayOutcomeKind {
  /// 网盘里有片且取到直链，直接播。
  playable,

  /// 115 没登入，先引导登入。
  needsLogin,

  /// 刚提交成功，等下载完成。
  submitted,

  /// 已经在离线中（或下完了还在整理）。
  downloading,

  /// 播不了，message 是中文原因。
  failed,
}

class MagnetPlayOutcome {
  const MagnetPlayOutcome._(
    this.kind, {
    this.url = '',
    this.headers = const {},
    this.message = '',
  });

  factory MagnetPlayOutcome.playable({
    required String url,
    Map<String, String> headers = const {},
  }) => MagnetPlayOutcome._(
    MagnetPlayOutcomeKind.playable,
    url: url,
    headers: headers,
  );

  factory MagnetPlayOutcome.needsLogin() => const MagnetPlayOutcome._(
    MagnetPlayOutcomeKind.needsLogin,
    message: '115 还没登入',
  );

  factory MagnetPlayOutcome.submitted(String message) =>
      MagnetPlayOutcome._(MagnetPlayOutcomeKind.submitted, message: message);

  factory MagnetPlayOutcome.downloading(String message) =>
      MagnetPlayOutcome._(
        MagnetPlayOutcomeKind.downloading,
        message: message,
      );

  factory MagnetPlayOutcome.failed(String message) =>
      MagnetPlayOutcome._(MagnetPlayOutcomeKind.failed, message: message);

  final MagnetPlayOutcomeKind kind;

  /// playable 时的播放直链。
  final String url;

  /// playable 时的播放请求头。
  final Map<String, String> headers;

  /// 给用户看的中文说明（playable 时为空）。
  final String message;
}

/// 磁力点播链：查网盘 → 在离线中 → 提交离线。网关可注入。
class MagnetOfflinePlayFlow {
  MagnetOfflinePlayFlow(this.gateway);

  final Pan115Gateway gateway;

  Future<MagnetPlayOutcome> play({
    required String code,
    required List<String> magnetUrls,
  }) async {
    final magnets = [
      for (final url in magnetUrls)
        if (actressIsMagnetPlayUrl(url)) url,
    ];
    if (magnets.isEmpty) {
      return MagnetPlayOutcome.failed('这部作品没有磁力链接');
    }
    if (code.trim().isEmpty) {
      return MagnetPlayOutcome.failed('这部作品没有番号，没法去网盘里找');
    }
    var loggedIn = false;
    try {
      loggedIn = await gateway.isLoggedIn();
    } catch (_) {
      loggedIn = false;
    }
    if (!loggedIn) return MagnetPlayOutcome.needsLogin();

    // 1) 网盘里已有这部片：取链直接播。
    try {
      final file = await gateway.findFileByCode(code);
      if (file != null) {
        final link = await gateway.directLink(file);
        if (link != null && link.url.trim().isNotEmpty) {
          return MagnetPlayOutcome.playable(
            url: link.url,
            headers: link.headers,
          );
        }
        return MagnetPlayOutcome.failed('网盘里有这部片，但取播放地址失败，稍后再试');
      }
    } catch (_) {
      // 查网盘这步失败不拦：继续走离线提交。
    }

    // 2) 已在离线任务里：报状态，不重复提交。
    final resolver = MagnetDriveStateResolver(gateway);
    final snap = await resolver.snapshot();
    for (final task in snap.tasks) {
      if (!pan115TaskMatchesWork(task, code, magnets)) continue;
      if (task.done) {
        return MagnetPlayOutcome.downloading(
          '离线已经下完，但还没按番号在网盘里找到文件：'
          '稍等一会儿再点一次，或去「网盘」页搜这部片的标题直接播',
        );
      }
      final percent = (task.percent * 100).toStringAsFixed(0);
      return MagnetPlayOutcome.downloading('这部片正在离线下载中（$percent%），下好后回来点播');
    }

    // 3) 提交离线：同番号多条逐条试，一条成功即止；本地已
    // 提交过的哈希跳过（115 那边再交会报重复）。
    var attempted = 0;
    for (final magnet in magnets) {
      final hash = pan115InfoHashOf(magnet);
      if (hash.isNotEmpty && snap.submitted.contains(hash)) continue;
      attempted++;
      var ok = false;
      try {
        ok = await gateway.submitOffline(magnet);
      } catch (_) {
        ok = false;
      }
      if (ok) {
        if (hash.isNotEmpty) {
          try {
            await gateway.recordSubmitted(hash);
          } catch (_) {
            // 记录落不下不改提交已成功的事实。
          }
        }
        return MagnetPlayOutcome.submitted('已提交 115 离线下载，下好后回来点播就是「网盘可播」');
      }
    }
    if (attempted == 0) {
      return MagnetPlayOutcome.downloading('这部片已经提交过离线了，网盘里还没找到文件，再等等');
    }
    return MagnetPlayOutcome.failed('115 离线提交失败（可能配额已满或这条磁力不可用），稍后再试');
  }
}
