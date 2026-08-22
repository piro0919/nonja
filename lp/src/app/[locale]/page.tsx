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
            height={24}
            src="/icon.png"
            width={24}
          />
          <span className="font-bold text-sm tracking-tight">Nonja</span>
        </div>
        <LanguageSwitch />
      </header>

      {/* 中央の細い一列に全部を積む。両脇の余白は空けたままにして、
          端に小さな注記だけを置く */}
      <main className="relative mx-auto max-w-6xl px-6">
        <span className="margin-note absolute top-24 left-6 hidden text-ink-3 lg:block">
          macOS
          <br />
          Menu bar
        </span>
        <span className="margin-note absolute top-24 right-6 hidden text-right text-ink-3 lg:block">
          No banners
          <br />
          No badge count
        </span>

        <div className="mx-auto max-w-md py-16 sm:py-24">
          <h1 className="text-balance text-center font-bold text-3xl leading-[1.4] tracking-tight">
            {t("hero.title")}
          </h1>
          <p className="mt-6 text-center text-ink-2 text-sm leading-loose">
            {t("hero.tagline")}
          </p>

          {/* メニューバーの印。数字を出さないという話なので、点ひとつで済ませる */}
          <div className="mt-12 flex justify-center">
            <span className="size-2 rounded-full bg-signal" />
          </div>

          <div className="mt-12 space-y-5">
            <Image
              alt={t("screens.list")}
              className="w-full border border-line"
              height={640}
              priority={true}
              src="/menubar.png"
              width={1120}
            />
            <Image
              alt={t("screens.list")}
              className="w-full border border-line"
              height={530}
              src="/list.png"
              width={960}
            />
          </div>

          <div className="mt-12 flex flex-col items-center gap-3">
            <a
              className="w-full bg-ink px-8 py-3.5 text-center font-bold text-paper text-sm transition hover:bg-indigo"
              href={DOWNLOAD}
            >
              {t("hero.download")}
            </a>
            <a
              className="w-full border border-line px-8 py-3.5 text-center font-bold text-sm transition hover:border-ink"
              href={REPO}
            >
              {t("hero.source")}
            </a>
          </div>
          <p className="mt-5 text-center text-ink-3 text-xs leading-relaxed">
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

          {/* することは4つ。列の中に積んで、罫だけで分ける */}
          <h2 className="mt-24 text-ink-3 text-xs tracking-wider">
            {t("features.title")}
          </h2>
          <dl className="mt-6 border-line border-t">
            {features.map((item) => (
              <div className="border-line border-b py-6" key={item.title}>
                <dt className="font-bold text-base">{item.title}</dt>
                <dd className="mt-2.5 text-ink-2 text-sm leading-relaxed">
                  {item.body}
                </dd>
              </div>
            ))}
          </dl>

          <footer className="mt-16 pb-4 text-center text-ink-3 text-xs">
            <a className="underline" href={REPO}>
              {t("footer.source")}
            </a>
            <span className="px-2">·</span>
            <Link className="underline" href="/privacy">
              {t("footer.privacy")}
            </Link>
          </footer>
        </div>
      </main>
    </>
  );
}
