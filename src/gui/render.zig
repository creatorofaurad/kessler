const std = @import("std");
const ring_buffer = @import("ring_buffer.zig");

const c = @cImport({
    @cInclude("gui/wrapper.h");
});

pub const AnimationState = struct {
    last_time: f64 = 0.0,
    frozen_frames: [36]f32 = [_]f32{0.0} ** 36,
    vignette_progress: f32 = 0.0,
    pulse_timer: f32 = 0.0,
};

var g_state = AnimationState{};

fn igColor(hex: u32, alpha: f32) u32 {
    const r = @as(f32, @floatFromInt((hex >> 16) & 0xFF)) / 255.0;
    const g = @as(f32, @floatFromInt((hex >> 8) & 0xFF)) / 255.0;
    const b = @as(f32, @floatFromInt(hex & 0xFF)) / 255.0;
    return c.w_igGetColorU32(.{ .x = r, .y = g, .z = b, .w = alpha });
}

pub fn renderAll(snapshot: *const ring_buffer.TickSnapshot, window_width: f32, window_height: f32) void {
    const draw_list = c.w_igGetBackgroundDrawList() orelse unreachable;

    if (!snapshot.engine_running) {
        renderOffline(draw_list, window_width, window_height);
        return;
    }

    const current_time = c.w_igGetTime();
    if (g_state.last_time == 0.0) g_state.last_time = current_time;
    const dt = @as(f32, @floatCast(current_time - g_state.last_time));
    g_state.last_time = current_time;
    g_state.pulse_timer += dt;

    renderBackground(draw_list, window_width, window_height);
    renderWaveform(draw_list, snapshot, window_width, window_height);
    renderConstellation(draw_list, snapshot, window_width, window_height);
    renderVignette(draw_list, snapshot, window_width, window_height, dt);
    
    // ImGui Overlay Panels
    renderTelemetryPanel(draw_list, snapshot, window_width, window_height, current_time);
}

fn renderBackground(draw_list: *c.ImDrawList, w: f32, h: f32) void {
    // Rich deep gradient background
    const col_top = igColor(0x07090F, 1.0);
    const col_bot = igColor(0x111827, 1.0);
    c.w_ImDrawList_AddRectFilledMultiColor(draw_list, .{ .x = 0, .y = 0 }, .{ .x = w, .y = h }, col_top, col_top, col_bot, col_bot);

    // Subtle grid lines
    const grid_col = igColor(0x1C2333, 0.5);
    var x: f32 = 0;
    while (x < w) : (x += 100.0) {
        c.w_ImDrawList_AddLine(draw_list, .{ .x = x, .y = 0 }, .{ .x = x, .y = h }, grid_col, 1.0);
    }
    var y: f32 = 0;
    while (y < h) : (y += 100.0) {
        c.w_ImDrawList_AddLine(draw_list, .{ .x = 0, .y = y }, .{ .x = w, .y = y }, grid_col, 1.0);
    }
}

fn renderWaveform(draw_list: *c.ImDrawList, snapshot: *const ring_buffer.TickSnapshot, window_width: f32, window_height: f32) void {
    const height = window_height * 0.30;
    const count = snapshot.market_prices.len;
    
    const dx = window_width / @as(f32, @floatFromInt(count - 1));
    var points: [200]c.MyImVec2 = undefined;
    var min_p: f32 = 999999.0;
    var max_p: f32 = -999999.0;
    
    for (0..count) |i| {
        const idx = (snapshot.price_write_idx + i) % count;
        const p = @as(f32, @floatCast(snapshot.market_prices[idx]));
        if (p < min_p) min_p = p;
        if (p > max_p) max_p = p;
    }
    if (max_p == min_p) max_p = min_p + 1.0;
    
    for (0..count) |i| {
        const idx = (snapshot.price_write_idx + i) % count;
        const p = @as(f32, @floatCast(snapshot.market_prices[idx]));
        const norm = (p - min_p) / (max_p - min_p);
        points[i].x = @as(f32, @floatFromInt(i)) * dx;
        points[i].y = window_height - (norm * height * 0.8) - (height * 0.1);
    }
    
    // Draw fill
    for (0..count - 1) |i| {
        const p1 = points[i];
        const p2 = points[i + 1];
        const color_fill_top = igColor(0x00F0FF, 0.15);
        const color_fill_bot = igColor(0x00F0FF, 0.0);
        c.w_ImDrawList_AddRectFilledMultiColor(draw_list, 
            .{ .x = p1.x, .y = @min(p1.y, p2.y) }, 
            .{ .x = p2.x, .y = window_height }, 
            color_fill_top, color_fill_top, color_fill_bot, color_fill_bot);
    }

    // Draw line
    for (0..count - 1) |i| {
        const p1 = points[i];
        const p2 = points[i + 1];
        const color = igColor(0x00F0FF, 0.9);
        c.w_ImDrawList_AddLine(draw_list, p1, p2, color, 3.0);
    }
}

fn renderConstellation(draw_list: *c.ImDrawList, snapshot: *const ring_buffer.TickSnapshot, window_width: f32, window_height: f32) void {
    const spacing: f32 = 70.0;
    const grid_w: f32 = 5.0 * spacing;
    const grid_h: f32 = 5.0 * spacing;
    
    const start_x = (window_width - grid_w) / 2.0;
    const start_y = (window_height - grid_h) / 2.0 - 50.0; // Shift up slightly
    
    // Draw connecting edges
    const edge_color = igColor(0x00F0FF, 0.1);
    for (0..36) |i| {
        for (i+1..36) |j| {
            // Draw a sparse net
            if ((i + j) % 5 == 0) {
                const ix = start_x + @as(f32, @floatFromInt(i % 6)) * spacing;
                const iy = start_y + @as(f32, @floatFromInt(i / 6)) * spacing;
                const jx = start_x + @as(f32, @floatFromInt(j % 6)) * spacing;
                const jy = start_y + @as(f32, @floatFromInt(j / 6)) * spacing;
                c.w_ImDrawList_AddLine(draw_list, .{ .x = ix, .y = iy }, .{ .x = jx, .y = jy }, edge_color, 1.0);
            }
        }
    }

    for (0..36) |i| {
        const row = i / 6;
        const col = i % 6;
        const cx = start_x + @as(f32, @floatFromInt(col)) * spacing;
        const cy = start_y + @as(f32, @floatFromInt(row)) * spacing;
        
        if (snapshot.asset_frozen[i]) {
            if (g_state.frozen_frames[i] < 30.0) {
                g_state.frozen_frames[i] += 1.0;
            }
        } else {
            g_state.frozen_frames[i] = 0.0;
        }
        
        const depth = snapshot.base_depths[i];
        var radius = @as(f32, @floatCast(depth)) * 20.0 + 8.0;
        if (radius > 35.0) radius = 35.0;
        
        // Shrink to 0 over 30 frames if frozen
        const shrink_factor = 1.0 - (g_state.frozen_frames[i] / 30.0);
        radius *= shrink_factor;
        if (radius <= 0.0) continue;
        
        // Color mapping
        var col_hex: u32 = 0x00F0FF; // Cyan active
        if (depth < 0.3) {
            col_hex = 0xFF0055; // Magenta critical
        } else if (depth < 0.7) {
            col_hex = 0x7000FF; // Purple warning
        }
        
        const alpha = 0.3 + 0.7 * @as(f32, @floatCast(snapshot.volatilities[i]));
        const fill_col = igColor(col_hex, alpha);
        
        c.w_ImDrawList_AddCircleFilled(draw_list, .{ .x = cx, .y = cy }, radius + 2.0, igColor(col_hex, 0.5));
        c.w_ImDrawList_AddCircleFilled(draw_list, .{ .x = cx, .y = cy }, radius, fill_col);
        
        // Pulse ring
        if (depth < 0.3 and !snapshot.asset_frozen[i]) {
            const pulse = @as(f32, @floatCast(@mod(g_state.pulse_timer * 2.0, 1.0)));
            c.w_ImDrawList_AddCircleFilled(draw_list, .{ .x = cx, .y = cy }, radius + 5.0 + (pulse * 20.0), igColor(col_hex, (1.0 - pulse) * 0.3));
        }
    }
}

fn renderVignette(draw_list: *c.ImDrawList, snapshot: *const ring_buffer.TickSnapshot, window_width: f32, window_height: f32, dt: f32) void {
    if (snapshot.cascade_depth > 0) {
        g_state.vignette_progress += dt / 2.0; 
        if (g_state.vignette_progress > 1.0) g_state.vignette_progress = 1.0;
    } else {
        g_state.vignette_progress -= dt / 5.0; 
        if (g_state.vignette_progress < 0.0) g_state.vignette_progress = 0.0;
    }
    
    if (g_state.vignette_progress <= 0.0) return;
    
    const pulse = @as(f32, @floatCast((std.math.sin(g_state.pulse_timer * std.math.pi * 3.0) + 1.0) / 2.0));
    const alpha = g_state.vignette_progress * (0.3 + 0.2 * pulse);
    
    const color_out = igColor(0xFF0055, alpha);
    const color_in = igColor(0xFF0055, 0.0);
    
    const w = window_width;
    const h = window_height;
    const thick = 200.0;
    
    c.w_ImDrawList_AddRectFilledMultiColor(draw_list, .{ .x = 0, .y = 0 }, .{ .x = w, .y = thick }, color_out, color_out, color_in, color_in);
    c.w_ImDrawList_AddRectFilledMultiColor(draw_list, .{ .x = 0, .y = h - thick }, .{ .x = w, .y = h }, color_in, color_in, color_out, color_out);
    c.w_ImDrawList_AddRectFilledMultiColor(draw_list, .{ .x = 0, .y = 0 }, .{ .x = thick, .y = h }, color_out, color_in, color_in, color_out);
    c.w_ImDrawList_AddRectFilledMultiColor(draw_list, .{ .x = w - thick, .y = 0 }, .{ .x = w, .y = h }, color_in, color_out, color_out, color_in);
}

fn renderTelemetryPanel(draw_list: *c.ImDrawList, snapshot: *const ring_buffer.TickSnapshot, window_width: f32, window_height: f32, current_time: f64) void {
    _ = current_time;
    const font2 = c.w_GetFont(2) orelse unreachable; // 28px
    const font1 = c.w_GetFont(1) orelse unreachable; // 24px

    const hud_x: f32 = 40.0;
    const hud_y: f32 = 40.0;
    const hud_w: f32 = 350.0;
    const hud_h: f32 = 400.0;

    // HUD Background
    const bg_color = igColor(0x0A0F1A, 0.85);
    c.w_ImDrawList_AddRectFilledMultiColor(draw_list, .{ .x = hud_x, .y = hud_y }, .{ .x = hud_x + hud_w, .y = hud_y + hud_h }, bg_color, bg_color, bg_color, bg_color);

    // Title
    c.w_ImDrawList_AddText(draw_list, font2, 28.0, .{ .x = hud_x + 20.0, .y = hud_y + 20.0 }, igColor(0x00F0FF, 1.0), "KESSLER ORACLE v2.0");
    c.w_ImDrawList_AddLine(draw_list, .{ .x = hud_x + 20.0, .y = hud_y + 60.0 }, .{ .x = hud_x + hud_w - 20.0, .y = hud_y + 60.0 }, igColor(0x1C2333, 1.0), 1.0);

    var cur_y = hud_y + 80.0;
    var buf: [32]u8 = undefined;

    // TICK CLOCK
    c.w_ImDrawList_AddText(draw_list, font1, 16.0, .{ .x = hud_x + 20.0, .y = cur_y }, igColor(0x808C99, 1.0), "TICK CLOCK");
    const t_text = std.fmt.bufPrintZ(&buf, "{d}", .{snapshot.tick_number}) catch return;
    c.w_ImDrawList_AddText(draw_list, font2, 28.0, .{ .x = hud_x + 20.0, .y = cur_y + 20.0 }, igColor(0xFFFFFF, 1.0), t_text.ptr);
    cur_y += 70.0;

    // ACTIVE DEFAULTS
    c.w_ImDrawList_AddText(draw_list, font1, 16.0, .{ .x = hud_x + 20.0, .y = cur_y }, igColor(0x808C99, 1.0), "ACTIVE DEFAULTS");
    const d_text = std.fmt.bufPrintZ(&buf, "{d}", .{snapshot.total_defaults}) catch return;
    const def_col = if (snapshot.total_defaults > 0) igColor(0xFF0055, 1.0) else igColor(0xFFFFFF, 1.0);
    c.w_ImDrawList_AddText(draw_list, font2, 28.0, .{ .x = hud_x + 20.0, .y = cur_y + 20.0 }, def_col, d_text.ptr);
    cur_y += 70.0;

    // CASCADE DEPTH
    c.w_ImDrawList_AddText(draw_list, font1, 16.0, .{ .x = hud_x + 20.0, .y = cur_y }, igColor(0x808C99, 1.0), "CASCADE DEPTH");
    const c_text = std.fmt.bufPrintZ(&buf, "{d}", .{snapshot.cascade_depth}) catch return;
    const cas_col = if (snapshot.cascade_depth >= 3) igColor(0xFF0055, 1.0) else igColor(0xFFFFFF, 1.0);
    c.w_ImDrawList_AddText(draw_list, font2, 28.0, .{ .x = hud_x + 20.0, .y = cur_y + 20.0 }, cas_col, c_text.ptr);
    cur_y += 70.0;

    // MARKET SENTIMENT
    c.w_ImDrawList_AddText(draw_list, font1, 16.0, .{ .x = hud_x + 20.0, .y = cur_y }, igColor(0x808C99, 1.0), "MARKET SENTIMENT");
    const sentiment_mapped = snapshot.theta_avg;
    var s_col = igColor(0x00F0FF, 1.0); // Calm
    var s_txt: [:0]const u8 = "CALM";
    if (sentiment_mapped < 0.3) {
        s_txt = "PANIC"; s_col = igColor(0xFF0055, 1.0);
    } else if (sentiment_mapped < 0.6) {
        s_txt = "FEAR"; s_col = igColor(0xFF9900, 1.0);
    }
    c.w_ImDrawList_AddText(draw_list, font2, 28.0, .{ .x = hud_x + 20.0, .y = cur_y + 20.0 }, s_col, s_txt.ptr);

    // Hash panel bottom right
    const hash_w: f32 = 280.0;
    const hash_h: f32 = 40.0;
    const hash_x = window_width - hash_w - 20.0;
    const hash_y = window_height - hash_h - 20.0;
    c.w_ImDrawList_AddRectFilledMultiColor(draw_list, .{ .x = hash_x, .y = hash_y }, .{ .x = hash_x + hash_w, .y = hash_y + hash_h }, bg_color, bg_color, bg_color, bg_color);
    
    const h_text = std.fmt.bufPrintZ(&buf, "SEC: {x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
        snapshot.hash_first8[0], snapshot.hash_first8[1], snapshot.hash_first8[2], snapshot.hash_first8[3],
        snapshot.hash_first8[4], snapshot.hash_first8[5], snapshot.hash_first8[6], snapshot.hash_first8[7]
    }) catch return;
    c.w_ImDrawList_AddText(draw_list, font1, 14.0, .{ .x = hash_x + 10.0, .y = hash_y + 10.0 }, igColor(0x4D5566, 1.0), h_text.ptr);
}

fn renderOffline(draw_list: *c.ImDrawList, window_width: f32, window_height: f32) void {
    const font = c.w_GetFont(1) orelse unreachable;
    const font_size = 24.0;
    const text = "ENGINE OFFLINE";
    const color = igColor(0x505866, 1.0);
    const text_size = c.w_CalcTextSize(font, font_size, text);
    const pos = c.MyImVec2{
        .x = (window_width - text_size.x) / 2.0,
        .y = (window_height - text_size.y) / 2.0,
    };
    c.w_ImDrawList_AddText(draw_list, font, font_size, pos, color, text);
}
