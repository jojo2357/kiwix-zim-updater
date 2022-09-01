#!/bin/bash

VER="1.6"

# Set required packages Array
PackagesArray=('wget')

# Set Script Arrays
LocalZIMArray=(); ZIMNameArray=(); ZIMRootArray=(); ZIMLangArray=(); ZIMTypeArray=(); ZIMSubTypeArray=(); ZIMVerArray=(); RawURLArray=(); URLArray=(); PurgeArray=(); DownloadArray=();

# Set Script Strings
SCRIPT="$(readlink -f "$0")"
SCRIPTFILE="$(basename "$SCRIPT")"
SCRIPTPATH="$(dirname "$SCRIPT")"
SCRIPTNAME="$0"
ARGS=( "$@" )
BRANCH="main"
DEBUG=1
BaseURL="https://download.kiwix.org/zim/"
ZIMURL=""
ZIMPath=""
ZIMCount=0

# self_update - Script Update Function
self_update() {
    echo "3. Checking for Script Updates..."
    echo
    # Check if script path is a git clone.
    #   If true, then check for update.
    #   If false, skip update check.
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

# packages - Package Check/Install Function
packages() {
    echo "2. Checking Required Packages..."
    echo
    install_pkgs=" "
    for keys in "${!PackagesArray[@]}"; do
        REQUIRED_PKG=${PackagesArray[$keys]}
        #PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $REQUIRED_PKG|grep "install ok installed")
        PKG_OK=$(command -v $REQUIRED_PKG)
        if [ "" = "$PKG_OK" ]; then
            echo "   ✗ $REQUIRED_PKG: Not Found"
            install_pkgs+=" $REQUIRED_PKG"
        else
            echo "   ✓ $REQUIRED_PKG: Found"
        fi
    done
    if [ " " != "$install_pkgs" ]; then
        echo
        echo "2a. Installing Missing Packages:"
        echo
        [[ $DEBUG -eq 1 ]] && apt --dry-run -y install $install_pkgs
        [[ $DEBUG -eq 0 ]] && apt install -y $install_pkgs
    fi
}

# usage_example - Show Usage and Exit
usage_example() {
    echo 'Usage: ./kiwix-zim.sh <h|d> /full/path/'
    echo
    echo '    /full/path/       Full path to ZIM directory'
    echo
    echo '    -h or h           Show this usage and exit.'
    echo
    echo '    -d or d           Dry-Run - Simulation ONLY.'
    echo
    exit 0
}

# onlineZIMcheck - Fetch/Scrape download.kiwix.org for ZIM
onlineZIMcheck() {   
    # Clear out Arrays
    unset URLArray
    unset RawURLArray

    # Parse RAW Website - Directory checked is based upon the ZIM's Root
    URL="$BaseURL${ZIMRootArray[$1]}/"
    IFS=$'\n' read -r -d '' -a RawURLArray < <( wget -q $URL -O - | tr "\t\r\n'" '   "' | grep -i -o '<a[^>]\+href[ ]*=[ \t]*"[^"]\+">[^<]*</a>' | sed -e 's/^.*"\([^"]\+\)".*$/\1/g' && printf '\0' ); unset IFS

    # Parse for Valid Releases
    for x in "${RawURLArray[@]}"; do
        [[ $x == [a-z]* ]] && DirtyURLArray+=($x)
    done

    # Let's sort the array in reverse to ensure newest versions are first when we dig through.
    # This does slow down the search, but ensures the newest version is picked every time.
    URLArray=($(printf "%s\n" "${DirtyURLArray[@]}" | sort -r))
    unset DirtyURLArray
}

# Flag Processing Function
flags() {
    echo "1. Preprocessing..."
    echo
    # Check for HELP argument
    ([ "$1" = "h" ] || [ "$1" = "-h" ]) && usage_example
    ([ "$2" = "h" ] || [ "$2" = "-h" ]) && usage_example
    ([ "$3" = "h" ] || [ "$3" = "-h" ]) && usage_example

    echo "  -Validating ZIM directory..."
    
    # Validate Supplied Directory argument
    if [[ -d ${1} ]]; then
        ZIMPath=$1
    elif [[ -d ${2} ]]; then
        ZIMPath=$2
    elif [[ -d ${3} ]]; then
        ZIMPath=$3
    else
        echo "  ✗ Missing or Invalid"
        echo
        usage_example
    fi
    echo "    ✓ Valid."
    echo

    # Check for and add if missing, trailing slash
    [[ "${ZIMPath}" != */ ]] && ZIMPath="${ZIMPath}/"

    # use nullglob in case there are no matching files
    shopt -s nullglob #dotglob

    # Load ZIMs w/path into Array
    IFS=$'\n' LocalZIMArray=($ZIMPath*.zim); unset IFS

    # Check that ZIMs were found
    if [ ${#LocalZIMArray[@]} -eq 0 ]; then
        echo "    ✗ No ZIMs found. Exiting..."
        exit 0
    fi

    # Populate ZIM arrays from found ZIM(s)
    echo "  -Parsing ZIM(s)..."

    # Because there isn't a strict standard in the file naming of the ZIMs we need to be 
    #  smart at how we match the onine ZIMs to our exact local ZIMs.
    for ((i=0; i<${#LocalZIMArray[@]}; i++)); do
        ZIMNameArray[$i]=$(basename ${LocalZIMArray[$i]})

        # Break the ZIM filename appart delimited by the underscore '_'
        IFS='_' read -ra fields <<< $(basename ${LocalZIMArray[$i]}); unset IFS
        ZIMRootArray[$i]=${fields[0]} # First element is the Root
        ZIMLangArray[$i]=${fields[1]} # Second element is the Language
        ZIMVerArray[$i]=$(echo ${fields[-1]} | cut -d "." -f1) # Last element (minus the extension) is the Version

        # The remaining (variable) number of parts get combined and set to the ZIMTypeArray
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

# ZIM download
zim_download() {
    echo "5. Downloading Updates..."
    echo

    # Let's clear out any possible duplicates
    CleanDownloadArray=($(printf "%s\n" "${DownloadArray[@]}" | sort -u))

    if [ ${#CleanDownloadArray[@]} -ne 0 ]; then
        for ((z=0; z<${#CleanDownloadArray[@]}; z++)); do
            echo "      ✓ Download: ${CleanDownloadArray[$z]}"
            echo
            [[ $DEBUG -eq 0 ]] && wget -P $ZIMPath ${CleanDownloadArray[$z]} -q --show-progress && echo
        done
    fi
    unset CleanDownloadArray
    unset DownloadArray
}

# ZIM purge
zim_purge() {
    echo "6. Purging Replaced ZIM(s)..."
    echo

    # Let's clear out any possible duplicates
    CleanPurgeArray=($(printf "%s\n" "${PurgeArray[@]}" | sort -u))

    if [ ${#CleanPurgeArray[@]} -ne 0 ]; then
        for ((z=0; z<${#CleanPurgeArray[@]}; z++)); do
            echo "      ✓ Purge: ${CleanPurgeArray[$z]}"
            echo
            [[ $DEBUG -eq 0 ]] && rm ${CleanPurgeArray[$z]}
        done
    fi
    unset CleanPurgeArray
    unset PurgeArray
}

# Begin Script Execute

# Check for Dry-Run Override argument
([ "$1" = "d" ] || [ "$1" = "-d" ]) && DEBUG=0
([ "$2" = "d" ] || [ "$2" = "-d" ]) && DEBUG=0
([ "$3" = "d" ] || [ "$3" = "-d" ]) && DEBUG=0

clear
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

# Flag Check
flags $1 $2 $3

# Package Check
packages
echo

# Self Update Check
self_update
echo

echo "4. Processing ZIM(s)..."
echo
for ((i=0; i<${#ZIMNameArray[@]}; i++)); do
    onlineZIMcheck $i     
    echo "  -Checking: ${ZIMNameArray[$i]}:"
    UpdateFound=0
    for ((x=0; x<${#URLArray[@]}; x++)); do
        unset Onfields
        unset Zmfields
        IFS='_' read -ra Onfields <<< ${URLArray[$x]}; unset IFS
        IFS='_' read -ra Zmfields <<< ${ZIMNameArray[$i]}; unset IFS
        match=1
        for ((t=0; t<$(echo $((${#Onfields[@]} - 1))); t++)); do 
            if [ ${#Onfields[@]} = ${#Zmfields[@]} ]; then
                if [ ${Onfields[$t]} != ${Zmfields[$t]} ]; then
                    match=0
                fi
            else
                match=0
            fi
        done     
        if [[ $match -eq 1 ]]; then
            OnlineVersion=$(echo ${URLArray[$x]} | sed 's/^.*_\([^_]*\)$/\1/' | cut -d "." -f1)
            OnlineYear=$(echo $OnlineVersion | cut -d "-" -f1)
            OnlineMonth=$(echo $OnlineVersion | cut -d "-" -f2)
            ZIMYear=$(echo ${ZIMVerArray[$i]} | cut -d "-" -f1)
            ZIMMonth=$(echo ${ZIMVerArray[$i]} | cut -d "-" -f2)
            
            if [ $OnlineYear -lt $ZIMYear ]; then
                continue
            elif [ $OnlineYear -eq $ZIMYear ] && [ $OnlineMonth -le $ZIMMonth ]; then
                continue
            else
                UpdateFound=1
                echo "    ✓ Update found! --> $OnlineVersion"
                DownloadArray+=( $(echo $BaseURL${ZIMRootArray[$i]}/${URLArray[$x]}) )
                PurgeArray+=( $(echo $ZIMPath${ZIMNameArray[$i]}) )
                break # This needs to be dealt with eventually.
            fi          
        fi
    done
    if [ $UpdateFound -eq 0 ]; then
        echo "    ✗ No new update"
    fi
    echo
done
# Process download que
zim_download

# Process purge que
zim_purge

# We made it home!
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

# Good night!
exit 0
