# 図の元データ

`img/*.png` の元になる HTML です。ハンズオンの実行には不要です。

- 図は [Kenta-Matsuda/slide-template](https://github.com/Kenta-Matsuda/slide-template) と同じ仕組み（HTML ＋ AWS 公式アイコン ＋ `wires.js` の矢印）で描いています。`diagram.css` と `wires.js` はそのテンプレートのものです。`deepcuts.css` は記事の本文幅に合わせて足した部品です。`iaa.css` と `iaa.js` は、この回の図で共通に使う枠・箱の部品と、座標で水平・垂直の線を引く補助です。
- アイコンは npm パッケージ `aws-icons` の SVG を `img/icons/` にコピーしています。

書き出し方（Chrome か Chromium が必要です）:

```bash
cd img/src
npm install
node render-diagrams.cjs "<Chrome の実行ファイルのパス>"            # すべての図を書き出す
node render-diagrams.cjs "<Chrome の実行ファイルのパス>" architecture  # 1 つだけ書き出す
```
