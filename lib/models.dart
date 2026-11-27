import 'dart:convert';

import 'app_build.dart';
import 'track_selection.dart';

/// 用户自定义的 MacCMS / XBPQ 站源记录。
class CustomSourceSite {
  const CustomSourceSite({
    required this.id,
    required this.name,
    required this.base,
    this.rule = '',
    this.kind = '',
  });
  final String id;
  final String name;
  final String base;
  final String rule;

  /// 源类型：web=网页源（走 HTML 抓取）/ json=JSON 源（直连 API）/ 空=自动识别。
  final String kind;

  factory CustomSourceSite.fromJson(Map<String, dynamic> json) =>
      CustomSourceSite(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        base: json['base'] as String? ?? '',
        rule: json['rule'] as String? ?? '',
        kind: (json['kind'] as String? ?? json['type'] as String? ?? ''),
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'base': base,
    if (rule.isNotEmpty) 'rule': rule,
    if (kind.isNotEmpty) 'kind': kind,
  };
  bool get isCustom => SourceSite.isCustomId(id);
  bool get hasRule => rule.trim().isNotEmpty;
  SourceSite get asSourceSite => SourceSite(
    id,
    name,
    base,
    section: SourceSite.sectionVideo,
    origin: SourceSite.originConfig,
  );
}

class SourceSite {
  const SourceSite(
    this.id,
    this.name,
    this.description, {
    this.section = sectionDrama,
    this.slotId = '',
    this.origin = originBuiltin,
    this.configId = '',
    this.configName = '',
    this.importType = '',
    this.importExt = '',
  });

  static const sectionDrama = 'drama';
  static const sectionVideo = 'video';
  static const originBuiltin = 'builtin';
  static const originConfig = 'config';
  static const originImport = 'import';

  final String id;
  final String name;
  final String description;
  final String section;
  final String slotId;
  final String origin;
  final String configId;
  final String configName;
  final String importType;
  final String importExt;
  bool get isVideoSection => section == sectionVideo;
  bool get isDramaSection => section != sectionVideo;

  /// HTML 导入站：点选进宿主页面，不走目录/搜索/聚合链路。
  /// 与 ImportedSiteRecord.typeHtml 同值（importType 由登记 asSite 填入）。
  bool get isHtmlSite => importType == 'html';
  String get coreSlotId => slotId.isEmpty ? id : slotId;
  bool get onlineSearch =>
      isVideoSection || id == 'hongguo' || pagedSearch || duanjuOnlineSearch;
  bool get duanjuOnlineSearch =>
      // 动态安装的 idj 短剧站没有字面量可补，改规则式：
      // 短剧分区 + js 导入站自动获得在线搜索（现有 JS 站全是视频分区，
      // 不受影响）。
      (isDramaSection && importType == 'js') ||
      const {
        'yaguo',
        'maoguo',
        'fanguo',
        'guanguo',
        'heguo',
        'xingguo',
        'huaguo',
        'niuguo',
        'wangguo',
        'faguo',
        'wuguo',
        'huangdou_yh',
        'ai2026',
        'ai4k',
        'aidj',
        'aiduanju',
        'aimove',
        'aisxpc',
        'danai',
        'dj69',
        'dj91',
        'djwo',
        'duanjuone',
        'aihi',
        'ficeforand',
        'aipornx',
        'aiyinhang',
        'sexaix',
        'aiwu',
        'youzidj',
        'jinguo',
        'jinguo_jg',
      }.contains(id);
  bool get pagedSearch =>
      isVideoSection ||
      id == 'huangju' ||
      id == 'yeguo' ||
      id == 'dsd' ||
      id == 'guipian' ||
      id == 'hanxiaoquan' ||
      id == 'ikanbot' ||
      id == 'a123' ||
      duanjuPaged;
  bool get duanjuPaged =>
      (isDramaSection && importType == 'js') ||
      const {
        'yaguo',
        'guanguo',
        'huaguo',
        'niuguo',
        'wangguo',
        'faguo',
        'wuguo',
        'huangdou_yh',
        'ai2026',
        'ai4k',
        'aidj',
        'aiduanju',
        'aimove',
        'aisxpc',
        'danai',
        'dj69',
        'dj91',
        'djwo',
        'duanjuone',
        'aihi',
        'ficeforand',
        'aipornx',
        'aiyinhang',
        'sexaix',
        'aiwu',
        'youzidj',
        'jinguo',
        'jinguo_jg',
      }.contains(id);
  bool get searchSuggestions => id == 'hongguo';
  String get groupId => switch (id) {
    'huangguo-video' || 'huangguoai' || 'cloudfront' => 'huangguo',
    _ => id,
  };
  String get groupName => groupId == 'huangguo' ? '黄果' : name;
  String get entryName => switch (id) {
    'huangguo-video' => '视频',
    'huangguoai' => 'AI',
    'cloudfront' => '旧版',
    _ => name,
  };

  static const hongguo = SourceSite(
    'hongguo',
    '红果',
    '短剧 · 漫剧 · AI 剧 · 小说 · 听书',
    section: sectionDrama,
  );
  static const hongguoNew = SourceSite(
    'hongguo_new',
    '红果(新)',
    '红果短剧全集 + 五档清晰度',
    section: sectionDrama,
  );
  static const fanqie = SourceSite(
    'fanqie',
    '番茄',
    '番茄短剧 · 排行榜单流',
    section: sectionDrama,
  );
  static const dsd = SourceSite('dsd', '帝果', '分类视频 · 在线搜索');
  static const guipian = SourceSite(
    'guipian',
    '鬼片',
    '鬼片 · 电视剧 · 动漫',
    section: sectionDrama,
  );
  static const ikanbot = SourceSite(
    'ikanbot',
    '爱看机器人',
    '电影 · 剧集 · 多线路搜索',
    section: sectionDrama,
  );
  static const a123 = SourceSite(
    'a123',
    'A123',
    '电影 · 连续剧 · 综艺 · 动漫 · 多线路',
    section: sectionDrama,
  );
  static const hanxiaoquan = SourceSite(
    'hanxiaoquan',
    '韩小圈',
    '韩剧 · 韩国电影 · 综艺动漫',
    section: sectionDrama,
  );
  /// 短剧/影视内置站表：2026-11-26 空壳片库定版，内置站登记全部剥离
  /// （站点改从插件市场安装/外部导入），两表清空保留空表占位。
  static const duanjuValues = <SourceSite>[];
  static const videoValues = <SourceSite>[];
  /// 内置站总表：2026-11-26 空壳片库定版后只剩原生功能站——
  /// 红果 / 红果(新) / 番茄是原生代码写死的功能（短剧功能页 + 原生
  /// 签名栈，插件市场装不回来），按用户令保留登记；其余片库内置站
  /// （py 蜘蛛、jar、Go 核槽位站）登记全部剥离，改从插件市场/导入进站。
  static const knownValues = [hongguo, hongguoNew, fanqie];
  static const allValues = [hongguo, hongguoNew, fanqie];
  static const values = allSourcesEnabled ? knownValues : [hongguo];

  /// 当前会话已注册的自定义源 ID，供可用性判断与站源归一化使用。
  static final Set<String> customIds = {};

  /// 导入配置（TVBox 远程配置等）动态注册的站点，key 为站点 id。
  /// 导入功能本体负责填充与持久化，本表只是壳侧的预留注册结构：
  /// 配置删除时只需移除该配置名下的条目，内置站不受影响。
  static final Map<String, SourceSite> importedSites = {};

  /// 网盘站源动态注册表，key 为站点 id（`cloud:<网盘>`）。
  /// 只注册已登录的网盘，由 CloudDriveStations.refresh 维护；
  /// 与导入配置的注册表分开，删配置不影响网盘站。
  static final Map<String, SourceSite> cloudDriveSites = {};

  /// 演员库内部源登记表（2026-11-26 发版实报修复）：演员库在线
  /// 源（JavDB / 123AV / PH / AV01 / Jable）与 115 竞速线造的
  /// Drama 用这批 id 作 source。它们是演员库模块内部源、不是
  /// 片库可切换站点：不进 values / knownValues / allValues，
  /// LocalStore.sources 也不读本表，所以不会出现在选站列表
  /// 里；登记只为让 isAvailable / isKnown / byId 认它们——否则
  /// 详情页源门禁（allowsSource）对这批 id 恒为假，从演员库
  /// 点开任何作品都误落「当前用户无权访问」面板。
  /// 注意 pan115 是演员库 115 线的内部 id，与网盘站的
  /// cloud:pan115 是两个 id，不要混。
  static const Map<String, SourceSite> actressOnlySites = {
    'javdb': SourceSite(
      'javdb',
      'JavDB',
      '演员库在线源 · 番号信息与剧照',
      section: sectionVideo,
    ),
    'av123': SourceSite('av123', '123AV', '演员库在线源', section: sectionVideo),
    'ph': SourceSite('ph', 'PH', '演员库在线源', section: sectionVideo),
    'av01': SourceSite('av01', 'AV01', '演员库在线源', section: sectionVideo),
    'jable': SourceSite('jable', 'Jable', '演员库在线源', section: sectionVideo),
    'pan115': SourceSite(
      'pan115',
      '115',
      '演员库 115 已存 / 离线线路',
      section: sectionVideo,
    ),
    // 本地女优库里 vod_play_from='lsp' 的那批作品（定版库
    // 107,844 部、占 24%）：toDramaDetail 对它不做映射、原样
    // 当 Drama.source，此前全仓零登记，点开必落「当前用户
    // 无权访问」面板（2026-11-27 用户实报）。它只是库内数据
    // 来源标记、不是片库可切换站点，故只进这张专用登记表。
    'lsp': SourceSite(
      'lsp',
      '本地库',
      '演员库本地库数据来源',
      section: sectionVideo,
    ),
  };

  /// py 导入站的蜘蛛文件名（应用文档目录 imported_spiders/ 下），key 为站点 id。
  static final Map<String, String> importedPyFiles = {};
  static final Map<String, String> importedJsFiles = {};
  static final Map<String, String> importedPyRemoteUrls = {};
  static final Map<String, String> importedJsRemoteUrls = {};

  /// HTML 导入站的文件名（同一 imported_spiders/ 目录），key 为站点 id。
  static final Map<String, String> importedHtmlFiles = {};
  static bool isCustomId(String id) => id.startsWith('custom:');
  static bool isAvailable(String id) =>
      values.any((site) => site.id == id) ||
      customIds.contains(id) ||
      importedSites.containsKey(id) ||
      cloudDriveSites.containsKey(id) ||
      actressOnlySites.containsKey(id);
  static bool isKnown(String id) =>
      allValues.any((site) => site.id == id) ||
      customIds.contains(id) ||
      importedSites.containsKey(id) ||
      cloudDriveSites.containsKey(id) ||
      actressOnlySites.containsKey(id);
  static SourceSite byId(String id) {
    final cloud = cloudDriveSites[id];
    if (cloud != null) return cloud;
    final imported = importedSites[id];
    if (imported != null) return imported;
    final actressOnly = actressOnlySites[id];
    if (actressOnly != null) return actressOnly;
    if (customIds.contains(id)) {
      return SourceSite(
        id,
        customName(id),
        '自定义站源',
        section: sectionVideo,
        origin: originConfig,
      );
    }
    return allValues.firstWhere((site) => site.id == id, orElse: () => hongguo);
  }

  static String customName(String id) {
    if (id.startsWith('custom:')) return '自定义源';
    return id;
  }

  /// 从未配置过「源显示列表」时默认隐藏的内置站源。
  /// 默认可见集 = 红果、韩小圈、鬼片、A123、爱看机器人，
  /// 其余内置源（whos识图、剧果、野果、帝果、黄果视频、黄果 AI、黄果旧版、
  /// 芽果、猫果、饭果、观果、河果、星果、花果、牛果、网果、发果、伍果）默认隐藏。
  static const defaultHiddenSiteIds = <String>{
    // 旧内置站 id 已随 2026-11-26 空壳片库剥离失效，一并清掉；
    // 下面只剩 idj 成人站（只影响从未配过隐藏列表的新用户；已配过的用户以存档值为准）：
    // 默认不显示，要在源显示列表里手动打开才可见。只是默认不显示，
    // 不是访问控制（导入站走 allowsSource 直接放行）。
    'idj_chaoliu',
    'idj_ai2048',
    'idj_porntube',
    'idj_qiyoushe',
    'idj_hqporner',
  };
}

/// 统一视频区谓词（第二阶段站合并后）：全部视频分区站源都在点播区浏览，
/// 不再按来源（内置/导入）或 🔞 名拆成点播/午夜两个区。午夜区已并入
/// 统一站点区（站源管理页呈现与管理），本谓词是首页唯一的视频区分流。
bool isVodZoneSource(SourceSite site) => site.isVideoSection;

class SourceGroup {
  const SourceGroup(
    this.id,
    this.name,
    this.sources, {
    this.origin = SourceSite.originBuiltin,
    this.configId = '',
  });
  final String id;
  final String name;
  final List<SourceSite> sources;

  /// 分组来源：builtin=内置写死站点；config=某份导入配置。
  final String origin;

  /// origin=config 时所属配置的 id；删配置只删该组，内置组恒在。
  final String configId;
  bool get isConfig => origin == SourceSite.originConfig;

  factory SourceGroup.config({
    required String configId,
    required String name,
    required List<SourceSite> sources,
  }) => SourceGroup(
    'config:$configId',
    name,
    sources,
    origin: SourceSite.originConfig,
    configId: configId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'origin': origin,
    if (configId.isNotEmpty) 'configId': configId,
    'sourceIds': [for (final source in sources) source.id],
  };

  factory SourceGroup.fromJson(Map<String, dynamic> json) => SourceGroup(
    json['id'] as String? ?? '',
    json['name'] as String? ?? '',
    [
      for (final id in json['sourceIds'] as List? ?? const [])
        SourceSite.byId(id as String),
    ],
    origin: json['origin'] as String? ?? SourceSite.originBuiltin,
    configId: json['configId'] as String? ?? '',
  );

  static List<SourceGroup> fromSources(Iterable<SourceSite> sources) {
    final groups = <String, List<SourceSite>>{};
    for (final source in sources) {
      (groups[source.groupId] ??= []).add(source);
    }
    return [
      for (final group in groups.entries)
        SourceGroup(group.key, group.value.first.groupName, group.value),
    ];
  }

  /// 站点切换的展示分组：内置短剧组 / 内置影视组 / 导入配置组。
  /// [imported] 为已导入配置各自的分组（本轮可为空组渲染），
  /// 与内置组并列返回；内置组恒在，不随配置增删变化。
  static List<SourceGroup> sectionGroups(
    Iterable<SourceSite> sources, {
    List<SourceGroup> imported = const [],
  }) {
    final drama = <SourceSite>[];
    final video = <SourceSite>[];
    final importedSites = <SourceSite>[];
    final looseConfig = <SourceSite>[];
    final byConfig = <String, List<SourceSite>>{};
    for (final source in sources) {
      if (source.origin == SourceSite.originImport) {
        importedSites.add(source);
      } else if (source.origin == SourceSite.originConfig) {
        if (source.configId.isNotEmpty) {
          (byConfig[source.configId] ??= []).add(source);
        } else {
          looseConfig.add(source);
        }
      } else if (source.isVideoSection) {
        video.add(source);
      } else {
        drama.add(source);
      }
    }
    return [
      if (drama.isNotEmpty) SourceGroup('builtin:drama', '内置短剧', drama),
      if (video.isNotEmpty) SourceGroup('builtin:video', '内置影视', video),
      if (importedSites.isNotEmpty)
        SourceGroup(
          'import',
          '导入',
          importedSites,
          origin: SourceSite.originImport,
        ),
      if (looseConfig.isNotEmpty)
        SourceGroup(
          'config:custom',
          '导入配置',
          looseConfig,
          origin: SourceSite.originConfig,
          configId: 'custom',
        ),
      for (final entry in byConfig.entries)
        SourceGroup.config(
          configId: entry.key,
          name: entry.value.first.configName.isNotEmpty
              ? entry.value.first.configName
              : '导入配置',
          sources: entry.value,
        ),
      ...imported,
    ];
  }

  /// 站点切换弹窗的展示分组（设计 §5.3）：按内容类别分，不按来源分。
  /// 短剧类 = `section == sectionDrama`（不论显示名带不带 🔞）；
  /// 视频类 = 视频分区且显示名不以 🔞 开头；
  /// 午夜类 = 视频分区且显示名以 🔞 开头。
  /// 空组不出现；组内顺序沿用传入的顺序，不重排。
  /// 这只是展示分组，不改变任何站的浏览分区（`isVodZoneSource` 不动）。
  static List<SourceGroup> pickerCategoryGroups(Iterable<SourceSite> sources) {
    final drama = <SourceSite>[];
    final video = <SourceSite>[];
    final midnight = <SourceSite>[];
    for (final source in sources) {
      if (!source.isVideoSection) {
        drama.add(source);
      } else if (source.name.startsWith('🔞')) {
        midnight.add(source);
      } else {
        video.add(source);
      }
    }
    return [
      if (drama.isNotEmpty) SourceGroup('picker:drama', '短剧类', drama),
      if (video.isNotEmpty) SourceGroup('picker:video', '视频类', video),
      if (midnight.isNotEmpty) SourceGroup('picker:midnight', '午夜类', midnight),
    ];
  }
}

class CatalogCategory {
  const CatalogCategory(
    this.id,
    this.name, {
    this.local = false,
    this.kind = '',
    this.folderId = '',
  });
  static const all = CatalogCategory('', '全部');
  final String id;
  final String name;
  final bool local;

  /// 分类条目本身也可为文件夹（多级分类）：kind=folder 时点入下钻。
  final String kind;
  final String folderId;
  bool get isFolder => kind == 'folder' || folderId.isNotEmpty;
  String get drillId => folderId.isNotEmpty ? folderId : id;
  factory CatalogCategory.fromJson(Map<String, dynamic> json) =>
      CatalogCategory(
        json['id'] as String? ?? '',
        json['name'] as String? ?? '全部',
        kind: json['kind'] as String? ?? '',
        folderId: json['folderId'] as String? ?? '',
      );
}

class CatalogTag {
  const CatalogTag(this.id, this.name);
  final String id;
  final String name;
  String get folderId => id.startsWith('tag:') ? id : 'tag:$id';
  factory CatalogTag.fromJson(Object? value) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      return CatalogTag(
        map['id']?.toString() ?? '',
        map['name']?.toString() ?? '',
      );
    }
    final text = value?.toString() ?? '';
    return CatalogTag(text, text);
  }
}

class CatalogFilterOption {
  const CatalogFilterOption(this.id, this.name);
  final String id;
  final String name;
  factory CatalogFilterOption.fromJson(Map<String, dynamic> json) =>
      CatalogFilterOption(
        json['id']?.toString() ?? '',
        json['name']?.toString() ?? '',
      );
}

class CatalogFilterGroup {
  const CatalogFilterGroup(this.key, this.name, this.options);
  final String key;
  final String name;
  final List<CatalogFilterOption> options;
  factory CatalogFilterGroup.fromJson(Map<String, dynamic> json) =>
      CatalogFilterGroup(
        json['key']?.toString() ?? '',
        json['name']?.toString() ?? '',
        [
          for (final row in json['options'] as List? ?? const [])
            if (row is Map)
              CatalogFilterOption.fromJson(Map<String, dynamic>.from(row)),
        ].where((option) => option.id.isNotEmpty).toList(),
      );
}

int intValue(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

class Drama {
  const Drama({
    required this.id,
    required this.source,
    required this.title,
    this.sourceId = '',
    this.description = '',
    this.cover = '',
    this.episodes = 0,
    this.category = '',
    bool? vip,
    this.heat = '',
    this.views = '',
    this.onlineDate = '',
    this.tags = const [],
    this.releaseStatus = '',
    this.kind = 'video',
    this.folderId = '',
    // peers 是跨源聚合搜索里其它站源的同一部剧，用于一键切换播放源。
    this.peers = const [],
  }) : vipStatus = vip;
  final String id;
  final String source;
  final String sourceId;
  final String title;
  final String description;
  final String cover;
  final int episodes;
  final String category;
  final bool? vipStatus;
  bool get vip => vipStatus == true;
  final String heat;
  final String views;
  final String onlineDate;
  final List<String> tags;
  final String releaseStatus;

  /// 目录条目类型：video=视频卡（缺省）；folder=文件夹卡，点击以
  /// [folderId] 作为 category 参数再次请求目录实现下钻（层级不限）；
  /// action=动作卡，点击不走详情/播放，直接按 [sourceId] 里的动作
  /// JSON 打开对应界面（见 action_protocol.dart）。
  final String kind;
  final String folderId;
  bool get isFolder => kind == 'folder';
  bool get isAction => kind == 'action';
  bool get isTagFolder => isFolder && folderId.startsWith('tag:');
  final List<Drama> peers;
  String get releaseLabel => switch (releaseStatus) {
    'finished' || 'completed' => '已完结',
    'ongoing' => '连载中',
    _ => '状态未知',
  };

  factory Drama.fromJson(Map<String, dynamic> json) => Drama(
    id: json['id'] as String? ?? '',
    source: json['source'] as String? ?? 'hongguo',
    sourceId: json['sourceId'] as String? ?? '',
    title: json['title'] as String? ?? '短剧',
    description: json['description'] as String? ?? '',
    cover: json['cover'] as String? ?? json['pic'] as String? ?? '',
    episodes: intValue(json['episodes']),
    category: json['category'] as String? ?? '',
    vip: json['vip'] == true
        ? true
        : json['vip'] == false &&
              (json['source'] != 'huangdou' ||
                  intValue(json['metadataSchema']) >= 1)
        ? false
        : null,
    heat: json['heat']?.toString() ?? '',
    views: json['views']?.toString() ?? '',
    onlineDate: json['onlineDate'] as String? ?? '',
    tags: [
      for (final tag in json['tags'] as List? ?? const [])
        if (tag is String)
          tag
        else if (tag is Map)
          (tag['name']?.toString() ?? '')
        else
          '',
    ].where((tag) => tag.isNotEmpty).toList(),
    releaseStatus: json['releaseStatus'] as String? ?? '',
    kind: json['kind'] as String? ?? 'video',
    folderId: json['folderId'] as String? ?? '',
    peers: [
      for (final row in json['peers'] as List? ?? const [])
        Drama.fromJson(Map<String, dynamic>.from(row as Map)),
    ],
  );
  Map<String, dynamic> toJson() => {
    'metadataSchema': 1,
    'id': id,
    'source': source,
    'sourceId': sourceId,
    'title': title,
    'description': description,
    'cover': cover,
    'episodes': episodes,
    'category': category,
    'vip': vipStatus,
    'heat': heat,
    'views': views,
    'onlineDate': onlineDate,
    'tags': tags,
    'releaseStatus': releaseStatus,
    if (kind != 'video') 'kind': kind,
    if (folderId.isNotEmpty) 'folderId': folderId,
    if (peers.isNotEmpty) 'peers': [for (final peer in peers) peer.toJson()],
  };

  // withPeers 复制一份并替换跨源副本列表，用于切换播放源时把副本关系传递下去。
  Drama withPeers(List<Drama> value) => Drama(
    id: id,
    source: source,
    sourceId: sourceId,
    title: title,
    description: description,
    cover: cover,
    episodes: episodes,
    category: category,
    vip: vipStatus,
    heat: heat,
    views: views,
    onlineDate: onlineDate,
    tags: tags,
    releaseStatus: releaseStatus,
    kind: kind,
    folderId: folderId,
    peers: value,
  );

  Drama merge(Drama fresh) {
    if (id != fresh.id) return fresh;
    const genericCategories = {
      '短剧',
      '真人剧',
      '漫剧',
      'AI剧',
      'AI 剧',
      'AI短剧',
      'AI 短剧',
      'AI漫剧',
      'AI 漫剧',
    };
    return Drama(
      id: id,
      source: fresh.source.isEmpty ? source : fresh.source,
      sourceId: fresh.sourceId.isEmpty ? sourceId : fresh.sourceId,
      title: fresh.title.isEmpty || fresh.title == '短剧' ? title : fresh.title,
      description: fresh.description.isEmpty ? description : fresh.description,
      cover: fresh.cover.isEmpty ? cover : fresh.cover,
      episodes: fresh.episodes > 0 ? fresh.episodes : episodes,
      category:
          fresh.category.isEmpty ||
              genericCategories.contains(fresh.category) &&
                  category.isNotEmpty &&
                  !genericCategories.contains(category)
          ? category
          : fresh.category,
      vip: fresh.vipStatus ?? vipStatus,
      heat: fresh.heat.isEmpty ? heat : fresh.heat,
      views: fresh.views.isEmpty ? views : fresh.views,
      onlineDate: fresh.onlineDate.isEmpty ? onlineDate : fresh.onlineDate,
      tags: fresh.tags.isEmpty ? tags : fresh.tags,
      releaseStatus:
          fresh.releaseStatus.isEmpty || fresh.releaseStatus == 'unknown'
          ? releaseStatus
          : fresh.releaseStatus,
      // 文件夹性粘住（2026-11-27 问题 6）：kind 只许往“是文件
      // 夹”并，不许被不懂类型的合并方（详情/封面更新重建出的
      // kind='' 条目）冲掉——folderId 本来就是空才回退，kind
      // 此前无条件取新值，文件夹卡被合并一次就变回普通条目、
      // 点按改走详情，观感就是“文件夹点了没反应”。
      kind: isFolder || fresh.isFolder
          ? 'folder'
          : (fresh.kind.isEmpty ? kind : fresh.kind),
      folderId: fresh.folderId.isEmpty ? folderId : fresh.folderId,
      peers: fresh.peers.isEmpty ? peers : fresh.peers,
    );
  }
}

class Episode {
  Episode(this.raw, int fallback)
    : id = raw['id'] as String? ?? '',
      title = raw['title'] as String? ?? '第$fallback集',
      number = intValue(raw['currentEpisode']) > 0
          ? intValue(raw['currentEpisode'])
          : fallback,
      vip = raw['vip'] == true,
      vertical = raw['vertical'] as bool?;
  final Map<String, dynamic> raw;
  final String id;
  final String title;
  final int number;
  final bool vip;
  final bool? vertical;
}

/// 集标题是否像链接：源数据有时把播放地址塞进标题字段，直接显示会把
/// 直链暴露在界面上。标题里含链接 scheme 或以流媒体后缀结尾时只用集数标签。
bool episodeTitleLooksLikeUrl(String title) {
  final text = title.trim().toLowerCase();
  return text.contains('://') ||
      text.endsWith('.m3u8') ||
      text.endsWith('.mp4');
}

/// 显示用集标题：链接型标题回“第N集”，干净标题原样回。
String displayEpisodeTitle(String title, int number) =>
    episodeTitleLooksLikeUrl(title) ? '第$number集' : title;

/// 显示用集数行：干净标题拼“第N集 | 标题”，链接型、空、与标签相同的
/// 标题只显示集数标签，绝不把链接拼进显示文本。
String displayEpisodeLine(String? title, int number) {
  final label = '第$number集';
  final text = (title ?? '').trim();
  if (text.isEmpty || text == label || episodeTitleLooksLikeUrl(text)) {
    return label;
  }
  return '$label | $text';
}

/// heat 值是否像文件大小：jar 侧 heat 取 vod_remarks，TG 站把文件
/// 大小（如 1.4MB）塞进该字段，标“热度”会拿文件大小冒充热度。
bool heatLooksLikeFileSize(String heat) {
  final value = heat.trim();
  return RegExp(
    r'^\d+(\.\d+)?\s*(B|KB|MB|GB|TB)$',
    caseSensitive: false,
  ).hasMatch(value);
}

/// 显示用 heat 文案：文件大小形状的值标“大小”，其余标“热度”。
String heatDisplayText(String heat) =>
    heatLooksLikeFileSize(heat) ? '大小 $heat' : '热度 $heat';

class DetailTag {
  const DetailTag({required this.id, required this.name});
  final String id;
  final String name;
  factory DetailTag.fromJson(Object? value) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final name = map['name'] as String? ?? '';
      return DetailTag(id: map['id'] as String? ?? name, name: name);
    }
    final name = value?.toString() ?? '';
    return DetailTag(id: name, name: name);
  }
}

class MagnetLink {
  const MagnetLink({
    required this.name,
    required this.url,
    this.sizeLabel = '',
    this.quality = '',
    this.date = '',
    this.tags = const [],
  });
  final String name;
  final String url;
  final String sizeLabel;
  final String quality;
  final String date;
  final List<String> tags;

  factory MagnetLink.fromJson(Map<String, dynamic> json) => MagnetLink(
    name: json['name'] as String? ?? '',
    url: json['url'] as String? ?? '',
    sizeLabel: json['sizeLabel'] as String? ?? '',
    quality: json['quality'] as String? ?? '',
    date: json['date'] as String? ?? '',
    tags: [
      for (final row in json['tags'] as List? ?? const [])
        if (row != null && row.toString().isNotEmpty) row.toString(),
    ],
  );

  String get metaLabel => [
    if (sizeLabel.isNotEmpty) sizeLabel,
    if (quality.isNotEmpty) quality,
    for (final tag in tags) tag,
    if (date.length == 8)
      '${date.substring(0, 4)}-${date.substring(4, 6)}-${date.substring(6, 8)}',
  ].join(' · ');
}

class DramaDetail {
  DramaDetail(
    this.drama,
    this.episodes, {
    this.warning = '',
    this.backdrop = '',
    this.stills = const [],
    this.related = const [],
    this.tags = const [],
    this.magnets = const [],
    this.extraInfo = const [],
  });
  final Drama drama;
  final List<Episode> episodes;
  final String warning;
  final String backdrop;
  final List<String> stills;
  final List<Drama> related;
  final List<DetailTag> tags;
  final List<MagnetLink> magnets;

  /// 附加信息行（标签 → 值）：详情页信息卡的数据来源之一
  /// （在线源详情页自带的发行日期/长度/制作商等，源里有才带，
  /// 没有就是空——详情页不编造）。与 Drama 自带字段（onlineDate
  /// 等）重复时详情页优先用这里的。
  final List<(String, String)> extraInfo;

  DramaDetail withDrama(Drama value) => DramaDetail(
    value,
    episodes,
    warning: warning,
    backdrop: backdrop,
    stills: stills,
    related: related,
    tags: tags,
    magnets: magnets,
    extraInfo: extraInfo,
  );

  DramaDetail withEpisodes(List<Episode> value) => DramaDetail(
    drama,
    value,
    warning: warning,
    backdrop: backdrop,
    stills: stills,
    related: related,
    tags: tags,
    magnets: magnets,
    extraInfo: extraInfo,
  );

  DramaDetail withStills(List<String> value) => DramaDetail(
    drama,
    episodes,
    warning: warning,
    backdrop: backdrop,
    stills: value,
    related: related,
    tags: tags,
    magnets: magnets,
    extraInfo: extraInfo,
  );

  DramaDetail withExtraInfo(List<(String, String)> value) => DramaDetail(
    drama,
    episodes,
    warning: warning,
    backdrop: backdrop,
    stills: stills,
    related: related,
    tags: tags,
    magnets: magnets,
    extraInfo: value,
  );

  DramaDetail withTags(List<DetailTag> value) => DramaDetail(
    drama,
    episodes,
    warning: warning,
    backdrop: backdrop,
    stills: stills,
    related: related,
    tags: value,
    magnets: magnets,
    extraInfo: extraInfo,
  );

  DramaDetail withRelated(List<Drama> value) => DramaDetail(
    drama,
    episodes,
    warning: warning,
    backdrop: backdrop,
    stills: stills,
    related: value,
    tags: tags,
    magnets: magnets,
    extraInfo: extraInfo,
  );

  factory DramaDetail.fromJson(Map<String, dynamic> json) {
    final rows = json['chapters'] as List? ?? const [];
    final dramaJson = Map<String, dynamic>.from(json['drama'] as Map);
    Object? pick(String key) => json[key] ?? dramaJson[key];
    final stillsRaw = pick('stills');
    final relatedRaw = pick('related');
    final tagsRaw = pick('tags');
    final magnetsRaw = pick('magnets');
    return DramaDetail(
      Drama.fromJson(dramaJson),
      [
        for (var i = 0; i < rows.length; i++)
          Episode(Map<String, dynamic>.from(rows[i] as Map), i + 1),
      ],
      warning: json['warning'] as String? ?? '',
      backdrop: pick('backdrop') as String? ?? '',
      stills: [
        for (final row in stillsRaw as List? ?? const [])
          if (row != null && row.toString().isNotEmpty) row.toString(),
      ],
      related: [
        for (final row in relatedRaw as List? ?? const [])
          if (row is Map) Drama.fromJson(Map<String, dynamic>.from(row)),
      ],
      tags: [
        for (final row in tagsRaw as List? ?? const [])
          if (row != null) DetailTag.fromJson(row),
      ].where((tag) => tag.name.isNotEmpty).toList(),
      magnets: [
        for (final row in magnetsRaw as List? ?? const [])
          if (row is Map) MagnetLink.fromJson(Map<String, dynamic>.from(row)),
      ].where((magnet) => magnet.url.isNotEmpty).toList(),
    );
  }
}

class CatalogPage {
  CatalogPage(
    this.items, {
    this.hasMore = false,
    this.warning = '',
    this.page = 1,
    this.fresh = false,
    this.tags = const [],
    this.filters = const [],
  });
  final List<Drama> items;
  final bool hasMore;
  final String warning;
  final int page;
  final bool fresh;

  /// 分类响应携带的标签集（标签一等浏览维度），渲染为可点 chip，
  /// 点击以 tag 的 folderId（tag: 前缀）下钻。
  final List<CatalogTag> tags;

  /// 分类响应携带的筛选组（站源侧筛选面板，如主题/设定/背景），
  /// 渲染为筛选行，选项透传回站源作二次筛选。
  final List<CatalogFilterGroup> filters;
  factory CatalogPage.fromJson(Map<String, dynamic> json) => CatalogPage(
    [
      for (final row in json['items'] as List? ?? const [])
        Drama.fromJson(Map<String, dynamic>.from(row as Map)),
    ],
    hasMore: json['hasMore'] == true,
    warning: json['warning'] as String? ?? '',
    page: intValue(json['page']) > 0 ? intValue(json['page']) : 1,
    fresh: json['fresh'] == true,
    tags: [
      for (final row in json['tags'] as List? ?? const [])
        CatalogTag.fromJson(row),
    ].where((tag) => tag.id.isNotEmpty).toList(),
    filters: [
      for (final row in json['filters'] as List? ?? const [])
        if (row is Map)
          CatalogFilterGroup.fromJson(Map<String, dynamic>.from(row)),
    ].where((group) => group.key.isNotEmpty).toList(),
  );
}


/// 播放 DRM 信息（源侧随播放结果带回，字段口径与 FongMi 系
/// `drm:{key,type,header,forceKey}` 对齐）：
/// - [type]：许可证体系，如 com.widevine.alpha / org.w3.clearkey /
///   com.microsoft.playready（也认 widevine / clearkey 短名）。
/// - [key]：type 为服务器型时是许可证服务器地址（可带 `|头=值&...`
///   后缀形式的请求头，由归一化层拆开）；ClearKey 本地键时是
///   十六进制 `kid:key` 对或现成的 JWK JSON，归一化在
///   tvbox_player_bridge / live_drm 里完成，这里只存原样。
/// - [headers]：许可证请求头。
/// 只有 EXO 核（Media3）能消费这组信息；带 drm 的计划在播放器
/// 路由时强制走 EXO（见 player_screen 的 useNativeForPlan）。
class PlaybackDrm {
  const PlaybackDrm({
    required this.type,
    required this.key,
    this.headers = const {},
    this.forceKey = false,
  });

  final String type;
  final String key;
  final Map<String, String> headers;
  final bool forceKey;

  bool get isValid => type.isNotEmpty && key.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'type': type,
    'key': key,
    'headers': headers,
    'forceKey': forceKey,
  };

  /// 容忍两种形态：本站 toJson 的 {type,key,headers,forceKey} 与
  /// FongMi 系的 {key,type,header,forceKey}（header 可为 Map 或
  /// JSON 字符串）。字段不全返回 null，不硬造。
  static PlaybackDrm? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = value.map((k, v) => MapEntry(k.toString(), v));
    final type = (map['type'] ?? '').toString().trim();
    final key = (map['key'] ?? '').toString().trim();
    if (type.isEmpty || key.isEmpty) return null;
    final headers = <String, String>{};
    void absorb(Object? raw) {
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v != null) headers[k.toString()] = v.toString();
        });
      } else if (raw is String && raw.trim().startsWith('{')) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) absorb(decoded);
        } catch (_) {}
      }
    }

    absorb(map['headers']);
    absorb(map['header']);
    return PlaybackDrm(
      type: type,
      key: key,
      headers: headers,
      forceKey: map['forceKey'] == true,
    );
  }
}

class PlaybackPlan {
  const PlaybackPlan({
    required this.url,
    this.originalUrl = '',
    this.headers = const {},
    this.decryptionKey = '',
    this.quality = 0,
    this.qualities = const [],
    this.session = '',
    this.danmakuId = '',
    this.prefetchedBytes = 0,
    this.expiresAt = 0,
    this.routeIndex = 0,
    this.routeCount = 1,
    this.local = false,
    this.needsParse = false,
    this.forceMpv = false,
    this.drm,
    this.subs = const [],
  });
  final String url;
  final String originalUrl;
  final Map<String, String> headers;
  final String decryptionKey;
  final int quality;
  final List<int> qualities;
  final String session;
  final String danmakuId;
  final int prefetchedBytes;
  final int expiresAt;
  final int routeIndex;
  final int routeCount;
  final bool local;
  final bool needsParse;

  /// 强制走 mpv（media_kit）播放：光盘类（ISO/VIDEO_TS/BDMV）只有
  /// mpv 能播，原生/ijk 播不了；引擎在取流时置真，播放器路由时
  /// 认它（与 decryptionKey 的强制 mpv 语义一致）。复制方法必须透传。
  final bool forceMpv;

  /// DRM 信息；null 表示明流。带值时只有 EXO 核能播，
  /// 路由层据此强制走 EXO（decryptionKey 的强制 mpv 与此互斥，
  /// 两者同时出现时 decryptionKey 优先，保持既有口径）。
  final PlaybackDrm? drm;
  bool get hasDrm => drm?.isValid ?? false;
  /// 源在播放结果里给的外挂字幕列表（subs 字段透传，第 8 点）。
  final List<SubtitleSource> subs;
  bool get hasAlternative => session.isNotEmpty && routeIndex + 1 < routeCount;

  PlaybackPlan withDanmaku(String sessionValue, String danmakuIdValue) =>
      PlaybackPlan(
        url: url,
        originalUrl: originalUrl,
        headers: headers,
        decryptionKey: decryptionKey,
        quality: quality,
        qualities: qualities,
        session: sessionValue,
        danmakuId: danmakuIdValue,
        prefetchedBytes: prefetchedBytes,
        expiresAt: expiresAt,
        routeIndex: routeIndex,
        routeCount: routeCount,
        local: local,
        needsParse: needsParse,
        forceMpv: forceMpv,
        drm: drm,
        subs: subs,
      );

  PlaybackPlan withUrl(String value) => PlaybackPlan(
    url: value,
    originalUrl: originalUrl,
    headers: headers,
    decryptionKey: decryptionKey,
    quality: quality,
    qualities: qualities,
    session: session,
    danmakuId: danmakuId,
    prefetchedBytes: prefetchedBytes,
    expiresAt: expiresAt,
    routeIndex: routeIndex,
    routeCount: routeCount,
    local: local,
    needsParse: needsParse,
    forceMpv: forceMpv,
        drm: drm,
    subs: subs,
  );

  PlaybackPlan withHeaders(Map<String, String> value) => PlaybackPlan(
    url: url,
    originalUrl: originalUrl,
    headers: value,
    decryptionKey: decryptionKey,
    quality: quality,
    qualities: qualities,
    session: session,
    danmakuId: danmakuId,
    prefetchedBytes: prefetchedBytes,
    expiresAt: expiresAt,
    routeIndex: routeIndex,
    routeCount: routeCount,
    local: local,
    needsParse: needsParse,
    forceMpv: forceMpv,
        drm: drm,
    subs: subs,
  );

  PlaybackPlan withNeedsParse(bool value) => PlaybackPlan(
    url: url,
    originalUrl: originalUrl,
    headers: headers,
    decryptionKey: decryptionKey,
    quality: quality,
    qualities: qualities,
    session: session,
    danmakuId: danmakuId,
    prefetchedBytes: prefetchedBytes,
    expiresAt: expiresAt,
    routeIndex: routeIndex,
    routeCount: routeCount,
    local: local,
    needsParse: value,
    forceMpv: forceMpv,
        drm: drm,
    subs: subs,
  );
  factory PlaybackPlan.fromJson(Map<String, dynamic> json) => PlaybackPlan(
    url: json['url'] as String? ?? '',
    originalUrl: json['originalUrl'] as String? ?? '',
    local: json['local'] == true,
    headers: (json['headers'] as Map? ?? {}).map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    ),
    decryptionKey: json['decryptionKey'] as String? ?? '',
    quality: intValue(json['quality']),
    qualities: (json['qualities'] as List? ?? []).map(intValue).toSet().toList()
      ..sort((a, b) => b.compareTo(a)),
    session: json['session'] as String? ?? '',
    danmakuId: json['danmakuId'] as String? ?? '',
    prefetchedBytes: intValue(json['prefetchedBytes']),
    expiresAt: intValue(json['expiresAt']),
    routeIndex: intValue(json['routeIndex']),
    routeCount: intValue(json['routeCount']) > 0
        ? intValue(json['routeCount'])
        : 1,
    needsParse: json['parse'] == true || json['needsParse'] == true,
    drm: PlaybackDrm.fromJson(json['drm']),
    subs: parseSubtitleSources(json['subs']),
  );
}

class WatchEntry {
  WatchEntry({
    required this.drama,
    required this.episode,
    required this.position,
    required this.duration,
    required this.updatedAt,
  });
  final Drama drama;
  final int episode;
  final double position;
  final double duration;
  final DateTime updatedAt;
  bool get finished => duration > 1 && position >= duration - 1;
  Map<String, dynamic> toJson() => {
    'drama': drama.toJson(),
    'episode': episode,
    'position': position,
    'duration': duration,
    'updatedAt': updatedAt.toIso8601String(),
  };
  factory WatchEntry.fromJson(Map<String, dynamic> json) => WatchEntry(
    drama: Drama.fromJson(Map<String, dynamic>.from(json['drama'] as Map)),
    episode: intValue(json['episode']),
    position: (json['position'] as num?)?.toDouble() ?? 0,
    duration: (json['duration'] as num?)?.toDouble() ?? 0,
    updatedAt:
        DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime(2000),
  );
}

class DownloadJob {
  const DownloadJob({
    required this.id,
    required this.drama,
    required this.episode,
    required this.state,
    this.bytes = 0,
    this.total = 0,
    this.progress = 0,
    this.quality = 0,
    this.actualQuality = 0,
    this.error = '',
    this.created = 0,
    this.revision = 0,
    this.archived = false,
  });
  final int created;
  final int revision;
  final bool archived;
  final String id;
  final Drama drama;
  final Episode episode;
  final String state;
  final int bytes;
  final int total;
  final double progress;
  final int quality;
  final int actualQuality;
  final String error;
  bool get completed => state == 'completed';
  bool get active => state == 'queued' || state == 'downloading';
  bool get resumable => state == 'paused' || state == 'failed';
  String get stateLabel => switch (state) {
    'queued' => '等待下载',
    'downloading' => '正在下载',
    'paused' => '已暂停',
    'failed' => '下载失败',
    'completed' => '已下载',
    'removing' => '正在取消',
    _ => '等待更新',
  };
  factory DownloadJob.fromJson(Map<String, dynamic> value) => DownloadJob(
    id: value['id'] as String? ?? '',
    drama: Drama.fromJson(Map<String, dynamic>.from(value['drama'] as Map)),
    episode: Episode(
      Map<String, dynamic>.from(value['chapter'] as Map),
      intValue(value['index']),
    ),
    state: value['state'] as String? ?? 'failed',
    bytes: intValue(value['bytes']),
    total: intValue(value['total']),
    progress: ((value['progress'] as num?)?.toDouble() ?? 0).clamp(0, 1),
    quality: intValue(value['quality']),
    actualQuality: intValue(value['actualQuality']),
    error: value['error'] as String? ?? '',
    created: intValue(value['created']),
    revision: intValue(value['revision']),
    archived: value['archived'] == true,
  );
}

List<Map<String, dynamic>> readJsonList(String? value) {
  try {
    return (jsonDecode(value ?? '[]') as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  } catch (_) {
    return [];
  }
}
