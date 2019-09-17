#!/usr/bin/env bash

# Remark: Run this script from its directory.

export PROGNAME="entry.sh"

# #############################################################################
# Globals

export USAGE="Syntax
$PROGNAME [-c] [-d runr_dir] [-q] [-r repos_list] [-u] [-v]

-c    Keeps previous assets repos i.e. do not clone repos with recipes
      (must have one from a previous run in order to look recipes up)

-d runr_dir
      Overrides default RUNR_DIR

-k    use insecure curl ie do not check for certificates, ssl etc.
-q    quiet (not exported i.e. does not propagate to runr subprocesses)
-r    repository(ies) desired instead of the default (stroparo/dotfiles)
-u    has runr update itself i.e. its core, runs prior to any recipe
-v    verbose output (not exported i.e. does not propagate to runr subprocesses)
"

: ${RUNR_DIR:=${HOME}/.runr} ; export RUNR_DIR

: ${DEV:=${HOME}/workspace} ; export DEV
: ${OVERRIDE_SUBL_PREFS:=false} ; export OVERRIDE_SUBL_PREFS

# Security
: ${IGNORE_SSL:=false} ; export IGNORE_SSL

# System installers
export APTPROG=apt-get; which apt >/dev/null 2>&1 && export APTPROG=apt
export RPMPROG=yum; which dnf >/dev/null 2>&1 && export RPMPROG=dnf
export RPMGROUP="yum groupinstall"; which dnf >/dev/null 2>&1 && export RPMGROUP="dnf group install"
export INSTPROG="$APTPROG"; which "$RPMPROG" >/dev/null 2>&1 && export INSTPROG="$RPMPROG"

# #############################################################################
# Options

if [ -z "${RUNR_ASSETS_REPOS}" ] ; then
  export RUNR_ASSETS_REPOS="https://bitbucket.org/stroparo/dotfiles.git"
fi
if [ -z "${RUNR_ASSETS_REPOS_FALLBACKS}" ] ; then
  export RUNR_ASSETS_REPOS_FALLBACKS="https://github.com/stroparo/dotfiles.git"
fi

: ${RUNR_ASSETS_KEEP:=false} ; export RUNR_ASSETS_KEEP
: ${RUNR_QUIET:=false}
: ${UPDATE_LOCAL_RUNR:=false} ; export UPDATE_LOCAL_RUNR
: ${VERBOSE:=false}

# Options:
OPTIND=1
while getopts ':cd:kqr:uv' option ; do
  case "${option}" in
    c) export RUNR_ASSETS_KEEP=true ;;
    d) export RUNR_DIR="$OPTARG" ;;
    k) export IGNORE_SSL=true ;;
    q) RUNR_QUIET=true ;;
    r) export RUNR_ASSETS_REPOS="$OPTARG" ;;
    u) export UPDATE_LOCAL_RUNR=true ;;
    v) VERBOSE=true; VERBOSE_OPTION="v" ;;
  esac
done
shift "$((OPTIND-1))"

export RUNR_BAK_DIRNAME="${RUNR_DIR}.bak.$(date '+%Y%m%d-%OH%OM%OS')"

RUNR_TMP="${RUNR_DIR}/tmp"

export RUNR_QUIET
if ${RUNR_QUIET:-false} ; then
  RUNR_QUIET_OPTION_Q='-q'
fi

if ${IGNORE_SSL:-false} ; then
  export IGNORE_SSL_OPTION="-k"
fi


# #############################################################################
# Helpers


_install_packages () {
  for package in "$@" ; do
    echo "Installing '$package'..."
    if ! sudo $INSTPROG install -y "$package" >/tmp/pkg-install-${package}.log 2>&1 ; then
      echo "RUNR: WARN: There was an error installing package '$package' - see '/tmp/pkg-install-${package}.log'."
    fi
  done
}


_print_footer_bar () {
  echo "////////////////////////////////////////////////////////////////////////////////"
}


_print_header_bar () {
  echo "################################################################################"
}


_print_footer () {

  if ${RUNR_QUIET:-false} ; then
    return
  fi

  echo
  _print_footer_bar
}


_print_header () {

  if ${RUNR_QUIET:-false} ; then
    return
  fi

  typeset recipe="$1"

  echo
  echo
  _print_header_bar
  echo "==> Routine: '${recipe}'"
  echo "    PWD='$(pwd)'"
  echo
  echo
}


# #############################################################################
# Dependencies


if (uname | grep -q linux) ; then
  if ! which sudo >/dev/null 2>&1 ; then
    echo "RUNR: WARN: Installing sudo via root and opening up visudo"
    su - -c "bash -c '$INSTPROG install sudo; visudo'"
  fi
  if ! sudo whoami >/dev/null 2>&1 ; then
    echo "RUNR: FATAL: No sudo access." 1>&2
    exit 1
  fi
fi

if (! which curl || ! which git || ! which unzip) >/dev/null 2>&1 ; then
  which $APTPROG >/dev/null 2>&1 && sudo $APTPROG update
  _install_packages curl git unzip
fi


# #############################################################################
# Provisioning


_info_runr_dir () {
  if ! ${RUNR_QUIET:-false} ; then
    echo
    echo "RUNR: INFO: RUNR dir is '${RUNR_DIR}'."
  fi
}


_exclude_core_files () {

  typeset exclude_root="${1:-$RUNR_DIR}"

  sed -e "#^#${exclude_root}/#" \
    "${RUNR_DIR}"/core_files.lst \
    | xargs rm -f -r
}


_exclude_non_core_files () {

  typeset exclude_root="${1:-$RUNR_DIR}"

  sed -e "#^#${exclude_root}/#" "${RUNR_DIR}"/core_files.lst \
    > "${RUNR_DIR}"/core_files.lst.tmp

  find "${exclude_root}" -mindepth 1 -depth \
    | fgrep -v -f "${RUNR_DIR}"/core_files.lst.tmp \
    | xargs rm -f -r \
    && rm -f "${RUNR_DIR}"/core_files.lst.tmp
}


_archive_runr_dir () {
  if [ -d "${RUNR_DIR}" ] ; then
    if mv -f "${RUNR_DIR}" "${RUNR_BAK_DIRNAME}" ; then
      if tar cz${VERBOSE_OPTION}f "${RUNR_BAK_DIRNAME}.tar.gz" "${RUNR_BAK_DIRNAME}" ; then
        if ! ${RUNR_ASSETS_KEEP} ; then
          rm -f -r "${RUNR_BAK_DIRNAME}"
        fi
      else
        echo "RUNR: WARN: Could not make tarball but kept backup in the '${RUNR_BAK_DIRNAME}' dir."
      fi
    else
      echo "RUNR: FATAL: Could not archive existing '${RUNR_DIR}'." 1>&2
      exit 1
    fi
  fi
  return 0
}


_unarchive_backup_assets () {
  if ${RUNR_ASSETS_KEEP} ; then
    _exclude_core_files "${RUNR_BAK_DIRNAME}"
    mv -f "${RUNR_BAK_DIRNAME}"/* "${RUNR_DIR}"/ \
      && [ -f "${RUNR_BAK_DIRNAME}.tar.gz" ] \
      && rm -f -r "${RUNR_BAK_DIRNAME}"
  fi
}


_update_pre_proc () {
  if ! ${UPDATE_LOCAL_RUNR:-false} ; then
    return
  fi

  _archive_runr_dir
}


_update_post_proc () {
  if ! ${UPDATE_LOCAL_RUNR:-false} ; then
    return
  fi

  _unarchive_backup_assets
}


_setup_download () {
  curl ${DLOPTEXTRA} ${IGNORE_SSL_OPTION} -LSfs -o "${HOME}"/.runr.zip "$RUNR_SRC" \
    || curl ${DLOPTEXTRA} ${IGNORE_SSL_OPTION} -LSfs -o "${HOME}"/.runr.zip "$RUNR_SRC_ALT"
}


_setup_extract () {
  unzip -o "${HOME}"/.runr.zip -d "${HOME}" \
    || exit $?
}


_setup_final_dir () {
  zip_root_dir=$(unzip -l "${HOME}"/.runr.zip | head -5 | tail -1 | awk '{print $NF;}')
  echo "RUNR: INFO: RUNR package's root directory: '${zip_root_dir}'"
  echo "RUNR: INFO: RUNR package's root rename to final dir '${RUNR_DIR}':"
  if ! (cd "${HOME}"; mv -f -v "${zip_root_dir}" "${RUNR_DIR}") ; then
    echo "RUNR: FATAL: Could not move/rename '${zip_root_dir}' to '${RUNR_DIR}'" 1>&2
    exit 1
  fi
}


_setup () {

  if [ -d "${RUNR_DIR}" ] && ! ${UPDATE_LOCAL_RUNR:-false} ; then
    return
  fi

  _setup_download
  _setup_extract
  _setup_final_dir
}


_enforce_env () {
  if [ ! -e "${RUNR_DIR}"/entry.sh ] ; then
    echo "RUNR: FATAL: No RUNR instance available ('${RUNR_DIR}/entry.sh' does not exist)." 1>&2
    exit 1
  fi
  cd "${RUNR_DIR}"
  echo "RUNR: INFO: Current dir (should be RUNR's): '$(pwd)'"
  if [ "${RUNR_DIR##*/}" != "${PWD##*/}" ] ; then
    echo "RUNR: FATAL: Current dir's basename differs from RUNR dir's ('${RUNR_DIR}')" 1>&2
    exit 1
  fi
}


_provision_runr () {
  export RUNR_SRC="https://bitbucket.org/stroparo/runr/get/master.zip"
  export RUNR_SRC_ALT="https://github.com/stroparo/runr/archive/master.zip"

  _info_runr_dir
  _update_pre_proc
  _setup
  _enforce_env
  _update_post_proc
  if ! ${RUNR_ASSETS_KEEP} ; then
    _exclude_non_core_files
  fi
}


# #############################################################################
# Asset retrieval


_clone_assets_prep () {
  mkdir "${RUNR_TMP}" 2>/dev/null
  if [ ! -d "${RUNR_TMP}" ] ; then
    echo "RUNR: FATAL: There was some error creating temp dir at '${RUNR_TMP}'." 1>&2
    exit 1
  fi
}


_clone_assets () {

  _clone_assets_prep

  if ! ${RUNR_ASSETS_KEEP} && [ -n "$RUNR_ASSETS_REPOS" ] ; then
    while read repo ; do
      repo_basename=$(basename "${repo%.git}")
      echo "RUNR: INFO: Cloning assets repo '$repo'..."
      if ! git clone --depth=1 ${RUNR_QUIET_OPTION_Q} "$repo" "${RUNR_TMP}/${repo_basename}" ; then
        repo_fallback="$(echo "${RUNR_ASSETS_REPOS_FALLBACKS}" | egrep "/$repo_basename[.]?[^/]*$" | head -1)"
        git clone --depth=1 ${RUNR_QUIET_OPTION_Q} "${repo_fallback}" "${RUNR_TMP}/${repo_basename}"
      fi
      if cp -f -R ${VERBOSE_OPTION:+-${VERBOSE_OPTION}} "${RUNR_TMP}/${repo_basename}"/* "${RUNR_DIR}"/ ; then
        rm -f -r "${RUNR_TMP}/${repo_basename}"
      else
        echo "RUNR: WARN: There was some error deploying '${RUNR_TMP}/${repo_basename}' files to '${RUNR_DIR}'."
      fi
    done <<EOF
$(echo "$RUNR_ASSETS_REPOS" | tr -s ' ' '\n' | grep .)
EOF
  fi
}


# #############################################################################
# Run sequences


_run_sequences () {
  for recipe in "$@" ; do
    for dir in */ ; do
      if [ -f "./${dir%/}/${recipe%.sh}.sh" ] ; then
        _print_header "${dir%/}/${recipe%.sh}"
        bash "./${dir%/}/${recipe%.sh}.sh"
        _print_footer
      fi
    done
  done
}


# #############################################################################


_main () {
  _provision_runr
  _clone_assets
  _run_sequences "$@"
}


_main "$@"
