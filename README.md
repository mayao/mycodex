# Snake (Classic)

Minimal classic Snake implementation:
- Grid-based movement
- Food spawn and snake growth
- Score tracking
- Game-over on wall/self collision
- Pause and restart

## Run

1. Start a static server from the repo root (example):
   - `python3 -m http.server 8000`
2. Open:
   - `http://localhost:8000/index.html`

## Test

If Node.js is installed:
- `node --test`

## Manual Verification Checklist

- Movement:
  - Arrow keys and `W/A/S/D` move the snake.
  - 180-degree reverse input is ignored.
- Food and growth:
  - Snake grows by 1 segment after eating food.
  - Score increments by 1 per food eaten.
- Pause/restart:
  - `P` pauses/resumes.
  - Pause button toggles pause/resume.
  - `R` and Restart button reset score and state.
- Boundaries and collisions:
  - Hitting a wall ends the game.
  - Hitting the snake body ends the game.
