# Sudoku Solver

Just for fun I wanted to try writing a sudoku solver with powershell. Fun little challenge to write a recursive function with backtracking in order to try multiple iterations of failed sequences, test and correct.

Inspired by: [This short "Computerphile" youtube video](https://www.youtube.com/watch?v=G_UYXzGuqvM&ab_channel=Computerphile)

## Usage

```
& '.\sudoku solver.ps1' -Grid 1,0,0,0,0,7,0,9,0,0,3,0,0,2,0,0,0,8,0,0,9,6,0,0,5,0,0,0,0,5,3,0,0,9,0,0,0,1,0,0,8,0,0,0,2,6,0,0,0,0,4,0,0,0,3,0,0,0,0,0,0,1,0,0,4,0,0,0,0,0,0,7,0,0,7,0,0,0,3,0,0
Unsolved Puzzle:
┌───────┬───────┬───────┐
│ 1 0 0 │ 0 0 7 │ 0 9 0 │
│ 0 3 0 │ 0 2 0 │ 0 0 8 │
│ 0 0 9 │ 6 0 0 │ 5 0 0 │
├───────┼───────┼───────┤
│ 0 0 5 │ 3 0 0 │ 9 0 0 │
│ 0 1 0 │ 0 8 0 │ 0 0 2 │
│ 6 0 0 │ 0 0 4 │ 0 0 0 │
├───────┼───────┼───────┤
│ 3 0 0 │ 0 0 0 │ 0 1 0 │
│ 0 4 0 │ 0 0 0 │ 0 0 7 │
│ 0 0 7 │ 0 0 0 │ 3 0 0 │
└───────┴───────┴───────┘
Solved Puzzle:
┌───────┬───────┬───────┐
│ 1 6 2 │ 8 5 7 │ 4 9 3 │
│ 5 3 4 │ 1 2 9 │ 6 7 8 │
│ 7 8 9 │ 6 4 3 │ 5 2 1 │
├───────┼───────┼───────┤
│ 4 7 5 │ 3 1 2 │ 9 8 6 │
│ 9 1 3 │ 5 8 6 │ 7 4 2 │
│ 6 2 8 │ 7 9 4 │ 1 3 5 │
├───────┼───────┼───────┤
│ 3 5 6 │ 4 7 8 │ 2 1 9 │
│ 2 4 1 │ 9 3 5 │ 8 6 7 │
│ 8 9 7 │ 2 6 1 │ 3 5 4 │
└───────┴───────┴───────┘

Boxes Solved Attempted Possibilities Times Backtracked Elapsed Solve Time
------------ ----------------------- ----------------- ------------------
          58                    8969              8911 00:00:02.3119968
```
