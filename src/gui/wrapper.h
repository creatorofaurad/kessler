#pragma once
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct GLFWwindow GLFWwindow;
typedef struct ImDrawList ImDrawList;
typedef struct ImFont ImFont;
typedef struct ImDrawData ImDrawData;

typedef struct { float x, y; } MyImVec2;
typedef struct { float x, y, z, w; } MyImVec4;

void* w_igCreateContext();
void w_igDestroyContext();

ImFont* w_AddFont(void* font_data, int font_data_size, float size_pixels);
ImFont* w_GetFont(int index);

bool w_ImGui_ImplGlfw_InitForOpenGL(GLFWwindow* window, bool install_callbacks);
void w_ImGui_ImplGlfw_Shutdown();
void w_ImGui_ImplGlfw_NewFrame();

bool w_ImGui_ImplOpenGL3_Init(const char* glsl_version);
void w_ImGui_ImplOpenGL3_Shutdown();
void w_ImGui_ImplOpenGL3_NewFrame();
void w_ImGui_ImplOpenGL3_RenderDrawData(ImDrawData* draw_data);

void w_igNewFrame();
void w_igRender();
ImDrawData* w_igGetDrawData();

void w_igSetNextWindowPos(MyImVec2 pos);
void w_igSetNextWindowSize(MyImVec2 size);
bool w_igBegin(const char* name, int flags);
void w_igEnd();

ImDrawList* w_igGetBackgroundDrawList();
void w_ImDrawList_AddLine(ImDrawList* list, MyImVec2 p1, MyImVec2 p2, uint32_t col, float thickness);
void w_ImDrawList_AddCircleFilled(ImDrawList* list, MyImVec2 center, float radius, uint32_t col);
void w_ImDrawList_AddText(ImDrawList* list, ImFont* font, float font_size, MyImVec2 pos, uint32_t col, const char* text);
void w_ImDrawList_AddRectFilledMultiColor(ImDrawList* list, MyImVec2 p_min, MyImVec2 p_max, uint32_t col_upr_left, uint32_t col_upr_right, uint32_t col_bot_right, uint32_t col_bot_left);

uint32_t w_igGetColorU32(MyImVec4 col);
MyImVec2 w_CalcTextSize(ImFont* font, float size, const char* text);
double w_igGetTime();

#ifdef __cplusplus
}
#endif
