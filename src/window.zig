const std = @import("std");
const log = std.log.scoped(.window);
const glfw = @import("zglfw");
const gl = @import("gl");

const Shader = @import("shader.zig").Shader;
const Framebuffer = @import("framebuffer.zig").Framebuffer;
const CHIP8 = @import("cpu.zig").CHIP8;

const SCREEN_WIDTH = @import("main.zig").SCREEN_WIDTH;
const SCREEN_HEIGHT = @import("main.zig").SCREEN_HEIGHT;
const PIXEL_COUNT = @import("main.zig").PIXEL_COUNT;

const ScreenQuad = struct {
    handle: u32,

    pub fn init() ScreenQuad {
        const vertices = [_]f32{
            -3.0, -1.0, -1.0, 0.0,
            1.0,  -1.0, 1.0,  0.0,
            1.0,  3.0,  1.0,  2.0,
        };
        const indices = [_]u32{
            0, 1, 2,
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

pub const Window = struct {
    glfw_window: *glfw.Window,
    framebuffer: Framebuffer,
    shader: Shader,
    screen_quad: ScreenQuad,

    var procs: gl.ProcTable = undefined;

    pub fn init() !Window {
        try glfw.init();

        // MacOS compatible
        glfw.windowHint(.context_version_major, 4);
        glfw.windowHint(.context_version_minor, 1);
        glfw.windowHint(.opengl_forward_compat, true);
        glfw.windowHint(.opengl_profile, .opengl_core_profile);

        const glfw_window = try glfw.createWindow(
            SCREEN_WIDTH * 10,
            SCREEN_HEIGHT * 10,
            "Render",
            null,
        );

        glfw.makeContextCurrent(glfw_window);

        glfw.swapInterval(0); // Request to disable vsync

        if (!procs.init(getProcAddress)) return error.InitFailed;
        gl.makeProcTableCurrent(&procs);

        const framebuffer = try Framebuffer.init(SCREEN_WIDTH, SCREEN_HEIGHT);
        const shader = Shader.init("./shaders/screen.vert", "./shaders/screen.frag");

        const screen_quad = ScreenQuad.init();

        return .{
            .glfw_window = glfw_window,
            .framebuffer = framebuffer,
            .shader = shader,
            .screen_quad = screen_quad,
        };
    }

    pub fn attach_cpu(self: Window, cpu: *CHIP8) void {
        glfw.setWindowUserPointer(self.glfw_window, cpu);
        _ = glfw.setKeyCallback(self.glfw_window, CHIP8.Input.on_key_event);
    }

    pub fn draw(
        self: Window,
        pixels: *[SCREEN_HEIGHT][SCREEN_WIDTH]u8,
    ) void {
        glfw.pollEvents();

        gl.ClearColor(1.0, 0.0, 1.0, 1.0);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        self.framebuffer.draw(&@as([PIXEL_COUNT]u8, @bitCast(pixels.*)));
        self.framebuffer.bind();
        defer self.framebuffer.unbind();

        const err = gl.GetError();
        if (err != gl.NO_ERROR) {
            log.err("{}\n", .{err});
        }

        self.shader.use();

        self.screen_quad.bind();
        defer ScreenQuad.unbind();

        gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, 0);
        self.shader.free();

        glfw.swapBuffers(self.glfw_window);
    }

    pub fn should_close(self: Window) bool {
        return self.glfw_window.shouldClose();
    }

    pub fn deinit(self: Window) void {
        self.screen_quad.deinit();
        self.shader.deinit();
        gl.makeProcTableCurrent(null);
        glfw.makeContextCurrent(null);
        glfw.destroyWindow(self.glfw_window);
        glfw.terminate();
    }

    pub fn getProcAddress(name: [*:0]const u8) ?*align(4) const anyopaque {
        return @alignCast(glfw.getProcAddress(name));
    }
};
