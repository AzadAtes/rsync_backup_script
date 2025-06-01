#!/bin/bash

### CONFIG ###
SOURCE_DIR="/home"
DESTINATION_DIR="/mnt/Backup/"

RSYNC_EXCLUDES="--exclude='.*' --exclude='Downloads/'"

RSYNC_COMMAND="rsync -av $RSYNC_EXCLUDES $SOURCE_DIR $DESTINATION_DIR"
RSYNC_COMMAND_WITH_DELETE="$RSYNC_COMMAND --delete"
RSYNC_COMMAND_WITH_DELETE_DRY_RUN="$RSYNC_COMMAND_WITH_DELETE -n"

### DEFINE FUNCTIONS ###
runRsyncCommand () {
    COMMAND_OUTPUT=$($1 2>&1) # 2>&1 redirects stderr to stdout so we can store it in our variable
    echo -e "$COMMAND_OUTPUT"
    printf "%s\n" "$1" > "$LOGS_DIR/rsyncLog_$(date +"%Y-%m-%d_%H:%M:%S").txt"

    if [ $? == 0 ] ; then
        kdialog --title "Backup Script Successful" --icon dialog-ok --passivepopup "$LOGS_DIR" "$COMMAND_OUTPUT" 10
    else
        kdialog --title "Backup Script FAILED" --error "Command failed:\n$1\n\nCheck the Logs or Details for more Information:\n$LOGS_DIR" "$COMMAND_OUTPUT"
    fi
}

saveApproval () {
    echo "$RSYNC_COMMAND" > "$APPROVED_COMMAND_FILE"
}

### SETUP ###
{
    trap 'ERR_MSG="ERROR! Script failed on command:\n\n$BASH_COMMAND"; echo "$ERR_MSG" >> "$LOGS_DIR/rsync_error.log"; kdialog --title "Backup Script FAILED" --error "$ERR_MSG"; exit 1' ERR

    ### Check if kdialog is installed ###
    if ! command -v kdialog &> /dev/null; then
        echo "Error: kdialog is not installed. Please install kdialog."
        notify-send -a "Backup Script" --urgency=critical "Error: kdialog is not installed." "Backup canceled. Please install kdialog."
        exit 1
    fi

    # ensure source and destination directories exist
    for DIR in "$SOURCE_DIR" "$DESTINATION_DIR"; do
        if [ ! -d "$DIR" ]; then
            kdialog --title "Backup Script" --sorry "Directory does not exist:\n$DIR\n\nExiting."
            exit 1
        fi
    done

    # define directories and files
    SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
    LOGS_DIR="$SCRIPT_DIR/logs"
    STATE_DIR="$SCRIPT_DIR/state"
    FILES_TO_DELETE_FILE="$SCRIPT_DIR/state/filesToDelete.txt"
    APPROVED_COMMAND_FILE="$STATE_DIR/approvedCommand.txt"

    # create directories and files if they don't exist
    mkdir -p "$LOGS_DIR"
    mkdir -p "$STATE_DIR"
    touch "$FILES_TO_DELETE_FILE"
    touch "$APPROVED_COMMAND_FILE"
}

### DRY RUN ###
DRY_RUN_OUTPUT=$($RSYNC_COMMAND_WITH_DELETE_DRY_RUN)

if [ -z "$DRY_RUN_OUTPUT" ]; then
    kdialog --title "Backup Script" --error "Dry run failed or returned no output. Check permissions or paths."
    exit 1
fi

echo -e "$DRY_RUN_OUTPUT"

PREV_FILES_TO_DELETE=$(cat "$FILES_TO_DELETE_FILE") # load files that would be deleted by --delete option from previous run
FILES_TO_DELETE=$(echo "$DRY_RUN_OUTPUT" | grep deleting || true) # extract the files that would be deleted from the dry run output

### USER APPROVAL ###
{
    trap '' ERR

    # prompt user for approval only if the destination directory has changed or hasn't been approved before
    if [ ! -f "$APPROVED_COMMAND_FILE" ] || ! grep -Fxq "$RSYNC_COMMAND" "$APPROVED_COMMAND_FILE"; then

        kdialog --title "Rsync Data Backup" --warningcontinuecancel \
        "The following Rsync command will be executed:\n\n$RSYNC_COMMAND\n\nDo you wish to continue?"

        if [ $? -ne 0 ]; then
            kdialog --title "Backup Script" --icon dialog-cancel --passivepopup "Backup Script Canceled." 10
            exit 1
        fi

        DESTINATION_CONTENTS=$(ls -A "$DESTINATION_DIR")

        # Prompt user for additional approval if the destination is not empty
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
}

### USER INTERACTION ###
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
                        saveApproval
                        
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
                    saveApproval
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