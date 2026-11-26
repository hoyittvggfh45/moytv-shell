# 魔蚁TV「空壳片库」剥离报告

分支：`strip-shell`（基线 main `efd0049` / v67），worktree `~/workspace/moyi_strip_shell_20261126`。
范围：只在自己工作树做、本地提交、不推仓、不构建。
口径：用户 2026-11-26 08:17/08:18 令——下一版片库不带任何内置站点资源、站点列表不再有「内置区」；听读、小程序保留。
（注：此路径原有一份 v66 .sql 导入修复报告，是主树提交带进来的；其正本在 `~/workspace/moyi_import_fix_20261125/` 一线，未丢失。）

## 一、剥离清单（逐项）

### 1. 内置 py 蜘蛛（片库）
- `assets/py_spiders/` 整目录删除：**130 个 py 文件**（127 条登记 + hghub/roshy/javtiful/youtube 等未登记文件）。
- `lib/builtin_py_sites.dart`：2497 行 → 99 行骨架。`BuiltinPySites.entries` 清空；注册/安装/卸载机器保留（空表自然无操作）。仅保留 `javmenuSiteId`/`avdbSiteId`/`memojavSiteId` 三个 id 常量——女优库跨站探针候选名单（`lib/adult_scrape_service.dart`）按 id 引用，站点本体已剥、候选查不到自动跳过。
- `pubspec.yaml` 删 `assets/py_spiders/` 声明。

### 2. jar 内置站登记与 jar 文件
- `lib/zakatv_builtin.dart`：862 行 → 68 行。`zakatvBuiltinSites` **137 条 → 只剩 1 条**（飞卢听书，见一.3 破例）；`oneBuiltinSites` 1 条 → 空；`missav30BuiltinSites` 本就空表。
- 删除 jar 文件 3 个：`assets/jars/youtube.jar`、`assets/jars/one.jar`、`assets/jars/missav30.jar`（missav30 登记早已摘空，本版连文件一并删）。
- 删除配置 JSON 2 个：`assets/youtube3.json`、`assets/jar_site_configs.json`。删除安全性已核：`registerBuiltinZakatv` 对 JSON 有 try/catch 兜底、`loadBuiltinJarConfigs` 加载失败返回空表；用户导入 jar 走学习配置兜底，不依赖这两个文件。
- `pubspec.yaml` 删对应 5 行声明（3 jar + 2 json）。
- 各 jar 的 asset/md5/id 常量在 Dart 侧保留作历史记录（测试有守卫断言）。

### 3. ⚠️ 破例保留：zakatv.jar 本体（飞卢听书宿主）
- `assets/jars/zakatv.jar` **原样保留**（md5 `029005c7ce017dc0a412f2d079a29dab`，与常量一致，测试守卫在）。
- 原因：jar 内 `go_tingshu` 飞卢听书（audioOnly）是听读源 `jar_tingshu` 的唯一实现，类 `com.github.catvod.spider.TingShu` 在该 jar 的 classes11.dex 里；该 jar 是 20 个 dex 的合并体（221+ 类与框架交织、含混淆合并类），无类级拆分条件、本环境无法验证拆分正确性。用户「听读保留」是明令且曾两次亲口保飞卢听书，故裁决：**jar 文件保留作听书宿主，片库登记只留 go_tingshu 一条，其余 136 条全删**——jar 其余内容对片库不可达。
- 这是全树唯一已知残留：jar 本体瘦身（拆出 TingShu 单类）需单独立项，不在本批。

### 4. Dart 侧站点登记（lib/models.dart）
- `SourceSite.knownValues`/`allValues`：83 条 → **3 条**（只剩原生功能三站，见第三节）。
- `duanjuValues` 12 条 → 空；`videoValues` 68 条 → 空（均保留空表占位 + 剥离注释，下游迭代不报错）。
- `defaultHiddenSiteIds` 只剩 5 个 idj_* 插件条目。
- dsd/guipian/ikanbot/a123/hanxiaoquan 等 const 对象保留（代码有引用），仅摘登记。

### 5. 插件清单（lib/plugin_manager.dart）
- `PluginManager.builtinPlugins()` 无条件返回空表（原：zakatv jar 插件 + one jar 插件 + 124 个 py 插件，共 126 条）。
- `ensureBuiltinPlugins()` 只剩 `JarImport.registerBuiltinZakatv()`（即飞卢听书登记）；`installBuiltinPlugin`/`uninstallBuiltinPlugin` 保留，清单为空自然失效。
- 树里原有的 `MOYI_EMPTY_SHELL` 构建变体与 `scripts/empty_shell_build.sh`：该脚本靠临时改 pubspec + 传 define 拼空壳；本树（空壳发布线种子）已在源码层剥净，不传 define 也恒为空壳行为，脚本不再需要。它在新仓运行会在自己的 grep 守卫处停下报错（fail-safe），本批未删、留发布组装时处置。

### 6. 站标与主页桥接
- `assets/site_icons/` 删 14 个片库图标，保留 4 个听读图标（akmh/hhlz/jmtt/mw）。
- `lib/site_builtin_icons.dart`：映射 22 键 → 4 键（akmh、hhlz、legado_7621_0、legado_8039_0）。
- `lib/site_homepages.dart`：`goSiteHomepages` 59 条 → 空；`pySiteHomepages` 148 条 → **23 条**（删 125 条片库桥接；23 条是听读阅读蜘蛛的主页桥接，属听读保留范围——初版曾整表清空，靠 site_homepages_test 抓出并已恢复）；`legadoSiteHomepages` 93 条原样。

### 7. 站点列表撤「内置区」
- `lib/source_picker_sheet.dart`：三区 → 两区。删 `zoneBuiltin` 常量与区签，区名改 [导入区, 插件区]，区号 0=导入、1=插件；空态文案两区化。
- `lib/home_screen.dart` 的选站分组：区列表改 [导入区, 插件区]；`__all__` 组落导入区；`_zoneIndexForSite` 改 plugin→1、其余→0（原生三站 origin=builtin 落导入区，代码注释已明说）。

### 8. 升级清理（旧内置登记）
- 内置登记本身不落盘（每次启动按登记表重建），停注册即清净。
- `lib/import_file_store.dart` 新增 `purgeBuiltinLeftovers()`：启动时删 `imported_spiders/` 下 `builtin_` 前缀的残留蜘蛛文件（旧版内置 py 落盘副本）；`lib/main.dart` 在 `ensureBuiltinPlugins` 后调用。已核用户导入文件名前缀是 `py_`/`js_`/`jsonlist_`，永不冲突。
- 档案（LocalProfile）里指向已剥离站的来源 id，恢复时按未知 id 滤除（既有过滤逻辑，app_build_test 已按新口径断言）；档案身份/权限位、收藏、历史、设置不动。
- 无害残留（只说明不处理）：JarBridge 对 zakatv.jar 的缓存拷贝（听书还要用）；`hiddenSites` 里对已剥离站 id 的残条目（查不到站自然失效）。

### 9. 片库空态
- 既有正牌空态是 `_noSourcesPanel()`（通用分支/Win7 窗口体在 `_librarySources` 为空时用它）。本批把它的「一个站源都没有」分支升级为空壳口径：文案改「这个版本不预置片库站点。从插件市场安装站点，或导入你自己的站点文件，片库就能用了。」+ 主行动「去插件市场」（跳 PluginMarketScreen）+ 次行动「导入站点」（走 showSiteImportFlow）；「全部被隐藏」分支文案与行为不变。原「请联系管理员」文案只在本树改（带站点版树未动）。
- 首启形态如实说明：全新安装时原生三站在来源里，首屏是红果戏剧首页（原生功能，有内容），不是空态；空态出现在档案无来源/全部来源不可用且走通用分支时。另注：手机窄屏且当前组为红果时首屏恒走戏剧首页分支、`byId('')` 回落红果组——基线 efd0049 既有行为（空档案探针实测：store 来源为空、首页仍出红果 feed），与剥离无关，本批未改，留主聊裁量。

### 剥离总量
- assets 删除 **149 个文件**（py 130 + jar 3 + json 2 + 图标 14）；pubspec 删 6 行声明。
- 登记删除：py 127 条、zakatv jar 136 条（留 1）、one 1 条、Dart 短剧 12 + 点播 68 条、插件清单 126 条、主页桥接 125+59 条、图标映射 18 键。
- 全量 diff 以 git 提交统计为准（约 190+ 文件、-71,000 行量级）。

## 二、保留清单核对（逐项验过）

- **听读**：小说/听书/音乐内置源全保留——`assets/novel_spiders`、`assets/audio_spiders`、`assets/legado_sources`、ContentRegistry、legado 主页桥接 93 条、阅读 py 主页桥接 23 条、听读图标 4 个全在；飞卢听书经 zakatv.jar 宿主保留（见一.3）。听读相关测试（lwlive 的 ASMR MOON 断言、feilu_tingshu、site_builtin_icons 听读键、zgj 音乐分区）全过。
- **小程序**：小程序区与 ant 小程序体系未动。连带后果一条：`HostMiniAppSourceProvider`（给小程序供宿主站点数据的桥）原本只读内置登记，剥离后它能列出的宿主站点为零（jar 侧空、py 侧只认运行时 originBuiltin 登记，而内置 py 注册已停）——小程序本体能开，但「用宿主站点取数」类小程序会拿到空清单。这是空壳口径的必然结果还是要给它接插件/导入站，由主聊裁量，本批未擅自扩围。
- **直播**：内置直播源、订阅、m3u 全未动（yuhuo_registry 的直播两条测试与基线同败、原因是基线既有的清单漂移，非剥离面）。
- **女优库**：库本体与页面未动；跨站探针候选名单里的已剥站点自动跳过（crosssite_probe/preview 测试已按替身夹具改写并通过）；`adult_scrape_service` 引用的三个 id 常量保留。
- **网盘、游戏区**：未动（kof_game_test 全过）。
- **用户数据**：已导入站、已装插件、收藏/历史/设置不删；升级清理只碰 `builtin_` 前缀残留文件与登记引用（见一.8）。

## 三、红果类原生条目的形态说明

`hongguo`（红果）、`hongguo_new`（红果新版）、`fanqie`（番茄）是 `SourceSite.knownValues` 里的**原生功能登记**：背后是原生代码写死的功能页（红果戏剧首页/番茄短剧），不是蜘蛛站点资源（无 py 文件、无 jar 类、无种子登记）。按任务口径保留登记本体；在站点列表里它们 origin=builtin，撤内置区后按两区口径**落导入区展示**（选站弹窗第一组「片库」即它们，见预览图 1）。单独标明：这是「原生功能以站点条目形态出现」的既有形态，剥离未动其功能。

## 四、测试对照（基线 efd0049 vs strip-shell）

方法：受影响集约 49 个测试文件按同分组在主检出与 strip 树各跑一遍逐名对照；预览类按仓内惯例单跑（toImage 后收尾挂起，按「出图 + 无失败断言」判过、超时杀掉取图）。日志在 `testlogs/`（base_*.log / strip_*.log，本目录不进提交）。

### 基线既有失败（strip 同名同败、平齐，不算新增）
- one_builtin/feilu/eroshort/xhs 的 137/140/145 计数漂移（基线批 2/3）。
- app_build「edition sources include DSD」：口味 define 差异（断言按 duanjushijie 口味写、本树 appSlug 恒 'moyi'）——strip 已改写为与口味无关的剥离断言并通过。
- catalog_categories「rankings are separate from categories…」：基线与 strip 同败。
- yuhuo_registry 直播两条（内置直播源清单锁定/绿色模式）：基线与 strip 同败，直播未动。
- interface_test 三条（refresh rotates / only Huangdou VIP / posters align）：基线单跑 600 秒超时未完且同名失败在先；strip 批跑同名三条。属既有失败，本批未动该文件。
- bottom_tab_nav「短剧首页 requestedTab 直达女优库页」：基线单跑同败。
- source_picker_wiring 两条 testWidgets 为 `skip: !allSourcesEnabled` 既有跳过，两边一致。
- site_homepages「桥接站标」在批跑时失败、单跑全过（AGENTS.md 在册的批量抖动项），基线同现象。

### 按新口径改写并通过的测试（逐条）
- builtin_py_sites_test：整篇重写为剥离守卫（entries 空、entryFor null、register 无操作、三探针 id 常量在、rootBundle 加载不到 4 个已删 py 文件）。
- plugin_manager_test：清单三条改空表口径（jar/py/jinguo 条目皆无）+ zakatv 只剩 go_tingshu 且 md5 不变。
- plugin_zip_bundle_test：按注册表组包只剩整包 jar、py 为零。
- plugin_empty_shell_test：两个变体下清单都为空；installBuiltinPlugin 两变体都拒绝（原仅空壳变体断言）。
- site_builtin_icons_test：映射 4 键/4 文件；计数改 0/1/101；查表改听读键（akmh 直查、legado jar 形态取 key 段），片库键回空；widget 站改 akmh。
- site_homepages_test：py 映射改「只剩听读 23 条且逐条验真」；Go 映射改空表；桥接查表改 akmh/legado 可解析、片库站回空；桥接站标 widget 改用 legado_8059_0（有桥接、无内置图标）。
- sources_test：果站 12 条改剥离断言（duanju/video 为空、knownValues 只剩原生三站、isKnown 全假）。
- app_build_test：三条改新口径（dsd/huangdou 不再已知、当前站回落红果；外来档案身份保留、已剥 id 恢复时滤除；DSD 档案同理）。
- catalog_categories_test：黄果组分页重试改用本地构造的同 id 替身组（被测逻辑与登记来源无关）。
- vod_zone_sources_test：黄果/黄豆 jar 登记、Roshy/Javtiful 两条改剥离断言（不在表、总数 1、md5 不变）。
- yuhuo_registry_test：点播/短剧三条改空表口径（前两条基线即因计数漂移失败）；直播两条未动。
- one_builtin_test / missav30_builtin_test / youtube_builtin_test / eroshor_builtin（eroshort）/ hstv_builtin_test / xhs_builtin_test / feilu_tingshu_builtin_test / builtin_jar_configs_test / zakatg_builtin_test：登记类断言改剥离守卫（不在表/文件不在/镜像已删）；jar 本体类断言（md5、dex 类表、指纹、未成年指向词注册面扫描）全部保留原样并通过。zakatg 的注册面扫描删去已删除的 jar_site_configs.json 一面，Dart 表与 Go 核表两面保留。
- chaoliu/javmenu/avdb_memojav/lwlive/zgj 注册类测试：逐站改剥离守卫，跨站探针名单与 key 不撞断言保留；zgj 的漫果改剥离、音乐分区三项不变；lwlive 的听书源 ASMR MOON 断言不变。
- crosssite_probe_test：探针 id 形态断言改字面量校验（py 候选 entryFor 为 null）；详情页 widget 改用本地构造的 originImport 替身站。
- crosssite_preview_test：探针登记改字面量构造（zakav01/ZakaJable 两条 jar 登记 + missav 替身站）；两张预览均出图。
- site_picker_zone_flip_test：整篇按两区重写（夹具原内置两组落导入区；区号 0 导入/1 插件；滑动/空态/搜索/点选意图全保留；导入区夹具并为 3 组防图卡挤出首屏；点选测试补手机视口）。
- site_picker_zone_preview_test / site_picker_thumb_preview_test：夹具改区（zoneBuiltin→zoneImport）、PNG 改名（site_picker_zone_import、site_thumb_grid_import）、插件区 index 2→1；thumb 导入区预览图数断言 7→10（实测渲染数）。
- site_picker_thumb_test、preview_json_import_test：夹具改区/改名，preview_json 5 张预览按名逐个验过全出图。
- mini_app_sources_test：HostMiniApp 组原从登记表取 jar 夹具，改：list 改剥离口径（jar 条目零、py 只剩夹具站、go_tingshu 不出现）；未知 key 组改 SITE_NOT_FOUND；jar 分发一条改「SITE_NOT_FOUND 且 jar 桥不被调用」；详情拆包/蜘蛛错误/并发/超时四条改走 py 路验同一共享逻辑；「无 imageBaseUrl 不改写」jar 半改剥离断言。

### 结果汇总
- 批 1（6 文件）：改写后全过（site_homepages 单跑 7 条全过）。
- 批 2（8 文件）：42 过 0 败。
- 批 3（8 文件）：全过（复跑 23 过 0 败）。
- 批 4 系列（app_build、catalog、kof、actress、adult_scrape、crosssite_probe、bottom_tab）：除基线同败的 rankings、bottom_tab 女优库直达外全过。
- 批 5（8 文件）：除 interface 三条基线同败外全过（idj/jar 系/json/miniapp/missav 合计 133 过）。
- 批 6 系列（library_workflow、one_play_fix、plugin_empty_shell、yuhuo、picker 系、sources）：除 yuhuo 直播两条基线同败外全过。
- 预览类：zone_flip 单跑 12 条全过；thumb 全过；zone/thumb/crosssite/preview_json 共 12 张预览按名逐个出图、无失败断言。
- analyze：**0 错 0 警告**（563 条 info 全为既有风格项；基线总量 828，剥离后随代码量下降）。

## 五、预览图

- `preview/site_picker_no_builtin.png`：剥离后的站点列表——只有「导入区（4）/插件区（1）」两个区签，无内置区；导入区含原生三站（红果/红果新版/番茄）与导入演示站。
- `preview/library_empty_state.png`：片库空态页（升级后的 _noSourcesPanel：暂无显示中的站源 + 新文案 + 去插件市场/导入站点）。注：该图在桌面宽度下渲染——手机窄屏首屏恒为红果戏剧首页（基线既有分支），空态面板出现在通用分支/电视/桌面/窗口模式，面板本身与宽度无关。
- 生成测试：`test/strip_shell_preview_test.dart`（随提交保留，与仓内其他预览测试同惯例：单跑、超时杀掉取图）。

## 六、遗留与建议（交主聊/发布总管）

1. zakatv.jar 本体瘦身（拆 TingShu 单类）单独立项后，听书宿主可换小包，jar 残留清零。
2. HostMiniAppSourceProvider 是否要改读插件/导入站（让小程序在空壳版也能用宿主站取数），属功能扩围，本批未动。
3. 空档案/全隐藏时手机首屏仍出红果戏剧首页（byId 空回落红果组）是基线既有行为；空壳版是否要改这条回落，留裁量。
4. `scripts/empty_shell_build.sh` 在新仓失效（grep 守卫会停下报错），发布组装时可删或改。
5. 本批只本地提交，未推仓、未构建；与发布组装清单（ext-open-fix 等）的合流由发布总管处理。
