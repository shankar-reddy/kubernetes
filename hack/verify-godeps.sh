#!/bin/bash

# Copyright 2015 The Kubernetes Authors All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail

# As of go 1.6, the vendor experiment is enabled by default.
export GO15VENDOREXPERIMENT=1

#### HACK ####
# Sometimes godep just can't handle things. This lets use manually put
# some deps in place first, so godep won't fall over.
preload-dep() {
  org="$1"
  project="$2"
  sha="$3"

  org_dir="${GOPATH}/src/${org}"
  mkdir -p "${org_dir}"
  pushd "${org_dir}" > /dev/null
    git clone "https://${org}/${project}.git" > /dev/null 2>&1
    pushd "${org_dir}/${project}" > /dev/null
      git checkout "${sha}" > /dev/null 2>&1
    popd > /dev/null
  popd > /dev/null
}

KUBE_ROOT=$(dirname "${BASH_SOURCE}")/..
source "${KUBE_ROOT}/hack/lib/init.sh"

readonly branch=${1:-${KUBE_VERIFY_GIT_BRANCH:-master}}
if ! [[ ${KUBE_FORCE_VERIFY_CHECKS:-} =~ ^[yY]$ ]] && \
  ! kube::util::has_changes_against_upstream_branch "${branch}" 'Godeps/'; then
  exit 0
fi

# Create a nice clean place to put our new godeps
_tmpdir="$(mktemp -d -t gopath.XXXXXX)"
function cleanup {
  echo "Removing ${_tmpdir}"
  rm -rf "${_tmpdir}"
}
trap cleanup EXIT

# Copy the contents of the kube directory into the nice clean place
_kubetmp="${_tmpdir}/src/k8s.io"
mkdir -p "${_kubetmp}"
# should create ${_kubectmp}/kubernetes
git archive --format=tar --prefix=kubernetes/ $(git write-tree) | (cd "${_kubetmp}" && tar xf -)
_kubetmp="${_kubetmp}/kubernetes"

# Do all our work in the new GOPATH
export GOPATH="${_tmpdir}"
cd "${_kubetmp}"

# Build the godep tool
go get -u github.com/tools/godep 2>/dev/null
GODEP="${GOPATH}/bin/godep"
pushd "${GOPATH}/src/github.com/tools/godep" > /dev/null
  git checkout v53
  "${GODEP}" go install
popd > /dev/null

# Fill out that nice clean place with the kube godeps
echo "Starting to download all kubernetes godeps. This takes a while"
"${GODEP}" restore
echo "Download finished"

# Destroy deps in the copy of the kube tree
rm -rf ./Godeps ./vendor

# For some reason the kube tree needs to be a git repo for the godep tool to
# run. Doesn't make sense.
git init > /dev/null 2>&1

# Recreate the Godeps using the nice clean set we just downloaded
"${GODEP}" save ./...

# Test for diffs
if ! _out="$(diff -Naupr --ignore-matching-lines='^\s*\"GoVersion\":' --ignore-matching-lines='^\s*\"Comment\":' ${KUBE_ROOT}/Godeps/Godeps.json ${_kubetmp}/Godeps/Godeps.json)"; then
  echo "Your Godeps.json is different:"
  echo "${_out}"
  exit 1
fi

# ex: ts=2 sw=2 et filetype=sh
