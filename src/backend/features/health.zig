const std = @import("std");
const native_sdk = @import("native_sdk");
const app_config = @import("app_manifest_zon");

/// 暴露给前端适配层的稳定 Bridge 命令名。
pub const command_name = "app.health";

/// 记录当前应用进程生命周期内的健康检查次数。
pub const Service = struct {
    request_count: u64 = 0,

    /// 返回当前应用标识，并递增请求计数。
    pub fn handle(context: *anyopaque, invocation: native_sdk.bridge.Invocation, output: []u8) anyerror![]const u8 {
        const self: *Service = @ptrCast(@alignCast(context));
        if (!std.mem.eql(u8, std.mem.trim(u8, invocation.request.payload, " \t\r\n"), "null")) return error.InvalidPayload;
        const next_count = try std.math.add(u64, self.request_count, 1);
        const result = try writeHealth(output, app_config.display_name, app_config.version, next_count);
        self.request_count = next_count;
        return result;
    }
};

fn writeHealth(output: []u8, name: []const u8, version: []const u8, count: u64) ![]const u8 {
    var writer = std.Io.Writer.fixed(output);
    try std.json.Stringify.value(.{ .status = "ok", .app = name, .version = version, .requestCount = count }, .{}, &writer);
    return writer.buffered();
}

test "health service returns valid status JSON" {
    var service: Service = .{};
    var output: [256]u8 = undefined;
    const result = try Service.handle(
        &service,
        .{ .request = .{ .id = "1", .command = command_name }, .source = .{} },
        &output,
    );

    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, result, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("ok", parsed.value.object.get("status").?.string);
    try std.testing.expectEqualStrings(app_config.version, parsed.value.object.get("version").?.string);
    try std.testing.expectEqual(@as(i64, 1), parsed.value.object.get("requestCount").?.integer);
}

test "health JSON escapes display names" {
    var output: [512]u8 = undefined;
    const name = "工具 \"Demo\" \\ local";
    const result = try writeHealth(&output, name, "1.2.3", 2);
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, result, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings(name, parsed.value.object.get("app").?.string);
}

test "health rejects payloads and preserves count on failure" {
    var service: Service = .{};
    var output: [256]u8 = undefined;
    const invocation: native_sdk.bridge.Invocation = .{ .request = .{ .id = "1", .command = command_name, .payload = "{}" }, .source = .{} };
    try std.testing.expectError(error.InvalidPayload, Service.handle(&service, invocation, &output));
    try std.testing.expectEqual(@as(u64, 0), service.request_count);
    var valid = invocation;
    valid.request.payload = "null";
    try std.testing.expectError(error.WriteFailed, Service.handle(&service, valid, output[0..1]));
    try std.testing.expectEqual(@as(u64, 0), service.request_count);
}
