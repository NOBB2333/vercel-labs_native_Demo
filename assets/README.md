# 原生资源说明

`icon.png` 是默认应用图标。复制模板后可以替换它，但应继续保留相同路径，或同步修改 `app.json` 与 Zig 启动配置。

`WebView2Loader.dll` 是保留在仓库中的 x86-64 Windows loader 基准文件，不得删除。它用于模板完整性检查、人工审计和必要时恢复，不是 WebView2 Runtime，也不是 arm64 文件。

正式 Windows 构建从锁定版本的 `node_modules/@native-sdk/cli/third_party/webview2/<arch>/WebView2Loader.dll` 选择与目标 exe 一致的 loader：标准包复制到 exe 同目录，portable 将它嵌入单个 EXE。这样升级 Native SDK 或构建 arm64 时不会误用仓库中的 x64 基准文件。

运行以下命令检查仓库基准文件与 Native SDK 双架构文件：

```sh
pnpm windows:loader:check
```

更新或替换 DLL 时，应确认来源为 Microsoft WebView2 SDK、PE 架构正确，并在原生 Windows 环境重新构建和启动标准包及 portable。
