<div align="center">

# asdf-caf-scripts

[caf-scripts](https://github.com/AdaptiveConsulting/asdf-caf-scripts) plugin for the [asdf version manager](https://asdf-vm.com).

</div>

# Contents

- [Dependencies](#dependencies)
- [Install](#install)

# Dependencies

- `bash`, `curl`, `tar`: generic POSIX utilities.
- `yq`

# Install

Plugin:

```shell
asdf plugin add caf-scripts
# or
asdf plugin add caf-scripts git@github.com:AdaptiveConsulting/asdf-caf-scripts.git
```

caf-scripts:

```shell
# Show all installable versions
asdf list-all caf-scripts

# Install specific version
asdf install caf-scripts 1.0.2

# Set a version globally (on your ~/.tool-versions file)
asdf global caf-scripts 1.0.2

# Now caf-scripts commands are available
caf-scripts
```

Check [asdf](https://github.com/asdf-vm/asdf) readme for more instructions on how to
install & manage versions.

# Release

This plugin follows semantic versioning.

To create a new release, tag a commit with the release version in format `vX.X.X`. e.g.

```
git tag v1.0.4
git push --tags
```

To finalize, create a new release in GitHub's [releases section](https://github.com/AdaptiveConsulting/asdf-caf-scripts/releases).
