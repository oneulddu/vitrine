# Palette check

    ./build.sh && build/palette-check

runs `Redesigned/Kit/SGRPalette.m` on the Mac (as Mac Catalyst, for UIKit): a blue cover with a pale border along
its foot, read once by its bottom edge (the player's field) and once by its main color (a playlist, album or
artist page, `mainColor`). The edge has to come out gray and the main color blue. It prints PASS or FAIL; the exit
status is the number of failures.

`bash harness/palette/field-check.sh` runs the production artwork field and flow layer on Mac Catalyst
with controlled palette replies. It covers artwork arriving before Colours is selected, reusing retained
artwork after a completed mode change, and late palette replies in both directions. The palette service,
player-transition observer and unused Fluid renderer are test doubles; no Spotify or GPU run is implied.
The temporary executable and its debug symbols are removed on exit.
