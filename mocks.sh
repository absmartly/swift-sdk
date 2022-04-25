#!/usr/bin/env bash

if ! type sourcery >/dev/null 2>&1; then
	echo "error: sourcery not installed"
	exit 1
else
	sourcery -p \
		--sources Sources \
		--templates Templates \
		--output Tests/ABSmartlyTests/Mocks/SourceryGenerated.swift \
		--args autoMockableTestableImports=\"ABSmartly\" \
		--args autoMockableImports=\"PromiseKit\"
	./format.sh
fi
