# 検証済みのビルド環境

2026-10-30、x86_64のrootless Podmanコンテナで`make check-host prepare`が成功。
CおよびC++プログラムのコンパイルと実行も成功した。

| ツール | バージョン |
| --- | --- |
| GCC / G++ | 14.2.0 |
| Binutils | 2.44 |
| Bash | 5.2.37 |
| Bison | 3.8.2 |
| GNU Awk | 5.2.1 |
| GNU Make | 4.4.1 |
| M4 | 1.4.19 |
| Patch | 2.8 |
| Texinfo | 7.1.1 |
| Python | 3.13.5 |
| Perl | 5.40.1 |
| Xz | 5.8.1 |

shはBash、awkはGNU Awk、yaccはBisonとして検査済み。
ホストのFedoraパッケージは変更していない。

Debian 13のベースイメージはDockerfileでdigest固定した。
aptの取得先は更新されるため、再ビルド後は`make builder-check`で再検査する。
これは取得する全パッケージのバージョンを厳密に固定する仕組みではない。
現在のローカルイメージID:

```
59ed9303db6d34039b49147b9554373559756b3897839c4f5afacf6a93e109da
```

ここで用意したのはブートストラップ用のホストツール。
Lightnix向けのGCCとglibcは、このホストツールからソース構築する。

## クロスGCCの検証結果

2026-10-30、`gcc-bootstrap`レシピでGCC 15.2.0と同梱するGMP/MPFR/MPCを構築し、
`build/rootfs/tools`へインストールした。コンパイルとインストールは約25分。

- ターゲット: `x86_64-lfs-linux-gnu`
- sysroot: コンテナ内の`/work/build/rootfs`
- C/C++両コンパイラのバージョン、ターゲット、sysrootを検証
- クロスBinutilsのアセンブラとリンカを使用することをファイル実体で確認
- C/C++からELF64・x86_64の再配置可能オブジェクトを生成
- LFSの手順に従い、内部ヘッダの`limits.h`を補完

ビルド完了後、検証処理のパス比較を修正し、`verify-gcc-bootstrap.sh`を再実行して成功。
glibc、libstdc++、通常の実行ファイルのリンクは後続工程。
GCCの公式テストスイートは未実行。

## Linux APIヘッダの検証結果

2026-10-30、`make linux-headers`でマニフェストに固定したLinux 6.16.1から
x86向けAPIヘッダを生成した。ソースのSHA-256を検証した後、1,018個の`.h`を
`build/rootfs/usr/include`に配置し、すべてコピー元と一致することを確認した。

クロスGCCの`-nostdinc`と明示したインクルードパスで、Linux型定義、asmの
システムコール定義、およびマニフェストのバージョンと`LINUX_VERSION_CODE`の一致を
コンパイル検証。出力はELF64/x86_64の再配置可能オブジェクトだった。
カーネル本体は構築していない。

## glibcの検証結果

2026-10-30、`make glibc-bootstrap`でglibc 2.42とFHSパッチをSHA-256検証して
構築し、`DESTDIR=/work/build/rootfs`でインストールした。最低対応カーネルは5.4。
コンパイルとインストールは約8分。

- Cプログラムによりglibcヘッダのバージョンをコンパイル時に確認
- インクルード検索先がLightnixのrootfs内であることを検証
- 起動用オブジェクト`Scrt1.o`、`crti.o`、`crtn.o`と`libc.so.6`の実際のリンク先を検証
- リンカの検索ディレクトリがsysroot基準であることを検証
- ELFのインタープリタが`/lib64/ld-linux-x86-64.so.2`であることを確認
- rootfs内のリンクがインストール済み動的ローダを指すことを確認
- `libc.so.6`への依存と、RPATH/RUNPATHを埋め込んでいないことを確認

リンクの詳細は作業先の`link.log`に保持している。生成したプログラムとglibcの
公式テストスイートは実行していない。次はlibstdc++を構築する。

## libstdc++の検証結果

2026-10-30、`make libstdcxx-bootstrap`でGCC 15.2.0のソースをSHA-256検証し、
そこからlibstdc++を構築して`DESTDIR=/work/build/rootfs`でインストールした。
コンパイルとインストールは約1分。LFSの手順に従い、対象ライブラリの`.la`を削除した。

- vector、string、algorithm、iostreamを使うC++プログラムをコンパイル・リンク
- `_GLIBCXX_RELEASE`がマニフェストのGCCメジャーバージョンに一致することを確認
- 標準ヘッダの検索先がrootfs内であることを検証
- libstdc++とlibcの実際のリンク先がrootfs内であることを検証
- ELFの動的ローダと`libstdc++.so.6`、`libc.so.6`への依存を確認
- sysroot基準のリンカ検索先と、RPATH/RUNPATHを埋め込んでいないことを確認

生成したプログラムと公式テストスイートは実行していない。
これでLFS第5章のクロスツールチェーンの構築とリンク検証が揃った。

## 一時ツールM4の検証結果

2026-10-30、`make m4-bootstrap`でM4 1.4.20をクロスコンパイルし、rootfsに
インストールした。公式ソースはLFSのMD5との一致を確認してからSHA-256を記録した。

- インストールしたバイナリとビルド結果が一致
- ELF64/x86_64、動的ローダのパス、libc依存、RPATH/RUNPATHの不在を確認
- Lightnixの動的ローダでライブラリキャッシュを無効にし、rootfs側のlibcへの解決を検証
- 同じローダを使ったバージョン表示が1.4.20に一致
- defineマクロの展開結果が`Lightnix`になることを実行して確認

chroot・起動試験およびM4公式テストスイートは未実行。
