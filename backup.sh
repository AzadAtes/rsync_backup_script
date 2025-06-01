#!/bin/bash

SOURCE_DIR="/home/az/IdeaProjects/os_stuff/linux/rsyncScript/source/"
DESTINATION_DIR="/home/az/IdeaProjects/os_stuff/linux/rsyncScript/destination/"

# Check if kdialog is installed
if ! command -v kdialog &> /dev/null; then
    echo "Error: kdialog is not installed. Please install kdialog."
    notify-send -a "Backup Script" --urgency=critical "Error: kdialog is not installed." "Backup canceled. Please install kdialog."
    exit 1
fi

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DESTINATION_APPROVED_MARKER="$SCRIPT_DIR/state/destinationApprovedMarker"

echo $DESTINATION_APPROVED_MARKER

# Prompt user for approval on first sync if the destination directory contains files,
# unless approval has already been granted (indicated by the presence of the marker file).
if [ ! -f "$DESTINATION_APPROVED_MARKER" ]; then
    DESTINATION_CONTENTS=$(ls -A "$DESTINATION_DIR")

    if [ -n "$DESTINATION_CONTENTS" ]; then
        kdialog --title "Rsync Data Backup" --warningcontinuecancel \
        "Destination is not empty\nDestination: '$DESTINATION_DIR'\n\nDo you wish to continue anyway?" \
        "Contents of the destination directory:\n\n$DESTINATION_CONTENTS"

        if [ $? -ne 0 ]; then
            kdialog --title "Backup Script" --icon dialog-cancel --passivepopup "Backup Script Canceled." 10
            exit 1
        fi
    fi
fi

{
    trap 'ERR_MSG="Script failed on command:\n$BASH_COMMAND"; echo "$ERR_MSG" >> "$LOGS_DIR/rsync_error.log"; kdialog --title "Backup Script FAILED" --error "$ERR_MSG"; exit 1' ERR

    RSYNC_COMMAND="rsync -av $SOURCE_DIR $DESTINATION_DIR"
    RSYNC_COMMAND_WITH_DELETE="$RSYNC_COMMAND --delete"
    RSYNC_COMMAND_WITH_DELETE_DRY_RUN="$RSYNC_COMMAND_WITH_DELETE -n"

    LOGS_DIR="$SCRIPT_DIR/logs"
    FILES_TO_DELETE_FILE="$SCRIPT_DIR/state/filesToDelete.txt"

    # ensure source and destination directories exist
    for DIR in "$SOURCE_DIR" "$DESTINATION_DIR"; do
        if [ ! -d "$DIR" ]; then
            kdialog --title "Backup Script" --sorry "Directory does not exist:\n$DIR\n\nExiting."
            exit 1
        fi
    done

    # create directories and files if they don't exist
    mkdir -p "$LOGS_DIR"
    touch "$FILES_TO_DELETE_FILE"

    # make a dry run
    DRY_RUN_OUTPUT=$($RSYNC_COMMAND_WITH_DELETE_DRY_RUN)
    PREV_FILES_TO_DELETE=$(cat "$FILES_TO_DELETE_FILE") # load files that would be deleted by --delete option from previous run
    FILES_TO_DELETE=$(echo "$DRY_RUN_OUTPUT" | grep deleting || true) # extract the files that would be deleted from the dry run output
}

runRsyncCommand () {
    COMMAND_OUTPUT=$($1 2>&1) # 2>&1 redirects stderr to stdout so we can store it in our variable
    if [ $? == 0 ] ; then
        kdialog --title "Backup Script Successful" --icon dialog-ok --passivepopup "$LOGS_DIR" "$COMMAND_OUTPUT" 10
    else
        kdialog --title "Backup Script FAILED" --error "Command failed:\n$1\n\nCheck the Logs or Details for more Information:\n$LOGS_DIR" "$COMMAND_OUTPUT"
    fi
    echo "$1" > $LOGS_DIR/rsyncLog_$(date +"%Y-%m-%d_%H:%M:%S").txt # save rsync command output to a log file
}

{
    trap '' ERR

    # if FILES_TO_DELETE is empty or has not changed since previous run, don't ask for user interaction and run the rsync command without the --delete option.
    if [ -z "$FILES_TO_DELETE" ] || [ "$FILES_TO_DELETE" = "$PREV_FILES_TO_DELETE" ]; then
        runRsyncCommand "$RSYNC_COMMAND"
    else
        while : ; do

            # ask for user interaction
            kdialog --title "Backup Script" \
            --warningyesnocancel "There are files present in the Destination which are missing in the Source\nDo you want to DELETE these files only present in the Destination?\n\nSource = $SOURCE_DIR\nDestination = $DESTINATION_DIR" \
            "$FILES_TO_DELETE" \
            --yes-label "Yes - DELETE files" \
            --no-label "No - Keep files"

            case $? in

            0) # Yes
                input=$(kdialog --title "Backup Script" --inputbox "Type 'Delete' and press ok if you want to continue.\n -The Destination will be synced with Source.\n -Files only present in the Destination will be DELETED." "")

                if [ $? == 0 ] ; then
                    if [ "$input" = "Delete" ] ; then
                        runRsyncCommand "$RSYNC_COMMAND_WITH_DELETE"
                        touch "$DESTINATION_APPROVED_MARKER"
                        break
                    else
                        kdialog --title "Backup Script" --sorry "Invalid input."
                    fi
                fi
                ;;

            1) # No
                kdialog --title "Backup Script" --warningcontinuecancel "Are you sure you want to continue?\n -The Destination will be synced with Source.\n -Files only present in the Destination will NOT be deleted.\n -You will not be prompted to delete these files until the list of files only present in the Destination changes."

                if [ $? == 0 ] ; then
                    runRsyncCommand "$RSYNC_COMMAND"
                    echo "$FILES_TO_DELETE" > $FILES_TO_DELETE_FILE # override files to delete from previous run
                    touch "$DESTINATION_APPROVED_MARKER"
                    break
                fi
                ;;


            2) # Cancel
                kdialog --title "Backup Script" --icon dialog-cancel --passivepopup "Backup Script Canceled." 10
                break
                ;;

            *)
                kdialog --title "Backup Script" --icon dialog-error --passivepopup "Unknown Error." 99
                break
                ;;
            esac
        done
    fi
}