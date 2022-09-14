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

# # Successful case workflow_dispatch
# GITHUB_REF_TYPE=branch
# GITHUB_EVENT_NAME=workflow_dispatch
# IMAGE_STATIC_TAG=latest
# CLUSTER=release

# # Successful case latest
# GITHUB_REF_TYPE=branch
# GITHUB_EVENT_NAME=pull_request
# GITHUB_REF=refs/pull/1234/merge
# GITHUB_HEAD_REF=feature/TOTO-4567_blablabla
# GITHUB_REF_NAME=feature/TOTO-4567_blablabla
# IMAGE_STATIC_TAG=latest

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

CREATE_TAG_LATEST="false"

# Manual case uses image static tag (such as "latest")
if  [ ${GITHUB_EVENT_NAME} == "workflow_dispatch" ]; then
    IMAGE_TAG=${IMAGE_STATIC_TAG}
elif  [ ${GITHUB_REF_TYPE} == "tag" ] && [ ${GITHUB_EVENT_NAME} == "release" ]; then
    # Tag git
    IMAGE_TAG=${GITHUB_REF_NAME}

    if [[ $(echo ${GITHUB_REF_NAME} | grep -P '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$') ]]; then
        # SemVer with suffix (1.0.0-alpha.1)
        CLUSTER=release
    elif [[ $(echo ${GITHUB_REF_NAME} | grep -P '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') ]]; then
        # SemVer without suffix (1.0.0)
        CLUSTER=prod
        CREATE_TAG_LATEST="true"
    else
        echo "::error title=Define vars::Tag format error: your git tag does not respect Semantic Versioning, see https://regex101.com/r/vkijKf/1/"
        echo "::debug::Could not define cluster with ref_type '${GITHUB_REF_TYPE}' and ref_name '${GITHUB_REF_NAME}'"
        exit 1
    fi
elif [ ${GITHUB_REF_TYPE} == "branch" ] && [ ${GITHUB_EVENT_NAME} == "pull_request" ]; then
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
        echo "::error title=Define vars::Naming convention error: could not extract JIRA ticket code from PR source branch ref '${GITHUB_HEAD_REF}'"
        exit 1
    fi

    IMAGE_TAG=${JIRA_TICKET_CODE}
    CLUSTER=test
else
    echo "::error title=Define vars::Not implemented case with event '${GITHUB_EVENT_NAME}' and ref_type '${GITHUB_REF_TYPE}'"
    exit 1
fi

echo "::notice title=Define vars::Cluster output value is '${CLUSTER}'"
echo "::notice title=Define vars::Image tag output value is '${IMAGE_TAG}'"
echo "::notice title=Define vars::Create tag latest is '${CREATE_TAG_LATEST}'"

if [ -z ${CLUSTER} ] || [ -z ${IMAGE_TAG} ]; then
    echo "::error title=Define vars::Could not define one or more required vars with event '${GITHUB_EVENT_NAME}', ref_type '${GITHUB_REF_TYPE}', ref_name '${GITHUB_REF_NAME}'"
    exit 1
fi

echo "::set-output name=CLUSTER::${CLUSTER}"
echo "::set-output name=IMAGE_TAG::${IMAGE_TAG}"
echo "::set-output name=CREATE_TAG_LATEST::${CREATE_TAG_LATEST}"
