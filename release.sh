#!/bin/bash

set -eo pipefail

main() {
  local image_dir=/usr/src/image-2-build
  local build_dir=/usr/src/docker-builder
  local tag="${DOCKER_IMAGE##*:}"

  cd $image_dir

  cp docker-compose/production.yml $build_dir/release/production.yml

  cd $build_dir

  if [[ ! $APPLICATION_PORT ]]; then
    APPLICATION_PORT=3000
  fi

  if [[ ! $CD_CONFIG_NAME ]]; then
    CD_CONFIG_NAME="CodeDeployDefault.OneAtATime"
  fi

  cat <<EOF >./release/config.json
{
  "release_bucket": "$RELEASES_BUCKET",
  "port": "$APPLICATION_PORT",
  "docker": {
    "registry": "$DOCKER_REGISTRY",
    "image": "$DOCKER_IMAGE",
    "login_email": "$DOCKER_LOGIN_EMAIL",
    "login_username": "$DOCKER_LOGIN_USERNAME",
    "login_password": "$DOCKER_LOGIN_PASSWORD"
  }
}
EOF

  # Package release
  $(cd release && tar -cf ../release.tar ./)

  # Put release on S3
  echo "Pushing release to s3://${RELEASES_BUCKET}/release-${tag}.tar"
  echo "aws s3api put-object --bucket=\"${RELEASES_BUCKET}\" --key=\"release-${tag}.tar\" --body release.tar"

  if [[ $KMS_KEY_ID ]]; then
    aws s3api put-object \
      --bucket="${RELEASES_BUCKET}" \
      --key="release-${tag}.tar" \
      --server-side-encryption "aws:kms" \
      --ssekms-key-id "$KMS_KEY_ID" \
      --body=release.tar
  else
    aws s3api put-object \
      --bucket="$RELEASES_BUCKET" \
      --key="release-${tag}.tar" \
      --body=release.tar
  fi

  # Register revision with code deploy
  local revision=$(cat <<EOF
{
  "revisionType": "S3",
  "s3Location": {
    "bucket": "$RELEASES_BUCKET",
    "key": "release-${tag}.tar",
    "bundleType": "tar"
  }
}
EOF
)

  local deployment=$(aws deploy create-deployment \
    --application-name="${CD_APPLICATION_NAME}" \
    --deployment-group-name="${CD_DEPLOYMENT_GROUP_NAME}" \
    --deployment-config-name="${CD_CONFIG_NAME}" \
    --description="release: ${tag}" \
    --revision="${revision}")

  local deployment_id="$(echo "$deployment" | jq -r '.deploymentId')"

  if [[ ! $deployment_id ]]; then
    echo "Failed to create deployment" >&2
    exit 1
  fi

  echo "Deployment Created"

  while [[ true ]]; do
    local deployment_info="$(aws deploy get-deployment --deployment-id="${deployment_id}")"
    local deployment_status="$(echo "${deployment_info}" | jq -r '.deploymentInfo.status')"

    echo "Deployment Status: ${deployment_status}"

    if [[ "$deployment_status" == "Failed" || "$deployment_status" ==  "Stopped" ]]; then
      local errorInformation="$(echo "${deployment_info}" | jq -r '.deploymentInfo.errorInformation')"
      local errorCode="$(echo "${errorInformation}" | jq -r '.code')"
      local errorMsg="$(echo "${errorInformation}" | jq -r '.message')"
      echo "Error Code: ${errorCode}, Error Message: ${errorMsg}"
      exit 1
    fi

    if [[ "$deployment_status" == "Succeeded" ]]; then
      break
    fi

    sleep 1
  done
}

main "$@"
