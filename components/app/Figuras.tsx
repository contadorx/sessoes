"use client";

import Image from "next/image";
import { useRef, useState } from "react";
import { supabaseNavegador } from "@/lib/supabase/navegador";
import { registrarFigura, apagarFigura } from "@/app/(app)/negocio/blog/acoes";
import {
  problemaNoArquivo,
  caminhoDaFigura,
  tamanhoLegivel,
  type Figura,
} from "@/lib/blog";

/**
 * A biblioteca de figuras — subir, escolher e tirar.
 *
 * A ORDEM DO UPLOAD, E POR QUE ELA É ESSA
 *
 * O arquivo sobe **do navegador direto para o storage**, com a sessão de quem
 * está logado, e só depois um `server action` registra a linha. Passar o arquivo
 * por um `server action` seria mais curto e teria dois problemas: o limite de
 * corpo de requisição (que morde justamente na figura grande) e o arquivo
 * inteiro trafegando duas vezes — do navegador para o servidor, e do servidor
 * para o balde.
 *
 * Errar nessa ordem custa um arquivo órfão no balde, que é barato. A ordem
 * contrária — registrar antes de subir — custaria uma linha apontando para um
 * arquivo que nunca chegou, e isso vira figura quebrada num texto publicado.
 *
 * A ALTERNATIVA VEM ANTES DO ARQUIVO
 *
 * O campo de descrição fica **acima** do seletor e o botão não liga sem ele. É
 * de propósito: pedir a alternativa depois do upload é pedir para uma tela que a
 * pessoa já considera resolvida. O único momento em que ela está de fato olhando
 * para a imagem é agora.
 *
 * O QUE O NAVEGADOR MEDE
 *
 * Largura e altura saem do próprio arquivo, aqui, antes de subir. Sem elas o
 * navegador de quem lê não reserva o espaço e o texto pula quando a imagem
 * carrega. Medir no servidor exigiria uma biblioteca de imagem só para isso;
 * medir aqui é uma linha, e o número é o mesmo.
 */

function medir(arquivo: File): Promise<{ largura: number; altura: number }> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(arquivo);
    const img = new window.Image();
    img.onload = () => {
      URL.revokeObjectURL(url);
      resolve({ largura: img.naturalWidth, altura: img.naturalHeight });
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error("não consegui abrir esta imagem"));
    };
    img.src = url;
  });
}

function sorteio(): string {
  return crypto.randomUUID().replace(/-/g, "").slice(0, 16);
}

export function SubirFigura({
  aoSubir,
  rotulo = "Subir uma figura",
}: {
  aoSubir: (f: Figura) => void;
  /** O que vai acontecer com o arquivo. O botão diz, em vez de só "escolher". */
  rotulo?: string;
}) {
  const [alt, setAlt] = useState("");
  const [ocupado, setOcupado] = useState(false);
  const [erro, setErro] = useState("");
  const [chave, setChave] = useState(0);

  // O `<input type="file">` fica escondido e é disparado por um `<button>` de
  // verdade. Antes ele era um `<input disabled>` dentro de um `<label>` com
  // cara de botão — e `label` de input desabilitado **não clica**: o botão
  // parecia quebrado e não dizia por quê, que é a pior forma de recusar.
  const seletor = useRef<HTMLInputElement>(null);
  const campoAlt = useRef<HTMLInputElement>(null);

  const pronto = alt.trim().length >= 3;

  const clicar = () => {
    if (ocupado) return;
    if (!pronto) {
      // Recusa que ensina: leva o cursor para o campo que falta em vez de
      // simplesmente não responder ao clique.
      setErro("Descreva a figura antes de escolher o arquivo — é o que quem usa leitor de tela vai ouvir no lugar dela.");
      campoAlt.current?.focus();
      return;
    }
    setErro("");
    seletor.current?.click();
  };

  const escolher = async (arquivo: File | undefined) => {
    if (!arquivo) return;
    setErro("");

    const problema = problemaNoArquivo(arquivo);
    if (problema) {
      setErro(problema);
      setChave((k) => k + 1);
      return;
    }

    setOcupado(true);
    try {
      const { largura, altura } = await medir(arquivo);
      const caminho = caminhoDaFigura(arquivo.type, new Date(), sorteio());

      const supabase = supabaseNavegador();
      const { error } = await supabase.storage
        .from("blog")
        .upload(caminho, arquivo, { contentType: arquivo.type, upsert: false });

      if (error) throw new Error(error.message);

      const url = supabase.storage.from("blog").getPublicUrl(caminho).data.publicUrl;

      const r = await registrarFigura({
        caminho,
        url,
        alt: alt.trim(),
        largura,
        altura,
        bytes: arquivo.size,
        tipo: arquivo.type,
      });

      if (r.estado === "erro") throw new Error(r.mensagem);

      aoSubir({
        id: r.id,
        caminho,
        url,
        alt: alt.trim(),
        largura,
        altura,
        bytes: arquivo.size,
        tipo: arquivo.type,
        criado_em: new Date().toISOString(),
        usos: 0,
        usos_no_ar: 0,
      });

      setAlt("");
      setErro("");
    } catch (e) {
      setErro(e instanceof Error ? e.message : "Não consegui subir a figura.");
    } finally {
      setOcupado(false);
      setChave((k) => k + 1);
    }
  };

  return (
    <div className="rounded-cartao border border-linha bg-folha2 px-5 py-4">
      <label className="block">
        <span className="rotulo">O que a figura mostra</span>
        <input
          ref={campoAlt}
          value={alt}
          onChange={(e) => {
            setAlt(e.target.value);
            if (erro) setErro("");
          }}
          maxLength={200}
          placeholder="uma grade de horários com três vazios"
          className="mt-1.5 w-full rounded-[5px] border border-linha2 bg-folha px-3 py-2 text-[13.5px] text-tinta"
        />
      </label>
      <p className="mt-1.5 max-w-[62ch] text-[11.5px] leading-relaxed text-tinta3">
        Escreva antes de escolher o arquivo — é agora que você está olhando para a
        imagem. É o que quem usa leitor de tela ouve no lugar dela, e é como o
        buscador sabe do que ela trata.
      </p>

      <div className="mt-3 flex flex-wrap items-center gap-3">
        <button
          type="button"
          onClick={clicar}
          disabled={ocupado}
          aria-describedby="ajuda-figura"
          className={`rounded-full px-4 py-2 text-[12.5px] font-semibold transition-opacity ${
            pronto && !ocupado
              ? "bg-cheia text-white hover:opacity-90"
              : "border border-linha2 bg-folha text-tinta3"
          }`}
        >
          {ocupado ? "subindo…" : rotulo}
        </button>
        <span id="ajuda-figura" className="text-[11.5px] text-tinta3">
          JPEG, PNG, WebP ou AVIF · até 5 MB
        </span>

        {/* Fora do fluxo, e disparado pelo botão acima. */}
        <input
          key={chave}
          ref={seletor}
          type="file"
          accept="image/jpeg,image/png,image/webp,image/avif"
          onChange={(e) => escolher(e.target.files?.[0])}
          className="hidden"
          tabIndex={-1}
        />
      </div>

      {erro && (
        <p className="mt-2 max-w-[62ch] text-[12px] leading-relaxed text-vaga" role="alert">
          {erro}
        </p>
      )}
    </div>
  );
}

/**
 * A grade da biblioteca.
 *
 * Cada figura mostra **onde está sendo usada**, e o botão de tirar só aparece
 * para quem não está em texto publicado. É a invariante 3 da 0054 chegando à
 * tela na forma certa: não oferecer o que a função vai negar, e dizer o motivo
 * no lugar do botão.
 */
export function Biblioteca({
  figuras,
  aoEscolher,
  aoSumir,
}: {
  figuras: Figura[];
  aoEscolher?: (f: Figura) => void;
  aoSumir?: (id: string) => void;
}) {
  const [erro, setErro] = useState("");

  if (figuras.length === 0) {
    return (
      <p className="mt-3 text-[13px] text-tinta3">
        Nenhuma figura ainda. A primeira que subir aparece aqui e fica disponível
        para qualquer texto.
      </p>
    );
  }

  const tirar = async (id: string) => {
    setErro("");
    const r = await apagarFigura(id);
    if (r.estado === "erro") setErro(r.mensagem);
    else aoSumir?.(id);
  };

  return (
    <div>
      <ul className="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {figuras.map((f) => (
          <li key={f.id} className="overflow-hidden rounded-cartao border border-linha bg-folha">
            <div className="relative aspect-[3/2] bg-folha2">
              <Image
                src={f.url}
                alt={f.alt}
                fill
                sizes="(max-width: 640px) 100vw, 300px"
                className="object-cover"
              />
            </div>
            <div className="px-3 py-2.5">
              <p className="line-clamp-2 text-[12px] leading-snug text-tinta2">{f.alt}</p>
              <p className="mt-1 font-mono text-[11px] text-tinta3">
                {f.largura}×{f.altura} · {tamanhoLegivel(f.bytes)}
              </p>

              <div className="mt-2 flex flex-wrap items-center gap-3">
                {aoEscolher && (
                  <button
                    type="button"
                    onClick={() => aoEscolher(f)}
                    className="rounded-full border border-linha2 px-3 py-1 text-[11.5px] font-medium text-tinta2 hover:bg-folha2"
                  >
                    usar
                  </button>
                )}

                {f.usos_no_ar > 0 ? (
                  <span className="text-[11px] leading-snug text-tinta3">
                    em {f.usos_no_ar} texto{f.usos_no_ar > 1 ? "s" : ""} que já estreou — não sai
                  </span>
                ) : (
                  <button
                    type="button"
                    onClick={() => tirar(f.id)}
                    className="toque text-[11.5px] text-tinta3 underline decoration-linha2 underline-offset-4 hover:text-vaga"
                  >
                    tirar
                  </button>
                )}
              </div>

              {f.usos > f.usos_no_ar && f.usos_no_ar === 0 && (
                <p className="mt-1.5 text-[11px] leading-snug text-tinta3">
                  usada em {f.usos} rascunho{f.usos > 1 ? "s" : ""}
                </p>
              )}
            </div>
          </li>
        ))}
      </ul>
      {erro && <p className="mt-3 text-[12px] leading-relaxed text-vaga">{erro}</p>}
    </div>
  );
}
