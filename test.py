import pygame
import sys

pygame.init()

# Set up the display *before* loading images or converting them
screen = pygame.display.set_mode((800, 600))
pygame.display.set_caption("Show Colorized Pawn")

def colorize(surface, new_color):
    """
    Returns a new Surface that is tinted with 'new_color',
    preserving the alpha (transparency) of the original.
    Assumes the original is a mostly black silhouette on a transparent background.
    """
    colored_image = surface.copy()
    # 1) Zero out RGB (keep alpha) by multiplying with (0,0,0,255)
    colored_image.fill((0, 0, 0, 255), special_flags=pygame.BLEND_RGBA_MULT)
    # 2) Add in the new color's RGB
    colored_image.fill(new_color[0:3] + (0,), special_flags=pygame.BLEND_RGBA_ADD)
    return colored_image

try:
    # Load the black pawn image
    base_pawn_img = pygame.image.load("pawn.png").convert_alpha()
except pygame.error as e:
    print("Could not load 'pawn.png':", e)
    pygame.quit()
    sys.exit()

# Colorize the black pawn to red
pawn_red_img = colorize(base_pawn_img, (255, 0, 0))

running = True
while running:
    for event in pygame.event.get():
        if event.type == pygame.QUIT:
            running = False

    # Clear the screen (fill with white)
    screen.fill((255, 255, 255))

    # Draw the red pawn image at position (100, 100)
    screen.blit(pawn_red_img, (100, 100))

    pygame.display.flip()

pygame.quit()
sys.exit()
