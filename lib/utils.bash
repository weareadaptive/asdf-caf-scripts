#!/usr/bin/env bash

set -euo pipefail

OWNER="weareadaptive"
REPO="asdf-caf-scripts"
GITHUB_REPO="https://github.com/${OWNER}/${REPO}"
TOOL_NAME="caf-scripts"
RELEASE_NAME="asdf-caf-scripts"

fail() {
	echo -e "asdf-$TOOL_NAME: $*"
	exit 1
}

curl_opts=(-fsSL)

# NOTE: You might want to remove this if caf-scripts is not hosted on GitHub releases.
if [ -n "${GITHUB_API_TOKEN:-}" ]; then
	curl_opts=("${curl_opts[@]}" -H "Authorization: token $GITHUB_API_TOKEN")
fi

sort_versions() {
	sed 'h; s/[+-]/./g; s/.p\([[:digit:]]\)/.z\1/; s/$/.z/; G; s/\n/ /' |
		LC_ALL=C sort -t. -k 1,1 -k 2,2n -k 3,3n -k 4,4n -k 5,5n | awk '{print $2}'
}

list_github_tags() {
	git ls-remote --tags --refs "${GITHUB_REPO}" |
		grep -o 'refs/tags/.*' | cut -d/ -f3- |
		sed 's/^v//' # NOTE: You might want to adapt this sed to remove non-version strings from tags
}

list_all_versions() {
	# TODO: Adapt this. By default we simply list the tag names from GitHub releases.
	# Change this function if caf-scripts has other means of determining installable versions.
	list_github_tags
}

download_release() {
	local install_type="$1"
	local version="$2"
	local filename="$3"
	local url

	if [ "$install_type" == "version" ]; then
		url="${GITHUB_REPO}/archive/refs/tags/v${version}.tar.gz"
	else
		url="https://api.github.com/repos/${OWNER}/${REPO}/tarball/${version}"
	fi

	# TODO: Adapt the release URL convention for <YOUR TOOL>
	echo "* Downloading $TOOL_NAME release $version..."
	curl -L "$url" -C - -o $filename || fail "Could not download $url"
}

install_version() {
	local install_type="$1"
	local version="$2"
	local install_path="${3%/bin}/bin"

	(
		mkdir -p "$install_path"
		cp -r "$ASDF_DOWNLOAD_PATH"/scripts/* "$install_path"

		echo "$TOOL_NAME $version installation was successful!"
	) || (
		rm -rf "$install_path"
		fail "An error occurred while installing $TOOL_NAME $version."
	)
}
