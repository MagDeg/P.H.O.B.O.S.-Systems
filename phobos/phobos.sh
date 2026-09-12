#!/bin/bash
#declares interpreter for this script

# determining the real path of the currently executed PHOBOS script
#
# readlink -f resolves symbolic links.
#
# This is important because /usr/local/bin/phobos is a symbolic link
# to the actual PHOBOS script in /usr/local/lib/phobos/.
local_script="$(readlink -f "${BASH_SOURCE[0]}")"

# extracting the directory in which the actual phobos.sh is located
SCRIPT_DIR="$(dirname "$local_script")"

# checking if a separate lib directory exists
#
# In the development environment the structure is:
#
# phobos/
# ├── phobos.sh
# └── lib/
#     ├── config.sh
#     ├── utils.sh
#     └── ...
#
# During installation the library files are currently copied directly
# next to phobos.sh:
#
# /usr/local/lib/phobos/
# ├── phobos.sh
# ├── config.sh
# ├── utils.sh
# └── ...
if [[ -d "$SCRIPT_DIR/lib" ]]; then
    LIB_DIR="$SCRIPT_DIR/lib"
else
    LIB_DIR="$SCRIPT_DIR"
fi

# loading all PHOBOS libraries
source "$LIB_DIR/config.sh"
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/backup.sh"
source "$LIB_DIR/restore.sh"
source "$LIB_DIR/container.sh"

# case statement to handle phobos-commands
case "$1" in 
    --version)
        version
        ;;
    save_file)
        save_file "$2" "$3"
        ;; 
    check_dependancies)
        check_dependancies
        ;;
    save)
        if [[ -d "$2" ]]; then
            save_folder "$2" "$3"
        elif [[ -f "$2" ]]; then
            save_file "$2" "$3"
        else 
            echo "Source not found: $2"
            exit 1
        fi
        ;;
    info)
        info "$2"
        ;;
    add_to_path)
        add_to_path
        ;;
    restore)
        # checks if input parameter is a directory
        if [[ -d "$2" ]]; then 
            restore_dir "$2" "$3"
        elif [[ -f "$2" ]]; then 
            restore_file "$2" "$3"
        else 
            echo "Backup not found: $2"
            exit 1
        fi
        ;;
    *)
        echo "Ungültiger Befehl"
        ;;
esac