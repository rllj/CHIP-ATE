const gl = @import("gl");

pub const Framebuffer = struct {
    texture: u32,
    width: u16,
    height: u16,

    pub fn init(width: u16, height: u16) !Framebuffer {
        var texture: c_uint = undefined;
        gl.GenTextures(1, (&texture)[0..1]);
        gl.BindTexture(gl.TEXTURE_2D, texture);
        defer gl.BindTexture(gl.TEXTURE_2D, 0);

        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

        return .{
            .texture = texture,
            .width = width,
            .height = height,
        };
    }

    pub fn bind(self: Framebuffer) void {
        gl.BindTexture(gl.TEXTURE_2D, self.texture);
    }

    pub fn unbind(self: Framebuffer) void {
        _ = self;
        gl.BindTexture(gl.TEXTURE_2D, 0);
    }

    pub fn draw(self: Framebuffer, pixels: []const u8) void {
        self.bind();
        gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB, self.width, self.height, 0, gl.RGB, gl.UNSIGNED_BYTE_3_3_2, pixels.ptr);
        self.unbind();
    }

    pub fn deinit(self: Framebuffer) void {
        gl.DeleteTextures(1, &self.texture);
    }
};
