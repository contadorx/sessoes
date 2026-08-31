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
 */

const CACHE = "sessoes-estaticos-v1";

self.addEventListener("install", () => {
  // Nada é pré-carregado: o cache se enche sozinho, com o que for pedido.
  self.skipWaiting();
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

  // Navegação, POST, API, outra origem: passa direto. Não tocar é a resposta
  // certa para tudo que pode conter dado de alguém.
  if (req.method !== "GET") return;

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
