import sys
import csv
import random
import math
import pygame
import numpy as np
import moderngl

pygame.init()

# --- Constants ---
DEFAULT_WINDOW_WIDTH = 900
DEFAULT_WINDOW_HEIGHT = 700
FPS = 60

HOLE_COUNT = 6

# Colors
WHITE = (255, 255, 255)
BLACK = (0, 0, 0)
GRAY = (180, 180, 180)
DARK_GRAY = (50, 50, 50)
YELLOW = (255, 255, 0)
LIGHT_GREEN = (150, 255, 150)
LIGHT_RED = (255, 150, 150)
RED_WARNING = (220, 20, 60)
GREEN_BAR = (50, 205, 50)
YELLOW_BAR = (255, 215, 0)

PLAYER_COLORS = [
    (220, 20, 60), (30, 144, 255), (34, 139, 34), (255, 215, 0)
]

category_colors = {
    "Sport": (0, 200, 0), "History": (139, 69, 19), "Music": (128, 0, 128),
    "Science": (0, 255, 255), "Art": (255, 192, 203), "Random": (128, 128, 128),
}

AUDIO_FILE = "shadertoy.mp3"

# -----------------------------
# Galaxy shader background renderer (ModernGL + audio FFT -> iChannel0)
# -----------------------------
FSQ_VERT = r"""
#version 330
in vec2 in_pos;
in vec2 in_uv;
out vec2 v_uv;
void main() {
    v_uv = in_uv;
    gl_Position = vec4(in_pos, 0.0, 1.0);
}
"""

GALAXY_FRAG = r"""
#version 330
uniform float iTime;
uniform vec3  iResolution;    // (w, h, 1)
uniform sampler2D iChannel0;  // audio FFT texture (R8)

in vec2 v_uv;
out vec4 fragColor;

// http://www.fractalforums.com/new-theories-and-research/very-simple-formula-for-fractal-patterns/
float field(in vec3 p,float s) {
    float strength = 7. + .03 * log(1.e-6 + fract(sin(iTime) * 4373.11));
    float accum = s/4.;
    float prev = 0.;
    float tw = 0.;
    for (int i = 0; i < 26; ++i) {
        float mag = dot(p, p);
        p = abs(p) / mag + vec3(-.5, -.4, -1.5);
        float w = exp(-float(i) / 7.);
        accum += w * exp(-strength * pow(abs(mag - prev), 2.2));
        tw += w;
        prev = mag;
    }
    return max(0., 5. * accum / tw - .7);
}

float field2(in vec3 p, float s) {
    float strength = 7. + .03 * log(1.e-6 + fract(sin(iTime) * 4373.11));
    float accum = s/4.;
    float prev = 0.;
    float tw = 0.;
    for (int i = 0; i < 18; ++i) {
        float mag = dot(p, p);
        p = abs(p) / mag + vec3(-.5, -.4, -1.5);
        float w = exp(-float(i) / 7.);
        accum += w * exp(-strength * pow(abs(mag - prev), 2.2));
        tw += w;
        prev = mag;
    }
    return max(0., 5. * accum / tw - .7);
}

vec3 nrand3(vec2 co) {
    vec3 a = fract( cos( co.x*8.3e-3 + co.y )*vec3(1.3e5, 4.7e5, 2.9e5) );
    vec3 b = fract( sin( co.x*0.3e-3 + co.y )*vec3(8.1e5, 1.0e5, 0.1e5) );
    return mix(a, b, 0.5);
}

void main() {
    vec2 fragCoord = v_uv * iResolution.xy;

    vec2 uv = 2. * fragCoord.xy / iResolution.xy - 1.;
    vec2 uvs = uv * iResolution.xy / max(iResolution.x, iResolution.y);

    vec3 p = vec3(uvs / 4., 0.) + vec3(1., -1.3, 0.);
    p += .2 * vec3(sin(iTime / 16.), sin(iTime / 12.),  sin(iTime / 128.));

    float freqs[4];
    // Sound (FFT texture)
    freqs[0] = texture(iChannel0, vec2(0.01, 0.25)).r;
    freqs[1] = texture(iChannel0, vec2(0.07, 0.25)).r;
    freqs[2] = texture(iChannel0, vec2(0.15, 0.25)).r;
    freqs[3] = texture(iChannel0, vec2(0.30, 0.25)).r;

    // Make it "move" even on quiet bits
    float bass = pow(freqs[0], 0.6);
    float mid  = pow(freqs[1], 0.8);
    float hi   = pow(freqs[3], 0.9);

    float t = field(p, freqs[2] + 0.08 + 0.35 * mid);
    float v = (1. - exp((abs(uv.x) - 1.) * 6.)) * (1. - exp((abs(uv.y) - 1.) * 6.));

    // Second layer
    vec3 p2 = vec3(uvs / (4.+sin(iTime*0.11)*0.2+0.2+sin(iTime*0.15)*0.3+0.4), 1.5) + vec3(2., -1.3, -1.);
    p2 += 0.25 * vec3(sin(iTime / 16.), sin(iTime / 12.),  sin(iTime / 128.));
    float t2 = field2(p2, freqs[3] + 0.10 + 0.45 * hi);

    vec4 c2 = mix(.4, 1., v) * vec4(1.3 * t2 * t2 * t2,
                                    1.8 * t2 * t2,
                                    t2 * (freqs[0] + 0.15 + 0.6*bass),
                                    t2);

    // Stars
    vec2 seed = p.xy * 2.0;
    seed = floor(seed * iResolution.x);
    vec3 rnd = nrand3(seed);
    vec4 starcolor = vec4(pow(rnd.y,40.0));

    vec2 seed2 = p2.xy * 2.0;
    seed2 = floor(seed2 * iResolution.x);
    vec3 rnd2 = nrand3(seed2);
    starcolor += vec4(pow(rnd2.y,40.0));

    fragColor = mix(freqs[3]-.3, 1., v) * vec4(1.5*freqs[2] * t * t* t ,
                                               1.2*freqs[1] * t * t,
                                               freqs[3]*t, 1.0)
                + c2 + starcolor;
}
"""

OVERLAY_FRAG = r"""
#version 330
uniform sampler2D src;
in vec2 v_uv;
out vec4 fragColor;
void main() {
    fragColor = texture(src, v_uv);
}
"""

class GalaxyRenderer:
    def __init__(self, win_w: int, win_h: int, audio_file: str):
        # ---- audio ----
        pygame.mixer.pre_init(44100, -16, 2, 512)
        pygame.mixer.init()

        try:
            pygame.mixer.music.load(audio_file)
            pygame.mixer.music.play(-1)
        except Exception as e:
            raise RuntimeError(
                f"[AUDIO] Can't load/play {audio_file}: {e}\n"
                f"Put {audio_file} next to the script. If mp3 decode is flaky, convert to WAV."
            )

        try:
            snd = pygame.mixer.Sound(audio_file)
            arr = pygame.sndarray.array(snd)
        except Exception as e:
            raise RuntimeError(
                f"[AUDIO] Can't decode samples for FFT from {audio_file}: {e}\n"
                f"Convert to WAV (shadertoy.wav) and update AUDIO_FILE."
            )

        mix_init = pygame.mixer.get_init()
        if not mix_init:
            raise RuntimeError("pygame.mixer not initialized")
        self.sample_rate, _fmt, ch = mix_init

        if arr.ndim == 2:
            mono = arr.astype(np.float32).mean(axis=1)
        else:
            mono = arr.astype(np.float32)
        mono *= (1.0 / 32768.0)
        self.mono = mono
        self.total_samples = mono.shape[0]

        # ---- FFT parameters ----
        self.FFT_TEX_W = 512
        self.FFT_TEX_H = 2
        self.FFT_WINDOW = 4096
        self.FFT_SMOOTH = 0.25
        self.prev_fft = np.zeros(self.FFT_TEX_W, dtype=np.float32)

        # ---- GL ----
        self.ctx = moderngl.create_context(require=330)
        self.ctx.enable(moderngl.BLEND)
        self.ctx.blend_func = (moderngl.SRC_ALPHA, moderngl.ONE_MINUS_SRC_ALPHA)

        quad = np.array([
            -1.0, -1.0,  0.0, 0.0,
             1.0, -1.0,  1.0, 0.0,
            -1.0,  1.0,  0.0, 1.0,
             1.0,  1.0,  1.0, 1.0,
        ], dtype="f4")
        self.vbo = self.ctx.buffer(quad.tobytes())

        self.bg_prog = self.ctx.program(vertex_shader=FSQ_VERT, fragment_shader=GALAXY_FRAG)
        self.bg_vao = self.ctx.vertex_array(self.bg_prog, [(self.vbo, "2f 2f", "in_pos", "in_uv")])

        self.ov_prog = self.ctx.program(vertex_shader=FSQ_VERT, fragment_shader=OVERLAY_FRAG)
        self.ov_vao = self.ctx.vertex_array(self.ov_prog, [(self.vbo, "2f 2f", "in_pos", "in_uv")])
        self.ov_prog["src"].value = 0

        # audio texture
        self.audio_tex = self.ctx.texture((self.FFT_TEX_W, self.FFT_TEX_H), components=1, dtype="f1")
        self.audio_tex.filter = (moderngl.LINEAR, moderngl.LINEAR)
        self.audio_tex.repeat_x = False
        self.audio_tex.repeat_y = False
        self.bg_prog["iChannel0"].value = 1  # texture unit 1

        # overlay texture (RGBA8)
        self.overlay_tex = None
        self.resize(win_w, win_h)

    def resize(self, win_w: int, win_h: int):
        self.win_w = int(win_w)
        self.win_h = int(win_h)

        # update shader resolution
        self.bg_prog["iResolution"].value = (float(self.win_w), float(self.win_h), 1.0)

        # recreate overlay texture to match window size
        if self.overlay_tex is not None:
            self.overlay_tex.release()
        self.overlay_tex = self.ctx.texture((self.win_w, self.win_h), components=4, dtype="f1")
        self.overlay_tex.filter = (moderngl.LINEAR, moderngl.LINEAR)
        self.overlay_tex.repeat_x = False
        self.overlay_tex.repeat_y = False

        # new software overlay surface (draw everything here)
        self.overlay_surface = pygame.Surface((self.win_w, self.win_h), pygame.SRCALPHA)

    def _build_fft_row(self, play_time_sec: float) -> np.ndarray:
        center = int(play_time_sec * self.sample_rate) % self.total_samples
        half = self.FFT_WINDOW // 2
        start = center - half
        end = center + half

        if start < 0:
            window = np.concatenate([self.mono[start:], self.mono[:end]])
        elif end > self.total_samples:
            window = np.concatenate([self.mono[start:], self.mono[:(end - self.total_samples)]])
        else:
            window = self.mono[start:end]

        if window.shape[0] != self.FFT_WINDOW:
            window = np.pad(window, (0, max(0, self.FFT_WINDOW - window.shape[0])))

        window = window.astype(np.float32) * np.hanning(self.FFT_WINDOW).astype(np.float32)

        spec = np.fft.rfft(window)
        mag = np.abs(spec).astype(np.float32)
        mag = np.log1p(mag)

        mmax = float(mag.max() + 1e-6)
        mag = mag / mmax

        take = max(32, int(mag.shape[0] * 0.35))
        src_x = np.linspace(0.0, 1.0, take, endpoint=True)
        dst_x = np.linspace(0.0, 1.0, self.FFT_TEX_W, endpoint=True)
        out = np.interp(dst_x, src_x, mag[:take]).astype(np.float32)

        out = np.clip(out * 1.25, 0.0, 1.0)
        out = np.sqrt(out)
        return out

    def _update_audio_tex(self, t: float):
        pos_ms = pygame.mixer.music.get_pos()
        play_time = (pos_ms / 1000.0) if pos_ms >= 0 else t

        fft_now = self._build_fft_row(play_time)
        self.prev_fft = (1.0 - self.FFT_SMOOTH) * self.prev_fft + self.FFT_SMOOTH * fft_now

        fft_bytes = (np.clip(self.prev_fft, 0.0, 1.0) * 255.0).astype(np.uint8)
        audio_img = np.zeros((self.FFT_TEX_H, self.FFT_TEX_W), dtype=np.uint8)
        audio_img[0, :] = fft_bytes
        audio_img[1, :] = fft_bytes
        self.audio_tex.write(audio_img.tobytes())

    def present(self, t: float):
        # upload overlay surface into GL texture
        # NOTE: flip vertically so uv matches
        rgba = pygame.image.tostring(self.overlay_surface, "RGBA", True)
        self.overlay_tex.write(rgba)

        self._update_audio_tex(t)

        # render background to screen
        self.ctx.screen.use()
        self.ctx.viewport = (0, 0, self.win_w, self.win_h)

        self.bg_prog["iTime"].value = float(t)
        self.audio_tex.use(location=1)
        self.bg_vao.render(mode=moderngl.TRIANGLE_STRIP)

        # render overlay on top
        self.overlay_tex.use(location=0)
        self.ov_vao.render(mode=moderngl.TRIANGLE_STRIP)

        pygame.display.flip()


# --- Classes ---
class Player:
    def __init__(self, name, color_id):
        self.name = name
        self.color = PLAYER_COLORS[color_id]
        self.color_id = color_id
        self.score = 0

class Pawn:
    def __init__(self, player, row, col, is_flag=False):
        self.player = player
        self.row = row
        self.col = col
        self.is_flag = is_flag
        self.anim_x = 0
        self.anim_y = 0

class Cell:
    def __init__(self, category="", is_hole=False):
        self.rect = pygame.Rect(0, 0, 60, 60)
        self.is_hole = is_hole
        self.pawn = None
        self.category = category

class Button:
    def __init__(self, rel_x, rel_y, w, h, text, color, hover_color, action=None):
        self.rel_x = rel_x
        self.rel_y = rel_y
        self.rect = pygame.Rect(0, 0, w, h)
        self.text = text
        self.color = color
        self.hover_color = hover_color
        self.action = action
        self.is_hovered = False

    def update_pos(self, screen_w, screen_h):
        self.rect.centerx = screen_w // 2 + self.rel_x
        self.rect.centery = screen_h // 2 + self.rel_y

    def draw(self, screen, font, glitch_offset=(0,0)):
        draw_color = self.hover_color if self.is_hovered else self.color
        gx, gy = glitch_offset
        draw_rect = self.rect.move(gx, gy)

        pygame.draw.rect(screen, (245, 235, 220, 255), draw_rect, border_radius=8)
        pygame.draw.rect(screen, (*draw_color, 255), draw_rect.inflate(-6, -6), border_radius=4)
        pygame.draw.rect(screen, (20, 20, 20, 255), draw_rect, 2, border_radius=8)

        text_surf = font.render(self.text, True, (20, 20, 20))
        text_rect = text_surf.get_rect(center=draw_rect.center)
        if abs(gx) > 2:
            text_rect.x += random.randint(-2, 2)
        screen.blit(text_surf, text_rect)

    def check_hover(self, mouse_pos):
        self.is_hovered = self.rect.collidepoint(mouse_pos)

    def check_click(self, mouse_pos):
        if self.is_hovered and self.action:
            self.action()

# --- Assets ---
def create_placeholder_pawn():
    surf = pygame.Surface((40, 40), pygame.SRCALPHA)
    pygame.draw.circle(surf, (200, 200, 200), (20, 20), 18)
    pygame.draw.circle(surf, BLACK, (20, 20), 18, 2)
    pygame.draw.circle(surf, (255, 255, 255), (15, 15), 5)
    return surf

def create_placeholder_flag():
    surf = pygame.Surface((40, 40), pygame.SRCALPHA)
    pygame.draw.line(surf, (100, 100, 100), (10, 35), (10, 5), 3)
    pygame.draw.polygon(surf, (200, 50, 50), [(10, 5), (35, 12), (10, 20)])
    return surf

def colorize(surface, new_color):
    colored_image = surface.copy()
    colored_image.fill((0, 0, 0, 255), special_flags=pygame.BLEND_RGBA_MULT)
    colored_image.fill(new_color[0:3] + (0,), special_flags=pygame.BLEND_RGBA_ADD)
    return colored_image

def load_assets():
    try:
        pawn_img = pygame.image.load("pawn.png").convert_alpha()
        flag_img = pygame.image.load("flag.png").convert_alpha()
    except pygame.error:
        print("Images not found. Using generated placeholders.")
        pawn_img = create_placeholder_pawn()
        flag_img = create_placeholder_flag()
    pawn_img = pygame.transform.scale(pawn_img, (40, 40))
    flag_img = pygame.transform.scale(flag_img, (40, 40))
    return pawn_img, flag_img

# --- Data ---
def load_questions_from_csv(filename):
    questions_by_category = {}
    try:
        with open(filename, mode="r", encoding="utf-8") as f:
            reader = csv.reader(f)
            for row in reader:
                if len(row) < 5:
                    continue
                category, question, correct, w1, w2, w3 = row
                category = category.strip()
                if category not in questions_by_category:
                    questions_by_category[category] = []
                questions_by_category[category].append(
                    {"question": question, "correct": correct, "wrong": [w1, w2, w3]}
                )
    except FileNotFoundError:
        print(f"Warning: File '{filename}' not found.")
    return questions_by_category

questions_by_category = load_questions_from_csv("questions.csv")

def get_random_question_any():
    if not questions_by_category:
        return None
    all_cats = list(questions_by_category.keys())
    category = random.choice(all_cats)
    if not questions_by_category[category]:
        return None
    return random.choice(questions_by_category[category])

def get_random_question_from(category):
    if category in questions_by_category and questions_by_category[category]:
        return random.choice(questions_by_category[category])
    return get_random_question_any()

# --- UI helpers ---
def draw_dim_panel(screen, alpha=130):
    w, h = screen.get_size()
    dim = pygame.Surface((w, h), pygame.SRCALPHA)
    dim.fill((0, 0, 0, alpha))
    screen.blit(dim, (0, 0))

def show_feedback(renderer: GalaxyRenderer, correct: bool):
    screen = renderer.overlay_surface
    screen.fill((0, 0, 0, 0))
    draw_dim_panel(screen, 120)

    w, h = screen.get_size()
    feedback_rect = pygame.Rect(0, 0, 420, 320)
    feedback_rect.center = (w//2, h//2)

    panel = pygame.Surface((feedback_rect.w, feedback_rect.h), pygame.SRCALPHA)
    panel.fill((245, 245, 245, 240))
    screen.blit(panel, feedback_rect.topleft)
    pygame.draw.rect(screen, (10, 10, 10, 255), feedback_rect, 3, border_radius=12)

    big_font = pygame.font.SysFont(None, 200)
    text_surf = big_font.render("✓", True, (0, 200, 0)) if correct else big_font.render("X", True, (200, 0, 0))
    screen.blit(text_surf, text_surf.get_rect(center=feedback_rect.center))

    renderer.present(pygame.time.get_ticks() * 0.001)

    start_time = pygame.time.get_ticks()
    while True:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                pygame.quit(); sys.exit()
        if pygame.time.get_ticks() - start_time > 900:
            break

def ask_question_from_category(renderer: GalaxyRenderer, font, category, time_limit):
    qdata = get_random_question_from(category)
    if not qdata:
        return None

    question_text = qdata["question"]
    correct_answer = qdata["correct"]
    wrong_answers = qdata["wrong"]
    answers = [correct_answer] + wrong_answers
    random.shuffle(answers)

    screen = renderer.overlay_surface
    w, h = screen.get_size()

    question_box = pygame.Rect(0, 0, 640, 340)
    if w < 740:
        question_box.width = w - 60
    question_box.centerx = w // 2
    question_box.y = 90

    margin = 20
    chosen_answer = None
    answer_rects = []
    clock = pygame.time.Clock()
    start_ticks = pygame.time.get_ticks()

    bar_width = min(520, w - 80)
    bar_height = 25
    bar_x = (w - bar_width) // 2
    bar_y = 40

    while True:
        # events first
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                pygame.quit(); sys.exit()
            elif event.type == pygame.VIDEORESIZE:
                _reset_gl_window(renderer, event.w, event.h)
                screen = renderer.overlay_surface
                w, h = screen.get_size()

            elif event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
                mx, my = pygame.mouse.get_pos()
                for rect, ans_text in answer_rects:
                    if rect.collidepoint(mx, my):
                        chosen_answer = ans_text
                        return chosen_answer == correct_answer

        # time
        seconds_passed = (pygame.time.get_ticks() - start_ticks) / 1000.0
        time_left = max(0.0, time_limit - seconds_passed)
        if time_left <= 0.0:
            return False

        # draw
        screen.fill((0, 0, 0, 0))
        draw_dim_panel(screen, 150)

        pct = time_left / time_limit
        fill_width = int(bar_width * pct)
        bar_color = GREEN_BAR if pct > 0.5 else (YELLOW_BAR if pct > 0.2 else RED_WARNING)

        pygame.draw.rect(screen, (180, 180, 180, 220), (bar_x, bar_y, bar_width, bar_height), border_radius=6)
        pygame.draw.rect(screen, (*bar_color, 255), (bar_x, bar_y, fill_width, bar_height), border_radius=6)
        pygame.draw.rect(screen, (10, 10, 10, 255), (bar_x, bar_y, bar_width, bar_height), 2, border_radius=6)

        panel = pygame.Surface((question_box.w, question_box.h), pygame.SRCALPHA)
        panel.fill((245, 245, 245, 240))
        screen.blit(panel, question_box.topleft)
        pygame.draw.rect(screen, (10, 10, 10, 255), question_box, 3, border_radius=12)

        # word wrap
        words = question_text.split(' ')
        lines = []
        current = ""
        for word in words:
            if font.size(current + word)[0] < question_box.width - 2 * margin:
                current += word + " "
            else:
                lines.append(current)
                current = word + " "
        lines.append(current)

        y_offset = question_box.y + margin
        for line in lines:
            screen.blit(font.render(line, True, (10, 10, 10)), (question_box.x + margin, y_offset))
            y_offset += 30

        answer_rects.clear()
        start_y = y_offset + 18
        for i, ans in enumerate(answers):
            ans_surf = font.render(f"{chr(65+i)}: {ans}", True, (10, 10, 10))
            ans_rect = ans_surf.get_rect()
            ans_rect.topleft = (question_box.x + margin, start_y + i * 40)
            screen.blit(ans_surf, ans_rect)
            answer_rects.append((ans_rect, ans))

        renderer.present(pygame.time.get_ticks() * 0.001)
        clock.tick(FPS)

def ask_two_questions_from_category(renderer: GalaxyRenderer, font, category, time_limit):
    for _ in range(2):
        result = ask_question_from_category(renderer, font, category, time_limit)
        if result is None or not result:
            return False
    return True

# --- Game Logic ---
def place_random_holes(board, rows, cols, hole_count=HOLE_COUNT):
    free_positions = []
    for r in range(rows):
        for c in range(cols):
            if board[r][c].pawn is None:
                free_positions.append((r, c))
    if hole_count > len(free_positions):
        hole_count = len(free_positions)
    chosen = random.sample(free_positions, hole_count)
    for r, c in chosen:
        board[r][c].is_hole = True

def get_valid_moves(board, selected_pawn, rows, cols):
    directions = [(0, 1), (0, -1), (1, 0), (-1, 0)]
    valid_moves = []
    r, c = selected_pawn.row, selected_pawn.col
    for dr, dc in directions:
        nr, nc = r + dr, c + dc
        if 0 <= nr < rows and 0 <= nc < cols:
            cell = board[nr][nc]
            if not cell.is_hole:
                if not (cell.pawn and cell.pawn.player == selected_pawn.player):
                    valid_moves.append((nr, nc))
    return valid_moves

def draw_legend(screen, font, x_start, y_start):
    screen.blit(font.render("Legend", True, WHITE), (x_start + 70, y_start))
    y_offset = y_start + 35

    for cat, color in category_colors.items():
        color_box = pygame.Rect(x_start, y_offset, 20, 20)
        pygame.draw.rect(screen, (*color, 255), color_box)
        pygame.draw.rect(screen, (*WHITE, 255), color_box, 1)
        screen.blit(font.render(cat, True, WHITE), (x_start + 30, y_offset))
        y_offset += 25

    y_offset += 20
    for label, color in [("Selected", YELLOW), ("Move Empty", LIGHT_GREEN), ("Attack", LIGHT_RED), ("Hole", WHITE)]:
        color_box = pygame.Rect(x_start, y_offset, 20, 20)
        pygame.draw.rect(screen, (*color, 255), color_box)
        pygame.draw.rect(screen, (*WHITE, 255), color_box, 1)
        screen.blit(font.render(label, True, WHITE), (x_start + 30, y_offset))
        y_offset += 25

def draw_current_player_display(screen, font, current_player, icon_map, x_start, y_start):
    screen.blit(font.render("Current Turn", True, WHITE), (x_start + 70, y_start))
    pawn_surf = icon_map.get((current_player, False))
    if pawn_surf:
        large_icon = pygame.transform.scale(pawn_surf, (100, 100))
        icon_rect = large_icon.get_rect(center=(x_start + 100, y_start + 110))
        screen.blit(large_icon, icon_rect)

    name_font = pygame.font.SysFont("Arial", 30, bold=True)
    name_surf = name_font.render(current_player.name, True, current_player.color)
    screen.blit(name_surf, name_surf.get_rect(center=(x_start + 100, y_start + 200)))

    score_surf = pygame.font.SysFont("Arial", 24).render(f"Score: {current_player.score}", True, WHITE)
    screen.blit(score_surf, score_surf.get_rect(center=(x_start + 100, y_start + 240)))

def setup_players_and_pawns(num_players, board_size):
    players = []
    pawns = []
    corners = [(0, 0), (board_size-1, board_size-1), (0, board_size-1), (board_size-1, 0)]
    base_offsets = [(0, 0), (1, 0), (0, 1), (1, 1), (2, 0), (0, 2)]

    for i in range(num_players):
        p = Player(f"Player {i+1}", i)
        players.append(p)
        corner_r, corner_c = corners[i]
        for j, (dr, dc) in enumerate(base_offsets):
            is_flag = (j == 0)
            if i == 0:
                r, c = corner_r + dr, corner_c + dc
            elif i == 1:
                r, c = corner_r - dr, corner_c - dc
            elif i == 2:
                r, c = corner_r + dr, corner_c - dc
            else:
                r, c = corner_r - dr, corner_c + dc
            if 0 <= r < board_size and 0 <= c < board_size:
                pawns.append(Pawn(p, r, c, is_flag))
    return players, pawns

# --- GL window reset helper ---
def _reset_gl_window(renderer: GalaxyRenderer, w: int, h: int):
    pygame.display.gl_set_attribute(pygame.GL_CONTEXT_MAJOR_VERSION, 3)
    pygame.display.gl_set_attribute(pygame.GL_CONTEXT_MINOR_VERSION, 3)
    pygame.display.gl_set_attribute(pygame.GL_CONTEXT_PROFILE_MASK, pygame.GL_CONTEXT_PROFILE_CORE)
    pygame.display.gl_set_attribute(pygame.GL_DOUBLEBUFFER, 1)
    try:
        pygame.display.set_mode((w, h), pygame.OPENGL | pygame.DOUBLEBUF | pygame.RESIZABLE, vsync=0)
    except TypeError:
        pygame.display.set_mode((w, h), pygame.OPENGL | pygame.DOUBLEBUF | pygame.RESIZABLE)
    renderer.resize(w, h)

# --- Screens ---
def splash_screen(renderer: GalaxyRenderer, clock, font):
    screen = renderer.overlay_surface
    running = True
    while running:
        w, h = screen.get_size()
        screen.fill((0, 0, 0, 0))
        draw_dim_panel(screen, 110)

        title_surf = font.render("TRIVIA STRATEGY", True, WHITE)
        title_rect = title_surf.get_rect(center=(w//2, h//2 - 50))
        screen.blit(title_surf, title_rect)

        sub_surf = pygame.font.SysFont("Arial", 24).render("Capture the Flag", True, (200, 200, 200))
        sub_rect = sub_surf.get_rect(center=(w//2, h//2 + 20))
        screen.blit(sub_surf, sub_rect)

        instr_surf = pygame.font.SysFont("Arial", 20).render("Click anywhere to start", True, YELLOW)
        instr_rect = instr_surf.get_rect(center=(w//2, h//2 + 80))
        screen.blit(instr_surf, instr_rect)

        renderer.present(pygame.time.get_ticks() * 0.001)

        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                pygame.quit(); sys.exit()
            elif event.type == pygame.MOUSEBUTTONDOWN:
                running = False
            elif event.type == pygame.VIDEORESIZE:
                _reset_gl_window(renderer, event.w, event.h)
                screen = renderer.overlay_surface

        clock.tick(FPS)

def menu_loop(renderer: GalaxyRenderer, clock, title_font, option_font):
    num_players = 2
    time_limit = 30
    board_size = 8
    running = True

    def change_players(val):
        nonlocal num_players
        num_players = max(2, min(4, num_players + val))

    def change_time(val):
        nonlocal time_limit
        time_limit = max(5, min(120, time_limit + val))

    def change_board(val):
        nonlocal board_size
        board_size = max(6, min(32, board_size + val))

    def start_game():
        nonlocal running
        running = False

    buttons = [
        Button(-100, -120, 50, 50, "-", (20, 20, 20), (200, 50, 50), lambda: change_players(-1)),
        Button(100, -120, 50, 50, "+", (20, 20, 20), (200, 50, 50), lambda: change_players(1)),
        Button(-100, -40, 50, 50, "-", (20, 20, 20), (200, 50, 50), lambda: change_time(-5)),
        Button(100, -40, 50, 50, "+", (20, 20, 20), (200, 50, 50), lambda: change_time(5)),
        Button(-100, 40, 50, 50, "-", (20, 20, 20), (200, 50, 50), lambda: change_board(-1)),
        Button(100, 40, 50, 50, "+", (20, 20, 20), (200, 50, 50), lambda: change_board(1)),
        Button(-80, 130, 160, 60, "PLAY", (50, 50, 200), (100, 149, 237), start_game),
    ]
    base_pawn_img, base_flag_img = load_assets()

    screen = renderer.overlay_surface
    while running:
        w, h = screen.get_size()
        screen.fill((0, 0, 0, 0))
        draw_dim_panel(screen, 105)

        mouse_pos = pygame.mouse.get_pos()
        for btn in buttons:
            btn.update_pos(w, h)

        ticks = pygame.time.get_ticks()
        glitch_x, glitch_y = (0, 0)
        if ticks % 60 == 0 and random.random() < 0.3:
            glitch_x, glitch_y = random.randint(-4, 4), random.randint(-2, 2)

        title_surf = title_font.render("MAIN MENU", True, WHITE)
        title_rect = title_surf.get_rect(center=(w//2 + glitch_x, h//2 - 200 + glitch_y))
        if glitch_x != 0:
            screen.blit(title_font.render("MAIN MENU", True, (255, 0, 0)), (title_rect.x + 4, title_rect.y))
            screen.blit(title_font.render("MAIN MENU", True, (0, 255, 255)), (title_rect.x - 4, title_rect.y))
        screen.blit(title_surf, title_rect)

        lbl_surf = option_font.render("Number of Players:", True, WHITE)
        screen.blit(lbl_surf, lbl_surf.get_rect(center=(w//2 + glitch_x, h//2 - 150 + glitch_y)))
        num_surf = title_font.render(str(num_players), True, WHITE)
        screen.blit(num_surf, num_surf.get_rect(center=(w//2, h//2 - 120)))

        lbl_time_surf = option_font.render("Time (sec):", True, WHITE)
        screen.blit(lbl_time_surf, lbl_time_surf.get_rect(center=(w//2 + glitch_x, h//2 - 70 + glitch_y)))
        time_surf = title_font.render(str(time_limit), True, WHITE)
        screen.blit(time_surf, time_surf.get_rect(center=(w//2, h//2 - 40)))

        lbl_board_surf = option_font.render(f"Board Size ({board_size}x{board_size}):", True, WHITE)
        screen.blit(lbl_board_surf, lbl_board_surf.get_rect(center=(w//2 + glitch_x, h//2 + 10 + glitch_y)))
        board_surf = title_font.render(str(board_size), True, WHITE)
        screen.blit(board_surf, board_surf.get_rect(center=(w//2, h//2 + 40)))

        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                pygame.quit(); sys.exit()
            elif event.type == pygame.VIDEORESIZE:
                _reset_gl_window(renderer, event.w, event.h)
                screen = renderer.overlay_surface
            elif event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
                for btn in buttons:
                    btn.check_click(mouse_pos)

        for btn in buttons:
            btn.check_hover(mouse_pos)
            btn.draw(screen, option_font, (glitch_x, glitch_y))

        renderer.present(pygame.time.get_ticks() * 0.001)
        clock.tick(FPS)

    return num_players, time_limit, board_size, base_pawn_img, base_flag_img

def main_game_real(renderer: GalaxyRenderer, clock, font, num_players, time_limit, board_size, base_pawn_img, base_flag_img):
    players, pawns = setup_players_and_pawns(num_players, board_size)

    icon_map = {}
    for p in players:
        pawn_col = colorize(base_pawn_img, p.color)
        flag_col = colorize(base_flag_img, p.color)
        flag_light = colorize(flag_col, (50, 50, 50))
        icon_map[(p, False)] = pawn_col
        icon_map[(p, True)] = flag_light

    current_player_index = 0
    selected_pawn = None
    running = True

    move_anim = {
        'active': False,
        'pawn': None,
        'start_pos': (0,0),
        'end_pos': (0,0),
        'start_ticks': 0,
        'turn_done': False
    }
    ANIM_DURATION = 300

    board_data = [[Cell() for _ in range(board_size)] for _ in range(board_size)]

    # --- BOARD CREATION ---
    all_cats = list(category_colors.keys())
    for r in range(board_size):
        for c in range(board_size):
            cat_index = (r + c) % len(all_cats)
            board_data[r][c].category = all_cats[cat_index]

    for p in pawns:
        board_data[p.row][p.col].pawn = p
    place_random_holes(board_data, board_size, board_size, HOLE_COUNT)

    screen = renderer.overlay_surface
    while running:
        w, h = screen.get_size()
        screen.fill((0, 0, 0, 0))
        draw_dim_panel(screen, 70)

        margin_x = 240 + 240
        margin_y = 180 + 50
        available_w = max(50, w - margin_x)
        available_h = max(50, h - margin_y)
        cell_size = int(min(available_w / board_size, available_h / board_size))
        start_x = (w - (board_size * cell_size)) // 2
        start_y = (h - (board_size * cell_size)) // 2
        pawn_size = int(cell_size * 0.7)

        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                pygame.quit(); sys.exit()
            elif event.type == pygame.VIDEORESIZE:
                _reset_gl_window(renderer, event.w, event.h)
                screen = renderer.overlay_surface

            # --- INPUT HANDLING ---
            if (not move_anim['active']
                and event.type == pygame.MOUSEBUTTONDOWN
                and event.button == 1):
                mx, my = pygame.mouse.get_pos()
                current_player = players[current_player_index]

                if not selected_pawn:
                    for r in range(board_size):
                        for c in range(board_size):
                            cell_rect = pygame.Rect(start_x + c * cell_size, start_y + r * cell_size, cell_size, cell_size)
                            cell = board_data[r][c]
                            if cell_rect.collidepoint(mx, my) and cell.pawn:
                                if cell.pawn.player == current_player:
                                    selected_pawn = cell.pawn
                                    break
                        else:
                            continue
                        break
                else:
                    for r in range(board_size):
                        for c in range(board_size):
                            cell_rect = pygame.Rect(start_x + c * cell_size, start_y + r * cell_size, cell_size, cell_size)
                            cell = board_data[r][c]
                            if cell_rect.collidepoint(mx, my):
                                if abs(selected_pawn.row - r) + abs(selected_pawn.col - c) == 1:
                                    if cell.is_hole:
                                        selected_pawn = None
                                        break

                                    if not cell.pawn:
                                        # MOVE
                                        result = ask_question_from_category(renderer, font, cell.category, time_limit)
                                        if result:
                                            board_data[selected_pawn.row][selected_pawn.col].pawn = None
                                            selected_pawn.row, selected_pawn.col = r, c
                                            cell.pawn = selected_pawn
                                            current_player.score += 1

                                            # animation (optional; kept as in original, but end_pos wasn't set)
                                            move_anim['pawn'] = selected_pawn
                                            move_anim['start_pos'] = (cell_rect.centerx, cell_rect.centery)
                                            move_anim['end_pos'] = (cell_rect.centerx, cell_rect.centery)
                                            move_anim['active'] = True
                                            move_anim['start_ticks'] = pygame.time.get_ticks()
                                            move_anim['turn_done'] = False

                                            selected_pawn = None
                                            show_feedback(renderer, True)
                                        else:
                                            show_feedback(renderer, False)
                                            selected_pawn = None
                                            current_player_index = (current_player_index + 1) % len(players)
                                    else:
                                        # ATTACK
                                        occupant = cell.pawn
                                        if occupant.player != current_player:
                                            success = ask_two_questions_from_category(renderer, font, cell.category, time_limit)
                                            if success:
                                                board_data[occupant.row][occupant.col].pawn = None
                                                if occupant in pawns:
                                                    pawns.remove(occupant)
                                                board_data[selected_pawn.row][selected_pawn.col].pawn = None
                                                selected_pawn.row, selected_pawn.col = r, c
                                                cell.pawn = selected_pawn
                                                current_player.score += 5

                                                move_anim['pawn'] = selected_pawn
                                                move_anim['start_pos'] = (cell_rect.centerx, cell_rect.centery)
                                                move_anim['end_pos'] = (cell_rect.centerx, cell_rect.centery)
                                                move_anim['active'] = True
                                                move_anim['start_ticks'] = pygame.time.get_ticks()
                                                move_anim['turn_done'] = False

                                                selected_pawn = None
                                                show_feedback(renderer, True)
                                            else:
                                                show_feedback(renderer, False)
                                                selected_pawn = None
                                                current_player_index = (current_player_index + 1) % len(players)
                                        else:
                                            selected_pawn = None
                                break
                        else:
                            continue
                        break

        # animation update (kept minimal)
        if move_anim['active']:
            time_passed = pygame.time.get_ticks() - move_anim['start_ticks']
            progress = time_passed / ANIM_DURATION
            if progress >= 1.0:
                move_anim['active'] = False
                move_anim['pawn'] = None
                move_anim['turn_done'] = True

        if move_anim.get('turn_done', False):
            move_anim['turn_done'] = False
            current_player_index = (current_player_index + 1) % len(players)

        # draw board
        valid_moves = get_valid_moves(board_data, selected_pawn, board_size, board_size) if selected_pawn else []

        for r in range(board_size):
            for c in range(board_size):
                cell = board_data[r][c]
                cell.rect = pygame.Rect(start_x + c * cell_size, start_y + r * cell_size, cell_size, cell_size)

                if cell.is_hole:
                    cell_color = BLACK
                else:
                    cell_color = GRAY

                if selected_pawn and (r, c) == (selected_pawn.row, selected_pawn.col):
                    cell_color = YELLOW
                elif (r, c) in valid_moves:
                    if cell.pawn and cell.pawn.player != selected_pawn.player:
                        cell_color = LIGHT_RED
                    else:
                        cell_color = LIGHT_GREEN

                pygame.draw.rect(screen, (*cell_color, 240), cell.rect, border_radius=6)
                pygame.draw.rect(screen, (10, 10, 10, 255), cell.rect, 2, border_radius=6)

                if not cell.is_hole:
                    cat_color = category_colors.get(cell.category, (128, 128, 128))
                    cat_rect = pygame.Rect(cell.rect.x + 4, cell.rect.y + 4, int(cell_size*0.16), int(cell_size*0.16))
                    pygame.draw.rect(screen, (*cat_color, 255), cat_rect, border_radius=4)

                if cell.pawn:
                    pawn_obj = cell.pawn
                    base_icon = icon_map.get((pawn_obj.player, pawn_obj.is_flag))
                    if base_icon:
                        scaled_icon = pygame.transform.scale(base_icon, (pawn_size, pawn_size))
                        if pawn_obj == selected_pawn:
                            pulse_scale = 1.0 + 0.1 * math.sin(pygame.time.get_ticks() * 0.01)
                            final_size = int(pawn_size * pulse_scale)
                            scaled_icon = pygame.transform.scale(base_icon, (final_size, final_size))

                        icon_rect = scaled_icon.get_rect(center=cell.rect.center)
                        screen.blit(scaled_icon, icon_rect)

        # HUD
        hud_bg = pygame.Surface((180, 150), pygame.SRCALPHA)
        pygame.draw.rect(hud_bg, (0, 0, 0, 180), (0, 0, 180, 150), border_radius=10)
        screen.blit(hud_bg, (10, 10))
        y_offset = 10
        for p in players:
            text = f"{p.name} (Score: {p.score})"
            surf = font.render(text, True, p.color)
            screen.blit(surf, (20, y_offset))
            y_offset += 30

        draw_legend(screen, font, x_start=10, y_start=200)
        draw_current_player_display(screen, font, players[current_player_index], icon_map, x_start=w - 210, y_start=50)

        renderer.present(pygame.time.get_ticks() * 0.001)
        clock.tick(FPS)

# -----------------------------
# Entrypoint
# -----------------------------
if __name__ == "__main__":
    # Create OpenGL window (required for ModernGL background)
    pygame.display.gl_set_attribute(pygame.GL_CONTEXT_MAJOR_VERSION, 3)
    pygame.display.gl_set_attribute(pygame.GL_CONTEXT_MINOR_VERSION, 3)
    pygame.display.gl_set_attribute(pygame.GL_CONTEXT_PROFILE_MASK, pygame.GL_CONTEXT_PROFILE_CORE)
    pygame.display.gl_set_attribute(pygame.GL_DOUBLEBUFFER, 1)

    try:
        pygame.display.set_mode((DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT),
                                pygame.OPENGL | pygame.DOUBLEBUF | pygame.RESIZABLE, vsync=0)
    except TypeError:
        pygame.display.set_mode((DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT),
                                pygame.OPENGL | pygame.DOUBLEBUF | pygame.RESIZABLE)

    pygame.display.set_caption("Trivia Strategy Game (Galaxy BG)")

    clock = pygame.time.Clock()
    title_font = pygame.font.SysFont("Arial", 48, bold=True)
    game_font = pygame.font.SysFont("Arial", 20)

    renderer = GalaxyRenderer(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, AUDIO_FILE)

    while True:
        splash_screen(renderer, clock, title_font)
        num_players, time_limit, board_size, pawn_img, flag_img = menu_loop(renderer, clock, title_font, game_font)
        main_game_real(renderer, clock, game_font, num_players, time_limit, board_size, pawn_img, flag_img)
