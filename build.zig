const std = @import("std");

const PlatformOption = enum {
    auto,
    null,
    macos,
    linux,
    windows,
};

const TraceOption = enum {
    off,
    events,
    runtime,
    all,
};

const WebEngineOption = enum {
    system,
    chromium,
};

const WebLayerOption = enum {
    auto,
    include,
    exclude,
};

const PackageTarget = enum {
    macos,
    windows,
    linux,
};

const NativeConfig = struct {
    devServer: struct {
        host: []const u8,
        port: u16,
        strictPort: bool,
    },
    build: struct {
        trace: TraceOption,
        debugOverlay: bool,
        automation: bool,
        jsBridge: bool,
        nativeSdkPath: []const u8,
    },
};

pub fn build(b: *std.Build) void {
    // 直接读取配置并复用 SDK 已有的 manifest 模块，不在 src/ 保存配置副本。
    const metadata = std.json.parseFromSliceLeaky(struct { name: []const u8, version: []const u8 }, b.allocator, @embedFile("app.json"), .{ .ignore_unknown_fields = true }) catch
        @panic("无法读取 app.json 应用名称和版本");
    if (!std.mem.eql(u8, metadata.version, @import("build.zig.zon").version))
        @panic("build.zig.zon 与 app.json 版本不一致，请运行 pnpm version:sync");
    const app_version = metadata.version;
    const app_exe_name = metadata.name;
    const manifest_mod = appManifestModule(b);
    const target = nativeSdkTarget(b);
    // 手动注册 optimize 选项，以区分未设置和显式设置：开发运行默认
    // 使用 Debug，而 `zig build package` 默认构建发布版本；显式传入
    // -Doptimize 或 --release 时，两种构建统一使用指定模式。
    const optimize_request = b.option(std.builtin.OptimizeMode, "optimize", "Prioritize performance, safety, or binary size");
    const optimize = optimizeMode(b, optimize_request, .Debug);
    const package_optimize = optimizeMode(b, optimize_request, .ReleaseFast);
    const platform_option = b.option(PlatformOption, "platform", "Desktop backend: auto, null, macos, linux, windows") orelse .auto;
    const native_config = nativeBuildConfig(b);
    const dev_origin = if (native_config.devServer.port == 80)
        b.fmt("http://{s}", .{native_config.devServer.host})
    else
        b.fmt("http://{s}:{d}", .{ native_config.devServer.host, native_config.devServer.port });
    const trace_option = b.option(TraceOption, "trace", "Trace output: off, events, runtime, all") orelse native_config.build.trace;
    const debug_overlay = b.option(bool, "debug-overlay", "Enable debug overlay output") orelse native_config.build.debugOverlay;
    const automation_enabled = b.option(bool, "automation", "Enable Native SDK automation artifacts") orelse native_config.build.automation;
    const js_bridge_enabled = b.option(bool, "js-bridge", "Enable optional JavaScript bridge stubs") orelse native_config.build.jsBridge;
    const web_engine_override = b.option(WebEngineOption, "web-engine", "Override app.zon web engine: system, chromium");
    const web_layer_override = b.option(WebLayerOption, "web-layer", "Override app.zon webview_layer: auto, include, exclude");
    const cef_dir_override = b.option([]const u8, "cef-dir", "Override CEF root directory for Chromium builds");
    const cef_auto_install_override = b.option(bool, "cef-auto-install", "Override app.zon CEF auto-install setting");
    const package_target = b.option(PackageTarget, "package-target", "Package target: macos, windows, linux") orelse switch (target.result.os.tag) {
        .windows => PackageTarget.windows,
        .linux => PackageTarget.linux,
        else => PackageTarget.macos,
    };
    const native_sdk_path = b.option([]const u8, "native-sdk-path", "Path to the Native SDK framework checkout") orelse native_config.build.nativeSdkPath;
    const package_optimize_name = @tagName(package_optimize);
    const selected_platform: PlatformOption = switch (platform_option) {
        .auto => if (target.result.os.tag == .macos) .macos else if (target.result.os.tag == .linux) .linux else if (target.result.os.tag == .windows) .windows else .null,
        else => platform_option,
    };
    if (selected_platform == .macos and target.result.os.tag != .macos) {
        @panic("-Dplatform=macos requires a macOS target");
    }
    if (selected_platform == .linux and target.result.os.tag != .linux) {
        @panic("-Dplatform=linux requires a Linux target");
    }
    if (selected_platform == .windows and target.result.os.tag != .windows) {
        @panic("-Dplatform=windows requires a Windows target");
    }
    const app_config = appManifestBuildConfig(b);
    const web_engine = web_engine_override orelse app_config.web_engine;
    const cef_dir = cef_dir_override orelse defaultCefDir(selected_platform, app_config.cef_dir);
    const cef_auto_install = cef_auto_install_override orelse app_config.cef_auto_install;
    const web_layer = resolveWebLayer(app_config, web_engine, web_layer_override);
    if (app_config.updates_enabled and selected_platform == .macos and web_engine == .chromium) {
        @panic("\nnative updates currently require the system macOS host; use web_engine = \"system\" or remove the updates block\n");
    }
    if (web_engine == .chromium and selected_platform != .macos) {
        @panic("-Dweb-engine=chromium currently requires -Dplatform=macos");
    }
    const native_sdk_mod = nativeSdkModule(b, target, optimize, native_sdk_path);
    const relational_migrations_source = if (app_config.relational_capability)
        sqliteMigrationsSource(b, native_sdk_path)
    else
        nativeSdkPath(b, native_sdk_path, "src/app_runner/no_migrations.zig");
    const options = b.addOptions();
    options.addOption([]const u8, "platform", switch (selected_platform) {
        .auto => unreachable,
        .null => "null",
        .macos => "macos",
        .linux => "linux",
        .windows => "windows",
    });
    options.addOption([]const u8, "trace", @tagName(trace_option));
    options.addOption([]const u8, "web_engine", @tagName(web_engine));
    options.addOption(bool, "debug_overlay", debug_overlay);
    options.addOption(bool, "automation", automation_enabled);
    options.addOption(bool, "js_bridge", js_bridge_enabled);
    options.addOption(bool, "web_layer", web_layer);
    options.addOption(bool, "portable", false);
    options.addOption([]const u8, "dev_origin", dev_origin);
    const options_mod = options.createModule();

    const runner_mod = localModule(b, target, optimize, "src/runner.zig");
    runner_mod.addImport("native_sdk", native_sdk_mod);
    runner_mod.addImport("build_options", options_mod);
    runner_mod.addImport("app_manifest_zon", manifest_mod);
    const migrations_mod = b.createModule(.{ .root_source_file = relational_migrations_source, .target = target, .optimize = optimize });
    migrations_mod.addImport("native_sdk", native_sdk_mod);
    runner_mod.addImport("relational_migrations", migrations_mod);

    const app_mod = localModule(b, target, optimize, "src/main.zig");
    app_mod.addImport("native_sdk", native_sdk_mod);
    app_mod.addImport("runner", runner_mod);
    app_mod.addImport("build_options", options_mod);
    app_mod.addImport("app_manifest_zon", manifest_mod);
    if (app_config.sqlite_capability) addSqliteEngine(b, app_mod, native_sdk_path);
    addWindowsIconResource(b, target, selected_platform, app_mod);
    addMacosInfoPlist(b, app_mod, target, app_config);
    const exe = b.addExecutable(.{
        .name = app_exe_name,
        .root_module = app_mod,
        // Zig 0.16.0 的自托管 x86_64 后端在长参数列表的 SysV C 调用约定
        // 上存在错误，会导致 Linux x86_64 的 Debug 开发运行在创建窗口时崩溃。
        // 这里强制使用 LLVM；Release 模式本来就使用 LLVM，因此只影响 Debug。
        .use_llvm = useLlvmWorkaround(target),
    });
    // Windows 发布版本使用 GUI 子系统，避免启动时短暂显示控制台；
    // Debug 保留控制台以便查看开发日志。重定向日志仍可在 GUI 程序中工作。
    if (target.result.os.tag == .windows and optimize != .Debug) {
        exe.subsystem = .windows;
    }
    addWindowsDpiManifest(b, target, exe, native_sdk_path);
    linkPlatform(b, target, app_mod, exe, selected_platform, web_engine, web_layer, native_sdk_path, cef_dir, cef_auto_install);
    b.installArtifact(exe);

    const frontend_install = b.addSystemCommand(&.{ "pnpm", "install", "--frozen-lockfile" });
    const frontend_install_step = b.step("frontend-install", "Install frontend dependencies");
    frontend_install_step.dependOn(&frontend_install.step);

    const frontend_build = b.addSystemCommand(&.{ "pnpm", "--dir", "src_web", "run", "build" });
    const frontend_step = b.step("frontend-build", "Build the frontend");
    frontend_step.dependOn(&frontend_build.step);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(&frontend_build.step);
    addCefRuntimeRunFiles(b, target, run, exe, web_engine, cef_dir);
    addWebView2RuntimeRunFiles(b, target, run, web_engine, web_layer, native_sdk_path);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run.step);

    const dev = b.addSystemCommand(&.{ "pnpm", "exec", "native", "dev", "--manifest", "app.json", "--binary" });
    dev.addFileArg(exe.getEmittedBin());
    addWebView2RuntimeRunFiles(b, target, dev, web_engine, web_layer, native_sdk_path);
    dev.step.dependOn(&exe.step);
    const dev_step = b.step("dev", "Run the frontend dev server and native shell");
    dev_step.dependOn(&dev.step);

    // `zig build package` 默认使用发布模式构建自己的可执行文件，
    // 避免开发循环默认的 Debug 模式影响正式产物。显式指定优化模式时，
    // 开发和打包角色使用同一个模式。
    const package_exe = if (package_optimize == optimize) exe else pkg: {
        const package_sdk_mod = nativeSdkModule(b, target, package_optimize, native_sdk_path);
        const package_runner_mod = localModule(b, target, package_optimize, "src/runner.zig");
        package_runner_mod.addImport("native_sdk", package_sdk_mod);
        package_runner_mod.addImport("build_options", options_mod);
        package_runner_mod.addImport("app_manifest_zon", manifest_mod);
        const package_migrations_mod = b.createModule(.{ .root_source_file = relational_migrations_source, .target = target, .optimize = package_optimize });
        package_migrations_mod.addImport("native_sdk", package_sdk_mod);
        package_runner_mod.addImport("relational_migrations", package_migrations_mod);
        const package_app_mod = localModule(b, target, package_optimize, "src/main.zig");
        package_app_mod.addImport("native_sdk", package_sdk_mod);
        package_app_mod.addImport("runner", package_runner_mod);
        package_app_mod.addImport("build_options", options_mod);
        package_app_mod.addImport("app_manifest_zon", manifest_mod);
        if (app_config.sqlite_capability) addSqliteEngine(b, package_app_mod, native_sdk_path);
        addWindowsIconResource(b, target, selected_platform, package_app_mod);
        addMacosInfoPlist(b, package_app_mod, target, app_config);
        const built = b.addExecutable(.{
            .name = app_exe_name,
            .root_module = package_app_mod,
            // 与上面的开发程序使用相同的 x86_64 LLVM 兼容处理。
            .use_llvm = useLlvmWorkaround(target),
        });
        // Windows 发布模式使用 GUI 子系统，Debug 模式保留控制台。
        if (target.result.os.tag == .windows and package_optimize != .Debug) {
            built.subsystem = .windows;
        }
        addWindowsDpiManifest(b, target, built, native_sdk_path);
        linkPlatform(b, target, package_app_mod, built, selected_platform, web_engine, web_layer, native_sdk_path, cef_dir, cef_auto_install);
        break :pkg built;
    };

    const package_output = b.fmt("zig-out/package/{s}-{s}-{s}-{s}{s}", .{ app_exe_name, app_version, @tagName(package_target), package_optimize_name, packageSuffix(package_target) });
    const clean_package = b.addSystemCommand(&.{ "node", "scripts/package.mjs", "prepare", @tagName(package_target), package_optimize_name });
    const package = b.addSystemCommand(&.{
        "pnpm",
        "exec",
        "native",
        "package",
        "--target",
        @tagName(package_target),
        "--manifest",
        "app.json",
        "--assets",
        "src_web/dist",
        "--optimize",
        package_optimize_name,
        "--output",
        package_output,
        // 同时生成可分发的单文件归档和中间应用目录。
        "--archive",
        "--binary",
    });
    // CLI 从框架根目录解析 SDK 自带的打包输入（包括 WebView2 loader）。
    // 显式传入同一个根目录，避免 PATH 中的 native 来自另一份 SDK。
    package.addFileArg(package_exe.getEmittedBin());
    package.addArgs(&.{ "--web-engine", @tagName(web_engine), "--cef-dir", cef_dir });
    // 传递已经解析出的 Web 层决定，而不是让 CLI 根据 app.zon 再次推断，
    // 避免命令行覆盖参数后出现可执行文件与打包配置不一致。
    package.addArgs(&.{ "--web-layer", if (web_layer) "include" else "exclude" });
    if (package_target == .macos) package.addArgs(&.{ "--signing", "adhoc" });
    if (cef_auto_install) package.addArg("--cef-auto-install");
    if (app_config.updates_enabled and package_target == .macos and b.graph.host.result.os.tag == .macos) package.addArg("--update-archive");
    package.step.dependOn(&package_exe.step);
    package.step.dependOn(&frontend_build.step);
    package.step.dependOn(&clean_package.step);
    const package_step = b.step("package", "Create a local package artifact");
    package_step.dependOn(&package.step);

    // Portable 复用普通 src_web/dist，将整个目录（以及可选的原生运行库）
    // 编成单一 bundle；普通 package 路径仍由上面的 frontend_build 驱动。
    const bundle_command = b.addSystemCommand(&.{"node"});
    bundle_command.addFileArg(b.path("scripts/embed-assets.mjs"));
    // dist 的文件名由前置 Vite 构建动态生成，目录参数不会跟踪其内容。
    // 每次重建轻量 bundle，让 Zig 按实际资源内容缓存后续编译。
    bundle_command.has_side_effects = true;
    bundle_command.addDirectoryArg(b.path("src_web/dist"));
    if (target.result.os.tag == .windows and web_engine == .system and web_layer) {
        bundle_command.addFileArg(nativeSdkPath(b, native_sdk_path, webView2LoaderSubPath(target)));
    } else {
        bundle_command.addArg("-");
    }
    if (b.build_root.handle.access(b.graph.io, "assets/icon.png", .{})) |_| {
        bundle_command.addFileArg(b.path("assets/icon.png"));
    } else |_| {}
    const bundle_output = bundle_command.addOutputFileArg("portable_bundle.bin");
    const bundle_source = bundle_command.addOutputFileArg("portable_bundle.zig");
    _ = bundle_output;
    bundle_command.step.dependOn(&frontend_build.step);
    const bundle_module = b.createModule(.{
        .root_source_file = bundle_source,
        .target = target,
        .optimize = package_optimize,
    });

    const portable_options = b.addOptions();
    portable_options.addOption([]const u8, "platform", switch (selected_platform) {
        .auto => unreachable,
        .null => "null",
        .macos => "macos",
        .linux => "linux",
        .windows => "windows",
    });
    portable_options.addOption([]const u8, "trace", @tagName(trace_option));
    portable_options.addOption([]const u8, "web_engine", @tagName(web_engine));
    portable_options.addOption(bool, "debug_overlay", debug_overlay);
    portable_options.addOption(bool, "automation", automation_enabled);
    portable_options.addOption(bool, "js_bridge", js_bridge_enabled);
    portable_options.addOption(bool, "web_layer", web_layer);
    portable_options.addOption(bool, "portable", true);
    portable_options.addOption([]const u8, "dev_origin", dev_origin);
    const portable_options_mod = portable_options.createModule();

    const portable_sdk_mod = nativeSdkModule(b, target, package_optimize, native_sdk_path);
    const portable_runner_mod = localModule(b, target, package_optimize, "src/runner.zig");
    portable_runner_mod.addImport("native_sdk", portable_sdk_mod);
    portable_runner_mod.addImport("build_options", portable_options_mod);
    portable_runner_mod.addImport("app_manifest_zon", manifest_mod);
    const portable_migrations_mod = b.createModule(.{ .root_source_file = relational_migrations_source, .target = target, .optimize = package_optimize });
    portable_migrations_mod.addImport("native_sdk", portable_sdk_mod);
    portable_runner_mod.addImport("relational_migrations", portable_migrations_mod);

    const portable_app_mod = localModule(b, target, package_optimize, "src/main.zig");
    portable_app_mod.addImport("native_sdk", portable_sdk_mod);
    portable_app_mod.addImport("runner", portable_runner_mod);
    portable_app_mod.addImport("build_options", portable_options_mod);
    portable_app_mod.addImport("app_manifest_zon", manifest_mod);
    portable_app_mod.addImport("portable_bundle", bundle_module);
    if (app_config.sqlite_capability) addSqliteEngine(b, portable_app_mod, native_sdk_path);
    addWindowsIconResource(b, target, selected_platform, portable_app_mod);
    addMacosInfoPlist(b, portable_app_mod, target, app_config);

    const portable_exe = b.addExecutable(.{
        .name = app_exe_name,
        .root_module = portable_app_mod,
        .use_llvm = useLlvmWorkaround(target),
    });
    if (target.result.os.tag == .windows and package_optimize != .Debug) {
        portable_exe.subsystem = .windows;
    }
    addWindowsDpiManifest(b, target, portable_exe, native_sdk_path);
    linkPlatform(b, target, portable_app_mod, portable_exe, selected_platform, web_engine, web_layer, native_sdk_path, cef_dir, cef_auto_install);
    portable_exe.step.dependOn(&bundle_command.step);

    const write_portable = b.addSystemCommand(&.{ "node", "scripts/package.mjs", "portable", @tagName(package_target), package_optimize_name });
    write_portable.addFileArg(portable_exe.getEmittedBin());
    const portable_step = b.step("portable", "Create one directly distributable executable");
    portable_step.dependOn(&write_portable.step);
    if (web_engine != .system or !web_layer or selected_platform == .null) {
        portable_step.dependOn(&b.addFail("portable requires a system WebView desktop build").step);
    }

    const tests = b.addTest(.{ .root_module = app_mod });
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}

// Zig 0.16.0's self-hosted x86_64 backend miscompiles the SysV C
// calling convention for long mixed int/pointer/double signatures
// (the platform hosts' view-create calls) and f32-heavy ones (the
// embed viewport ABI): stack-passed arguments arrive shifted, so a
// Debug x86_64 build crashes at the first platform call that passes
// strings on the stack. Force the LLVM backend on x86_64 until the
// upstream backend is fixed; Release modes already default to LLVM,
// so this only changes Debug builds.
/// 读取开发地址与 Native 构建默认值，确保所有入口使用同一份配置。
fn nativeBuildConfig(b: *std.Build) NativeConfig {
    const config = std.json.parseFromSliceLeaky(NativeConfig, b.allocator, @embedFile("config/native.json"), .{}) catch
        @panic("无法解析 config/native.json");
    if (!config.devServer.strictPort) @panic("config/native.json 的 devServer.strictPort 必须保持 true");
    if (config.devServer.port == 0) @panic("开发端口必须在 1 到 65535 之间");
    const host = config.devServer.host;
    if (!std.mem.eql(u8, host, "127.0.0.1") and !std.mem.eql(u8, host, "localhost") and !std.mem.eql(u8, host, "[::1]"))
        @panic("开发 host 必须为 127.0.0.1、localhost 或 [::1]");
    return config;
}

fn useLlvmWorkaround(target: std.Build.ResolvedTarget) ?bool {
    return if (target.result.cpu.arch == .x86_64) true else null;
}

/// Bare Mach-O dev executables have no bundle Info.plist. Embed launch
/// policy plus capture usage strings so LaunchServices starts accessory
/// apps without a transient Dock tile and macOS can present consent.
/// Packaged apps receive the richer external plist from the package command.
fn addMacosInfoPlist(b: *std.Build, app_mod: *std.Build.Module, target: std.Build.ResolvedTarget, config: AppManifestBuildConfig) void {
    if (target.result.os.tag != .macos) return;
    if (config.dock_visible and !config.microphone_permission and !config.system_audio_permission) return;

    const launch_policy = if (!config.dock_visible)
        "  <key>LSUIElement</key>\\n  <true/>\\n"
    else
        "";
    const microphone = if (config.microphone_permission)
        "  <key>NSMicrophoneUsageDescription</key>\\n  <string>This app captures microphone audio when you start recording.</string>\\n"
    else
        "";
    const system_audio = if (config.system_audio_permission)
        "  <key>NSAudioCaptureUsageDescription</key>\\n  <string>This app captures system audio when you start recording.</string>\\n" ++
            "  <key>NSScreenCaptureUsageDescription</key>\\n  <string>This app captures system audio when you start recording.</string>\\n"
    else
        "";
    const source = b.fmt(
        \\#define NATIVE_SDK_INFO_PLIST "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n" "<plist version=\"1.0\">\n<dict>\n{s}{s}{s}</dict>\n</plist>\n"
        \\__attribute__((used, section("__TEXT,__info_plist")))
        \\static const unsigned char native_sdk_info_plist[sizeof(NATIVE_SDK_INFO_PLIST) - 1] = NATIVE_SDK_INFO_PLIST;
        \\
    , .{ launch_policy, microphone, system_audio });
    const generated = b.addWriteFiles().add("native_sdk_macos_info_plist.c", source);
    app_mod.addCSourceFile(.{ .file = generated, .flags = &.{} });
}

// Resolve the optimize mode for one exe role (mirrors the Native SDK
// build graph): an explicit -Doptimize wins for every role, --release
// resolves through zig's release_mode, and only when neither was
// passed does the role keep its own default — Debug for the dev loop,
// ReleaseFast for the exe `zig build package` wraps.
fn optimizeMode(b: *std.Build, requested: ?std.builtin.OptimizeMode, default_mode: std.builtin.OptimizeMode) std.builtin.OptimizeMode {
    if (requested) |mode| return mode;
    return switch (b.release_mode) {
        .off => default_mode,
        .any, .fast => .ReleaseFast,
        .safe => .ReleaseSafe,
        .small => .ReleaseSmall,
    };
}

fn nativeSdkTarget(b: *std.Build) std.Build.ResolvedTarget {
    const target = b.standardTargetOptions(.{});
    if (target.result.os.tag != .macos) return target;

    if (b.sysroot == null) {
        b.sysroot = macosSdkPath(b) orelse b.sysroot;
    }

    var query = target.query;
    query.os_tag = .macos;
    query.os_version_min = .{ .semver = .{ .major = 11, .minor = 0, .patch = 0 } };
    return b.resolveTargetQuery(query);
}

fn macosSdkPath(b: *std.Build) ?[]const u8 {
    if (b.graph.environ_map.get("SDKROOT")) |sdkroot| {
        if (sdkroot.len > 0) return sdkroot;
    }

    const result = std.process.run(b.allocator, b.graph.io, .{
        .argv = &.{ "xcrun", "--sdk", "macosx", "--show-sdk-path" },
        .stdout_limit = .limited(4096),
        .stderr_limit = .limited(4096),
    }) catch return null;
    defer b.allocator.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0) {
        b.allocator.free(result.stdout);
        return null;
    }
    return std.mem.trimEnd(u8, result.stdout, "\r\n");
}

fn localModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, path: []const u8) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path(path),
        .target = target,
        .optimize = optimize,
    });
}

fn nativeSdkPath(b: *std.Build, native_sdk_path: []const u8, sub_path: []const u8) std.Build.LazyPath {
    return .{ .cwd_relative = b.pathJoin(&.{ native_sdk_path, sub_path }) };
}

/// Windows 高 DPI 清单必须嵌入每一条可执行文件构建路径，避免系统把
/// 96-DPI 的 WebView 位图放大到显示器缩放比例，导致界面文字发糊。
fn addWindowsDpiManifest(b: *std.Build, target: std.Build.ResolvedTarget, exe: *std.Build.Step.Compile, native_sdk_path: []const u8) void {
    if (target.result.os.tag != .windows) return;
    exe.win32_manifest = nativeSdkPath(b, native_sdk_path, "assets/native-sdk.manifest");
}

/// 将应用自己的多尺寸 ICO 嵌入 Windows 可执行文件，供任务栏和窗口
/// 标题栏使用；仅在打包目录生成 app-icon.ico 不会改变 exe 的资源图标。
fn addWindowsIconResource(b: *std.Build, target: std.Build.ResolvedTarget, platform: PlatformOption, app_mod: *std.Build.Module) void {
    if (target.result.os.tag != .windows or platform != .windows) return;
    app_mod.addWin32ResourceFile(.{ .file = b.path("assets/app.rc") });
}

fn nativeSdkModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, native_sdk_path: []const u8) *std.Build.Module {
    const geometry_mod = externalModule(b, target, optimize, native_sdk_path, "src/primitives/geometry/root.zig");
    const assets_mod = externalModule(b, target, optimize, native_sdk_path, "src/primitives/assets/root.zig");
    const app_dirs_mod = externalModule(b, target, optimize, native_sdk_path, "src/primitives/app_dirs/root.zig");
    const trace_mod = externalModule(b, target, optimize, native_sdk_path, "src/primitives/trace/root.zig");
    const app_manifest_mod = externalModule(b, target, optimize, native_sdk_path, "src/primitives/app_manifest/root.zig");
    const diagnostics_mod = externalModule(b, target, optimize, native_sdk_path, "src/primitives/diagnostics/root.zig");
    const platform_info_mod = externalModule(b, target, optimize, native_sdk_path, "src/primitives/platform_info/root.zig");
    const json_mod = externalModule(b, target, optimize, native_sdk_path, "src/primitives/json/root.zig");
    const canvas_mod = externalModule(b, target, optimize, native_sdk_path, "src/primitives/canvas/root.zig");
    canvas_mod.addImport("geometry", geometry_mod);
    canvas_mod.addImport("json", json_mod);
    const debug_mod = externalModule(b, target, optimize, native_sdk_path, "src/debug/root.zig");
    debug_mod.addImport("app_dirs", app_dirs_mod);
    debug_mod.addImport("trace", trace_mod);

    const native_sdk_mod = externalModule(b, target, optimize, native_sdk_path, "src/root.zig");
    native_sdk_mod.addIncludePath(nativeSdkPath(b, native_sdk_path, "third_party/sqlite"));
    native_sdk_mod.addImport("geometry", geometry_mod);
    native_sdk_mod.addImport("assets", assets_mod);
    native_sdk_mod.addImport("app_dirs", app_dirs_mod);
    native_sdk_mod.addImport("trace", trace_mod);
    native_sdk_mod.addImport("app_manifest", app_manifest_mod);
    native_sdk_mod.addImport("diagnostics", diagnostics_mod);
    native_sdk_mod.addImport("platform_info", platform_info_mod);
    native_sdk_mod.addImport("json", json_mod);
    native_sdk_mod.addImport("canvas", canvas_mod);
    return native_sdk_mod;
}

fn sqliteMigrationsSource(b: *std.Build, native_sdk_path: []const u8) std.Build.LazyPath {
    const generate = b.addSystemCommand(&.{"node"});
    generate.addFileArg(nativeSdkPath(b, native_sdk_path, "build/ts_run.mjs"));
    generate.addFileArg(nativeSdkPath(b, native_sdk_path, "packages/core/src/sqlite_cli.ts"));
    generate.addArg("--src");
    generate.addDirectoryArg(b.path("src"));
    generate.addArg("--zig-out");
    const migrations = generate.addOutputFileArg("migrations.zig");
    generate.addArgs(&.{ "--state", "src/schema/migrations.lock.json" });
    if (b.build_root.handle.access(b.graph.io, "src/schema/migrations.lock.json", .{})) |_| {
        generate.addFileInput(b.path("src/schema/migrations.lock.json"));
    } else |_| {}
    generate.addFileInput(nativeSdkPath(b, native_sdk_path, "packages/core/src/sqlite_codegen.ts"));
    generate.addFileInput(nativeSdkPath(b, native_sdk_path, "packages/core/src/sqlite_runtime_policy.ts"));
    addAppSqlDirInputs(b, generate, "src");
    return migrations;
}

fn addAppSqlDirInputs(b: *std.Build, run: *std.Build.Step.Run, src_path: []const u8) void {
    var dir = b.build_root.handle.openDir(b.graph.io, src_path, .{ .iterate = true }) catch return;
    defer dir.close(b.graph.io);
    var walker = dir.walk(b.allocator) catch return;
    defer walker.deinit();
    while (walker.next(b.graph.io) catch null) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".sql")) continue;
        run.addFileInput(b.path(b.fmt("{s}/{s}", .{ src_path, entry.path })));
    }
}

fn addSqliteEngine(b: *std.Build, app_mod: *std.Build.Module, native_sdk_path: []const u8) void {
    app_mod.addIncludePath(nativeSdkPath(b, native_sdk_path, "third_party/sqlite"));
    app_mod.addCSourceFile(.{
        .file = nativeSdkPath(b, native_sdk_path, "third_party/sqlite/sqlite3.c"),
        .flags = &.{ "-DSQLITE_THREADSAFE=2", "-DSQLITE_OMIT_LOAD_EXTENSION", "-DSQLITE_DQS=0", "-DSQLITE_ENABLE_FTS5", "-DSQLITE_ENABLE_JSON1", "-DSQLITE_ENABLE_UPDATE_HOOK", "-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1", "-DSQLITE_DEFAULT_MEMSTATUS=0" },
    });
    app_mod.link_libc = true;
}

fn externalModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, native_sdk_path: []const u8, path: []const u8) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = nativeSdkPath(b, native_sdk_path, path),
        .target = target,
        .optimize = optimize,
    });
}

fn linkPlatform(b: *std.Build, target: std.Build.ResolvedTarget, app_mod: *std.Build.Module, exe: *std.Build.Step.Compile, platform: PlatformOption, web_engine: WebEngineOption, web_layer: bool, native_sdk_path: []const u8, cef_dir: []const u8, cef_auto_install: bool) void {
    if (platform == .macos) {
        switch (web_engine) {
            .system => {
                const sdk_include = if (b.sysroot) |sysroot| b.fmt("-I{s}/usr/include", .{sysroot}) else "";
                const flags: []const []const u8 = if (b.sysroot) |sysroot| &.{ "-fobjc-arc", "-fno-sanitize=builtin", "-ObjC", "-mmacosx-version-min=11.0", "-isysroot", sysroot, sdk_include } else &.{ "-fobjc-arc", "-fno-sanitize=builtin", "-ObjC", "-mmacosx-version-min=11.0" };
                app_mod.addCSourceFile(.{ .file = nativeSdkPath(b, native_sdk_path, "src/platform/macos/appkit_host.m"), .flags = flags });
                app_mod.linkFramework("WebKit", .{});
            },
            .chromium => {
                const cef_check = addCefCheck(b, target, cef_dir);
                if (cef_auto_install) {
                    const cef_auto = b.addSystemCommand(&.{ "pnpm", "exec", "native", "cef", "install", "--dir", cef_dir });
                    cef_check.step.dependOn(&cef_auto.step);
                }
                exe.step.dependOn(&cef_check.step);
                const include_arg = b.fmt("-I{s}", .{cef_dir});
                const define_arg = b.fmt("-DNATIVE_SDK_CEF_DIR=\"{s}\"", .{cef_dir});
                // The SDK's usr/include must stay a system include dir (searched after zig's
                // bundled libc++/libc headers). A plain -I shadows libc++'s <string.h>/<math.h>
                // wrappers in ObjC++ and surfaces SDK nullability gaps as a diagnostic flood.
                const sdk_include = if (b.sysroot) |sysroot| b.fmt("-isystem{s}/usr/include", .{sysroot}) else "";
                const flags: []const []const u8 = if (b.sysroot) |sysroot| &.{ "-fobjc-arc", "-fno-sanitize=builtin", "-ObjC++", "-std=c++17", "-stdlib=libc++", "-mmacosx-version-min=11.0", "-isysroot", sysroot, sdk_include, include_arg, define_arg } else &.{ "-fobjc-arc", "-fno-sanitize=builtin", "-ObjC++", "-std=c++17", "-stdlib=libc++", "-mmacosx-version-min=11.0", include_arg, define_arg };
                app_mod.addCSourceFile(.{ .file = nativeSdkPath(b, native_sdk_path, "src/platform/macos/cef_host.mm"), .flags = flags });
                app_mod.addObjectFile(b.path(b.fmt("{s}/libcef_dll_wrapper/libcef_dll_wrapper.a", .{cef_dir})));
                app_mod.addFrameworkPath(b.path(b.fmt("{s}/Release", .{cef_dir})));
                app_mod.linkFramework("Chromium Embedded Framework", .{});
                app_mod.addRPath(.{ .cwd_relative = "@executable_path/Frameworks" });
            },
        }
        if (b.sysroot) |sysroot| {
            app_mod.addFrameworkPath(.{ .cwd_relative = b.pathJoin(&.{ sysroot, "System/Library/Frameworks" }) });
        }
        app_mod.linkFramework("AppKit", .{});
        app_mod.linkFramework("AVFoundation", .{});
        app_mod.linkFramework("CoreMedia", .{});
        app_mod.linkFramework("ScreenCaptureKit", .{ .weak = true });
        app_mod.linkFramework("CoreVideo", .{});
        app_mod.linkFramework("MediaToolbox", .{});
        app_mod.linkFramework("Accelerate", .{});
        app_mod.linkFramework("Foundation", .{});
        app_mod.linkFramework("CoreText", .{});
        app_mod.linkFramework("UniformTypeIdentifiers", .{});
        app_mod.linkFramework("Security", .{});
        app_mod.linkFramework("Metal", .{});
        app_mod.linkFramework("QuartzCore", .{});
        app_mod.linkSystemLibrary("c", .{});
        if (web_engine == .chromium) app_mod.linkSystemLibrary("c++", .{});
    } else if (platform == .linux) {
        switch (web_engine) {
            .system => if (web_layer) {
                app_mod.addCSourceFile(.{ .file = nativeSdkPath(b, native_sdk_path, "src/platform/linux/gtk_host.c"), .flags = &.{} });
                app_mod.linkSystemLibrary("gtk4", .{});
                app_mod.linkSystemLibrary("webkitgtk-6.0", .{});
                app_mod.linkSystemLibrary("dl", .{});
            } else {
                // Native-only app (nothing in app.zon declares web use):
                // compile the GTK host without the embedded web layer.
                // The stub define excludes the layer outright — the host
                // honors it before probing for the WebKitGTK header, so
                // the layer stays out even on machines where the
                // development package is installed — libwebkitgtk is
                // neither linked nor required at runtime, and the
                // executable carries no WebKit reference at all. This
                // is the expected, configured state of every canvas
                // app on Linux, so the stub compile is deliberately
                // silent — no build note, no compiler diagnostic (the
                // host's seam comment explains why even an
                // informational pragma is dangerous); a stubbed host
                // teaches at runtime by reporting WebViewNotFound the
                // moment an app actually uses a WebView.
                app_mod.addCSourceFile(.{ .file = nativeSdkPath(b, native_sdk_path, "src/platform/linux/gtk_host.c"), .flags = &.{"-DNATIVE_SDK_ALLOW_WEBKITGTK_STUB"} });
                app_mod.linkSystemLibrary("gtk4", .{});
                app_mod.linkSystemLibrary("dl", .{});
            },
            .chromium => {
                const cef_check = addCefCheck(b, target, cef_dir);
                if (cef_auto_install) {
                    const cef_auto = b.addSystemCommand(&.{ "pnpm", "exec", "native", "cef", "install", "--dir", cef_dir });
                    cef_check.step.dependOn(&cef_auto.step);
                }
                exe.step.dependOn(&cef_check.step);
                const include_arg = b.fmt("-I{s}", .{cef_dir});
                const define_arg = b.fmt("-DNATIVE_SDK_CEF_DIR=\"{s}\"", .{cef_dir});
                app_mod.addCSourceFile(.{ .file = nativeSdkPath(b, native_sdk_path, "src/platform/linux/cef_host.cpp"), .flags = &.{ "-std=c++17", include_arg, define_arg } });
                app_mod.addObjectFile(b.path(b.fmt("{s}/libcef_dll_wrapper/libcef_dll_wrapper.a", .{cef_dir})));
                app_mod.addLibraryPath(b.path(b.fmt("{s}/Release", .{cef_dir})));
                app_mod.linkSystemLibrary("cef", .{});
                app_mod.addRPath(.{ .cwd_relative = "$ORIGIN" });
            },
        }
        app_mod.linkSystemLibrary("c", .{});
        if (web_engine == .chromium) app_mod.linkSystemLibrary("stdc++", .{});
    } else if (platform == .windows) {
        switch (web_engine) {
            .system => if (web_layer) {
                // Native SDK 内置的 WebView2 头文件启用 Windows WebView 层；
                // 缺少头文件时让编译直接失败，避免生成无法打开页面的程序。
                app_mod.addIncludePath(nativeSdkPath(b, native_sdk_path, "third_party/webview2/include"));
                app_mod.addCSourceFile(.{ .file = nativeSdkPath(b, native_sdk_path, "src/platform/windows/webview2_host.cpp"), .flags = &.{"-std=c++17"} });
                // 将目标架构的 WebView2Loader.dll 安装到 exe 同目录，
                // Windows host 通过它发现系统 WebView2 Runtime。
                const loader = b.addInstallBinFile(nativeSdkPath(b, native_sdk_path, webView2LoaderSubPath(target)), "WebView2Loader.dll");
                b.getInstallStep().dependOn(&loader.step);
            } else {
                // Native-only app (nothing in app.zon declares web use):
                // compile the host without the embedded-WebView layer.
                // The stub define excludes the layer outright — the host
                // honors it before probing for the WebView2 header, so
                // the layer stays out even on machines where the SDK
                // headers are reachable through the system include paths
                // — no WebView2Loader.dll is installed or path-wired,
                // and the executable carries no reference to it at all.
                // This is the expected, configured state of every
                // canvas app on Windows, so the stub compile is
                // deliberately silent — no build note, no compiler
                // diagnostic (the host's seam comment explains why
                // even an informational pragma is dangerous); a
                // stubbed host teaches at runtime by reporting
                // WebViewNotFound the moment an app actually uses a
                // WebView.
                app_mod.addCSourceFile(.{ .file = nativeSdkPath(b, native_sdk_path, "src/platform/windows/webview2_host.cpp"), .flags = &.{ "-std=c++17", "-DNATIVE_SDK_ALLOW_WEBVIEW2_STUB" } });
            },
            .chromium => {
                const cef_check = addCefCheck(b, target, cef_dir);
                if (cef_auto_install) {
                    const cef_auto = b.addSystemCommand(&.{ "pnpm", "exec", "native", "cef", "install", "--dir", cef_dir });
                    cef_check.step.dependOn(&cef_auto.step);
                }
                exe.step.dependOn(&cef_check.step);
                const include_arg = b.fmt("-I{s}", .{cef_dir});
                const define_arg = b.fmt("-DNATIVE_SDK_CEF_DIR=\"{s}\"", .{cef_dir});
                app_mod.addCSourceFile(.{ .file = nativeSdkPath(b, native_sdk_path, "src/platform/windows/cef_host.cpp"), .flags = &.{ "-std=c++17", include_arg, define_arg } });
                app_mod.addObjectFile(b.path(b.fmt("{s}/libcef_dll_wrapper/libcef_dll_wrapper.lib", .{cef_dir})));
                app_mod.addLibraryPath(b.path(b.fmt("{s}/Release", .{cef_dir})));
            },
        }
        app_mod.addCSourceFile(.{ .file = nativeSdkPath(b, native_sdk_path, "src/platform/windows/gpu_surface_renderer.cpp"), .flags = &.{"-std=c++17"} });
        app_mod.linkSystemLibrary("c", .{});
        app_mod.linkSystemLibrary("c++", .{});
        app_mod.linkSystemLibrary("user32", .{});
        app_mod.linkSystemLibrary("gdi32", .{});
        app_mod.linkSystemLibrary("d2d1", .{});
        app_mod.linkSystemLibrary("dwrite", .{});
        app_mod.linkSystemLibrary("imm32", .{});
        app_mod.linkSystemLibrary("comctl32", .{});
        app_mod.linkSystemLibrary("ole32", .{});
        app_mod.linkSystemLibrary("oleacc", .{});
        app_mod.linkSystemLibrary("shell32", .{});
        // TypeScript cores link ScriptC's host runtime, whose network-interface
        // helpers use GetAdaptersAddresses and Winsock address conversion.
        app_mod.linkSystemLibrary("iphlpapi", .{});
        app_mod.linkSystemLibrary("ws2_32", .{});
        // The audio backend: Media Foundation (session + source resolver
        // + streaming audio renderer) and WinHTTP (the cache fill).
        app_mod.linkSystemLibrary("mf", .{});
        app_mod.linkSystemLibrary("mfplat", .{});
        app_mod.linkSystemLibrary("winhttp", .{});
        if (web_engine == .chromium) app_mod.linkSystemLibrary("libcef", .{});
    }
}

/// 返回 Native SDK 中目标架构 WebView2Loader.dll 的相对路径。
fn webView2LoaderSubPath(target: std.Build.ResolvedTarget) []const u8 {
    return if (target.result.cpu.arch == .aarch64)
        "third_party/webview2/arm64/WebView2Loader.dll"
    else
        "third_party/webview2/x64/WebView2Loader.dll";
}

/// 开发命令直接运行缓存中的 exe，旁边没有安装后的 loader；因此只在
/// Windows WebView 构建中把 SDK loader 目录加入 PATH，供 LoadLibrary 查找。
fn addWebView2RuntimeRunFiles(b: *std.Build, target: std.Build.ResolvedTarget, run: *std.Build.Step.Run, web_engine: WebEngineOption, web_layer: bool, native_sdk_path: []const u8) void {
    if (web_engine != .system) return;
    if (!web_layer) return;
    if (target.result.os.tag != .windows) return;
    const loader_dir = std.fs.path.dirname(webView2LoaderSubPath(target)).?;
    run.addPathDir(b.pathFromRoot(b.pathJoin(&.{ native_sdk_path, loader_dir })));
}

fn addCefRuntimeRunFiles(b: *std.Build, target: std.Build.ResolvedTarget, run: *std.Build.Step.Run, exe: *std.Build.Step.Compile, web_engine: WebEngineOption, cef_dir: []const u8) void {
    if (web_engine != .chromium) return;
    if (target.result.os.tag != .macos) return;
    const copy = b.addSystemCommand(&.{
        "sh", "-c",
        b.fmt(
            \\set -e
            \\exe="$0"
            \\exe_dir="$(dirname "$exe")"
            \\rm -rf "zig-out/Frameworks/Chromium Embedded Framework.framework" "zig-out/bin/Frameworks/Chromium Embedded Framework.framework" ".zig-cache/o/Frameworks/Chromium Embedded Framework.framework" &&
            \\mkdir -p "zig-out/Frameworks" "zig-out/bin/Frameworks" ".zig-cache/o/Frameworks" "$exe_dir" &&
            \\cp -R "{s}/Release/Chromium Embedded Framework.framework" "zig-out/Frameworks/" &&
            \\cp -R "{s}/Release/Chromium Embedded Framework.framework" "zig-out/bin/Frameworks/" &&
            \\cp -R "{s}/Release/Chromium Embedded Framework.framework" ".zig-cache/o/Frameworks/" &&
            \\cp "{s}/Release/Chromium Embedded Framework.framework/Libraries/libEGL.dylib" "$exe_dir/" &&
            \\cp "{s}/Release/Chromium Embedded Framework.framework/Libraries/libGLESv2.dylib" "$exe_dir/" &&
            \\cp "{s}/Release/Chromium Embedded Framework.framework/Libraries/libvk_swiftshader.dylib" "$exe_dir/" &&
            \\cp "{s}/Release/Chromium Embedded Framework.framework/Libraries/vk_swiftshader_icd.json" "$exe_dir/"
        , .{ cef_dir, cef_dir, cef_dir, cef_dir, cef_dir, cef_dir, cef_dir }),
    });
    copy.addFileArg(exe.getEmittedBin());
    run.step.dependOn(&copy.step);
}

fn addCefCheck(b: *std.Build, target: std.Build.ResolvedTarget, cef_dir: []const u8) *std.Build.Step.Run {
    const script = switch (target.result.os.tag) {
        .macos => b.fmt(
            \\test -f "{s}/include/cef_app.h" &&
            \\test -d "{s}/Release/Chromium Embedded Framework.framework" &&
            \\test -f "{s}/libcef_dll_wrapper/libcef_dll_wrapper.a" || {{
            \\  echo "missing CEF dependency for -Dweb-engine=chromium" >&2
            \\  echo "Expected:" >&2
            \\  echo "  {s}/include/cef_app.h" >&2
            \\  echo "  {s}/Release/Chromium Embedded Framework.framework" >&2
            \\  echo "  {s}/libcef_dll_wrapper/libcef_dll_wrapper.a" >&2
            \\  echo "Fix with: native cef install --dir {s}" >&2
            \\  echo "Or rerun with: -Dcef-auto-install=true" >&2
            \\  echo "Pass -Dcef-dir=/path/to/cef if your bundle lives elsewhere." >&2
            \\  exit 1
            \\}}
        , .{ cef_dir, cef_dir, cef_dir, cef_dir, cef_dir, cef_dir, cef_dir }),
        .linux => b.fmt(
            \\test -f "{s}/include/cef_app.h" &&
            \\test -f "{s}/Release/libcef.so" &&
            \\test -f "{s}/libcef_dll_wrapper/libcef_dll_wrapper.a" || {{
            \\  echo "missing CEF dependency for -Dweb-engine=chromium" >&2
            \\  echo "Fix with: native cef install --dir {s}" >&2
            \\  exit 1
            \\}}
        , .{ cef_dir, cef_dir, cef_dir, cef_dir }),
        .windows => b.fmt(
            \\test -f "{s}/include/cef_app.h" &&
            \\test -f "{s}/Release/libcef.dll" &&
            \\test -f "{s}/libcef_dll_wrapper/libcef_dll_wrapper.lib" || {{
            \\  echo "missing CEF dependency for -Dweb-engine=chromium" >&2
            \\  echo "Fix with: native cef install --dir {s}" >&2
            \\  exit 1
            \\}}
        , .{ cef_dir, cef_dir, cef_dir, cef_dir }),
        else => "echo unsupported CEF target >&2; exit 1",
    };
    return b.addSystemCommand(&.{ "sh", "-c", script });
}

fn packageSuffix(target: PackageTarget) []const u8 {
    return switch (target) {
        .macos => ".app",
        .windows, .linux => "",
    };
}

/// What this build graph reads out of app.zon: the web-engine/CEF
/// knobs and the web-layer inference inputs. An unreadable or
/// unparsable manifest falls back to the system engine WITH the web
/// layer kept — over-inclusion is a size cost, wrong exclusion is a
/// broken app.
const AppManifestBuildConfig = struct {
    web_engine: WebEngineOption = .system,
    cef_dir: []const u8 = "third_party/cef/macos",
    cef_auto_install: bool = false,
    webview_layer: WebLayerOption = .auto,
    dock_visible: bool = true,
    microphone_permission: bool = false,
    system_audio_permission: bool = false,
    sqlite_capability: bool = false,
    relational_capability: bool = false,
    updates_enabled: bool = false,
    /// The first web declaration found (for teaching messages), or
    /// null when app.zon declares no web use. `web_engine = "system"`
    /// alone is NOT web intent — it is the default in many canvas
    /// manifests.
    web_declaration: ?[]const u8 = null,
};

/// The lenient app.zon shape parsed for inference: only the fields
/// that decide the web layer and the web engine; everything else is
/// ignored. Full schema validation stays with `native validate`.
const InferenceManifest = struct {
    capabilities: []const []const u8 = &.{},
    permissions: []const []const u8 = &.{},
    dock_visible: bool = true,
    web_engine: []const u8 = "system",
    webview_layer: []const u8 = "auto",
    cef: struct {
        dir: []const u8 = "third_party/cef/macos",
        auto_install: bool = false,
    } = .{},
    frontend: ?struct {} = null,
    updates: ?struct {} = null,
    shell: struct {
        windows: []const struct {
            views: []const struct {
                kind: []const u8 = "",
            } = &.{},
        } = &.{},
    } = .{},
};

fn defaultCefDir(platform: PlatformOption, configured: []const u8) []const u8 {
    if (!std.mem.eql(u8, configured, "third_party/cef/macos")) return configured;
    return switch (platform) {
        .linux => "third_party/cef/linux",
        .windows => "third_party/cef/windows",
        else => configured,
    };
}

fn appManifestBuildConfig(b: *std.Build) AppManifestBuildConfig {
    // The fallback for a manifest this lenient parse cannot read
    // keeps the web layer (see AppManifestBuildConfig): a shape
    // mismatch here is not proof the app declares no web use.
    const fallback: AppManifestBuildConfig = .{ .web_declaration = "an app.json this build graph could not parse" };
    const source = @embedFile("app.json");
    @setEvalBranchQuota(4000);
    const raw = std.json.parseFromSliceLeaky(InferenceManifest, b.allocator, source, .{ .ignore_unknown_fields = true }) catch return fallback;
    var config: AppManifestBuildConfig = .{
        .web_engine = parseWebEngine(raw.web_engine) orelse .system,
        .cef_dir = raw.cef.dir,
        .cef_auto_install = raw.cef.auto_install,
        .webview_layer = parseWebLayer(raw.webview_layer) orelse @panic("app.zon .webview_layer must be \"auto\", \"include\", or \"exclude\""),
        .dock_visible = raw.dock_visible,
        .microphone_permission = hasManifestPermission(raw.permissions, "microphone"),
        .system_audio_permission = hasManifestPermission(raw.permissions, "system_audio"),
        .sqlite_capability = hasManifestCapability(raw.capabilities, "store") or hasManifestCapability(raw.capabilities, "sqlite"),
        .relational_capability = hasManifestCapability(raw.capabilities, "sqlite"),
        .updates_enabled = raw.updates != null,
    };
    config.web_declaration = blk: {
        if (raw.frontend != null) break :blk "a .frontend block";
        for (raw.capabilities) |capability| {
            if (std.mem.eql(u8, capability, "webview")) break :blk "the \"webview\" capability";
        }
        for (raw.shell.windows) |window| {
            for (window.views) |view| {
                if (std.mem.eql(u8, view.kind, "webview")) break :blk "a .shell webview view";
            }
        }
        break :blk null;
    };
    return config;
}

fn appManifestModule(b: *std.Build) *std.Build.Module {
    const root = std.json.parseFromSliceLeaky(std.json.Value, b.allocator, @embedFile("app.json"), .{ .parse_numbers = false }) catch
        @panic("cannot parse app.json; run `native check` for a precise diagnostic");
    if (root != .object) @panic("app.json must contain one object");
    var out = std.Io.Writer.Allocating.init(b.allocator);
    writeManifestValue(&out.writer, root, 0) catch |err| switch (err) {
        error.NullNotAllowed => @panic("app.json cannot contain null values; omit optional fields instead"),
        else => @panic("out of memory converting app.json"),
    };
    const generated = b.addWriteFiles().add("app_manifest.zon", out.written());
    return b.createModule(.{ .root_source_file = generated });
}

fn writeManifestValue(writer: *std.Io.Writer, value: std.json.Value, depth: usize) !void {
    switch (value) {
        .null => return error.NullNotAllowed,
        .bool => |v| try writer.writeAll(if (v) "true" else "false"),
        .integer => |v| try writer.print("{d}", .{v}),
        .float => |v| try writer.print("{d}", .{v}),
        .number_string => |v| try writer.writeAll(v),
        .string => |v| try writer.print("\"{f}\"", .{std.zig.fmtString(v)}),
        .array => |array| {
            try writer.writeAll(".{");
            for (array.items) |item| {
                try writeManifestValue(writer, item, depth + 1);
                try writer.writeByte(',');
            }
            try writer.writeByte('}');
        },
        .object => |object| {
            try writer.writeAll(".{");
            var iterator = object.iterator();
            while (iterator.next()) |entry| {
                if (depth == 0 and std.mem.eql(u8, entry.key_ptr.*, "$schema")) continue;
                try writer.print(".{f}=", .{std.zig.fmtId(entry.key_ptr.*)});
                try writeManifestValue(writer, entry.value_ptr.*, depth + 1);
                try writer.writeByte(',');
            }
            try writer.writeByte('}');
        },
    }
}

fn hasManifestPermission(permissions: []const []const u8, name: []const u8) bool {
    for (permissions) |permission| {
        if (std.mem.eql(u8, permission, name)) return true;
    }
    return false;
}

fn hasManifestCapability(capabilities: []const []const u8, name: []const u8) bool {
    for (capabilities) |capability| {
        if (std.mem.eql(u8, capability, name)) return true;
    }
    return false;
}

/// The web-layer decision for this build — the same declare-to-use
/// contract the Native SDK's standard build graph, CLI, and runner
/// apply: an app is WEB when app.zon declares web use (a .frontend
/// block, the "webview" capability, a .shell webview view) or the
/// build resolves to the Chromium engine; otherwise it is
/// NATIVE-ONLY and the platform host compiles without the
/// embedded-WebView layer. `.webview_layer` (and `-Dweb-layer`)
/// override the inference — but an exclude that contradicts a web
/// declaration is a hard configure error, never a silently broken
/// app.
fn resolveWebLayer(config: AppManifestBuildConfig, web_engine: WebEngineOption, override: ?WebLayerOption) bool {
    const setting = override orelse config.webview_layer;
    const declaration: ?[]const u8 = config.web_declaration orelse
        (if (web_engine == .chromium) "the Chromium web engine" else null);
    return switch (setting) {
        .include => true,
        .auto => declaration != null,
        .exclude => {
            if (declaration) |reason| {
                std.debug.panic(
                    "the web layer is excluded ({s}) but the app declares web use ({s}); remove the exclude or drop the web declaration",
                    .{ if (override != null) "-Dweb-layer=exclude" else "app.zon .webview_layer = \"exclude\"", reason },
                );
            }
            return false;
        },
    };
}

fn parseWebEngine(value: []const u8) ?WebEngineOption {
    if (std.mem.eql(u8, value, "system")) return .system;
    if (std.mem.eql(u8, value, "chromium")) return .chromium;
    return null;
}

fn parseWebLayer(value: []const u8) ?WebLayerOption {
    if (std.mem.eql(u8, value, "auto")) return .auto;
    if (std.mem.eql(u8, value, "include")) return .include;
    if (std.mem.eql(u8, value, "exclude")) return .exclude;
    return null;
}
