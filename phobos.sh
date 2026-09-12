#!/bin/bash
#declares interpreter for this script

# const variable for versioning
readonly VERSION="0.0.1"

# contains file types that are already compressed, so there is no need to compress them again
readonly NO_COMPRESS_EXTENSIONS=(
    jpg jpeg png gif webp avif heic
    mp4 mkv avi mov webm
    mp3 flac wav ogg aac
    zip rar 7z gt bz2 xz zst
    pdf
)

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
    sudo cp phobos.sh /usr/local/bin/phobos
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

# searches through a directory recursively and create for every found file a .phbs-Container
save_folder() {
    # defining parameters as local variables
    local source_dir="$1"
    local backup_dir="$2"

    # -z means, if the string is empty
    # if so, the parameters are not given correctly
    if [[ -z "$source_dir" || -z "$backup_dir" ]]; then
        echo "Usage: phobos save_dir <quelle> <backup>"
        # ends function
        return 1
    fi

    # -d means, if path exists and if it is a directory
    # checks if path source directory exists
    if [[ ! -d "$source_dir" ]]; then
        echo "source directory not found: $source_dir"
        return 1
    fi

    # removing "/" at the end of path
    # %/ means, remove / if existing from the end 
    source_dir="${source_dir%/}"

    # searching through source directory (find works recursively)
    # -type f means, only normale files (f), directoryies will not be worked with
    # -print0: typically find will separate files with returns, which can cause errors, so -print0 separates files with a NUL-Byte
    find "$source_dir" -type f -print0 |
    # result of find will be given to the while - loop
    # IFS = Internal Field Separator (prohibits separation by space-characters)
    # read -r: reads input, -r prohibits special interpretation of "\"
    # -d '', read only up to the next NUL-character
    while IFS= read -r -d '' file; do
        local relative_path
        # calculate relative path (basically removes head-directory)
        relative_path="${file#"$source_dir"/}"

        local relative_dir
        # remove filename from path, so only directory path stays
        relative_dir="$(dirname "$relative_path")"

        local target_dir
        # relative_dir will be "." if file is present in source folder
        if [[ "$relative_dir" == "." ]]; then
            # file will be placed directly inside backup folder
            target_dir="$backup_dir"
        else
            # file will be placed at relative path with backup directory as head-directory
            target_dir="$backup_dir/$relative_dir"
        fi

        # create all missing parent-directories
        # -p blocks possible errors, if files already exist
        mkdir -p "$target_dir"

        # save the current file according to the protocoll provided in save_file to this path (target_dir)
        save_file "$file" "$target_dir"
    done
}


save_file() {
    # defining parameters as local variables
    local source="$1"
    local backup_dir="$2"

    # is provided file a existing normal file?
    if [[ ! -f "$source" ]]; then
        echo "File not found: $source"
        return 1
    fi

    # creates backup-directory (just to make shure it exists)
    mkdir -p "$backup_dir"

    local filename
    # basename removes path of file, which leaves only the name of the file
    filename=$(basename "$source")

    # %. removes the file ending
    # .phbs adds the new file ending (container format for phobos backup files)
    local container_name="${filename%.*}.phbs"
    local container="$backup_dir/$container_name"

    local original_size
    # stat reads informations about files
    # -c '%s', returns size of file in bytes
    original_size=$(stat -c '%s' "$source")

    local source_hash
    # xxhsum generates hash value for the file
    # | (pipe) takes results and hands them over to awk
    # normally xxhsum return sth like a7fe... ./.../file.txt, so $1 takes only hash-value
    source_hash=$(xxhsum "$source" | awk '{print $1}')

    # checks if a backup of the file already exists
    if [[ -f "$container" ]]; then

        local header_size
        # reading header size from existing backup
        header_size=$(head -c 8 "$container")

        # checks if the header size contains only numbers
        if [[ "$header_size" =~ ^[0-9]+$ ]]; then
            # converting bytes to decimal number
            header_size=$((10#$header_size))

            local header
            # reads the header from the existing container
            # skip=9: first 9 bytes wll be skipped because they contain the header size and the newline char
            header=$(dd if="$container" bs=1 skip=9 count="$header_size" 2>/dev/null)

            local backup_hash
            # reads the stored hash from the existing header
            backup_hash=$(printf '%s\n' "$header" |
                grep '^HASH=' |
                cut -d= -f2-)

            # compares hash of source file with hash stored in backup
            # if hashes are identically there is no need for a new backup
            if [[ "$source_hash" == "$backup_hash" ]]; then
                echo "Unchanged: $source"
                return 0
            fi
        fi
    fi

    echo "Sichere: $source"

    local compressed
    #mktemp creates temorary file
    compressed=$(mktemp)


    local compression_type

    if should_compress "$source"; then
        # compresses file 
        # -c: write compressed file to stdout instead of changing original file
        # result is pushed to temporary file by using '>'
        gzip -c "$source" > "$compressed"
        compression_type="gzip"
    else 
        cp "$source" "$compressed"
        compression_type="none"
    fi 


    # building custom header for .phbs files
    # VERSION of container-format, if it will be updated in the future
    # HASH of uncompressed originale file
    # COMPRESSION states the type of compression 
    # FILENAME saves original filename
    # ORIGINAL_SIZE saves originale size of file

    local header
    header="PHBS
VERSION=1
HASH=$source_hash
COMPRESSION=$compression_type
FILENAME=$filename
ORIGINAL_SIZE=$original_size"

    local header_size
    # calculating amout of bytes for header
    # printf ... returns header and adds additional newline
    # wc -c: counts bytes 
    header_size=$(printf '%s\n' "$header" | wc -c)
    # curly brackets group multiply commands
    {
        # prints header size as a int (%d) with 8 figures and fills missing places with 0
        printf '%08d\n' "$header_size"
        # prints header
        printf '%s\n' "$header"
        # add the compressed file
        cat "$compressed"
    } > "$container"
    # remvoe temporary file
    rm -f "$compressed"

    echo "Erstellt: $container"
}


restore_file() {
    # defining parameters as local variables
    local container="$1" # path to .phbs file
    local restore_dir="$2" # path in which file shall be restored

    # checking if .phbs-container exists
    if [[ ! -f "$container" ]]; then
        echo "Container not found: $container"
        return 1
    fi

    local header_size
    # reading header size (first 8 Bytes contain size of header)
    header_size=$(head -c 8 "$container")

    # validate header size
    # if header size only contains numbers (REGEX)
    # ^ beginning of text
    # [0-9] numbers from 0 to 9
    # + one or multple of those
    # $ end of text
    if ! [[ "$header_size" =~ ^[0-9]+$ ]]; then
        echo "Invalid PHBS-Container."
        return 1
    fi

    # convert to decimal number
    # in bash numbers with leading 0 will normally be convertet to octal-numbers
    # 10# demands the decimal interpretation
    header_size=$((10#$header_size))

    local header
    # reading header from container
    # skip=9 : skipping first 9 bytes because they only contain header_size an newline
    # dd : reads data from file and returns only an specified area 
    # bs=1 : block size is 1 Byte
    # count="$header_size" : reads exactly amount of bytes as the size of header
    # 2>/dev/null : redirect error messages to /dev/null, so they will not be promtet to the terminal (2 stands for stderr)
    header=$(dd if="$container" bs=1 skip=9 count="$header_size" 2>/dev/null)

    # checking if header starts with PHBS to make shure it is a phobos-container
    # grep -q : search but do not return result
    if ! grep -q '^PHBS$' <<< "$header"; then
        echo "Invalid PHBS-Container."
        return 1
    fi

    # variable for header values
    local filename
    local expected_hash
    local compression

    # reading values from header and plotting them into the variables by using a pipeline
    # cut -d= -f2- : -d= states that = will be used as separating character; -f2- takes filed 2 upto end
    filename=$(printf '%s\n' "$header" | grep '^FILENAME=' | cut -d= -f2-)
    expected_hash=$(printf '%s\n' "$header" | grep '^HASH=' | cut -d= -f2-)
    compression=$(printf '%s\n' "$header" | grep '^COMPRESSION=' | cut -d= -f2-)

    # cecking if filename exits, if not, file can not be restored
    if [[ -z "$filename" ]]; then
        echo "Header contains no filename."
        return 1
    fi




    # if target directory does not already exists it will be created
    # -p creates also the parent-directories
    mkdir -p "$restore_dir"

    local compressed
    # creating temporary file for compression
    compressed=$(mktemp)

    # extracting payload from container and writing it to temporary file
    tail -c +$((10 + header_size)) "$container" > "$compressed"

    # creating target path
    local output="$restore_dir/$filename"

    echo "Restoring: $output"

    # checking compression type
    case "$compression" in 
        # if type is gzip, file has been compressed using gzip and can be properly decompressed
        gzip) 
            # restoring file
            # gzip -d : decrompressing
            # -c : write result to stdcout, instead of overriting source file
            # > : moves output to correct file
            if ! gzip -dc "$compressed" > "$output"; then
                echo "Error while decompression"
                rm -f "$compressed" "$output"
                return 1
            fi
            ;;
        # if type is none, file has not been compressed, because it was a non-compress file
        # so it will only be copied
        none)
            cp "$compressed" "$output"
            ;;
        *)
            echo "Not supported compression type: $compression"
            rm -f "$compressed"
            return 1
            ;;
    esac



    # remove temporary file
    rm -f "$compressed"


    local actual_hash
    # generate hash of the restored file
    actual_hash=$(xxhsum "$output" | awk '{print $1}')

    # if those hashes dont match, sth went wrong during process (e.g. file was damaged)
    if [[ "$actual_hash" != "$expected_hash" ]]; then
        echo "Error: Hashes are not consistent!"
        echo "Expected: $expected_hash"
        echo "Received: $actual_hash"
        # remove faulty file
        rm -f "$output"
        return 1
    fi

    echo "Successfully recovered: $output"
}


restore_dir() {
    # defining parameters as local variable
    local backup_dir="$1" # backup-directory
    local restore_dir="$2" # target-directory for restoring

    # if either of those parameters is empty, the funtion is not called properly
    if [[ -z "$backup_dir" || -z "$restore_dir" ]]; then
        echo "Usage: phobos restore_dir <backup> <ziel>"
        return 1
    fi

    # checking if backup-directory exists properly
    if [[ ! -d "$backup_dir" ]]; then
        echo "Backup-directory not found: $backup_dir"
        return 1
    fi

    # removing possible / from the end of paths
    backup_dir="${backup_dir%/}"
    restore_dir="${restore_dir%/}"

    # creating target-directory
    mkdir -p "$restore_dir"

    # find : searches through directory recursively
    # -type f : only uses normal files /no directories
    # -name '*.phbs' : only files that end with .phbs will be used
    # print0 : files will be separated by NULL-Byte (because filenames can in theory contain \n)
    find "$backup_dir" -type f -name '*.phbs' -print0 |
    # -r : \ will not be special interpeted
    # -d '' : using NULL-Byte as separting character
    while IFS= read -r -d '' container; do

        local relative_path
        relative_path="${container#"$backup_dir"/}"
        # removeing .phbs ending
        relative_path="${relative_path%.phbs}"

        local target_dir
        target_dir="$restore_dir/$(dirname "$relative_path")"

        # creating target directory
        mkdir -p "$target_dir"

        echo "Restore: $container"

        # restore file is delageted to designated function
        if ! restore_file "$container" "$target_dir"; then
            echo "Error with: $container"
        fi

    done
}
    

# reads meta-data from .phbs files
info() {
    #defining parameters as local variables
    local container="$1" # path to .phbs-container

    # checking if .phsb-file exits
    if [[ ! -f "$container" ]]; then
        echo "File not found: $container"
        return 1
    fi

    local header_size
    # reading first 8 bytes of header as header size
    header_size=$(head -c 8 "$container")
    # converting header size to decimal number
    header_size=$((10#$header_size))

    # validating header size using REGEX, so only numbers are contained
    if ! [[ "$header_size" =~ ^[0-9]+$ ]]; then
        echo "Invalid PHBS-Container."
        return 1
    fi

    local header
    # reading header from byte 10
    header=$(tail -c +"$((9))" "$container" | head -c "$header_size")

    # checking if container is phbs-container
    if ! grep -q "^PHBS$" <<< "$header"; then
        echo "Invalid PHBS-Container."
        return 1
    fi

    local version
    local hash
    local compression
    local filename
    local original_size

    # reading values from header
    version=$(grep '^VERSION=' <<< "$header" | cut -d= -f2-)
    hash=$(grep '^HASH=' <<< "$header" | cut -d= -f2-)
    compression=$(grep '^COMPRESSION=' <<< "$header" | cut -d= -f2-)
    filename=$(grep '^FILENAME=' <<< "$header" | cut -d= -f2-)
    original_size=$(grep '^ORIGINAL_SIZE=' <<< "$header" | cut -d= -f2-)

    local container_size
    # calculating size of container
    container_size=$(stat -c '%s' "$container")

    local compressed_size
    # calculating compressed size (subtracting the not-payload-ares from container size)
    compressed_size=$((container_size - header_size - 9))

    # Ausgabe
    echo "PHBS Container"
    echo "--------------"
    echo "Version:          $version"
    echo "Filename:         $filename"
    echo "Compression:      $compression"
    echo "Hash:             $hash"
    echo "Original Size:    $original_size bytes"
    echo "Compressed Size:  $compressed_size bytes"

    # calculating compression rate
    # only if orignal file is not empty
    if (( original_size > 0 )); then
        local compression_percent
        # -v : hand values over to awk
        # printf "%.1f" : floating point number with exactly 1 number after decimal point ist printed
        compression_percent=$(awk \
            -v original="$original_size" \
            -v compressed="$compressed_size" \
            'BEGIN { printf "%.1f", (1 - compressed / original) * 100 }')

        # print compression rate
        echo "Compression Rate: ${compression_percent}%"
    fi
}

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
