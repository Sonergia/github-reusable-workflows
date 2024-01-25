#!/bin/bash

# exit when any command fails
set -e

# echo "-------------- DEBUG ENV --------------"
# echo "GITHUB_EVENT_NAME => $GITHUB_EVENT_NAME"
# echo "GITHUB_JOB        => $GITHUB_JOB"
# echo "GITHUB_REPOSITORY => $GITHUB_REPOSITORY"
# echo "GITHUB_WORKFLOW   => $GITHUB_WORKFLOW"
# echo "GITHUB_REF        => $GITHUB_REF"
# echo "GITHUB_REF_NAME   => $GITHUB_REF_NAME"
# echo "GITHUB_REF_TYPE   => $GITHUB_REF_TYPE"
# echo "GITHUB_SHA        => $GITHUB_SHA"
# exit 1

# Successful case workflow_dispatch
# GITHUB_REF_TYPE=branch
# GITHUB_EVENT_NAME=workflow_dispatch
# ENVIRONMENT=test
# GITHUB_REF=refs/pull/1234/merge
# GITHUB_HEAD_REF=feature/TOTO-4567_blablabla
# GITHUB_REF_NAME=feature/TOTO-4567_blablabla

# case workflow_dispatch to sandbox
# GITHUB_REF_TYPE=branch
# GITHUB_EVENT_NAME=workflow_dispatch
# ENVIRONMENT=sandbox
# GITHUB_REF=refs/pull/1234/merge
# GITHUB_REF_NAME=feature/test
# GITHUB_REF_NAME=feature/TOTO-4567_blablabla
# GITHUB_SHA="26e20b6f463484417188263bf58b1bae71ffa8b9"
# GITHUB_OUTPUT=/dev/stdout

# # Successful case latest
# GITHUB_REF_TYPE=branch
# GITHUB_EVENT_NAME=pull_request
# GITHUB_REF=refs/pull/1234/merge
# GITHUB_HEAD_REF=feature/TOTO-4567_blablabla
# GITHUB_REF_NAME=feature/TOTO-4567_blablabla

# # Successful case branch
# GITHUB_REF_TYPE=branch
# GITHUB_EVENT_NAME=pull_request
# GITHUB_REF=refs/pull/1234/merge
# GITHUB_HEAD_REF=feature/TOTO-4567_blablabla
# GITHUB_REF_NAME=feature/TOTO-4567_blablabla

# # Successful case tag release
# GITHUB_REF_TYPE=tag
# GITHUB_EVENT_NAME=release
# GITHUB_REF=refs/tags/1.0.0-alpha.1
# GITHUB_HEAD_REF=
# GITHUB_REF_NAME=1.0.0-alpha.1

# # Successful case tag prod
# GITHUB_REF_TYPE=tag
# GITHUB_EVENT_NAME=release
# GITHUB_REF=refs/tags/1.0.0
# GITHUB_HEAD_REF=
# GITHUB_REF_NAME=1.0.0

# Extract JIRA code from branch name
function getJiraCodeFromBranch {
    # Get PR number from GITHUB_REF
    # PR_NUMBER=$(echo ${GITHUB_REF} | awk 'BEGIN { FS = "/" } ; { print $3 }')

    # Check if source branch is project or epic
    if [[ ${GITHUB_REF_NAME} =~ ^(project|epic)/.*/master$ ]]; then
        # Extract JIRA codes from branch pattern (ex: project/MAESTRO-1186/master)
        JIRA_CODE=$(echo "${GITHUB_REF_NAME}" | awk 'BEGIN { FS = "/" } ; { print $2 }')
    elif [[ ${GITHUB_REF_NAME} =~ ^(project|epic)/.*$ ]]; then
        # Extract JIRA codes from branch pattern (ex: project/MAESTRO-1186/feature/MAESTRO-1151)
        JIRA_CODE=$(echo "${GITHUB_REF_NAME}" | awk 'BEGIN { FS = "/" } ; { print $4 }')
    else
        # Extract JIRA codes from branch pattern (ex: feature/MAESTRO-1280, or tech/DEVOPS-160_refactoring)
        JIRA_CODE=$(echo "${GITHUB_REF_NAME}" | awk 'BEGIN { FS = "/" } ; { print $2 }')
    fi

    # Check JIRA ticket code format and clean up if not compliant
    if [ ! -z "${JIRA_CODE}" ]; then
        # avoid exit code in case JIRA_CODE does not match
        JIRA_CODE=$(echo ${JIRA_CODE} | grep -P -o '^[A-Z]{2,}-[0-9]+' || echo "")
        echo "::notice title=Set context::JIRA_CODE output value is '${JIRA_CODE}'"
    fi

    if [ -z "${JIRA_CODE}" ] && [ "${ENVIRONMENT}" != "sandbox" ]; then
        echo "::warning title=Set context::Naming convention error: could not extract JIRA ticket code from source branch ref '${GITHUB_REF_NAME}'"
    fi
}

# /!\ This script mixes logic from new ECS infra and legacy EC2 infra
# Start script
ENVIRONMENT=${1:-"test"}
IS_LAMBDA=${2:-"false"}
IS_LEGACY=${3:-"false"}
CREATE_TAG_LATEST="false"

# Parameters checks
if [ ${IS_LAMBDA} = "false" ] && [ ${IS_LEGACY} = "true" ]; then
    echo "::error title=Set context::Not implemented case SERVICE+LEGACY"
    exit 1
fi

if [ -z ${IS_LAMBDA} ]; then
    echo "::error title=Set context::IS_LAMBDA flag can not be empty"
    exit 1
fi

if [ -z ${IS_LEGACY} ]; then
    echo "::error title=Set context::IS_LEGACY flag can not be empty"
    exit 1
fi

# Manual case uses image static tag
if [ ${GITHUB_EVENT_NAME} = "workflow_dispatch" ]; then
    getJiraCodeFromBranch
    IMAGE_TAG=${JIRA_CODE}
    # use short SHA for sandbox if JIRA code is not set
    if [ "${ENVIRONMENT}" = "sandbox" ] && [ -z "${IMAGE_TAG}" ]; then
        IMAGE_TAG=$(echo "${GITHUB_SHA}" | cut -c1-7)
    fi
    if [ "${IS_LEGACY}" = "true" ]; then
        ENVIRONMENT_OUTPUT="development"
    else
        # Check if environment is test or sandbox before using it
        if [ "${ENVIRONMENT}" != "test" ] && [ "${ENVIRONMENT}" != "sandbox" ]; then
            echo "::error title=Set context::Invalid environment: '${ENVIRONMENT}'. Only 'test' and 'sandbox' environments are allowed for ${GITHUB_EVENT_NAME} events."
            exit 1
        fi
        ENVIRONMENT_OUTPUT="$ENVIRONMENT"
    fi
elif [ ${GITHUB_REF_TYPE} = "tag" ] && [ ${GITHUB_EVENT_NAME} = "release" ]; then
    # Tag git
    IMAGE_TAG=${GITHUB_REF_NAME}

    if [[ $(echo ${GITHUB_REF_NAME} | grep -P '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$') ]]; then
        # SemVer with suffix (1.0.0-alpha.1)
        # if [ "${IS_LEGACY}" = "true" ]; then ENVIRONMENT_OUTPUT="notprod"; else ENVIRONMENT_OUTPUT="release"; fi
        ENVIRONMENT_OUTPUT=$([ "${IS_LEGACY}" = "true" ] && echo "notprod" || echo "release")
    elif [[ $(echo ${GITHUB_REF_NAME} | grep -P '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') ]]; then
        # SemVer without suffix (1.0.0)
        ENVIRONMENT_OUTPUT=prod
        CREATE_TAG_LATEST="true"
    else
        echo "::error title=Set context::Tag format error: your git tag does not respect Semantic Versioning, see https://regex101.com/r/vkijKf/1/"
        echo "::error title=Set context::Could not set Cluster/Env with ref_type '${GITHUB_REF_TYPE}' and ref_name '${GITHUB_REF_NAME}'"
        exit 1
    fi
elif [ ${GITHUB_REF_TYPE} = "branch" ] && [ ${GITHUB_EVENT_NAME} = "pull_request" ]; then
    getJiraCodeFromBranch
    IMAGE_TAG=${JIRA_CODE}
    # if [ "${IS_LEGACY}" = "true" ]; then ENVIRONMENT_OUTPUT="development"; else ENVIRONMENT_OUTPUT="test"; fi
    ENVIRONMENT_OUTPUT=$([ "${IS_LEGACY}" = "true" ] && echo "development" || echo "test")
else
    echo "::error title=Set context::Not implemented case with event '${GITHUB_EVENT_NAME}' and ref_type '${GITHUB_REF_TYPE}'"
    exit 1
fi

# Integrity checks
if [ -z "${ENVIRONMENT_OUTPUT}" ]; then
    echo "::error title=Set context::Could not set Cluster/Env output value with event '${GITHUB_EVENT_NAME}', ref_type '${GITHUB_REF_TYPE}', ref_name '${GITHUB_REF_NAME}'"
    exit 1
# elif [ "${ENVIRONMENT}" != "${ENVIRONMENT_OUTPUT}" ]; then
#     # This check does not work with all cases
#     echo "::error title=Set context::Input Cluster/Env '${ENVIRONMENT}' does not match with output one '${ENVIRONMENT_OUTPUT}', that smells fishy"
#     exit 1
fi

if [ ${IS_LAMBDA} = "false" ]; then
    echo "::notice title=Set context::Image tag output value is '${IMAGE_TAG}'"
    echo "::notice title=Set context::Create tag latest is '${CREATE_TAG_LATEST}'"

    if [ -z "${IMAGE_TAG}" ]; then
        echo "::error title=Set context::Could not set IMAGE_TAG output value with event '${GITHUB_EVENT_NAME}', ref_type '${GITHUB_REF_TYPE}', ref_name '${GITHUB_REF_NAME}'"
        exit 1
    fi

    # New ECS infra expects CLUSTER var instead of ENVIRONMENT => to fix
    # TODO: la var CLUSTER doit disparaître au profit de ENVIRONMENT
    echo "CLUSTER=${ENVIRONMENT_OUTPUT}" >>${GITHUB_OUTPUT}
    echo "IMAGE_TAG=${IMAGE_TAG}" >>${GITHUB_OUTPUT}
    echo "CREATE_TAG_LATEST=${CREATE_TAG_LATEST}" >>${GITHUB_OUTPUT}
fi

echo "ENVIRONMENT=${ENVIRONMENT_OUTPUT}" >>${GITHUB_OUTPUT}
echo "JIRA_CODE=${JIRA_CODE}" >>${GITHUB_OUTPUT}
