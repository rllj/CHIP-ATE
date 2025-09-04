const std = @import("std");
const gl = @import("gl");

pub const Shader = struct {
    handle: c_uint,

    pub fn init(
        comptime vert_shader_path: []const u8,
        comptime frag_shader_path: []const u8,
    ) Shader {
        const vert_shader_src = @embedFile(vert_shader_path);
        const frag_shader_src = @embedFile(frag_shader_path);

        const vert_shader = gl.CreateShader(gl.VERTEX_SHADER);
        defer gl.DeleteShader(vert_shader);
        gl.ShaderSource(vert_shader, 1, &.{vert_shader_src}, null);
        gl.CompileShader(vert_shader);

        const frag_shader = gl.CreateShader(gl.FRAGMENT_SHADER);
        defer gl.DeleteShader(frag_shader);
        gl.ShaderSource(frag_shader, 1, &.{frag_shader_src}, null);
        gl.CompileShader(frag_shader);

        const program = gl.CreateProgram();
        gl.AttachShader(program, vert_shader);
        gl.AttachShader(program, frag_shader);
        gl.LinkProgram(program);

        {
            var buf: [1024]u8 = undefined;
            var len: c_int = 0;
            gl.GetShaderInfoLog(vert_shader, 1024, &len, &buf);
            std.debug.print(
                \\Vertex shader log:
                \\{s}
                \\--------------
                \\
            , .{buf[0..@intCast(len)]});
        }
        {
            var buf: [1024]u8 = undefined;
            var len: c_int = 0;
            gl.GetShaderInfoLog(frag_shader, 1024, &len, &buf);
            std.debug.print(
                \\Fragment shader log:
                \\{s}
                \\--------------
                \\
            , .{buf[0..@intCast(len)]});
        }
        {
            var buf: [1024]u8 = undefined;
            var len: c_int = 0;
            gl.GetProgramInfoLog(program, 1024, &len, &buf);
            std.debug.print(
                \\Shader program log:
                \\{s}
                \\--------------
                \\
            , .{buf[0..@intCast(len)]});
        }

        return .{ .handle = program };
    }

    pub fn deinit(self: Shader) void {
        gl.UseProgram(0);
        gl.DeleteProgram(self.handle);
    }

    pub fn use(self: Shader) void {
        gl.UseProgram(self.handle);
    }

    pub fn free(self: Shader) void {
        _ = self;
        gl.UseProgram(0);
    }
};
