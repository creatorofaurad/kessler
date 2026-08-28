const std = @import("std");
const ring_buffer = @import("gui/ring_buffer.zig");
const engine_thread = @import("gui/engine_thread.zig");
const render = @import("gui/render.zig");

const c = @cImport({
    @cInclude("GLFW/glfw3.h");
    @cInclude("gui/wrapper.h");
});

var g_ring_buffer = ring_buffer.RingBuffer.init();
var dragging = false;
var drag_offset_x: f64 = 0;
var drag_offset_y: f64 = 0;

fn mouseButtonCallback(window: ?*c.GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.c) void {
    _ = mods;
    if (button == c.GLFW_MOUSE_BUTTON_LEFT) {
        if (action == c.GLFW_PRESS) {
            dragging = true;
            var x: f64 = 0;
            var y: f64 = 0;
            c.glfwGetCursorPos(window, &x, &y);
            drag_offset_x = x;
            drag_offset_y = y;
        } else if (action == c.GLFW_RELEASE) {
            dragging = false;
        }
    }
}

fn cursorPositionCallback(window: ?*c.GLFWwindow, xpos: f64, ypos: f64) callconv(.c) void {
    if (dragging) {
        var wx: c_int = 0;
        var wy: c_int = 0;
        c.glfwGetWindowPos(window, &wx, &wy);
        const new_x = wx + @as(c_int, @intFromFloat(xpos - drag_offset_x));
        const new_y = wy + @as(c_int, @intFromFloat(ypos - drag_offset_y));
        c.glfwSetWindowPos(window, new_x, new_y);
    }
}

pub fn main() !void {
    if (c.glfwInit() == 0) {
        return error.GlfwInitFailed;
    }
    defer c.glfwTerminate();

    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
    c.glfwWindowHint(c.GLFW_DECORATED, c.GLFW_FALSE); // No title bar

    const window = c.glfwCreateWindow(1400, 900, "Kessler", null, null) orelse return error.WindowCreateFailed;
    
    // Center window
    const monitor = c.glfwGetPrimaryMonitor();
    if (monitor != null) {
        const mode = c.glfwGetVideoMode(monitor);
        if (mode != null) {
            c.glfwSetWindowPos(window, @divTrunc(mode.*.width - 1400, 2), @divTrunc(mode.*.height - 900, 2));
        }
    }

    c.glfwMakeContextCurrent(window);
    c.glfwSwapInterval(1); // Enable vsync

    _ = c.glfwSetMouseButtonCallback(window, mouseButtonCallback);
    _ = c.glfwSetCursorPosCallback(window, cursorPositionCallback);

    // Spawn Engine Thread
    const thread = try std.Thread.spawn(.{}, engine_thread.engineMain, .{&g_ring_buffer});

    // Setup Dear ImGui
    _ = c.w_igCreateContext();
    defer c.w_igDestroyContext();
    
    // Load Fonts
    const font_regular = @embedFile("fonts/FiraCode-Regular.ttf");
    const font_bold = @embedFile("fonts/FiraCode-Bold.ttf");
    
    _ = c.w_AddFont(@constCast(font_regular.ptr), @intCast(font_regular.len), 11.0);
    _ = c.w_AddFont(@constCast(font_regular.ptr), @intCast(font_regular.len), 24.0);
    _ = c.w_AddFont(@constCast(font_regular.ptr), @intCast(font_regular.len), 28.0);
    _ = c.w_AddFont(@constCast(font_bold.ptr), @intCast(font_bold.len), 96.0);

    _ = c.w_ImGui_ImplGlfw_InitForOpenGL(window, true);
    defer c.w_ImGui_ImplGlfw_Shutdown();
    _ = c.w_ImGui_ImplOpenGL3_Init("#version 330");
    defer c.w_ImGui_ImplOpenGL3_Shutdown();

    var current_snapshot: ring_buffer.TickSnapshot = std.mem.zeroes(ring_buffer.TickSnapshot);
    var last_read_idx: u64 = 0;

    while (c.glfwWindowShouldClose(window) == 0) {
        c.glfwPollEvents();
        
        if (c.glfwGetKey(window, c.GLFW_KEY_ESCAPE) == c.GLFW_PRESS) {
            c.glfwSetWindowShouldClose(window, 1);
        }

        // Read latest snapshot
        const write_idx = g_ring_buffer.write_idx.load(.acquire);
        if (write_idx > last_read_idx) {
            // Read the most recent snapshot (write_idx - 1)
            current_snapshot = g_ring_buffer.slots[(write_idx - 1) % ring_buffer.RingBuffer.CAPACITY];
            last_read_idx = write_idx;
        }

        c.w_ImGui_ImplOpenGL3_NewFrame();
        c.w_ImGui_ImplGlfw_NewFrame();
        c.w_igNewFrame();

        // Render GUI
        var w: c_int = 0;
        var h: c_int = 0;
        c.glfwGetWindowSize(window, &w, &h);
        
        c.w_igSetNextWindowPos(.{ .x = 0, .y = 0 });
        c.w_igSetNextWindowSize(.{ .x = @floatFromInt(w), .y = @floatFromInt(h) });
        
        const flags = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 5) | (1 << 7) | (1 << 9);
                      
        _ = c.w_igBegin("Background", flags);
        
        render.renderAll(&current_snapshot, @floatFromInt(w), @floatFromInt(h));
        
        c.w_igEnd();
        c.w_igRender();

        c.glClearColor(0, 0, 0, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT);
        
        c.w_ImGui_ImplOpenGL3_RenderDrawData(c.w_igGetDrawData());
        
        c.glfwSwapBuffers(window);
    }
    
    // In a real application, you'd gracefully shut down the thread here.
    // For this prototype, exiting main() will kill the process and thread.
    thread.detach();
}
