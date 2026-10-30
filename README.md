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

現段階ではBinutils・GCC・Linux APIヘッダ・glibc・libstdc++のブートストラップ構築と
C/C++プログラムのリンク検証に対応しています。起動可能イメージ、パッケージ管理は未実装です。
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
クロスツールチェーンのソースは[マニフェスト](manifests/toolchain.json)に固定し、
ハッシュの出所と対象範囲は[説明](manifests/README.md)に記録しています。
全体の進め方は[構築計画](docs/roadmap.md)を参照してください。

## ソースの取得と検証

```sh
make fetch
make verify-sources
```

Python 3の標準ライブラリでマニフェストを読み、HTTPSで`sources/`へ取得します。
取得済みのファイルはサイズとSHA-256を確認して再利用します。
不一致なら停止し、自動で上書きしません。内容を確認して対象ファイルを移動した後に
`make fetch`を再実行してください。

ダウンロードは`.part`に保存し、検証成功後に正式な名前へ変更します。
失敗した`.part`は保持し、次回は最初から取得し直します。
`verify-sources`は通信せず、不足・不一致があれば失敗します。
`fetch`の同時実行はロックで拒否します。

## Binutils pass 1

```sh
make fetch
make binutils-bootstrap
```

`make builder-image`で作成した専用コンテナを使い、LFS 12.4第5.2節の設定で
Binutils 2.45を構築します。ホスト検査と構築先の準備を行い、マニフェストの
Binutilsを検証してから展開します。ネットワークによる自動取得は行いません。

インストール先は`build/rootfs/tools`です。アセンブラ・リンカのバージョン、
ターゲット、sysrootを検証し、小さなアセンブリをELF64/x86_64実行形式にリンクして
ヘッダを確認します。これはBinutilsの動作確認で、公式テストスイートの実行ではありません。

ログは`build/logs/binutils-bootstrap.*.log`、ソースとビルド結果は
`build/work/binutils-bootstrap.*`に保持します。成功後に`build/stamps/binutils-bootstrap.success`へ
ログと作業先を記録します。再実行時は新しい作業先で再構築して同じtoolsへインストールし、
古い作業先は残します。後続のツールチェーン構築を始めた後の再実行は避けてください。

## GCCブートストラップ

```sh
make gcc-bootstrap
```

構築済みのBinutilsが必要です。専用コンテナ内でGCC・GMP・MPFR・MPCのSHA-256を
検証して展開し、GCCのソース内に依存ライブラリを配置します。バージョンとglibcの
設定値はマニフェストから読み取ります。LFS 12.4第5.3節に従ってC/C++用の
クロスコンパイラを`build/rootfs/tools`へインストールし、内部の`limits.h`を補完します。

バージョン・ターゲット・sysroot・使用するアセンブラとリンカを検査し、C/C++から
ELF64/x86_64オブジェクトを生成します。glibcとlibstdc++は未構築なので、標準ライブラリを
使うプログラムのリンクは後続工程で検証します。公式テストスイートは実行しません。

ログは`build/logs/gcc-bootstrap.*.log`、ソースとビルド結果は
`build/work/gcc-bootstrap.*`、成功記録は`build/stamps/gcc-bootstrap.success`です。
失敗時も作業先とログを保持し、再実行は新しい作業先で行います。
後続工程を始めた後の再実行は避けてください。

## Linux APIヘッダ

```sh
make linux-headers
```

構築済みのクロスGCCを使い、専用コンテナ内でLinuxソースを検証・展開します。
バージョンはマニフェストから読み取ります。LFS 12.4第5.4節に従い、
`make mrproper`と`make headers`でx86向けAPIヘッダを生成し、`.h`ファイルだけを
`build/rootfs/usr/include`へコピーします。カーネル本体はコンパイルしません。

コピー元と配置先の全ヘッダを比較し、必要なLinux/asmヘッダを確認します。
ホストのインクルードパスを無効にしたクロスGCCで、型・システムコール定義・
マニフェストに対応するAPIバージョンをコンパイル検証します。

ログは`build/logs/linux-headers.*.log`、作業先は`build/work/linux-headers.*`、
成功記録は`build/stamps/linux-headers.success`に保存します。
再実行は新しい作業先を使い、同じ配置先へ上書きします。別バージョンへの更新では
古いヘッダを自動削除しないため、新しいrootfsから構築してください。

## glibcブートストラップ

```sh
make glibc-bootstrap
```

クロスGCCとLinux APIヘッダが必要です。専用コンテナ内で、マニフェストに固定した
glibcと対応するFHSパッチのSHA-256を検証し、パッチを適用して構築します。
最低対応カーネルは`config/toolchain.env`で管理します。
LFS 12.4第5.5節に従い、`DESTDIR`を`build/rootfs`に指定してインストールします。

x86_64向けローダのリンクと`ldd`のパスを整え、Cプログラムをコンパイル・リンクします。
ヘッダ、起動用オブジェクト、libc、ローダ、リンカの検索先がLightnix側であることを
確認します。生成したプログラムはこの段階では実行せず、公式テストスイートも実行しません。

ログは`build/logs/glibc-bootstrap.*.log`、作業先は`build/work/glibc-bootstrap.*`、
リンクの詳細は作業先の`link.log`、成功記録は`build/stamps/glibc-bootstrap.success`です。
再実行は新しい作業先を使い、同じrootfsへ上書きします。
後続工程の開始後や別バージョンへの更新では、新しいrootfsから構築してください。

## libstdc++ブートストラップ

```sh
make libstdcxx-bootstrap
```

クロスGCCとglibcが必要です。マニフェストのGCCアーカイブをSHA-256検証し、
新しい作業先に展開して、その中のlibstdc++をLFS 12.4第5.6節に従って構築します。
GCCのバージョンを直書きせず、標準ヘッダのインストール先にもマニフェストの値を使います。
`DESTDIR`は`build/rootfs`です。ライブラリは`usr/lib`、標準ヘッダはクロスGCCが
参照する`tools/<ターゲット>/include/c++/<バージョン>`に配置します。

クロスコンパイルの妨げになるlibtoolの`.la`を対象ライブラリから削除した後、
vector・string・algorithm・iostreamを使うC++プログラムをリンクします。
ヘッダとlibstdc++・libcの参照先、動的ローダ、ELFの依存ライブラリを検証します。
生成したプログラムと公式テストスイートは、この段階では実行しません。

ログは`build/logs/libstdcxx-bootstrap.*.log`、作業先は`build/work/libstdcxx-bootstrap.*`、
リンクの詳細は作業先の`link.log`、成功記録は`build/stamps/libstdcxx-bootstrap.success`です。
再実行は新しい作業先から同じrootfsへ上書きします。後続工程の開始後やバージョン変更時は、
新しいrootfsから構築してください。

## 一時ツール: M4

```sh
make fetch
make m4-bootstrap
```

第6章のソースは`manifests/temporary-tools.json`で管理します。
M4は専用コンテナでクロスコンパイルし、`DESTDIR`を`build/rootfs`に指定して
`usr/bin/m4`などへインストールします。バージョンと取得先はマニフェストで管理します。

配置したバイナリとビルド結果の一致、ELF64/x86_64形式、動的ローダとlibc依存を確認します。
同じx86_64ホスト上でLightnixの動的ローダを明示し、ライブラリキャッシュを無効にして
rootfs内のライブラリを使用したバージョン表示とマクロ展開も検証します。
これはchrootや起動試験ではなく、M4の公式テストスイートも実行しません。

ログは`build/logs/m4-bootstrap.*.log`、作業先は`build/work/m4-bootstrap.*`、
動的ライブラリの解決結果は作業先の`libraries.log`、成功記録は
`build/stamps/m4-bootstrap.success`です。再実行時は新しい作業先で構築します。

## 一時ツール: Ncurses

```sh
make fetch
make ncurses-bootstrap
```

LFS 12.4第6.3節に従い、まずホスト用`tic`を構築し、`build/rootfs/tools/bin`へ
インストールします。続いて別のビルドディレクトリでLightnix向けの共有ライブラリ、
C++共有バインディング、ヘッダ、端末データベースを構築してrootfsへ配置します。
ソースとバージョンは一時ツールのマニフェストで管理します。

`libncurses.so`は`libncursesw.so`へのリンクとし、`curses.h`もwide-character ABIを
使うようLFSの手順どおりに調整します。ホスト用`tic`のバージョンと、標準ヘッダ、
ライブラリ、ELF形式、動的ローダを検証します。さらにLightnixのローダとライブラリを
明示してサンプルを実行し、rootfsのterminfoからxtermの端末情報を取得できることを確認します。
対話的な画面描画、chroot、公式テストスイートは検証対象に含めません。

ログは`build/logs/ncurses-bootstrap.*.log`、作業先は`build/work/ncurses-bootstrap.*`、
リンクと実行時ライブラリの詳細は作業先の`link.log`と`libraries.log`、
成功記録は`build/stamps/ncurses-bootstrap.success`です。

## 一時ツール: Bash

```sh
make fetch
make bash-bootstrap
```

一時ツールのマニフェストからBashソースとバージョンを読み、SHA-256検証後に
新しい作業先へ展開します。LFS 12.4第6.4節に従って`--without-bash-malloc`で
クロスコンパイルし、`DESTDIR`をrootfsに指定して`usr/bin/bash`へ配置します。
`usr/bin/sh`から`bash`への相対リンクを作り、既存の`bin -> usr/bin`経由でも使用します。

インストール結果とビルドしたバイナリの一致、ELF形式、動的ローダ、Ncursesとglibcの
実行時参照先を検証します。Lightnixのローダを明示し、起動設定を読み込まず、ホストの
外部コマンドをPATHから除いた状態で、変数・配列・算術・コマンド置換・ループ・
printfとshリンク経由の実行を確認します。
対話的シェル、chroot、Bash公式テストスイートは検証対象に含めません。

ログは`build/logs/bash-bootstrap.*.log`、作業先は`build/work/bash-bootstrap.*`、
ライブラリ解決結果は作業先の`libraries.log`、成功記録は
`build/stamps/bash-bootstrap.success`です。
