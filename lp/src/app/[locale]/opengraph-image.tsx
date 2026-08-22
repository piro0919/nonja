import { ImageResponse } from "next/og";

export const alt = "Nonja";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

const PAPER = "#faf9f7";
const INK = "#12142e";
const INK_2 = "#6b6d80";
const INK_3 = "#9a9bab";
const SIGNAL = "#f03a20";
const LINE = "#e6e3dd";

export default async function OgImage({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<ImageResponse> {
  const { locale } = await params;
  const isJa = locale === "ja";

  const rows = isJa
    ? ["通知 / 15:00 から定例です", "通知 / レビュー依頼が届いています", "通知 / ビルドが通りました"]
    : ["Notification / Standup at 15:00", "Notification / Review requested", "Notification / Build passed"];

  return new ImageResponse(
    <div
      style={{
        alignItems: "center",
        background: PAPER,
        display: "flex",
        flexDirection: "column",
        height: "100%",
        justifyContent: "center",
        position: "relative",
        width: "100%",
      }}
    >
      <div
        style={{
          color: INK_3,
          fontSize: 15,
          left: 56,
          letterSpacing: 3,
          position: "absolute",
          top: 52,
        }}
      >
        MACOS · MENU BAR
      </div>
      <div
        style={{
          color: INK_3,
          fontSize: 15,
          letterSpacing: 3,
          position: "absolute",
          right: 56,
          top: 52,
        }}
      >
        NO BANNERS
      </div>

      {/* 溜まっているという印。これ以上は出さない */}
      <div
        style={{
          background: SIGNAL,
          borderRadius: 999,
          height: 14,
          width: 14,
        }}
      />

      <div
        style={{
          color: INK,
          display: "flex",
          flexDirection: "column",
          fontSize: 46,
          fontWeight: 700,
          lineHeight: 1.4,
          marginTop: 34,
          textAlign: "center",
        }}
      >
        {(isJa
          ? ["macOS の通知を、静かに", "溜めておく受信箱です"]
          : ["A quiet inbox for", "your macOS notifications"]
        ).map((line) => (
          <div key={line}>{line}</div>
        ))}
      </div>

      <div
        style={{
          display: "flex",
          flexDirection: "column",
          marginTop: 44,
          width: 620,
        }}
      >
        {rows.map((row, i) => (
          <div
            key={row}
            style={{
              alignItems: "center",
              borderTop: `1px solid ${LINE}`,
              color: INK_2,
              display: "flex",
              fontSize: 20,
              opacity: 1 - i * 0.28,
              padding: "16px 4px",
            }}
          >
            {row}
          </div>
        ))}
      </div>
    </div>,
    { ...size },
  );
}
