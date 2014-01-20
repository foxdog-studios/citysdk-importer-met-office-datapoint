#!/usr/bin/env zsh

setopt err_exit

cd ${0:h}/../
bundle exec ruby ./main.rb ${@}

