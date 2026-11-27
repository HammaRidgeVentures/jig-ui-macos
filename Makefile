# Jig Screen. Every target needs the Command Line Tools only.
.PHONY: app install check snapshot

app:        ## build build/Jig Screen.app
	bash scripts/bundle.sh

install:    ## build it, copy it to /Applications, open it
	bash scripts/bundle.sh --install

check:      ## run the checks
	swift run jig-screen-check 2>&1 | grep -v "search path"

snapshot:   ## draw the screen into docs/screen.png, from the sample data
	swift build 2>&1 | grep -v "search path" || true
	"$$(swift build --show-bin-path)/JigScreen" --snapshot docs/screen.png
