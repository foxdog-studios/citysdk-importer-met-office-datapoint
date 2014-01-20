#!/usr/bin/env bash

set -o errexit
set -o nounset


# ==============================================================================
# = Configuration                                                              =
# ==============================================================================

# Paths

repo=$(realpath "$(dirname "$(realpath -- "${BASH_SOURCE[0]}")")/..")

env=$repo/env


# Packages

aur_packages=(
)

node_global_packages=(
    bower
    meteorite
    grunt-cli
)

pacman_packages=(
    git
    nodejs
    python
    yaourt
)


# ==============================================================================
# = Tasks                                                                      =
# ==============================================================================

function add_archlinuxfr_repo()
{
    if grep --quiet '\[archlinuxfr\]' /etc/pacman.conf; then
        return
    fi

    sudo tee --append /etc/pacman.conf <<-'EOF'
		[archlinuxfr]
		Server = http://repo.archlinux.fr/$arch
		SigLevel = Never
	EOF
}

function install_pacman_packages()
{
    sudo pacman --noconfirm --sync --needed --refresh "${pacman_packages[@]}"
}

function install_aur_packages()
{
    local package

    for package in "${aur_packages[@]}"; do
        if ! pacman -Q "$package" &> /dev/null; then
            yaourt --noconfirm --sync "$package"
        fi
    done
}

function ensure_ve()
{
    if [[ ! -d "$env" ]]; then
        python3.3 -m venv "$env"
    fi
}

function install_distribute()
{
    ve _install_distribute
}

function _install_distribute()
{
    easy_install pip
}

function install_pip()
{
    ve _install_pip
}

function _install_pip()
{
    curl http://python-distribute.org/distribute_setup.py | python3.3
    rm --force distribute-*.tar.gz
}

function install_python_packages()
{
    pip install --requirement "$repo/requirement.txt"
}

function install_node_packages()
{
    npm install
}


# ==============================================================================
# = Helpers                                                                    =
# ==============================================================================

function allow_unset()
{
    local restore=$(set +o | grep nounset)
    set +o nounset
    "$@"
    local exit_status=$?
    # Do not quote, expansion is desired
    $restore
    return "$exit_status"
}

function ve()
{
    allow_unset source "$env/bin/activate"
    "$@"
    allow_unset deactivate
}


# ==============================================================================
# = Command line interface                                                     =
# ==============================================================================

tasks=(
    add_archlinuxfr_repo
    install_pacman_packages
    install_aur_packages
    ensure_ve
    install_distribute
    install_pip
    install_python_packages
    install_global_node_packages
    install_node_packages
)

function usage()
{
    cat <<-'EOF'
		Set up a development environment

		Usage:

		    setup.sh [TASK...]

		Tasks:

		    add_archlinuxfr_repo
		    install_pacman_packages
		    install_aur_packages
		    ensure_ve
		    install_python_packages
		    install_global_node_packages
		    install_node_packages
	EOF
    exit 1
}

for task in "$@"; do
    if [[ "$(type -t "$task" 2> /dev/null)" != function ]]; then
        usage
    fi
done

for task in "${@:-${tasks[@]}}"; do
    echo -e "\e[5;32mTask: $task\e[0m\n"
    "$task"
done

