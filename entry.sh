#!/usr/bin/env bash

# Remark: Run this script from its directory.

export PROGNAME="entry.sh"

# #############################################################################
# Globals

export USAGE="Syntax
$PROGNAME [-u] [-r repos_list] [-v]

-u  has runr update itself i.e. its core
-r  repository(ies) desired instead of the default (stroparo/dotfiles)
-v  verbose outputs
"

export RUNR_DIR="${HOME}/.runr"
export RUNR_BAK_DIRNAME="${RUNR_DIR}.bak.$(date '+%Y%m%d-%OH%OM%OS')"

: ${DEV:=${HOME}/workspace} ; export DEV
: ${OVERRIDE_SUBL_PREFS:=false} ; export OVERRIDE_SUBL_PREFS

# System installers
export APTPROG=apt-get; which apt >/dev/null 2>&1 && export APTPROG=apt
export RPMPROG=yum; which dnf >/dev/null 2>&1 && export RPMPROG=dnf
export RPMGROUP="yum groupinstall"; which dnf >/dev/null 2>&1 && export RPMGROUP="dnf group install"
export INSTPROG="$APTPROG"; which "$RPMPROG" >/dev/null 2>&1 && export INSTPROG="$RPMPROG"

# #############################################################################
# Options

: ${REPOS:=https://github.com/stroparo/dotfiles.git}; export REPOS
: ${UPDATE_LOCAL_RUNR:=false}
: ${VERBOSE:=false}

# Options:
OPTIND=1
while getopts ':r:uv' option ; do
  case "${option}" in
    r) export REPOS="$OPTARG";;
    u) export UPDATE_LOCAL_RUNR=true;;
    v) VERBOSE=true; VERBOSE_OPTION='v';;
  esac
done
shift "$((OPTIND-1))"

# #############################################################################
# Helpers

_install_packages () {
  for package in "$@" ; do
    echo "Installing '$package'..."
    if ! sudo $INSTPROG install -y "$package" >/tmp/pkg-install-${package}.log 2>&1 ; then
      echo "${PROGNAME:+$PROGNAME: }WARN: There was an error installing package '$package' - see '/tmp/pkg-install-${package}.log'." 1>&2
    fi
  done
}

_print_bar () {
  echo "################################################################################"
}

# #############################################################################
# Dependencies

if (uname | grep -q linux) ; then
  if ! which sudo >/dev/null 2>&1 ; then
    echo "${PROGNAME:+$PROGNAME: }WARN: Installing sudo via root and opening up visudo" 1>&2
    su - -c "bash -c '$INSTPROG install sudo; visudo'"
  fi
  if ! sudo whoami >/dev/null 2>&1 ; then
    echo "${PROGNAME:+$PROGNAME: }FATAL: No sudo access." 1>&2
    exit 1
  fi
fi

if (! which curl || ! which git || ! which unzip) >/dev/null 2>&1 ; then
  which $APTPROG >/dev/null 2>&1 && sudo $APTPROG update
  _install_packages curl git unzip
fi

# #############################################################################

_archive_runr_dir () {
  if [ -d "${RUNR_DIR}" ] ; then
    if mv -f "${RUNR_DIR}" "${RUNR_BAK_DIRNAME}" ; then
      if tar cz${VERBOSE_OPTION}f "${RUNR_BAK_DIRNAME}.tar.gz" "${RUNR_BAK_DIRNAME}" ; then
        rm -f -r "${RUNR_BAK_DIRNAME}"
      else
        echo "${PROGNAME:+$PROGNAME: }WARN: Could not make tarball but kept backup in the '${RUNR_BAK_DIRNAME}' dir." 1>&2
      fi
    else
      echo "${PROGNAME:+$PROGNAME: }FATAL: Could not archive existing '${RUNR_DIR}'." 1>&2
      exit 1
    fi
  fi
  return 0
}

_provision_runr () {
  export RUNR_SRC="https://bitbucket.org/stroparo/runr/get/master.zip"
  export RUNR_SRC_ALT="https://github.com/stroparo/runr/archive/master.zip"

  if [ ! -d "${RUNR_DIR}" ] || (${UPDATE_LOCAL_RUNR:-false} && _archive_runr_dir) ; then
    # Provide an updated runr instance:
    curl -LSfs -o "${HOME}"/.runr.zip "$RUNR_SRC" \
      || curl -LSfs -o "${HOME}"/.runr.zip "$RUNR_SRC_ALT"
    unzip -o "${HOME}"/.runr.zip -d "${HOME}" \
      || exit $?
    zip_dir=$(unzip -l "${HOME}"/.runr.zip | head -5 | tail -1 | awk '{print $NF;}')
    echo "Zip dir: '$zip_dir'" 1>&2
    if ! (cd "${HOME}"; mv -f ${VERBOSE_OPTION:+-${VERBOSE_OPTION}} "${zip_dir}" "${RUNR_DIR}" 1>&2) ; then
      echo "${PROGNAME:+$PROGNAME: }FATAL: Could not move '$zip_dir' to '${RUNR_DIR}'" 1>&2
      exit 1
    fi
  fi

  if [ ! -e "${RUNR_DIR}"/entry.sh ] ; then
    echo "${PROGNAME:+$PROGNAME: }FATAL: No runr instance available ('${RUNR_DIR}/entry.sh' does not exist)." 1>&2
    exit 1
  fi

  cd "${RUNR_DIR}"

  find "${RUNR_DIR}" -name '*.sh' -type f -exec chmod u+x {} \;
  if ! (echo "$PATH" | fgrep -q "$(basename "${RUNR_DIR}")") ; then
    # Root intentionally omitted from PATH as these must be called with absolute path:
    export PATH="${RUNR_DIR}/installers:${RUNR_DIR}/recipes:${RUNR_DIR}/scripts:$PATH"
  fi
}
_provision_runr

# #############################################################################
# Clone repos with sequences to be ran

RUNR_TMP="${RUNR_DIR}/tmp"
mkdir "${RUNR_TMP}"
if [ ! -d "${RUNR_TMP}" ] ; then
  echo "${PROGNAME:+$PROGNAME: }FATAL: There was some error creating temp dir at '${RUNR_TMP}'." 1>&2
  exit 1
fi

if [ -n "$REPOS" ] ; then
  while read repo ; do
    repo_basename=$(basename "${repo%.git}")
    git clone --depth=1 "$repo" "${RUNR_TMP}/${repo_basename}"
    if cp -f -R ${VERBOSE_OPTION:+-${VERBOSE_OPTION}} "${RUNR_TMP}/${repo_basename}"/* "${RUNR_DIR}"/ ; then
      rm -f -r "${RUNR_TMP}/${repo_basename}"
    else
      echo "${PROGNAME:+$PROGNAME: }WARN: There was some error deploying '${RUNR_TMP}/${repo_basename}' files to '${RUNR_DIR}'." 1>&2
    fi
  done <<EOF
$(echo "$REPOS" | tr -s ' ' '\n')
EOF
fi

# #############################################################################
# Run sequences

for recipe in "$@" ; do
  for dir in */ ; do
    if [ -f "./${dir%/}/${recipe%.sh}.sh" ] ; then
      bash "./${dir%/}/${recipe%.sh}.sh"
    fi
  done
done
