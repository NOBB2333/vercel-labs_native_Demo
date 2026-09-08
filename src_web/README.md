# 前端说明

`src_web/` 是独立的 Vue 前端 workspace。目录名刻意与后端 `src/` 区分：看到 `src_web` 即表示 WebView 中运行的代码，看到根目录 `src` 即表示 Zig 本地代码。

## 采用的技术

- Vue 3 + `<script setup lang="ts">`
- Vue Router 4，使用 hash history，确保 `zero://app` 和离线资源下刷新路由可用
- Vite 8，`base` 固定为 `./`，避免生产资源生成根路径 URL
- 前端构建仅使用普通 Vite 配置，生成供 APP、目录包、归档和 portable bundle 共用的资源目录。
- Tailwind CSS 4，通过 `@tailwindcss/vite` 和 `@import "tailwindcss"` 接入
- Lucide Vue Next，交互按钮优先使用语义图标
- Oxlint + Oxfmt，均属于 Oxc 工具链，以 Rust 实现
- Vitest + Vue Test Utils + jsdom

模板没有安装 Naive UI。Naive UI 是第三方 Vue 组件库；Native SDK 的 Native UI 是另一套原生能力。不要因为名称相似而混用。需要 Naive UI 时应由具体业务项目显式添加，并确认它不会破坏现有桌面密度和主题。

## 目录约定

```text
src_web/
├── src/
│   ├── components/
│   │   ├── layout/             # 应用级侧栏、顶栏等布局组件
│   │   └── dashboard/          # 仪表盘展示组件
│   ├── features/dashboard/     # 仪表盘领域类型与后续业务逻辑
│   ├── router/                 # 路由定义
│   ├── services/native.ts      # 唯一 Native Bridge 适配层
│   ├── styles/main.css         # Tailwind 与全局基础样式
│   ├── test/                   # 测试环境初始化
│   ├── views/                  # 路由页面与页面测试
│   ├── App.vue
│   └── main.ts
├── index.html
├── vite.config.ts
└── tsconfig*.json
```

`DashboardView.vue` 保留原有仪表盘视觉样式并负责页面状态；侧栏、顶栏、任务、统计、运行时和活动区域已经拆为组件。新增复杂页面时按相同方式让 view 负责组装，让 feature 负责类型和业务状态，让 component 负责展示与局部交互。

## Bridge 规则

Vue 组件不得直接调用 `window.zero.invoke`。所有调用先在 `src_web/src/services/native.ts` 中声明输入/输出类型和函数，再由页面使用适配函数。这样浏览器预览、错误处理、模拟测试和命令改名都有单一入口。

新增命令时需要同时完成：

1. 在 Zig 后端实现并注册 handler。
2. 在根目录 `app.json` 声明同名命令和允许来源。
3. 在 `services/native.ts` 添加类型化函数。
4. 补充成功、Bridge 缺失和后端错误测试。

Bridge 输入始终按不可信数据处理。不要把任意文件路径、shell 命令或无限制 payload 直接传给本地后端。

## 路由与资源

路由使用 `createWebHashHistory()`，生产地址形如 `zero://app/index.html#/settings`。不要改成 HTML5 history，除非 Native SDK 的自定义 scheme 已明确实现所有回退行为。

Vite 的 `base: "./"` 不得移除。Native SDK 从本地 scheme 提供 `dist`，`/assets/...` 这类根路径可能跳出资源目录。原生图标来自根目录 `assets/`，不会作为 Web public directory 整体复制。

## 开发端口

开发 host、port 和 `strictPort` 从根目录 `config/native.json` 读取。Vite 直接读取它；`pnpm dev:config:sync` 将相同地址写入 `app.json`；Zig 构建再把 origin 注入 Bridge 运行时策略。配置流是：

```text
config/native.json -> Vite
                   -> app.json
                   -> Zig build_options.dev_origin
```

5173 只是模板默认值。永久改成其他端口时，从仓库根目录运行：

```sh
pnpm dev:port 5180
pnpm dev:config:check
```

端口范围必须是 1 到 65535。端口被其他进程占用时，Vite 会直接退出，不会自动尝试 5181。这是有意设计：自动递增会让实际页面来源与 Native Bridge 安全白名单不一致。请结束占用进程，或执行 `pnpm dev:port <另一个端口>` 后重新启动。

不要只传 `vite --port`，不要手改 `app.json` 中某一个 5173，也不要关闭 `strictPort`。如果手工编辑 `config/native.json`，必须接着运行 `pnpm dev:config:sync`。生产包从 `src_web/dist` 加载资源，与开发端口无关。

## 样式约定

Tailwind CSS 已完整启用，可用于新组件。当前仪表盘为了保留既有视觉效果，仍有一组页面级 CSS；修改时应维持安静、紧凑、适合重复操作的桌面工具风格。

- 不在卡片中再嵌套装饰卡片。
- 固定格式控件要有稳定尺寸，移动端不得发生文本遮挡。
- 熟悉动作优先使用 Lucide 图标并提供 `title` 或 `aria-label`。
- 不引入大面积单色渐变、装饰光球或营销页式 hero。
- 新的全局规则放在 `styles/main.css`，页面专用规则留在对应 view。

## 开发与测试

从仓库根目录打开 VS Code，并安装工作区推荐的 `Oxc`（`oxc.oxc-vscode`）、Vue 和 Zig 扩展。Oxfmt 与 Oxlint 从项目依赖自动发现，使用根目录的 `.oxfmtrc.json` 和 `.oxlintrc.json`。

保存 JS、TS、Vue 时运行 Oxlint 诊断，显式保存时执行安全自动修复，并由 Oxfmt 格式化整份文件。无法自动修复的问题会保留在 Problems 面板。Zig/ZON 使用 Zig 扩展调用 `zig fmt`；TypeScript 和 Vue 类型错误由各自语言服务提供，完整类型检查仍由 `pnpm frontend:check` 执行。本工作区关闭 ESLint，避免同一文件同时执行两套检查与修复。

`pnpm format` 同时覆盖 Oxfmt 支持的前端与配置文件、Zig 源码；`pnpm lint:fix` 可手动运行 Oxlint 安全修复。保存不会触发依赖安装、全项目测试或打包。

从项目根目录运行：

```sh
pnpm frontend:dev
pnpm frontend:test
pnpm frontend:check
```

前端检查包含严格 TypeScript、Vitest 和生产构建。测试采用以下分层，不机械复制一套源码目录：

- 单元测试和 Vue 组件测试与被测文件就近放置，命名为 `*.test.ts`，例如 `services/native.test.ts`、`views/DashboardView.test.ts`。这样移动或删除模块时，测试不会与实现分离。
- `src/test/` 只放 jsdom 初始化、全局 mock 和测试 helper，不集中存放各模块测试。
- 将来加入跨页面 E2E 时，在 `src_web/tests/e2e/` 集中放置，并使用用户流程命名；E2E 不属于任何单一源码模块。

Bridge 通过 mock 验证，组件应覆盖关键渲染、筛选、刷新和错误状态。不要为了覆盖率测试第三方实现细节。

## 构建模式

- `pnpm --dir src_web build`：输出 `dist/`，供 APP、目录包、归档和 portable bundle 使用。

`dist/` 是生成物，不提交 Git。portable 会在普通构建后将资源写入 bundle，运行时再从二进制写入版本化缓存并由 `zero://app` 提供；它不需要用户随程序携带前端目录。
