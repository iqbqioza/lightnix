.PHONY: help check-host prepare builder-image builder-check builder-shell fetch verify-sources binutils-bootstrap gcc-bootstrap

help:
	@printf '%s\n' 'check-host  LFSビルド環境を検査' 'prepare     検査後に構築先と環境ファイルを作成'
	@printf '%s\n' 'fetch       ソースを取得・検証（検証済みは再利用）' 'verify-sources  取得済みソースをオフライン検証'
	@printf '%s\n' 'binutils-bootstrap  専用コンテナでBinutils pass 1を構築'
	@printf '%s\n' 'gcc-bootstrap  専用コンテナでGCCのクロスコンパイラを構築'

gcc-bootstrap:
	bash scripts/builder.sh bash scripts/gcc-bootstrap.sh

binutils-bootstrap:
	bash scripts/builder.sh bash scripts/binutils-bootstrap.sh

fetch:
	python3 scripts/sources.py fetch

verify-sources:
	python3 scripts/sources.py verify

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
