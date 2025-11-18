#!/bin/bash

# Change to the root web development directory using the HOME variable
cd "$HOME/Documents/MywebsiteGIT"

# Replace the current shell process with a new instance of the interactive shell.
# This is the trick that ensures the directory change (cd) persists 
# after the script finishes, leaving you in the target directory.
exec "$SHELL" -i
