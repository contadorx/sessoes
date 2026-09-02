"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import {
  salvarPost,
  publicarPost,
  despublicarPost,
  apagarPost,
  type Resultado,
} from "@/app/(app)/negocio/blog/acoes";
import {
  slugDe,
  estadoDoPost,
  explicaEstado,
  podeApagar,
  podeTrocarEndereco,
  porQueNaoApaga,
  type Post,
  type PostLink,
  type Figura,
} from "@/lib/blog";
import { Marcador } from "@/components/app/Marcador";
import { SubirFigura, Biblioteca } from "@/components/app/Figuras";
import { ConferenciaSeo } from "@/components/app/ConferenciaSeo";

const INICIAL: Resultado = { estado: "ok", mensagem: "" };

const CAMPO =
  "w-full rounded-[5px] border border-linha2 bg-folha px-3 py-2 text-[13.5px] text-tinta";

function Botao({ children, perigo = false }: { children: React.ReactNode; perigo?: boolean }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className={`rounded-full px-4 py-2 text-[12.5px] font-medium transition-opacity disabled:opacity-45 ${
        perigo
          ? "border border-vaga-linha text-vaga hover:bg-vaga-bg"
          : "border border-linha2 text-tinta2 hover:bg-folha2"
      }`}
    >
      {pending ? "…" : children}
    </button>
  );
}

function Aviso({ r }: { r: Resultado }) {
  if (!r.mensagem) return null;
  return (
    <p
      className={`mt-2 text-[12px] leading-relaxed ${
        r.estado === "erro" ? "text-vaga" : "text-cheia"
      }`}
    >
      {r.mensagem}
    </p>
  );
}

/**
 * O editor de um texto.
 *
 * **O endereço é sugerido e depois deixado em paz.** Ele nasce do título
 * enquanto ninguém o tocou; no instante em que a pessoa digita nele, o
 * automatismo desliga para sempre naquela sessão. Um campo que se reescreve
 * sozinho depois de editado é o tipo de coisa que se descobre tarde — quando o
 * endereço publicado não é o que se escreveu.
 *
 * **E ele some quando o texto já foi publicado**, com a frase explicando por
 * quê. É a invariante 2 da 0051 chegando à tela na forma certa: não oferecer o
 * que a função vai negar, e dizer o motivo no lugar do campo.
 *
 * A 0054 acrescentou três coisas, e cada uma segue a mesma regra:
 *
 *   · **a barra de marcação** só aparece para texto em formato `marcacao` —
 *     num texto antigo ela ofereceria uma formatação que não vai acontecer;
 *   · **a figura vem da biblioteca**, com as medidas do arquivo, e não de um
 *     campo de texto onde se digita um caminho que pode não existir;
 *   · **a conferência** fica ao lado, viva, mudando enquanto se escreve — não
 *     numa tela separada que se visita uma vez.
 */
export function BlogEditor({
  post,
  links,
  figuras,
}: {
  post?: Post;
  links?: PostLink[];
  figuras: Figura[];
}) {
  const [r, salvar] = useActionState(salvarPost, INICIAL);

  const [titulo, setTitulo] = useState(post?.titulo ?? "");
  const [slug, setSlug] = useState(post?.slug ?? "");
  const [slugTocado, setSlugTocado] = useState(Boolean(post));
  const [resumo, setResumo] = useState(post?.resumo ?? "");
  const [corpo, setCorpo] = useState(post?.corpo ?? "");
  const [canonica, setCanonica] = useState(post?.canonica ?? "");
  const [indexavel, setIndexavel] = useState(post?.indexavel ?? true);

  const [capa, setCapa] = useState({
    url: post?.figura_url ?? "",
    alt: post?.figura_alt ?? "",
    largura: post?.figura_largura ?? null as number | null,
    altura: post?.figura_altura ?? null as number | null,
  });

  const [acervo, setAcervo] = useState<Figura[]>(figuras);
  const [escolhendo, setEscolhendo] = useState<"capa" | "corpo" | null>(null);

  const [lista, setLista] = useState<PostLink[]>(
    links && links.length > 0 ? links : [{ rotulo: "", url: "" }],
  );

  const enderecoLivre = post ? podeTrocarEndereco(post) : true;
  const formato = post?.formato ?? "marcacao";

  const usar = (f: Figura) => {
    if (escolhendo === "capa") {
      setCapa({ url: f.url, alt: f.alt, largura: f.largura, altura: f.altura });
    } else if (escolhendo === "corpo") {
      // Entra como bloco próprio, com a alternativa já preenchida a partir do
      // cadastro. Colar só o endereço deixaria a alternativa vazia por padrão —
      // e o padrão é o que sobrevive.
      const marca = `![${f.alt}](${f.url})`;
      setCorpo(corpo.trimEnd() === "" ? marca : `${corpo.trimEnd()}\n\n${marca}\n`);
    }
    setEscolhendo(null);
  };

  return (
    <div className="grid gap-8 lg:grid-cols-[minmax(0,1fr)_20rem] lg:items-start">
      <form action={salvar}>
        {post && <input type="hidden" name="id" value={post.id} />}

        {/* O formato só viaja para rascunho — ver o comentário em `acoes.ts`. */}
        {enderecoLivre && <input type="hidden" name="formato" value={formato} />}

        <label className="block">
          <span className="rotulo">Título</span>
          <input
            name="titulo"
            required
            value={titulo}
            onChange={(e) => {
              setTitulo(e.target.value);
              if (!slugTocado) setSlug(slugDe(e.target.value));
            }}
            className={`mt-1.5 ${CAMPO}`}
          />
        </label>

        <div className="mt-4">
          <span className="rotulo">Endereço</span>
          {enderecoLivre ? (
            <>
              <div className="mt-1.5 flex items-center gap-1.5">
                <span className="font-mono text-[12.5px] text-tinta3">sessoes.com.br/blog/</span>
                <input
                  name="slug"
                  required
                  value={slug}
                  onChange={(e) => {
                    setSlugTocado(true);
                    setSlug(e.target.value);
                  }}
                  className={`${CAMPO} font-mono`}
                />
              </div>
              <p className="mt-1.5 text-[11.5px] leading-relaxed text-tinta3">
                Depois de publicado ele não muda mais — é agora que ele custa nada.
              </p>
            </>
          ) : (
            <>
              <input type="hidden" name="slug" value={post!.slug} />
              <p className="mt-1.5 font-mono text-[12.5px] text-tinta2">
                sessoes.com.br/blog/{post!.slug}
              </p>
              <p className="mt-1.5 max-w-[62ch] text-[11.5px] leading-relaxed text-tinta3">
                Congelado: este texto já foi publicado, e o endereço dele está em links
                que outras pessoas guardaram.
              </p>
            </>
          )}
        </div>

        <label className="mt-4 block">
          <span className="rotulo">Resumo</span>
          <textarea
            name="resumo"
            rows={2}
            maxLength={400}
            value={resumo}
            onChange={(e) => setResumo(e.target.value)}
            placeholder="a frase que aparece na vitrine e no resultado da busca"
            className={`mt-1.5 ${CAMPO} leading-relaxed`}
          />
        </label>
        <p className="mt-1.5 max-w-[62ch] text-[11.5px] leading-relaxed text-tinta3">
          É o que o buscador mostra embaixo do título quando prefere a sua frase à
          dele. Sem resumo, ele monta o trecho com um pedaço qualquer do texto.
        </p>

        {/* ----------------------------------------------------------- o corpo */}
        <div className="mt-6">
          <Marcador
            nome="corpo"
            valor={corpo}
            aoMudar={setCorpo}
            formato={formato}
            aoInserirFigura={() => setEscolhendo("corpo")}
          />
        </div>

        {/* ----------------------------------------------------------- a capa */}
        <div className="mt-6">
          <span className="rotulo">Figura de capa</span>
          <input type="hidden" name="figura_url" value={capa.url} />
          <input type="hidden" name="figura_alt" value={capa.alt} />
          <input type="hidden" name="figura_largura" value={capa.largura ?? ""} />
          <input type="hidden" name="figura_altura" value={capa.altura ?? ""} />

          {capa.url === "" ? (
            <div className="mt-2">
              <button
                type="button"
                onClick={() => setEscolhendo("capa")}
                className="rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 hover:bg-folha2"
              >
                Escolher da biblioteca
              </button>
              <p className="mt-2 max-w-[62ch] text-[11.5px] leading-relaxed text-tinta3">
                É a imagem que aparece quando alguém manda o link no WhatsApp. Sem ela,
                o texto compartilhado vira uma linha de link.
              </p>
            </div>
          ) : (
            <div className="mt-2 flex flex-wrap items-start gap-4 rounded-cartao border border-linha bg-folha2 px-4 py-3">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={capa.url}
                alt={capa.alt}
                className="h-20 w-32 rounded border border-linha object-cover"
              />
              <div className="min-w-[12rem] flex-1">
                <p className="text-[12.5px] leading-snug text-tinta2">{capa.alt}</p>
                <p className="mt-1 font-mono text-[11px] text-tinta3">
                  {capa.largura && capa.altura
                    ? `${capa.largura}×${capa.altura}`
                    : "sem medidas — o texto vai pular quando ela carregar"}
                </p>
                <div className="mt-2 flex gap-3">
                  <button
                    type="button"
                    onClick={() => setEscolhendo("capa")}
                    className="text-[11.5px] text-tinta3 underline decoration-linha2 underline-offset-4 hover:text-vaga"
                  >
                    trocar
                  </button>
                  <button
                    type="button"
                    onClick={() => setCapa({ url: "", alt: "", largura: null, altura: null })}
                    className="text-[11.5px] text-tinta3 underline decoration-linha2 underline-offset-4 hover:text-vaga"
                  >
                    tirar
                  </button>
                </div>
              </div>
            </div>
          )}
        </div>

        {/* ---------------------------------------------------------- os links */}
        <div className="mt-6">
          <span className="rotulo">Links do texto</span>
          <div className="mt-2 flex flex-col gap-2">
            {lista.map((l, i) => (
              <div key={i} className="flex flex-wrap gap-2">
                <input
                  name="link_rotulo"
                  value={l.rotulo}
                  onChange={(e) => {
                    const c = [...lista];
                    c[i] = { ...c[i], rotulo: e.target.value };
                    setLista(c);
                  }}
                  placeholder="o que se lê"
                  className={`${CAMPO} sm:w-[16rem] sm:flex-none`}
                />
                <input
                  name="link_url"
                  value={l.url}
                  onChange={(e) => {
                    const c = [...lista];
                    c[i] = { ...c[i], url: e.target.value };
                    setLista(c);
                  }}
                  placeholder="https://…"
                  className={`${CAMPO} font-mono text-[12.5px] sm:flex-1`}
                />
              </div>
            ))}
          </div>
          <button
            type="button"
            onClick={() => setLista([...lista, { rotulo: "", url: "" }])}
            className="mt-2 text-[12px] text-tinta3 underline decoration-linha2 underline-offset-4 hover:text-vaga"
          >
            mais um link
          </button>
          <p className="mt-2 max-w-[62ch] text-[11.5px] leading-relaxed text-tinta3">
            Linha em branco é ignorada, não gravada vazia. O endereço tem de começar
            com https:// ou com / — outros formatos viram código na página.
          </p>
        </div>

        {/* --------------------------------------------- o que os buscadores leem */}
        <details className="mt-6 rounded-cartao border border-linha bg-folha2 px-5 py-3">
          <summary className="cursor-pointer text-[12.5px] font-medium text-tinta2">
            Quando este texto saiu antes em outro lugar
          </summary>

          <label className="mt-3 block">
            <span className="rotulo">Endereço original</span>
            <input
              name="canonica"
              value={canonica}
              onChange={(e) => setCanonica(e.target.value)}
              placeholder="https://…"
              className={`mt-1.5 ${CAMPO} font-mono text-[12.5px]`}
            />
          </label>
          <p className="mt-1.5 max-w-[62ch] text-[11.5px] leading-relaxed text-tinta3">
            Preencha só se este texto foi publicado primeiro em outro site. Ele sai do
            sitemap: sitemap é a lista dos originais.
          </p>

          <label className="mt-4 flex items-start gap-2.5">
            <input
              type="checkbox"
              name="indexavel"
              value="1"
              checked={indexavel}
              onChange={(e) => setIndexavel(e.target.checked)}
              className="mt-0.5"
            />
            <span className="text-[12.5px] leading-relaxed text-tinta">
              Pedir aos buscadores para indexar
              <span className="mt-0.5 block text-[12px] text-tinta2">
                Desmarcado, o texto continua público e legível para quem tem o link —
                não indexar não é esconder.
              </span>
            </span>
          </label>
        </details>

        <div className="mt-7 border-t border-linha pt-5">
          <Botao>Guardar</Botao>
          <Aviso r={r} />
        </div>
      </form>

      {/* ------------------------------------------------------------- a coluna */}
      <div className="flex flex-col gap-5 lg:sticky lg:top-6">
        <ConferenciaSeo
          post={{
            titulo,
            slug,
            resumo,
            corpo,
            formato,
            figura_url: capa.url,
            figura_alt: capa.alt,
            figura_largura: capa.largura,
            figura_altura: capa.altura,
            canonica,
            indexavel,
          }}
        />
      </div>

      {/* ---------------------------------------------------------- a biblioteca */}
      {escolhendo !== null && (
        <div className="lg:col-span-2">
          <div className="rounded-cartao border border-linha bg-folha px-5 py-4">
            <div className="flex flex-wrap items-baseline gap-3">
              <h2 className="rotulo">
                {escolhendo === "capa" ? "Escolher a capa" : "Escolher a figura do texto"}
              </h2>
              <button
                type="button"
                onClick={() => setEscolhendo(null)}
                className="ml-auto text-[12px] text-tinta3 underline decoration-linha2 underline-offset-4 hover:text-vaga"
              >
                deixa
              </button>
            </div>

            <div className="mt-3">
              <SubirFigura aoSubir={(f) => setAcervo([f, ...acervo])} />
            </div>

            <Biblioteca
              figuras={acervo}
              aoEscolher={usar}
              aoSumir={(id) => setAcervo(acervo.filter((f) => f.id !== id))}
            />
          </div>
        </div>
      )}
    </div>
  );
}

/**
 * As ações que mudam o estado — separadas do formulário de propósito.
 *
 * Se "publicar" fosse um botão do mesmo `form`, o texto iria ao ar com o que
 * está no banco, e não com o que está na tela: a pessoa editaria, clicaria em
 * publicar e publicaria a versão anterior. Formulários separados tornam a
 * ordem visível — guardar primeiro, publicar depois.
 */
export function AcoesDoPost({ post }: { post: Post }) {
  const [rp, publicar] = useActionState(publicarPost, INICIAL);
  const [rd, despublicar] = useActionState(despublicarPost, INICIAL);
  const [ra, apagar] = useActionState(apagarPost, INICIAL);
  const [confirmando, setConfirmando] = useState(false);

  const e = estadoDoPost(post);

  return (
    <div className="rounded-cartao border border-linha bg-folha2 px-5 py-4">
      <p className="text-[13px] text-tinta">
        <b className="font-medium">
          {e === "no_ar" ? "No ar" : e === "rascunho" ? "Rascunho" : "Fora do ar"}
        </b>
      </p>
      <p className="mt-1 max-w-[58ch] text-[12px] leading-relaxed text-tinta3">
        {explicaEstado(e)}
      </p>

      <div className="mt-4 flex flex-wrap items-center gap-3">
        {e !== "no_ar" && (
          <form action={publicar}>
            <input type="hidden" name="id" value={post.id} />
            <Botao>{e === "rascunho" ? "Publicar" : "Pôr de volta no ar"}</Botao>
          </form>
        )}

        {e === "no_ar" && (
          <form action={despublicar}>
            <input type="hidden" name="id" value={post.id} />
            <Botao>Tirar do ar</Botao>
          </form>
        )}

        {podeApagar(post) &&
          (confirmando ? (
            <form action={apagar} className="flex items-center gap-2">
              <input type="hidden" name="id" value={post.id} />
              <Botao perigo>Apagar mesmo</Botao>
              <button
                type="button"
                onClick={() => setConfirmando(false)}
                className="text-[12px] text-tinta3 hover:text-tinta2"
              >
                deixa
              </button>
            </form>
          ) : (
            <button
              type="button"
              onClick={() => setConfirmando(true)}
              className="text-[12px] text-tinta3 underline decoration-linha2 underline-offset-4 hover:text-vaga"
            >
              apagar
            </button>
          ))}
      </div>

      {!podeApagar(post) && (
        <p className="mt-3 max-w-[58ch] text-[11.5px] leading-relaxed text-tinta3">
          {porQueNaoApaga()}
        </p>
      )}

      <Aviso r={rp.mensagem ? rp : rd.mensagem ? rd : ra} />
    </div>
  );
}
