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

# --- Classes ---

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
                dist = abs(x - self.width//2) / (self.width//2)
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
        # Animation properties
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
                if len(row) < 5: continue
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
    if not questions_by_category: return None
    all_cats = list(questions_by_category.keys())
    category = random.choice(all_cats)
    if not questions_by_category[category]: return None
    return random.choice(questions_by_category[category])

def get_random_question_from(category):
    if category in questions_by_category and questions_by_category[category]:
        return random.choice(questions_by_category[category])
    else:
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
    waiting = True
    while waiting:
        for event in pygame.event.get():
            if event.type == pygame.QUIT: pygame.quit(); sys.exit()
        if pygame.time.get_ticks() - start_time > 1000:
            waiting = False

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
    if not qdata: return None 
    question_text = qdata["question"]
    correct_answer = qdata["correct"]
    wrong_answers = qdata["wrong"]
    answers = [correct_answer] + wrong_answers
    random.shuffle(answers)

    w, h = screen.get_size()
    question_box = pygame.Rect(0, 0, 600, 300)
    if w < 700: question_box.width = w - 50
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
        seconds_passed = (pygame.time.get_ticks() - start_ticks) / 1000
        time_left = max(0, time_limit - seconds_passed)
        if time_left == 0: return False
            
        pct = time_left / time_limit
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
            if event.type == pygame.QUIT: pygame.quit(); sys.exit()
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
        if result is None or not result: return False
    return True

# --- Game Logic ---

def place_random_holes(board, rows, cols, hole_count=HOLE_COUNT):
    free_positions = []
    for r in range(rows):
        for c in range(cols):
            if board[r][c].pawn is None:
                free_positions.append((r, c))
    if hole_count > len(free_positions): hole_count = len(free_positions)
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
            elif i == 3: r, c = corner_r - dr, corner_c + dc
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
    
    def change_players(val): nonlocal num_players; num_players = max(2, min(4, num_players + val))
    def change_time(val): nonlocal time_limit; time_limit = max(5, min(120, time_limit + val))
    def change_board(val): nonlocal board_size; board_size = max(6, min(32, board_size + val))
    def start_game(): nonlocal running; running = False

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
        for btn in buttons: btn.update_pos(w, h)
        
        ticks = pygame.time.get_ticks()
        glitch_x, glitch_y = (0, 0)
        if ticks % 60 == 0 and random.random() < 0.3:
            glitch_x, glitch_y = random.randint(-4, 4), random.randint(-2, 2)
        
        # Title
        title_surf = title_font.render("MAIN MENU", True, WHITE)
        title_rect = title_surf.get_rect(center=(w//2 + glitch_x, h//2 - 200 + glitch_y))
        if glitch_x != 0:
            screen.blit(title_font.render("MAIN MENU", True, (255, 0, 0)), (title_rect.x + 4, title_rect.y))
            screen.blit(title_font.render("MAIN MENU", True, (0, 255, 255)), (title_rect.x - 4, title_rect.y))
        screen.blit(title_surf, title_rect)
        
        # --- DRAW LABELS WITH CORRECT SYNTAX ---
        
        # 1. Players
        lbl_surf = option_font.render("Number of Players:", True, WHITE)
        lbl_rect = lbl_surf.get_rect(center=(w//2 + glitch_x, h//2 - 150 + glitch_y))
        screen.blit(lbl_surf, lbl_rect)
        num_surf = title_font.render(str(num_players), True, WHITE)
        screen.blit(num_surf, num_surf.get_rect(center=(w//2, h//2 - 120)))
        
        # 2. Time
        lbl_time_surf = option_font.render("Time (sec):", True, WHITE)
        lbl_time_rect = lbl_time_surf.get_rect(center=(w//2 + glitch_x, h//2 - 70 + glitch_y))
        screen.blit(lbl_time_surf, lbl_time_rect)
        time_surf = title_font.render(str(time_limit), True, WHITE)
        screen.blit(time_surf, time_surf.get_rect(center=(w//2, h//2 - 40)))

        # 3. Board
        lbl_board_surf = option_font.render(f"Board Size ({board_size}x{board_size}):", True, WHITE)
        lbl_board_rect = lbl_board_surf.get_rect(center=(w//2 + glitch_x, h//2 + 10 + glitch_y))
        screen.blit(lbl_board_surf, lbl_board_rect)
        board_surf = title_font.render(str(board_size), True, WHITE)
        screen.blit(board_surf, board_surf.get_rect(center=(w//2, h//2 + 40)))

        # Handle Input
        for event in pygame.event.get():
            if event.type == pygame.QUIT: pygame.quit(); sys.exit()
            elif event.type == pygame.VIDEORESIZE: bg.resize(event.w, event.h)
            elif event.type == pygame.MOUSEBUTTONDOWN:
                if event.button == 1:
                    for btn in buttons: btn.check_click(mouse_pos)
        
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
    
    # --- BOARD CREATION (Checkerboard Pattern) ---
    all_cats = list(category_colors.keys())
    for r in range(board_size):
        for c in range(board_size):
            cat_index = (r + c) % len(all_cats)
            board_data[r][c].category = all_cats[cat_index]
    # ---------------------------

    for p in pawns:
        board_data[p.row][p.col].pawn = p
    place_random_holes(board_data, board_size, board_size, HOLE_COUNT) 

    while running:
        w, h = screen.get_size()
        bg.resize(w, h)
        bg.update_and_draw(screen, colorful=True)

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
                pygame.quit()
                sys.exit()
            elif event.type == pygame.VIDEORESIZE: bg.resize(event.w, event.h)
            
            # --- INPUT HANDLING ---
            # Allow input ONLY if NO animation is active
            if not move_anim['active'] and event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
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
                        else: continue
                        break
                else:
                    # Selected Pawn Logic
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
                                        # --- MOVE TO EMPTY ---
                                        result = ask_question_from_category(screen, font, cell.category, time_limit)
                                        if result:
                                            # SUCCESS
                                            board_data[selected_pawn.row][selected_pawn.col].pawn = None
                                            selected_pawn.row, selected_pawn.col = r, c
                                            cell.pawn = selected_pawn
                                            current_player.score += 1
                                            
                                            # Trigger Animation
                                            move_anim['pawn'] = selected_pawn
                                            move_anim['start_pos'] = (cell_rect.centerx, cell_rect.centery)
                                            move_anim['active'] = True
                                            move_anim['start_ticks'] = pygame.time.get_ticks()
                                            move_anim['turn_done'] = False
                                            
                                            selected_pawn = None
                                            show_feedback(screen, True)
                                        else:
                                            # FAILURE: Skip Turn
                                            show_feedback(screen, False)
                                            selected_pawn = None
                                            current_player_index = (current_player_index + 1) % len(players)
                                            # Check Win Condition immediately
                                            flags_by_player = {p: False for p in players}
                                            for pawn in pawns:
                                                if pawn.is_flag: flags_by_player[pawn.player] = True
                                            losers = [p for p, has_flag in flags_by_player.items() if not has_flag]
                                            if losers:
                                                remaining = [p for p in players if p not in losers]
                                                if len(remaining) == 1: print(f"{remaining[0].name} Wins!"); running = False
                                                else:
                                                    print(f"Eliminating: {[l.name for l in losers]}.")
                                                    for p in losers:
                                                        for pawn in pawns[:]:
                                                            if pawn.player == p:
                                                                board_data[pawn.row][pawn.col].pawn = None
                                                                pawns.remove(pawn)
                                                    if current_player_index >= len(remaining): current_player_index = 0
                                                    players = remaining
                                            
                                    else:
                                        # --- ATTACK ---
                                        occupant = cell.pawn
                                        if occupant.player != current_player:
                                            success = ask_two_questions_from_category(screen, font, cell.category, time_limit)
                                            if success:
                                                # SUCCESS
                                                board_data[occupant.row][occupant.col].pawn = None
                                                if occupant in pawns: pawns.remove(occupant)
                                                board_data[selected_pawn.row][selected_pawn.col].pawn = None
                                                selected_pawn.row, selected_pawn.col = r, c
                                                cell.pawn = selected_pawn
                                                current_player.score += 5
                                                
                                                # Trigger Animation
                                                move_anim['pawn'] = selected_pawn
                                                move_anim['start_pos'] = (cell_rect.centerx, cell_rect.centery)
                                                move_anim['active'] = True
                                                move_anim['start_ticks'] = pygame.time.get_ticks()
                                                move_anim['turn_done'] = False
                                                
                                                selected_pawn = None
                                                show_feedback(screen, True)
                                            else:
                                                # FAILURE: Skip Turn
                                                show_feedback(screen, False)
                                                selected_pawn = None
                                                current_player_index = (current_player_index + 1) % len(players)
                                                # Check Win Condition immediately
                                                flags_by_player = {p: False for p in players}
                                                for pawn in pawns:
                                                    if pawn.is_flag: flags_by_player[pawn.player] = True
                                                losers = [p for p, has_flag in flags_by_player.items() if not has_flag]
                                                if losers:
                                                    remaining = [p for p in players if p not in losers]
                                                    if len(remaining) == 1: print(f"{remaining[0].name} Wins!"); running = False
                                                    else:
                                                        print(f"Eliminating: {[l.name for l in losers]}.")
                                                        for p in losers:
                                                            for pawn in pawns[:]:
                                                                if pawn.player == p:
                                                                    board_data[pawn.row][pawn.col].pawn = None
                                                                    pawns.remove(pawn)
                                                        if current_player_index >= len(remaining): current_player_index = 0
                                                        players = remaining
                                        else:
                                            selected_pawn = None
                                break
                        else: continue
                        break

        # --- ANIMATION UPDATE ---
        if move_anim['active']:
            time_passed = pygame.time.get_ticks() - move_anim['start_ticks']
            progress = time_passed / ANIM_DURATION
            if progress >= 1.0:
                move_anim['active'] = False
                move_anim['pawn'] = None
                move_anim['turn_done'] = True
            else:
                t_ease = progress * (2 - progress)
                cur_x = move_anim['start_pos'][0] + (move_anim['end_pos'][0] - move_anim['start_pos'][0]) * t_ease
                cur_y = move_anim['start_pos'][1] + (move_anim['end_pos'][1] - move_anim['start_pos'][1]) * t_ease
                move_anim['pawn'].anim_x = cur_x
                move_anim['pawn'].anim_y = cur_y

        # --- TURN SWITCH ---
        # Only switch turn if animation says so (successful move)
        if move_anim.get('turn_done', False):
            move_anim['turn_done'] = False
            current_player_index = (current_player_index + 1) % len(players)
            
            # Check win condition
            flags_by_player = {p: False for p in players}
            for pawn in pawns:
                if pawn.is_flag: flags_by_player[pawn.player] = True
            losers = [p for p, has_flag in flags_by_player.items() if not has_flag]
            if losers:
                remaining = [p for p in players if p not in losers]
                if len(remaining) == 1:
                    print(f"{remaining[0].name} Wins!")
                    running = False
                else:
                    print(f"Eliminating: {[l.name for l in losers]}.")
                    for p in losers:
                        for pawn in pawns[:]:
                            if pawn.player == p:
                                board_data[pawn.row][pawn.col].pawn = None
                                pawns.remove(pawn)
                    if current_player_index >= len(remaining): current_player_index = 0
                    players = remaining

        # --- DRAW ---
        valid_moves = get_valid_moves(board_data, selected_pawn, board_size, board_size) if selected_pawn else []

        for r in range(board_size):
            for c in range(board_size):
                cell = board_data[r][c]
                
                cell.rect.x = start_x + c * cell_size
                cell.rect.y = start_y + r * cell_size
                cell.rect.w = cell_size
                cell.rect.h = cell_size

                if cell.is_hole: cell_color = BLACK
                else: cell_color = GRAY
                if selected_pawn and (r, c) == (selected_pawn.row, selected_pawn.col): cell_color = YELLOW
                elif (r, c) in valid_moves:
                    if cell.pawn and cell.pawn.player != selected_pawn.player: cell_color = LIGHT_RED
                    else: cell_color = LIGHT_GREEN

                pygame.draw.rect(screen, cell_color, cell.rect)
                pygame.draw.rect(screen, BLACK, cell.rect, 2)

                if not cell.is_hole:
                    cat_color = category_colors.get(cell.category, (128, 128, 128))
                    cat_rect = pygame.Rect(cell.rect.x + 2, cell.rect.y + 2, int(cell_size*0.15), int(cell_size*0.15))
                    pygame.draw.rect(screen, cat_color, cat_rect)

                if cell.pawn:
                    pawn_obj = cell.pawn
                    base_icon = icon_map.get((pawn_obj.player, pawn_obj.is_flag))
                    if base_icon:
                        is_animating = (move_anim['pawn'] == pawn_obj)
                        
                        if is_animating:
                            px, py = getattr(pawn_obj, 'anim_x', cell.rect.centerx), getattr(pawn_obj, 'anim_y', cell.rect.centery)
                        else:
                            px, py = cell.rect.centerx, cell.rect.centery

                        scaled_icon = pygame.transform.scale(base_icon, (pawn_size, pawn_size))
                        # Pulse applies only if NOT animating
                        if pawn_obj == selected_pawn and not is_animating:
                            pulse_scale = 1.0 + 0.1 * math.sin(pygame.time.get_ticks() * 0.01)
                            final_size = int(pawn_size * pulse_scale)
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
        clock.tick(FPS)

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