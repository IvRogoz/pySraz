import pygame
import sys
import csv
import random

pygame.init()

WINDOW_WIDTH = 800
WINDOW_HEIGHT = 600
FPS = 30

ROWS = 8
COLS = 8
CELL_SIZE = 60
MARGIN_TOP = 50

# Number of random holes to create
HOLE_COUNT = 6

WHITE = (255, 255, 255)
BLACK = (0, 0, 0)
GRAY = (180, 180, 180)
YELLOW = (255, 255, 0)
LIGHT_GREEN = (150, 255, 150)
LIGHT_RED = (255, 150, 150)

category_colors = {
    "Sport": (0, 200, 0),
    "History": (139, 69, 19),
    "Music": (128, 0, 128),
    "Science": (0, 255, 255),
    "Art": (255, 192, 203),
    "Random": (128, 128, 128),
}

class Player:
    def __init__(self, name, color):
        self.name = name
        self.color = color
        self.score = 0

class Pawn:
    def __init__(self, player, row, col, is_flag=False):
        self.player = player
        self.row = row
        self.col = col
        self.is_flag = is_flag

class Cell:
    def __init__(self, x, y, w, h, category="", is_hole=False):
        self.rect = pygame.Rect(x, y, w, h)
        self.is_hole = is_hole
        self.pawn = None
        self.category = category  # new: store a category for each cell

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
        print(f"Error: File '{filename}' not found. Make sure it exists.")
        sys.exit(1)

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
    else:
        return get_random_question_any()

def show_feedback(screen, correct):
    # Fill the background so old stuff isn't visible
    screen.fill((255, 255, 255))

    # Draw a gray box in the center
    feedback_rect = pygame.Rect(150, 100, 500, 400)
    pygame.draw.rect(screen, (220, 220, 220), feedback_rect)
    pygame.draw.rect(screen, (0, 0, 0), feedback_rect, 2)

    # Use a large font
    big_font = pygame.font.SysFont(None, 200)

    # Prepare the symbol
    if correct:
        # A big green check
        text_surf = big_font.render("✓", True, (0, 200, 0))
    else:
        # A big red X
        text_surf = big_font.render("X", True, (200, 0, 0))

    # Center the symbol inside the rectangle
    text_rect = text_surf.get_rect(center=feedback_rect.center)
    screen.blit(text_surf, text_rect)

    pygame.display.flip()

    # Pause for ~1 second, but still allow the user to close the game if desired
    start_time = pygame.time.get_ticks()
    waiting = True
    while waiting:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                pygame.quit()
                sys.exit()
        if pygame.time.get_ticks() - start_time > 1000:
            waiting = False


def ask_question_from_category(screen, font, category):
    qdata = get_random_question_from(category)
    if not qdata:
        return None  # no questions available at all

    question_text = qdata["question"]
    correct_answer = qdata["correct"]
    wrong_answers = qdata["wrong"]

    answers = [correct_answer] + wrong_answers
    random.shuffle(answers)

    margin = 10
    question_box = pygame.Rect(100, 100, 600, 250)

    chosen_answer = None
    done_asking = False
    answer_rects = []

    clock = pygame.time.Clock()

    while not done_asking:
        screen.fill(WHITE)

        pygame.draw.rect(screen, GRAY, question_box)

        q_surf = font.render(question_text, True, BLACK)
        screen.blit(q_surf, (question_box.x + margin, question_box.y + margin))

        answer_rects.clear()
        for i, ans in enumerate(answers):
            ans_surf = font.render(ans, True, BLACK)
            ans_rect = ans_surf.get_rect()
            ans_rect.topleft = (question_box.x + margin, question_box.y + 60 + i * 40)
            screen.blit(ans_surf, ans_rect)
            answer_rects.append((ans_rect, ans))

        pygame.display.flip()
        clock.tick(FPS)

        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                pygame.quit()
                sys.exit()
            elif event.type == pygame.MOUSEBUTTONDOWN:
                mx, my = pygame.mouse.get_pos()
                for rect, ans_text in answer_rects:
                    if rect.collidepoint(mx, my):
                        chosen_answer = ans_text
                        done_asking = True
                        break

    return chosen_answer == correct_answer

def ask_three_questions_from_category(screen, font, category):
    for _ in range(3):
        result = ask_question_from_category(screen, font, category)
        if result is None:
            return False
        if not result:
            return False
    return True

def colorize(surface, new_color):
    colored_image = surface.copy()
    colored_image.fill((0, 0, 0, 255), special_flags=pygame.BLEND_RGBA_MULT)
    colored_image.fill(new_color[0:3] + (0,), special_flags=pygame.BLEND_RGBA_ADD)
    return colored_image

def create_empty_board():
    board = []
    start_x = (WINDOW_WIDTH - (COLS * CELL_SIZE)) // 2
    start_y = MARGIN_TOP

    # Convert the dict keys to a list for random choice
    all_categories = list(category_colors.keys())

    for row in range(ROWS):
        row_cells = []
        for col in range(COLS):
            cell_x = start_x + col * CELL_SIZE
            cell_y = start_y + row * CELL_SIZE
            # Randomly pick one of our known categories
            random_cat = random.choice(all_categories)
            row_cells.append(
                Cell(
                    cell_x,
                    cell_y,
                    CELL_SIZE,
                    CELL_SIZE,
                    category=random_cat,
                    is_hole=False,
                )
            )
        board.append(row_cells)
    return board

def place_random_holes(board, pawns, hole_count=HOLE_COUNT):
    free_positions = []
    for r in range(ROWS):
        for c in range(COLS):
            if board[r][c].pawn is None:
                free_positions.append((r, c))

    if hole_count > len(free_positions):
        hole_count = len(free_positions)

    chosen_holes = random.sample(free_positions, hole_count)
    for r, c in chosen_holes:
        board[r][c].is_hole = True

def get_valid_moves(board, selected_pawn):
    directions = [(0, 1), (0, -1), (1, 0), (-1, 0)]
    valid_moves = []
    r, c = selected_pawn.row, selected_pawn.col

    for dr, dc in directions:
        nr, nc = r + dr, c + dc
        if 0 <= nr < ROWS and 0 <= nc < COLS:
            cell = board[nr][nc]
            if cell.is_hole:
                continue
            # skip same-player pawns
            if cell.pawn and cell.pawn.player == selected_pawn.player:
                continue
            valid_moves.append((nr, nc))
    return valid_moves

def draw_legend(screen, font, x_start, y_start):
    y_offset = y_start
    for cat, color in category_colors.items():
        # small color box
        color_box = pygame.Rect(x_start, y_offset, 20, 20)
        pygame.draw.rect(screen, color, color_box)
        pygame.draw.rect(screen, BLACK, color_box, 1)

        # category text
        text_surf = font.render(cat, True, BLACK)
        screen.blit(text_surf, (x_start + 30, y_offset))
        y_offset += 30

    # Also add an explanation of the highlight colors
    y_offset += 20
    highlight_info = [
        ("Selected Tile", YELLOW),
        ("Valid Move (Empty)", LIGHT_GREEN),
        ("Valid Move (Enemy)", LIGHT_RED),
        ("Hole", BLACK),
    ]
    for label, color in highlight_info:
        color_box = pygame.Rect(x_start, y_offset, 20, 20)
        pygame.draw.rect(screen, color, color_box)
        pygame.draw.rect(screen, BLACK, color_box, 1)

        text_surf = font.render(label, True, BLACK)
        screen.blit(text_surf, (x_start + 30, y_offset))
        y_offset += 30

def main():
    screen = pygame.display.set_mode((WINDOW_WIDTH, WINDOW_HEIGHT))
    pygame.display.set_caption("Sraz with Category Colors + Legend")
    clock = pygame.time.Clock()
    game_font = pygame.font.SysFont(None, 24)

    # Create Players
    players = [
        Player("Player 1", (255, 0, 0)),  # Red
        Player("Player 2", (0, 0, 255)),  # Blue
    ]

    # Create Pawns
    pawns = []
    # Player 1
    pawns.append(Pawn(players[0], 0, 0, is_flag=True))  # Flag
    pawns.append(Pawn(players[0], 1, 0))
    pawns.append(Pawn(players[0], 0, 1))
    pawns.append(Pawn(players[0], 1, 1))
    pawns.append(Pawn(players[0], 2, 0))
    pawns.append(Pawn(players[0], 0, 2))
    # Player 2
    pawns.append(Pawn(players[1], 7, 7, is_flag=True))  # Flag
    pawns.append(Pawn(players[1], 6, 7))
    pawns.append(Pawn(players[1], 7, 6))
    pawns.append(Pawn(players[1], 6, 6))
    pawns.append(Pawn(players[1], 5, 7))
    pawns.append(Pawn(players[1], 7, 5))

    # Create Board
    board = create_empty_board()
    for p in pawns:
        board[p.row][p.col].pawn = p

    place_random_holes(board, pawns, HOLE_COUNT)

    # Load & colorize images
    try:
        base_pawn_img = pygame.image.load("pawn.png").convert_alpha()
        base_flag_img = pygame.image.load("flag.png").convert_alpha()
    except pygame.error as e:
        print("Image loading error:", e)
        pygame.quit()
        sys.exit()

    # Scale
    base_pawn_img = pygame.transform.scale(base_pawn_img, (40, 40))
    base_flag_img = pygame.transform.scale(base_flag_img, (40, 40))

    # Color variants
    pawn_red_img = colorize(base_pawn_img, (255, 0, 0))
    flag_red_img = colorize(base_flag_img, (255, 150, 150))
    pawn_blue_img = colorize(base_pawn_img, (0, 0, 255))
    flag_blue_img = colorize(base_flag_img, (150, 150, 255))

    icon_map = {
        (players[0], False): pawn_red_img,
        (players[0], True): flag_red_img,
        (players[1], False): pawn_blue_img,
        (players[1], True): flag_blue_img,
    }

    current_player_index = 0
    selected_pawn = None

    running = True
    while running:
        screen.fill(WHITE)

        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False

            elif event.type == pygame.MOUSEBUTTONDOWN:
                mx, my = pygame.mouse.get_pos()
                current_player = players[current_player_index]

                # If no pawn selected, try to select one
                if not selected_pawn:
                    for row in range(ROWS):
                        for col in range(COLS):
                            cell = board[row][col]
                            if cell.rect.collidepoint(mx, my) and cell.pawn:
                                if cell.pawn.player == current_player:
                                    selected_pawn = cell.pawn
                                    break
                        else:
                            continue
                        break
                else:
                    # Attempt to move selected pawn
                    for row in range(ROWS):
                        for col in range(COLS):
                            cell = board[row][col]
                            if cell.rect.collidepoint(mx, my):
                                # Must be orthogonally adjacent
                                if (
                                    abs(selected_pawn.row - row)
                                    + abs(selected_pawn.col - col)
                                    == 1
                                ):
                                    # Hole?
                                    if cell.is_hole:
                                        selected_pawn = None
                                        break

                                    # If empty, ask 1 question from cell's category
                                    if not cell.pawn:
                                        result = ask_question_from_category(
                                            screen, game_font, cell.category
                                        )
                                        if result:
                                            board[selected_pawn.row][
                                                selected_pawn.col
                                            ].pawn = None
                                            selected_pawn.row, selected_pawn.col = (
                                                row,
                                                col,
                                            )
                                            cell.pawn = selected_pawn
                                            current_player.score += 1
                                            show_feedback(screen, True)
                                        else:
                                            show_feedback(screen, False)
                                        selected_pawn = None
                                        current_player_index = (
                                            current_player_index + 1
                                        ) % len(players)
                                        break
                                    else:
                                        # Occupied
                                        occupant = cell.pawn
                                        if occupant.player != current_player:
                                            # Attempt capture, 3 questions from cell's category
                                            success = ask_three_questions_from_category(
                                                screen, game_font, cell.category
                                            )
                                            if success:
                                                board[occupant.row][
                                                    occupant.col
                                                ].pawn = None
                                                if occupant in pawns:
                                                    pawns.remove(occupant)
                                                board[selected_pawn.row][
                                                    selected_pawn.col
                                                ].pawn = None
                                                selected_pawn.row, selected_pawn.col = (
                                                    row,
                                                    col,
                                                )
                                                cell.pawn = selected_pawn
                                                current_player.score += 5
                                            selected_pawn = None
                                            current_player_index = (
                                                current_player_index + 1
                                            ) % len(players)
                                            break
                                        else:
                                            # Occupied by same player
                                            selected_pawn = None
                                            break

                    # Check for winner
                    flag_1 = next(
                        (p for p in pawns if p.is_flag and p.player == players[0]), None
                    )
                    flag_2 = next(
                        (p for p in pawns if p.is_flag and p.player == players[1]), None
                    )
                    if flag_1 not in pawns:
                        print("Player 2 captured Player 1's flag and wins!")
                        running = False
                    elif flag_2 not in pawns:
                        print("Player 1 captured Player 2's flag and wins!")
                        running = False

        # ----- DRAW BOARD -----
        if selected_pawn:
            valid_moves = get_valid_moves(board, selected_pawn)
        else:
            valid_moves = []

        for row in range(ROWS):
            for col in range(COLS):
                cell = board[row][col]

                # Base color
                if cell.is_hole:
                    cell_color = BLACK
                else:
                    cell_color = GRAY

                # Highlight selected pawn's tile
                if selected_pawn and (row, col) == (
                    selected_pawn.row,
                    selected_pawn.col,
                ):
                    cell_color = YELLOW
                elif (row, col) in valid_moves:
                    # if enemy occupant
                    if cell.pawn and cell.pawn.player != selected_pawn.player:
                        cell_color = LIGHT_RED
                    else:
                        cell_color = LIGHT_GREEN

                pygame.draw.rect(screen, cell_color, cell.rect)
                pygame.draw.rect(screen, BLACK, cell.rect, 2)

                # Draw the small category rectangle in the top-left corner
                # (skip if it's a hole)
                if not cell.is_hole:
                    cat_color = category_colors.get(cell.category, (128, 128, 128))
                    cat_rect = pygame.Rect(cell.rect.x + 2, cell.rect.y + 2, 10, 10)
                    pygame.draw.rect(screen, cat_color, cat_rect)

                # Draw pawn
                if cell.pawn:
                    pawn_obj = cell.pawn
                    icon_surf = icon_map[(pawn_obj.player, pawn_obj.is_flag)]

                    # Optionally tint the selected pawn icon
                    if selected_pawn and (row, col) == (
                        selected_pawn.row,
                        selected_pawn.col,
                    ):
                        icon_surf = colorize(icon_surf, (255, 255, 180))

                    icon_rect = icon_surf.get_rect(center=cell.rect.center)
                    screen.blit(icon_surf, icon_rect)

        # Draw the legend on the right side
        draw_legend(screen, game_font, x_start=650, y_start=50)

        # ----- DRAW UI -----
        y_offset = 10
        for p in players:
            text = f"{p.name} (score: {p.score})"
            surf = game_font.render(text, True, p.color)
            screen.blit(surf, (10, y_offset))
            y_offset += 30

        if selected_pawn:
            instr_text = f"Selected {selected_pawn.player.name}'s pawn. Click an adjacent cell to move/capture."
        else:
            instr_text = f"{players[current_player_index].name}'s turn. Click one of your pawns to move."
        instr_surf = game_font.render(instr_text, True, BLACK)
        screen.blit(instr_surf, (10, y_offset))

        pygame.display.flip()
        clock.tick(FPS)

    pygame.quit()
    sys.exit()

if __name__ == "__main__":
    main()
