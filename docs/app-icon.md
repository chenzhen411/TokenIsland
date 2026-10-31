# TokenIsland 应用图标

图标使用内置 imagegen 生成，原稿为 `Resources/AppIcon.png`（1024 × 1024，RGBA）。深石墨底与薄荷绿玻璃胶囊呼应应用本身；三根柱形代表用量，圆点代表 Token 与额度。

构建应用时，`scripts/build-icon.sh` 使用 macOS `sips` 和 `iconutil` 生成 16、32、128、256、512 pt 的普通及 Retina 图标，再通过 `CFBundleIconFile` 注册到应用。也可以独立执行：

```sh
./scripts/build-icon.sh
```

独立执行输出 `dist/AppIcon.icns`。透明边缘与留白保留在所有尺寸中。

## 生成提示词

工具：内置 imagegen，`transparent_background: true`。最终提示词：

> Use case: logo-brand. Asset: final macOS application icon for TokenIsland, a minimalist floating Dynamic Island token-usage monitor. Produce exactly ONE finished icon, square 1024x1024, front-facing and centered, no presentation board. Transparent canvas outside the macOS rounded-square tile. Tile occupies approximately 84 percent of canvas, with smoothly continuous macOS squircle corners. Rich near-black graphite tile, very subtle satin depth and tasteful thin edge highlight. A single distinctive horizontal pill-shaped island sits centered, slightly elevated, rendered as beautifully polished dark translucent glass with an emerald/mint luminous rim. Within this capsule, three bold softly rounded mint energy bars form a simple ascending usage silhouette, paired with one small luminous circular token on the right separated by generous space. Make the capsule a strong, simple, memorable silhouette visible at 32px. Use mint green close to #7AE8C2 and restrained cool emerald highlights consistent with a black/mint native Mac app. Sophisticated native macOS craftsmanship, soft restrained 3D bevel, clean premium utility icon, crisp geometry. Generous negative space, strong contrast, subtle shadow under the capsule. Do not add any letters, words, numerals, charts with axes, tiny details, robot, palm tree, Apple logo, OpenAI logo, watermarks, or multiple icons. No white backdrop, no scene, no perspective skew. Actual transparent alpha outside the tile and its subtle shadow.
