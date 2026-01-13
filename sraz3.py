import pygame
import sys
import csv
import random
import math
import colorsys

pygame.init()

# --- Constants ---
DEFAULT_WINDOW_WIDTH = 900
DEFAULT_WINDOW_HEIGHT = 700
FPS = 30
HOLE_COUNT = 6

# Colors
WHITE = (255, 255, 255)
BLACK = (0, 0, 0)
GRAY = (180, 180, 180)
DARK_GRAY = (50, 50, 50)
YELLOW = (255, 255, 0)
LIGHT_GREEN = (150, 255, 150)
LIGHT_RED = (255, 150, 150)
BLUE_UI = (70, 130, 180)
RED_WARNING = (220, 20, 60)
GREEN_BAR = (50, 205, 50)
YELLOW_BAR = (255, 215, 0)

# Balatro Palette
BG_COLOR = (15, 10, 20)
GRID_COLOR = (60, 40, 80)
CARD_RED = (200, 50, 50)
CARD_BLUE = (50, 50, 200)
CARD_BLACK = (20, 20, 20)
CARD_HOVER = (240, 240, 240)

# Question Palette
Q_BG_COLOR = (15, 20, 35)
Q_GRID_COLOR = (40, 55, 80)
Q_SWEEP_COLOR = (60, 90, 120)

PLAYER_COLORS = [
    (220, 20, 60), (30, 144, 255), (34, 139, 34), (255, 215, 0)
]

category_colors = {
    "Sport": (0, 200, 0), "History": (139, 69, 19), "Music": (128, 0, 128),
    "Science": (0, 255, 255), "Art": (255, 192, 203), "Random": (128, 128, 128),
}

# -----------------------------
# Helpers
# -----------------------------

def clamp(x, a, b):
    return a if x < a else (b if x > b else x)

def smoothstep01(x):
    x = clamp(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)

def lerp(a, b, t):
    return a + (b - a) * t

def shade(rgb, f):
    r, g, b = rgb
    return (int(clamp(r * f, 0, 255)),
            int(clamp(g * f, 0, 255)),
            int(clamp(b * f, 0, 255)))

def blend(a, b, t):
    return (int(a[0] + (b[0] - a[0]) * t),
            int(a[1] + (b[1] - a[1]) * t),
            int(a[2] + (b[2] - a[2]) * t))

def exp_smooth(curr, target, dt, speed=14.0):
    # stable smoothing for dt spikes
    dt = min(max(dt, 0.0), 1.0 / 20.0)
    k = 1.0 - math.exp(-speed * dt)
    return curr + (target - curr) * k

# -----------------------------
# 3D-ish tilt (center pivot)
# -----------------------------

def _shear_x_by_rows(src, shear_px, chunk_h=6):
    """Shear in X by shifting horizontal chunks across Y."""
    w, h = src.get_size()
    if w <= 2 or h <= 2 or abs(shear_px) < 0.5:
        return src

    shear_px = int(shear_px)
    pad = abs(shear_px) + 2
    out = pygame.Surface((w + pad, h), pygame.SRCALPHA)

    base_x = pad // 2
    for y in range(0, h, chunk_h):
        hh = min(chunk_h, h - y)
        t = (y + hh * 0.5) / max(1.0, h)  # 0..1
        # shift more toward top/bottom -> looks like "tilt"
        off = int((t - 0.5) * shear_px)
        out.blit(src, (base_x + off, y), area=pygame.Rect(0, y, w, hh))
    return out

def _shear_y_by_cols(src, shear_py, chunk_w=6):
    """Shear in Y by shifting vertical chunks across X."""
    w, h = src.get_size()
    if w <= 2 or h <= 2 or abs(shear_py) < 0.5:
        return src

    shear_py = int(shear_py)
    pad = abs(shear_py) + 2
    out = pygame.Surface((w, h + pad), pygame.SRCALPHA)

    base_y = pad // 2
    for x in range(0, w, chunk_w):
        ww = min(chunk_w, w - x)
        t = (x + ww * 0.5) / max(1.0, w)  # 0..1
        off = int((t - 0.5) * shear_py)
        out.blit(src, (x, base_y + off), area=pygame.Rect(x, 0, ww, h))
    return out

def tilt_surface(src, rx, ry):
    """
    Apply a pivoted "3D tilt" based on rx/ry:
      - scale by cos
      - shear by sin
    This matches a center-pivot 3D card tilt feel in pygame.
    """
    w, h = src.get_size()
    if w <= 2 or h <= 2:
        return src

    # scale from "foreshortening"
    sx = max(0.35, abs(math.cos(ry)))
    sy = max(0.35, abs(math.cos(rx)))
    w2 = max(2, int(w * sx))
    h2 = max(2, int(h * sy))

    scaled = pygame.transform.smoothscale(src, (w2, h2))

    # shear amounts (perspective-ish)
    shear_x = math.sin(ry) * (h2 * 0.55)  # left/right tilt -> skew along Y
    shear_y = math.sin(rx) * (w2 * 0.55)  # up/down tilt -> skew along X

    s1 = _shear_x_by_rows(scaled, shear_x, chunk_h=6)
    s2 = _shear_y_by_cols(s1, shear_y, chunk_w=6)

    return s2

def render_tile_flat(size, base_color, cat_color, border_color, is_hole=False):
    """
    Draw the flat tile art ONCE per frame (cheap) then warp it.
    """
    surf = pygame.Surface((size, size), pygame.SRCALPHA)

    if is_hole:
        pygame.draw.rect(surf, (0, 0, 0), (0, 0, size, size))
        pygame.draw.rect(surf, (10, 10, 10), (0, 0, size, size), 2)
        return surf

    # base face + subtle bands like a card
    face = base_color
    pygame.draw.rect(surf, shade(face, 0.90), (0, 0, size, size))
    pygame.draw.rect(surf, shade(face, 1.08), (0, 0, size, int(size * 0.18)))
    pygame.draw.rect(surf, shade(face, 0.84), (0, int(size * 0.78), size, int(size * 0.22)))

    # category tag
    tag = int(size * 0.16)
    pygame.draw.rect(surf, cat_color, (4, 4, tag, tag))
    pygame.draw.rect(surf, (0, 0, 0), (4, 4, tag, tag), 1)

    # border
    pygame.draw.rect(surf, border_color, (0, 0, size, size), 2)

    return surf

# -----------------------------
# Game Classes
# -----------------------------

class BalatroBackground:
    def __init__(self, w, h):
        self.width = w
        self.height = h
        self.static_surf = pygame.Surface((w, h))
        self.generate_static()
        self.scanline_surf = pygame.Surface((w, h), pygame.SRCALPHA)
        for y in range(0, h, 4):
            pygame.draw.line(self.scanline_surf, (0, 0, 0, 30), (0, y), (w, y))

    def resize(self, w, h):
        if self.width != w or self.height != h:
            self.width = w
            self.height = h
            self.static_surf = pygame.Surface((w, h))
            self.generate_static()
            self.scanline_surf = pygame.Surface((w, h), pygame.SRCALPHA)
            for y in range(0, h, 4):
                pygame.draw.line(self.scanline_surf, (0, 0, 0, 30), (0, y), (w, y))

    def generate_static(self):
        for x in range(0, self.width, 4):
            for y in range(0, self.height, 4):
                if random.random() > 0.9:
                    c = random.randint(50, 80)
                    self.static_surf.set_at((x, y), (c, c, c))
                else:
                    self.static_surf.set_at((x, y), (0, 0, 0))

    def update_and_draw(self, screen, colorful=False):
        screen.fill(BG_COLOR)
        current_grid_color = GRID_COLOR
        if colorful:
            time_val = pygame.time.get_ticks() * 0.001
            hue = (time_val * 0.1) % 1.0
            r, g, b = colorsys.hsv_to_rgb(hue, 0.9, 0.9)
            current_grid_color = (int(r*255), int(g*255), int(b*255))

        time_val = pygame.time.get_ticks() * 0.002
        for x in range(0, self.width, 40):
            offset = math.sin(time_val + x * 0.01) * 10
            pygame.draw.line(screen, current_grid_color, (x + offset, 0), (x - offset, self.height), 1)

        grid_offset = (pygame.time.get_ticks() * 0.05) % 40
        for y in range(int(grid_offset) - 40, self.height, 40):
            points = []
            for x in range(0, self.width, 50):
                dist = abs(x - self.width//2) / max(1, (self.width//2))
                curve_y = y + (dist * dist * 20)
                points.append((x, curve_y))
            if len(points) > 1:
                pygame.draw.lines(screen, current_grid_color, False, points, 1)

        static_copy = self.static_surf.copy()
        static_copy.set_alpha(30)
        screen.blit(static_copy, (0, 0))
        screen.blit(self.scanline_surf, (0, 0))

        overlay = pygame.Surface((self.width, self.height), pygame.SRCALPHA)
        pygame.draw.rect(overlay, (0, 0, 0, 150), (0, 0, 100, self.height))
        pygame.draw.rect(overlay, (0, 0, 0, 150), (self.width-100, 0, 100, self.height))
        pygame.draw.rect(overlay, (0, 0, 0, 100), (0, 0, self.width, 50))
        pygame.draw.rect(overlay, (0, 0, 0, 100), (0, self.height-50, self.width, 50))
        screen.blit(overlay, (0, 0))

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

        pygame.draw.rect(screen, (245, 235, 220), draw_rect, border_radius=8)
        pygame.draw.rect(screen, draw_color, draw_rect.inflate(-6, -6), border_radius=4)
        pygame.draw.rect(screen, (20, 20, 20), draw_rect, 2, border_radius=8)

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
    except (pygame.error, FileNotFoundError):
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
                if len(row) < 6:
                    continue
                category, question, correct, w1, w2, w3 = row[:6]
                category = category.strip()
                questions_by_category.setdefault(category, []).append(
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

# --- UI ---

def show_feedback(screen, correct):
    screen.fill(WHITE)
    w, h = screen.get_size()
    feedback_rect = pygame.Rect(0, 0, 400, 300)
    feedback_rect.center = (w//2, h//2)
    pygame.draw.rect(screen, (240, 240, 240), feedback_rect)
    pygame.draw.rect(screen, BLACK, feedback_rect, 2)

    big_font = pygame.font.SysFont(None, 200)
    text_surf = big_font.render("✓", True, (0, 200, 0)) if correct else big_font.render("X", True, (200, 0, 0))
    screen.blit(text_surf, text_surf.get_rect(center=feedback_rect.center))
    pygame.display.flip()

    start_time = pygame.time.get_ticks()
    while True:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                pygame.quit(); sys.exit()
        if pygame.time.get_ticks() - start_time > 1000:
            break

def draw_question_background(screen):
    screen.fill(Q_BG_COLOR)
    w, h = screen.get_size()
    scroll_speed = pygame.time.get_ticks() * 0.02
    offset_x = int(scroll_speed) % 40
    offset_y = int(scroll_speed) % 40
    for x in range(-40, w, 40):
        pygame.draw.line(screen, Q_GRID_COLOR, (x + offset_x, 0), (x + offset_x, h), 1)
    for y in range(-40, h, 40):
        pygame.draw.line(screen, Q_GRID_COLOR, (0, y + offset_y), (w, y + offset_y), 1)

    center_x, center_y = w // 2, h // 2
    radius = (pygame.time.get_ticks() * 0.05) % max(w, h)
    pygame.draw.circle(screen, Q_SWEEP_COLOR, (center_x, center_y), int(radius), 2)

    pulse_alpha = int(20 + 10 * math.sin(pygame.time.get_ticks() * 0.005))
    pulse_surf = pygame.Surface((w, h), pygame.SRCALPHA)
    pulse_surf.fill((40, 60, 90, pulse_alpha))
    screen.blit(pulse_surf, (0,0))

def ask_question_from_category(screen, font, category, time_limit):
    qdata = get_random_question_from(category)
    if not qdata:
        return None
    question_text = qdata["question"]
    correct_answer = qdata["correct"]
    wrong_answers = qdata["wrong"]
    answers = [correct_answer] + wrong_answers
    random.shuffle(answers)

    w, h = screen.get_size()
    question_box = pygame.Rect(0, 0, 600, 300)
    if w < 700:
        question_box.width = w - 50
    question_box.centerx = w // 2
    question_box.y = 100

    margin = 20
    chosen_answer = None
    done_asking = False
    answer_rects = []
    clock = pygame.time.Clock()
    start_ticks = pygame.time.get_ticks()

    bar_width = 400
    bar_height = 25
    bar_x = (w - bar_width) // 2
    bar_y = 50

    while not done_asking:
        draw_question_background(screen)
        seconds_passed = (pygame.time.get_ticks() - start_ticks) / 1000.0
        time_left = max(0.0, time_limit - seconds_passed)
        if time_left <= 0.0:
            return False

        pct = time_left / max(0.001, time_limit)
        fill_width = int(bar_width * pct)
        bar_color = GREEN_BAR if pct > 0.5 else (YELLOW_BAR if pct > 0.2 else RED_WARNING)

        pygame.draw.rect(screen, GRAY, (bar_x, bar_y, bar_width, bar_height))
        pygame.draw.rect(screen, bar_color, (bar_x, bar_y, fill_width, bar_height))
        pygame.draw.rect(screen, BLACK, (bar_x, bar_y, bar_width, bar_height), 2)

        pygame.draw.rect(screen, WHITE, question_box)
        pygame.draw.rect(screen, BLACK, question_box, 2)

        words = question_text.split(' ')
        lines = []
        current_line = ""
        for word in words:
            if font.size(current_line + word)[0] < question_box.width - 2*margin:
                current_line += word + " "
            else:
                lines.append(current_line)
                current_line = word + " "
        lines.append(current_line)

        y_offset = question_box.y + margin
        for line in lines:
            screen.blit(font.render(line, True, BLACK), (question_box.x + margin, y_offset))
            y_offset += 30

        answer_rects.clear()
        start_y = y_offset + 20
        for i, ans in enumerate(answers):
            ans_surf = font.render(f"{chr(65+i)}: {ans}", True, BLACK)
            ans_rect = ans_surf.get_rect()
            ans_rect.topleft = (question_box.x + margin, start_y + i * 40)
            screen.blit(ans_surf, ans_rect)
            answer_rects.append((ans_rect, ans))

        pygame.display.flip()
        clock.tick(FPS)

        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                pygame.quit(); sys.exit()
            elif event.type == pygame.MOUSEBUTTONDOWN:
                mx, my = pygame.mouse.get_pos()
                for rect, ans_text in answer_rects:
                    if rect.collidepoint(mx, my):
                        chosen_answer = ans_text
                        done_asking = True
                        break

    return chosen_answer == correct_answer

def ask_two_questions_from_category(screen, font, category, time_limit):
    for _ in range(2):
        result = ask_question_from_category(screen, font, category, time_limit)
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
    hole_count = min(hole_count, len(free_positions))
    chosen_holes = random.sample(free_positions, hole_count)
    for r, c in chosen_holes:
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
        pygame.draw.rect(screen, color, color_box)
        pygame.draw.rect(screen, WHITE, color_box, 1)
        screen.blit(font.render(cat, True, WHITE), (x_start + 30, y_offset))
        y_offset += 25

    y_offset += 20
    for label, color in [("Selected", YELLOW), ("Move Empty", LIGHT_GREEN), ("Attack", LIGHT_RED), ("Hole", WHITE)]:
        color_box = pygame.Rect(x_start, y_offset, 20, 20)
        pygame.draw.rect(screen, color, color_box)
        pygame.draw.rect(screen, WHITE, color_box, 1)
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
            if i == 0: r, c = corner_r + dr, corner_c + dc
            elif i == 1: r, c = corner_r - dr, corner_c - dc
            elif i == 2: r, c = corner_r + dr, corner_c - dc
            else: r, c = corner_r - dr, corner_c + dc
            if 0 <= r < board_size and 0 <= c < board_size:
                pawns.append(Pawn(p, r, c, is_flag))
    return players, pawns

# --- Screens ---

def splash_screen(screen, clock, font):
    bg = BalatroBackground(screen.get_width(), screen.get_height())
    running = True
    while running:
        w, h = screen.get_size()
        bg.update_and_draw(screen)
        title_surf = font.render("TRIVIA STRATEGY", True, WHITE)
        title_rect = title_surf.get_rect(center=(w//2, h//2 - 50))
        screen.blit(title_surf, title_rect)
        sub_surf = pygame.font.SysFont("Arial", 24).render("Capture the Flag", True, (200, 200, 200))
        sub_rect = sub_surf.get_rect(center=(w//2, h//2 + 20))
        screen.blit(sub_surf, sub_rect)
        instr_surf = pygame.font.SysFont("Arial", 20).render("Click anywhere to start", True, YELLOW)
        instr_rect = instr_surf.get_rect(center=(w//2, h//2 + 80))
        screen.blit(instr_surf, instr_rect)
        pygame.display.flip()

        for event in pygame.event.get():
            if event.type == pygame.QUIT: pygame.quit(); sys.exit()
            elif event.type == pygame.MOUSEBUTTONDOWN: running = False
            elif event.type == pygame.VIDEORESIZE: bg.resize(event.w, event.h)
        clock.tick(FPS)

def menu_loop(screen, clock, title_font, option_font):
    num_players = 2
    time_limit = 30
    board_size = 8
    running = True
    bg = BalatroBackground(screen.get_width(), screen.get_height())

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
        Button(-100, -120, 50, 50, "-", CARD_BLACK, CARD_RED, lambda: change_players(-1)),
        Button(100, -120, 50, 50, "+", CARD_BLACK, CARD_RED, lambda: change_players(1)),
        Button(-100, -40, 50, 50, "-", CARD_BLACK, CARD_RED, lambda: change_time(-5)),
        Button(100, -40, 50, 50, "+", CARD_BLACK, CARD_RED, lambda: change_time(5)),
        Button(-100, 40, 50, 50, "-", CARD_BLACK, CARD_RED, lambda: change_board(-1)),
        Button(100, 40, 50, 50, "+", CARD_BLACK, CARD_RED, lambda: change_board(1)),
        Button(-80, 130, 160, 60, "PLAY", CARD_BLUE, (100, 149, 237), start_game)
    ]
    base_pawn_img, base_flag_img = load_assets()

    while running:
        w, h = screen.get_size()
        bg.resize(w, h)
        bg.update_and_draw(screen)
        mouse_pos = pygame.mouse.get_pos()
        for btn in buttons:
            btn.update_pos(w, h)

        ticks = pygame.time.get_ticks()
        glitch_x, glitch_y = (0, 0)
        if ticks % 60 == 0 and random.random() < 0.3:
            glitch_x, glitch_y = random.randint(-4, 4), random.randint(-2, 2)

        title_surf = title_font.render("MAIN MENU", True, WHITE)
        title_rect = title_surf.get_rect(center=(w//2 + glitch_x, h//2 - 200 + glitch_y))
        screen.blit(title_surf, title_rect)

        lbl_surf = option_font.render("Number of Players:", True, WHITE)
        screen.blit(lbl_surf, lbl_surf.get_rect(center=(w//2, h//2 - 150)))
        num_surf = title_font.render(str(num_players), True, WHITE)
        screen.blit(num_surf, num_surf.get_rect(center=(w//2, h//2 - 120)))

        lbl_time_surf = option_font.render("Time (sec):", True, WHITE)
        screen.blit(lbl_time_surf, lbl_time_surf.get_rect(center=(w//2, h//2 - 70)))
        time_surf = title_font.render(str(time_limit), True, WHITE)
        screen.blit(time_surf, time_surf.get_rect(center=(w//2, h//2 - 40)))

        lbl_board_surf = option_font.render(f"Board Size ({board_size}x{board_size}):", True, WHITE)
        screen.blit(lbl_board_surf, lbl_board_surf.get_rect(center=(w//2, h//2 + 10)))
        board_surf = title_font.render(str(board_size), True, WHITE)
        screen.blit(board_surf, board_surf.get_rect(center=(w//2, h//2 + 40)))

        for event in pygame.event.get():
            if event.type == pygame.QUIT: pygame.quit(); sys.exit()
            elif event.type == pygame.VIDEORESIZE: bg.resize(event.w, event.h)
            elif event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
                for btn in buttons:
                    btn.check_click(mouse_pos)

        for btn in buttons:
            btn.check_hover(mouse_pos)
            btn.draw(screen, option_font, (glitch_x, glitch_y))

        pygame.display.flip()
        clock.tick(FPS)

    return num_players, time_limit, board_size, base_pawn_img, base_flag_img

def main_game_real(screen, clock, font, num_players, time_limit, board_size, base_pawn_img, base_flag_img):
    players, pawns = setup_players_and_pawns(num_players, board_size)
    bg = BalatroBackground(screen.get_width(), screen.get_height())

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

    # --- Move animation FIX (your file had start_pos/end_pos wrong) ---
    move_anim = {
        'active': False,
        'pawn': None,
        'start_pos': (0, 0),
        'end_pos': (0, 0),
        'start_ticks': 0,
        'turn_done': False
    }
    ANIM_DURATION = 300

    board_data = [[Cell() for _ in range(board_size)] for _ in range(board_size)]
    all_cats = list(category_colors.keys())
    for r in range(board_size):
        for c in range(board_size):
            board_data[r][c].category = all_cats[(r + c) % len(all_cats)]

    for p in pawns:
        board_data[p.row][p.col].pawn = p
    place_random_holes(board_data, board_size, board_size, HOLE_COUNT)

    # --- 3D rotation state per tile (pivoted) ---
    phases = [[random.random() * (math.pi * 2.0) for _ in range(board_size)] for __ in range(board_size)]
    rot_x = [[0.0 for _ in range(board_size)] for __ in range(board_size)]
    rot_y = [[0.0 for _ in range(board_size)] for __ in range(board_size)]
    hover_w = [[0.0 for _ in range(board_size)] for __ in range(board_size)]  # smooth hover

    while running:
        dt = clock.tick(FPS) / 1000.0
        dt = min(max(dt, 0.0), 1.0 / 20.0)
        t = pygame.time.get_ticks() * 0.001

        w, h = screen.get_size()
        bg.resize(w, h)
        bg.update_and_draw(screen, colorful=True)

        margin_x = 240 + 240
        margin_y = 180 + 50
        available_w = max(50, w - margin_x)
        available_h = max(50, h - margin_y)
        cell_size = int(min(available_w / board_size, available_h / board_size))
        cell_size = max(18, cell_size)
        start_x = (w - (board_size * cell_size)) // 2
        start_y = (h - (board_size * cell_size)) // 2
        pawn_size = int(cell_size * 0.7)

        mx, my = pygame.mouse.get_pos()

        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                pygame.quit(); sys.exit()
            elif event.type == pygame.VIDEORESIZE:
                bg.resize(event.w, event.h)

            if not move_anim['active'] and event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
                mx0, my0 = pygame.mouse.get_pos()
                current_player = players[current_player_index]

                def cell_at(x, y):
                    col = (x - start_x) // cell_size
                    row = (y - start_y) // cell_size
                    if 0 <= row < board_size and 0 <= col < board_size:
                        return int(row), int(col)
                    return None

                hit = cell_at(mx0, my0)
                if hit is None:
                    continue
                r, c = hit
                cell = board_data[r][c]

                if not selected_pawn:
                    if cell.pawn and cell.pawn.player == current_player:
                        selected_pawn = cell.pawn
                else:
                    if abs(selected_pawn.row - r) + abs(selected_pawn.col - c) == 1:
                        if cell.is_hole:
                            selected_pawn = None
                            continue

                        sr, sc = selected_pawn.row, selected_pawn.col

                        # MOVE TO EMPTY
                        if not cell.pawn:
                            result = ask_question_from_category(screen, font, cell.category, time_limit)
                            if result:
                                board_data[sr][sc].pawn = None
                                selected_pawn.row, selected_pawn.col = r, c
                                board_data[r][c].pawn = selected_pawn
                                current_player.score += 1

                                # start->end positions for anim
                                sx = start_x + sc * cell_size + cell_size // 2
                                sy = start_y + sr * cell_size + cell_size // 2
                                ex = start_x + c * cell_size + cell_size // 2
                                ey = start_y + r * cell_size + cell_size // 2
                                move_anim.update({
                                    'active': True,
                                    'pawn': selected_pawn,
                                    'start_pos': (sx, sy),
                                    'end_pos': (ex, ey),
                                    'start_ticks': pygame.time.get_ticks(),
                                    'turn_done': False
                                })
                                selected_pawn.anim_x, selected_pawn.anim_y = sx, sy

                                selected_pawn = None
                                show_feedback(screen, True)
                            else:
                                show_feedback(screen, False)
                                selected_pawn = None
                                current_player_index = (current_player_index + 1) % len(players)

                        else:
                            # ATTACK
                            occupant = cell.pawn
                            if occupant.player != current_player:
                                success = ask_two_questions_from_category(screen, font, cell.category, time_limit)
                                if success:
                                    board_data[occupant.row][occupant.col].pawn = None
                                    if occupant in pawns:
                                        pawns.remove(occupant)

                                    board_data[sr][sc].pawn = None
                                    selected_pawn.row, selected_pawn.col = r, c
                                    board_data[r][c].pawn = selected_pawn
                                    current_player.score += 5

                                    sx = start_x + sc * cell_size + cell_size // 2
                                    sy = start_y + sr * cell_size + cell_size // 2
                                    ex = start_x + c * cell_size + cell_size // 2
                                    ey = start_y + r * cell_size + cell_size // 2
                                    move_anim.update({
                                        'active': True,
                                        'pawn': selected_pawn,
                                        'start_pos': (sx, sy),
                                        'end_pos': (ex, ey),
                                        'start_ticks': pygame.time.get_ticks(),
                                        'turn_done': False
                                    })
                                    selected_pawn.anim_x, selected_pawn.anim_y = sx, sy

                                    selected_pawn = None
                                    show_feedback(screen, True)
                                else:
                                    show_feedback(screen, False)
                                    selected_pawn = None
                                    current_player_index = (current_player_index + 1) % len(players)
                            else:
                                selected_pawn = None
                    else:
                        selected_pawn = None

        # --- ANIMATION UPDATE ---
        if move_anim['active']:
            time_passed = pygame.time.get_ticks() - move_anim['start_ticks']
            progress = time_passed / max(1, ANIM_DURATION)
            if progress >= 1.0:
                move_anim['active'] = False
                move_anim['pawn'] = None
                move_anim['turn_done'] = True
            else:
                # ease out
                te = 1.0 - (1.0 - progress) * (1.0 - progress)
                sx, sy = move_anim['start_pos']
                ex, ey = move_anim['end_pos']
                cur_x = sx + (ex - sx) * te
                cur_y = sy + (ey - sy) * te
                move_anim['pawn'].anim_x = cur_x
                move_anim['pawn'].anim_y = cur_y

        if move_anim.get('turn_done', False):
            move_anim['turn_done'] = False
            current_player_index = (current_player_index + 1) % len(players)

        valid_moves = get_valid_moves(board_data, selected_pawn, board_size, board_size) if selected_pawn else []

        # --- DRAW TILES WITH 3D ROTATION ---
        for r in range(board_size):
            for c in range(board_size):
                cell = board_data[r][c]
                cell.rect = pygame.Rect(start_x + c * cell_size, start_y + r * cell_size, cell_size, cell_size)

                # hover detection
                is_hover = cell.rect.collidepoint(mx, my) and (not cell.is_hole)

                # smooth hover weight so it doesn't "snap"
                hover_w[r][c] = exp_smooth(hover_w[r][c], 1.0 if is_hover else 0.0, dt, speed=18.0)
                hw = clamp(hover_w[r][c], 0.0, 1.0)

                # base colors by state (same logic as your original)
                base_face = GRAY
                border_col = BLACK

                if selected_pawn and (r, c) == (selected_pawn.row, selected_pawn.col):
                    base_face = blend(GRAY, YELLOW, 0.65)
                    border_col = YELLOW
                elif (r, c) in valid_moves:
                    if cell.pawn and selected_pawn and cell.pawn.player != selected_pawn.player:
                        base_face = blend(GRAY, LIGHT_RED, 0.65)
                        border_col = LIGHT_RED
                    else:
                        base_face = blend(GRAY, LIGHT_GREEN, 0.65)
                        border_col = LIGHT_GREEN
                elif is_hover:
                    base_face = blend(GRAY, CARD_HOVER, 0.55)
                    border_col = WHITE

                cat_color = category_colors.get(cell.category, (128, 128, 128))

                # --- ROTATION TARGETS ---
                # Idle spherical path: sin for X, cos for Y (your description)
                idle_amp = 0.10  # radians-ish
                ph = phases[r][c]
                idle_rx = math.sin(t * 1.15 + ph) * idle_amp
                idle_ry = math.cos(t * 1.15 + ph * 1.13) * idle_amp

                # Hover: mouse distance from center controls rotation
                cx, cy = cell.rect.center
                nx = clamp((mx - cx) / max(1.0, cell.rect.w * 0.5), -1.0, 1.0)
                ny = clamp((my - cy) / max(1.0, cell.rect.h * 0.5), -1.0, 1.0)
                dist = clamp(math.hypot(nx, ny), 0.0, 1.0)
                dist = smoothstep01(dist)

                hover_amp = 0.25  # make it obvious
                hov_rx = (-ny) * dist * hover_amp
                hov_ry = (nx) * dist * hover_amp

                # Blend idle->hover by smoothed hover weight
                target_rx = lerp(idle_rx, hov_rx, hw)
                target_ry = lerp(idle_ry, hov_ry, hw)

                # Smooth angles to kill jitter/flicker
                rot_x[r][c] = exp_smooth(rot_x[r][c], target_rx, dt, speed=14.0)
                rot_y[r][c] = exp_smooth(rot_y[r][c], target_ry, dt, speed=14.0)

                rx = clamp(rot_x[r][c], -1.05, 1.05)
                ry = clamp(rot_y[r][c], -1.05, 1.05)

                if cell.is_hole:
                    # hole stays flat
                    flat = render_tile_flat(max(12, int(cell_size * 0.92)), base_face, cat_color, border_col, is_hole=True)
                    rr = flat.get_rect(center=cell.rect.center)
                    screen.blit(flat, rr)
                    continue

                # render flat tile at slightly smaller size (prevents overlap)
                tile_px = max(12, int(cell_size * 0.90))
                flat = render_tile_flat(tile_px, base_face, cat_color, border_col, is_hole=False)

                # apply tilt only if it matters
                if abs(rx) + abs(ry) < 0.02:
                    warped = flat
                else:
                    warped = tilt_surface(flat, rx, ry)

                # shadow from tilt direction
                sh_off_x = int(math.sin(ry) * (cell_size * 0.14))
                sh_off_y = int(math.sin(rx) * (cell_size * 0.14)) + 3

                shadow = pygame.Surface(warped.get_size(), pygame.SRCALPHA)
                shadow.fill((0, 0, 0, 85))

                # pivot in the middle: always blit centered on cell center
                cx, cy = cell.rect.center
                sh_rect = shadow.get_rect(center=(cx + sh_off_x, cy + sh_off_y))
                wr_rect = warped.get_rect(center=(cx, cy))

                screen.blit(shadow, sh_rect)
                screen.blit(warped, wr_rect)

                # small category dot in the real board cell corner (optional extra clarity)
                # (kept subtle so it doesn't fight the warped surface)
                if not cell.is_hole:
                    dot = pygame.Rect(cell.rect.x + 2, cell.rect.y + 2, max(3, int(cell_size * 0.10)), max(3, int(cell_size * 0.10)))
                    pygame.draw.rect(screen, cat_color, dot)

                # pawn drawn later (unchanged)

        # --- DRAW PAWNS (same as yours, with move anim) ---
        for r in range(board_size):
            for c in range(board_size):
                cell = board_data[r][c]
                if cell.pawn:
                    pawn_obj = cell.pawn
                    base_icon = icon_map.get((pawn_obj.player, pawn_obj.is_flag))
                    if not base_icon:
                        continue

                    is_anim = (move_anim['pawn'] == pawn_obj)
                    if is_anim:
                        px, py = int(pawn_obj.anim_x), int(pawn_obj.anim_y)
                    else:
                        px, py = cell.rect.center

                    scaled_icon = pygame.transform.scale(base_icon, (pawn_size, pawn_size))
                    if pawn_obj == selected_pawn and not is_anim:
                        pulse_scale = 1.0 + 0.1 * math.sin(pygame.time.get_ticks() * 0.01)
                        final_size = int(pawn_size * pulse_scale)
                        final_size = max(10, final_size)
                        scaled_icon = pygame.transform.scale(base_icon, (final_size, final_size))

                    icon_rect = scaled_icon.get_rect(center=(px, py))
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

        pygame.display.flip()

if __name__ == "__main__":
    screen = pygame.display.set_mode((DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT), pygame.RESIZABLE)
    pygame.display.set_caption("Trivia Strategy Game")
    clock = pygame.time.Clock()
    title_font = pygame.font.SysFont("Arial", 48, bold=True)
    game_font = pygame.font.SysFont("Arial", 20)

    while True:
        splash_screen(screen, clock, title_font)
        num_players, time_limit, board_size, pawn_img, flag_img = menu_loop(screen, clock, title_font, game_font)
        main_game_real(screen, clock, game_font, num_players, time_limit, board_size, pawn_img, flag_img)
