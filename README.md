# kiwix-zim.sh

A script to check `download.kiwix.org` for updates to your local ZIM library.

Just pass this script your ZIM directory and away it goes. *(see Usage below)*

Scripted, tested and used on my Ubuntu server, so it should work for just about all Debian-based systems. It probably works on all Linux systems... I just have no time to test that.

![screenshot](https://github.com/DocDrydenn/kiwix-zim/blob/main/screenshot.png)

## What It Does

I wanted an easy way to ensure my ZIM library was kept updated without actually needing to check every ZIM individually. I looked for a tool to do this, but didn't find anything... so I put on my amature BASH hat and made one.

I run this script via a scheduled cron job on my Linux server where I store my ZIM library and host the Kiwix server. After it's complete, I follow it up with an automated call to update my `library.xml` for the Kiwix server (Note: this part is not provided via this script). This keeps my ZIM library and Kiwix server updated.

It works for me. Your miles may vary...

This script will parse a list of all ZIM(s) found in the ZIM directory passed to it. It then checks each ZIM against what is on the `download.kiwix.org` website via the file name Year-Month part.

Any new versions found get queued for direct download (processed via `curl`). Replaced ZIM(s) are then queued for purging (processed via `rm`). *(see Limitations below)*

**UPDATE: As of v1.10, this script will attempt to use a preferred mirror (if available) for all downloads. If a valid mirror cannot be found, this script will default to the direct download from `download.kiwix.org`.**

```text
Note: Due to the nature of ZIM sizes and internet connection speeds, 
      you should expect the download process to take a while.

      This script will output the download progress bar during the 
      download process just so you can see that the script hasn't 
      frozen or locked up.

      Download status is also logged in real-time for monitoring from
      outside this script. (see Special Note 2 below)
```

### Special Note 1

For data safety reasons, I have coded this script to "dry-run" by default. This means that this script will not downloaded or purge anything, however, it will "go through the motions" and output what it would have actually done, allowing you to review the "effects" before commiting to them.

Once you are good with the "dry-run" results and wish to commit to them, simply re-run the script like you did the first time, but this time, add the "dry-run" override flag (`-d`) to the end.

```text
Bonus: A dry-run/simulation run is not required. If you like to 
       live dangerously, feel free to just call the script with 
       the override flag right from the start. 

       It's your ZIM libary... not mine.
```

### Special Note 2

Downloads (`download.log`) and Purges (`purge.log`) are now created for two main reasons:

1. History of what was done. Just good to have.
2. Because downloads can take a really long time, if you were to run this script in the background, you'd have no real way of monitoring the status of any downloads it may be running... since switching over to `curl`, the `download.log` can be monitored for real-time status of any downloads taking place. You could use a very simple `tail -f download.log` to watch those download stats in real-time from outside of the script.

## Limitations

- If you maintain multiple dated versions of the same ZIM (i.e. `xxx_2022-06.zim` and `xxx_2022-07.zim`) this script may not be for you... at least not yet. Give it a dry-run and check the results.
- This script is only for ZIM(s) hosted by `download.kiwix.org` due to the file naming standard they use. If you have self-made ZIM(s) or ZIM(s) downloaded from somewhere else, they most likely do not use the same naming standards and will not be processed by this script.
- If you have ZIM(s) from `download.kiwix.org`, but you have changed their file names, this script will treat them like the previous limitation explains.
- This script does not attempt to update any `library.xml` that may or may not exist/be needed for your install/setup of Kiwix. If needed, you'll need to handle this part on your own.

## Requirements

This script does not need root, however it does need the same rights as your ZIM directory or it won't be able to download and/or purge ZIMs.

This script checks for the below packages. If not found, it will attempt to install them via APT.

- curl

Not checked or installed via script:

- Git *(only needed for the self-update process to work.)*

## Install

This script is self-updating. The self-update routine uses git commands to make the update so this script should be "installed" with the below command.

```text
git clone https://github.com/DocDrydenn/kiwix-zim.git
```

UPDATE: If you decide not to install via a git clone, you can still use this script, however, it will just skip the update check and continue on.

## Usage

```text
    Usage: ./kiwix-zim.sh <h|d> /full/path/

    /full/path/       Full path to ZIM directory

    -d or d           Dry-Run Override

    -h or h           Show this usage and exit
```
