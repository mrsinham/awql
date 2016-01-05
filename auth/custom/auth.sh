#!/usr/bin/env bash

##
# Get a Access Token for Google Adwords by using a dedicated custom Web Service
#
# @example of HTTP response
# {
#     "access_token": "ya29.ExaMple",
#     "token_type": "Bearer",
#     "expire_at": "2015-12-20T00:35:58+01:00"
# }

# Envionnement
SCRIPT=$(basename ${BASH_SOURCE[0]})
SCRIPT_PATH="$0"; while [[ -h "$SCRIPT_PATH" ]]; do SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"; done
SCRIPT_ROOT=$(dirname "$SCRIPT_PATH")

# Requires
source "${SCRIPT_ROOT}/../../conf/awql.sh"
source "${AWQL_INC_DIR}/common.sh"

# Help
function usage ()
{
    echo "Usage: ${SCRIPT} \"http://ws.sample.com/token\""
}

# Mandatory options
URL="$1"
REGEX='(https?|ftp|file)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]'
if [[ -z "$URL" ]] || ! [[ "$URL" =~ ${REGEX} ]]; then
    usage
    exit 1
fi

##
# Retrieve access token by calling a custom web service
# @param string $1 URL
# @return stringableArray
function auth ()
{
    local URL="$1"
    local FILE="${AWQL_WRK_DIR}/${AWQL_TOKEN_FILE_NAME}"

    # Check availibility of existing token in cache
    if [[ -f "$FILE" ]]; then
        local TOKEN="$(getTokenFromFile "$FILE")"
        if [[ $? -eq 0 ]]; then
            declare -A -r TOKEN="$TOKEN"
            local TIMESTAMP="$(getTimestampFromUtcDateTime "${TOKEN[EXPIRE_AT]}")"
            if [[ $? -eq 0 ]]; then
                local CURRENT_TIMESTAMP="$(getCurrentTimestamp)"
                if [[ $? -eq 0 ]] && [[ "$TIMESTAMP" -gt "$CURRENT_TIMESTAMP" ]]; then
                    echo -n "$(stringableArray "$(declare -p TOKEN)")"
                    return
                fi
            fi
        fi
        # Cached token is now deprecated
        rm -f "$FILE"
    fi

    # Try to retrieve a fresh token
    refresh "$URL" "$FILE"
    if [[ $? -eq 0 ]]; then
        local AUTH="$(getTokenFromFile "$FILE")"
        if [[ $? -eq 0 ]]; then
            echo -n "$AUTH"
            return
        else
            # Invalid token
            echo "AccessAuthError.UNABLE_TO_FETCH"
            rm -f "$FILE"
        fi
    fi

    # Unable to retrieve a valid token
    return 1
}

##
# Send request to custom Web Service to retrieve a Google Access Token
# @param string $1 URL
# @param string $2 FILE
function refresh ()
{
    local URL="$1"
    local FILE="$2"

    # Connexion to Google Account
    local HTTP_STATUS_CODE=$(curl \
        --silent --connect-timeout 1 --max-time 600 \
        --request "GET" "$URL" \
        --output "$FILE" \
        --write-out "%{http_code}"
    )

    if [[ "$HTTP_STATUS_CODE" -eq 0 ]] || [[ "$HTTP_STATUS_CODE" -gt 400 ]]; then
        echo "RefreshAuthError.CUSTOM_REQUEST_FAIL"
        rm -f "$FILE"
        return 1
    fi
}

auth "$URL"
if [[ $? -ne 0 ]]; then
    exit 1
fi