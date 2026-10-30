# ソースマニフェスト

`toolchain.json`はLFS 12.4第5章のクロスツールチェーン用の入力を固定する。
最終システム全体のパッケージ一覧ではない。

- Binutils、GCC、Linux API headers、glibc
- GCCと一緒に構築するGMP、MPFR、MPC
- glibcのFHSパッチ

libstdc++はGCCアーカイブに含まれるため、別の取得項目はない。

## フィールド

| フィールド | 意味 |
| --- | --- |
| schema_version | マニフェスト形式のバージョン |
| baseline / scope | 参照手順と対象範囲 |
| reference / checksum_reference | 公式の参照元 |
| packages[].name / version | ソース名とバージョン（パッチはリビジョンを含む） |
| kind | archiveまたはpatch |
| filename | sources/内に保存するファイル名 |
| url | LFSの一覧に記載されたHTTPS取得先 |
| sha256 | 取得ファイルから算出したSHA-256 |
| lfs_md5 | LFS 12.4公式一覧との照合に使用したMD5 |
| size_bytes | 圧縮アーカイブまたはパッチのファイルサイズ |

## ハッシュの出所

LFS 12.4の公式[wget-list-sysv](https://www.linuxfromscratch.org/lfs/view/12.4/wget-list-sysv)と
[md5sums](https://www.linuxfromscratch.org/lfs/view/12.4/md5sums)をHTTPSで取得した。
各ソースを記載URLからHTTPSで取得し、LFSのMD5に一致することを確認してから
SHA-256を算出した。SHA-256は上流が公開した値の転記ではない。
MD5はLFSのファイルとの対応確認用であり、今後の整合性検証にはSHA-256を使う。
上流の署名による認証はまだ実施していない。

取得済みのファイルはGit管理外の`sources/`に保持する。
`make fetch`で取得・検証、`make verify-sources`でオフライン検証を実行する。
ビルドレシピは次の工程で実装する。
Linuxの項目はAPIヘッダ用であり、配布する起動カーネルの選定を意味しない。
公開用ビルドへの採用前に、LFSと上流のセキュリティ勧告を確認する。
