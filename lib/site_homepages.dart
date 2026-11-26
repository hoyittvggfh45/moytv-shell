/// 站 id → 主页地址桥接：给没有 ext 主页的 py 站、Go 核站、阅读 JSON
/// 源补一个取站标的地址来源，[SiteIcon] 由此派生 favicon 候选。
///
/// 每个值都取自树内源文件原文，绝不编造：
/// - py 站：蜘蛛文件里的基址常量/首个站点地址（assets/py_spiders、
///   assets/novel_spiders），jinguo_jg 与 jinguo 共用 jinguo.py；
/// - Go 核站：Go 核 slot 注册的 HomeURL（native/core/seku），按 Dart
///   站的 slotId 连接；镜像槽位取的是实际供源 origin 的站标；
/// - 阅读 JSON 源：源文件自身的 bookSourceUrl。
/// 无主页可取的站（音频站、用户自己导入的站）不在表里，一律回落图案标。
/// 值全部归一为 origin（协议 + 主机 + 端口），favicon 派生只用它。
/// 测试逐条核对：py 值的主机名确在对应蜘蛛文件里、Go 值的主机名
/// 确在 Go 核源码里、JSON 值确与源文件 bookSourceUrl 同 origin。

/// py 蜘蛛站（含视频 81 + 阅读 23）的主页。
// 2026-11-26 空壳片库定版：本表原有 148 条，其中 125 条是片库
// 内置 py 站的主页桥接，已随登记一并删除；剩下 23 条是听读侧
// 阅读蜘蛛（assets/novel_spiders）的主页桥接，听读不在剥离范围，
// 原样保留。
const Map<String, String> pySiteHomepages = {
  '1000novel': 'https://1000novel.com',
  '55comics': 'https://www.55comics.com',
  '69story': 'https://69story.com',
  'aabook': 'https://aabook.net',
  'akmh': 'https://www.eemh.cc',
  'baozi': 'https://www.webmota.com',
  'buliang': 'https://bass-23023-bug.buliangxiaoshuowang2.cc',
  'canovel': 'https://canovel.com',
  'cheniyo': 'https://cheniyo.cfd',
  'csmanhua': 'https://csmanhua.cc',
  'h528': 'http://www.h528.com',
  'hhlz': 'https://www.hhby9.com',
  'ho5ho': 'https://www.ho5ho.com',
  'hwg4': 'http://zffrbqg6y.www.hwg4.club',
  'jywx2': 'http://1mx8i3.www.jywx2.quest',
  'kmh001': 'https://kmh001.com',
  'kxmanhua': 'https://kxmanhua.com',
  'manga18fx': 'https://manga18fx.com',
  'mhbl': 'https://xn--uns.mhbl.buzz',
  'modu18': 'https://api.modu18.vip',
  'nnhanman': 'https://nnhanman.xyz',
  'yinse': 'https://9p6j22--wv.yinse1xiaoshuo2.com',
  'ylxs': 'https://ylxs.net',
};


/// Go 核站（Dart 站 id → 槽位 HomeURL origin）。
const Map<String, String> goSiteHomepages = {};
// 2026-11-26 空壳片库定版：Go 核槽位站登记已全部剥离，本表清空。


/// 阅读 JSON 源（legado id → bookSourceUrl origin）。
const Map<String, String> legadoSiteHomepages = {
  'legado_1751_0': 'https://m.jjwxc.net',
  'legado_7621_0': 'https://manwa.me',
  'legado_7713_0': 'https://m.uaa.com',
  'legado_7740_0': 'https://ixdzs8.com',
  'legado_7813_0': 'https://www.mowan.lol',
  'legado_7895_0': 'https://api-bc.wtzw.com',
  'legado_7968_0': 'https://hd.huadudm.com',
  'legado_7974_0': 'https://www.sushujuan.org',
  'legado_7975_0': 'https://www.alicesw.com',
  'legado_7976_0': 'https://sudugu520.com',
  'legado_7978_0': 'https://baka3.cfd',
  'legado_7979_0': 'https://zuidazy.co',
  'legado_7981_0': 'https://m.dzrjk.com',
  'legado_7982_0': 'https://m.tkshuw.com',
  'legado_7985_0': 'https://m.qishu99.cc',
  'legado_7986_0': 'https://fanqienovel.com',
  'legado_7987_0': 'https://mmrgb.com',
  'legado_7988_0': 'https://m.juzhishuwu.net',
  'legado_7992_0': 'https://fanqienovel.com',
  'legado_8006_0': 'https://cyj.vv9v.cn',
  'legado_8007_0': 'https://zwtoacvqie3.hq777.icu',
  'legado_8008_0': 'https://l205.arj2ftl0.cc',
  'legado_8009_0': 'https://www.bqquge.org',
  'legado_8010_0': 'https://l205.arj2ftl0.cc',
  'legado_8011_0': 'https://ocean.shuqireader.com',
  'legado_8018_0': 'https://webapi.gongzicp.com',
  'legado_8019_0': 'https://www.alicesw.com%EF%BC%88%E8%87%AA%E7%BC%96+%E4%BF%AE%E5%A4%8D%E6%90%9C%E7%B4%A2%EF%BC%89',
  'legado_8020_0': 'https://www.deqitxt.com',
  'legado_8023_0': 'https://www.banshanren.com',
  'legado_8024_0': 'https://m.jhsssd.com',
  'legado_8025_0': 'https://www.qibuge.com',
  'legado_8027_0': 'https://www.shubenshu.com',
  'legado_8029_0': 'https://www.qbxs.net',
  'legado_8030_0': 'https://www.deqixss.com',
  'legado_8032_0': 'https://www.byqg.cc',
  'legado_8033_0': 'https://www.xiguashuwu2.com',
  'legado_8035_0': 'https://wap.shoujixs.net',
  'legado_8039_0': 'https://jmtt1.net',
  'legado_8042_0': 'https://misskon.us',
  'legado_8043_0': 'http://www.xsbook.org',
  'legado_8044_0': 'https://zh.virtualtaboo.live',
  'legado_8045_0': 'https://www.pili45.com',
  'legado_8046_0': 'http://www.tjsyjjzs.com',
  'legado_8048_0': 'https://www.twkan.cc',
  'legado_8049_0': 'https://www.10000api.net',
  'legado_8050_0': 'https://www.banshanren.com',
  'legado_8052_0': 'https://www.shuqi.com',
  'legado_8054_0': 'https://m.qidian.com',
  'legado_8055_0': 'https://book.washai.net',
  'legado_8056_0': 'https://xanimu.ws',
  'legado_8057_0': 'https://fb.omoo.tv',
  'legado_8058_0': 'https://book.washai.net',
  'legado_8059_0': 'https://www.978xs.com',
  'legado_8066_0': 'https://fb.omoo.tv',
  'legado_8073_0': 'https://m.bookmaopu.com',
  'legado_8075_0': 'https://www.pilishuwu.com',
  'legado_8077_0': 'https://www.shuqi.com',
  'legado_8078_0': 'https://www.esjzone.one',
  'legado_8079_0': 'https://klmanga.autos',
  'legado_8080_0': 'http://www.ijjxs.org',
  'legado_8081_0': 'https://www.uukan.org',
  'legado_8088_0': 'https://www.txt520.org',
  'legado_8089_0': 'https://www.bilibili.com',
  'legado_8097_0': 'https://jiuxiaozw.com',
  'legado_8099_0': 'https://www.netflixgc.com',
  'legado_8100_0': 'https://www.omofuns.com',
  'legado_8101_0': 'https://www.klxs123.com',
  'legado_8102_0': 'https://quickapi.biduwenxue.com',
  'legado_8103_0': 'https://tybook.taoyuewenhua.net',
  'legado_8104_0': 'https://goway.reader.yueyouxs.com',
  'legado_8108_0': 'https://spudnovel.com',
  'legado_8109_0': 'https://www.banzhu44444444.net',
  'legado_8113_0': 'https://trxs.cc',
  'legado_8114_0': 'https://www.alicesw.tw',
  'legado_8116_0': 'https://m.libahao2.com',
  'legado_8117_0': 'https://www.deqixss.com',
  'legado_8118_0': 'https://www.alicesw3.homes',
  'legado_8119_0': 'https://www.38ksw.com',
  'legado_8121_0': 'https://www.bilinovel.net',
  'legado_8124_0': 'https://conflux.de5.net',
  'legado_8127_0': 'https://m.3renwx.com',
  'legado_8130_0': 'https://www.bilixs.com',
  'legado_8133_0': 'https://yesx.cc',
  'legado_8137_0': 'https://m.zjrtqs.com',
  'legado_8138_0': 'https://m.maolin.cc',
  'legado_8139_0': 'http://www.quduwx.net',
  'legado_8140_0': 'https://ik8.net',
  'legado_8141_0': 'https://www.geged.org',
  'legado_8142_0': 'https://cxb-pro.cread.com',
  'legado_8145_0': 'http://www.qunxs.com',
  'legado_8158_0': 'http://www.92xs.info',
  'legado_8160_0': 'http://www.sjxs5.org',
  'legado_8162_0': 'https://m.or7.net',
};
