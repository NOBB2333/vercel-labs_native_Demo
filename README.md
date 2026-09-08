# Native Demo

一个可直接复制的 WebView 桌面应用模板。Vue 负责界面，Zig 负责可信本地能力，Native SDK 负责窗口、系统 WebView、JavaScript Bridge 与三平台打包。它适合用来替代同类 Tauri + Rust 项目的基础工程。

当前首页保留了完整的桌面控制台仪表盘，不是空白演示页；模板同时提供一个真实可调用的 `app.health` Bridge 命令，方便新项目从完整链路开始扩展。

## 技术栈

| 范围     | 技术                                                          |
| -------- | ------------------------------------------------------------- |
| 前端     | Vue 3、TypeScript、Vue Router、Vite 8、Tailwind CSS 4、Lucide |
| 前端质量 | Oxlint、Oxfmt、Vitest、Vue Test Utils                         |
| 本地后端 | Zig 0.16、Native SDK 0.10                                     |
| 工程     | pnpm workspace、GitHub Actions、CodeGraph                     |

这里没有安装 Naive UI。Naive UI 是 Vue 组件库，而 Native SDK 文档中的 Native UI 是原生界面能力，两者不是同一个项目。模板当前仪表盘使用 Vue 组件和自有样式；业务项目确实需要现成组件时，再决定是否加入 Naive UI。

## 环境要求

- Node.js 24 或更高版本，推荐读取 `.nvmrc`
- pnpm 11，版本固定在 `packageManager`
- Zig 0.16.0，版本固定在 `.zigversion`
- macOS 需要 Xcode Command Line Tools
- Windows 需要系统安装 WebView2 Runtime；项目还会随包携带 `WebView2Loader.dll`
- Linux 打包需要 GTK 4、WebKitGTK 6.0 和 `pkg-config`

Native SDK CLI 已作为根目录开发依赖固定为 `0.10.1`，不需要全局安装，也不依赖 Homebrew 的固定路径。

## 快速开始

macOS 或 Linux：

```sh
./scripts/dev.sh
```

Windows PowerShell：

```powershell
.\scripts\dev.ps1
```

也可以手动运行：

```sh
pnpm install --frozen-lockfile
pnpm dev
```

`pnpm dev` 会启动 Vite 热更新服务和 Native 桌面窗口。只看浏览器页面时使用 `pnpm frontend:dev`；此时 Bridge 会显示为 Browser preview。开发地址由 `config/native.json` 统一管理，模板默认是 `http://127.0.0.1:5173/`，5173 只是可修改的默认值，不是框架协议。

端口被占用时会直接报错，不会自动改成 5174。原因是 Native Bridge 使用严格的 origin 白名单，Vite 单方面换端口会让 WebView 地址、manifest 和 Zig 运行时策略失配。修改默认端口使用：

```sh
pnpm dev:port 5180
```

该命令会更新 `config/native.json`，并同步 `app.json` 的 Vite 地址、Bridge origins 与导航白名单。手工修改统一配置后运行 `pnpm dev:config:sync`；`pnpm dev:config:check` 会检查同步状态。不要只运行 `vite --port`，也不要把 `strictPort` 改为 `false`。生产包使用内置资源，不监听这个开发端口。完整规则见 [`src_web/README.md`](src_web/README.md#开发端口)。

## 常用命令

| 命令                          | 用途                                                 |
| ----------------------------- | ---------------------------------------------------- |
| `pnpm dev`                    | 启动前端热更新与本地窗口                             |
| `pnpm dev:port 5180`          | 修改并同步默认开发端口                               |
| `pnpm frontend:dev`           | 只启动浏览器前端                                     |
| `pnpm build`                  | 构建前端和 ReleaseFast Zig 二进制                    |
| `pnpm test`                   | 执行 Zig 后端测试                                    |
| `pnpm frontend:test`          | 执行前端单元与组件测试                               |
| `pnpm lint`                   | 使用 Oxlint 检查代码                                 |
| `pnpm format`                 | 使用 Oxfmt 和 zig fmt 格式化项目                     |
| `pnpm lint:fix`               | 使用 Oxlint 修复可自动修复的问题                     |
| `pnpm check`                  | 执行版本、配置、格式、前端、manifest 与 Zig 全套检查 |
| `pnpm package`                | 构建当前平台的标准归档与 portable 文件               |
| `pnpm package:standard`       | 只构建当前平台标准包                                 |
| `pnpm portable`               | 只构建当前平台 portable 可执行文件                   |
| `pnpm release:stage <target>` | 校验并整理指定平台待发布文件                         |
| `pnpm version:set 1.2.3`      | 修改并同步所有应用版本字段                           |
| `pnpm windows:loader:check`   | 校验仓库及 Native SDK 中的 Windows loader            |

## 目录结构

```text
native-demo/
├── src_web/                   # 前端：Vue、路由、组件、样式、测试
├── src/                       # 后端：Zig 入口、Bridge 与业务能力
├── assets/                    # 应用图标与保留的 x64 WebView2 loader 基准文件
├── scripts/                   # 开发、打包、改名、版本与产物校验
├── docs/                      # 架构和发布细节
├── app.json                   # 应用标识、唯一版本源、窗口、权限与 Web 引擎
├── config/native.json         # 开发地址与构建开关
├── build.zig                  # Native SDK/Zig 构建图
├── pnpm-workspace.yaml        # pnpm workspace 与安装脚本策略
└── AGENTS.md                  # AI 编码代理必须遵守的项目约定
```

前端细节见 [`src_web/README.md`](src_web/README.md)，后端细节见 [`src/README.md`](src/README.md)，完整模块关系见 [`docs/architecture.md`](docs/architecture.md)。

## 从模板创建项目

复制目录后执行：

```sh
pnpm rename -- "My Product" "com.example.my-product"
```

第三个参数可显式指定机器名：

```sh
pnpm rename -- "我的应用" "com.example.my-app" "my-app"
```

脚本会按字段更新 `app.json`、两个 `package.json`、网页标题和 `build.zig.zon` 的包名及 fingerprint。Zig 和 Vue 路由直接读取 manifest，无需替换源码；文档中的模板示例由项目按需维护。显示名支持中文和引号；机器名须以小写字母开头，且不能使用 Windows 保留文件名。完成后可按需把项目目录改成机器名，再运行 `pnpm check`。

## 版本与发布

`app.json.version` 是唯一手工维护的应用版本来源。正常修改直接使用 `version:set`，它已经包含同步步骤：

```sh
pnpm version:set 1.2.3
pnpm version:check
```

脚本会修改 `app.json.version`，同步根 `package.json`、`src_web/package.json` 与 `build.zig.zon`。前端和 Zig 都读取 manifest，应用名称和版本不再另外保存源码副本。如果只手工编辑了 `app.json.version`，再运行 `pnpm version:sync`；不要逐个修改派生字段，也不要用 `pnpm version` 自动打 tag。发布 tag 必须精确等于 `v` 加当前版本，例如版本 `1.2.3` 对应 `v1.2.3`。

几个文件中出现版本号，是因为 pnpm、Native SDK 和 Zig 读取各自的包元数据；除 `app.json.version` 外，其他应用版本字段都是派生输出。`app.json` 是 Native SDK 的应用清单，类似 Tauri 的应用配置，还负责窗口、权限、Bridge 和打包信息。根 `package.json` 的 `packageManager: "pnpm@11.22.0"` 指包管理工具版本，`dependencies` / `devDependencies` 指依赖版本，都与应用版本独立。

本地打包：

macOS / Linux：

```sh
./scripts/package.sh                      # 标准归档 + portable（默认）
./scripts/package.sh --standard-only      # 只生成标准归档
./scripts/package.sh --portable-only      # 只生成 portable
```

Windows PowerShell：

```powershell
.\scripts\package.ps1                    # 标准 ZIP + portable EXE（默认）
.\scripts\package.ps1 -Mode Standard     # 只生成标准 ZIP
.\scripts\package.ps1 -Mode Portable     # 只生成 portable EXE
```

本地脚本只构建当前宿主平台，因为原生 WebView、链接器与签名工具不能由另一个系统可靠替代。推送与 `app.json.version` 一致的 `vMAJOR.MINOR.PATCH` tag 后，Release workflow 会一次并行启动 Windows、macOS、Linux 原生 runner，构建标准归档和 `-portable` 单文件，并发布 SHA-256 清单。

Native SDK 0.10.1 的标准格式是 Windows ZIP、macOS DMG、Linux tar.gz；其中 DMG 是安装磁盘映像，ZIP/tar.gz 是分发归档，并非 MSI/EXE 安装向导或 AppImage。模板没有用改后缀的方式伪造安装器。需要企业安装器或应用商店包时，应在具体项目中引入对应平台工具并配置签名。

基于 GitHub Release 的自动更新已预留，但模板默认关闭且不关联当前仓库。Native SDK 0.10.1 的更新器仅支持打包后的 macOS `.app`；启用方法、密钥和架构限制见 [`docs/release.md`](docs/release.md)。

标准 Windows 目录包仍把 `WebView2Loader.dll` 放在 exe 同目录。portable Windows EXE 则嵌入架构匹配的 DLL，首次运行释放到临时缓存后预加载，因此下载和搬运时只有一个 EXE。`assets/WebView2Loader.dll` 已保留为 x64 基准与恢复文件，`pnpm check` 会阻止它再次被误删；正式产物使用锁定 Native SDK 中与目标架构匹配的 loader。这个 DLL 不能替代用户系统上的 WebView2 Runtime。详细来源、架构校验与升级规则见 [`docs/release.md`](docs/release.md#windows-webview2loader)。
