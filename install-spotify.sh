#!/bin/bash
#
# Automate installation of Spotify on openSUSE 12.2
#
# Credits for original version go to arminw on spotify forums:
#
# http://community.spotify.com/t5/Desktop-Linux/Segfault-on-opensuse-12-2/m-p/161048/highlight/true#M1331

SPOTIFY_BIN="/usr/bin/spotify"

POOL_URL="http://repository.spotify.com/pool/non-free/s/spotify"

#RPM_TOPDIR="/usr/src/packages"
RPM_TOPDIR="$HOME/rpmbuild"
RPM_SOURCE_DIR="$RPM_TOPDIR/SOURCES"
# We prefer to keep the amount of code running as root to an absolute
# minimum, but spotify-installer.spec can't install to a user's home
# directory, so the spec file goes in /usr/src/packages even though
# the rest of the rpmbuild stuff lives in $HOME.
RPM_SPEC_DIR="/usr/src/packages/SPECS"

# Name of file residing within official Spotify repository above
RPM_NAME="spotify-client"
VERSION="0.8.8.323.gd143501.250-1"
BASENAME="${RPM_NAME}_$VERSION"

ISSUE_TRACKER_URL="https://github.com/aspiers/opensuse-spotify-installer/issues"

main () {
    parse_args "$@"

    check_non_root

    if [ -z "$uninstall" ]; then
        safe_run mkdir -p "$RPM_TOPDIR"/{BUILD,BUILDROOT,SPECS,SOURCES,SRPMS,RPMS/{i586,x86_64}}
        download_spotify_deb
        echo
        install_dependencies
        echo
        build_rpm
        echo
        install_rpm
        echo
        progress "Spotify can now be run via $SPOTIFY_BIN - happy listening!"
    else
        uninstall
    fi
}

usage () {
    # Call as: usage [EXITCODE] [USAGE MESSAGE]
    exit_code=1
    if [[ "$1" == [0-9] ]]; then
        exit_code="$1"
        shift
    fi
    if [ -n "$1" ]; then
        echo "$*" >&2
        echo
    fi

    me=`basename $0`

    cat <<EOF >&2
Usage: $me
       $me -u | --uninstall
EOF
    exit "$exit_code"
}

parse_args () {
    uninstall=

    while [ $# != 0 ]; do
        case "$1" in
            -h|--help)
                usage 0
                ;;
            -u|--uninstall)
                uninstall=y
                shift
                ;;
            -*)
                usage "Unrecognised option: $1"
                ;;
            *)
                break
                ;;
        esac
    done

    if [ $# -gt 1 ]; then
        usage
    fi

    if [ -n "$1" ]; then
        BASENAME=$1
    fi
}

progress () { tput bold; tput setaf 2; echo     "$*"; tput sgr0; }
warn     () { tput bold; tput setaf 3; echo >&2 "$*"; tput sgr0; }
error    () { tput bold; tput setaf 1; echo >&2 "$*"; tput sgr0; }
fatal    () { error "$@"; exit 1; }

safe_run () {
    if ! "$@"; then
        fatal "$* failed! Aborting." >&2
        exit 1
    fi
}

check_non_root () {
    if [ "$(id -u)" = "0" ]; then
        fatal "\
Please run this script non-root, it's a bit safer that way.
It will use sudo for commands which need root.  Aborting."
    fi
}

install_dependencies () {
    if ! rpm -q libmp3lame0 >/dev/null; then
        warn "\
WARNING: You do not have libmp3lame0 installed, so playback of local
mp3 files will not work.  Would you like me to install this from
Packman now?
"
        echo -n "Type y/n> "
        read answer
        echo
        case "$answer" in
            y|yes|Y|YES)
                install_libmp3lame0
                ;;
        esac
    fi

    if rpm -q rpm-build >/dev/null; then
        progress "rpm-build is already installed."
    else
        safe_run sudo zypper -n install -lny rpm-build
    fi
}

install_libmp3lame0 () {
    if safe_run zypper lr -d | grep -iq 'packman'; then
        progress "Packman repository is already configured - good :)"
    else
        safe_run sudo zypper ar -f http://packman.inode.at/suse/12.2/packman.repo
        progress "Added Packman repository."
    fi

    echo
    safe_run sudo zypper -n in -l libmp3lame0
    echo
    progress "Installed libmp3lame0."
}

download_spotify_deb () {
    arch=$(arch)
    if [ "$arch" == "x86_64" ]; then
        deb=${BASENAME}_amd64.deb
        rpmarch="x86_64"
    elif [ "$arch" == "i686" ]; then
        deb=${BASENAME}_i386.deb
        rpmarch="i586"
    else
        fatal "
Sorry, $arch architecture isn't supported.  If you think this is a
mistake, please consider filing a bug at:

    $ISSUE_TRACKER_URL

Aborting.
"
    fi

    RPM_DIR="$RPM_TOPDIR/RPMS/$rpmarch"

    dest="$RPM_SOURCE_DIR/$deb"
    if [ ! -e "$dest" ]; then
        echo "Downloading Spotify .deb package ..."
        safe_run wget -O "$dest" "$POOL_URL/$deb"
        progress ".deb downloaded."
    else
        progress "Spotify .deb package already exists:"
        echo
        echo "  ${dest/$HOME/~}"
        echo
        echo "Skipping download."
    fi
}

build_rpm () {
    echo "About to build $RPM_NAME rpm; please be patient ..."
    echo
    sleep 3
    safe_run rpmbuild -ba "$RPM_SPEC_DIR/spotify.spec"

    rpm="$RPM_DIR/${RPM_NAME}-${VERSION}.$rpmarch.rpm"

    if ! [ -e "$rpm" ]; then
        fatal "
rpmbuild failed :-(  Please consider filing a bug at:

    $ISSUE_TRACKER_URL
"
    fi

    echo
    progress "rpm successfully built!"
}

install_rpm () {
    echo "Installing Spotify from the rpm we just built ..."
    safe_run sudo zypper -n in "$rpm"

    if ! rpm -q "$RPM_NAME" >/dev/null; then
        error "Failed to install $rpm :-("
        error "Please consider filing a bug at:

    $ISSUE_TRACKER_URL"
    fi
}

uninstall () {
    if rpm -q "$RPM_NAME" >/dev/null; then
        echo "Removing $RPM_NAME rpm ..."
        safe_run sudo rpm -ev "$RPM_NAME"
        progress "De-installation done!"
    else
        warn "$RPM_NAME was not installed; nothing to uninstall."
    fi
}

main "$@"
