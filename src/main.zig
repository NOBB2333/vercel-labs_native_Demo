const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const runner = @import("runner");
const native_sdk = @import("native_sdk");
const app_config = @import("app_manifest_zon");
const backend_module = @import("backend/root.zig");
const portable_bundle = if (build_options.portable) @import("portable_bundle").bytes else "";

const BundleHeaderSize = 12;
const BundleMagic = "LDF1\x00";
extern "kernel32" fn LoadLibraryW(path: [*:0]const u16) callconv(.winapi) ?*anyopaque;

const App = struct {
    env_map: *std.process.Environ.Map,
    dist_path: []const u8,

    fn app(self: *@This()) native_sdk.App {
        return .{ .context = self, .name = app_config.name, .source = native_sdk.frontend.productionSource(.{ .dist = self.dist_path }), .source_fn = source };
    }
    fn source(context: *anyopaque) anyerror!native_sdk.WebViewSource {
        const self: *@This() = @ptrCast(@alignCast(context));
        if (build_options.portable) return native_sdk.frontend.productionSource(.{ .dist = self.dist_path });
        return native_sdk.frontend.sourceFromEnv(self.env_map, .{ .dist = self.dist_path, .entry = "index.html" });
    }
};
/// 从可执行文件位置解析标准包资源，避免依赖当前工作目录。
/// 在源码目录执行 `zig build run` 时仍回退到 src_web/dist。
fn productionDistPath(init: std.process.Init) []const u8 {
    const allocator = init.arena.allocator();
    const executable = std.process.executablePathAlloc(init.io, allocator) catch return "src_web/dist";
    const executable_dir = std.fs.path.dirname(executable) orelse return "src_web/dist";
    const relative = if (builtin.os.tag == .macos and std.mem.endsWith(u8, executable_dir, "/Contents/MacOS"))
        "../Resources/src_web/dist"
    else
        "../resources/src_web/dist";
    const packaged = std.fs.path.join(allocator, &.{ executable_dir, relative }) catch return "src_web/dist";
    std.Io.Dir.cwd().access(init.io, packaged, .{}) catch return "src_web/dist";
    return packaged;
}

/// 校验 bundle 内相对路径，拒绝绝对路径、盘符和 .. 穿越。
fn safeBundlePath(path: []const u8) bool {
    if (path.len == 0 or std.fs.path.isAbsolute(path) or path[0] == '/') return false;
    if (std.mem.indexOfAny(u8, path, ":\\") != null) return false;
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| if (std.mem.eql(u8, part, "..") or part.len == 0) return false;
    return true;
}

fn materializePortableBundle(init: std.process.Init) ![]const u8 {
    const allocator = init.arena.allocator();
    const cache_root = if (builtin.os.tag == .windows) init.environ_map.get("LOCALAPPDATA") orelse init.environ_map.get("TEMP") orelse "." else if (builtin.os.tag == .macos) if (init.environ_map.get("HOME")) |home| try std.fs.path.join(allocator, &.{ home, "Library", "Caches" }) else init.environ_map.get("TMPDIR") orelse "/tmp" else init.environ_map.get("XDG_CACHE_HOME") orelse if (init.environ_map.get("HOME")) |home| try std.fs.path.join(allocator, &.{ home, ".cache" }) else init.environ_map.get("TMPDIR") orelse "/tmp";
    const fingerprint = std.hash.Wyhash.hash(0, portable_bundle);
    var nonce: u128 = undefined;
    try init.io.randomSecure(std.mem.asBytes(&nonce));
    const root = try std.fmt.allocPrint(allocator, "{s}/{s}-{s}-{x}-{x}", .{ cache_root, app_config.name, app_config.version, fingerprint, nonce });
    // 目录名包含安全随机数，并以原子 createDir 创建；绝不复用可被预置为符号链接的路径。
    try std.Io.Dir.cwd().createDirPath(init.io, cache_root);
    try std.Io.Dir.cwd().createDir(init.io, root, .default_dir);
    var root_dir = try std.Io.Dir.openDirAbsolute(init.io, root, .{});
    defer root_dir.close(init.io);
    var offset: usize = 0;
    if (portable_bundle.len < BundleMagic.len or !std.mem.eql(u8, portable_bundle[0..BundleMagic.len], BundleMagic)) return error.InvalidPortableBundle;
    offset = BundleMagic.len;
    while (offset < portable_bundle.len) {
        if (portable_bundle.len - offset < BundleHeaderSize) return error.InvalidPortableBundle;
        const name_length: usize = @intCast(std.mem.readInt(u32, portable_bundle[offset..][0..4], .little));
        const data_len = std.mem.readInt(u64, portable_bundle[offset + 4 ..][0..8], .little);
        offset += BundleHeaderSize;
        if (name_length == 0 or data_len > std.math.maxInt(usize) or name_length > portable_bundle.len - offset) return error.InvalidPortableBundle;
        const name = portable_bundle[offset .. offset + name_length];
        offset += name_length;
        const length: usize = @intCast(data_len);
        if (!safeBundlePath(name) or length > portable_bundle.len - offset) return error.InvalidPortableBundle;
        const parent = std.fs.path.dirname(name) orelse ".";
        if (!std.mem.eql(u8, parent, ".")) {
            var parent_dir = try root_dir.createDirPathOpen(init.io, parent, .{ .open_options = .{ .follow_symlinks = false } });
            parent_dir.close(init.io);
        }
        try root_dir.writeFile(init.io, .{ .sub_path = name, .data = portable_bundle[offset .. offset + length], .flags = .{ .exclusive = true, .resolve_beneath = true } });
        offset += length;
    }
    return root;
}

fn loadPortableLoader(allocator: std.mem.Allocator, dist_path: []const u8) !void {
    if (builtin.os.tag != .windows or !build_options.web_layer or !std.mem.eql(u8, build_options.web_engine, "system")) return;
    const loader_path = try std.fs.path.join(allocator, &.{ dist_path, "__native", "WebView2Loader.dll" });
    const wide = try std.unicode.utf8ToUtf16LeAllocZ(allocator, loader_path);
    if (LoadLibraryW(wide.ptr) == null) return error.PortableWebView2LoaderUnavailable;
}

const dev_origins = [_][]const u8{ "zero://app", "zero://inline", build_options.dev_origin };

/// 组装应用壳、Bridge 注册表和长生命周期服务。
pub fn main(init: std.process.Init) !void {
    var app = App{
        .env_map = init.environ_map,
        .dist_path = if (build_options.portable)
            try materializePortableBundle(init)
        else
            productionDistPath(init),
    };
    if (build_options.portable) try loadPortableLoader(init.arena.allocator(), app.dist_path);
    var backend = backend_module.Backend.init();
    try runner.runWithOptions(app.app(), .{
        .app_name = app_config.display_name,
        .window_title = app_config.display_name,
        .bundle_id = app_config.id,
        .icon_path = "assets/icon.png",
        .bridge = backend.dispatcher(),
        .security = .{ .navigation = .{ .allowed_origins = &dev_origins } },
    }, init);
}

test {
    // Zig 按需分析声明，显式引用后端才能将其测试纳入测试入口。
    std.testing.refAllDecls(backend_module);
}
