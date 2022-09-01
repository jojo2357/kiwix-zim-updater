# kiwix-zim.sh

A script to check `download.kiwix.org` for updates to your local ZIM library.

Just pass this script your ZIM directory and away it goes. *(see Usage below)*

## What It Does

I wanted an easy way to ensure my ZIM library was kept updated without actually needing to check every ZIM individually. I looked for a tool/script to do this, but didn't turn up anything... so I make one.

This script will parse a list of all ZIM(s) found in the ZIM directory passed to it. It then checks each ZIM against what is on the `download.kiwix.org` website via the file name Year-Month part.

Any new versions found get queued for direct download (processed via `wget`). Replaced ZIM(s) are then queued for purging (processed via `rm`). *(see Limitations below)*

    Note: Due to the nature of ZIM sizes and internet connection speeds, you should expect the download process to take a while. This script will output the download progress bar during the download process just so you can see that the script hasn't frozen or locked up.

### Special Note

For data safety reasons, I have coded this script to "dry-run" by default. This means that this script will not downloaded or purge anything, however, it will "go through the motions" and output what it would have actually done, allowing you to review the "effects" before commiting to them.

Once you are good with the "dry-run" results and wish to commit to them, simply re-run the script like you did the first time, but this time, add the "dry-run" override flag (`-d`) to the end.

    Bonus: A dry-run/simulation run is not required. If you like to live dangerously, feel free to just call the script with the override flag right from the start. It's your ZIM libary... not mine.

## Limitations

- If you maintain multiple dated versions of the same ZIM (i.e. `xxx_2022-06.zim` and `xxx_2022-07.zim`) this script may not be for you... at least not yet.
- This script is only for ZIM(s) hosted by `download.kiwix.org` due to the file naming standard they use. If you have self-made ZIM(s) or ZIM(s) downloaded from somewhere else, they most likely do not use the same naming standards and will not be processed by this script.
- If you have ZIM(s) from `download.kiwix.org`, but you have changed their file names, this script will treat them like the previous limitation explains.
- This script does not attempt to update any `library.xml` that may or may not exist/be needed for your install/setup of Kiwix. If needed, you'll need to handle this part on your own.

## Requirements

This script checks for the below packages. If not found, it will attempt to install them via APT.

- wget

Not checked or installed via script:

- Git *(needed for the self-update process to work.)*

## Install

This script is self-updating. The self-update routine uses git commands to make the update so it should be "installed" with the following command.
*(A future update will allow the user to skip this self-update function... allowing the script to be "installed" and/or run from outside of a git clone.)*

    git clone https://github.com/DocDrydenn/svr_fans.git

## Usage

    Usage: ./kiwix-zim.sh <h|d> /full/path/

    /full/path/       Full path to ZIM directory

    -d or d           Dry-Run Override

    -h or h           Show this usage and exit
