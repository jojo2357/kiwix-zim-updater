#!/bin/bash

VER="2.1"

# Set required packages Array
PackagesArray=('curl')

# Set Script Arrays
LocalZIMArray=(); ZIMNameArray=(); ZIMRootArray=(); ZIMVerArray=(); RawURLArray=(); URLArray=(); PurgeArray=(); DownloadArray=(); MasterRootArray=(); MasterZIMArray=();

# Set Script Strings
SCRIPT="$(readlink -f "$0")"
SCRIPTFILE="$(basename "$SCRIPT")"
SCRIPTPATH="$(dirname "$SCRIPT")"
SCRIPTNAME="$0"
ARGS=( "$@" )
BRANCH="main"
DEBUG=1 # This forces the script to default to "dry-run/simulation mode"
BaseURL="https://download.kiwix.org/zim/"
ZIMPath=""

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

    # Parse Website for Root Directories
    IFS=$'\n' read -r -d '' -a RawMasterRootArray < <( wget -q "$BaseURL" -O - | tr "\t\r\n'" '   "' | grep -i -o '<a[^>]\+href[ ]*=[ \t]*"[^"]\+">[^<]*</a>' | sed -e 's/^.*"\([^"]\+\)".*$/\1/g' && printf '\0' ); unset IFS

    # Parse for Valid Responces and save into MasterRootArray
    for x in "${RawMasterRootArray[@]}"; do
        [[ $x == [a-z]* ]] && MasterRootArray+=("$x")
    done
  
    a=0
    # For each Root Directory...
    for i in "${MasterRootArray[@]}"
    do
        # Call ProgressBar Function
        ((++a))
        ProgressBar ${a} ${#MasterRootArray[@]}
        
        # Parse Website Directory for ZIMs
        IFS=$'\n' read -r -d '' -a RawMasterZIMArray < <( wget -q "$BaseURL$i" -O - | tr "\t\r\n'" '   "' | grep -i -o '<a[^>]\+href[ ]*=[ \t]*"[^"]\+">[^<]*</a>' | sed -e 's/^.*"\([^"]\+\)".*$/\1/g' && printf '\0' ); unset IFS

        # Parse for Valid Responces and save into MasterZIMArray
        for z in "${RawMasterZIMArray[@]}"; do
            [[ $z == [a-z]* ]] && MasterZIMArray+=("${z%???????????}") && MasterZIMRootArray+=("$i")
        done
        
    done 
    
    # Housekeeping...
    unset RawMasterRootArray
    unset DirtyMasterRootArray
    unset RawMasterZIMArray
    unset DirtyMasterZIMArray
}

# self_update - Script Self-Update Function
self_update() {
    echo -e "\033[1;33m3. Checking for Script Updates...\033[0m"
    echo
    # Check if script path is a git clone.
    #   If true, then check for update.
    #   If false, skip self-update check/funciton.
    if [[ -d "$SCRIPTPATH/.git" ]]; then
        echo -e "\033[1;32m   ✓ Git Clone Detected: Checking Script Version...\033[0m"
        cd "$SCRIPTPATH" || exit 1
        timeout 1s git fetch --quiet
        timeout 1s git diff --quiet --exit-code "origin/$BRANCH" "$SCRIPTFILE"
        [ $? -eq 1 ] && {
            echo -e "\033[0;31m   ✗ Version: Mismatched\033[0m"
            echo
            echo -e "\033[1;33m3a. Fetching Update...\033[0m"
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
}

# packages - Required Package(s) Check/Install Function
packages() {
    echo -e "\033[1;33m2. Checking Required Packages...\033[0m"
    echo
    install_pkgs=" "
    for keys in "${!PackagesArray[@]}"; do
        REQUIRED_PKG=${PackagesArray[$keys]}
        PKG_OK=$(command -v "$REQUIRED_PKG")
        if [ "" = "$PKG_OK" ]; then
            echo -e "\033[0;31m  ✗ $REQUIRED_PKG: Not Found\033[0m"
            echo
            install_pkgs+=" $REQUIRED_PKG"
        else
            echo -e "\033[1;32m  ✓ $REQUIRED_PKG: Found\033[0m"
            echo
        fi
    done
    if [ " " != "$install_pkgs" ]; then
        echo
        echo -e "\033[1;33m2a. Installing Missing Packages:\033[0m"
        echo
        [[ $DEBUG -eq 1 ]] && apt --dry-run -y install "$install_pkgs" # Simulation
        [[ $DEBUG -eq 0 ]] && apt install -y "$install_pkgs" # Real
        echo
    fi
}

# usage_example - Show Usage and Exit
usage_example() {
    echo 'Usage: ./kiwix-zim.sh <h|d> /full/path/'
    echo
    echo '    /full/path/       Full path to ZIM directory'
    echo
    echo '    -d or d           Dry-Run Override.'
    echo '                      *** Caution ***'
    echo
    echo '    -h or h           Show this usage and exit.'
    echo
    exit 0
}

# onlineZIMcheck - Fetch/Scrape download.kiwix.org for single ZIM
onlineZIMcheck() {   
    # Clear out Arrays, for good measure.
    unset URLArray
    unset RawURLArray

    # Parse RAW Website - The online directory checked is based upon the ZIM's Root
    URL="$BaseURL${ZIMRootArray[$1]}/"
    IFS=$'\n' read -r -d '' -a RawURLArray < <( wget -q "$URL" -O - | tr "\t\r\n'" '   "' | grep -i -o '<a[^>]\+href[ ]*=[ \t]*"[^"]\+">[^<]*</a>' | sed -e 's/^.*"\([^"]\+\)".*$/\1/g' && printf '\0' ); unset IFS

    # Parse for Valid Releases
    for x in "${RawURLArray[@]}"; do
        [[ $x == [a-z]* ]] && DirtyURLArray+=("$x")
    done

    # Let's sort the array in reverse to ensure newest versions are first when we dig through.
    #  This does slow down the search a little, but ensures the newest version is picked first every time.
    URLArray=($(printf "%s\n" "${DirtyURLArray[@]}" | sort -r)) # Sort Array
    unset DirtyURLArray # Housekeeping...
}

# flags - Flag and ZIM Processing Functions
flags() {
    echo -e "\033[1;33m1. Preprocessing...\033[0m"
    echo
    echo -e "\033[1;34m  -Building online ZIM list...\033[0m"
    
    # Build online ZIM list.
    master_scrape
    
    echo
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

    # Populate ZIM arrays from found ZIM(s)
    echo -e "\033[1;34m  -Parsing ZIM(s)...\033[0m"

    # Online ZIM(s) have a semi-strict filename standard we can use for matching to our local ZIM(s).
    for ((i=0; i<${#LocalZIMArray[@]}; i++)); do  # Loop through local ZIM(s).
        ZIMNameArray[$i]=$(basename "${LocalZIMArray[$i]}")  # Extract file name.
        IFS='_' read -ra fields <<< "${ZIMNameArray[$i]}"; unset IFS  # Break the filename into fields delimited by the underscore '_'
        
        # Search MasterZIMArray for the current local ZIM to discover the online Root (directory) for the URL
        for ((z=0; z<${#MasterZIMArray[@]}; z++)); do         
            if [[ ${MasterZIMArray[$z]} == "${ZIMNameArray[$i]%???????????}" ]]; then # Match Found (ignore the filename datepart).
                ZIMRootArray[$i]=${MasterZIMRootArray[$z]}
                break
            else # No Match Found.
                ZIMRootArray[$i]="NotFound"
            fi
        done
        ZIMVerArray[$i]=$(echo "${fields[-1]}" | cut -d "." -f1)  # Last element (minus the extension) is the Version - YYYY-MM
        
        if [[ ${ZIMRootArray[$i]} == "NotFound" ]]; then
            echo -e "\033[0;31m    ✗ ${ZIMNameArray[$i]}  No online match found.\033[0m"
        else
            echo -e "\033[1;32m    ✓ ${ZIMNameArray[$i]}  [${ZIMRootArray[$i]}]\033[0m"
        fi
    done

    echo
    echo -e "\033[0;32m    ${#ZIMNameArray[*]} ZIM(s) found.\033[0m"
    echo
}

# mirror_search - Find ZIM URL Priority #1 mirror from meta4 Function
mirror_search() {
    IsMirror=0
    DownloadURL=""
    Direct=${CleanDownloadArray[$z]}
    # Silently fetch (via curl) the associated meta4 xml and extract the mirror URL marked priority="1"
    RawMirror=$(curl -s "$Direct".meta4 | grep 'priority="1"' | grep -Eo 'https?://[^ ")]+')
    # Check that we actually got a URL (this could probably be done better). If no mirror URL, default back to direct URL.
    if [[ $RawMirror == *"http"* ]]; then # Mirror URL found
        CleanMirror=${RawMirror%</url>} # We need to remove the trailing "</url>".
        DownloadURL=$CleanMirror # Set the mirror URL as our download URL
        IsMirror=1
    else # Mirror URL not found
        DownloadURL=${CleanDownloadArray[$z]} # Set the direct download URL as our download URL
    fi
}

# zim_download - ZIM download Function
zim_download() {
    echo -e "\033[1;33m5. Downloading New ZIM(s)...\033[0m"
    echo
    
    # Let's clear out any possible duplicates
    CleanDownloadArray=($(printf "%s\n" "${DownloadArray[@]}" | sort -u)) # Sort Array
    
    # Let's Start the download process, but only if we have actual downloads to do.
    if [ ${#CleanDownloadArray[@]} -ne 0 ]; then
        for ((z=0; z<${#CleanDownloadArray[@]}; z++)); do # Iterate through the download queue.
            mirror_search # Let's look for a mirror URL first.
            FileName=$(basename "$DownloadURL") # Extract New/Updated ZIM file name.
            FilePath=$ZIMPath$FileName # Set destination path with file name

            [[ $IsMirror -eq 0 ]] && echo -e "\033[1;34m  Download (direct) : $DownloadURL\033[0m"
            [[ $IsMirror -eq 1 ]] && echo -e "\033[1;34m  Download (mirror) : $DownloadURL\033[0m"

            if [[ -f $FilePath ]]; then # New ZIM already found, we don't need to download it.
                [[ $DEBUG -eq 0 ]] && echo -e "\033[0;32m  ✓ Status : ZIM already exists on disk. Skipping download.\033[0m"
                [[ $DEBUG -eq 1 ]] && echo -e "\033[0;32m  ✓ Status : *** Simulated ***  ZIM already exists on disk. Skipping download.\033[0m"
            else # New ZIM not found, so we'll go ahead and download it.
                [[ $DEBUG -eq 0 ]] && echo -e "\033[1;32m  ✓ Status : ZIM doesn't exist on disk. Downloading...\033[0m"
                [[ $DEBUG -eq 1 ]] && echo -e "\033[1;32m  ✓ Status : *** Simulated ***  ZIM doesn't exist on disk. Downloading...\033[0m"
            fi
            echo

            # Here is where we actually download the files and log to the download.log file.
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
            if [[ -f $FilePath ]]; then # New ZIM already found, we don't need to download it.
                #[[ $DEBUG -eq 0 ]] && curl -L -o "$FilePath" "$DownloadURL" |& tee -a download.log && echo # Download new ZIM
                [[ $DEBUG -eq 1 ]] && echo "  Download : New ZIM already exists on disk. Skipping download." >> download.log
            else # New ZIM not found, so we'll go ahead and download it.
                [[ $DEBUG -eq 0 ]] && curl -L -o "$FilePath" "$DownloadURL" |& tee -a download.log && echo # Download new ZIM
                [[ $DEBUG -eq 1 ]] && echo "  Download : $FilePath" >> download.log
            fi
            echo >> download.log
            [[ $DEBUG -eq 0 ]] && echo "End : $(date -u)" >> download.log
            [[ $DEBUG -eq 1 ]] && echo "End : $(date -u) *** Simulation ***" >> download.log
        done
    else
        echo -e "\033[0;32m    ✓ Download: Nothing to download.\033[0m"
        echo
    fi
    unset CleanDownloadArray # Housekeeping
    #unset DownloadArray     # Housekeeping, I know, but we can't do this here - we need it to verify new ZIM(s) during the purge function.
}

# zim_purge - ZIM purge Function
zim_purge() {
    echo -e "\033[1;33m6. Purging Old ZIM(s)...\033[0m"
    echo

    # Let's clear out any possible duplicates.
    CleanPurgeArray=($(printf "%s\n" "${PurgeArray[@]}" | sort -u)) # Sort Array
    
    # Let's start the purge process, but only if there are items to purge.
    if [ ${#CleanPurgeArray[@]} -ne 0 ]; then
        echo >> purge.log
        echo "=======================================================================" >> purge.log
        [[ $DEBUG -eq 0 ]] && date -u >> purge.log    
        [[ $DEBUG -eq 1 ]] && echo "$(date -u) *** Simulation ***" >> purge.log
        echo >> purge.log      
        for ((z=0; z<${#CleanPurgeArray[@]}; z++)); do
            # Before we actually purge, we want to check that the new ZIM downloaded and exists.
            #   Fist, we have to figure out what the old ZIM was. To do this we'll have to iterate through the old Arrays. Ugh. Total PITA.
            for ((o=0; o<${#PurgeArray[@]}; o++)); do
                if [[ ${PurgeArray[$o]} = "${CleanPurgeArray[$z]}" ]]; then
                    NewZIM=$ZIMPath$(basename "${DownloadArray[$o]}")
                    OldZIM=${PurgeArray[$o]}
                    break # Found it. No reason to keep looping.
                fi
            done
            echo -e "\033[0;34m  Old : $OldZIM\033[0m"
            echo "  Old : $OldZIM" >> purge.log
            echo -e "\033[1;34m  New : $NewZIM\033[0m"
            echo "  New : $NewZIM" >> purge.log
            # Check for the new ZIM on disk.
            if [[ -f $NewZIM ]]; then # New ZIM found
                if [[ $DEBUG -eq 0 ]]; then
                    echo -e "\033[1;32m  ✓ Status : New ZIM verified. Old ZIM purged.\033[0m"
                    echo "  ✓ Status : New ZIM verified. Old ZIM purged." >> purge.log
                    [[ -f $OldZIM ]] && rm "${CleanPurgeArray[$z]}" # Purge old ZIM
                else
                    echo -e "\033[1;32m  ✓ Status : *** Simulated ***\033[0m"
                    echo "  ✓ Status : *** Simulated ***" >> purge.log
                fi
            else # New ZIM not found. Something went wrong, so we will skip this purge.
                if [[ $DEBUG -eq 0 ]]; then
                    echo -e "\033[0;31m  ✗ Status : New ZIM failed verification. Old ZIM purge skipped.\033[0m"
                    echo "  ✗ Status : New ZIM failed verification. Old ZIM purge skipped." >> purge.log
                else
                    echo -e "\033[1;32m  ✓ Status : *** Simulated ***\033[0m"
                    echo "  ✓ Status : *** Simulated ***" >> purge.log
                fi
            fi
            echo
            echo >> purge.log
        done
        [[ $DEBUG -eq 0 ]] && date -u >> purge.log    
        [[ $DEBUG -eq 1 ]] && echo "$(date -u) *** Simulation ***" >> purge.log
    else
        echo -e "\033[0;32m    ✓ Purge: Nothing to purge.\033[0m"
        echo
    fi
    unset PurgeArray # Housekeeping
    unset CleanPurgeArray # Housekeeping
    
    # Ah, now we can properly Housekeep these Arrays.
    unset DownloadArray
    unset MasterZIMArray
    unset MasterRootArray
    unset MasterZIMRootArray
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

# Check for HELP argument first.
{ [ "$1" = "h" ] || [ "$1" = "-h" ]; } && usage_example
{ [ "$2" = "h" ] || [ "$2" = "-h" ]; } && usage_example
{ [ "$3" = "h" ] || [ "$3" = "-h" ]; } && usage_example

# Check for Dry-Run Override argument
{ [ "$1" = "d" ] || [ "$1" = "-d" ]; } && DEBUG=0
{ [ "$2" = "d" ] || [ "$2" = "-d" ]; } && DEBUG=0
{ [ "$3" = "d" ] || [ "$3" = "-d" ]; } && DEBUG=0

clear # Clear screen

# Display Header
echo "=========================================="
echo " kiwix-zim"
echo "       download.kiwix.org ZIM Updater"
echo
echo "   v$VER by DocDrydenn"
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

# First, Flag Check.
flags "$1" "$2" "$3"

# Second, Package Check.
packages

# Third, Self-Update Check.
self_update
echo

echo -e "\033[1;33m4. Processing ZIM(s)...\033[0m"
echo
for ((i=0; i<${#ZIMNameArray[@]}; i++)); do
    onlineZIMcheck "$i"     
    echo -e "\033[1;34m  - ${ZIMNameArray[$i]}:\033[0m"
    UpdateFound=0
    unset Zmfields # Housekeeping
    IFS='_' read -ra Zmfields <<< ${ZIMNameArray[$i]}; unset IFS # Break name into fields
    for ((x=0; x<${#URLArray[@]}; x++)); do
        unset Onfields # Housekeeping
        IFS='_' read -ra Onfields <<< ${URLArray[$x]}; unset IFS # Break URL name into fields
        match=1
        # Here we need to iterate through the fields in order to find a full match.
        for ((t=0; t<$((${#Onfields[@]} - 1)); t++)); do 
            # Do they have the same field counts?
            if [ ${#Onfields[@]} = ${#Zmfields[@]} ]; then # Field counts match, keep going.
                # Are the current fields equal?
                if [ "${Onfields[$t]}" != "${Zmfields[$t]}" ]; then # Not equal, abort and goto the next entry.
                    match=0
                    break # <-- This (and the one below, give a 55% increase in speed/performance. Woot!)
                fi
            else # Field counts don't match, abort and goto the next entry.
                match=0
                break # <-- This (and the one above, give a 55% increase in speed/performance. Woot!)
            fi
        done
        # Field counts were equal and all fields matched. We have a Winner!
        if [[ $match -eq 1 ]]; then
            #  Now we need to check if it is newer than the local.     
            OnlineVersion=$(echo "${URLArray[$x]}" | sed 's/^.*_\([^_]*\)$/\1/' | cut -d "." -f1)
            OnlineYear=$(echo "$OnlineVersion" | cut -d "-" -f1)
            OnlineMonth=$(echo "$OnlineVersion" | cut -d "-" -f2)
            ZIMYear=$(echo "${ZIMVerArray[$i]}" | cut -d "-" -f1)
            ZIMMonth=$(echo "${ZIMVerArray[$i]}" | cut -d "-" -f2)
            
            # Check if online Year is older than local Year.
            if [ "$OnlineYear" -lt "$ZIMYear" ]; then # Online Year is older, skip.
                continue
            # Check if Years are equal, but online Month is older than local Month.
            elif [ "$OnlineYear" -eq "$ZIMYear" ] && [ "$OnlineMonth" -le "$ZIMMonth" ]; then # Years are equal, but Month is older, skip.
                continue
            else # Online is newer than local. Double Winner!
                UpdateFound=1
                echo -e "\033[1;32m    ✓ Update found! --> $OnlineVersion\033[0m"
                DownloadArray+=( "$BaseURL${ZIMRootArray[$i]}/${URLArray[$x]}" )
                PurgeArray+=( "$ZIMPath${ZIMNameArray[$i]}" )
                break # No need to conitnue checking the URLArray.
            fi          
        fi
    done
    if [[ $UpdateFound -eq 0 ]]; then # No update was found.
        echo "    ✗ No new update"
    fi
    echo
done

# Process the download que.
zim_download

# Process the purge que.
zim_purge

# Display Footer.
echo "=========================================="
echo " Process Complete."
echo "=========================================="
echo
echo "            DRY-RUN/SIMULATION"
[[ $DEBUG -eq 1 ]] && echo "               - ENABLED -"
[[ $DEBUG -eq 1 ]] && echo
[[ $DEBUG -eq 1 ]] && echo "           Use '-d' to disable."
[[ $DEBUG -eq 0 ]] && echo "               - DISABLED -"
echo
echo "=========================================="
echo

# Holy crap! We made it through!
# Good night!
exit 0
