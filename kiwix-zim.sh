#!/bin/bash

VER="1.11"

# Set required packages Array
PackagesArray=('curl')

# Set Script Arrays
LocalZIMArray=(); ZIMNameArray=(); ZIMRootArray=(); ZIMLangArray=(); ZIMTypeArray=(); ZIMSubTypeArray=(); ZIMVerArray=(); RawURLArray=(); URLArray=(); PurgeArray=(); DownloadArray=(); MirrorArray=();

# Set Script Strings
SCRIPT="$(readlink -f "$0")"
SCRIPTFILE="$(basename "$SCRIPT")"
SCRIPTPATH="$(dirname "$SCRIPT")"
SCRIPTNAME="$0"
ARGS=( "$@" )
BRANCH="main"
DEBUG=1 # This forces the script to default to "dry-run/simulation mode"
BaseURL="https://download.kiwix.org/zim/"
ZIMURL=""
ZIMPath=""
ZIMCount=0

# self_update - Script Self-Update Function
self_update() {
    echo "3. Checking for Script Updates..."
    echo
    # Check if script path is a git clone.
    #   If true, then check for update.
    #   If false, skip self-update check/funciton.
    if [[ -d "$SCRIPTPATH/.git" ]]; then
        echo "   ✓ Git Clone Detected: Checking Script Version..."
        cd "$SCRIPTPATH"
        timeout 1s git fetch --quiet
        timeout 1s git diff --quiet --exit-code "origin/$BRANCH" "$SCRIPTFILE"
        [ $? -eq 1 ] && {
            echo "   ✗ Version: Mismatched"
            echo
            echo "3a. Fetching Update..."
            echo
            if [ -n "$(git status --porcelain)" ];  then
                git stash push -m 'local changes stashed before self update' --quiet
            fi
            git pull --force --quiet
            git checkout $BRANCH --quiet
            git pull --force --quiet
            echo "   ✓ Update Complete. Running New Version. Standby..."
            sleep 3
            cd - > /dev/null

            # Execute new instance of the new script
            exec "$SCRIPTNAME" "${ARGS[@]}"

            # Exit this old instance of the script
            exit 1
        }
        echo "   ✓ Version: Current"
    else
        echo "   ✗ Git Clone Not Detected: Skipping Update Check"
    fi
}

# packages - Required Package(s) Check/Install Function
packages() {
    echo "2. Checking Required Packages..."
    echo
    install_pkgs=" "
    for keys in "${!PackagesArray[@]}"; do
        REQUIRED_PKG=${PackagesArray[$keys]}
        #PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $REQUIRED_PKG|grep "install ok installed")
        PKG_OK=$(command -v $REQUIRED_PKG)
        if [ "" = "$PKG_OK" ]; then
            echo "  ✗ $REQUIRED_PKG: Not Found"
            install_pkgs+=" $REQUIRED_PKG"
        else
            echo "  ✓ $REQUIRED_PKG: Found"
        fi
    done
    if [ " " != "$install_pkgs" ]; then
        echo
        echo "2a. Installing Missing Packages:"
        echo
        [[ $DEBUG -eq 1 ]] && apt --dry-run -y install $install_pkgs # Simulation
        [[ $DEBUG -eq 0 ]] && apt install -y $install_pkgs # Real
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
    IFS=$'\n' read -r -d '' -a RawURLArray < <( wget -q $URL -O - | tr "\t\r\n'" '   "' | grep -i -o '<a[^>]\+href[ ]*=[ \t]*"[^"]\+">[^<]*</a>' | sed -e 's/^.*"\([^"]\+\)".*$/\1/g' && printf '\0' ); unset IFS

    # Parse for Valid Releases
    for x in "${RawURLArray[@]}"; do
        [[ $x == [a-z]* ]] && DirtyURLArray+=($x)
    done

    # Let's sort the array in reverse to ensure newest versions are first when we dig through.
    # This does slow down the search, but ensures the newest version is picked every time.
    URLArray=($(printf "%s\n" "${DirtyURLArray[@]}" | sort -r))
    unset DirtyURLArray # Housekeeping...
}

# flags - Flag Processing Function
flags() {
    echo "1. Preprocessing..."
    echo
    echo "  -Validating ZIM directory..."
    
    # Let's identify which argument is the ZIM directory path and if it's an actual directory.
    if [[ -d ${1} ]]; then
        ZIMPath=$1
    elif [[ -d ${2} ]]; then
        ZIMPath=$2
    elif [[ -d ${3} ]]; then
        ZIMPath=$3
    else # Um... no ZIM directory path provided? Okay, let's show the usage.
        echo "  ✗ Missing or Invalid"
        echo
        usage_example
    fi
    echo "    ✓ Valid."
    echo

    # Check for and add if missing, trailing slash.
    [[ "${ZIMPath}" != */ ]] && ZIMPath="${ZIMPath}/"

    # Now we need to check for ZIM files.
    shopt -s nullglob # This is in case there are no matching files

    # Load all found ZIM(s) w/path into LocalZIMArray
    IFS=$'\n' LocalZIMArray=($ZIMPath*.zim); unset IFS

    # Check that ZIM(s) were actually found/loaded.
    if [ ${#LocalZIMArray[@]} -eq 0 ]; then # No ZIM(s) were found in the directory... I guess there's nothing else for us to do, so we'll Exit.
        echo "    ✗ No ZIMs found. Exiting..."
        exit 0
    fi

    # Populate ZIM arrays from found ZIM(s)
    echo "  -Parsing ZIM(s)..."

    # Because there isn't a strict standard in the file naming of the ZIMs we need to be 
    #  smart at how we match the onine ZIMs to our exact local ZIMs.
    for ((i=0; i<${#LocalZIMArray[@]}; i++)); do # Loop through local ZIM(s).
        ZIMNameArray[$i]=$(basename ${LocalZIMArray[$i]}) # Extract file names.

        # Break the ZIM filename appart delimited by the underscore '_'
        IFS='_' read -ra fields <<< $(basename ${LocalZIMArray[$i]}); unset IFS

        ZIMRootArray[$i]=${fields[0]} # First element is the Root
        ZIMLangArray[$i]=${fields[1]} # Second element is the Language
        ZIMVerArray[$i]=$(echo ${fields[-1]} | cut -d "." -f1) # Last element (minus the extension) is the Version

        # The remaining parts (field #2 to last field minus 1) get combined and set as the ZIM Type.
        Type=${fields[2]}
        for ((q=3; q<${#fields[@]}-1; q++)); do
            Type=+${fields[$q]}
        done
        ZIMTypeArray[$i]=$Type
        echo "    ✓ ${ZIMNameArray[$i]}"
    done
    echo
    echo "    ${#ZIMNameArray[*]} ZIM(s) found."
    echo
}

# mirror_search - Find ZIM URL Priority #1 mirror from meta4 Function
mirror_search() {
    IsMirror=0
    DownloadURL=""
    Direct=${CleanDownloadArray[$z]}
    # Fetch (silent) meta4 xml and extract url marked priority="1"
    RawMirror=$(curl -s $Direct.meta4 | grep 'priority="1"' | egrep -o 'https?://[^ ")]+')
    # Check that we actually got a URL (this could probably be done way better than this). If not mirror URL, default back to direct URL.
    if [[ $RawMirror == *"http"* ]]; then # URL found
        CleanMirror=${RawMirror%</url>} # We need to remove the trailing "</url>".
        DownloadURL=$CleanMirror
        IsMirror=1
    else # Mirror not found, default to direct download URL.
        DownloadURL=${CleanDownloadArray[$z]}
    fi
}

# zim_downlaod - ZIM download Function
zim_download() {
    echo "5. Downloading New ZIM(s)..."
    echo
    # Let's clear out any possible duplicates
    CleanDownloadArray=($(printf "%s\n" "${DownloadArray[@]}" | sort -u))
    # Let's Start the download process
    if [ ${#CleanDownloadArray[@]} -ne 0 ]; then
        for ((z=0; z<${#CleanDownloadArray[@]}; z++)); do
            mirror_search # Let's look for a mirror URL first.
            [[ $IsMirror -eq 0 ]] && echo "  ✓ Download (direct) : $DownloadURL"
            [[ $IsMirror -eq 1 ]] && echo "  ✓ Download (mirror) : $DownloadURL"
            [[ $DEBUG -eq 1 ]] && echo "  *** Simulated ***"
            echo
            FileName=$(basename $DownloadURL) # Extract file name.
            FilePath=$ZIMPath$FileName
            echo >> download.log
            echo "=======================================================================" >> download.log
            echo "File : $FileName" >> download.log
            [[ $IsMirror -eq 0 ]] && echo "URL (direct) : $DownloadURL" >> download.log
            [[ $IsMirror -eq 1 ]] && echo "URL (mirror) : $DownloadURL" >> download.log
            echo >> download.log
            [[ $DEBUG -eq 0 ]] && echo "Start : $(date -u)" >> download.log
            [[ $DEBUG -eq 1 ]] && echo "Start : $(date -u) *** Simulation ***" >> download.log
            echo >> download.log
            [[ $DEBUG -eq 0 ]] && curl -L -o $FilePath $DownloadURL |& tee -a download.log && echo
            [[ $DEBUG -eq 1 ]] && echo "  Download : $FilePath" >> download.log
            echo >> download.log
            [[ $DEBUG -eq 0 ]] && echo "End : $(date -u)" >> download.log
            [[ $DEBUG -eq 1 ]] && echo "End : $(date -u) *** Simulation ***" >> download.log
        done
    fi
    unset CleanDownloadArray # Housekeeping
    #unset DownloadArray     # Housekeeping, I know, but we can't do this here - we need it to verify new ZIM(s) during the purge function.
}

# zim_purge - ZIM purge Function
zim_purge() {
    echo "6. Purging Old ZIM(s)..."
    echo
    # Let's clear out any possible duplicates.
    CleanPurgeArray=($(printf "%s\n" "${PurgeArray[@]}" | sort -u))
    # Let's start the purge process.
    if [ ${#CleanPurgeArray[@]} -ne 0 ]; then
        echo >> purge.log
        echo "=======================================================================" >> purge.log
        [[ $DEBUG -eq 0 ]] && echo "$(date -u)" >> purge.log    
        [[ $DEBUG -eq 1 ]] && echo "$(date -u) *** Simulation ***" >> purge.log
        echo >> purge.log      
        for ((z=0; z<${#CleanPurgeArray[@]}; z++)); do
            # Before we actually purge, we want to check that the new ZIM exists.
            # Fist, we have to figure out what the old ZIM was. To do this we'll have to iterate through the old Arrays. Ugh. Total PITA.
            for ((o=0; o<${#PurgeArray[@]}; o++)); do
                if [[ ${PurgeArray[$o]} = ${CleanPurgeArray[$z]} ]]; then
                    NewZIM=$ZIMPath$(basename ${DownloadArray[$o]})
                    OldZIM=${PurgeArray[$o]}
                    break # Found, no reason to keep looping.
                fi
            done
            echo "  Old : $OldZIM"
            echo "  Old : $OldZIM" >> purge.log
            echo "  New : $NewZIM"
            echo "  New : $NewZIM" >> purge.log
            # Check for the new ZIM on disk.
            if [[ -f $NewZIM ]]; then # Found new ZIM
                if [[ $DEBUG -eq 0 ]]; then
                    echo "  ✓ Status : New ZIM verified. Old ZIM purged."
                    echo "  ✓ Status : New ZIM verified. Old ZIM purged." >> purge.log
                    [[ -f $OldZIM ]] && rm ${CleanPurgeArray[$z]}
                else
                    echo "  ✓ Status : *** Simulated ***"
                    echo "  ✓ Status : *** Simulated ***" >> purge.log
                fi
            else # New ZIM not found. Something went wrong, so we'll need to skip this purge.
                if [[ $DEBUG -eq 0 ]]; then
                    echo "  ✗ Status : New ZIM failed verification. Old ZIM purge skipped."
                    echo "  ✗ Status : New ZIM failed verification. Old ZIM purge skipped." >> purge.log
                else
                    echo "  ✓ Status : *** Simulated ***"
                    echo "  ✓ Status : *** Simulated ***" >> purge.log
                fi
            fi
            echo
            echo >> purge.log
        done
        [[ $DEBUG -eq 0 ]] && echo "$(date -u)" >> purge.log    
        [[ $DEBUG -eq 1 ]] && echo "$(date -u) *** Simulation ***" >> purge.log
    fi
    unset PurgeArray # Housekeeping
    unset CleanPurgeArray # Housekeeping
    unset DownloadArray # Ah, now we can properly Housekeep this Array from the zim_download function.
}

# Begin Script Execute

# Check for HELP argument first.
([ "$1" = "h" ] || [ "$1" = "-h" ]) && usage_example
([ "$2" = "h" ] || [ "$2" = "-h" ]) && usage_example
([ "$3" = "h" ] || [ "$3" = "-h" ]) && usage_example
# Check for Dry-Run Override argument
([ "$1" = "d" ] || [ "$1" = "-d" ]) && DEBUG=0
([ "$2" = "d" ] || [ "$2" = "-d" ]) && DEBUG=0
([ "$3" = "d" ] || [ "$3" = "-d" ]) && DEBUG=0

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
flags $1 $2 $3

# Second, Package Check.
packages
echo

# Third, Self-Update Check.
self_update
echo

echo "4. Processing ZIM(s)..."
echo
for ((i=0; i<${#ZIMNameArray[@]}; i++)); do
    onlineZIMcheck $i     
    echo "  -Checking: ${ZIMNameArray[$i]}:"
    UpdateFound=0
    unset Zmfields # Housekeeping
    IFS='_' read -ra Zmfields <<< ${ZIMNameArray[$i]}; unset IFS
    for ((x=0; x<${#URLArray[@]}; x++)); do
        unset Onfields # Housekeeping
        IFS='_' read -ra Onfields <<< ${URLArray[$x]}; unset IFS
        match=1
        # Here we need to iterate through the fields to find a full match.
        for ((t=0; t<$(echo $((${#Onfields[@]} - 1))); t++)); do 
            # Do they have the same field counts?
            if [ ${#Onfields[@]} = ${#Zmfields[@]} ]; then # Field counts match, keep going.
                # Are the current fields equal?
                if [ ${Onfields[$t]} != ${Zmfields[$t]} ]; then # Not equal, abort and goto the next entry.
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
            OnlineVersion=$(echo ${URLArray[$x]} | sed 's/^.*_\([^_]*\)$/\1/' | cut -d "." -f1)
            OnlineYear=$(echo $OnlineVersion | cut -d "-" -f1)
            OnlineMonth=$(echo $OnlineVersion | cut -d "-" -f2)
            ZIMYear=$(echo ${ZIMVerArray[$i]} | cut -d "-" -f1)
            ZIMMonth=$(echo ${ZIMVerArray[$i]} | cut -d "-" -f2)
            
            # Check if online Year is older than local Year.
            if [ $OnlineYear -lt $ZIMYear ]; then # Online Year is older, skip.
                continue
            # Check if online Year is equal, but Month is older than local Month.
            elif [ $OnlineYear -eq $ZIMYear ] && [ $OnlineMonth -le $ZIMMonth ]; then # Years are equal, but Month is older, skip.
                continue
            # Online Year and/or Online Month is newer than local. Double Winner!
            else
                UpdateFound=1
                echo "    ✓ Update found! --> $OnlineVersion"
                DownloadArray+=( $(echo $BaseURL${ZIMRootArray[$i]}/${URLArray[$x]}) )
                PurgeArray+=( $(echo $ZIMPath${ZIMNameArray[$i]}) )
                PurgeLocation=$(echo $ZIMPath)$(basename ${URLArray[$x]})
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