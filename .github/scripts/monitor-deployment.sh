#!/bin/bash

# exit when any command fails
set -e

# Notes:
# A successful deployment is completed after about 5min
# A failed deployment is roll out by this script after about 10 min
# A failed deployment is roll out automatically by deployment_circuit_breaker after at least 30min (10 tasks must fail)

# See https://docs.amazonaws.cn/en_us/AmazonECS/latest/developerguide/deployment-type-ecs.html
# See https://aws.amazon.com/blogs/containers/announcing-amazon-ecs-deployment-circuit-breaker/

# For testing
# CLUSTER=test
# SERVICE=orpheo

echo "------------------- MONITOR DEPLOYMENT -------------------------"

CLUSTER=${1:?CLUSTER is required}
SERVICE=${2:?SERVICE is required}

SERVICE_DEPLOYMENT_ROLLBACK=0
SERVICE_DEPLOYMENT_ERROR=0
MAX_FAILED_TASKS_COUNT=2
DESCRIBE_SERVICE=$(aws ecs describe-services --cluster ${CLUSTER} --services ${SERVICE})
SERVICE_DEPLOYMENT_IN_PROGRESS=$(echo "${DESCRIBE_SERVICE}" | jq ".services[].deployments[] \
    | select(.status == \"PRIMARY\") | select(.rolloutState == \"IN_PROGRESS\")")

while [ ! -z "${SERVICE_DEPLOYMENT_IN_PROGRESS}" ]; do
    # echo "------------------- LOOP -------------------------"

    DESCRIBE_SERVICE=$(aws ecs describe-services --cluster ${CLUSTER} --services ${SERVICE})
    SERVICE_DEPLOYMENT_IN_PROGRESS=$(echo "${DESCRIBE_SERVICE}" | jq ".services[].deployments[] \
        | select(.status == \"PRIMARY\") | select(.rolloutState == \"IN_PROGRESS\")")
    FAILED_TASKS_COUNT=$(echo "${SERVICE_DEPLOYMENT_IN_PROGRESS}" | jq ".failedTasks")
    ROLLOUT_STATE_REASON=$(echo "${SERVICE_DEPLOYMENT_IN_PROGRESS}" | jq --raw-output ".rolloutStateReason")

    if [ -z "${INITIAL_ROLLOUT_STATE_REASON}" ]; then
        INITIAL_ROLLOUT_STATE_REASON=${ROLLOUT_STATE_REASON}
        echo "::notice title=Monitor deployment::${SERVICE}: ${INITIAL_ROLLOUT_STATE_REASON}"
    fi

    # echo "::debug title=Monitor deployment::FAILED_TASKS_COUNT=${FAILED_TASKS_COUNT}"

    if [ ! -z ${FAILED_TASKS_COUNT} ] && [ ${FAILED_TASKS_COUNT} -gt 0 ]; then
        echo "::error title=Monitor deployment::${SERVICE}: Houston we have a problem! ${FAILED_TASKS_COUNT} task(s) failed to start! Max fails is set to ${MAX_FAILED_TASKS_COUNT}!"

        # When reaching max fails => roll back to previous working version
        if [ ${FAILED_TASKS_COUNT} -ge ${MAX_FAILED_TASKS_COUNT} ] && [ ${SERVICE_DEPLOYMENT_ROLLBACK} == 0 ]; then
            # Get a previous working task definition (which is inactive now)
            # And create a new revision from the previous working one
            SERVICE_DEPLOYMENT_ROLLBACK=1
            WORKING_SERVICE_TASK_ARN=$(echo "${DESCRIBE_SERVICE}" | jq --raw-output ".services[].deployments[] \
                | select(.status == \"ACTIVE\") | select(.rolloutState == \"COMPLETED\") | .taskDefinition")

            if [ ! -z "${WORKING_SERVICE_TASK_ARN}" ]; then
                echo "::warning title=Monitor deployment::${SERVICE}: Roll back service with a previous working task definition"

                PREVIOUS_WORKING_TASK_DEFINITION=$(aws ecs describe-task-definition --task-definition ${WORKING_SERVICE_TASK_ARN})
                NEW_TASK_DEFINITION=$(echo "${PREVIOUS_WORKING_TASK_DEFINITION}" | jq ".taskDefinition \
                    | del(.taskDefinitionArn) \
                    | del(.revision) \
                    | del(.status) \
                    | del(.requiresAttributes) \
                    | del(.compatibilities) \
                    | del(.registeredAt) \
                    | del(.registeredBy) \
                    | del(.deregisteredAt)")
                REGISTER_NEW_TASK_DEFINITION=$(aws ecs register-task-definition --cli-input-json "${NEW_TASK_DEFINITION}")
                NEW_TASK_DEFINITION_ARN=$(echo "${REGISTER_NEW_TASK_DEFINITION}" | jq --raw-output ".taskDefinition.taskDefinitionArn")
                SERVICE_ROLLBACK=$(aws ecs update-service --cluster ${CLUSTER} --service ${SERVICE} \
                    --task-definition ${NEW_TASK_DEFINITION_ARN})
            else
                SERVICE_DEPLOYMENT_ERROR=1
                echo "::error title=Monitor deployment::${SERVICE}: Could not find a previous working task definition to roll back onto! This is bad, better call your DevOps!"

                break
            fi
        fi
    elif [[ $(echo "${ROLLOUT_STATE_REASON}" | grep "rolling back") ]]; then
        SERVICE_DEPLOYMENT_ROLLBACK=1
        echo "::warning title=Monitor deployment::${SERVICE}: ${ROLLOUT_STATE_REASON}"
    elif [ "${INITIAL_ROLLOUT_STATE_REASON}" != "${ROLLOUT_STATE_REASON}" ]; then
        INITIAL_ROLLOUT_STATE_REASON=""
    fi

    sleep 10
done

SERVICE_DEPLOYMENT_COMPLETED=$(echo "${DESCRIBE_SERVICE}" | jq ".services[].deployments[] \
    | select(.status == \"PRIMARY\") | select(.rolloutState == \"COMPLETED\")")

if [ ! -z "${SERVICE_DEPLOYMENT_COMPLETED}" ]; then
    echo "------------------- DEPLOYMENT COMPLETED -------------------------"

    if [ ${SERVICE_DEPLOYMENT_ROLLBACK} == 1 ]; then
        echo "::warning title=Monitor deployment::${SERVICE}: Service was roll backed!"
    else
        echo "::notice title=Monitor deployment::${SERVICE}: Deployment completed"
    fi
else
    # detecter le rollback :
    #  * status=PRIMARY rolloutState=IN_PROGRESS rolloutStateReason="*rolling back to*"
    #  * status=ACTIVE rolloutState=FAILED rolloutStateReason="*task failed to start*"
    # extra: chercher dans les events la cause si rolloutStateReason insuffisant: "failed container health checks"

    SERVICE_DEPLOYMENT_FAILED=$(echo "${DESCRIBE_SERVICE}" | jq ".services[].deployments[] \
        | select(.status == \"ACTIVE\") | select(.rolloutState == \"FAILED\")")

    if [ ! -z "${SERVICE_DEPLOYMENT_FAILED}" ]; then
        echo "------------------- DEPLOYMENT FAILED -------------------------"

        ROLLOUT_STATE_REASON=$(echo "${SERVICE_DEPLOYMENT_FAILED}" | jq --raw-output ".rolloutStateReason")
        echo "::error title=Monitor deployment::${SERVICE}: Deployment failed, rolloutStateReason: ${ROLLOUT_STATE_REASON}"
    fi
fi

# Github statuses are: error, failure, inactive, in_progress, queued, pending, success
if [ ${SERVICE_DEPLOYMENT_ERROR} == 1 ]; then
    DEPLOY_STATUS=error
elif [ ${SERVICE_DEPLOYMENT_ROLLBACK} == 1 ]; then
    DEPLOY_STATUS=failure
else
    DEPLOY_STATUS=success
fi

echo "::notice title=Monitor deployment::${SERVICE}: Deploy status is ${DEPLOY_STATUS}"
echo "DEPLOY_STATUS=${DEPLOY_STATUS}" >> ${GITHUB_OUTPUT}
