#!/bin/bash

set -eo

main() {
  local release_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
  local config="$(cat ${release_dir}/config.json)"
  local docker_image="$(echo $config | jq -r '.docker.image')"
  local docker_registry="$(echo $config | jq -r '.docker.registry')"
  local docker_login_email="$(echo $config | jq -r '.docker.login_email')"
  local docker_login_username="$(echo $config | jq -r '.docker.login_username')"
  local docker_login_password="$(echo $config | jq -r '.docker.login_password')"
  local docker_compose_file="$release_dir/production.yml"

  # modify docker-compose production file with the image release
  sed -i -e "s/{{release}}/$(echo $docker_image | sed -e 's/[\/&]/\\&/g')/" $docker_compose_file

  docker login --email="${docker_login_email}" --username="${docker_login_username}" --password="${docker_login_password}" $docker_registry
  docker pull $docker_image

  # Ensure docker is already running
  service docker start || true
}

main "$@"
