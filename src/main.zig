const std = @import("std");
const glfw = @import("zglfw");
const gl = @import("gl");

const Shader = @import("shader.zig").Shader;
const Framebuffer = @import("framebuffer.zig").Framebuffer;

const CPU = @import("cpu.zig").CHIP_8;

const WINDOW_WIDTH = 640;
const WINDOW_HEIGHT = 320;

var procs: gl.ProcTable = undefined;

pub fn getProcAddress(name: [*:0]const u8) ?*align(4) const anyopaque {
    return @alignCast(glfw.getProcAddress(name));
}

const ScreenQuad = struct {
    handle: u32,

    pub fn init() ScreenQuad {
        const vertices = [_]f32{
            -1.0, -1.0, 0.0, 0.0,
            1.0,  1.0,  1.0, 1.0,
            1.0,  -1.0, 1.0, 0.0,
            -1.0, 1.0,  0.0, 1.0,
        };
        const indices = [_]u32{
            0, 1, 2,
            3, 1, 0,
        };

        var vao: c_uint = undefined;
        gl.GenVertexArrays(1, (&vao)[0..1]);
        gl.BindVertexArray(vao);

        var vbo: c_uint = undefined;
        gl.GenBuffers(1, (&vbo)[0..1]);
        gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
        defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);
        gl.BufferData(
            gl.ARRAY_BUFFER,
            @sizeOf(@TypeOf(vertices)),
            &vertices,
            gl.STATIC_DRAW,
        );

        gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 4 * @sizeOf(f32), 0);
        gl.EnableVertexAttribArray(0);
        gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, 4 * @sizeOf(f32), 2 * @sizeOf(f32));
        gl.EnableVertexAttribArray(1);

        var ebo: c_uint = undefined;
        gl.GenBuffers(1, (&ebo)[0..1]);
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);
        gl.BufferData(
            gl.ELEMENT_ARRAY_BUFFER,
            @sizeOf(@TypeOf(indices)),
            &indices,
            gl.STATIC_DRAW,
        );

        return .{ .handle = vao };
    }

    pub fn deinit(self: ScreenQuad) void {
        gl.DeleteVertexArrays(1, &.{self.handle});
    }

    pub fn bind(self: ScreenQuad) void {
        gl.BindVertexArray(self.handle);
    }

    pub fn unbind() void {
        gl.BindVertexArray(0);
    }
};

pub fn main() !void {
    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(.context_version_major, 4);
    glfw.windowHint(.context_version_minor, 1);
    glfw.windowHint(.opengl_forward_compat, true);
    glfw.windowHint(.opengl_profile, .opengl_core_profile);

    const window = try glfw.createWindow(
        WINDOW_WIDTH,
        WINDOW_HEIGHT,
        "Render",
        null,
    );
    defer glfw.destroyWindow(window);

    glfw.makeContextCurrent(window);
    defer glfw.makeContextCurrent(null);

    if (!procs.init(getProcAddress)) return error.InitFailed;

    gl.makeProcTableCurrent(&procs);
    defer gl.makeProcTableCurrent(null);

    const shader = Shader.init("./shaders/screen.vert", "./shaders/screen.frag");
    defer shader.deinit();

    const screen_quad = ScreenQuad.init();
    defer screen_quad.deinit();

    const framebuffer = try Framebuffer.init(WINDOW_WIDTH, WINDOW_HEIGHT);

    const pixels = try std.heap.page_allocator.alloc(u8, WINDOW_WIDTH * WINDOW_HEIGHT);
    @memset(pixels, 0b11100001);
    defer std.heap.page_allocator.free(pixels);

    var cpu = CPU.init(pixels);

    while (!glfw.windowShouldClose(window)) {
        gl.ClearColor(1.0, 0.0, 1.0, 1.0);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        cpu.cycle();
        framebuffer.draw(pixels);
        framebuffer.bind();
        defer framebuffer.unbind();

        const err = gl.GetError();
        if (err != gl.NO_ERROR) {
            std.debug.print("ERROR: {}\n", .{err});
        }

        shader.use();

        screen_quad.bind();
        defer ScreenQuad.unbind();

        gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, 0);
        shader.free();

        glfw.swapBuffers(window);
        glfw.pollEvents();
    }
}
