const std = @import("std");
const builtin = @import("builtin");

const wm_set_icon: u32 = 0x0080;
const icon_small: usize = 0;
const icon_big: usize = 1;
const image_icon: u32 = 1;
const load_image_shared: u32 = 0x0000_8000;

extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) u32;
extern "kernel32" fn GetModuleHandleW(module_name: ?[*:0]const u16) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn Sleep(milliseconds: u32) callconv(.winapi) void;
extern "user32" fn EnumWindows(callback: *const fn (*anyopaque, isize) callconv(.winapi) i32, data: isize) callconv(.winapi) i32;
extern "user32" fn GetClassNameW(window: *anyopaque, class_name: [*]u16, max_count: i32) callconv(.winapi) i32;
extern "user32" fn GetWindowThreadProcessId(window: *anyopaque, process_id: *u32) callconv(.winapi) u32;
// `name` is MAKEINTRESOURCEW(1), so it intentionally uses an untyped pointer.
extern "user32" fn LoadImageW(module: ?*anyopaque, name: *const anyopaque, image_type: u32, width: i32, height: i32, flags: u32) callconv(.winapi) ?*anyopaque;
extern "user32" fn SetClassLongPtrW(window: *anyopaque, index: i32, new_long: isize) callconv(.winapi) isize;
extern "user32" fn PostMessageW(window: *anyopaque, message: u32, wparam: usize, lparam: isize) callconv(.winapi) i32;

const native_window_class = "NativeSdkWindowsHost";

const WindowSearch = struct {
    process_id: u32,
    window: ?*anyopaque = null,
};

/// 在 Native SDK 创建窗口后，把 exe 中的 ICO 设置为窗口的大/小图标。
/// SDK 当前只把 icon_path 用于托盘图标，窗口类本身没有设置 hIcon。
pub fn start() ?std.Thread {
    if (comptime builtin.os.tag != .windows) return null;
    return std.Thread.spawn(.{}, applyWhenWindowExists, .{}) catch null;
}

pub fn join(thread: ?std.Thread) void {
    if (thread) |value| value.join();
}

fn applyWhenWindowExists() void {
    if (comptime builtin.os.tag != .windows) return;

    const module = GetModuleHandleW(null) orelse return;
    const resource_id: *const anyopaque = @ptrFromInt(@as(usize, 1));
    const large_icon = LoadImageW(module, resource_id, image_icon, 32, 32, load_image_shared);
    const small_icon = LoadImageW(module, resource_id, image_icon, 16, 16, load_image_shared);
    if (large_icon == null and small_icon == null) return;

    // Native SDK creates its HWND after runWithOptions starts. Poll only this
    // short startup window; Sleep blocks this worker, never the UI thread.
    var attempts: usize = 0;
    while (attempts < 250) : (attempts += 1) {
        var search = WindowSearch{ .process_id = GetCurrentProcessId() };
        _ = EnumWindows(findNativeWindow, @bitCast(@intFromPtr(&search)));
        if (search.window) |window| {
            applyIcon(window, large_icon, small_icon);
            return;
        }
        Sleep(20);
    }
}

fn findNativeWindow(window: *anyopaque, data: isize) callconv(.winapi) i32 {
    var process_id: u32 = 0;
    if (GetWindowThreadProcessId(window, &process_id) == 0) return 1;
    const search: *WindowSearch = @ptrFromInt(@as(usize, @bitCast(data)));
    if (process_id != search.process_id) return 1;

    var class_name: [64]u16 = undefined;
    const length = GetClassNameW(window, &class_name, @intCast(class_name.len));
    if (length != native_window_class.len) return 1;
    for (native_window_class, 0..) |expected, index| {
        if (class_name[index] != expected) return 1;
    }
    search.window = window;
    return 0;
}

fn applyIcon(window: *anyopaque, large_icon: ?*anyopaque, small_icon: ?*anyopaque) void {
    if (large_icon) |icon| {
        const handle: isize = @bitCast(@intFromPtr(icon));
        // Set the class icon as well as the per-window icon. This fixes the
        // title bar and the taskbar entry for hosts that omit WNDCLASSEX.hIcon.
        _ = SetClassLongPtrW(window, -14, handle); // GCLP_HICON
        _ = PostMessageW(window, wm_set_icon, icon_big, handle);
    }
    if (small_icon) |icon| {
        const handle: isize = @bitCast(@intFromPtr(icon));
        _ = SetClassLongPtrW(window, -34, handle); // GCLP_HICONSM
        _ = PostMessageW(window, wm_set_icon, icon_small, handle);
    }
}
