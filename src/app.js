import { createInitialState, queueDirection, tick, togglePause } from "./snake.js";

const CELL_SIZE = 24;
const TICK_MS = 140;
const DIR_BY_KEY = {
  ArrowUp: "up",
  ArrowDown: "down",
  ArrowLeft: "left",
  ArrowRight: "right",
  w: "up",
  s: "down",
  a: "left",
  d: "right",
};

const boardEl = document.querySelector("#board");
const scoreEl = document.querySelector("#score");
const statusEl = document.querySelector("#status");
const pauseBtn = document.querySelector("#pause-btn");
const restartBtn = document.querySelector("#restart-btn");
const controlButtons = Array.from(document.querySelectorAll("[data-dir]"));

let state = createInitialState({ cols: 16, rows: 16 });

function renderBoard(nextState) {
  boardEl.style.setProperty("--cols", String(nextState.cols));
  boardEl.style.setProperty("--rows", String(nextState.rows));
  boardEl.style.setProperty("--cell-size", `${CELL_SIZE}px`);

  const snakeCells = new Set(nextState.snake.map((part) => `${part.x},${part.y}`));
  const cells = [];
  for (let y = 0; y < nextState.rows; y += 1) {
    for (let x = 0; x < nextState.cols; x += 1) {
      const key = `${x},${y}`;
      const classes = ["cell"];
      if (snakeCells.has(key)) {
        classes.push("snake");
      } else if (nextState.food && nextState.food.x === x && nextState.food.y === y) {
        classes.push("food");
      }
      cells.push(`<div class="${classes.join(" ")}" role="presentation"></div>`);
    }
  }
  boardEl.innerHTML = cells.join("");
}

function renderHUD(nextState) {
  scoreEl.textContent = String(nextState.score);
  if (!nextState.alive) {
    statusEl.textContent = "Game Over";
    pauseBtn.disabled = true;
    pauseBtn.textContent = "Pause";
    return;
  }
  pauseBtn.disabled = false;
  pauseBtn.textContent = nextState.paused ? "Resume" : "Pause";
  statusEl.textContent = nextState.paused ? "Paused" : "Running";
}

function render(nextState) {
  renderBoard(nextState);
  renderHUD(nextState);
}

function step() {
  state = tick(state);
  render(state);
}

function setDirection(dir) {
  state = queueDirection(state, dir);
}

document.addEventListener("keydown", (event) => {
  const key = event.key.toLowerCase();
  if (DIR_BY_KEY[key]) {
    event.preventDefault();
    setDirection(DIR_BY_KEY[key]);
    return;
  }
  if (key === "p") {
    state = togglePause(state);
    render(state);
    return;
  }
  if (key === "r") {
    state = createInitialState({ cols: state.cols, rows: state.rows });
    render(state);
  }
});

pauseBtn.addEventListener("click", () => {
  state = togglePause(state);
  render(state);
});

restartBtn.addEventListener("click", () => {
  state = createInitialState({ cols: state.cols, rows: state.rows });
  render(state);
});

controlButtons.forEach((button) => {
  button.addEventListener("click", () => {
    const dir = button.getAttribute("data-dir");
    setDirection(dir);
  });
});

setInterval(step, TICK_MS);
render(state);
