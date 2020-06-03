#!/bin/bash
######################################################################################################
#
# bwrs_update - script to update and compile bitwarden_rs from src, and update pre-compiled web vault
#
# * Pull latest bitwarden_rs src from github and compile any newer commits
# * Pull latest pre-compiled web vault from github and untar it over the existing installation
#
# NOTE: This is for compiling an executable from the rust source code for bitwarden_rs,
#		not for creating a docker installation
#
# bitwarden_rs on Github: https://github.com/dani-garcia/bitwarden_rs
#
# Ayitaka
#
######################################################################################################
#
# Syntax:
#	bwrs_update			- Checks for and compiles/extracts any new commits
#	bwrs_update clean	- Forces removal of all dependencies and re-compile of latest version
#
######################################################################################################

HOME_DIR="/home/bitwarden"
SRC_DIR="${HOME_DIR}/src/bitwarden_rs"
INSTALL_DIR="${HOME_DIR}/bw"
#WEB_VAULT_DIR="${INSTALL_DIR}/web-vault"
WEB_VAULT_DIR="${INSTALL_DIR}"

UPDATED=0

#########################
##### bitwarden_rs update
#########################

cd $SRC_DIR

if [ "$1" = "clean" ]; then
	# Clear out all compiled dependency files and build from scratch
    cargo clean
fi

# Pull any updates from project on github
# TODO Add checks for merge failure and other fail scenerios?
{ git pull origin master | grep "Already up to date"; } >/dev/null 2>&1;
if [ "$?" -eq "1" ] || [ "$1" = "clean" ]; then
	UPDATED=1

	TAGS="$( git ls-remote https://github.com/dani-garcia/bitwarden_rs.git )"

	bwrs_latest_version="$( echo "${TAGS}" | sed -E '/refs\/tags\//!d;s/.*refs\/tags\/(.*)$/\1/g' | sort -V -r | head -n 1 )"
	bwrs_latest_commit="$( echo "${TAGS}" | sed -E '/refs\/heads\/master/!d;s/^(.) refs\/heads\/master/\1/g' | head -n 1 | cut -c1-7)"

	export BWRS_VERSION="${bwrs_latest_version}-${bwrs_latest_commit}"

	echo "Updating bitwarden_rs to v${BWRS_VERSION}"

	# Change version configuration in bitwarden_rs.env
	sed -iE "s/BWRS_VERSION=.*/BWRS_VERSION=${BWRS_VERSION}/" ${INSTALL_DIR}/bitwarden_rs.env

#	cargo build --features sqlite --release >/dev/null 2>&1
	cargo build --features sqlite --release

	service bitwarden stop

	rm -f ${INSTALL_DIR}/bitwarden_rs
	cp -p ${SRC_DIR}/target/release/bitwarden_rs ${INSTALL_DIR}/bitwarden_rs >/dev/null 2>&1
	chown -R bitwarden.bitwarden $HOME_DIR

	echo "bitwarden_rs update complete"
else
	echo "No bitwarden_rs update available"
fi

######################
##### web vault update
######################

cd $WEB_VAULT_DIR

if [ -f ${WEB_VAULT_DIR}/bw_web_v*.tar.gz ]; then
	wv_current_file="$( ls ${WEB_VAULT_DIR}/bw_web_v*.tar.gz )"
	wv_current_version="$( echo "${wv_current_file}" | sed -E 's/.*v(.*)\.tar\.gz/\1/g' )"
else
	# No current version installed
	wv_current_file=''
	wv_current_version='0.0.0'
fi

#echo "Current web vault version: ${wv_current_version}"

# Scrape list of releases to figure out what the latest version available is
wv_releases="$( curl -fsL --retry 3 "https://github.com/dani-garcia/bw_web_builds/releases" )"
wv_latest_version="$( echo "$wv_releases" | sed -E '/bw_web_builds\/releases\/download/!d;s/.*v(.*)\.tar\.gz.*/\1/g' | sort -V -r | head -n 1 )"

#echo "Latest web vault version:  ${wv_latest_version}"

if [ ! -f "$wv_current_file" ] || ( [ -n "$wv_current_version" ] && [ -n "$wv_latest_version" ] && [ "$wv_latest_version" != "$wv_current_version" ]; ); then
	UPDATED=1
	echo "Updating web vault to v${wv_latest_version}"

	if [ -f "$wv_current_file" ]; then 
		rm -f ${wv_current_file} >/dev/null 2>&1
	fi

	# Download and untar latest version
	curl -fsL -o ${WEB_VAULT_DIR}/bw_web_v${wv_latest_version}.tar.gz --retry 3 https://github.com/dani-garcia/bw_web_builds/releases/download/v${wv_latest_version}/bw_web_v${wv_latest_version}.tar.gz >/dev/null 2>&1
	tar xvfz ${WEB_VAULT_DIR}/bw_web_v${wv_latest_version}.tar.gz >/dev/null 2>&1
	echo "web vault update complete"
else
	echo "No web vault update available"
fi

if [ "$UPDATED" -eq 1 ]; then 
#	echo "Updated, changing file permissions"
	chown -R bitwarden.bitwarden $HOME_DIR
fi

service bitwarden restart >/dev/null 2>&1
