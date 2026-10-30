.PHONY: help check-host prepare builder-image builder-check builder-shell

help:
	@printf '%s\n' 'check-host  LFSビルド環境を検査' 'prepare     検査後に構築先と環境ファイルを作成'

builder-image:
	podman build -t localhost/lightnix-builder container

builder-check:
	bash scripts/builder.sh make check-host

builder-shell:
	bash scripts/builder.sh

check-host:
	python3 scripts/check-host.py

prepare: check-host
	bash scripts/prepare.sh
