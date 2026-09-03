/*
 * O service worker mais tímido possível — e é de propósito.
 *
 * Ele existe por um motivo só: sem um service worker com `fetch`, o navegador
 * não oferece "instalar na tela inicial". Ou seja, é o preço do ícone.
 *
 * E aí vem a decisão que importa: **este arquivo não guarda nada que uma pessoa
 * escreveu.** Nem página, nem resposta de API, nem navegação. Só os arquivos
 * estáticos que o Next publica com hash no nome — JavaScript, CSS, fontes,
 * ícones — que são idênticos para todo mundo e não dizem nada sobre ninguém.
 *
 * O motivo é concreto. O cache do service worker é um banco de dados no
 * aparelho, que sobrevive ao logout e não é apagado quando a sessão termina.
 * Guardar ali a tela de um paciente seria deixar prontuário no celular de quem
 * usou o app naquele navegador — inclusive num computador emprestado da clínica.
 * O "modo offline" que isso compraria não vale esse preço, e o doc 07 chama isso
 * pelo nome: acesso restrito, o armário chaveado.
 *
 * Então: se a requisição não for um GET de arquivo estático da mesma origem, o
 * service worker não faz nada — deixa a rede responder, como se ele não
 * existisse.
 *
 * ------------------------------------------------------------------ a exceção
 *
 * Há **uma** página no cache, e ela é vazia: `/offline`.
 *
 * Instalada na tela inicial, a PWA não tem barra de endereço. Ficar sem sinal
 * entregava a tela de erro do navegador dentro de uma janela sem recarregar,
 * sem voltar e sem sair — o único caminho era fechar o aplicativo. A tela de
 * sem conexão devolve o botão.
 *
 * O que **não** muda: nenhuma navegação é guardada. A resposta da rede passa
 * intacta e nada dela entra no cache; a página vazia só é servida quando o
 * `fetch` falha, que é a definição de estar sem rede. Cachear a agenda seria
 * deixar prontuário no aparelho, e continua fora de questão.
 */

// v2: a versão muda porque o `install` agora pré-carrega uma página. Sem
// trocar o nome, o cache antigo sobrevive ao `activate` e a `/offline` nunca
// entra nele.
const CACHE = "sessoes-estaticos-v2";

const SEM_CONEXAO = "/offline";

self.addEventListener("install", (evento) => {
  // O resto do cache continua se enchendo sozinho, com o que for pedido. Só a
  // tela de sem conexão é pré-carregada: ela precisa estar lá **antes** de
  // fazer falta, e a hora em que faz falta é a hora em que não dá para buscar.
  evento.waitUntil(
    (async () => {
      try {
        const cache = await caches.open(CACHE);
        await cache.add(new Request(SEM_CONEXAO, { cache: "reload" }));
      } catch {
        // Falhou o pré-carregamento: o service worker instala do mesmo jeito.
        // Sem a página, a navegação offline volta a ser a tela do navegador —
        // que é ruim, mas é o que já era. Derrubar a instalação por causa dela
        // custaria o cache de estáticos inteiro.
      }
      await self.skipWaiting();
    })(),
  );
});

self.addEventListener("activate", (evento) => {
  evento.waitUntil(
    (async () => {
      // Versão nova, cache velho fora. Sem isto, um deploy deixaria o aparelho
      // servindo o JavaScript da semana passada por tempo indeterminado.
      const nomes = await caches.keys();
      await Promise.all(nomes.filter((n) => n !== CACHE).map((n) => caches.delete(n)));
      await self.clients.claim();
    })(),
  );
});

function ehEstatico(url) {
  if (url.origin !== self.location.origin) return false;
  if (url.pathname.startsWith("/api/")) return false;
  return (
    url.pathname.startsWith("/_next/static/") ||
    /\.(png|svg|ico|webmanifest|woff2?)$/.test(url.pathname)
  );
}

self.addEventListener("fetch", (evento) => {
  const req = evento.request;

  // POST, API, outra origem: passa direto. Não tocar é a resposta certa para
  // tudo que pode conter dado de alguém.
  if (req.method !== "GET") return;

  // Navegação: a rede responde, sempre, e a resposta **não** é guardada. O
  // service worker só entra quando o `fetch` levanta — sem rede — e aí entrega
  // a página vazia no lugar da tela de erro do navegador.
  if (req.mode === "navigate") {
    evento.respondWith(
      (async () => {
        try {
          return await fetch(req);
        } catch (erro) {
          const guardada = await caches.match(SEM_CONEXAO);
          if (guardada) return guardada;
          // Sem a página no cache não há o que servir: devolve o erro
          // original, que é o comportamento de antes desta build.
          throw erro;
        }
      })(),
    );
    return;
  }

  const url = new URL(req.url);
  if (!ehEstatico(url)) return;

  evento.respondWith(
    (async () => {
      const guardado = await caches.match(req);
      if (guardado) return guardado;

      const resposta = await fetch(req);
      // Só resposta boa e da mesma origem entra no cache.
      if (resposta.ok && resposta.type === "basic") {
        const cache = await caches.open(CACHE);
        cache.put(req, resposta.clone());
      }
      return resposta;
    })(),
  );
});
