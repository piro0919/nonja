import { Analytics } from "@vercel/analytics/next";
import type { Metadata } from "next";
import { Inter, Zen_Kaku_Gothic_New } from "next/font/google";
import { notFound } from "next/navigation";
import { hasLocale, NextIntlClientProvider } from "next-intl";
import { getTranslations, setRequestLocale } from "next-intl/server";
import type { ReactNode } from "react";
import { routing } from "@/i18n/routing";
import { languageAlternates, localePath, ogAlternateLocales, ogLocale } from "@/i18n/urls";
import "./globals.css";

// 静かに使う道具の話なので、字面も素直なゴシックにする
const sans = Inter({
  display: "swap",
  subsets: ["latin"],
  variable: "--font-sans",
});

/* 見出しの書体。忍者の印象に明朝は合わないので角ゴシック。
   日本語は unicode-range で百件以上に割れるので preload は切る。
   切らないと使わない範囲まで先読みして 1ページで 1.5MB 取りに行く */
const display = Zen_Kaku_Gothic_New({
  display: "swap",
  preload: false,
  subsets: ["latin"],
  variable: "--font-display",
  weight: ["500", "700"],
});

type LayoutProps = {
  children: ReactNode;
  params: Promise<{ locale: string }>;
};

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

export async function generateMetadata({
  params,
}: Omit<LayoutProps, "children">): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "meta" });

  return {
    description: t("description"),
    icons: { icon: "/icon.png" },
    alternates: {
      canonical: localePath(locale),
      languages: languageAlternates(),
    },
    metadataBase: new URL("https://nonja.kkweb.io"),
    openGraph: {
      locale: ogLocale(locale),
      alternateLocale: ogAlternateLocales(locale),
      description: t("description"),
      title: t("title"),
      type: "website",
      url: localePath(locale),
    },
    title: t("title"),
    twitter: {
      card: "summary_large_image",
      description: t("description"),
      title: t("title"),
    },
  };
}

export default async function Layout({ children, params }: LayoutProps) {
  const { locale } = await params;

  if (!hasLocale(routing.locales, locale)) {
    notFound();
  }
  setRequestLocale(locale);

  return (
    <html className={`${sans.variable} ${display.variable}`} lang={locale}>
      <body className="font-[family-name:var(--font-sans)] antialiased">
        <NextIntlClientProvider>{children}</NextIntlClientProvider>
        <Analytics />
      </body>
    </html>
  );
}
