#!/bin/bash

################################################################################
############# Push Local Branches individually @admiralawkbar ##################
################################################################################

# Legend:
# This script should be run from inside the local repository
# It will get a list of all local branches, checkout the individual branch,
# and push it to the remote.

########
# VARS #
########
MAIN_BRANCH="master" # Default branch main or master usually
BRANCH_LIST=()       # List of all branches found in repository locally
BRANCH_COUNT=0       # Count of branches pushed to remote
TOTAL_BRANCHES=0     # Total count of branches found
COUNTER=0            # Current branch were pushing
ERROR_COUNT=0        # Count of all failed pushes

##########
# Header #
##########
echo ""
echo "-----------------------------------------"
echo "Push Local Branches individually to remote"
echo "-----------------------------------------"
echo ""
echo "-----------------------------------------"
echo "Main branch set to:[${MAIN_BRANCH}]"
echo "-----------------------------------------"
echo ""

####################################################
# Check to see we are on the main or master branch #
####################################################
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
if [ "${BRANCH_NAME}" != "${MAIN_BRANCH}" ]; then
  # Error
  echo "ERROR! You need to currently have checked out the branch:[$MAIN_BRANCH] to run the script!"
  exit 1
fi

#######################################
# Populate the list with all branches #
#######################################
mapfile -t BRANCH_LIST < <(git for-each-ref --format='%(refname:short)' refs/heads/)

###############################
# Get total count of branches #
###############################
TOTAL_BRANCHES="${#BRANCH_LIST[@]}"

############################################################
# Go through all branches found locally and push to remote #
############################################################
for BRANCH in "${BRANCH_LIST[@]}";
do
  # Increment the counter
  ((COUNTER++))
  echo "-----------------------------------------"
  echo "Branch [${COUNTER}] of [${TOTAL_BRANCHES}]"
  echo "Checking out git Branch:[${BRANCH}]"
  git checkout "${BRANCH}"
  echo "Pushing git branch to remote..."
  if ! git push --force --set-upstream origin "${BRANCH}";
  then
    # Increment error count
    ((ERROR_COUNT++))
  fi
  echo "ERROR_CODE:[$?]"
  # Increment branch count
  ((BRANCH_COUNT++))
done

##########
# Footer #
##########
echo "-----------------------------------------"
echo "Pushed:[${BRANCH_COUNT}] of [${TOTAL_BRANCHES}] branches to remote"
echo "ERROR_COUNT:[${ERROR_COUNT}]"
echo "-----------------------------------------"
exit 0
