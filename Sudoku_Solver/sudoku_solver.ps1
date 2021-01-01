param(
    $Grid = @(8, 1, 2, 7, 5, 3, 6, 0, 9, 0, 0, 3, 6, 0, 0, 0, 0, 0, 0, 7, 0, 0, 9, 0, 2, 0, 0, 0, 5, 0, 0, 0, 7, 0, 0, 0, 0, 0, 9, 0, 4, 5, 7, 0, 0, 0, 0, 0, 1, 0, 0, 0, 3, 0, 0, 0, 1, 0, 0, 0, 0, 6, 8, 0, 0, 8, 5, 0, 0, 0, 1, 0, 0, 9, 0, 0, 0, 0, 4, 0, 2)
)

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

function Get-SudokuPossibilities {
    param(
        $x,
        $y
    )
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
    $BoxNumbers = foreach ($RowNumber in $XBox) {
        $grid[$RowNumber][$YBox]
    }

    [array]$xNumbers = $grid[$x]
    
    [array]$yNumbers = foreach ($Row in $Grid) {
        $row[$y]
    }

    $NotPossible = ($xNumbers + $yNumbers + $BoxNumbers)
    $Possible = (1..9) | Where-Object { $NotPossible -notcontains $_ }
    
    if ($Possible) {
        return $Possible
    }
    else {
        return $null
    }
}

function Write-SudokuGrid {
    param(
        $Grid = $Grid
    )
    $x = 0
    foreach ($row in $grid) {
        if (0 -eq $x ) { "┌───────┬───────┬───────┐" }
        if (3, 6 -contains $x ) { '├───────┼───────┼───────┤' }
        @(
            '│ ' + $($row[0..2] -join ' ')
            $row[3..5] -join ' '
            ($row[6..8] -join ' ') + ' │' 
        ) -join ' │ '
        if ($x -eq 8 ) { '└───────┴───────┴───────┘' }
        $x++
    }
}

function Get-SudokuSolution {
    param(
        $Grid = $Grid
    )
    $Global:StopProcessing = $false
    $x = 0
    foreach ($Row in $Grid) {
        $y = 0
        foreach ($Column in $Row) {
            if ($Grid[$x][$y] -eq 0) {
                $Possible = Get-SudokuPossibilities $x $y
                foreach ($Possibility in $Possible) { 
                    $Grid[$x][$y] = $Possibility
                    Get-SudokuSolution -Grid $Grid
                    if ($StopProcessing) {
                        break
                    }
                    else {
                        $Grid[$x][$y] = 0
                    }
                }
                return
            }
            $y++
        }
        $x++
    }
    $Global:StopProcessing = $True
    return write-SudokuGrid -Grid $Grid
}

$StartTime = Get-Date
Write-SudokuGrid -Grid $Grid
Get-SudokuSolution -Grid $Grid
Write-Output "Solve Time: $(New-TimeSpan $StartTime $(Get-Date))"
