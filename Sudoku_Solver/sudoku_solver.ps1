param(
    $Grid = @(8, 1, 2, 7, 5, 3, 6, 0, 9, 0, 0, 3, 6, 0, 0, 0, 0, 0, 0, 7, 0, 0, 9, 0, 2, 0, 0, 0, 5, 0, 0, 0, 7, 0, 0, 0, 0, 0, 9, 0, 4, 5, 7, 0, 0, 0, 0, 0, 1, 0, 0, 0, 3, 0, 0, 0, 1, 0, 0, 0, 0, 6, 8, 0, 0, 8, 5, 0, 0, 0, 1, 0, 0, 9, 0, 0, 0, 0, 4, 0, 2)
)

# Transform grid array into actual 9x9 2-dimensional array 
if ($Grid) {
    $Row = 0
    $SudokuGrid = New-Object "System.Collections.ArrayList"
    do {
        $StartIndex = $Row * 9
        $SudokuGrid.add( $Grid[$StartIndex..($StartIndex + 8)] ) | Out-Null
        $Row++
    }
    until($Row -gt 8)
    $Grid = $SudokuGrid
}

# Function to find the possible values for a given box
function Get-SudokuPossibilities {
    param(
        $x, # Column of target box
        $y # Row of target box
    )
    # Calculate the 3x3 box the number is in
    $XBox = switch ($x) {
        { 0..2 -contains $x } { 0..2 ; break }
        { 3..5 -contains $x } { 3..5 ; break }
        { 6..8 -contains $x } { 6..8 ; break }
    }
    $YBox = switch ($y) {
        { 0..2 -contains $y } { 0..2 ; break }
        { 3..5 -contains $y } { 3..5 ; break }
        { 6..8 -contains $y } { 6..8 ; break }
    }
    # See what numbers exist in the 3x3 box
    $BoxNumbers = foreach ($RowNumber in $XBox) {
        $grid[$RowNumber][$YBox]
    }
    # See what numbers exist in the column
    [array]$xNumbers = $grid[$x]
    
    # See what numbers exist in the row
    [array]$yNumbers = foreach ($Row in $Grid) {
        $row[$y]
    }

    $NotPossible = ($xNumbers + $yNumbers + $BoxNumbers) # Numbers it can't be
    $Possible = (1..9) | Where-Object { $NotPossible -notcontains $_ } # Possible numbers
    
    if ($Possible) {
        return $Possible # Return array of possible numbers
    }
    else {
        return $null # Return nothing if there are no possibilities
    }
}

# Function to write a 9x9 sudoku grid to the screen
function Write-SudokuGrid {
    param(
        $Grid = $Grid
    )
    $y = 0
    foreach ($row in $grid) {
        if (0 -eq $y ) { "┌───────┬───────┬───────┐" }
        if (3, 6 -contains $y ) { '├───────┼───────┼───────┤' }
        @(
            '│ ' + $($row[0..2] -join ' ')
            $row[3..5] -join ' '
            ($row[6..8] -join ' ') + ' │' 
        ) -join ' │ '
        if ($y -eq 8 ) { '└───────┴───────┴───────┘' }
        $y++
    }
}

function Get-SudokuSolution {
    param(
        $Grid = $Grid
    )
    $Global:Solved = $false # To stop the recursive backlash later
    foreach ($Row in (0..8)) {
        foreach ($Column in (0..8)) {
            if ($Grid[$Row][$Column] -eq 0) {
                # Get the possible numbers for a given box
                $Possible = Get-SudokuPossibilities $Row $Column
                foreach ($Possibility in $Possible) { 
                    # Set the box to a possible value
                    $Grid[$Row][$Column] = $Possibility
                    # Recursive call to continue attempting to solve unsolved boxes
                    Get-SudokuSolution -Grid $Grid
                    if ($Solved) {
                        # If the puzzle has been solved don't continue the function
                        break
                    }
                    else {
                        # If the puzzle hasn't been solved, and we're back, the solution didn't work
                        # Let's backtrack by zeroing out this box and trying another possibility
                        $Grid[$Row][$Column] = 0
                    }
                }
                return # There is an unsolvable box, let's backtrack
            }
        }
    }
    $Global:Solved = $True # If we got here, the puzzle has been solved
}

Write-SudokuGrid -Grid $Grid # Write the unsolved pussle to the screen
$StartTime = Get-Date # Store the solve start time
Get-SudokuSolution -Grid $Grid # Find a solution
Write-SudokuGrid -Grid $Grid # Write the solved puzzle to the screen
Write-Output "Solve Time: $(New-TimeSpan $StartTime $(Get-Date))" # Write the solve time
