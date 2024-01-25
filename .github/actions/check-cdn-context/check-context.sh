#!/usr/bin/env bash

set -euo pipefail

# Define variables
readonly SCRIPT_NAME=$(basename "${0}")

# Extract JIRA code from branch name
function getJiraCodeFromBranch {
    # Get PR number from GITHUB_REF
    # PR_NUMBER=$(echo ${GITHUB_REF} | awk 'BEGIN { FS = "/" } ; { print $3 }')

    # Check if source branch is project or epic
    if [[ ${GITHUB_REF_NAME} =~ ^(project|epic)/.*$ ]]; then
        # Extract JIRA codes from branch pattern (ex: project/MAESTRO-1186/feature/MAESTRO-1151)
        JIRA_CODE=$(echo "${GITHUB_REF_NAME}" | awk 'BEGIN { FS = "/" } ; { print $4 }')
    else
        # Extract JIRA codes from branch pattern (ex: feature/MAESTRO-1280, or tech/DEVOPS-160_refactoring)
        JIRA_CODE=$(echo "${GITHUB_REF_NAME}" | awk 'BEGIN { FS = "/" } ; { print $2 }')
    fi

    # Check JIRA ticket code format and clean up if not compliant
    if [ ! -z "${JIRA_CODE}" ]; then
        JIRA_CODE=$(echo "${JIRA_CODE}" | grep -P -o '^[A-Z]{2,}-[0-9]+' || echo "")
        # echo "::notice title=Set context::JIRA_CODE output value is '${JIRA_CODE}'"
    fi

    if [ -z "${JIRA_CODE}" ]; then
        echo "${SCRIPT_NAME}::Naming convention error: could not extract JIRA ticket code from source branch ref '${GITHUB_REF_NAME}'" >>"${GITHUB_STEP_SUMMARY}"
    fi
}

function main() {

    local ENVIRONMENT=${1:-"test"}
    local JIRA_CODE=""
    local TAG_NAME=""

    # Manual case uses image static tag
    if [ "${GITHUB_EVENT_NAME}" = "workflow_dispatch" ]; then
        getJiraCodeFromBranch
        TAG_NAME=${JIRA_CODE}
        # use short SHA for sandbox if JIRA code is not set
        if [ "${ENVIRONMENT}" = "sandbox" ]; then
            TAG_NAME=$(echo "${GITHUB_SHA}" | cut -c1-7)
        fi
        # Check if environment is test or sandbox before using it
        if [ "${ENVIRONMENT}" != "test" ] && [ "${ENVIRONMENT}" != "sandbox" ]; then
            echo "::error title=Set context::Invalid environment: '${ENVIRONMENT}'. Only 'test' and 'sandbox' environments are allowed for ${GITHUB_EVENT_NAME} events."
            exit 1
        fi
        ENVIRONMENT_OUTPUT="$ENVIRONMENT"
    elif [ "${GITHUB_REF_TYPE}" = "tag" ] && [ ${GITHUB_EVENT_NAME} = "release" ]; then
        TAG_NAME=${GITHUB_REF_NAME}
        if [[ $(echo "${GITHUB_REF_NAME}" | grep -P '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$') ]]; then
            # SemVer with suffix (1.0.0-alpha.1)
            ENVIRONMENT_OUTPUT="release"
        elif [[ $(echo "${GITHUB_REF_NAME}" | grep -P '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') ]]; then
            # SemVer without suffix (1.0.0)
            ENVIRONMENT_OUTPUT=prod
        else
            echo "::error title=Set context::Tag format error: your git tag does not respect Semantic Versioning, see https://regex101.com/r/vkijKf/1/"
            echo "::error title=Set context::Could not set Env with ref_type '${GITHUB_REF_TYPE}' and ref_name '${GITHUB_REF_NAME}'"
            exit 1
        fi
    elif [ "${GITHUB_REF_TYPE}" = "branch" ] && [ "${GITHUB_EVENT_NAME}" = "pull_request" ]; then
        getJiraCodeFromBranch
        ENVIRONMENT_OUTPUT="test"
    else
        echo "::error title=Set context::Not implemented case with event '${GITHUB_EVENT_NAME}' and ref_type '${GITHUB_REF_TYPE}'"
        exit 1
    fi

    echo "ENVIRONMENT=${ENVIRONMENT_OUTPUT}" >>"${GITHUB_OUTPUT}"
    echo "JIRA_CODE=${JIRA_CODE}" >>"${GITHUB_OUTPUT}"
    echo "TAG_NAME=${TAG_NAME}" >>"${GITHUB_OUTPUT}"

}

# Call main function
main "$@"
