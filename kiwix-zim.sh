#!/bin/bash

VER="1.15"

# Set required packages Array
PackagesArray=('curl')

# Set Script Arrays
LocalZIMArray=(); ZIMNameArray=(); ZIMRootArray=(); ZIMVerArray=(); RawURLArray=(); URLArray=(); PurgeArray=(); DownloadArray=();

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

# self_update - Script Self-Update Function
self_update() {
    echo "3. Checking for Script Updates..."
    echo
    # Check if script path is a git clone.
    #   If true, then check for update.
    #   If false, skip self-update check/funciton.
    if [[ -d "$SCRIPTPATH/.git" ]]; then
        echo "   ✓ Git Clone Detected: Checking Script Version..."
        cd "$SCRIPTPATH" || exit 1
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
            cd - > /dev/null || exit 1

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
        PKG_OK=$(command -v "$REQUIRED_PKG")
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
    else # Um... no ZIM directory path provided? Okay, let's show the usage and exit.
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
    IFS=$'\n' LocalZIMArray=("$ZIMPath"*.zim); unset IFS

    # Check that ZIM(s) were actually found/loaded.
    if [ ${#LocalZIMArray[@]} -eq 0 ]; then # No ZIM(s) were found in the directory... I guess there's nothing else for us to do, so we'll Exit.
        echo "    ✗ No ZIMs found. Exiting..."
        exit 0
    fi

    # Populate ZIM arrays from found ZIM(s)
    echo "  -Parsing ZIM(s)..."

    # Online ZIM(s) have a semi-strict filename standard we can use for matching to our local ZIM(s).
    for ((i=0; i<${#LocalZIMArray[@]}; i++)); do  # Loop through local ZIM(s).
        ZIMNameArray[$i]=$(basename "${LocalZIMArray[$i]}")  # Extract file name.
        IFS='_' read -ra fields <<< "${ZIMNameArray[$i]}"; unset IFS  # Break the filename into fields delimited by the underscore '_'
        # First element is the Root - base directory for the URL
        # *** Special Case for all STACKEXCHANGE ZIM's becasue they're too good to follow the naming standards. ***
        if [[ ${fields[0]} == *"stackexchange.com"* || ${fields[0]} == *"stackoverflow.com"* || ${fields[0]} == *"mathoverflow.net"* || ${fields[0]} == *"serverfault.com"* || ${fields[0]} == *"stackapps.com"* || ${fields[0]} == *"superuser.com"* || ${fields[0]} == *"askubuntu.com"* ]]; then
            ZIMRootArray[$i]="stack_exchange"
        # *** Special Case for all ZIM's stored in the OTHER folder. ***
        elif [[ ${fields[0]} == *"alittlequestionaday"* || ${fields[0]} == *"allthetropes"* || ${fields[0]} == *"alpinelinux"* || ${fields[0]} == *"appropedia"* || ${fields[0]} == *"archlinux"* || ${fields[0]} == *"artofproblemsolving"* || ${fields[0]} == *"bayardcuisine"* || ${fields[0]} == *"bitcoin"* || ${fields[0]} == *"bulbagarden"* || ${fields[0]} == *"chabadpedia"* || ${fields[0]} == *"crashcourse"* || ${fields[0]} == *"dandwiki"* || ${fields[0]} == *"diksha-std10ssc"* || ${fields[0]} == *"disledansmalangue"* || ${fields[0]} == *"ecured"* || ${fields[0]} == *"education-et-numerique"* || ${fields[0]} == *"edutechwiki"* || ${fields[0]} == *"ekopedia"* || ${fields[0]} == *"eleda"* || ${fields[0]} == *"energypedia"* || ${fields[0]} == *"eu4"* || ${fields[0]} == *"evageeks"* || ${fields[0]} == *"experiencesscientifiques"* || ${fields[0]} == *"explainxkcd"* || ${fields[0]} == *"finiki"* || ${fields[0]} == *"fountainpen"* || ${fields[0]} == *"gentoo"* || ${fields[0]} == *"granbluefantasy"* || ${fields[0]} == *"halachipedia"* || ${fields[0]} == *"hamichlol"* || ${fields[0]} == *"hitchwiki"* || ${fields[0]} == *"inciclopedia"* || ${fields[0]} == *"installgentoo"* || ${fields[0]} == *"jaimelire"* || ${fields[0]} == *"japprendsalire"* || ${fields[0]} == *"klexikon"* || ${fields[0]} == *"laboh"* || ${fields[0]} == *"les-fondamentaux"* || ${fields[0]} == *"lesbelleshistoires"* || ${fields[0]} == *"lesptitsphilosophes"* || ${fields[0]} == *"litterature-audiobooks-poetry"* || ${fields[0]} == *"los_miserables_audiobook"* || ${fields[0]} == *"mawsouaa"* || ${fields[0]} == *"mdwiki"* || ${fields[0]} == *"mesptitesquestions"* || ${fields[0]} == *"mesptitspourquoi"* || ${fields[0]} == *"metakgp"* || ${fields[0]} == *"mindfield"* || ${fields[0]} == *"neos-wiki"* || ${fields[0]} == *"openstreetmap-wiki"* || ${fields[0]} == *"physicell"* || ${fields[0]} == *"plume-app.co"* || ${fields[0]} == *"poesies"* || ${fields[0]} == *"pokepedia"* || ${fields[0]} == *"pokewiki"* || ${fields[0]} == *"rationalwiki"* || ${fields[0]} == *"scoopyendirectducorpshumain"* || ${fields[0]} == *"scratch-wiki"* || ${fields[0]} == *"skin-of-color-society"* || ${fields[0]} == *"storybox"* || ${fields[0]} == *"stupidedia"* || ${fields[0]} == *"t4-wiki"* || ${fields[0]} == *"termux"* || ${fields[0]} == *"thaki"* || ${fields[0]} == *"the_infosphere"* || ${fields[0]} == *"ubuntudoc"* || ${fields[0]} == *"ubuntuusers"* || ${fields[0]} == *"westeros"* || ${fields[0]} == *"whitewolfwiki"* || ${fields[0]} == *"wikem"* || ${fields[0]} == *"wikishia"* || ${fields[0]} == *"wikispecies"* || ${fields[0]} == *"wikisummaries"* || ${fields[0]} == *"wikiwel"* || ${fields[0]} == *"yeshiva"* || ${fields[0]} == *"youscribe"* || ${fields[0]} == *"zaya-english-duniya-marthi"* || ${fields[0]} == *"zdoom"* || ${fields[0]} == *"zimgit"* ]]; then
            ZIMRootArray[$i]="other"
        else
            ZIMRootArray[$i]=${fields[0]} # All other non-stack_exchange ZIMs.
        fi
        ZIMVerArray[$i]=$(echo "${fields[-1]}" | cut -d "." -f1)  # Last element (minus the extension) is the Version - YYYY-MM
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

# zim_downlaod - ZIM download Function
zim_download() {
    echo "5. Downloading New ZIM(s)..."
    echo
    # Let's clear out any possible duplicates
    CleanDownloadArray=($(printf "%s\n" "${DownloadArray[@]}" | sort -u)) # Sort Array
    # Let's Start the download process
    if [ ${#CleanDownloadArray[@]} -ne 0 ]; then
        for ((z=0; z<${#CleanDownloadArray[@]}; z++)); do # Iterate through the download queue.
            mirror_search # Let's look for a mirror URL first.
            FileName=$(basename "$DownloadURL") # Extract New/Updated ZIM file name.
            FilePath=$ZIMPath$FileName # Set destination path with file name

            [[ $IsMirror -eq 0 ]] && echo "  Download (direct) : $DownloadURL"
            [[ $IsMirror -eq 1 ]] && echo "  Download (mirror) : $DownloadURL"

            if [[ -f $FilePath ]]; then # New ZIM already found, we don't need to download it.
                [[ $DEBUG -eq 0 ]] && echo "  ✓ Status : ZIM already exists on disk. Skipping downlaod."
                [[ $DEBUG -eq 1 ]] && echo "  ✓ Status : *** Simulated ***  ZIM already exists on disk. Skipping downlaod."
            else # New ZIM not found, so we'll go ahead and download it.
                [[ $DEBUG -eq 0 ]] && echo "  ✓ Status : ZIM doesn't exist on disk. Downloading..."
                [[ $DEBUG -eq 1 ]] && echo "  ✓ Status : *** Simulated ***  ZIM doesn't exist on disk. Downloading..."
            fi
            echo

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
    fi
    unset CleanDownloadArray # Housekeeping
    #unset DownloadArray     # Housekeeping, I know, but we can't do this here - we need it to verify new ZIM(s) during the purge function.
}

# zim_purge - ZIM purge Function
zim_purge() {
    echo "6. Purging Old ZIM(s)..."
    echo
    # Let's clear out any possible duplicates.
    CleanPurgeArray=($(printf "%s\n" "${PurgeArray[@]}" | sort -u)) # Sort Array
    # Let's start the purge process.
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
            echo "  Old : $OldZIM"
            echo "  Old : $OldZIM" >> purge.log
            echo "  New : $NewZIM"
            echo "  New : $NewZIM" >> purge.log
            # Check for the new ZIM on disk.
            if [[ -f $NewZIM ]]; then # New ZIM found
                if [[ $DEBUG -eq 0 ]]; then
                    echo "  ✓ Status : New ZIM verified. Old ZIM purged."
                    echo "  ✓ Status : New ZIM verified. Old ZIM purged." >> purge.log
                    [[ -f $OldZIM ]] && rm "${CleanPurgeArray[$z]}" # Purge old ZIM
                else
                    echo "  ✓ Status : *** Simulated ***"
                    echo "  ✓ Status : *** Simulated ***" >> purge.log
                fi
            else # New ZIM not found. Something went wrong, so we will skip this purge.
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
        [[ $DEBUG -eq 0 ]] && date -u >> purge.log    
        [[ $DEBUG -eq 1 ]] && echo "$(date -u) *** Simulation ***" >> purge.log
    fi
    unset PurgeArray # Housekeeping
    unset CleanPurgeArray # Housekeeping
    unset DownloadArray # Ah, now we can properly Housekeep this Array from the zim_download function.
}

# Begin Script Execute

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
echo

# Third, Self-Update Check.
self_update
echo

echo "4. Processing ZIM(s)..."
echo
for ((i=0; i<${#ZIMNameArray[@]}; i++)); do
    onlineZIMcheck "$i"     
    echo "  -Checking: ${ZIMNameArray[$i]}:"
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
                echo "    ✓ Update found! --> $OnlineVersion"
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