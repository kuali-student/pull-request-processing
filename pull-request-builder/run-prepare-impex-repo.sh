#!/usr/bin/env bash
#
# run-setup-impex-repo.sh
#
# This will checkout the ks-impex repository and setup the pull-request versions 
# and create the local pull-request branch.
#
#
# This script will facilitate the setup.
#
# Expected Jenkins Build Parameter Names:
# PULL_REQUEST_NUMBER
# PULL_REQUEST_COMMIT_ID
#

# for example set this to -Doracle.dba.password=<password>
DEBUG_DB_OPTS=

REPO_BASE=https://github.com/kuali-student

KS_REPO=$REPO_BASE/ks-development
KS_IMPEX_REPO=$REPO_BASE/ks-development-impex

PR_BRANCH="pull-request-${PULL_REQUEST_NUMBER}"

set +e

mkdir -p target

cd target

# next checkout the ks-impex-repo
# consider restricting this to just the development branch and the pull request branch
# I wonder if we can use ls-remote to see if the pull-request branch exists.

echo "Make ks-impex-repo directory"
mkdir ks-impex-repo

echo "Initialize ks-impex-repo"
git init ks-impex-repo

cd ks-impex-repo

echo "Setup Origin Remote"


echo "[remote \"origin\"]" >> .git/config
echo "    url=$KS_IMPEX_REPO" >> .git/config

$(git ls-remote origin | grep $PR_BRANCH)
R=$?

if test 0 -eq "$R"
then 	
	# remote pull request branch exists
	echo "    fetch=refs/heads/$PR_BRANCH:refs/remotes/origin/$PR_BRANCH" >> ./.git/config
	
	git fetch origin --depth=1
	
else
	# no pull request branch on the remote
	echo "    fetch=refs/heads/development:refs/remotes/origin/development" >> ./.git/config
	
	git fetch origin --depth=1
	
	git checkout -b $PR_BRANCH origin/development
	
	echo "Setup the pom versions to $PR_BRANCH"
	
	# setup the pom versions.
	
	set +e
	mvn validate -Ppull-request -Dfusion.tag.phase=validate -Dfusion.tag.pull-request-number-property=PULL_REQUEST_NUMBER -Dfusion.tag.pull-request-number=$PULL_REQUEST_NUMBER -N -e
	
fi


