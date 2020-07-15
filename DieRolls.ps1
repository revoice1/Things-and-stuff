# Basic die rolling function
function Invoke-DieRoll {
    param(
        $count = 1, # Number of dice to roll
        $sides = 6, # Number of sides per rolled die
        [switch]$sum # Optional result to sum the rolls
    )
    if ($Sum) {
        $Rolls = Invoke-DieRoll -count $count -sides $sides
        return [PSCustomObject]@{
            Sum   = ($Rolls | Measure-Object -Sum).Sum
            Rolls = $Rolls -join ", "
        }
    }
    else {
        if ($Count -gt 1) {
            $Count--
            Invoke-DieRoll -count $Count -sides $Sides
        }
        $Roll = (1..$Sides) | Get-Random
        return $Roll
    }
}

# Function to roll D&D stats, i.e. roll 4d6 keep highest 3
# Optional hero switch to re-roll on a 1, once per die
function Invoke-StatRolls {
    param(
        [switch]$Hero #Reroll on 1, once per roll.
    )
    $Rolls = @()
    do {
        If ($Hero) {
            $Roll = @()
            do {
                $Result = Invoke-DieRoll -sides 6
                if ($Result -eq 1) {
                    $Roll += "(1)"
                    $Roll += Invoke-DieRoll -sides 6
                }
                else {
                    $Roll += $Result
                }
            } until(($Roll | Where-Object { $_ -gt 0 }).count -eq 4)
        }
        else {
            $Roll = Invoke-DieRoll -count 4 -sides 6
        }
        $Rolls += [PSCustomObject]@{
            result = ($Roll | Sort-Object -Descending | Select-Object -First 3 | Measure-Object -Sum).sum
            rolls  = $Roll -join ", "
        }
    } until($Rolls.count -eq 6)

    return $Rolls | Sort-Object -Descending -Property result
}

Invoke-StatRolls
