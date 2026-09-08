const native_sdk = @import("native_sdk");
const build_options = @import("build_options");
const health = @import("features/health.zig");

test {
    @import("std").testing.refAllDecls(health);
}

const command_policies = [_]native_sdk.BridgeCommandPolicy{
    .{
        .name = health.command_name,
        .origins = &.{ "zero://app", build_options.dev_origin },
    },
};

/// 持有后端服务，并暴露 Native Bridge dispatcher。
pub const Backend = struct {
    health_service: health.Service = .{},
    handlers: [1]native_sdk.BridgeHandler = undefined,

    /// 创建具有全新服务状态的后端实例。
    pub fn init() Backend {
        return .{};
    }

    /// 注册 handler，并返回最小权限 Bridge 策略。
    pub fn dispatcher(self: *Backend) native_sdk.BridgeDispatcher {
        self.handlers = .{
            .{
                .name = health.command_name,
                .context = &self.health_service,
                .invoke_fn = health.Service.handle,
            },
        };

        return .{
            .policy = .{
                .enabled = true,
                .commands = &command_policies,
            },
            .registry = .{ .handlers = &self.handlers },
        };
    }
};

test "backend dispatches the health command" {
    const std = @import("std");

    var backend = Backend.init();
    const dispatcher = backend.dispatcher();
    var output: [512]u8 = undefined;
    const response = dispatcher.dispatch(
        \\{"id":"test","command":"app.health","payload":null}
    , .{ .origin = "zero://app" }, &output);

    try std.testing.expect(std.mem.indexOf(u8, response, "\"ok\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"status\":\"ok\"") != null);
}

test "backend rejects untrusted origins before invoking handlers" {
    const std = @import("std");
    var backend = Backend.init();
    const dispatcher = backend.dispatcher();
    var output: [512]u8 = undefined;
    const response = dispatcher.dispatch(
        \\{"id":"test","command":"app.health","payload":null}
    , .{ .origin = "https://example.com" }, &output);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"permission_denied\"") != null);
    try std.testing.expectEqual(@as(u64, 0), backend.health_service.request_count);
}

test "manifest command policies match the runtime registry" {
    const std = @import("std");
    const manifest = @import("app_manifest_zon");
    var backend = Backend.init();
    const dispatcher = backend.dispatcher();
    try std.testing.expectEqual(manifest.bridge.commands.len, command_policies.len);
    try std.testing.expectEqual(command_policies.len, dispatcher.registry.handlers.len);
    inline for (manifest.bridge.commands) |command| {
        const policy = dispatcher.policy.find(command.name) orelse return error.MissingPolicy;
        try std.testing.expect(dispatcher.registry.find(command.name) != null);
        try std.testing.expectEqual(command.origins.len, policy.origins.len);
        inline for (command.origins) |origin| {
            try std.testing.expect(dispatcher.policy.allows(command.name, origin));
        }
    }
}
