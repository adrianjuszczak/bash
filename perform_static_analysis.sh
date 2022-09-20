#!/bin/bash
ARGS=$(getopt -o ahvV --long ,all-files,clang-config:,conan-dir:,git-branch:,help,lum-build-dir:,manual:,repo-dir:,summary,output-dir:,log-file:,verbose-level:,version -- "$@") || exit

GIT_BRANCH=""
HCP2_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
CLANG_CONFIG_JSON_FILE=""
CONAN_CACHE_DIR="/home/${USER}/.conan/data"
LUM_BUILD_DIR=${HCP2_DIR}/e3_comp_lum/build
MANUAL_ANALYSIS_DIR=""
REPORTS_DIRECTORY=""
LOG_FILE=""
SUMMARY_FLAG="false"
declare -i VERBOSE_LEVEL="0"

CHECK_ALL_FILES=false

call_according_to_verbose_level() {
    if [ "$VERBOSE_LEVEL" -gt 0 ]; then
        [ "$VERBOSE_LEVEL" = 1 ] && { $1 "--verbose" "${@: 2}"; } || { [ "$VERBOSE_LEVEL" = 2 ] && { set -x; "$@"; } }
    else
        "$@"
    fi
}

error() {
    local FONT_RED='\033[0;31m'
    local FONT_NC='\033[0m'
    
    echo -e "${FONT_RED} ------ Error ------ ${FONT_NC} $1"
    exit 1
}

# The following functions search for all compile commands files and merge them using jq package.
# Files that need to be statically analyzed are treated as keys, on the basis of which objects
# are extracted and merged to the final compile_comands JSON file.
merge_compile_commands() {
    local CONAN_CACHE_DIR=$1
    local LUM_BUILD_DIR=$2
    local REPORTS_DIRECTORY=$3
    local MANUAL_ANALYSIS_DIR=$4
    local SEARCH_DIRECTORY="$CONAN_CACHE_DIR $LUM_BUILD_DIR"
    
    [ -z "$MANUAL_ANALYSIS_DIR" ] || { SEARCH_DIRECTORY="$MANUAL_ANALYSIS_DIR"; }
    local PATHS_TO_COMPILE_COMMANDS=$(find $SEARCH_DIRECTORY -type f -name '*compile_commands.json*')
    
    [ "$VERBOSE_LEVEL" != "0" ] && { echo "Paths to compile commands json files:"; echo "$PATHS_TO_COMPILE_COMMANDS"; }
    
    jq -s add $PATHS_TO_COMPILE_COMMANDS > "$REPORTS_DIRECTORY"/compile_commands.json # merging compile_commands.json files into one
}

# This function uses git to check which files were modified after the last delivery was merged into the main branch.
# It compares the delivery branch with the main branch, then returns the elaborated list with modified files.
collect_last_modified_files() {
    local HCP2_DIR=$1
    local CHECK_ALL_FILES=$2
    local MANUAL_ANALYSIS_DIR=$3
    
    if [ "$MANUAL_ANALYSIS_DIR" = "" ]; then
        local LAST_COMMIT_SHA=$(git -C "$HCP2_DIR" log origin/deliveries -1 | sed 's/commit //p' | head -1)
        # grep: ignore all files, except those with ending .cpp, .h, .hpp
        # sed: removes redundant spaces in paths 
        local PATHS_TO_ANALYZED_FILES=$(git diff --name-status "$LAST_COMMIT_SHA" | grep -v "\.py\|.cfg\|.json\|.txt\|.yml" | grep -e "\\.cpp\|\.h\|\.hpp"$ | sed -E 's/[A-Z][[:space:]]+//g')
        [ "$CHECK_ALL_FILES" = false ] && PATHS_TO_ANALYZED_FILES=$(echo "$PATHS_TO_ANALYZED_FILES" | grep -v "test\|mock")
    else
        local PATHS_TO_ANALYZED_FILES=$(find "$MANUAL_ANALYSIS_DIR" -wholename "*.cpp" -o -wholename ".c" -o -wholename "*.hpp" -o -wholename "*.h")
    fi
    
    echo "$PATHS_TO_ANALYZED_FILES"
}

# Static analysis is performed only on the last changed files.
# Keys are the values of those files and are used for extracting needed objects (e.g. file plus CMake build command)
get_keys_from_json() {
    local REPORTS_DIRECTORY=$1
    local HCP2_DIR=$2
    local CHECK_ALL_FILES=$3
    local MANUAL_ANALYSIS_DIR=$4
    local EXTRACTED_JSON_KEYS=""
    
    for i in $(collect_last_modified_files "$HCP2_DIR" "$CHECK_ALL_FILES" "$MANUAL_ANALYSIS_DIR"); do  # collecting keys needed for later files extracting process
        EXTRACTED_JSON_KEYS=$EXTRACTED_JSON_KEYS' '$(grep -Eo "\"file\".*${i}" "$REPORTS_DIRECTORY"/compile_commands.json | sed 's/"file": "//g')
    done

    EXTRACTED_JSON_KEYS=$(echo "$EXTRACTED_JSON_KEYS" | xargs -n1 | sort -u | xargs);     # remove duplicate
    
    echo "$EXTRACTED_JSON_KEYS"
}

help() {
    local FONT_BOLD=$(tput bold)
    local FONT_NORMAL=$(tput sgr0)
    
cat <<- EOF

${FONT_BOLD}NAME
    ${FONT_NORMAL}PERFORM STATIC ANALYSIS

${FONT_BOLD}SYNOPSIS
    ${FONT_NORMAL}perform_static_analysis [-a] [-h] [-v] [-V] [--all-files] [--clang-config] [--compile-commands-file] [--conan-dir] [--git-branch] [--help] [--manual] 
    [--lum-build-dir] [--repo-dir] [--summary] [--log-file] [--verbose-level] [--version] --output-dir

${FONT_BOLD}OPTIONS
    ${FONT_NORMAL}General options
        ${FONT_BOLD} -a, --all-files
            ${FONT_NORMAL} Perform static analysis on all files, tests and mocks included.
        ${FONT_BOLD} --clang-config
            ${FONT_NORMAL} The path to the file containing a config for clang-tidy
        ${FONT_BOLD} --conan-dir
            ${FONT_NORMAL} Absolute path to conan cache directory.
        ${FONT_BOLD} -h, --help
            ${FONT_NORMAL} Print a help message and exit.
        ${FONT_BOLD} --compile-commands-file
            ${FONT_NORMAL} Absolute path to compile-commands.json database.
        ${FONT_BOLD} --lum-build-dir
            ${FONT_NORMAL} Absolute path to lum build directory.
        ${FONT_BOLD} --log-file
            ${FONT_NORMAL} Optional report name.
        ${FONT_BOLD} --manual
            ${FONT_NORMAL} Performs static analysis at pointed directory. Directory shall contain both source files and compile-commands.json file. 
        ${FONT_BOLD} --repo-dir
            ${FONT_NORMAL} Absolute path to repository.
        ${FONT_BOLD} --summary
            ${FONT_NORMAL} Prints summary of static analysis.
        ${FONT_BOLD} --verbose-level
            ${FONT_NORMAL} Integer value in range 0-2. Value 1 sets --verbose flag, value 2 sets set -x flag.
        ${FONT_BOLD} --output-dir
            ${FONT_NORMAL} Required absolute path for saving static analysis report.



${FONT_BOLD}DESCRIPTION
        ${FONT_NORMAL}Execution of script performs static analysis which uses clang-tidy and basis at compile_commands JSON files generated by CMake.
        During analysis only the last changed files according to git SHA compared between main and delivery branches are checked.
        It is IMPORTANT to note that ${FONT_BOLD}test and mocks files are not included ${FONT_NORMAL}in the default static analysis sequence.
        In order to add them you have to add --all flag.

        The static analysis is executed in the following steps:
            1.	Creating last modified files using git

            2.	Finding paths to last modified files
                    used commands: grep, find

            3.	Finding compile_commands.json files
                    used commands: find

            4.	Merging previously found compile_commands.json files into one.
                    used commands: jq (the jq package need to be additionally installed on host)

            5.	Extracting needed files
                    used commands: jq
EOF
}

main () {
    local CONAN_CACHE_DIR=$(jq -r '.conan_dir' <<< $1)
    local LUM_BUILD_DIR=$(jq -r '.lum_dir' <<< $1)
    local REPORTS_DIRECTORY=$(jq -r '.output_dir' <<< $1)
    local MANUAL_ANALYSIS_DIR=$(jq -r '.manual_analysis_dir' <<< $1)
    local CLANG_CONFIG_JSON_FILE=$(jq -r '.clang_config_json_file' <<< $1)
    local HCP2_DIR=$(jq -r '.hcp2_dir' <<< $1)
    local LOG_FILE=$(jq -r '.log_file' <<< $1)
    local SUMMARY_FLAG=$(jq -r '.summary_flag' <<< $1)
    
    local FILE=${REPORTS_DIRECTORY}/${LOG_FILE}
    [ -f "$FILE" ] && { call_according_to_verbose_level mv "$FILE" "${FILE}_old"; }
    
    merge_compile_commands "$CONAN_CACHE_DIR" "$LUM_BUILD_DIR" "$REPORTS_DIRECTORY" "$MANUAL_ANALYSIS_DIR"
    
    local ACTIVE_CHECKERS=$(jq '."clang-tidy"."active-checkers"' ${CLANG_CONFIG_JSON_FILE})
    local COMPILATION_OPTIONS=$(jq '."clang-tidy"."compilation-options"' ${CLANG_CONFIG_JSON_FILE})
    local HEADER_FILTER=$(jq '."header-filter"."active-checkers"' ${CLANG_CONFIG_JSON_FILE})

    for i in $(get_keys_from_json "$REPORTS_DIRECTORY" "$HCP2_DIR" "$CHECK_ALL_FILES" "$MANUAL_ANALYSIS_DIR"); do  # starts static analysis
        [ "$VERBOSE_LEVEL" != "0" ] && { echo "Performing static analysis on: ${i}"; }                                                                                                                  # FIX ME: add additional variables for including headears path 
        clang-tidy --checks="$ACTIVE_CHECKERS" -header-filter="$HEADER_FILTER" -p "$REPORTS_DIRECTORY"/compile_commands.json "${i}" -- "$COMPILATION_OPTIONS"  >> "$REPORTS_DIRECTORY"/"$LOG_FILE"
    done
    
    [ "$VERBOSE_LEVEL" != "0" ] && { echo "Output files saved in $REPORTS_DIRECTORY"; }  
}

validation_before_start() {
    [ "$(jq --version)" ] && [ "$(git --version)" ] || { error "Required tools were not found. Check if jq and git packages are installed."; exit 2; }
    [ -f "$CLANG_CONFIG_JSON_FILE" ] || { error " Path to the clang config file needed or consider generating the default config with -C option."; }
    [ "$VERBOSE_LEVEL" != "0" ] && { echo "Default config file saved in ${CLANG_CONFIG_JSON_FILE}"; }   
    
    path_verification='[{"var":"'$HCP2_DIR'"},{"var":"'$CONAN_CACHE_DIR'"},{"var":"'$LUM_BUILD_DIR'"},{"var":"'$REPORTS_DIRECTORY'"}]'
    for row in $(echo "$path_verification" | jq -r '.[] | @base64'); do
        var=$(echo "$row" | base64 --decode  | jq "$1" | jq -r '.var')
        [ "$var" ] && [ -n "$var" ] || { echo "Path verification failed. Refer to the manual."; exit 3; }
    done
    
    [ "$MANUAL_ANALYSIS_DIR" != "" ] && { [ -d "$MANUAL_ANALYSIS_DIR" ] || { error "No such directory $MANUAL_ANALYSIS_DIR"; exit 4; } }
    [ "$LOG_FILE" ] || { LOG_FILE=staticAnalysisOutput_$(date '+%Y-%m-%d').txt; } &&
    [ "$VERBOSE_LEVEL" != "0" ] && { echo "Default value \"staticAnalysisOutput_$(date '+%Y-%m-%d').txt\" assigned to \"LOG_FILE\" variable."; }
    [[ $SUMMARY_FLAG = "false" || $SUMMARY_FLAG = "true" ]] || {  error "Summary flag value not correct."; exit 5; }
    
    local GIT_BRANCH=$1
    git branch -a | grep -w $GIT_BRANCH >/dev/null 2>&1 || { GIT_BRANCH=${GIT_BRANCH:-"origin/main"} &&
    [ "$VERBOSE_LEVEL" != "0" ] && { echo "Default value \"origin/main\" assigned to GIT_BRANCH variable."; } }
    
    local MAIN_ARGUMENT='{"all":"'$CHECK_ALL_FILES'",
        "conan_dir":"'$CONAN_CACHE_DIR'",
        "lum_dir":"'$LUM_BUILD_DIR'",
        "output_dir":"'$REPORTS_DIRECTORY'",
        "manual_analysis_dir":"'$MANUAL_ANALYSIS_DIR'",
        "clang_config_json_file":"'$CLANG_CONFIG_JSON_FILE'",
        "hcp2_dir":"'$HCP2_DIR'",
        "log_file":"'$LOG_FILE'",
        "summary_flag":"'$SUMMARY_FLAG'"}'
    
    [ "$VERBOSE_LEVEL" != "0" ] && { echo "$MAIN_ARGUMENT"; }
    
    main "$MAIN_ARGUMENT"
}

# # Loop until all parameters are used up
eval "set -- $ARGS"
while true ;
do
    case "$1" in
        --all-files)
            CHECK_ALL_FILES=true
            shift
        ;;
        --clang-config)
            if [ "$2" == "-C" ]; then
                echo '{"clang-tidy": {"active-checkers": "-clang-analyzer-cplusplus*", "header-filter": "=.*", "compilation-options": ""}}' | jq '.' \
                > "$HCP2_DIR/helper_scripts/test/perform_static_analysis/clang_config.json"
                CLANG_CONFIG_JSON_FILE="$HCP2_DIR/helper_scripts/test/perform_static_analysis/clang_config.json"
            else 
                CLANG_CONFIG_JSON_FILE=$2
            fi
            shift 2
        ;;
        --conan-dir)
            CONAN=$2
            shift 2
        ;;
        --git-branch)
            GIT_BRANCH=$2
            shift=$2
        ;;
        -h | --help)
            help
            exit 0
        ;;
        --lum-build-dir)
            LUM_BUILD_DIR=$2
            shift 2
        ;;
        --manual)
            MANUAL_ANALYSIS_DIR=$2
            shift 2
        ;;
        --repo-dir)
            HCP2_DIR=$2
            shift 2
        ;;
        --output-dir)
            REPORTS_DIRECTORY=$2
            shift 2
        ;;
        --log-file)
            LOG_FILE=$2
            shift 2
        ;;
        --summary)
            SUMMARY_FLAG=true
            shift
        ;;
        -V | --verbose-level)
            [[ "$2" -gt 2 || "$2" -lt 0 ]] && { error "Value of verbose level not correct. Refer to the manual."; exit 6; } || { VERBOSE_LEVEL=$2; }
            shift 2
        ;;
        -v | --version)
            echo "Perform Static Analysis 0.1"
            exit 0
        ;;
        --)
            shift
            break
        ;;
    esac
done

validation_before_start "$GIT_BRANCH"
