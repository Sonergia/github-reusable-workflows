#!/bin/bash

set -o errexit
set -o nounset

# arguments
CLUSTER=${1:?CLUSTER is required}
SERVICE=${2:?SERVICE is required}
CONTAINER=${3:?CONTAINER is required}
COMMAND=${4:?COMMAND is required}

# Requirements
if [[ ! $(which aws) ]]; then
    echo "::error title=ecs-exec-cmd::AWS CLI package is not installed!"
    exit 1
fi

if [[ ! $(which jq) ]]; then
    echo "::error title=ecs-exec-cmd::jq package is not installed!"
    exit 1
fi

if [[ ! $(which unbuffer) ]]; then
    echo "::error title=ecs-exec-cmd::Unbuffer package is not installed!"
    exit 1
fi

# Validate cluster
CLUSTERS_LIST=($(aws ecs list-clusters --no-paginate \
    | jq --raw-output '.clusterArns[]' | awk -F / '{ print $2 }'))

if [[ ! " ${CLUSTERS_LIST[*]} " =~ " ${CLUSTER} " ]]; then
    echo "::error title=ecs-exec-cmd::Cluster ${CLUSTER} does not exists!"
    exit 1
fi

echo "::debug title=ecs-exec-cmd::Cluster '${CLUSTER}' found"

# Validate service
SERVICES_LIST=($(aws ecs list-services --cluster ${CLUSTER} --page-size 100 \
    | jq --raw-output '.serviceArns[]' | awk -F / '{ print $3 }' | sort))

if [[ ! " ${SERVICES_LIST[*]} " =~ " ${SERVICE} " ]]; then
    echo "::error title=ecs-exec-cmd::Service ${SERVICE} does not exists on cluster ${CLUSTER}!"
    exit 1
fi

echo "::debug title=ecs-exec-cmd::Service ${SERVICE} found"

TASK_ARN=($(aws ecs list-tasks --cluster ${CLUSTER} --service-name ${SERVICE} \
    | jq --raw-output  '.taskArns | .[length-1]'))

echo "::debug title=ecs-exec-cmd::Task ARN ${TASK_ARN} found"

if [ -z ${TASK_ARN} ]; then
    echo "::error title=ecs-exec-cmd::There are no running tasks for service ${SERVICE} on cluster ${CLUSTER}!"
    exit 1
fi

TASK_ID=$(echo ${TASK_ARN} | awk -F / '{ print $3 }')

echo "::debug title=ecs-exec-cmd::Task ID ${TASK_ID} found"

CONTAINERS_LIST=$(aws ecs describe-tasks --cluster ${CLUSTER} --tasks ${TASK_ARN} \
    | jq --raw-output  '.tasks[].containers[] | select(.lastStatus | contains("RUNNING")) | .name')

if [[ ! " ${CONTAINERS_LIST[*]} " =~ " ${CONTAINER} " ]]; then
    echo "::error title=ecs-exec-cmd::There is no running container ${CONTAINER} in service ${SERVICE} on cluster ${CLUSTER}!"
    exit 1
fi

echo "::debug title=ecs-exec-cmd::Container ${CONTAINER} found"
echo "::notice title=ecs-exec-cmd::Trying to connect to container ${CONTAINER} on cluster ${CLUSTER}"

# Issues with SSM agent
# https://github.com/aws/amazon-ssm-agent/issues/361

# unbuffer disables the output buffering that occurs when program output is redirected from non-interactive programs
# See https://github.com/aws/amazon-ssm-agent/issues/354

# Append "echo execute-command-success" to command to know if it fails (hacki workaround)
# See: https://github.com/aws/amazon-ecs-agent/issues/2846
OUTPUT=$(unbuffer aws ecs execute-command \
    --cluster ${CLUSTER} \
    --task ${TASK_ID} \
    --container ${CONTAINER} \
    --interactive \
    --command "/bin/sh -c '${COMMAND} && echo execute-command-success'")

# Echo command output
echo "${OUTPUT}"

# Try to grep success confirmation
echo "${OUTPUT}" | grep execute-command-success

# Failover on SSM method
# DESCRIBE_TASKS=$(aws ecs describe-tasks --cluster ${CLUSTER} --tasks ${TASK_ARN})
# CONTAINER_RUNTIME_ID=$(echo ${DESCRIBE_TASKS} | jq --raw-output '.tasks[].containers[] | select(.name == "'${CONTAINER}'") | .runtimeId')
# ECS_TARGET_CODE=${CLUSTER}_${TASK_ID}_${CONTAINER_RUNTIME_ID}
# aws ssm start-session --target ecs:${ECS_TARGET_CODE}
