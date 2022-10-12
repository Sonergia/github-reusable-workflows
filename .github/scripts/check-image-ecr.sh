#!/bin/bash

# exit when any command fails
set -e

# echo "-------------- DEBUG SCRIPT --------------"
# # Successful case tag prod
# GITHUB_REF_TYPE=tag
# GITHUB_EVENT_NAME=release
# GITHUB_REF_NAME=notlatest

SERVICE_NAMESPACE=${1:?SERVICE_NAMESPACE is required}
IMAGE_NAMES_LIST=${2:?IMAGE_NAMES_LIST is required}
IMAGE_SHA=${3:?IMAGE_SHA is required}
IMAGE_EXISTS="false"

for IMAGE_NAME in ${IMAGE_NAMES_LIST}; do
  IMAGES_LIST=$(aws ecr list-images \
    --repository-name ${SERVICE_NAMESPACE}/${IMAGE_NAME} \
    --filter tagStatus=TAGGED)
  IMAGE_SHA_EXISTS=$(echo "${IMAGES_LIST}" \
    | jq -c ".imageIds[] | select(.imageTag == \"${IMAGE_SHA}\")")

  if [ ! -z "${IMAGE_SHA_EXISTS}" ]; then
    IMAGE_EXISTS="true"
    echo "::notice title=Check docker image::Image tag SHA '${IMAGE_SHA}' already exists in ${SERVICE_NAMESPACE}/${IMAGE_NAME}"

    # Check Git release tag
    if  [ "${GITHUB_REF_TYPE}" == "tag" ] && [ "${GITHUB_EVENT_NAME}" == "release" ]; then
      IMAGE_TAG=${GITHUB_REF_NAME}
      IMAGE_TAG_EXISTS=$(echo "${IMAGES_LIST}" \
        | jq -c ".imageIds[] | select(.imageTag == \"${IMAGE_TAG}\")")

      if [ ! -z "${IMAGE_TAG_EXISTS}" ]; then
        echo "::notice title=Check docker image::Image tag release '${IMAGE_TAG}' already exists in ${SERVICE_NAMESPACE}/${IMAGE_NAME}"
      else
        # Add missing tag to ECR
        MANIFEST=$(aws ecr batch-get-image \
          --repository-name ${SERVICE_NAMESPACE}/${IMAGE_NAME} \
          --image-ids imageTag=${IMAGE_SHA} --output json \
          | jq --raw-output --join-output '.images[0].imageManifest')

        PUT_IMAGE=$(aws ecr put-image \
          --repository-name ${SERVICE_NAMESPACE}/${IMAGE_NAME} \
          --image-tag "${IMAGE_TAG}" --image-manifest "${MANIFEST}")

        echo "::notice title=Check docker image::Image tag release '${IMAGE_TAG}' has been added to ${SERVICE_NAMESPACE}/${IMAGE_NAME} '${IMAGE_SHA}' image"
      fi
    fi
  else
    echo "::notice title=Check docker image::Image tag SHA '${IMAGE_SHA}' does not exists in ${SERVICE_NAMESPACE}/${IMAGE_NAME}"
  fi
done

echo "IMAGE_EXISTS=${IMAGE_EXISTS}" >> ${GITHUB_OUTPUT}
