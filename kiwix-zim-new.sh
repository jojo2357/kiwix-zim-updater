#!/bin/bash

VER="3.0"

# Set required packages Array
PackagesArray=('wget')

# Set Script Arrays
LocalZIMArray=(); ZIMNameArray=(); ZIMRootArray=(); ZIMVerArray=(); RawURLArray=(); URLArray=(); PurgeArray=(); ZimSkipped=(); DownloadArray=(); MasterRootArray=(); MasterZIMArray=();

# Set Script Strings
SCRIPT="$(readlink -f "$0")"
SCRIPTFILE="$(basename "$SCRIPT")"
SCRIPTPATH="$(dirname "$SCRIPT")"
SCRIPTNAME="$0"
ARGS=( "$@" )
BRANCH="main"
SKIP_UPDATE=0
DEBUG=1 # This forces the script to default to "dry-run/simulation mode"
MIN_SIZE=0
MAX_SIZE=0
CALCULATE_CHECKSUM=0
VERIFY_LIBRARY=0
BaseURL="https://download.kiwix.org/zim/"
ZIMPath=""

declare -A ZimRootCache
ZimRootCache[NotFound]=""

# master_scrape - Scrape "download.kiwix.org/zim/" for roots (directories) and zims (files)
master_scrape() {

    # Clear out Arrays, for good measure.
    unset RawMasterRootArray
    unset MasterRootArray
    unset DirtyMasterRootArray
    unset RawMasterZIMArray
    unset MasterZIMArray
    unset DirtyMasterZIMArray
    unset MasterZIMRootArray

    RawLibrary=$(wget -q -O - "https://library.kiwix.org/catalog/v2/entries?count=-1" | grep -i 'application/x-zim')

    IFS=$'\n' read -r -d '' -a FileSizes < <( echo "$RawLibrary" | grep -ioP '(?<=length=")\d+(?=")' ); unset IFS

    hrefs=$(echo "$RawLibrary" | grep -ioP "(?<=href=\")[\w:\/\-.]+(?=\.meta4\")" | grep -ioP "$BaseURL\K.*")

    IFS=$'\n' read -r -d '' -a RemoteFiles < <( echo "$hrefs" | grep -ioP "[^/]/\K[\w:\/\-.]+" ); unset IFS
    IFS=$'\n' read -r -d '' -a Basenames < <( echo "$hrefs" | grep -ioP "[^/]/\K[\w:\/\-.]+(?=\d{4}-\d{2}\.zim)" ); unset IFS
    IFS=$'\n' read -r -d '' -a RemotePaths < <( echo "$hrefs" | grep -ioP "^[\w:\/\-.]+" ); unset IFS # distinct from above for processing speed reasons
    IFS=$'\n' read -r -d '' -a RemoteCategory < <( echo "$hrefs" | grep -ioP "^[^/]+" ); unset IFS

#    echo "File Sizes: ${#FileSizes[@]}"
#    echo "Bazez: ${#Basenames[@]}"
#    echo "Filez: ${#RemoteFiles[@]}"
#    echo "Paths: ${#RemotePaths[@]}"
#    echo "Categories: ${#RemoteCategory[@]}"

#    # Parse Website for Root Directories
#    IFS=$'\n' read -r -d '' -a RawMasterRootArray < <( wget -q "$BaseURL?F=0" -O - | tr "\t\r\n'" '   "' | grep -i -o '<a[^>]\+href[ ]*=[ \t]*"[^"]\+">[^<]*</a>' | sed -e 's/^.*"\([^"]\+\)".*$/\1/g' && printf '\0' ); unset IFS
#
#    # Parse for Valid Responces and save into MasterRootArray
#    for x in "${RawMasterRootArray[@]}"; do
#        [[ $x == [a-z]* ]] && MasterRootArray+=("$x")
#    done
#
#    hits=0
#    a=0
#    # For each Root Directory...
#    for i in "${MasterRootArray[@]}"
#    do
#        # Call ProgressBar Function
#        ((++a))
#        ProgressBar ${a} ${#MasterRootArray[@]}
#
##        IFS=$'\n' read -r -d '' -a RawMasterZIMArray < <( echo "$RawLibrary" | grep -ioP '(?<=href=")[\w:\/\-.]+(?=\.meta4")' | grep -ioP "$BaseURL[^/]+/\K.+" ); unset IFS
#
#        # Parse Website Directory for ZIMs
#        IFS=$'\n' read -r -d '' -a RawMasterZIMArray < <( wget -q "$BaseURL$i?F=0" -O - | tr "\t\r\n'" '   "' | grep -i -o '<a[^>]\+href[ ]*=[ \t]*"[^"]\+">[^<]*</a>' | sed -e 's/^.*"\([^"]\+\)".*$/\1/g' && printf '\0' ); unset IFS
#
#        # Parse for Valid Responces and save into MasterZIMArray
#        for z in "${RawMasterZIMArray[@]}"; do
#            [[ $z == [a-z]* ]] && MasterZIMArray+=("${z%???????????}") && MasterZIMRootArray+=("$i") && hits=$((hits+1))
#        done
#    done

    # Housekeeping...
    unset RawMasterRootArray
    unset DirtyMasterRootArray
    unset RawMasterZIMArray
    unset DirtyMasterZIMArray
}

# self_update - Script Self-Update Function
self_update() {
    echo -e "\033[1;33m1. Checking for Script Updates...\033[0m"
    echo
    # Check if script path is a git clone.
    #   If true, then check for update.
    #   If false, skip self-update check/funciton.
    if [ $SKIP_UPDATE -eq 1 ]; then
        echo -e "\033[0;33m   Check Skipped\033[0m"
    elif [[ -d "$SCRIPTPATH/.git" ]]; then
        echo -e "\033[1;32m   ✓ Git Clone Detected: Checking Script Version...\033[0m"
        cd "$SCRIPTPATH" || exit 1
        timeout 1s git fetch --quiet
        timeout 1s git diff --quiet --exit-code "origin/$BRANCH" "$SCRIPTFILE"
        [ $? -eq 1 ] && {
            echo -e "\033[0;31m   ✗ Version: Mismatched\033[0m"
            echo
            echo -e "\033[1;33m1a. Fetching Update...\033[0m"
            echo
            if [ -n "$(git status --porcelain)" ];  then
                git stash push -m 'local changes stashed before self update' --quiet
            fi
            git pull --force --quiet
            git checkout $BRANCH --quiet
            git pull --force --quiet
            echo -e "\033[1;32m   ✓ Update Complete. Running New Version. Standby...\033[0m"
            sleep 3
            cd - > /dev/null || exit 1

            # Execute new instance of the new script
            exec "$SCRIPTNAME" "${ARGS[@]}"

            # Exit this old instance of the script
            exit 1
        }
        echo -e "\033[1;32m   ✓ Version: Current\033[0m"
    else
        echo -e "\033[0;31m   ✗ Git Clone Not Detected: Skipping Update Check\033[0m"
    fi
    echo
}

# usage_example - Show Usage and Exit
usage_example() {
    echo 'Usage: ./kiwix-zim.sh <options> /full/path/'
    echo
    echo '    /full/path/                Full path to ZIM directory'
    echo
    echo 'Options:'
    echo '    -c, --calculate-checksum   Verifies that the downloaded files were not corrupted, but can take a while for large downloads.'
    echo '    -f, --verify-library       Verifies that the entire library has the correct checksums as found online.'
    echo '                               For this reason, a file `library.sha256` will be left in your library for running sha256sum manually'
    echo '    -d, --disable-dry-run      Dry-Run Override.'
    echo '                               *** Caution ***'
    echo
    echo '    -h, --help                 Show this usage and exit.'
    echo '    -p, --skip-purge           Skips purging any replaced ZIMs.'
    echo '    -u, --skip-update          Skips checking for script updates (very useful for development).'
    echo '    -n <size>, --min-size      Minimum ZIM Size to be downloaded.'
    echo '                               Specify units include M Mi G Gi, etc. See `man numfmt`'
    echo '    -x <size>, --max-size      Maximum ZIM Size to be downloaded.'
    echo '                               Specify units include M Mi G Gi, etc. See `man numfmt`'
    echo '    -l <location>, --location  Country Code to prefer mirrors from'
    echo
    exit 0
}

# onlineZIMcheck - Fetch/Scrape download.kiwix.org for single ZIM
#onlineZIMcheck() {
#    # Clear out Arrays, for good measure.
#    unset URLArray
#    unset RawURLArray
#
#    # Parse RAW Website - The online directory checked is based upon the ZIM's Root
#    Extension="$(echo "${ZIMRootArray[$1]}" | grep -ioP '[^/]+')"
#    if ! [[ -v "ZimRootCache[$Extension]" ]]; then
#        URL="$BaseURL${ZIMRootArray[$1]}?F=0"
#        ZimRootCache["$Extension"]="$(wget -q "$URL" -O -)"
#    fi
#    IFS=$'\n' read -r -d '' -a RawURLArray < <( echo "${ZimRootCache[$Extension]}" | tr "\t\r\n'" '   "' | grep -i -o '<a[^>]\+href[ ]*=[ \t]*"[^"]\+">[^<]*</a>' | sed -e 's/^.*"\([^"]\+\)".*$/\1/g' && printf '\0' ); unset IFS
#
#    # Parse for Valid Releases
#    for x in "${RawURLArray[@]}"; do
#        [[ $x == [a-z]* ]] && DirtyURLArray+=("$x")
#    done
#
#    # Let's sort the array in reverse to ensure newest versions are first when we dig through.
#    #  This does slow down the search a little, but ensures the newest version is picked first every time.
#    URLArray=($(printf "%s\n" "${DirtyURLArray[@]}" | sort -r)) # Sort Array
#    unset Extension
#    unset DirtyURLArray # Housekeeping...
#}

# flags - Flag and ZIM Processing Functions
flags() {
    echo -e "\033[1;33m2. Preprocessing...\033[0m"
    echo
    echo -e "\033[1;34m  -Validating ZIM directory...\033[0m"

    # Let's identify which argument is the ZIM directory path and if it's an actual directory.
    if [[ -d ${1} ]]; then
        ZIMPath=$1
    elif [[ -d ${2} ]]; then
        ZIMPath=$2
    elif [[ -d ${3} ]]; then
        ZIMPath=$3
    else # Um... no ZIM directory path provided? Okay, let's show the usage and exit.
        echo -e "\033[0;31m  ✗ Missing or Invalid\033[0m"
        echo
        usage_example
    fi
    echo -e "\033[1;32m    ✓ Valid\033[0m"
    echo

    # Check for and add if missing, trailing slash.
    [[ "${ZIMPath}" != */ ]] && ZIMPath="${ZIMPath}/"

    # Now we need to check for ZIM files.
    shopt -s nullglob # This is in case there are no matching files

    # Load all found ZIM(s) w/path into LocalZIMArray
    IFS=$'\n' LocalZIMArray=("$ZIMPath"*.zim); unset IFS

    # Check that ZIM(s) were actually found/loaded.
    if [ ${#LocalZIMArray[@]} -eq 0 ]; then # No ZIM(s) were found in the directory... I guess there's nothing else for us to do, so we'll Exit.
        echo -e "\033[0;31m    ✗ No ZIMs found. Exiting...\033[0m"
        exit 0
    fi

    echo -e "\033[1;34m  -Building online ZIM list...\033[0m"

    # Build online ZIM list.
    master_scrape

    echo
    echo

    # Populate ZIM arrays from found ZIM(s)
    echo -e "\033[1;34m  -Parsing ZIM(s)...\033[0m"

    for ((i=0; i<${#LocalZIMArray[@]}; i++)); do  # Loop through local ZIM(s).
        ZIMNameArray[$i]=$(basename "${LocalZIMArray[$i]}")  # Extract file name.
        filename=$(basename "${LocalZIMArray[$i]}" | grep -ioP "[\w:\/\-.]+(?=\d{4}-\d{2}\.zim$)")  # Extract file name.
#        IFS='_' read -ra fields <<< "${ZIMNameArray[$i]}"; unset IFS  # Break the filename into fields delimited by the underscore '_'

        # Search MasterZIMArray for the current local ZIM to discover the online Root (directory) for the URL
        for ((z=0; z<${#Basenames[@]}; z++)); do
            if [[ ${Basenames[$z]} == "$filename" ]]; then # Match Found (ignore the filename datepart).
                ZIMRootArray[$i]="$z"
                break
            else # No Match Found.
                ZIMRootArray[$i]="-1"
            fi
        done

        if [[ ZIMRootArray[$i] -eq -1 ]]; then
            echo -e "\033[0;31m    ✗ ${ZIMNameArray[$i]}  No online match found.\033[0m"
        else
            echo -e "\033[1;32m    ✓ ${ZIMNameArray[$i]}  [${RemoteCategory[${ZIMRootArray[$i]}]}]\033[0m"
        fi
    done

    # Online ZIM(s) have a semi-strict filename standard we can use for matching to our local ZIM(s).
#    for ((i=0; i<${#LocalZIMArray[@]}; i++)); do  # Loop through local ZIM(s).
#        ZIMNameArray[$i]=$(basename "${LocalZIMArray[$i]}")  # Extract file name.
#        IFS='_' read -ra fields <<< "${ZIMNameArray[$i]}"; unset IFS  # Break the filename into fields delimited by the underscore '_'
#
#        # Search MasterZIMArray for the current local ZIM to discover the online Root (directory) for the URL
#        for ((z=0; z<${#MasterZIMArray[@]}; z++)); do
#            if [[ ${MasterZIMArray[$z]} == "${ZIMNameArray[$i]%???????????}" ]]; then # Match Found (ignore the filename datepart).
#                ZIMRootArray[$i]=${MasterZIMRootArray[$z]}
#                break
#            else # No Match Found.
#                ZIMRootArray[$i]="NotFound"
#            fi
#        done
#        ZIMVerArray[$i]=$(echo "${fields[-1]}" | cut -d "." -f1)  # Last element (minus the extension) is the Version - YYYY-MM
#
#        if [[ ${ZIMRootArray[$i]} == "NotFound" ]]; then
#            echo -e "\033[0;31m    ✗ ${ZIMNameArray[$i]}  No online match found.\033[0m"
#        else
#            echo -e "\033[1;32m    ✓ ${ZIMNameArray[$i]}  [${ZIMRootArray[$i]}]\033[0m"
#        fi
#    done

    echo
    echo -e "\033[0;32m    ${#ZIMNameArray[*]} ZIM(s) found.\033[0m"
    echo
}

# mirror_search - Find ZIM URL Priority #1 mirror from meta4 Function
mirror_search() {
    IsMirror=0
    DownloadURL=""
    RemotePath=${RemotePaths[$z]}
    # Silently fetch (via wget) the associated meta4 xml and extract the mirror URL marked priority="1"
    MetaInfo=$(wget -q -O - "$BaseURL$RemotePath.meta4?country=$COUNTRY_CODE")
    ExpectedSize=$(echo "$MetaInfo" | grep '<size>' | grep -Po '\d+')
    ExpectedHash=$(echo "$MetaInfo" | grep '<hash type="sha-256">' | grep -Poi '(?<="sha-256">)[a-f\d]{64}(?=<)')
    RawMirror=$(echo "$MetaInfo" | grep 'priority="1"' | grep -Po 'https?://[^ ")]+(?=</url>)')
    # Check that we actually got a URL (this could probably be done better). If no mirror URL, default back to direct URL.
    if [[ $RawMirror == *"http"* ]]; then # Mirror URL found
        DownloadURL=$RawMirror # Set the mirror URL as our download URL
        IsMirror=1
    else # Mirror URL not found
        DownloadURL=${CleanDownloadArray[$z]} # Set the direct download URL as our download URL
    fi
}

# ProgressBar - Simple Progress Bar
function ProgressBar {
    bar_size=25
    bar_char_done="#"
    bar_char_todo="-"
    bar_percentage_scale=2
    current="$1"
    total="$2"

    # calculate the progress in percentage
    percent=$(bc <<< "scale=$bar_percentage_scale; 100 * $current / $total" )

    # The number of done and todo characters
    done=$(bc <<< "scale=0; $bar_size * $percent / 100" )
    todo=$(bc <<< "scale=0; $bar_size - $done" )

    # build the done and todo sub-bars
    done_sub_bar=$(printf "%${done}s" | tr " " "${bar_char_done}")
    todo_sub_bar=$(printf "%${todo}s" | tr " " "${bar_char_todo}")

    # output the bar
    if [[ $percent == "100.00" ]]; then
        echo -ne "\033[1;32m\r    [${done_sub_bar}${todo_sub_bar}] ${percent}%\033[0m"
    else
        echo -ne "\r    [${done_sub_bar}${todo_sub_bar}] ${percent}%"
    fi
}

#########################
# Begin Script Execute
#########################

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      usage_example
      ;;
    -d|--disable-dry-run)
      DEBUG=0
      shift # discard argument
      ;;
    -v|--version)
      echo "$VER"
      exit 0
      ;;
    -p|--skip-purge)
      SKIP_PURGE=1
      shift # discard argument
      ;;
    -n|--min-size)
      shift # discard -n argument
      MIN_SIZE=$(numfmt --from=auto "$1") # convert passed arg to bytes
      shift # discard value
      ;;
    -x|--max-size)
      shift # discard -x argument
      MAX_SIZE=$(numfmt --from=auto "$1") # convert passed arg to bytes
      shift # discard value
      ;;
    -l|--location)
      shift # discard -l argument
      if [[ "$1" =~ ^[A-Z]{2}$ ]]; then
        COUNTRY_CODE=$1 # convert passed arg to bytes
      else
        COUNTRY_CODE=""
        echo "Invlaid country code, falling back to default kiwix behavior"
      fi
      shift # discard value
      ;;
    -c|--calculate-checksum)
      CALCULATE_CHECKSUM=1
      shift
      ;;
    -f|--verfiy-library)
      VERIFY_LIBRARY=1
      CALCULATE_CHECKSUM=1
      shift
      ;;
    -u|--skip-update)
      SKIP_UPDATE=1
      shift
      ;;
    *)
      # We can either parse the arg here, or just tuck it away for safekeeping
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift # past argument
      ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters that we skipped earlier

clear # Clear screen

# Display Header
echo "=========================================="
echo " kiwix-zim"
echo "       download.kiwix.org ZIM Updater"
echo
echo "   v$VER by DocDrydenn and jojo2357"
echo "=========================================="
echo
echo "            DRY-RUN/SIMULATION"
[[ $DEBUG -eq 1 ]] && echo "               - ENABLED -"
[[ $DEBUG -eq 1 ]] && echo
[[ $DEBUG -eq 1 ]] && echo "           Use '-d' to disable."
[[ $DEBUG -eq 0 ]] && echo "               - DISABLED -"
[[ $DEBUG -eq 0 ]] && echo
[[ $DEBUG -eq 0 ]] && echo "             !!! Caution !!!"
echo
echo "=========================================="
echo

# First, Self-Update Check.
# Shouldnt this be first? it is not dependent on anything else and resets everything, so may as well reset it before getting all invested?
self_update

# Second, Flag Check.
flags "$@"

echo
echo -e "\033[1;33m4. Processing ZIM(s)...\033[0m"
echo

AnyDownloads=0

for ((i=0; i<${#ZIMNameArray[@]}; i++)); do
    RemoteIndex=${ZIMRootArray[$i]}
    [[ $RemoteIndex -eq -1 ]] && DownloadArray+=( 0 ) && continue
    FileName=${ZIMNameArray[$i]}
    echo -e "\033[1;34m  - $FileName:\033[0m"
    [[ -f "$ZIMPath.~lock.$FileName" ]] && echo -e "\033[0;33m    Incomplete download detected\n\033[1;32m    ✓ Online Version Found\033[0m" && DownloadArray+=( 1 ) && AnyDownloads=1 && continue

    MatchingSize=${FileSizes[$RemoteIndex]}
    MatchingFileName=${RemoteFiles[$RemoteIndex]}
    MatchingFullPath=${RemotePaths[$RemoteIndex]}
    MatchingCategory=${RemoteCategory[$RemoteIndex]}

    if [[ "$MatchingFileName" == "$FileName" ]]; then
        if [ $VERIFY_LIBRARY -eq 1 ]; then
            DownloadArray+=( 1 )
            AnyDownloads=1
            echo -e "\033[1;32m    ✓ Online Version Found\033[0m"
        else
            DownloadArray+=( 0 )
            echo "    ✗ No new update"
        fi
    else
        if [ $VERIFY_LIBRARY -eq 1 ]; then
            if wget -S --spider -q -O - "$BaseURL$MatchingCategory$FileName.meta4">/dev/null 2>&1; then
                DownloadArray+=( 1 )
                AnyDownloads=1
                echo -e "\033[1;32m    ✓ Online Version Found\033[0m"
            else
                DownloadArray+=( 0 )
                echo "    ✗ Online Version Not Found"
            fi
        else
            DownloadArray+=( 1 )
            AnyDownloads=1
            echo -e "\033[1;32m    ✓ Update found! --> $(echo "$MatchingFileName" | grep -oP '\d{4}-\d{2}(?=\.zim$)')\033[0m"
        fi
    fi

#    unset Zmfields # Housekeeping
#    IFS='_' read -ra Zmfields <<< ${ZIMNameArray[$i]}; unset IFS # Break name into fields
#    unset Onfields # Housekeeping
#    IFS='_' read -ra Onfields <<< ${ZIMRootArray[$i]}; unset IFS # Break URL name into fields
#
#    for ((x=0; x<${#URLArray[@]}; x++)); do
#        unset Onfields # Housekeeping
#        IFS='_' read -ra Onfields <<< ${URLArray[$x]}; unset IFS # Break URL name into fields
#        match=1
#        # Here we need to iterate through the fields in order to find a full match.
#        for ((t=0; t<$((${#Onfields[@]} - 1)); t++)); do
#            # Do they have the same field counts?
#            if [ ${#Onfields[@]} = ${#Zmfields[@]} ]; then # Field counts match, keep going.
#                # Are the current fields equal?
#                if [ "${Onfields[$t]}" != "${Zmfields[$t]}" ]; then # Not equal, abort and goto the next entry.
#                    match=0
#                    break # <-- This (and the one below, give a 55% increase in speed/performance. Woot!)
#                fi
#            else # Field counts don't match, abort and goto the next entry.
#                match=0
#                break # <-- This (and the one above, give a 55% increase in speed/performance. Woot!)
#            fi
#        done
#        # Field counts were equal and all fields matched. We have a Winner!
#        if [[ $match -eq 1 ]]; then
#            #  Now we need to check if it is newer than the local.
#            OnlineVersion=$(echo "${URLArray[$x]}" | sed 's/^.*_\([^_]*\)$/\1/' | cut -d "." -f1)
#            OnlineYear=$(echo "$OnlineVersion" | cut -d "-" -f1)
#            OnlineMonth=$(echo "$OnlineVersion" | cut -d "-" -f2)
#            ZIMYear=$(echo "${ZIMVerArray[$i]}" | cut -d "-" -f1)
#            ZIMMonth=$(echo "${ZIMVerArray[$i]}" | cut -d "-" -f2)
#
#            if [ $VERIFY_LIBRARY -eq 1 ] || [[ $InterruptedDownload -eq 1 ]]; then
#                if [ "$OnlineYear" -eq "$ZIMYear" ] && [ "$OnlineMonth" -eq "$ZIMMonth" ]; then
#                    UpdateFound=2
#                    echo -e "\033[1;32m    ✓ Online Version Found\033[0m"
#                    DownloadArray+=( "$BaseURL${ZIMRootArray[$i]}/${URLArray[$x]}" )
#                    PurgeArray+=( "$ZIMPath${ZIMNameArray[$i]}" )
#                    break # No need to conitnue checking the URLArray.
#                fi
#            else
#                # Check if online Year is older than local Year.
#                if [ "$OnlineYear" -lt "$ZIMYear" ]; then # Online Year is older, skip.
#                    continue
#                # Check if Years are equal, but online Month is older than local Month.
#                elif [ "$OnlineYear" -eq "$ZIMYear" ] && [ "$OnlineMonth" -le "$ZIMMonth" ]; then # Years are equal, but Month is older, skip.
#                    continue
#                elif [ $UpdateFound -eq 0 ]; then # Online is newer than local. Double Winner!
#                    UpdateFound=1
#                    echo -e "\033[1;32m    ✓ Update found! --> $OnlineVersion\033[0m"
#                    DownloadArray+=( "$BaseURL${ZIMRootArray[$i]}/${URLArray[$x]}" )
#                    PurgeArray+=( "$ZIMPath${ZIMNameArray[$i]}" )
#                    break # No need to conitnue checking the URLArray.
#                fi
#            fi
#        fi
#    done
#    if [[ $UpdateFound -eq 0 ]]; then # No update was found.
#        if [ $VERIFY_LIBRARY -eq 1 ]; then
#            echo "    ✗ Online Version Not Found"
#        else
#            echo "    ✗ No new update"
#        fi
#    fi
#
#    echo
done

unset ZimRootCache

# TODO Start handling all the ZIMs
echo -e "\033[1;33m5. Downloading New ZIM(s)...\033[0m"
echo

# Let's clear out any possible duplicates
#CleanDownloadArray=($(printf "%s\n" "${DownloadArray[@]}" | sort -u)) # Sort Array
#CleanPurgeArray=($(printf "%s\n" "${PurgeArray[@]}" | sort -u))

# Let's Start the download process, but only if we have actual downloads to do.
if [ $AnyDownloads -eq 1 ]; then
    for ((z=0; z<${#ZIMNameArray[@]}; z++)); do # Iterate through the download queue.
        [[ ${DownloadArray[$z]} -eq 0 ]] && continue

        mirror_search # Let's look for a mirror URL first.

        if [ $VERIFY_LIBRARY -eq 0 ]; then
            [[ $IsMirror -eq 0 ]] && echo -e "\033[1;34m  Download (direct) : $DownloadURL\033[0m"
            [[ $IsMirror -eq 1 ]] && echo -e "\033[1;34m  Download (mirror) : $DownloadURL\033[0m"
        fi

        FileName=${RemoteFiles[$z]} # Extract New/Updated ZIM file name.
        FilePath=$ZIMPath$FileName # Set destination path with file name
        LockFilePath="$ZIMPath.~lock.$FileName" # Set destination path with file name

        RequiresDownload=0

        if [ $VERIFY_LIBRARY -eq 0 ] && [[ -f $FilePath ]] && ! [[ -f $LockFilePath ]]; then # New ZIM already found, and no interruptions, we don't need to download it.
            [[ $DEBUG -eq 0 ]] && echo -e "\033[0;32m  ✓ Status : ZIM already exists on disk. Skipping download.\033[0m"
            [[ $DEBUG -eq 1 ]] && echo -e "\033[0;32m  ✓ Status : *** Simulated ***  ZIM already exists on disk. Skipping download.\033[0m"
            echo
        elif [[ $MIN_SIZE -gt 0 ]] && [[ $ExpectedSize -lt $MIN_SIZE ]]; then
            if [ $VERIFY_LIBRARY -eq 0 ]; then
                [[ $DEBUG -eq 0 ]] && echo -e "\033[0;32m  ✓ Status : ZIM smaller than specified minimum size (minimum: $(numfmt --to=iec-i $MIN_SIZE), download size: $(numfmt --to=iec-i "$ExpectedSize")). Skipping download.\033[0m"
                [[ $DEBUG -eq 1 ]] && echo -e "\033[0;32m  ✓ Status : *** Simulated ***  ZIM smaller than specified minimum size (minimum: $(numfmt --to=iec-i $MIN_SIZE), download size: $(numfmt --to=iec-i "$ExpectedSize")). Skipping download.\033[0m"
            else
                [[ $DEBUG -eq 0 ]] && echo -e "\033[0;33m  ✓ Status : ZIM smaller than specified minimum size (minimum: $(numfmt --to=iec-i $MIN_SIZE), download size: $(numfmt --to=iec-i "$ExpectedSize")). Skipping check.\033[0m"
                [[ $DEBUG -eq 1 ]] && echo -e "\033[0;33m  ✓ Status : *** Simulated ***  ZIM smaller than specified minimum size (minimum: $(numfmt --to=iec-i $MIN_SIZE), download size: $(numfmt --to=iec-i "$ExpectedSize")). Skipping check.\033[0m"
            fi
            echo
        elif [[ $MAX_SIZE -gt 0 ]] && [[ $ExpectedSize -gt $MAX_SIZE ]]; then
            if [ $VERIFY_LIBRARY -eq 0 ]; then
                [[ $DEBUG -eq 0 ]] && echo -e "\033[0;32m  ✓ Status : ZIM larger than specified maximum size (maximum: $(numfmt --to=iec-i $MAX_SIZE), download size: $(numfmt --to=iec-i "$ExpectedSize")). Skipping download.\033[0m"
                [[ $DEBUG -eq 1 ]] && echo -e "\033[0;32m  ✓ Status : *** Simulated ***  ZIM larger than specified maximum size (maximum: $(numfmt --to=iec-i $MAX_SIZE), download size: $(numfmt --to=iec-i "$ExpectedSize")). Skipping download.\033[0m"
            else
                [[ $DEBUG -eq 0 ]] && echo -e "\033[0;33m  ✓ Status : ZIM larger than specified maximum size (maximum: $(numfmt --to=iec-i $MAX_SIZE), download size: $(numfmt --to=iec-i "$ExpectedSize")). Skipping check.\033[0m"
                [[ $DEBUG -eq 1 ]] && echo -e "\033[0;33m  ✓ Status : *** Simulated ***  ZIM larger than specified maximum size (maximum: $(numfmt --to=iec-i $MAX_SIZE), download size: $(numfmt --to=iec-i "$ExpectedSize")). Skipping check.\033[0m"
            fi
            echo
        elif [ $VERIFY_LIBRARY -eq 0 ]; then # New ZIM not found, so we'll go ahead and download it.
            RequiresDownload=1
            if [[ -f $LockFilePath ]]; then
                [[ $DEBUG -eq 0 ]] && echo -e "\033[1;32m  ✓ Status : ZIM download was interrupted. Continuing...\033[0m"
                [[ $DEBUG -eq 1 ]] && echo -e "\033[1;32m  ✓ Status : *** Simulated ***  ZIM download was interrupted. Continuing...\033[0m"
            else
                [[ $DEBUG -eq 0 ]] && echo -e "\033[1;32m  ✓ Status : ZIM doesn't exist on disk. Downloading...\033[0m"
                [[ $DEBUG -eq 1 ]] && echo -e "\033[1;32m  ✓ Status : *** Simulated ***  ZIM doesn't exist on disk. Downloading...\033[0m"
            fi
            echo
        else
            # lockfile implies an incomplete download
            if [[ -f $LockFilePath ]]; then
                echo "Incomplete download detected" >> download.log
                echo -e "\033[0;33m  Status: Incomplete download detected, resuming\033[0m"

                [[ $IsMirror -eq 0 ]] && echo -e "\033[1;34m  Download (direct) : $DownloadURL\033[0m"
                [[ $IsMirror -eq 1 ]] && echo -e "\033[1;34m  Download (mirror) : $DownloadURL\033[0m"
                RequiresDownload=1
            else
                # actually verify the file
                echo -e "\033[1;34m  Calculating checksum for : $FileName\033[0m"
                echo "  Calculating checksum for : $FileName" >> download.log
                echo "$ExpectedHash $FilePath" > "$FilePath.sha256"
                if [[ ${#ExpectedHash} -ne 64 ]]; then
                    echo "    This hash doesn't look quite right...skipping"
                elif ! sha256sum --status -c "$FilePath.sha256"; then
                    RequiresDownload=1
                    if [[ $DEBUG -eq 0 ]]; then
                        echo -e "\033[1;31m  ✗ Status : Checksum failed, removing corrupt file\033[0m"
                        echo "  ✗ Status : Checksum failed, removing corrupt file" >> download.log
                        rm "$FilePath"
                    else
                        echo -e "\033[1;31m  ✗ Status : *** Simulated *** Checksum failed, removing corrupt file ($FilePath)\033[0m"
                    fi

                    echo
                else
                    echo -e "\033[1;32m  ✓ Status : Checksum passed\033[0m"
                    echo "  ✓ Status : Checksum passed" >> download.log

                    [[ $DEBUG -eq 0 ]] && echo "End : $(date -u)" >> download.log
                    [[ $DEBUG -eq 1 ]] && echo "End : $(date -u) *** Simulation ***" >> download.log

                    echo
                    continue
                fi
                rm "$FilePath.sha256"
            fi
        fi

        # Here is where we actually download the files and log to the download.log file.
        if [[ $RequiresDownload -eq 1 ]]; then
            echo >> download.log
            echo "=======================================================================" >> download.log
            echo "File : $FileName" >> download.log
            [[ $IsMirror -eq 0 ]] && echo "URL (direct) : $DownloadURL" >> download.log
            [[ $IsMirror -eq 1 ]] && echo "URL (mirror) : $DownloadURL" >> download.log
            echo >> download.log
            [[ $DEBUG -eq 0 ]] && echo "Start : $(date -u)" >> download.log
            [[ $DEBUG -eq 1 ]] && echo "Start : $(date -u) *** Simulation ***" >> download.log
            echo >> download.log

            # Before we actually download, let's just check to see that it isn't already in the folder.
            if [[ -f "$LockFilePath" ]]; then
                [[ $DEBUG -eq 0 ]] && wget -q --show-progress -c -O "$FilePath" "$DownloadURL" 1>>download.log && echo # Download new ZIM
                [[ $DEBUG -eq 1 ]] && echo "  Continue Download : $FilePath" >> download.log
            elif [[ -f $FilePath ]]; then # New ZIM already found, we don't need to download it.
                [[ $DEBUG -eq 1 ]] && echo "  Download : New ZIM already exists on disk. Skipping download." >> download.log
            else # New ZIM not found, so we'll go ahead and download it.
                [[ $DEBUG -eq 0 ]] && touch "$LockFilePath"
                [[ $DEBUG -eq 0 ]] && wget -q --show-progress -c -O "$FilePath" "$DownloadURL" 1>>download.log && echo # Download new ZIM
                [[ $DEBUG -eq 1 ]] && echo "  Download : $FilePath" >> download.log
            fi
        fi

        if [[ $CALCULATE_CHECKSUM -eq 1 ]]; then
            echo -e "\033[1;34m  Calculating checksum for : $FileName\033[0m"
            echo "$ExpectedHash $FilePath" > "$FilePath.sha256"
            if [[ ${#ExpectedHash} -ne 64 ]]; then
                echo "    This hash doesn't look quite right...skipping"
            elif [[ $DEBUG -eq 0 ]] && ! sha256sum --status -c "$FilePath.sha256"; then
                echo -e "\033[0;31m  ✗ Checksum failed, removing corrupt file\033[0m"
                rm "$FilePath"
                DownloadFailed=1
            else
                if [[ $DEBUG -eq 0 ]]; then
                  echo -e "\033[0;32m  ✓ Checksum passed\033[0m"
                else
                  echo -e "\033[0;32m  ✓ *** Simulated *** Checksum passed\033[0m"
                fi
            fi
            rm "$FilePath.sha256"
            rm "$LockFilePath"
            echo
        fi

        echo >> download.log
        [[ $DownloadFailed -eq 1 ]] && echo " !!! DOWNLOAD FAILED !!!" >> download.log

        # in all of these cases, we will not re-pruge and will leave the lockfile so we know to resume later
        if [[ $DownloadFailed -eq 1 ]] || [[ $SKIP_PURGE -eq 1 ]] || [[ $VERIFY_LIBRARY -eq 1 ]]; then
            [[ $DEBUG -eq 0 ]] && echo "End : $(date -u)" >> download.log
            [[ $DEBUG -eq 1 ]] && echo "End : $(date -u) *** Simulation ***" >> download.log
            continue
        fi

        [[ $RequiresDownload -eq 1 ]] && rm "$LockFilePath"

        ########################################

        OldZIM=${ZIMNameArray[$z]}
        NewZIM=$FileName

        echo -e "\033[0;34m  Old : $OldZIM\033[0m"
        echo "  Old : $OldZIM" >> download.log
        echo -e "\033[1;34m  New : $NewZIM\033[0m"
        echo "  New : $NewZIM" >> download.log
        # Check for the new ZIM on disk.
        if [[ -f $NewZIM ]]; then # New ZIM found
            if [[ $DEBUG -eq 0 ]]; then
                echo -e "\033[1;32m  ✓ Status : New ZIM verified. Old ZIM purged.\033[0m"
                echo "  ✓ Status : New ZIM verified. Old ZIM purged." >> download.log
                [[ -f "$OldZIM" ]] && rm "$OldZIM" # Purge old ZIM
            else
                echo -e "\033[1;32m  ✓ Status : *** Simulated ***\033[0m"
                echo "  ✓ Status : *** Simulated ***" >> download.log
            fi
        else # New ZIM not found. Something went wrong, so we will skip this purge.
            if [[ $DEBUG -eq 0 ]]; then
                echo -e "\033[0;31m  ✗ Status : New ZIM failed verification. Old ZIM purge skipped.\033[0m"
                echo "  ✗ Status : New ZIM failed verification. Old ZIM purge skipped." >> download.log
            else
                if [[ $RequiresDownload -eq 0 ]]; then
                    echo -e "\033[1;32m  ✓ Status : *** Simulated ***\033[0m"
                    echo "  ✓ Status : *** Simulated ***" >> download.log
                else
                    echo -e "\033[1;33m  ✗ Status : *** Simulated *** Zim was skipped, and will not be purged\033[0m"
                    echo "  ✗ Status : *** Simulated *** Zim purge skipped" >> download.log
                fi
            fi
        fi
        echo
        echo >> download.log

        #########################################

        [[ $DEBUG -eq 0 ]] && echo "End : $(date -u)" >> download.log
        [[ $DEBUG -eq 1 ]] && echo "End : $(date -u) *** Simulation ***" >> download.log
    done
else
    echo -e "\033[0;32m    ✓ Download: Nothing to download.\033[0m"
    echo
fi
unset CleanDownloadArray # Housekeeping
#unset DownloadArray     # Housekeeping, I know, but we can't do this here - we need it to verify new ZIM(s) during the purge function.
