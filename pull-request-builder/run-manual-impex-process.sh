#!/usr/bin/env bash
#
# run-manual-impex-process.sh
#
# Determine if we should be running the manual impex process.
#
# If we need to it will run the manual impex process and push the branch
#
# into the upstream.
#
# Expected Jenkins Build Parameter Names:
# PULL_REQUEST_NUMBER
# PULL_REQUEST_COMMIT_ID
#

# Assumes we are run after run-prepare-ks-impex-repo.sh
#
# that the target/ks-impex-repo exists and is on the pull request branch
# that the target/ks-repo exists and is on the pull request branch

# for example set this to -Doracle.dba.password=<password>
DEBUG_DB_OPTS=

KS_REPO=target/ks-repo
KS_IMPEX_REPO=target/ks-impex-repo

PR_BRANCH="pull-request-${PULL_REQUEST_NUMBER}"

echo "Run manual impex process"

if test ! -d $KS_REPO
then
	echo "$KS_REPO does not exist"
	exit 1
fi

if test ! -d $KS_IMPEX_REPO
then
	echo "$KS_IMPEX_REPO does not exist"
	exit 1
fi

# We want to use the 'identifyChangesInGit' mojo to see if we need to run anything.
# that mojo will work against the target/ks-repo on the pull-request branch
# and identify the most recent commit from the tip that has sql changes.

# run local manual impex process

# this loads in all of the -sql module artifacts
mvn initialize -Plocal,source-db $DEBUG_DB_OPTS -N -e

# this creates the .mpx and .xml files from the source database 
mvn generate-resources -Pdump,local $DEBUG_DB_OPTS -N -e

# this moves the created .mpx and .xml files back under the src/main/resources directory.
mvn process-resources -Pimpexscm -N

# we want to add all newly generated files
git add src/main/resources

git commit -a -m'Commit Impex Changes for pull-request-$PULL_REQUEST_NUMBER\n\nFor pull-request commit id: $KS_REPO_PR_BRANCH_HEAD_ID'

# move back up to the pull-request-builder directory
cd ../..

set +e
# update the ks-impex-repo $PR_BRANCH into github.
mvn validate -Dpush-db-changes.phase=validate  -Dpush-db-changes.pull-request-branch-name=$PR_BRANCH

# EOF
