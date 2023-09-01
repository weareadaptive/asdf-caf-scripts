<div align="center">

# asdf-caf-scripts

[caf-scripts](https://gitlab.com/weareadaptive/adaptive/common/caf-scripts) plugin for the [asdf version manager](https://asdf-vm.com).

</div>

# Contents

- [Dependencies](#dependencies)
- [Install](#install)

# Dependencies

**TODO: adapt this section**

- `bash`, `curl`, `tar`: generic POSIX utilities.
- `SOME_ENV_VAR`: set this environment variable in your shell config to load the correct version of tool x.

# Install

Plugin:

```shell
asdf plugin add caf-scripts
# or
asdf plugin add caf-scripts https://gitlab.com/weareadaptive/adaptive/common/caf-scripts.git
```

caf-scripts:

```shell
# Show all installable versions
asdf list-all caf-scripts

# Install specific version
asdf install caf-scripts latest

# Set a version globally (on your ~/.tool-versions file)
asdf global caf-scripts latest

# Now caf-scripts commands are available
caf-scripts
```

Check [asdf](https://github.com/asdf-vm/asdf) readme for more instructions on how to
install & manage versions.
