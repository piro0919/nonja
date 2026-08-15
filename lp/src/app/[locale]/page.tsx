import Image from "next/image";
import { getTranslations, setRequestLocale } from "next-intl/server";
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
  const steps = t.raw("install.steps") as Item[];

  return (
    <>
      {/* 見出し。文章より先に、動いている実物を見せる */}
      <header className="brand px-6 pt-8 pb-0 text-white">
        <div className="mx-auto flex max-w-5xl items-center justify-between">
          <div className="flex items-center gap-3">
            <Image alt="" className="rounded-[24%]" height={32} src="/icon.png" width={32} />
            <span className="font-bold text-lg tracking-tight">Nonja</span>
          </div>
          <LanguageSwitch />
        </div>

        <div className="mx-auto mt-14 max-w-3xl text-center">
          <h1 className="font-bold text-4xl leading-tight tracking-tight sm:text-5xl">
            {t("hero.title")}
          </h1>
          <p className="mt-5 text-lg text-white/85 leading-relaxed">{t("hero.tagline")}</p>

          <div className="mt-9 flex flex-wrap items-center justify-center gap-4">
            <a
              className="rounded-full bg-white px-8 py-3.5 font-bold text-navy-deep transition hover:bg-white/90"
              href={DOWNLOAD}
            >
              {t("hero.download")}
            </a>
            <a
              className="rounded-full border border-white/50 px-8 py-3.5 font-bold transition hover:bg-white/10"
              href={REPO}
            >
              {t("hero.source")}
            </a>
          </div>
          <p className="mt-4 text-sm text-white/60">{t("hero.note")}</p>
        </div>

        {/* メニューバーの印と、その真下に開く窓。位置の関係ごと見せる */}
        <div className="mx-auto mt-14 max-w-4xl">
          <Image
            alt={t("screens.list")}
            className="w-full translate-y-px rounded-t-2xl"
            height={470}
            priority={true}
            src="/hero.png"
            width={820}
          />
        </div>
      </header>

      {/* することは4つ。枠で囲まず、赤い罫だけで区切る */}
      <section className="px-6 py-20">
        <div className="mx-auto grid max-w-5xl gap-x-12 gap-y-10 sm:grid-cols-2">
          {features.map((item) => (
            <div className="border-signal border-l-2 pl-5" key={item.title}>
              <h2 className="font-bold text-xl">{item.title}</h2>
              <p className="mt-3 text-ink/70 leading-relaxed">{item.body}</p>
            </div>
          ))}
        </div>
      </section>

      {/* 入れ方。自己署名なので初回だけ手間がかかる。隠さずに書く */}
      <div className="dot-bg">
        <section className="px-6 py-20" id="install">
          <div className="mx-auto max-w-5xl">
            <h2 className="font-bold text-3xl tracking-tight sm:text-4xl">{t("install.title")}</h2>
            <ol className="mt-10 grid gap-5 sm:grid-cols-3">
              {steps.map((step, index) => (
                <li className="rounded-2xl border border-line bg-white p-6" key={step.title}>
                  <span className="font-bold text-signal text-sm">{index + 1}</span>
                  <h3 className="mt-2 font-bold text-lg">{step.title}</h3>
                  <p className="mt-3 text-ink/70 leading-relaxed">{step.body}</p>
                </li>
              ))}
            </ol>
            <a
              className="mt-10 inline-block rounded-full bg-navy-deep px-8 py-3.5 font-bold text-white transition hover:opacity-90"
              href={DOWNLOAD}
            >
              {t("hero.download")}
            </a>
          </div>
        </section>
      </div>

      <footer className="border-line border-t px-6 py-10 text-center text-ink/60 text-sm">
        <p>{t("footer.built")}</p>
        <a className="mt-2 inline-block underline" href={REPO}>
          {t("footer.source")}
        </a>
      </footer>
    </>
  );
}
