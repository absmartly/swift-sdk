#!/usr/bin/env bash

if ! type swift-format >/dev/null 2>&1; then
	echo "error: swift-format not installed"
	exit 1
else
	swift-format --parallel --configuration swift-format.json -i -r Sources/ Tests/ Example/
fi
