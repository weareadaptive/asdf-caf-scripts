#!/usr/bin/env bash

set -euo pipefail

GITLAB_REPO="https://gitlab.com/weareadaptive/adaptive/common/asdf-caf-scripts"
TOOL_NAME="caf-scripts"
RELEASE_NAME="asdf-caf-scripts"
TOOL_NAME="caf-scripts"

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
	git ls-remote --tags --refs "$GITLAB_REPO" |
		grep -o 'refs/tags/.*' | cut -d/ -f3- |
		sed 's/^v//' # NOTE: You might want to adapt this sed to remove non-version strings from tags
}

list_all_versions() {
	# TODO: Adapt this. By default we simply list the tag names from GitHub releases.
	# Change this function if caf-scripts has other means of determining installable versions.
	list_github_tags
}

download_release() {
	local version directory
	version="${1}"
	directory="${2}"

	echo "* Downloading ${TOOL_NAME} release ${version}..."
	glab release download "v${version}" --repo "${GITLAB_REPO}" --asset-name "*.tar.gz" --dir "${directory}"
}

install_version() {
	local install_type="$1"
	local version="$2"
	local install_path="${3%/bin}/bin"

	if [ "$install_type" != "version" ]; then
		fail "asdf-$TOOL_NAME supports release installs only"
	fi

	(
		mkdir -p "$install_path"
		cp -r "$ASDF_DOWNLOAD_PATH"/scripts/* "$install_path"

		echo "$TOOL_NAME $version installation was successful!"
	) || (
		rm -rf "$install_path"
		fail "An error occurred while installing $TOOL_NAME $version."
	)
}

verify_glab_auth() {
	local gitlab_config_path

	echo "Verifying if glab is authenticated to Gitlab..."
	gitlab_config_path="$HOME/.config/glab-cli/config.yml"

	if ! test -e "${gitlab_config_path}" || [[ "$(yq '.hosts."gitlab.com".token' "${gitlab_config_path}")" == "null" ]]; then
	  cat <<EOF
ERROR: glab is not authenticated to Gitlab. Please authenticate:
- 'glab auth login'
- choose options: 'gitlab.com', 'Web' authentication
- follow instructions in the browser and 'HTTPS' as the preferred protocol
- run 'direnv reload'
EOF
	  exit 1
	fi
}
