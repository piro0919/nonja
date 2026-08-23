import Image from "next/image";
import { getTranslations, setRequestLocale } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { LanguageSwitch } from "./language-switch";

const REPO = "https://github.com/piro0919/nonja";
const DOWNLOAD = `${REPO}/releases/latest`;

type Item = { title: string; body: string };

type PageProps = { params: Promise<{ locale: string }> };

export default async function Page({ params }: PageProps) {
  const { locale } = await params;
  setRequestLocale(locale);

  const t = await getTranslations();
  const features = t.raw("features.items") as Item[];

  return (
    <>
      <header className="mx-auto flex max-w-6xl items-center justify-between px-6 py-6">
        <div className="flex items-center gap-2.5">
          <Image
            alt=""
            className="rounded-[24%]"
            height={26}
            src="/icon.png"
            width={26}
          />
          <span className="font-bold text-sm tracking-tight">Nonja</span>
        </div>
        <LanguageSwitch />
      </header>

      {/* 入手までを最初の画面に収める。同種のメニューバー常駐アプリは
          どれもボタンを一枚目に置いていて、Nonja だけ 900px 下にあった */}
      <main className="mx-auto grid max-w-6xl gap-12 px-6 pt-8 pb-20 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.15fr)] lg:items-center lg:gap-16 lg:pt-14">
        <div className="min-w-0">
          <Image
            alt=""
            className="rounded-[24%]"
            height={92}
            priority={true}
            src="/icon.png"
            width={92}
          />
          <h1 className="mt-7 text-balance font-display font-bold text-3xl leading-[1.4] tracking-tight sm:text-4xl">
            {t("hero.title")}
          </h1>
          <p className="mt-6 max-w-md text-ink-2 leading-relaxed">
            {t("hero.tagline")}
          </p>

          <div className="mt-9 flex flex-col gap-3 sm:flex-row">
            <a
              className="bg-ink px-8 py-3.5 text-center font-bold text-paper transition hover:bg-indigo"
              href={DOWNLOAD}
            >
              {t("hero.download")}
            </a>
            <a
              className="border border-line px-8 py-3.5 text-center font-bold transition hover:border-ink"
              href={REPO}
            >
              {t("hero.source")}
            </a>
          </div>
          <p className="mt-5 text-ink-3 text-sm leading-relaxed">
            {t("hero.note")}
            <br />
            {t("hero.firstRun")}
            <a
              className="ml-1.5 underline underline-offset-2 transition hover:text-ink"
              href={`${REPO}#installing`}
            >
              {t("hero.firstRunLink")}
            </a>
          </p>
        </div>

        {/* メニューバーの下に出る、という位置の関係ごと見せる。
            同じ中身の一覧を2枚並べていたのをやめた */}
        <div className="min-w-0">
          <Image
            alt={t("screens.list")}
            className="w-full"
            height={640}
            priority={true}
            src="/menubar.png"
            width={1120}
          />
        </div>
      </main>

      <section className="border-line border-t">
        <div className="mx-auto max-w-6xl px-6 py-16">
          <h2 className="text-ink-3 text-xs tracking-wider">
            {t("features.title")}
          </h2>
          <dl className="mt-8 grid gap-x-10 gap-y-10 sm:grid-cols-2 lg:grid-cols-4">
            {features.map((item) => (
              <div key={item.title}>
                <dt className="font-display font-bold text-base">
                  {item.title}
                </dt>
                <dd className="mt-2.5 text-ink-2 text-sm leading-relaxed">
                  {item.body}
                </dd>
              </div>
            ))}
          </dl>
        </div>
      </section>

      <footer className="mx-auto max-w-6xl px-6 py-10 text-center text-ink-3 text-xs">
        <a className="underline" href={REPO}>
          {t("footer.source")}
        </a>
        <span className="px-2">·</span>
        <Link className="underline" href="/privacy">
          {t("footer.privacy")}
        </Link>
      </footer>
    </>
  );
}
