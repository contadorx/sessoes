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
  paragrafos,
  type Post,
  type PostLink,
} from "@/lib/blog";

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
 */
export function BlogEditor({
  post,
  links,
}: {
  post?: Post;
  links?: PostLink[];
}) {
  const [r, salvar] = useActionState(salvarPost, INICIAL);

  const [titulo, setTitulo] = useState(post?.titulo ?? "");
  const [slug, setSlug] = useState(post?.slug ?? "");
  const [slugTocado, setSlugTocado] = useState(Boolean(post));
  const [corpo, setCorpo] = useState(post?.corpo ?? "");
  const [figura, setFigura] = useState(post?.figura_url ?? "");

  const [lista, setLista] = useState<PostLink[]>(
    links && links.length > 0 ? links : [{ rotulo: "", url: "" }],
  );

  const enderecoLivre = post ? podeTrocarEndereco(post) : true;

  return (
    <form action={salvar}>
      {post && <input type="hidden" name="id" value={post.id} />}

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
              Depois de publicado ele não muda mais — é agora que ele custa
              nada.
            </p>
          </>
        ) : (
          <>
            <input type="hidden" name="slug" value={post!.slug} />
            <p className="mt-1.5 font-mono text-[12.5px] text-tinta2">
              sessoes.com.br/blog/{post!.slug}
            </p>
            <p className="mt-1.5 max-w-[62ch] text-[11.5px] leading-relaxed text-tinta3">
              Congelado: este texto já foi publicado, e o endereço dele está em
              links que outras pessoas guardaram.
            </p>
          </>
        )}
      </div>

      <label className="mt-4 block">
        <span className="rotulo">Resumo</span>
        <input
          name="resumo"
          maxLength={400}
          defaultValue={post?.resumo ?? ""}
          placeholder="a frase que aparece na vitrine"
          className={`mt-1.5 ${CAMPO}`}
        />
      </label>

      {/* ------------------------------------------------------------- o corpo */}
      <label className="mt-5 block">
        <span className="rotulo">O texto</span>
        <textarea
          name="corpo"
          required
          rows={16}
          value={corpo}
          onChange={(e) => setCorpo(e.target.value)}
          className={`mt-1.5 ${CAMPO} font-serif text-[14.5px] leading-relaxed`}
        />
      </label>
      <p className="mt-1.5 max-w-[62ch] text-[11.5px] leading-relaxed text-tinta3">
        Linha em branco separa parágrafo, e é a única formatação que existe. Não
        é limitação de pressa: aceitar marcação aqui é aceitar que um dia entre
        um <code>{"<script>"}</code> numa página que estranhos abrem.{" "}
        {paragrafos(corpo).length > 0 && (
          <b className="font-medium">
            {paragrafos(corpo).length} parágrafo
            {paragrafos(corpo).length > 1 ? "s" : ""}.
          </b>
        )}
      </p>

      {/* ------------------------------------------------------------ a figura */}
      <div className="mt-5 grid gap-3 sm:grid-cols-2">
        <label className="block">
          <span className="rotulo">Figura</span>
          <input
            name="figura_url"
            value={figura}
            onChange={(e) => setFigura(e.target.value)}
            placeholder="/blog/nome-do-arquivo.png"
            className={`mt-1.5 ${CAMPO} font-mono text-[12.5px]`}
          />
        </label>
        <label className="block">
          <span className="rotulo">O que a figura mostra</span>
          <input
            name="figura_alt"
            defaultValue={post?.figura_alt ?? ""}
            placeholder="uma grade de horários com três vazios"
            className={`mt-1.5 ${CAMPO}`}
          />
        </label>
      </div>
      <p className="mt-1.5 max-w-[62ch] text-[11.5px] leading-relaxed text-tinta3">
        Arquivo em <code>public/blog/</code> ou endereço https. A descrição é
        obrigatória quando há figura — sem ela, quem usa leitor de tela recebe
        silêncio no lugar dela.
      </p>

      {/* ------------------------------------------------------------- os links */}
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
          Linha em branco é ignorada, não gravada vazia. O endereço tem de
          começar com https:// ou com / — outros formatos viram código na
          página.
        </p>
      </div>

      <div className="mt-7 border-t border-linha pt-5">
        <Botao>Guardar</Botao>
        <Aviso r={r} />
      </div>
    </form>
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
