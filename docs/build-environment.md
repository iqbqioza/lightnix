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
Lightnix向けのGCC 15.2.0とglibc 2.42は、これからソースから構築する。
