#include "wrapper.h"
#include <imgui.h>
#include <backends/imgui_impl_glfw.h>
#include <backends/imgui_impl_opengl3.h>

extern "C" {

void* w_igCreateContext() {
    ImGuiContext* ctx = ImGui::CreateContext();
    ImGui::GetIO().IniFilename = nullptr;
    return ctx;
}

void w_igDestroyContext() {
    ImGui::DestroyContext();
}

ImFont* w_AddFont(void* font_data, int font_data_size, float size_pixels) {
    // ImGui takes ownership of the memory, so we must malloc a copy if passing from Zig embedded memory
    // Actually, Zig's @embedFile memory is static, but ImGui will try to free it unless we tell it not to.
    ImFontConfig config;
    config.FontDataOwnedByAtlas = false;
    return ImGui::GetIO().Fonts->AddFontFromMemoryTTF(font_data, font_data_size, size_pixels, &config);
}

ImFont* w_GetFont(int index) {
    return ImGui::GetIO().Fonts->Fonts[index];
}

bool w_ImGui_ImplGlfw_InitForOpenGL(GLFWwindow* window, bool install_callbacks) {
    return ImGui_ImplGlfw_InitForOpenGL(window, install_callbacks);
}
void w_ImGui_ImplGlfw_Shutdown() {
    ImGui_ImplGlfw_Shutdown();
}
void w_ImGui_ImplGlfw_NewFrame() {
    ImGui_ImplGlfw_NewFrame();
}

bool w_ImGui_ImplOpenGL3_Init(const char* glsl_version) {
    return ImGui_ImplOpenGL3_Init(glsl_version);
}
void w_ImGui_ImplOpenGL3_Shutdown() {
    ImGui_ImplOpenGL3_Shutdown();
}
void w_ImGui_ImplOpenGL3_NewFrame() {
    ImGui_ImplOpenGL3_NewFrame();
}
void w_ImGui_ImplOpenGL3_RenderDrawData(ImDrawData* draw_data) {
    ImGui_ImplOpenGL3_RenderDrawData(draw_data);
}

void w_igNewFrame() {
    ImGui::NewFrame();
}
void w_igRender() {
    ImGui::Render();
}
ImDrawData* w_igGetDrawData() {
    return ImGui::GetDrawData();
}

void w_igSetNextWindowPos(MyImVec2 pos) {
    ImGui::SetNextWindowPos(ImVec2(pos.x, pos.y));
}
void w_igSetNextWindowSize(MyImVec2 size) {
    ImGui::SetNextWindowSize(ImVec2(size.x, size.y));
}
bool w_igBegin(const char* name, int flags) {
    return ImGui::Begin(name, nullptr, flags);
}
void w_igEnd() {
    ImGui::End();
}

ImDrawList* w_igGetBackgroundDrawList() {
    return ImGui::GetBackgroundDrawList();
}
void w_ImDrawList_AddLine(ImDrawList* list, MyImVec2 p1, MyImVec2 p2, uint32_t col, float thickness) {
    list->AddLine(ImVec2(p1.x, p1.y), ImVec2(p2.x, p2.y), col, thickness);
}
void w_ImDrawList_AddCircleFilled(ImDrawList* list, MyImVec2 center, float radius, uint32_t col) {
    list->AddCircleFilled(ImVec2(center.x, center.y), radius, col);
}
void w_ImDrawList_AddText(ImDrawList* list, ImFont* font, float font_size, MyImVec2 pos, uint32_t col, const char* text) {
    list->AddText(font, font_size, ImVec2(pos.x, pos.y), col, text);
}
void w_ImDrawList_AddRectFilledMultiColor(ImDrawList* list, MyImVec2 p_min, MyImVec2 p_max, uint32_t col_upr_left, uint32_t col_upr_right, uint32_t col_bot_right, uint32_t col_bot_left) {
    list->AddRectFilledMultiColor(ImVec2(p_min.x, p_min.y), ImVec2(p_max.x, p_max.y), col_upr_left, col_upr_right, col_bot_right, col_bot_left);
}

uint32_t w_igGetColorU32(MyImVec4 col) {
    return ImGui::GetColorU32(ImVec4(col.x, col.y, col.z, col.w));
}
MyImVec2 w_CalcTextSize(ImFont* font, float size, const char* text) {
    ImVec2 s = font->CalcTextSizeA(size, FLT_MAX, 0.0f, text);
    MyImVec2 res; res.x = s.x; res.y = s.y;
    return res;
}
double w_igGetTime() {
    return ImGui::GetTime();
}

}
