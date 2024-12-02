#!/usr/bin/env bash

set -euo pipefail

OWNER="weareadaptive"
REPO="asdf-caf-scripts"
GITHUB_REPO_URL="https://github.com/${OWNER}/${REPO}"
GITHUB_API_URL="https://api.github.com"
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

	formatted_version=$(printf "$version" | jq -sRr @uri)

	if [ "$install_type" == "version" ]; then
		url="${GITHUB_REPO_URL}/archive/refs/tags/v${version#v}.tar.gz"
	else
		url="${GITHUB_API_URL}/repos/${OWNER}/${REPO}/tarball/${formatted_version}"
	fi

	# TODO: Adapt the release URL convention for <YOUR TOOL>
	echo "* Downloading $TOOL_NAME release $version..."
	curl -fsSL "$url" -C - -o $filename || fail "Could not download $url"
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

asdf_data_dir() {
  local data_dir

  if [ -n "${ASDF_DATA_DIR}" ]; then
    data_dir="${ASDF_DATA_DIR}"
  elif [ -n "$HOME" ]; then
    data_dir="$HOME/.asdf"
  else
    data_dir=$(asdf_dir)
  fi

  printf "%s\n" "$data_dir"
}

get_download_path() {
  local plugin=$1
  local install_type=$2
  local version=${3//\//-}

  local download_dir
  download_dir="$(asdf_data_dir)/downloads"

  [ -d "${download_dir}/${plugin}" ] || mkdir -p "${download_dir}/${plugin}"

  if [ "$install_type" = "version" ]; then
    printf "%s/%s/%s\n" "$download_dir" "$plugin" "$version"
  elif [ "$install_type" = "path" ]; then
    return
  else
    printf "%s/%s/%s-%s\n" "$download_dir" "$plugin" "$install_type" "$version"
  fi
}

get_install_path() {
  local plugin=$1
  local install_type=$2
  local version=${3//\//-}

  local install_dir
  install_dir="$(asdf_data_dir)/installs"

  [ -d "${install_dir}/${plugin}" ] || mkdir -p "${install_dir}/${plugin}"

  if [ "$install_type" = "version" ]; then
    printf "%s/%s/%s\n" "$install_dir" "$plugin" "$version"
  elif [ "$install_type" = "path" ]; then
    printf "%s\n" "$version"
  else
    printf "%s/%s/%s-%s\n" "$install_dir" "$plugin" "$install_type" "$version"
  fi
}