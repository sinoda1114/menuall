# MenuAll アプリアイコン生成記録

- 生成日: 2026-09-02
- 方式: Codex組み込み`image_gen`（logo-brand）
- 用途: macOSアプリアイコンの128〜1024px原画

## 最終プロンプト

```text
Use case: logo-brand
Asset type: macOS application icon master artwork for MenuAll
Primary request: Create a polished, minimal macOS app icon that communicates “press once and see every menu bar item.”
Scene/backdrop: A single centered rounded-square macOS icon tile, no surrounding scene.
Subject: A simplified top menu-bar strip with a subtle central notch silhouette; several tiny circular and square menu-status symbols that appear constrained on the strip and visually gather downward into one clear compact 3-by-2 grid panel. The convergence should feel organized and immediate, not busy.
Style/medium: Vector-friendly geometric icon rendered as crisp premium digital artwork, consistent with modern macOS icon aesthetics.
Composition/framing: Symmetrical, centered, generous padding, strong silhouette that remains legible at 32 px. Use one coherent symbol, not multiple separate illustrations.
Lighting/mood: Soft restrained depth, calm and trustworthy.
Color palette: Deep graphite-to-indigo rounded tile with a subtle cool blue highlight; foreground symbol in clean off-white with one restrained cyan accent.
Materials/textures: Very subtle satin/glass depth, crisp edges, no photorealistic objects.
Constraints: square 1024x1024; no text, no letters, no Apple logo, no watermark; do not include a border outside the rounded-square tile; avoid overly thin strokes; preserve a clear recognizable silhouette at small sizes.
Avoid: mockup devices, screenshots, tiny illegible details, gradients outside the icon tile, excessive glow, neon cyberpunk styling.
```

## 現行デザイン

上記の生成原画は初期案として不採用とし、現行アセットには使用しない。

現行の[MenuAll-AppIcon.svg](MenuAll-AppIcon.svg)は、生成画像を使わず手作業で構成したフラットなベクターである。グラデーション、影、光沢、立体表現を使わず、上部に並ぶ項目を4つのピルへ抽象化し、V字と6つのタイルで「一覧を開く」機能を表す。白とアジュールブルーの2色を使い、16〜1024pxの全スロットを同じベクター原画から生成する。
