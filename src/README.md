# Zig 后端说明

根目录 `src/` 是本地后端和 Native SDK 组装层。它持有系统权限、本地资源与 Bridge handler；Web 前端只能通过 `app.json` 允许的命令访问这些能力。

## 目录职责

```text
src/
├── main.zig                       # 应用 composition root
├── runner.zig                     # Native SDK runner 集成代码
└── backend/
    ├── root.zig                   # Bridge 策略、handler 注册与服务生命周期
    └── features/
        └── health.zig             # app.health 示例能力
```

- `main.zig` 只组装应用、资源源、窗口和后端，不承载业务逻辑。
- `backend/root.zig` 是 Bridge 注册中心，命令策略和 handler 必须一一对应。
- `backend/features/` 按业务能力拆分，不按 controller/service/util 机械分层。
- `runner.zig` 视为 Native SDK 基础设施代码。除升级 SDK 所需的同步变更外，不把项目业务写进去。
- 名称、bundle id 和版本通过 `@import("app_manifest_zon")` 读取。`build.zig` 从 `app.json` 生成该模块到构建缓存，并核对派生的 Zig 包版本；`src/` 无需保存配置副本。
- 开发地址与构建开关统一维护在 `config/native.json`，由 `pnpm dev:config:sync` 将开发地址同步到 `app.json`。

`app.json` 统一维护应用名称、版本、窗口、Bridge 命令、安全权限、Web 引擎和 CEF 设置；`config/native.json` 只维护开发地址与构建开关。SDK 已支持的应用字段不在其他配置中重复保存。

## 新增本地能力

1. 在 `backend/features/<feature>.zig` 实现服务和 handler。
2. 为 payload 校验、正常输出和错误路径编写 Zig 测试。
3. 在 `backend/root.zig` 注册命令、context 和来源策略。
4. 在 `app.json` 声明相同命令、capability 和最小权限。
5. 在 `src_web/src/services/native.ts` 添加类型化适配函数和前端测试。

小功能先保持单文件。只有出现明确的数据模型、存储接口或多个 handler 时，再将 feature 扩展成目录。共享模块至少被两个 feature 使用后才放入 `backend/shared/`。

当前只有 4 个 Zig 文件：入口、SDK runner、Bridge 注册、health handler。保留这四个职责是为了新增业务时只需要关注 `backend/`。目录层级本身不会显著影响编译速度，不需要预建 repository、service、DTO 等空目录。

## Bridge 安全边界

- 来自 WebView 的所有 payload 都不可信，必须检查类型、长度、范围和路径。
- 命令只允许 `zero://app` 和开发地址等必要来源。
- 文件系统、网络、进程等能力必须同时收紧 `app.json` 权限。
- 不把任意 shell 字符串作为 Bridge API，也不把内部错误堆栈直接返回界面。
- 长耗时 I/O 不应阻塞界面线程，应使用 Native SDK 支持的异步或后台机制。

## 构建与测试

```sh
zig build test -Dplatform=null
zig build -Doptimize=ReleaseFast
zig build package
zig build portable
```

构建图默认从根目录 `node_modules/@native-sdk/cli` 读取 SDK，因此应先执行 `pnpm install --frozen-lockfile`。确需测试另一份 SDK checkout 时，可显式传 `-Dnative-sdk-path=/absolute/path`，但不要把个人机器路径提交进模板。

开发、前端构建和打包不再隐式执行依赖安装；首次使用或锁文件变化时安装即可。平台入口脚本仍负责首次准备。Zig 测试入口显式引用后端模块，确保 handler、权限拒绝和 manifest 策略一致性测试实际执行。

Windows 使用 WebView2，macOS 使用 WKWebView，Linux 使用 GTK 4 + WebKitGTK 6.0。平台代码必须在对应原生环境验证，不把交叉编译成功等同于应用可运行。

portable 构建复用普通 `src_web/dist`，由构建脚本将前端资源和可选的原生运行库编入 bundle，并在首次运行时写入版本化缓存。Windows 的 loader 同样从 bundle 释放并预加载。正式构建从锁定 Native SDK 读取目标架构 loader；`assets/WebView2Loader.dll` 是必须保留、由检查脚本验证的 x64 基准文件，不得删除，也不得用于替代 arm64 loader。
