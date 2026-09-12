#!/bin/bash
#declares interpreter for this script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/backup.sh"
source "$SCRIPT_DIR/lib/restore.sh"
source "$SCRIPT_DIR/lib/container.sh"

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