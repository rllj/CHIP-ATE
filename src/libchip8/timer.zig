const std = @import("std");

var wasm_timer: WASMTimer = undefined;

const WASMTimer = struct {
    start_time: f64,
};

pub fn start() !f64 {
    wasm_timer.start_time = std.os.emscripten.emscripten_get_now();
}

pub fn lap() f64 {
    const now = std.os.emscripten.emscripten_get_now();
    const res = now - wasm_timer.start_time;
    wasm_timer.start_time += now;
    return res;
}
