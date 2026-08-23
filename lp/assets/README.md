# assets

`ZenKakuGothicNew-Black-subset.ttf` is the face drawn into the Open Graph card
(`src/app/[locale]/opengraph-image.tsx`). It is the same display face the site
uses for its headings, cut down to the characters the card actually shows.

Any character missing from it silently falls back to a different face, so when
the card's copy changes, rebuild the subset:

```sh
curl -sL -o /tmp/ZenKakuGothicNew-Black.ttf \
  "https://github.com/google/fonts/raw/main/ofl/zenkakugothicnew/ZenKakuGothicNew-Black.ttf"

pyftsubset /tmp/ZenKakuGothicNew-Black.ttf \
  --text="Nonja 通知を、静かに溜めておく受信箱 A quiet inbox for your notifications MACOS MENU BAR" \
  --unicodes="U+0020-007E,U+00A0-00FF,U+2010-2027,U+3000-303F,U+30FB" \
  --output-file=assets/ZenKakuGothicNew-Black-subset.ttf \
  --no-hinting --desubroutinize --layout-features=''
```
