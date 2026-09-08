# AI 代理协作规范

本文件适用于整个仓库。AI 代理修改代码前必须先理解这里的边界，并优先遵循仓库已有模式。

## 项目事实

- 这是 Native SDK WebView 桌面模板，目标平台为 Windows、macOS、Linux。
- 前端位于 `src_web/`，技术栈为 Vue 3、TypeScript、Vue Router、Vite、Tailwind CSS。
- 本地后端位于 `src/`，语言为 Zig 0.16。
- 包管理器只使用 pnpm；Native SDK CLI 从根 `node_modules` 使用。
- `app.json` 是应用标识、版本、窗口、权限和 Web 引擎配置唯一来源；`config/native.json` 只维护开发地址与构建开关。
- 文档和项目新增注释优先使用中文；代码标识符保持英文。`build.zig`、`src/runner.zig` 中与 Native SDK 同步的上游注释可以保留英文，避免升级时产生无意义 diff。

## 查看代码

优先使用 CodeGraph 理解符号和影响范围：

```sh
codegraph status .
codegraph sync .
codegraph explore <主题>
codegraph node <符号或文件>
codegraph impact <符号>
```

CodeGraph 未安装、索引不支持某类配置，或只需精确文本搜索时，再使用 `rg`。完成结构性修改后运行 `codegraph sync .`。`.codegraph/` 是本机索引，禁止提交。

## 架构边界

- Vue 组件不得直接访问 `window.zero`，统一经过 `src_web/src/services/native.ts`。
- 新 Bridge 命令必须同步更新 `app.json`、`src/backend/root.zig`、feature handler、TypeScript adapter 和测试。
- `src/main.zig` 只负责组装，不写业务逻辑。
- `src/runner.zig` 是 Native SDK 基础设施，业务功能不得写入。
- portable 前端资源由 `scripts/embed-assets.mjs` 从 `src_web/dist` 编入 bundle，运行时释放逻辑留在 `src/main.zig`。
- 前端 view 负责页面编排，复用展示放 `components/`，业务类型和状态放 `features/`。
- 不提前加入数据库、状态库或 UI 框架；出现真实需求后再引入。

## 安全与跨平台

- Bridge payload 一律视为不可信输入，验证类型、大小、路径和范围。
- 权限与 origin 使用最小白名单，不暴露任意 shell 执行接口。
- 不提交本机绝对路径、证书、密钥、`.env` 或签名凭据。
- 不得删除 `assets/WebView2Loader.dll`；它是模板保留的 x64 基准文件，`pnpm check` 会验证其 PE 架构。
- Windows 正式包仍从锁定 Native SDK 选择目标架构 loader：标准包放在 exe 同目录，portable bundle 内嵌后在运行时预加载。基准文件不得冒充 arm64 loader。
- 平台相关改动必须说明并验证对应 Windows/macOS/Linux 行为。

## 前端规范

- 保留当前 dashboard 的紧凑桌面工具视觉，不将其简化成示例欢迎页。
- 路由保持 hash history，Vite `base` 保持 `./`。
- 熟悉操作使用 Lucide 图标并提供无障碍名称。
- Tailwind 可用于新代码；不要为了形式统一而大规模重写稳定的页面 CSS。
- 不使用卡片嵌套卡片、营销页 hero、装饰渐变球或会在小窗口溢出的固定宽度。
- Naive UI 与 Native SDK Native UI 不是同一技术；未有明确需求时不安装 Naive UI。
- 单元和组件测试与源码就近放置为 `*.test.ts`；`src_web/src/test/` 仅放共享环境，跨页面 E2E 才放 `src_web/tests/e2e/`。

## 开发配置与脚本

- 修改默认端口使用 `pnpm dev:port <port>`，手改 `config/native.json` 后运行 `pnpm dev:config:sync`。
- `strictPort` 必须保持 `true`；禁止只给 Vite 传 `--port` 或依赖自动递增端口。
- `.sh`/`.ps1` 是平台入口；MJS 负责跨平台结构化任务。端口、打包、改名、版本四项职责保持独立。
- `scripts/package.mjs` 是标准包、portable、Release staging 和可选更新配置的唯一实现，不在 shell、PowerShell 与 workflow 中复制文件布局逻辑。
- Windows loader 校验继续放在 `package.mjs`，不要为同一发布职责新增单独脚本。
- 本地只在当前宿主系统制作正式包；完整三平台发布由 GitHub Actions 原生 runner 矩阵完成。
- Release 只上传 `zig-out/release/<target>/` 中经过校验的文件，不直接上传 `zig-out/package/` 中间目录。
- Native SDK 0.10.1 的内置更新器仅支持 macOS `.app`；不得宣称 portable、Windows 或 Linux 已支持自动替换更新。
- 更新默认关闭。只有具体项目明确执行 `pnpm updates:configure` 后才允许在 `app.json` 写入其 GitHub 仓库和公钥；私钥只能放 GitHub Secret，禁止提交。

## 版本、依赖与生成物

- 更新版本使用 `pnpm version:set <SemVer>`，随后运行 `pnpm version:check`。
- `app.json.version` 是唯一手工版本源；根包、前端包和 Zig zon 的版本由脚本同步。前端直接读取 manifest，Zig 通过构建生成的 `app_manifest_zon` 模块读取配置，禁止再建立单字段版本文件或源码配置副本。
- 前端格式化和检查统一使用 Oxfmt、Oxlint，不并行启用 ESLint/Prettier；Zig 使用 `zig fmt`。VS Code 保存时的工具与 `pnpm format`、`pnpm lint:fix` 保持一致。
- 更新依赖后必须提交根 `pnpm-lock.yaml`，不得重新生成 npm lockfile。
- 不提交 `node_modules/`、`src_web/dist/`、`zig-out/`、`.zig-cache/` 或 `*.tsbuildinfo`。
- `pnpm-workspace.yaml` 的 `allowBuilds` 只允许审核过的依赖安装脚本。
- 改名使用 `pnpm rename -- "显示名称" "com.example.id" [machine-name]`。

## 完成标准

提交前至少运行：

```sh
pnpm check
```

涉及打包时还要在对应宿主系统运行：

```sh
zig build package
node scripts/package.mjs verify <windows|macos|linux> ReleaseFast
```

涉及 portable 时还要运行 `zig build portable` 和 `node scripts/package.mjs verify-portable <target> ReleaseFast`，并在目标宿主系统完成首次启动验证。修改 Release 产物规则后还要运行 `node scripts/package.mjs stage-release <target> ReleaseFast`，核对 SHA-256 清单与 manifest。

测试规模与风险匹配。前端交互补 Vitest/Vue Test Utils，Bridge 和后端逻辑补 Zig 测试；不要用仅构建成功替代行为验证。
