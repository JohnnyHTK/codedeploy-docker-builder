#!/bin/bash

set -eo pipefail

main() {
  local release_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
  local docker_compose_file="$release_dir/production.yml"

  docker-compose -f $docker_compose_file stop -t 20
  docker-compose -f $docker_compose_file rm
}

main "$@"
