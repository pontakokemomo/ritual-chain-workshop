# このリポジトリの読み方（日本語ガイド）

Ritual Academyの宿題「Privacy-Preserving AI Bounty Judge」の成果物リポジトリです。
このファイルは、リポジトリの中身をGitHub上で迷わず読めるようにするための日本語ガイドです。

---

## 1. まず知っておくこと：ブランチが2つある

| ブランチ | 中身 |
|---|---|
| `main` | ワークショップ開始時の元のテンプレート。**一切手を加えていない** |
| `feature/commit-reveal-bounty` | **宿題の成果物はすべてこちら** |

GitHubでリポジトリを開いたとき、左上のブランチ名（プルダウン）が
`feature/commit-reveal-bounty` になっているか必ず確認してください。
`main` を見ていると「中身が何もない」ように見えます。

直接開けるリンク:
`https://github.com/pontakokemomo/ritual-chain-workshop/tree/feature/commit-reveal-bounty`

---

## 2. フォルダ構成

```
ritual-chain-workshop/
├── README.md            ← リポジトリ全体の入口（案内のみ）
├── docs/ja/             ← このガイドを含む日本語資料
├── hardhat/             ← ★宿題の本体はここ★
│   ├── contracts/AIJudge.sol      ← スマートコントラクト本体
│   ├── README.md                  ← 宿題の説明書（英語・初心者向けに平易化済み）
│   ├── TEST_PLAN.md               ← テスト計画
│   ├── ARCHITECTURE_NOTE.md       ← 設計の理由の説明
│   ├── ADVANCED_TRACK_DESIGN.md   ← 上級トラックの設計書（実装なし・設計のみ）
│   ├── ignition/modules/AIJudge.ts ← デプロイ用の設定
│   └── hardhat.config.ts          ← ネットワーク設定（Ritual Testnet接続先など）
└── web/                 ← ブラウザ画面（フロントエンド）
                            ※旧コントラクト仕様のままで現在は未対応。宿題の提出要件外
```

---

## 3. 宿題の要求と成果物の対応表

| 宿題で要求されたもの | どのファイルにあるか |
|---|---|
| commit-reveal対応のSolidityコントラクト | `hardhat/contracts/AIJudge.sol` |
| ライフサイクルを説明するREADME | `hardhat/README.md` |
| リビールの正常系・異常系を含むテスト計画 | `hardhat/TEST_PLAN.md` |
| commit-revealとRitual独自方式を比較する設計ノート | `hardhat/ARCHITECTURE_NOTE.md` と `hardhat/ADVANCED_TRACK_DESIGN.md` |
| リフレクション設問への回答（5〜8文） | `hardhat/README.md` の「Reflection」セクション |

---

## 4. コントラクトの仕組み（超要約）

「答えをコピーされない懸賞コンテスト」を実現する仕組みです。

1. **作成**: 主催者が賞金を預けてコンテストを作る
2. **コミット**: 参加者は答えそのものではなく「答えの指紋（ハッシュ）」だけを提出する。
   封筒に入れて封をするイメージ。中身は誰にも見えない
3. **リビール**: 締切後、参加者が本当の答えと secret（salt）を提出。
   コントラクトが指紋と一致するか検算する。1文字でも違うと不合格
4. **AI審査**: 主催者がRitualのAI機能を呼び出し、公開された答えだけを一括で審査させる
5. **確定**: 主催者が勝者を決定し、賞金が自動送金される

ポイントは「**コミット段階では誰も他人の答えを読めない**」こと。
これで後出しコピーが不可能になります。

---

## 5. デプロイ情報（本番のテストネット上の実物）

| 項目 | 値 |
|---|---|
| チェーン | Ritual Testnet（chain id 1979） |
| コントラクトアドレス | `0xcBE5e9086f53F42586d4Cbb4394Db0721512DD7f` |
| デプロイトランザクション | `0x29d3f549231fb3e08ab9600964af86f8fbe9c907770e215d634374022fdb9188`（ブロック 40,002,921） |

注意: 公式エクスプローラー（explorer.ritualfoundation.org）でこのトランザクションを
検索すると「not found」と表示されることがありますが、これはエクスプローラー側の
インデックスの問題で、トランザクション自体はチェーン上に存在します
（RPCへの直接問い合わせとアドレス計算で検証済み）。

---

## 6. Ritual特有の注意点（ハマりどころ）

- **時刻はミリ秒**: 普通のEVMチェーンは秒単位ですが、Ritualのブロック時刻は
  ミリ秒単位です。締切をコントラクトに渡すときはミリ秒で渡します
- **saltの管理は自己責任**: saltを失くす・弱い乱数で作ると、
  リビールできない・答えを推測される危険があります（詳細は `TEST_PLAN.md` セクション5）
