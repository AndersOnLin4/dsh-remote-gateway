# 📱 DSH 远程网关 Android App（app/）

A 线产物：Flutter 编写的 Android 原生客户端，直连网关 REST/SSE 接口，出门在外也能**监控、回复、答题**，agent 提问**秒推通知**。

## 能力

| 模块 | 说明 |
|---|---|
| 登录 / 服务器管理 | 多服务器配置；密码与 Cookie 存 Android Keystore 加密区；重启免登录 |
| 监控 | DSH 状态灯、会话统计、最后活动、启动/重启/停止（二次确认）、完整控制台一键跳浏览器 |
| 会话 | 列表（标题/工作区/轮数/token/工作态高亮）+ 详情气泡对话（网关侧已过滤思考与工具细节） |
| 互动 | 直接回复；agent 选择题卡片点选提交（单选/多选） |
| 日志 | DSH 日志实时查看（8 秒刷新、自动滚动） |
| 推送 | 连接 `/gw/events`（SSE，自动重连），agent 提问 / 状态变化本地通知即时弹出 |

## 构建

前置：Flutter SDK（stable）+ Android SDK（platform-tools / platforms;android-36 / build-tools;36.0.0）+ JDK 17。

```bash
cd app
flutter pub get
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

> 本机开发环境记录：Flutter 3.47.0（G:\devtools\flutter）、JDK 17（G:\devtools\jdk-17.0.20+8）、
> Android SDK（G:\devtools\android-sdk）。依赖下载：Gradle 走阿里云镜像 + 代理，
> `dl.google.com / repo.maven.apache.org / maven.aliyun.com` 在 `gradle.properties` 里设了直连白名单
> （代理节点对 dl.google.com 不稳定）。换机器构建时按实际网络调整即可。
>
> **重要（本机）**：仓库父目录含中文（`Andersonlin4-design 远控二`），release AOT 编译器无法读取
> 中文路径。本机已建 ASCII 联接 `G:\dshgw` → 仓库目录，构建请在 `G:\dshgw\app` 下执行：
> `flutter build apk --release --split-per-abi`（产物同名映射回仓库 `app\build\...`）。
> 换到纯英文路径的机器则无需联接。仓库内已加 `android.overridePathCheck=true` 跳过 AGP 检查。

## 安装（侧载）

1. 把 `app-release.apk` 传到手机（微信文件传输/数据线均可）
2. 手机允许"安装未知来源应用"
3. 打开 App → 输入网关地址（局域网 `http://<电脑IP>:8080` 或 Tailscale `https://<电脑名>.<tailnet>.ts.net`）与密码 → 登录

## 版本与签名

- 当前 release 使用 debug 签名（个人侧载足够，同机构建可覆盖升级）
- 上架/分发升级需生成正式 keystore 并在 `android/app/build.gradle.kts` 配置 signingConfig

## 目录

```
lib/
├─ main.dart                  # 入口
├─ models.dart                # REST/SSE 数据结构
├─ api.dart                   # /gw/* 客户端（Cookie 会话）
├─ events.dart                # /gw/events SSE 流（自动重连）
├─ store.dart                 # 服务器列表 + Keystore 凭据
├─ notify.dart                # 本地通知
├─ helpers.dart               # 时间/数量格式化
└─ pages/
   ├─ startup_page.dart       # 启动路由
   ├─ login_page.dart         # 登录
   ├─ servers_page.dart       # 服务器管理
   ├─ home_page.dart          # 三 Tab 容器 + SSE 接线
   ├─ monitor_tab.dart        # 监控页
   ├─ sessions_tab.dart       # 会话列表
   ├─ log_tab.dart            # 日志页
   └─ session_detail_page.dart # 会话详情/答题/回复
```
