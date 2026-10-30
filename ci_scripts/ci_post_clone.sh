#!/bin/sh
# Xcode Cloud: the Xcode project is generated from project.yml, so create it after cloning.
set -e
brew install xcodegen
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate
