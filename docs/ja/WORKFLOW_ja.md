# 作業工程まとめ（フォークから提出まで）

Ritual Academyの宿題を完成させるまでに実際に行った作業を、順番に記録したものです。
同じことをもう一度やるとき、または他の人に説明するときの手順書として使えます。

---

## 全体の流れ

```
①フォーク → ②ブランチ作成 → ③環境構築 → ④コントラクト実装
→ ⑤コンパイル → ⑥鍵と資金の準備 → ⑦デプロイ → ⑧オンチェーン検証
→ ⑨ドキュメント作成 → ⑩push → ⑪Discordで提出
```

---

## ① リポジトリをフォークする

講師提供の元リポジトリ（`cozfuttu/ritual-chain-workshop`）を
自分のGitHubアカウントにフォーク（自分用のコピーを作成）した。

## ② 作業用ブランチを作成する

`main` ブランチは元のテンプレートのまま残し、
`feature/commit-reveal-bounty` という作業用ブランチを作って、
宿題の変更はすべてそちらで行った。

理由: 元の状態と自分の変更を比較できるようにするため。
「どこを変えたのか」が後から一目で分かる。

```
git checkout -b feature/commit-reveal-bounty
```

## ③ 環境構築

- `.gitignore` を確認し、秘密鍵などが誤ってGitHubに上がらないことを確認
- `pnpm install` で依存パッケージをインストール
- `hardhat.config.ts` にRitual Testnetの接続設定を追加
  （RPC: `https://rpc.ritualfoundation.org`、chain id: 1979）

## ④ コントラクト実装（宿題の本体）

`contracts/AIJudge.sol` を、答えが即公開される旧方式から
commit-reveal方式に書き換えた。

宿題で必須とされた4つの関数をすべて実装:

- `submitCommitment(bountyId, commitment)` … ハッシュだけを提出
- `revealAnswer(bountyId, answer, salt)` … 答えとsaltを公開して検証
- `judgeAll(bountyId, llmInput)` … RitualのAIで一括審査（1回の呼び出しで全員分）
- `finalizeWinner(bountyId, winnerIndex)` … 勝者確定と賞金支払い

追加した安全策:

- ハッシュに `msg.sender`（本人のアドレス）と `bountyId` を混ぜ、
  他人のコミットメントをコピーして流用する攻撃を防止
- 1人1コミットまで、1コンテスト最大10件、答えは最大2,000バイトの制限
- フェーズ順序の強制（締切前のリビール、審査前の確定などはすべて拒否）

## ⑤ コンパイル

```
npx hardhat compile
```

エラーなくコンパイルできることを確認した。

## ⑥ 鍵と資金の準備

- 宿題専用の使い捨てウォレットを用意
- 秘密鍵は `hardhat-keystore` に登録（ファイルに直接書かない）

```
npx hardhat keystore set DEPLOYER_PRIVATE_KEY
```

- テストネットトークンを入手し、Ritual Wallet（AI利用料の前払い口座）に入金

## ⑦ デプロイ

```
npx hardhat ignition deploy --network ritual ignition/modules/AIJudge.ts
```

結果: `0xcBE5e9086f53F42586d4Cbb4394Db0721512DD7f` にデプロイ成功。

## ⑧ オンチェーン検証

デプロイが本物であることを複数の方法で確認した。

- `eth_getCode` でチェーン上のバイトコードがコンパイル結果と一致することを確認
- `nextBountyId()` を読み出して初期値 `1` が返ることを確認
- デプロイトランザクションのハッシュを特定:
  `0x29d3f549231fb3e08ab9600964af86f8fbe9c907770e215d634374022fdb9188`
  （ローカルの記録が不完全だったため、RPCでブロックを直接調べて特定。
  送信者アドレス＋nonceからのアドレス計算で、このトランザクションが
  当該コントラクトを生成したことを数学的に確認済み）

### ここでハマったこと（記録）

- **Ritualの時刻はミリ秒単位**（普通のチェーンは秒）。ドキュメントに明記した
- **公式エクスプローラーが古いトランザクションを表示できない**ことがある。
  「not found」と出てもチェーン上には存在する。RPC直接問い合わせが確実
- RPCはバッチリクエストや一部のUser-Agentを拒否する（403エラー）

## ⑨ ドキュメント作成

宿題の提出要件に合わせて以下を作成した。

| ファイル | 内容 |
|---|---|
| `hardhat/README.md` | ライフサイクル説明・用語集・Reflection回答 |
| `hardhat/TEST_PLAN.md` | 状態遷移・境界値・異常系のテスト計画 |
| `hardhat/ARCHITECTURE_NOTE.md` | commit-revealを選んだ理由と公開範囲の整理 |
| `hardhat/ADVANCED_TRACK_DESIGN.md` | TEEを使う上級トラックの設計書（設計のみ） |

## ⑩ コミットしてpushする

```
git add <ファイル>
git commit -m "変更内容の説明"
git push -u origin feature/commit-reveal-bounty
```

リポジトリが公開設定（public）であることも確認した。

## ⑪ Discordで提出（Proof of Building）

DiscordのRitual Assistant Botのフォームから提出。

- **Step 1**: GitHubフォークのURL・コントラクトアドレス・
  デプロイトランザクションハッシュ・苦労した点
- **Step 2**: 遭遇したエラーと対処・総合評価（1〜10）・Loom録画URL（任意）
