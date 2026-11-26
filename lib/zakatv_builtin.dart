import 'models.dart';

class ZakatvBuiltinSite {
  const ZakatvBuiltinSite(
    this.key,
    this.name,
    this.className,
    this.ext, {
    this.section = SourceSite.sectionVideo,
    this.audioOnly = false,
  });
  final String key;
  final String name;
  final String className;
  final String ext;
  final String section;
  final bool audioOnly;
}

const String zakatvJarAsset = 'assets/jars/zakatv.jar';
const String zakatvJarMd5 = '029005c7ce017dc0a412f2d079a29dab';
const String youtubeJarAsset = 'assets/jars/youtube.jar';
const String youtubeJarMd5 = 'd294ce251d3b2aa8528efff12cc4bf19';
const String youtubeConfigAsset = 'assets/youtube3.json';
const String youtubeSpiderClass = 'com.github.catvod.spider.YouTube';
const String zakatvJarId = 'zakatv';
const String oneJarAsset = 'assets/jars/one.jar';
const String oneJarMd5 = 'af504c50de9f88246da9b086b5893c42';
const String oneJarId = 'one';
const String missav30JarAsset = 'assets/jars/missav30.jar';
const String missav30JarMd5 = '15efee5d3f3f4b2433bd25bc16ccf139';
const String missav30JarId = 'missav30';

/// 一点播独立 jar 的内置站点：绝不能合进 zakatv.jar——保持独立加载器
/// 与独立插件条目。2026-11-19 换成新蜘蛛重写版（One-cli_34 的 4 个
/// 蜘蛛类编 dex，见 ~/workspace/one_update_20261119/REPORT.md）：走
/// 域名分发接口领域名（30 分钟缓存，失败重领重试），视频是 mp4 直链；
/// 新蜘蛛无 Auth、无 SelfCheck、无 META-INF/SIG，旧 jar 的拉闸与签
/// 名机制已随旧实现一并退役。
const List<ZakatvBuiltinSite> oneBuiltinSites = [];
// 2026-11-26 空壳片库定版：一点播（One）是片库站，登记剥离、
// assets/jars/one.jar 一并删除；注册函数加载不到 asset 会自动失败
// 返回，不影响启动。

/// MissAV v30 独立 jar 的内置站点：2026-11-19 从 zakatv.jar 挪过来，
/// 2026-11-22 用户令：MissAV 三个 jar 站（ZakaMissav / ZakaMissavOff /
/// missavt）全部摘除登记，唯一 MissAV 站改为内置 py（key missav）。
/// 本表留空：jar 文件原样内置在 assets/jars/missav30.jar（见
/// test/missav30_builtin_test.dart 的 jar 原样断言），里面代码一个
/// 字节不改，仅供以后恢复时复用；ZakaMirror 同日从 zakatvBuiltinSites
/// 摘除。
const List<ZakatvBuiltinSite> missav30BuiltinSites = [];
const List<ZakatvBuiltinSite> zakatvBuiltinSites = [
  // 2026-11-26 空壳片库定版：原 137 条片库 jar 站登记全部剥离
  // （assets/jar_site_configs.json、assets/youtube3.json 一并删除），
  // 本表只保留一条听书源——飞卢听书（go_tingshu，audioOnly，不进
  // 片库、只给听读区供数）：它的 TingShu 蜘蛛类在 zakatv.jar 的
  // 合并 dex 里，与框架类交织、无类级拆分条件，所以 zakatv.jar
  // 文件本体破例保留作它的宿主；除本条外该 jar 再无任何登记，
  // 片库侧不可达。jar 本体瘦身（只留 TingShu 的精简 jar）需单独立项。
  ZakatvBuiltinSite(
    'go_tingshu',
    '飞卢听书',
    'com.github.catvod.spider.TingShu',
    '{}',
    audioOnly: true,
  ),
];
