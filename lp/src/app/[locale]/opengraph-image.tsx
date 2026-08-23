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

/* 実際に出るのは kk-web の一覧で176px、X のカードで500px 前後。
   その大きさで残るのはアイコンと名前と1行だけなので、それしか置かない。
   地はアイコンと同じ生成り */
const PAPER = "#f5f1ec";
const INK = "#15173b";
const SIGNAL = "#f03a20";

export default async function OgImage({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<ImageResponse> {
  const { locale } = await params;
  const isJa = locale === "ja";
  /* 見出しの書体はサイトと同じ Zen Old Mincho。使う文字だけに絞ったものを
     同梱している。文言を変えたら assets/README.md の手順で作り直す */
  const [icon, font] = await Promise.all([
    readFile(join(process.cwd(), "public/icon.png")),
    readFile(join(process.cwd(), "assets/ZenOldMincho-SemiBold-subset.ttf")),
  ]);
  const iconSrc = `data:image/png;base64,${icon.toString("base64")}`;

  return new ImageResponse(
    <div
      style={{
        alignItems: "center",
        flexDirection: "column",
        justifyContent: "center",
        background: PAPER,
        display: "flex",
        gap: 32,
        height: "100%",
        padding: "0 90px",
        width: "100%",
      }}
    >
      {/* biome-ignore lint/performance/noImgElement: next/image is not available in ImageResponse */}
      <img
        alt=""
        height={300}
        src={iconSrc}
        style={{ borderRadius: 68 }}
        width={300}
      />
      <div
        style={{
          alignItems: "center",
          display: "flex",
          flexDirection: "column",
          textAlign: "center",
        }}
      >
        <div
          style={{
            color: INK,
            fontSize: 128,
            fontWeight: 700,
            letterSpacing: -3,
          }}
        >
          Nonja
        </div>
        <div style={{ color: SIGNAL, display: "flex", fontSize: 38, marginTop: 18 }}>
          {isJa
            ? "通知を、静かに溜めておく受信箱"
            : "A quiet inbox for your notifications"}
        </div>
      </div>
    </div>,
    {
      ...size,
      fonts: [
        { data: font, name: "Zen Old Mincho", style: "normal", weight: 600 },
      ],
    },
  );
}
