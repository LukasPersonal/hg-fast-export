#!/bin/bash

################################################################################
########################## chunked-push.sh #####################################
################################################################################

# LEGEND:
# Repositories larger than 2GB cannot be pushed to github.com
#
# This script attempts to push one branch from such a repository in
# chunks smaller than 2GB. Make sure to use SSH as push protocol as
# HTTPS frequently runs into trouble with these large pushes.
#
# Run this script within the repository and pass the name of the
# remote as first argument.
#
# The script creates some temporary local and remote references with names like
#
#     refs/github-sevices/chunked-upload/*
#
# If it completes successfully, it will clean up those references.
#
# Example: chunked-push.sh origin
#
########################
# Set to exit on error #
########################
set -e

# DRY_RUN can be set (either by uncommenting the following line or by
# setting it via the environment) to test this script without doing
# any any actual pushes.
# DRY_RUN=1

# MAX_PUSH_SIZE is the maximum estimated size of a push that will be
# attempted. Note that this is only an estimate, so it should probably
# be set smaller than any hard limits. However, even if it is too big,
# the script should succeed (though that makes it more likely that
# pushes will fail and have to be retried).

########
# VARS #
########
# Default max push size is 2GB
MAX_PUSH_SIZE="${MAX_PUSH_SIZE:-2000000000}"
# Remote to push towards, default origin
REMOTE="${1:-origin}"
# Prefix for temorary refs created
REF_PREFIX='refs/github-services/chunked-upload'
# Tip commit of the current branch that we want to push to GitHub
HEAD="$(git rev-parse --verify HEAD)"
# Name of the current branch that we want to push to GitHub
BRANCH="$(git symbolic-ref --short HEAD)"
# Options to push
PUSH_OPTS="--no-follow-tags"

################################################################################
########################## FUNCTIONS BELOW #####################################
################################################################################
################################################################################
#### Function Header ###########################################################
Header() {
  echo ""
  echo "-------------------------------"
  echo "-- Push repository in chunks --"
  echo "-------------------------------"
  echo ""
  echo "Gathering information from local repository..."
}
################################################################################
#### Function Git_Push #########################################################
Git_Push() {
  if test -n "${DRY_RUN}"; then
    # Just show what push command would be run, without actually
    # running it:
    echo git push "$@"
  else
    git push "$@"
  fi
}
################################################################################
#### Function Estimate_Size ####################################################
Estimate_Size() {
  # usage: Estimate_Size [REV]
  #
  # Return the estimated total on-disk size of all unpushed objects that
  # are reachable from REV (or ${HEAD}, if REV is not specified).
  local REV=''
  REV="${1:-$HEAD}"

  git for-each-ref --format='^%(objectname)' "${REF_PREFIX}" |
    git rev-list --objects "${REV}" --stdin |
    awk '{print $1}' |
    git cat-file --batch-check='%(objectsize:disk)' |
    awk 'BEGIN {sum = 0} {sum += $1} END {print sum}'
}
################################################################################
#### Function Check_Size #######################################################
Check_Size() {
  # usage: Check_Size [REV]
  #
  # Check whether a push of REV (or ${HEAD}, if REV is not specified) is
  # estimated to be within $MAX_PUSH_SIZE.
  local REV=''
  REV="${1:-$HEAD}"
  local SIZE=''
  SIZE="$(Estimate_Size "${REV}")"

  if test "${SIZE}" -gt "${MAX_PUSH_SIZE}"; then
    echo >&2 "size of push is predicted to be too large: ${SIZE} bytes"
    return 1
  else
    echo >&2 "predicted push size: ${SIZE} bytes"
  fi
}
################################################################################
#### Function Push_Branch ######################################################
Push_Branch() {
  # usage: Push_Branch
  #
  # Check whether a push of ${BRANCH} to ${REMOTE} is likely to be within
  # $MAX_PUSH_SIZE. If so, try to push it. If not, emit an informational
  # message and return an error.
  Check_Size &&
  Git_Push ${PUSH_OPTS} --force "${REMOTE}" "${HEAD}:refs/heads/${BRANCH}"
}
################################################################################
#### Function Push_Rev #########################################################
Push_Rev() {
  # usage: Push_Branch REV
  #
  # Check whether a push of REV to ${REMOTE} is likely to be within
  # $MAX_PUSH_SIZE. If so, try to push it to a temporary reference. If
  # not, emit an informational message and return an error.
  local REV="$1"

  Check_Size "${REV}" &&
  Git_Push ${PUSH_OPTS} --force "${REMOTE}" "${REV}:${REF_PREFIX}/${REV}"
}
################################################################################
#### Function Push_Chunk #######################################################
Push_Chunk() {
  # usage: Push_Chunk
  #
  # Try to push a portion of the contents of ${HEAD}, such that the amount
  # to be pushed is estimated to be less than $MAX_PUSH_SIZE. This is
  # done using the same algorithm as 'git bisect'; namely, by
  # successively halving of the number of commits until the size of the
  # commits to be pushed is less than $MAX_PUSH_SIZE. For simplicity and
  # to avoid extra estimation work, instead of trying to find the
  # optimum number of commits to push, we stop as soon as we find a
  # range that meets the criterion. This will typically result in a push
  # with a size approximately in the range
  #
  #     $MAX_PUSH_SIZE / 2 <= size <= $MAX_PUSH_SIZE
  CHUNK_SIZE="${HEAD}"
  LAST_REV=''

  while true; do
    # find a new midpoint, this call sets ${bisect_rev} and $bisect_steps
    # Note: $bisect_rev and $bisect_steps are ENV vars and need to be lower case
    eval "$(
      git for-each-ref --format='^%(objectname)' "${REF_PREFIX}" |
        git rev-list --bisect-vars "${CHUNK_SIZE}" --stdin
    )"

    # Check to see if we have hit the bottom and cant get smaller
    if [ "${bisect_rev}" == "${LAST_REV}" ] && [ -n "${bisect_rev}" ] && [ -n "${LAST_REV}" ]; then
      # ERROR
      echo >&2 "We have hit the smallest commit:[${bisect_rev}] and its larger than allowed upload size!"
      exit 1
    fi

    # Try to push the bisect rev
    echo >&2 "attempting to push:[${bisect_rev}]..."
    if Push_Rev "${bisect_rev}"; then
      # Success
      echo >&2 "push succeeded!"
      git update-ref "${REF_PREFIX}/${bisect_rev}" "${bisect_rev}"
      return
    else
      # Failure
      echo >&2 "push failed; trying a smaller chunk"
      # Set the local vars
      CHUNK_SIZE="${bisect_rev}"
      LAST_REV="${bisect_rev}"
    fi
  done
}
################################################################################
############################### MAIN ###########################################
################################################################################

##########
# Header #
##########
Header

############################
# Start to push the chunks #
############################
while ! Push_Branch ; do
  echo >&2 "trying a partial push"
  Push_Chunk
done

###########################################
# Clean up the local temporary references #
###########################################
git for-each-ref --format='delete %(refname)' "${REF_PREFIX}" |
  git update-ref --stdin

############################################
# Clean up the remote temporary references #
############################################
Git_Push ${PUSH_OPTS} --prune "${REMOTE}" "${REF_PREFIX}/*:${REF_PREFIX}/*"
