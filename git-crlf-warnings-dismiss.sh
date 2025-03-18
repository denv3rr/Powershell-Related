# CRLF/LF related configs for git
# Warning will say: warning: CRLF will be replaced by LF in <file_name>

# Warning dismissal options:
# ---------------------------------------------------

# Set Git to Use LF for All Commits (Cross-Platform Development)
git config --global core.autocrlf input

# Disable the Warning (Only Suppresses the Message)
git config --global core.safecrlf false

# Force Git to Always Use LF (for Linux/macOS Development)
git config --global core.eol lf
git config --global core.autocrlf false

# Convert All Files to LF Immediately
git add --renormalize .
git commit -m "Normalize line endings"

# To Check Your Current Line Ending Configuration Run:
git config --global --list | grep crlf