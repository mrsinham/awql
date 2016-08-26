#!/usr/bin/env bash

# @includeBy /inc/awql.sh
# Load configuration file if is not already loaded
if [[ -z "${AWQL_ROOT_DIR}" ]]; then
    declare -r AWQL_CUR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${AWQL_CUR_DIR}/../conf/awql.sh"
fi

##
# Manage aggregate methods (distinct, count, sum, min, max, avg and group by)
# @example ([DISTINCT]="1" [COUNT]="2 3" [SUM]="4")
# @example ([COUNT]="2" [GROUP_BY]="1")
# @example ([COUNT]="1")
# @param string $1 Filepath
# @param string $2 Aggregates
# @param string $3 Group
# @return string Filepath
function __aggregateRows ()
{
    local file="$1"
    if [[ -z "$file" || ! -f "$file" || "$file" != *"${AWQL_FILE_EXT}" ]]; then
        return 1
    fi
    if [[ -z "$2" ]]; then
        echo "$file"
        return 0
    elif [[ "$2" != "("*")" ]]; then
        return 1
    fi
    declare -A aggregates="$2"
    local groupBy="$3"
    if [[ 0 -eq "${#aggregates[@]}" && -z "$groupBy" ]]; then
        echo "$file"
        return 0
    fi

    local extendedFile="$(checksum "${AWQL_AGGREGATE_GROUP}${groupBy// /-} ${aggregates[@]}")"
    local wrkFile="${file//${AWQL_FILE_EXT}/___${extendedFile}${AWQL_FILE_EXT}}"
    if [[ -f "$wrkFile" ]]; then
        # Job already done
        echo "$wrkFile"
        return 0
    fi

    # Move header line in working file and add aggregated data
    head -1 "$file" > "$wrkFile" && awk -v omitHeader=1 -v groupByColumns="$groupBy" \
                                        -v avgColumns="${aggregates["${AWQL_AGGREGATE_AVG}"]}" \
                                        -v distinctColumns="${aggregates["${AWQL_AGGREGATE_DISTINCT}"]}" \
                                        -v countColumns="${aggregates["${AWQL_AGGREGATE_COUNT}"]}" \
                                        -v maxColumns="${aggregates["${AWQL_AGGREGATE_MAX}"]}" \
                                        -v minColumns="${aggregates["${AWQL_AGGREGATE_MIN}"]}" \
                                        -v sumColumns="${aggregates["${AWQL_AGGREGATE_SUM}"]}" \
                                        -f "${AWQL_TERM_TABLES_DIR}/aggregate.awk" "$file" >> "$wrkFile"
    if [[ $? -ne 0 ]]; then
        return 1
    else
        echo "$wrkFile"
    fi
}

##
# Manage limit clause
# @example 5 10
# @param string $1 Filepath
# @param string $2 Limits
# @return string Filepath
function __limitRows ()
{
    local file="$1"
    if [[ -z "$file" || ! -f "$file" || "$file" != *"${AWQL_FILE_EXT}" ]]; then
        return 1
    fi
    declare -a limit="($2)"
    declare -i limitRange="${#limit[@]}"
    if [[ ${limitRange} -eq 0 ]]; then
        echo "$file"
        return 0
    elif [[ ${limitRange} -gt 2 ]]; then
        return 1
    fi

    # Limit size of data to display
    local wrkFile="${file//${AWQL_FILE_EXT}/_${2// /-}${AWQL_FILE_EXT}}"
    if [[ -f "$wrkFile" ]]; then
        # Job already done
        echo "$wrkFile"
        return 0
    fi

    # Keep only first line for column names and lines in bounces
    declare -a limitOptions=("-v withHeader=1")
    if [[ ${limitRange} -eq 2 ]]; then
        limitOptions+=("-v rowOffset=${limit[0]}")
        limitOptions+=("-v rowCount=${limit[1]}")
    else
        limitOptions+=("-v rowCount=${limit[0]}")
    fi

    awk ${limitOptions[@]} -f "${AWQL_TERM_TABLES_DIR}/limit.awk" "$file" > "$wrkFile"
    if [[ $? -ne 0 ]]; then
        return 1
    else
        echo "$wrkFile"
    fi
}

##
# Manage order clause
# @example d 2 0
# @param string $1 Filepath
# @param string $2 OrderBy
# @return string Filepath
function __sortingRows ()
{
    local file="$1"
    if [[ -z "$file" || ! -f "$file" || "$file" != *"${AWQL_FILE_EXT}" ]]; then
        return 1
    fi
    declare -a orders
    IFS="," read -a orders <<<"$2"
    declare -i numberOrders="${#orders[@]}"
    if [[ 0 -eq ${numberOrders} ]]; then
        echo "$file"
        return 0
    fi

    local wrkFile="${2// /-}"
    wrkFile="${file//${AWQL_FILE_EXT}/__${wrkFile//,/}${AWQL_FILE_EXT}}"
    if [[ -f "$wrkFile" ]]; then
        # Job already done
        echo "$wrkFile"
        return 0
    fi

    # Input field separator
    local sort=""
    declare -a sortOptions=("-t,")
    declare -i pos=0
    for (( pos=0; pos < ${numberOrders}; pos++ )); do
        declare -a order="(${orders[${pos}]})"
        if [[ 3 -ne "${#order[@]}" ]]; then
            return 1
        fi

        # Also see syntax: -k+${order[1]} -${order[0]} [-r]
        sort="-k${order[1]},${order[1]}${order[0]}"
        if [[ ${order[2]} -eq ${AWQL_SORT_ORDER_DESC} ]]; then
            sort+="r"
        fi
        sortOptions+=("$sort")
    done

    # Temporary remove header line for sorting, use the default language for output, and forces sorting to be bytewise
    head -1 "$file" > "$wrkFile" && sed 1d "$file" | LC_ALL=C sort ${sortOptions[@]} >> "$wrkFile"
    if [[ $? -ne 0 ]]; then
        return 1
    else
        echo "$wrkFile"
    fi
}

##
# Add context of the query (time duration & number of lines)
# @example 2 rows in set (0.93 sec)
#
# @param string $1 File path
# @param int $2 Number of line
# @param float $3 Time duration in milliseconds to get the data
# @param int $4 Caching
# @param int $5 Verbose
# @return string
function __printContext ()
{
    local file="$1"
    declare -i fileSize="$2"
    local timeDuration="$3"
    declare -i cache="$4"
    declare -i verbose="$5"

    # Size
    local size
    if [[ ${fileSize} -le 1 ]]; then
        size="Empty set"
    elif [[ ${fileSize} -eq 2 ]]; then
        size="1 row in set"
    else
        # Exclude header line
        size="$(($fileSize-1)) rows in set"
    fi

    # Time duration
    local duration
    if [[ -z "$timeDuration" ]]; then
        timeDuration="0.00"
    fi
    duration="${timeDuration/,/.}"

    # File path & cache
    local source
    if [[ ${verbose} -eq 1 ]]; then
        if [[ -n "$file" && -f "$file" ]]; then
            source="@source ${file}"
            if [[ ${cache} -eq 1 ]]; then
                source="${source} @cached"
            fi
        fi
    fi

    printf "%s (%s sec) %s\n\n" "$size" "$duration" "$source"
}

##
# Print CSV file with termTables
#
# @param string $1 File path
# @param int $2 Vertical mode
# @param string $3 Headers
# @return string
# @returnStatus 1 If file is empty or do not exist
function __printFile ()
{
    local file="$1"
    if [[ -z "$file" || ! -f "$file" ]]; then
        return 1
    fi
    declare -i vertical="$2"
    local headers="$3"
    declare -i rawMode="$4"

    # Format CVS to display it in a shell terminal
    if [[ ${rawMode} -eq 1 ]]; then
        cat "$file"
    else
        awk -v verticalMode=${vertical} -v replaceHeader="$headers" -f "${AWQL_TERM_TABLES_DIR}/termTable.awk" "$file"
    fi
}

##
# Show response & info about it
# @param arrayToString $1 Request
# @param arrayToString $2 Response
# @return string
function awqlResponse ()
{
    if [[ $1 != "("*")" || $2 != "("*")" ]]; then
        echo "${AWQL_INTERNAL_ERROR_CONFIG}"
        return 1
    fi
    declare -A request="$1"
    declare -A response="$2"

    # Print Awql response
    declare -i fileSize=0 rawMode="${request["${AWQL_REQUEST_RAW}"]}"
    local file="${response["${AWQL_RESPONSE_FILE}"]}"
    if [[ -f "$file" ]]; then
        fileSize="$(wc -l < "$file")"
    fi
    if [[ ${fileSize} -eq 0 ]]; then
        # No result in file
        return 2
    elif [[ ${fileSize} -gt 1 ]]; then
        if [[ ${fileSize} -gt 2 ]]; then
            # Manage group by, avg, distinct, count or sum methods
            file="$(__aggregateRows "$file" "${request["${AWQL_REQUEST_AGGREGATES}"]}" "${request["${AWQL_REQUEST_GROUP}"]}")"
            if [[ $? -ne 0 ]]; then
                echo "${AWQL_INTERNAL_ERROR_AGGREGATES}"
                return 1
            fi
            # Manage order clause
            file="$(__sortingRows "$file" "${request["${AWQL_REQUEST_ORDER}"]}")"
            if [[ $? -ne 0 ]]; then
                echo "${AWQL_INTERNAL_ERROR_ORDER}"
                return 1
            fi
            # Manage limit clause
            file="$(__limitRows "$file" "${request["${AWQL_REQUEST_LIMIT}"]}")"
            if [[ $? -ne 0 ]]; then
                echo "${AWQL_INTERNAL_ERROR_LIMIT}"
                return 1
            fi
            # Update the file size
            fileSize="$(wc -l < "$file")"
        fi

        # Print results
        __printFile "$file" "${request["${AWQL_REQUEST_VERTICAL}"]}" "${request["${AWQL_REQUEST_HEADERS}"]}" ${rawMode}
        if [[ $? -ne 0 ]]; then
            echo "${AWQL_INTERNAL_ERROR_DATA_FILE}"
            return 1
        fi
    fi

    # Add context (file size, time duration, etc.)
    if [[ ${rawMode} -eq 0 ]]; then
        local timeDuration="${response["${AWQL_RESPONSE_TIME_DURATION}"]}"
        declare -i cache="${response["${AWQL_RESPONSE_CACHED}"]}"
        declare -i verbose="${request["${AWQL_REQUEST_VERBOSE}"]}"

        # Add debugs
        if [[ "${request["${AWQL_REQUEST_DEBUG}"]}" -eq 1 ]]; then
            local debug=""
            for debug in "${!request[@]}"; do
                if [[ "$debug" == "${AWQL_REQUEST_TYPE}" || "$debug" == "${AWQL_REQUEST_STATEMENT}" ||\
                      "$debug" == "${AWQL_REQUEST_VERBOSE}" || "$debug" == "${AWQL_REQUEST_RAW}" ||\
                      "$debug" == "${AWQL_REQUEST_DEBUG}" \
                   ]]; then
                    continue
                fi
                echo -e "${BP_ASCII_COLOR_GRAY}${debug}: ${request["${debug}"]}${BP_ASCII_COLOR_OFF}"
            done
        fi
        __printContext "$file" ${fileSize} "$timeDuration" ${cache} ${verbose}
    fi
}