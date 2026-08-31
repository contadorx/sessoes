# Sessões

O sistema que faz a agenda da psicóloga não furar mais de graça, e tira dela o
papel de cobradora.

> Sua agenda não fura mais de graça, e você nunca mais precisa cobrar ninguém.

Este repositório começa pela **landing** (build `B-`, anterior à B0 do roadmap).
O produto vem depois, no mesmo projeto Next.js.

## Rodar

```bash
npm install
cp .env.example .env.local   # e preencha com o projeto Supabase
npm run dev
```

Variáveis:

| variável | o que é |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | URL do projeto Supabase |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | chave publicável (`sb_publishable_…`) — é pública por natureza; a segurança vem da RLS |

## Estrutura

```
app/(site)/        a landing pública — page.tsx e as server actions
app/layout.tsx     fontes (Newsreader / Archivo / IBM Plex Mono) e metadata
app/globals.css    tokens da identidade (doc 09), tema claro fixo
components/site/   cascata, simulador de ROI, discrição, lista de espera
lib/db.ts          o helper db() — a lei nº 1
lib/supabase/      cliente server-side
supabase/migrations/  migrations versionadas (nada se aplica fora daqui)
```

A B0 acrescenta `app/(app)/` — a área autenticada — ao lado de `app/(site)/`.

## As leis (doc 05 · cicatrizes do FinanceiroX)

1. **`supabase-js` não lança erro.** Toda operação passa por `db()` de
   `lib/db.ts`, que loga com contexto e lança. O ESLint reprova o import direto
   de `@supabase/supabase-js` fora de `lib/supabase/`.
2. **RLS desde a primeira tabela.** A `interessados` já nasceu com RLS: insert
   público, nenhuma policy de leitura.
3. **Fuso é decisão.** Tudo que é "dia" se calcula em `America/Sao_Paulo`, no
   banco, pela função `hoje_sp()`.
4. **Dinheiro em `numeric`**, nunca float.
5. **Migration é arquivo versionado no repo.** Nada se aplica no Supabase que
   não esteja em `supabase/migrations/`.

## Documentação

O kit de produto (visão, mercado, catálogo de features, roadmap, modelo de
dados, regras de CFP/LGPD, identidade, métricas e riscos) vive no projeto
**Sessões** no Claude — incluindo o `12-roadmap-de-builds.md`, que é o plano de
construção deste repositório.
