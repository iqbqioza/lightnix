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
