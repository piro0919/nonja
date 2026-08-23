import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { ImageResponse } from "next/og";
import { routing } from "@/i18n/routing";

export const alt = "Nonja";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

/* ビルド時に焼く。動的なままだと public/ が関数側に含まれず、
   本番で icon.png を読めずに 500 になる */
export function generateStaticParams(): { locale: string }[] {
  return routing.locales.map((locale) => ({ locale }));
}

/* 実在のアプリ（Linear / Arc / CleanShot / Setapp）の作りに合わせる。
   ブランド色の地に、アイコンと名前と短い一行だけ。説明文は入れない。
   色はアイコンから取る。忍者なので地は藍、文字は覆面のクリーム */
const FIELD = "#191c47";
const PAPER = "#f2f0e9";
const MUTED = "rgba(242, 240, 233, 0.6)";

export default async function OgImage({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<ImageResponse> {
  const { locale } = await params;
  const isJa = locale === "ja";
  const [icon, font] = await Promise.all([
    readFile(join(process.cwd(), "public/icon.png")),
    readFile(join(process.cwd(), "assets/ZenKakuGothicNew-Black-subset.ttf")),
  ]);
  const iconSrc = `data:image/png;base64,${icon.toString("base64")}`;

  return new ImageResponse(
    <div
      style={{
        alignItems: "center",
        background: FIELD,
        display: "flex",
        flexDirection: "column",
        height: "100%",
        justifyContent: "center",
        width: "100%",
      }}
    >
      {/* biome-ignore lint/performance/noImgElement: next/image is not available in ImageResponse */}
      <img alt="" height={210} src={iconSrc} width={210} />
      <div
        style={{
          color: PAPER,
          display: "flex",
          fontSize: 104,
          letterSpacing: -2,
          marginTop: 34,
        }}
      >
        Nonja
      </div>
      <div style={{ color: MUTED, display: "flex", fontSize: 32, marginTop: 18 }}>
        {isJa ? "通知を、静かに溜めておく受信箱" : "A quiet inbox for your notifications"}
      </div>
    </div>,
    {
      ...size,
      fonts: [
        { data: font, name: "Zen Kaku Gothic New", style: "normal", weight: 900 },
      ],
    },
  );
}
