# Renders `make help` from the Makefiles themselves:
#   ##@ Section name          -> section header
#   target: ... ## text       -> "  target   text"
# Works with BSD awk (macOS) and GNU awk.
BEGIN { FS = ":.*## " }
/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($0, 5); next }
/^[a-zA-Z0-9_-]+:.*## / { printf "  \033[36m%-20s\033[0m %s\n", $1, $2 }
