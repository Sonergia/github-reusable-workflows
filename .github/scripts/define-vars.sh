#!/bin/bash

# echo "-------------- DEBUG ENV --------------"
# echo "GITHUB_EVENT_NAME => $GITHUB_EVENT_NAME"
# echo "GITHUB_JOB        => $GITHUB_JOB"
# echo "GITHUB_REPOSITORY => $GITHUB_REPOSITORY"
# echo "GITHUB_WORKFLOW   => $GITHUB_WORKFLOW"
# echo "GITHUB_REF        => $GITHUB_REF"
# echo "GITHUB_REF_NAME   => $GITHUB_REF_NAME"
# echo "GITHUB_REF_TYPE   => $GITHUB_REF_TYPE"
# echo "GITHUB_SHA        => $GITHUB_SHA"
# echo "IMAGE_STATIC_TAG  => $IMAGE_STATIC_TAG"
# exit 1

# # Successful test case latest
# GITHUB_REF_TYPE=branch
# GITHUB_EVENT_NAME=pull_request
# GITHUB_REF=refs/pull/1234/merge
# GITHUB_HEAD_REF=feature/TOTO-4567_blablabla
# GITHUB_REF_NAME=feature/TOTO-4567_blablabla
# IMAGE_STATIC_TAG=latest

# # Successful test case branch
# GITHUB_REF_TYPE=branch
# GITHUB_EVENT_NAME=pull_request
# GITHUB_REF=refs/pull/1234/merge
# GITHUB_HEAD_REF=feature/TOTO-4567_blablabla
# GITHUB_REF_NAME=feature/TOTO-4567_blablabla

# # Successful test case tag release
# GITHUB_REF_TYPE=tag
# GITHUB_EVENT_NAME=release
# GITHUB_REF=refs/tags/1.0.0-alpha.1
# GITHUB_HEAD_REF=
# GITHUB_REF_NAME=1.0.0-alpha.1

# # Successful test case tag prod
# GITHUB_REF_TYPE=tag
# GITHUB_EVENT_NAME=release
# GITHUB_REF=refs/tags/1.0.0
# GITHUB_HEAD_REF=
# GITHUB_REF_NAME=1.0.0

if  [ ${GITHUB_REF_TYPE} == "tag" ]; then
    # Tag git
    CONCURRENCY_CODE=${GITHUB_REF_NAME}

    if  [ ${GITHUB_EVENT_NAME} == "release" ]; then
        if [[ $(echo ${GITHUB_REF_NAME} | grep -P '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$') ]]; then
            # SemVer with suffix (1.0.0-alpha.1)
            CLUSTER=release
        elif [[ $(echo ${GITHUB_REF_NAME} | grep -P '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') ]]; then
            # SemVer without suffix (1.0.0)
            CLUSTER=prod
        else
            echo "::error title=Tag format error::Your git tag does not respect Semantic Versioning format, see https://regex101.com/r/vkijKf/1/"
            echo "::debug::Could not define cluster with ref_type '${GITHUB_REF_TYPE}' and ref_name '${GITHUB_REF_NAME}'"
            exit 1
        fi
    fi
elif [ ${GITHUB_REF_TYPE} == "branch" ]; then
    if  [ ${GITHUB_EVENT_NAME} == "pull_request" ]; then
        # Get PR number from GITHUB_REF
        # PR_NUMBER=$(echo ${GITHUB_REF} | awk 'BEGIN { FS = "/" } ; { print $3 }')

        # Check if source branch is project
        if [[ ${GITHUB_HEAD_REF} =~ ^project/.*$ ]]; then
            # Extract JIRA codes from branch pattern (ex: project/MAESTRO-1186/feature/MAESTRO-1151)
            # JIRA_PROJECT_CODE=$(echo ${GITHUB_HEAD_REF} | awk 'BEGIN { FS = "/" } ; { print $2 }')
            JIRA_TICKET_CODE=$(echo ${GITHUB_HEAD_REF} | awk 'BEGIN { FS = "/" } ; { print $4 }')
        else
            # Extract JIRA codes from branch pattern (ex: feature/MAESTRO-1280)
            JIRA_TICKET_CODE=$(echo ${GITHUB_HEAD_REF} | awk 'BEGIN { FS = "/" } ; { print $2 }')
        fi

        # Check JIRA ticket code format and clean up if not compliant
        JIRA_TICKET_CODE=$(echo ${JIRA_TICKET_CODE} | grep -P -o '^[A-Z]{2,}-[0-9]+')

        if [ -z ${JIRA_TICKET_CODE} ]; then
            echo "::error title=Naming convention error::Could not extract JIRA ticket code from PR source branch '${GITHUB_HEAD_REF}'"
            exit 1
        fi

        CONCURRENCY_CODE=${JIRA_TICKET_CODE}
        CLUSTER=test
    else
        ####### Only for manual deployment #######
        # CONCURRENCY_CODE=${{ env.IMAGE_STATIC_TAG }}
        CONCURRENCY_CODE=${IMAGE_STATIC_TAG}
        CLUSTER=test
        ##########################################
    fi
fi

echo "::notice title=Cluster::Cluster output value is '${CLUSTER}'"
echo "::notice title=Concurrency::Concurrency code output value is '${CONCURRENCY_CODE}'"

if [ -z ${CLUSTER} ] || [ -z ${CONCURRENCY_CODE} ]; then
    echo "::error title=Something went wrong::Could not define one or more vars with event '${GITHUB_EVENT_NAME}', ref_type '${GITHUB_REF_TYPE}', ref_name '${GITHUB_REF_NAME}'"
    exit 1
fi

echo "::set-output name=CLUSTER::${CLUSTER}"
echo "::set-output name=CONCURRENCY_CODE::${CONCURRENCY_CODE}"
