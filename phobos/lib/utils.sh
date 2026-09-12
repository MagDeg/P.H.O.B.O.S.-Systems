# helper function, that returns, if a file type shall be compressed or not
# returns 0 if shall be compressed and 1 otherwise
should_compress() {
    local file="$1"


    # extracting file ending
    local ext="${file##*.}"

    # force letter so be lowercase
    ext="${ext,,}"
    
    # @ return all elements of array one by one
    for no_ext in "${NO_COMPRESS_EXTENSIONS[@]}"; do
        if [[ "$ext" == "$no_ext" ]]; then
            return 1
        fi
    done
    return 0
}

#install script as global command (adds phobos to path)
add_to_path() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    sudo mkdir -p /usr/local/lib/phobos
    sudo cp "$script_dir/phobos.sh" /usr/local/bin/phobos
    sudo cp -r "$script_dir/lib/." /usr/local/lib/phobos/
    sudo chmod +x /usr/local/bin/phobos

    echo "Added PHOBOS to local path!"
}


check_dependencies() {
    # exists a runnable command called xxhsum?
    # if installed, sth. like this will be returned /usr/bin/xxhsum
    # &> /dev/null suppresses a displayed massage (sth. like a data garbage can)
    if ! command -v xxhsum &> /dev/null; then
        # in case system runns on ubuntu/debian needed tools will be installed with apt manager
        if command -v apt &> /dev/null; then
            sudo apt update
            # -y automatically approves all questions privded with yes
            sudo apt install -y xxhash

        # in case using fedora/RHEL
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y xxhash
        # in case using Arch Linux
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm xxhash
        # in case there is no supported package manager
        else
            echo "No supported package manager was found."
            # ends total script
            exit 1
        fi
    fi
}

# returns version of phobos system
version() {
    echo "$VERSION"
}