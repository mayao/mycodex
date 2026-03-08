import test from "node:test";
import assert from "node:assert/strict";
import { createInitialState, tick, queueDirection, placeFood } from "./snake.js";

function rngFrom(values) {
  let i = 0;
  return () => {
    const v = values[i] ?? values[values.length - 1] ?? 0;
    i += 1;
    return v;
  };
}

test("moves one cell in queued direction", () => {
  let state = createInitialState({ cols: 8, rows: 8 }, () => 0);
  state = queueDirection(state, "down");
  state = tick(state, () => 0);
  assert.equal(state.snake[0].x, 4);
  assert.equal(state.snake[0].y, 5);
});

test("cannot reverse direction into itself", () => {
  let state = createInitialState({ cols: 8, rows: 8 }, () => 0);
  state = {
    ...state,
    snake: [
      { x: 4, y: 4 },
      { x: 3, y: 4 },
    ],
    direction: "right",
    queuedDirection: "right",
  };
  state = queueDirection(state, "left");
  assert.equal(state.queuedDirection, "right");
});

test("eating food grows snake and increments score", () => {
  let state = createInitialState({ cols: 8, rows: 8 }, () => 0);
  state = {
    ...state,
    snake: [{ x: 4, y: 4 }],
    direction: "right",
    queuedDirection: "right",
    food: { x: 5, y: 4 },
  };
  state = tick(state, () => 0);
  assert.equal(state.score, 1);
  assert.equal(state.snake.length, 2);
  assert.deepEqual(state.snake[0], { x: 5, y: 4 });
});

test("wall collision ends game", () => {
  let state = createInitialState({ cols: 4, rows: 4 }, () => 0);
  state = {
    ...state,
    snake: [{ x: 3, y: 1 }],
    direction: "right",
    queuedDirection: "right",
  };
  state = tick(state, () => 0);
  assert.equal(state.alive, false);
});

test("self collision ends game", () => {
  let state = createInitialState({ cols: 6, rows: 6 }, () => 0);
  state = {
    ...state,
    snake: [
      { x: 3, y: 3 },
      { x: 3, y: 4 },
      { x: 2, y: 4 },
      { x: 2, y: 3 },
    ],
    direction: "left",
    queuedDirection: "down",
    food: { x: 0, y: 0 },
  };
  state = tick(state, () => 0);
  assert.equal(state.alive, false);
});

test("food placement picks an available cell deterministically with injected rng", () => {
  const state = {
    cols: 3,
    rows: 3,
    snake: [
      { x: 0, y: 0 },
      { x: 1, y: 0 },
    ],
  };
  const food = placeFood(state, rngFrom([0.5]));
  assert.notEqual(`${food.x},${food.y}`, "0,0");
  assert.notEqual(`${food.x},${food.y}`, "1,0");
});
