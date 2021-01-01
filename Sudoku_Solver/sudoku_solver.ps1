param(
    $Grid = @(8, 1, 2, 7, 5, 3, 6, 0, 9, 0, 0, 3, 6, 0, 0, 0, 0, 0, 0, 7, 0, 0, 9, 0, 2, 0, 0, 0, 5, 0, 0, 0, 7, 0, 0, 0, 0, 0, 9, 0, 4, 5, 7, 0, 0, 0, 0, 0, 1, 0, 0, 0, 3, 0, 0, 0, 1, 0, 0, 0, 0, 6, 8, 0, 0, 8, 5, 0, 0, 0, 1, 0, 0, 9, 0, 0, 0, 0, 4, 0, 2)
)

# Transform grid array into actual 9x9 2-dimensional array
function ConvertTo-SudokuGrid {
    param(
        $GridArray
    )
    $Row = 0
    $SudokuGrid = New-Object "System.Collections.ArrayList"
    do {
        $StartIndex = $Row * 9
        $SudokuGrid.add( $GridArray[$StartIndex..($StartIndex + 8)] ) | Out-Null
        $Row++
    }
    until($Row -gt 8)
    return $SudokuGrid
}

# Function to find the possible values for a given box
function Get-SudokuPossibilities {
    param(
        $x, # Column of target box
        $y # Row of target box
    )
    # Calculate the 3x3 box the number is in
    $XBox = switch -Regex ($x) {
        [0-2] { 0..2 ; break }
        [3-5] { 3..5 ; break }
        [6-8] { 6..8 ; break }
    }
    $YBox = switch -Regex ($y) {
        [0-2] { 0..2 ; break }
        [3-5] { 3..5 ; break }
        [6-8] { 6..8 ; break }
    }
    # See what numbers exist in the 3x3 box
    $BoxNumbers = foreach ($Column in $XBox) {
        $grid[$Column][$YBox]
    }

    # See what numbers exist in the column
    [array]$xNumbers = $grid[$x]
    
    # See what numbers exist in the row
    [array]$yNumbers = foreach ($Row in $Grid) {
        $Row[$y]
    } 

    $NotPossible = ($xNumbers + $yNumbers + $BoxNumbers) # Numbers it can't be
    $Possible = foreach ($Number in 1..9) { 
        if ($NotPossible -notcontains $Number) {
            $Number
        }
    }
    
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
        $Spacer = "───────"
        if ($y -eq 0 ) { "┌$Spacer┬$Spacer┬$Spacer┐" }
        if (3, 6 -contains $y ) { "├$Spacer┼$Spacer┼$Spacer┤" }
        @( ('│ ' + ($row[0..2] -join ' ')), ($row[3..5] -join ' '), (($row[6..8] -join ' ') + ' │') ) -join ' │ '
        if ($y -eq 8 ) { "└$Spacer┴$Spacer┴$Spacer┘" }
        $y++
    }
}

function Get-SudokuSolution {
    [cmdletbinding()]
    param(
        $Grid = $Grid,
        $Backtracks = 0,
        $AttemptedPossibilities = 0,
        $Zeros = $null,
        $StartTime = (Get-Date)
    )
    $Global:Backtracks = $Backtracks
    $Global:AttemptedPossibilities = $AttemptedPossibilities

    if (!$Zeros) {
        $Zeros = ($Grid | ForEach-Object { $_ -eq 0 }).count    
    }
    $Global:Solved = $false # To stop the recursive backlash later
    foreach ($Row in (0..8)) {
        foreach ($Column in (0..8)) {
            if ($Grid[$Row][$Column] -eq 0) {
                # Get the possible numbers for a given box
                $Possible = Get-SudokuPossibilities $Row $Column
                foreach ($Possibility in $Possible) { 
                    # Set the box to a possible value
                    $Global:AttemptedPossibilities ++
                    $Grid[$Row][$Column] = $Possibility
                    # Recursive call to continue attempting to solve unsolved boxes
                    Get-SudokuSolution -Grid $Grid -Backtracks $Global:Backtracks -AttemptedPossibilities $Global:AttemptedPossibilities -Zeros $Zeros -StartTime $StartTime
                    if ($Solved) {
                        # If the puzzle has been solved don't continue the function
                        break
                    }
                    else {
                        # If the puzzle hasn't been solved, and we're back, the solution didn't work
                        # Let's backtrack by zeroing out this box and trying another possibility
                        $Global:Backtracks ++
                        $Grid[$Row][$Column] = 0
                    }
                }
                return # There is an unsolvable box, let's backtrack
            }
        }
    }
    $Global:Solved = $True # If we got here, the puzzle has been solved
    Write-Output "Solved Puzzle:"
    Write-SudokuGrid -Grid $Grid # Write the solved puzzle to the screen
    $Output = [PSCustomObject]@{
        "Boxes Solved"            = $Zeros
        "Attempted Possibilities" = $AttemptedPossibilities
        "Times Backtracked"       = $Backtracks
        "Elapsed Solve Time"      = "$(New-TimeSpan $StartTime $(Get-Date))"
    }
    Write-Output $($Output | Format-Table)
}

$Grid = ConvertTo-SudokuGrid -GridArray $Grid
Write-Output "Unsolved Puzzle:"
Write-SudokuGrid -Grid $Grid # Write the unsolved puzzle to the screen
Get-SudokuSolution -Grid $Grid # Find a solution
