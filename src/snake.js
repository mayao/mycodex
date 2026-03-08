const DIRS = {
  up: { x: 0, y: -1 },
  down: { x: 0, y: 1 },
  left: { x: -1, y: 0 },
  right: { x: 1, y: 0 },
};

const OPPOSITE = {
  up: "down",
  down: "up",
  left: "right",
  right: "left",
};

function cellKey(cell) {
  return `${cell.x},${cell.y}`;
}

function randomInt(max, rng = Math.random) {
  return Math.floor(rng() * max);
}

export function getFreeCells({ cols, rows, snake }) {
  const occupied = new Set(snake.map(cellKey));
  const free = [];
  for (let y = 0; y < rows; y += 1) {
    for (let x = 0; x < cols; x += 1) {
      if (!occupied.has(`${x},${y}`)) {
        free.push({ x, y });
      }
    }
  }
  return free;
}

export function placeFood(state, rng = Math.random) {
  const free = getFreeCells(state);
  if (free.length === 0) {
    return null;
  }
  return free[randomInt(free.length, rng)];
}

export function createInitialState(config = {}, rng = Math.random) {
  const cols = config.cols ?? 16;
  const rows = config.rows ?? 16;
  const start = { x: Math.floor(cols / 2), y: Math.floor(rows / 2) };
  const snake = [start];
  const state = {
    cols,
    rows,
    snake,
    direction: "right",
    queuedDirection: "right",
    food: null,
    score: 0,
    alive: true,
    paused: false,
  };
  state.food = placeFood(state, rng);
  return state;
}

export function queueDirection(state, nextDirection) {
  if (!DIRS[nextDirection] || !state.alive) {
    return state;
  }
  if (OPPOSITE[state.direction] === nextDirection) {
    return state;
  }
  return { ...state, queuedDirection: nextDirection };
}

function outOfBounds(head, cols, rows) {
  return head.x < 0 || head.x >= cols || head.y < 0 || head.y >= rows;
}

export function tick(state, rng = Math.random) {
  if (!state.alive || state.paused) {
    return state;
  }

  const direction = state.queuedDirection;
  const move = DIRS[direction];
  const currentHead = state.snake[0];
  const nextHead = { x: currentHead.x + move.x, y: currentHead.y + move.y };

  if (outOfBounds(nextHead, state.cols, state.rows)) {
    return { ...state, direction, alive: false };
  }

  const willEat = state.food && nextHead.x === state.food.x && nextHead.y === state.food.y;
  const bodyToCheck = willEat ? state.snake : state.snake.slice(0, -1);
  if (bodyToCheck.some((part) => part.x === nextHead.x && part.y === nextHead.y)) {
    return { ...state, direction, alive: false };
  }

  const grownSnake = [nextHead, ...state.snake];
  const nextSnake = willEat ? grownSnake : grownSnake.slice(0, -1);
  const nextScore = willEat ? state.score + 1 : state.score;

  const nextState = {
    ...state,
    direction,
    snake: nextSnake,
    score: nextScore,
  };
  nextState.food = willEat ? placeFood(nextState, rng) : state.food;

  if (willEat && !nextState.food) {
    nextState.alive = false;
  }
  return nextState;
}

export function togglePause(state) {
  if (!state.alive) {
    return state;
  }
  return { ...state, paused: !state.paused };
}
