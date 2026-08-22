import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { ImageResponse } from "next/og";

export const alt = "Nonja";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

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
  const icon = await readFile(join(process.cwd(), "public/icon.png"));
  const iconSrc = `data:image/png;base64,${icon.toString("base64")}`;

  return new ImageResponse(
    <div
      style={{
        alignItems: "center",
        background: PAPER,
        display: "flex",
        gap: 64,
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
      <div style={{ display: "flex", flexDirection: "column" }}>
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
    { ...size },
  );
}
