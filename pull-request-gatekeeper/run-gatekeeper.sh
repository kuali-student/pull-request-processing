#!/usr/bin/env bash
#
#
# Expects two environment variables to exist
#
# GITHUB_AUTH_USERNAME
# GITHUB_AUTH_PASSWORD

# make sure all environment variables are set
set -o nounset
# exit immediately if a pipeline returns a non-zero status
set -o errexit

if test -z "$GITHUB_AUTH_USERNAME"
then
	echo "GITHUB_AUTH_USERNAME field not set."
	exit 1
fi

if test -z "$GITHUB_AUTH_PASSWORD"
then
	echo "GITHUB_AUTH_PASSWORD field not set."
	exit 1
fi


set +e

mvn process-resources -DlistOpenPullRequests.phase=process-resources

set -e

ls -l target/ks-development-open-pull-requests.*

# After this script add a conditional step (multiple) that will load each of the 
# generated files and use that to bootstrap the downstream build pull request job.



