# Lightnix

ソースからツールチェーンとユーザーランドを構築する、glibcベースのLinuxディストリビューション。
最初の対象はx86_64のQEMU仮想マシンです。

## 設計

- 構築手順の基準: [Linux From Scratch 12.4 (SysV)](https://www.linuxfromscratch.org/lfs/view/12.4/)
- ツールチェーン: Binutils → GCC → Linux API headers → glibc → libstdc++
- libc: glibc。最初のブートストラップはLFS 12.4に合わせて2.42を使用
- シェルと基本コマンド: BashとGNU Coreutils
- 起動: まずQEMU、後から実機用のカーネル設定と起動メディア
- 配置先: リポジトリ内の`build/rootfs`。ホストの`/usr`にはインストールしない

現段階は構築基盤です。ツールチェーン、起動可能イメージ、パッケージ管理は未実装です。
LFSのバージョン固定は手順の整合性のためであり、公開リリース前には
[セキュリティ勧告](https://www.linuxfromscratch.org/lfs/advisories/)と更新を確認します。

## 開始

```sh
make check-host
make prepare
```

`check-host`は依存コマンド、バージョン、必須リンク、C/C++コンパイルを検査します。
検査に失敗した場合は`prepare`も停止します。`prepare`は構築用ディレクトリと
環境ファイルを作るだけで、ダウンロードやコンパイルは行いません。

ホストを変更せず、専用コンテナを使う場合:

```sh
make builder-image
make builder-check
make builder-shell
# コンテナ内で
make check-host
make prepare
source build/env.sh
```

コンテナは第5・6章の非特権ビルド用です。chrootと起動試験は後続段階で専用VMを使います。
`build/env.sh`はコンテナ内の`/work`を基準に生成されるため、同じコンテナ内で読み込みます。
検証済みのツール一覧は[環境記録](docs/build-environment.md)にあります。
全体の進め方は[構築計画](docs/roadmap.md)を参照してください。
