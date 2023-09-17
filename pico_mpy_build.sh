#!/bin/bash

USAGE() {
    echo
    echo "USAGE: $0 [OPTION]...  <repo_path>"
    echo 
    echo "Required paramaters: "
    echo -e "\t<repo_path> - The path to the micropython repo to use for the firmware build."
    echo -e "\t(Downloaded with 'git clone https://github.com/micropython/micropython.git')"
    echo
    echo "Available Options: "
    echo -e "\t-b <board>           -  Target board to build micropython firmware for. ( Default: 'RPI_PICO_W' )"
    echo -e "\t-p <port>            -  Target port to use for the micropython build. ( Default: 'rp2' )"
    echo -e "\t--no-package-check   -  Skips the check for required packages for the build. "
    echo
        
}

#Set to 1 for extra debug output
DEBUG=1
DATE_STAMP="$(date +%d%m%y)_$(($(date +%s) - $(date -d "$(date '+%B %d, %Y')" +%s)))"
LOGFILE="/tmp/micropython-build.${DATE_STAMP}.log"


        #                                #
        # Parsing options and paramaters # 
        #                                #

#Default target board and micropython port to build for.
#command line options will take precedence over these if they are provided
TARGET_BOARD="RPI_PICO"
TARGET_PORT="rp2"
DO_PACKAGE_CHECK=1

param_count=$#
index=0
if [ $# -ne 0 ]; then
    while [ $index -lt $param_count ];  do
        case $1 in
            "-b")
                TARGET_BOARD=$2
                index=$(($index+2))
                shift
                shift ;;
            "-p")
                TARGET_PORT=$2
                index=$(($index+2))
                shift
                shift;;
            "--no-package-check")
                DO_PACKAGE_CHECK=0
                index=$(($index+1))
                shift;;
            "help" | "--help" | "-h" )
                USAGE
                exit 0;;
            *)
                #Parse the last value as the required micropython path 
                if [ -z $2 ]; then
                    REPO_PATH=$1
                    index=$(($index+1))
                    shift
                else
                    echo "Error: Unexpected option $1 !"
                    USAGE
                    exit 1
                fi
        esac
    done
else
    USAGE
    exit 0
fi


        #                                       #
        # Validating paramaters and envrionment #
        #                                       #

if [ ! -d $REPO_PATH ]; then
    echo "Error: Provided micropython repo does not exist!!"
    echo "Got path: $REPO_PATH"
    USAGE
    exit 1
fi

REPO_CHECK=$(grep -q 'https://github.com/micropython/micropython.git' ${REPO_PATH}/.git/config 2>&1)
RC=$?
if [ $RC -ne 0 ] ; then
    echo "Error: provided  repo does not look like a valid micropython repo... Exiting."
    USAGE
    exit 1
else
    echo "Target directory does seem to be  micropython repo."
fi

if [ $DO_PACKAGE_CHECK -eq 1 ]; then
    REQ_PACKAGES="cmake gcc-arm-none-eabi libnewlib-arm-none-eabi build-essential"
    for pack in $REQ_PACKAGES ; do
        PACK_TEST=$(dpkg --get-selections | awk -F' ' '{print $1}'| grep "^$pack$")
        RC=$?
        if [  $RC -ne 0 ] ; then
            echo "Error: $pack package not found installed on the system! Either install it or skip the package checks."
            USAGE
            exit 1
        fi   
    done
    echo "Check for required packages complete!"
else
    echo "Note: Check for required system packages skipped." | tee $LOGFILE
fi

        ###########################
        #  Start of builds/makes  #
        ###########################

echo "Executing micropython firmware build with these settings: "
echo -e "\t Target Board: $TARGET_BOARD"
echo -e "\t Micropython Port: $TARGET_PORT"
echo -e "\t Micropython Repo Path: $REPO_PATH"


echo "Clearing out old build artifacts..."
if [ $DEBUG -eq 1 ]; then
    make BOARD=$TARGET_BOARD -C ${REPO_PATH}/ports/$TARGET_PORT clean 2>&1 | tee -a $LOGFILE
    RC=$?
else
    make BOARD=$TARGET_BOARD -C ${REPO_PATH}/ports/$TARGET_PORT clean > $LOGFILE 2>&1
    RC=$?
fi
if [ $RC -ne 0 ] ; then
    echo "Error: Got non-zero return code from make clean in $REPO_PATH !"
    echo -e "\nCheck the full build logs for more information: $LOGFILE \n"
    USAGE
    exit 1
else
    echo "Cleanup finished."
fi

# ---

echo "Starting micropython sub-modules build..."
if [ $DEBUG -eq 1 ]; then
    make BOARD=$TARGET_BOARD -C ${REPO_PATH}/ports/$TARGET_PORT submodules 2>&1 | tee -a $LOGFILE
    RC=$?
else
    make BOARD=$TARGET_BOARD -C ${REPO_PATH}/ports/$TARGET_PORT submodules >> $LOGFILE 2>&1
    RC=$?
fi

if [ $RC -ne 0 ] ; then
    echo "Error: Got non-zero return code from $TARGET_PORT submodules build for $TARGET_BOARD !"
    echo -e "\nCheck the full build logs for more information: $LOGFILE \n"
    USAGE
    exit 1
else
    echo "Submodules Build was successful!"
fi

# --- 

echo "Doing python cross-compiler build..."
if [ $DEBUG -eq 1 ]; then
    make BOARD=$TARGET_BOARD -C ${REPO_PATH}/mpy-cross 2>&1 | tee -a $LOGFILE
    RC=$?
else
    make BOARD=$TARGET_BOARD -C ${REPO_PATH}/mpy-cross >> $LOGFILE 2>&1
    RC=$?
fi

if [ $RC -ne 0 ] ; then
    echo "Error: Got non-zero return code from micropython cross-compiler build !"
    echo -e "\nCheck the full build logs for more information: $LOGFILE \n"
    USAGE
    exit 1
else
    echo "Submodules Build was successful!"
fi

# ---

echo "Starting main build..."
if [ $DEBUG -eq 1 ]; then
    make BOARD=$TARGET_BOARD -C ${REPO_PATH}/ports/$TARGET_PORT 2>&1 | tee -a $LOGFILE
    RC=$?
else
    make BOARD=$TARGET_BOARD -C ${REPO_PATH}/ports/$TARGET_PORT  >> $LOGFILE 2>&1
    RC=$?
fi

if [ $RC -ne 0 ] ; then
    echo "Error: Got non-zero return code from $TARGET_PORT main build for $TARGET_BOARD !"
    echo -e "\nCheck the full build logs for more information: $LOGFILE \n"
    USAGE
    exit 1
else
    echo "Full build output logs has been saved to: $LOGFILE"
    echo
    echo -e "Micropython build was successful! Check out the newly built .u2f file here: \n\t${REPO_PATH}/ports/${TARGET_PORT}/build-${TARGET_BOARD}/firmware.uf2 \n"
fi

# ---

