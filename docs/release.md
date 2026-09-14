# 发布说明

## 版本规则

项目使用 SemVer，`app.json.version` 是唯一手工维护的版本来源。推荐直接执行：

```sh
pnpm version:set 1.2.3
pnpm version:check
```

`version:set` 会先解析并验证全部目标，再更新 `app.json.version` 和派生文件，保留 manifest 中其他配置；第二条命令用于确认没有漂移。同步范围如下：

| 文件                   | 版本用途                                            |
| ---------------------- | --------------------------------------------------- |
| `app.json`             | 唯一手工版本源、Release tag 校验、Native 平台包版本 |
| `package.json`         | 根 workspace 版本                                   |
| `src_web/package.json` | 前端 workspace 版本                                 |
| `build.zig.zon`        | Zig 包版本                                          |

Zig 通过构建缓存中的 `app_manifest_zon` 模块读取 manifest，不再生成需要提交的 Zig 版本文件。构建图直接校验 `build.zig.zon.version` 与 `app.json.version`，即使直接运行 `zig build` 也会拒绝未同步的 Zig 包版本。

如果因为合并分支只修改了 `app.json.version`，运行 `pnpm version:sync` 可重新生成其余版本字段，且不会重写 manifest。不要逐个修改派生文件，也不要使用 `pnpm version` 或 `npm version` 自动提交和打 tag；模板将“改版本”和“创建 Release”分成两个可审查步骤。

推荐发布顺序：

```sh
pnpm version:set 1.2.3
pnpm check
git add app.json package.json src_web/package.json build.zig.zon
git commit -m "release: v1.2.3"
git tag v1.2.3
git push origin main v1.2.3
```

tag 必须精确等于 `v${version}`。例如 `app.json.version` 为 `1.2.3-beta.1` 时，tag 必须为 `v1.2.3-beta.1`；不一致时 workflow 会在打包前失败。

开发端口不属于发布版本。5173 只是 `config/native.json` 的默认开发端口，修改方法见根 README 和 `src_web/README.md`；生产包从本地资源加载，不会监听或占用该端口。

## 产物矩阵

| 平台    | Native SDK 标准目录                            | 标准发布文件   | portable 文件                                            |
| ------- | ---------------------------------------------- | -------------- | -------------------------------------------------------- |
| Windows | `native-demo-<version>-windows-ReleaseFast/`   | 不生成额外归档 | `native-demo-<version>-windows-ReleaseFast-portable.exe` |
| macOS   | `native-demo-<version>-macos-ReleaseFast.app/` | `.dmg`         | `native-demo-<version>-macos-ReleaseFast-portable`       |
| Linux   | `native-demo-<version>-linux-ReleaseFast/`     | `.tar.gz`      | `native-demo-<version>-linux-ReleaseFast-portable`       |

标准目录是打包中间结果，不直接上传。`scripts/package.mjs stage-release` 会验证标准目录和 portable，并在 macOS/Linux 上额外验证标准归档，再将公开文件复制到 `zig-out/release/<target>/`，同时生成：

- `<base>-SHA256SUMS.txt`：供用户校验下载文件。
- `<base>-manifest.json`：记录类型、字节数与 SHA-256，供后续自动化读取。

Native SDK 0.10.1 的 Windows ZIP 步骤要求额外的 `zip` 命令，因此模板默认跳过它，不安装或绑定任何归档工具。Linux tar.gz 是可解压运行的分发归档，macOS DMG 是拖入 Applications 的安装磁盘映像；它们都不是 MSI、安装型 EXE、deb/rpm、AppImage 或 Flatpak，模板不会通过修改扩展名伪造这些格式。

## 本地打包

macOS 和 Linux：

```sh
./scripts/package.sh                      # 标准归档 + portable
./scripts/package.sh --standard-only      # 只构建标准归档
./scripts/package.sh --portable-only      # 只构建 portable
```

Windows PowerShell：

```powershell
.\scripts\package.ps1                    # 标准目录包 + portable EXE
.\scripts\package.ps1 -Mode Standard     # 只构建标准目录包
.\scripts\package.ps1 -Mode Portable     # 只构建 portable EXE
```

默认入口会执行冻结安装、全套检查、当前平台 ReleaseFast 构建、产物验证和 Release staging。也可以使用底层命令：

```sh
zig build package portable -Dpackage-target=macos
node scripts/package.mjs stage-release macos ReleaseFast
```

正式发布包只能在对应宿主系统构建。macOS 无法可靠生成 Windows/Linux 的最终 WebView 包，反向同理；完整三平台构建由 GitHub Actions 原生 runner 矩阵负责，而不是把交叉编译结果当成已验证发布物。

## portable 的准确含义

portable 表示“用户只下载、复制和启动一个可执行文件”，不表示完全静态，也不表示运行时只有一个 OS 进程。构建时 `src_web/dist` 和必要原生 loader 被编入二进制，首次启动后释放到版本化用户缓存。

- Windows：单个 EXE 内含目标架构的 `WebView2Loader.dll`，运行时释放并预加载；系统仍须安装 Microsoft Edge WebView2 Runtime。
- macOS：单个 ad-hoc 签名的裸 Mach-O 使用系统 WKWebView。它没有 `.app` 的图标、权限声明、Gatekeeper 分发体验，也不能使用 Native SDK 的 `.app` 更新器。
- Linux：单个 ELF 使用系统 GTK 4 与 WebKitGTK 6.0，不能宣称为无动态依赖的全静态文件。

portable 当前只适用于 `web_engine: "system"`。CEF/Chromium 带有大型 framework/runtime 目录，不走单文件路径。

portable 校验需要本次构建的 `src_web/dist`，会逐个核对资源路径和完整内容确实存在于可执行文件中，防止旧 bundle 被误当作新版本发布。资源 bundle 每次在 Vite 构建后重新生成，后续 Zig 编译仍按内容使用缓存。

## GitHub Release

先确保主分支检查通过，再创建与版本一致的 tag：

```sh
git tag v1.2.3
git push origin v1.2.3
```

一次 tag 会触发 `.github/workflows/release.yml`：

1. 校验 tag 与 `app.json.version`。
2. 在 Windows、macOS、Linux 原生 runner 上并行检查和构建。
3. Windows 生成标准目录包和 portable EXE；macOS/Linux 生成标准归档和 portable。
4. 通过同一个 `package.mjs` 规则验证并整理发布文件。
5. 上传三平台文件、SHA-256 清单和 artifact manifest，最后创建 GitHub Release。

workflow 顶层只有只读权限，仅最终 `release` job 拥有 `contents: write`。这样构建 job 不需要仓库写权限。

## 可选的 GitHub Release 更新

模板默认没有 `app.json.updates`，因此不会关联模板仓库，也不会发起更新请求。自动更新必须知道真实下载源，这种项目级绑定只能在复制模板并创建自己的仓库后启用。

Native SDK 0.10.1 的内置更新能力有明确边界：

- 仅支持 macOS 系统 WKWebView host。
- 仅从打包后的 `.app` 检查并安装，portable 裸 Mach-O 会禁用更新配置。
- 更新包必须是包含唯一 `.app` 的专用 ZIP，不是 DMG。
- feed 必须使用 Ed25519 签名，并包含下载 URL、大小和 SHA-256。
- Windows 与 Linux 尚没有对应的 SDK 安装替换生命周期。

### 启用步骤

1. 在仓库外生成私钥；命令会在终端输出可公开的 Base64 公钥：

```sh
pnpm exec native update keygen --private-key ../native-update.key
```

2. 将真实仓库和公钥写入项目。最后一个参数控制启动时是否自动检查，默认 `false`，用户仍可从 macOS 应用菜单手动检查：

```sh
pnpm updates:configure -- owner/repository '<PUBLIC_KEY>' false
```

该命令生成的 feed 地址是：

```text
https://github.com/owner/repository/releases/latest/download/native-update.json
```

3. 把原始 32 字节私钥转换成 Base64，写入 GitHub Actions Secret `NATIVE_UPDATE_PRIVATE_KEY_BASE64`。不要提交私钥。

macOS/Linux：

```sh
base64 < ../native-update.key | tr -d '\n'
```

Windows PowerShell：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("..\native-update.key"))
```

4. 提交 `app.json` 的公开更新配置并正常推送版本 tag。macOS job 会额外生成 `<base>-update.zip`，使用 Secret 签出 `native-update.json`，并将两者放入同一个 Release。

workflow 会校验 `app.json` 中的 feed 是否属于当前 `GITHUB_REPOSITORY`。如果复制模板后忘记修改更新源，发布会失败，而不会把客户端指向旧仓库。

关闭更新并移除仓库关联：

```sh
pnpm updates:disable
```

### 架构限制

当前 workflow 只构建 `macos-latest` runner 的本机架构，feed 也只为该架构签名。若项目同时发布 Intel 与 Apple Silicon，需要分别定义构建矩阵和架构 feed；不要让一个架构下载另一个架构的更新。Native SDK 会校验 feed 中的 `macos-x86_64` 或 `macos-aarch64` 标识并拒绝不匹配更新。

## Windows WebView2Loader

Windows 的系统 WebView 模式包含两个不同依赖，不应混为一谈：

- `WebView2Loader.dll` 是随应用分发的小型加载器，应用通过它发现并调用 WebView2 Runtime。
- Microsoft Edge WebView2 Runtime 是用户机器上的浏览器运行时。携带 loader 不等于已经携带 Runtime。

当前模板的流向如下：

| 场景                 | loader 来源                                                 | 运行时位置                                   |
| -------------------- | ----------------------------------------------------------- | -------------------------------------------- |
| 标准 Windows 目录包  | `node_modules/@native-sdk/cli/third_party/webview2/<arch>/` | 与 `bin/<app>.exe` 同目录                    |
| portable Windows EXE | 同一 Native SDK 目标架构目录                                | 内嵌在 EXE，启动时释放到随机缓存目录并预加载 |
| 仓库基准文件         | `assets/WebView2Loader.dll`，固定为 x86-64                  | 不直接进入正式包，用于模板审计、对照和恢复   |

`assets/WebView2Loader.dll` 已恢复并列为必须保留资产。它不是 arm64 通用文件，也不应手工复制去覆盖 Native SDK 的目标架构选择。`pnpm windows:loader:check` 会同时检查仓库基准文件、Native SDK x64 loader 和 Native SDK arm64 loader 的 PE 头；`pnpm check` 已包含这项检查。Windows 标准包校验会比较 exe 与最终 DLL 的 PE 架构，并确认 DLL 字节与对应 SDK 输入一致；portable 校验会确认同一 SDK DLL 的完整字节确实存在于 EXE bundle 中。

升级 `@native-sdk/cli` 时，先运行冻结安装和 `pnpm windows:loader:check`，再在 Windows runner 上构建并启动两类产物。仓库基准文件与 SDK 文件不要求字节相同，它们可能来自不同的 Microsoft WebView2 SDK 版本；如果决定更新基准文件，应单独审查来源、架构和二进制 diff，不能顺手删除。

如果标准目录包中缺少 DLL，`node scripts/package.mjs verify windows ReleaseFast` 会失败。如果 portable 未能释放或预加载 loader，程序会返回 `PortableWebView2LoaderUnavailable`，而不是静默启动一个空窗口。

## 平台注意事项

Windows 首次发布必须在原生 Windows runner 上实际启动。macOS 上的文件存在性或交叉编译检查无法证明 WebView2 Runtime、DLL 搜索路径和 GUI 子系统都正确。最终用户机器仍须安装 WebView2 Runtime；微软当前通常随 Windows 10/11 和 Edge 提供它，但不能假定所有精简系统都存在。

Linux runner 安装 `libgtk-4-dev`、`libwebkitgtk-6.0-dev` 与 `pkg-config`。最终用户同样需要发行版提供兼容的 GTK/WebKitGTK 运行库；发布前应在声明支持的发行版做冷启动测试。

macOS 默认使用 ad-hoc 签名，适合本地验证。公开分发应接入 Developer ID 和 notarization；启用更新后，Developer ID 签名还能让更新器校验新旧 `.app` 的 Team ID 与 bundle id。Windows 公开分发同样应配置代码签名。模板不保存证书、密码、notary profile 或更新私钥。

## 发布前检查

- `pnpm check` 全部通过。
- 三个平台都能启动、加载静态资源并调用 `app.health`。
- 应用名称、bundle id、图标和版本正确。
- Windows 包中 DLL 架构与 exe 一致。
- portable 无需携带同目录资源文件，并能完成首次启动。
- `zig-out/release/<target>/` 只含预期发布文件，SHA-256 与 manifest 一致。
- macOS 签名和 notarization 状态符合分发渠道要求。
- 启用更新时，使用旧版本 `.app` 完成一次真实检查、下载、校验、替换和重启测试。
