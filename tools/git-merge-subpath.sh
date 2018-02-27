#!/bin/bash
# https://stackoverflow.com/a/30386041/9186433

APP_ARG_POSITIONAL=(DST_PREFIX SRC_PREFIX SRC_COMMIT)


# Common functions.

USAGE_ARG_POSITIONAL="${APP_ARG_POSITIONAL[@]}"

function usage() {
  # out. usage message.

  echo "Usage: $0 [--squash] ${USAGE_ARG_POSITIONAL}"
  echo
}

function help() {
  # out. help message with usage message as header.

  usage
  echo "Options:"
  echo
  echo "  --squash      Create single commit instead of merge commit"
  echo
  echo "Arguments:"
  echo
  echo "  DST_PREFIX    Destination path"
  echo "  SRC_PREFIX    Source path"
  echo "  SRC_COMMIT    Source commit SHA1"
  echo
}

function commit_msg_template_tag() {
  # DST_PREFIX: destination prefix.
  # SRC_PREFIX: source prefix.
  # out. built commit message header in single line as key for searching.

  echo "git-subpath-tag ${DST_PREFIX} -> ${SRC_PREFIX}"
}

function commit_msg_template() {
  # DST_PREFIX: destination prefix.
  # SRC_PREFIX: source prefix.
  # SRC_COMMIT: source commit SHA1.
  # out. built commit message from template with header.

  echo "Merge ${SRC_COMMIT}:${SRC_PREFIX} to ${DST_PREFIX}"
  echo

  commit_msg_template_tag
  echo " mainline: ${SRC_COMMIT}"
}

function commit_msg_extract_param() {
  # 1: parameter key to be extracted.
  # 2: regular expression of parameter value for extracting.
  # in. commit message body.
  # out. extracted parameter value.

  sed -E 's/\s*'"$1"': ('"$2"').*/\1/'
}

function verify_ref() {
  # 1: commit reference. (partial SHA1, branch name, tag, etc)
  # out. verified full SHA1 commit, ret. 1 if fail.

  git rev-parse --verify "$1^{commit}" || return 1
}

function get_toplevel() {
  # out. absolute path to current repo.

  git rev-parse --show-toplevel
}

function extract_previous_sha1() {
  # DST_PREFIX: destination prefix.
  # SRC_PREFIX: source prefix.
  # out. extracted prev. SHA1 commit, ret. 1 if fail.

  git log -1 --format='%b' -E --grep "$(commit_msg_template_tag)" \
    | commit_msg_extract_param "mainline" '[0-9a-f]{40}'
}


# Argument parsing.

ARG_IS_SQUASH=

while (( "$#" )); do
  case "$1" in
    --squash)
      ARG_IS_SQUASH=y
      shift
      ;;
    -*)
      # Unsupported flags.
      echo "$0: Unknown parameter '$1'" >&2
      usage >&2

      exit 1
      ;;
    *)
      # Positional parameters.
      arg=${APP_ARG_POSITIONAL[0]}
      APP_ARG_POSITIONAL=("${APP_ARG_POSITIONAL[@]:1}")

      if [ -z "${arg}" ]; then
        echo "$0: Unknown positional parameter" >&2
        usage >&2

        exit 1
      fi

      declare ARG_${arg}="$1"
      shift
      ;;
  esac
done


# Prepare parameters.

if [ "${#APP_ARG_POSITIONAL[@]}" -gt 0 ]; then
  echo "$0: Parameter ${APP_ARG_POSITIONAL[0]} has not provided yet" >&2
  usage >&2

  exit 1
fi

DST_PREFIX="${ARG_DST_PREFIX%/}"
SRC_PREFIX="${ARG_SRC_PREFIX%/}"

SRC_COMMIT="$(verify_ref "${ARG_SRC_COMMIT}")"

if [ $? -ne 0 ]; then
  echo "$0: Reference '${ARG_SRC_COMMIT}' is not valid" >&2
  exit 2
fi


# Step 1: Search for old SHA1.

GIT_ROOT="$(git rev-parse --show-toplevel)"
OLD_SHA1=

if [ -d "${GIT_ROOT}/${DST_PREFIX}" ]; then
  OLD_SHA1="$(extract_previous_sha1)"
fi

OLD_TREE=

if [ -n "${OLD_SHA1}" ]; then
  OLD_TREE="${OLD_SHA1}:${SRC_PREFIX}"
else
  # This is the first time git-merge-subpath is run, so diff against the
  # empty commit instead of the last commit created before.
  OLD_TREE="$(git hash-object -t tree /dev/null)"
fi


# Step 2: Synthesize content of the commit.

if [ -z "${ARG_IS_SQUASH}" ]; then
  git merge --allow-unrelated-histories -s ours --no-commit "${SRC_COMMIT}"
fi

git diff "${OLD_TREE}" "${SRC_COMMIT}:${SRC_PREFIX}" \
  | git apply -3 --whitespace=nowarn --directory="${DST_PREFIX}"

if (( $? == 1 )); then
  echo "Uh-oh! Try cleaning up with git reset --merge." >&2
  exit 3
fi


# Step 3: Create the commit.

git commit -em "$(commit_msg_template)"
