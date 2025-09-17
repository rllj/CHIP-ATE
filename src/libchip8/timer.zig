const std = @import("std");

var timer: WASMTimer = undefined;

pub const WASMTimer = struct {
    start_time: f64,

    pub fn start() !WASMTimer {
        timer = .{ .start_time = std.os.emscripten.emscripten_get_now() };
        return timer;
    }

    pub fn lap(_: *WASMTimer) f64 {
        const now = std.os.emscripten.emscripten_get_now();
        const res = now - timer.start_time;
        timer.start_time += now;
        return res;
    }
};
